// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20}          from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}       from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable}   from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/* ---------- 外部接口 ---------- */
interface IWNATIVE is IERC20 { function deposit() external payable; function withdraw(uint256) external; }
interface IDealPairLike { function mintOtherOnly() external returns (uint256 amountOther); }
interface IDealFactoryLike { function getPair(address token) external view returns (address); }

/**
 * @title DealABTemplateV5
 * @notice A/B 双方模板合约（仅 operator 驱动）：
 *  - setLegs 一次设定 A/B swap/stake；pair 由 factory.getPair(normalize(token)) 决定
 *  - confirm：用“≥”判定，首付看余额，次付看(余额-对方应付)；两项为0直接通过；次付成功即锁定
 *  - withdraw：仅允许“已付的一方在对方未付时”撤回（第一支付者可提）；按设定金额原样打回，多余忽略
 *  - 完成：仅对 swap 收费（DL/special 免）；优先入 pair；否则打 treasury
 */
contract DealABTemplateV5 is Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ===== 常量 / 枚举 ===== */
    address public constant NATIVE = address(0);
    enum Status { Ready, Abandoned, Locked, Completed, Cancelled }
    enum Vote   { Default, Accept, Reject }

    /* ===== 固化配置（初始化即定） ===== */
    string  public title;
    address public operator;
    address public factory;
    address public dl;
    address public WNATIVE;
    address public treasury;
    uint16  public feePermille;          // <=1000
    address public specialNoFeeToken;    // 规范化后比较
    uint64  public voteTimeout;          // >0

    /* ===== 参与者 / 腿 ===== */
    address public partyA;
    address public partyB;

    struct Leg {
        address swapToken;  uint256 swapAmount;   // 置换（计费）
        address stakeToken; uint256 stakeAmount;  // 保证金（不计费）
    }
    Leg public a;
    Leg public b;

    // 规范化 OTHER 与 Pair（随 setLegs 决定，仅用于手续费入池）
    address public aTokenNorm;  address public aPair;
    address public bTokenNorm;  address public bPair;

    /* ===== 状态 / 投票 ===== */
    Status public status;   // Ready -> Locked -> Completed/Cancelled，Abandoned 不可逆
    bool   public apaid;
    bool   public bpaid;
    Vote   public voteA;
    Vote   public voteB;
    uint64 public voteStart;

    /* ===== 事件 ===== */
    event Initialized(string title, address operator, address factory);
    event PartyASet(address a);
    event PartyBSet(address b);
    event LegsSet(
        address aSwap, uint256 aSwapAmt, address aStake, uint256 aStakeAmt,
        address bSwap, uint256 bSwapAmt, address bStake, uint256 bStakeAmt,
        address aTokenNorm, address aPair, address bTokenNorm, address bPair
    );
    event PaidConfirmed(bool isA);
    event Locked(uint64 voteStart, uint64 voteTimeout);
    event Voted(bool isA, Vote v);
    event ForcedExecute(bool completed);
    event Completed(uint256 when);
    event Cancelled(uint256 when);
    event Abandoned();
    event FeesInjected(address token, uint256 fee, bytes32 route, address endpoint, uint256 mintedOther);
    event Payout(address indexed to, address token, uint256 amount);

    /* ===== 修饰符 ===== */
    modifier onlyOperator() { require(msg.sender == operator, "ONLY_OPERATOR"); _; }
    modifier inStatus(Status s){ require(status == s, "BAD_STATUS"); _; }

    /* ===== 初始化 ===== */
    struct StaticConfig {
        string  title;
        address operator;
        address factory;
        address dl;
        address WNATIVE;
        address treasury;
        uint16  feePermille;           // <=1000
        address specialNoFeeToken;     // 可为0
        uint64  voteTimeoutSeconds;    // >0
    }
    function initialize(StaticConfig calldata c) external initializer {
        require(bytes(c.title).length > 0, "title");
        require(c.operator != address(0), "operator=0");
        require(c.factory  != address(0), "factory=0");
        require(c.WNATIVE  != address(0), "WNATIVE=0");
        require(c.voteTimeoutSeconds > 0, "timeout=0");
        require(c.feePermille <= 1000, "fee>1000");

        title              = c.title;
        operator           = c.operator;
        factory            = c.factory;
        dl                 = c.dl;
        WNATIVE            = c.WNATIVE;
        treasury           = c.treasury;
        feePermille        = c.feePermille;
        specialNoFeeToken  = c.specialNoFeeToken;
        voteTimeout        = c.voteTimeoutSeconds;

        status = Status.Ready;
        emit Initialized(title, operator, factory);
    }

    /* ===== Ready：分设参与者 ===== */
    function setPartyA(address _a) external onlyOperator inStatus(Status.Ready) {
        require(!apaid || _a != address(0), "A paid");
        partyA = _a; emit PartyASet(_a);
    }
    function setPartyB(address _b) external onlyOperator inStatus(Status.Ready) {
        require(!bpaid || _b != address(0), "B paid");
        partyB = _b; emit PartyBSet(_b);
    }

    /* ===== Ready：一次设定 A/B 的 swap+stake；Pair 由工厂解析 ===== */
    function setLegs(
        address aSwap,  uint256 aSwapAmt,
        address aStake, uint256 aStakeAmt,
        address bSwap,  uint256 bSwapAmt,
        address bStake, uint256 bStakeAmt
    ) external onlyOperator inStatus(Status.Ready) {
        require(!apaid && !bpaid, "paid!=0");

        a.swapToken=aSwap; a.swapAmount=aSwapAmt; a.stakeToken=aStake; a.stakeAmount=aStakeAmt;
        b.swapToken=bSwap; b.swapAmount=bSwapAmt; b.stakeToken=bStake; b.stakeAmount=bStakeAmt;

        aTokenNorm = (aSwap == NATIVE) ? WNATIVE : aSwap;
        bTokenNorm = (bSwap == NATIVE) ? WNATIVE : bSwap;

        aPair = (a.swapAmount > 0 && aTokenNorm != address(0)) ? IDealFactoryLike(factory).getPair(aTokenNorm) : address(0);
        bPair = (b.swapAmount > 0 && bTokenNorm != address(0)) ? IDealFactoryLike(factory).getPair(bTokenNorm) : address(0);

        emit LegsSet(aSwap,aSwapAmt,aStake,aStakeAmt,bSwap,bSwapAmt,bStake,bStakeAmt,aTokenNorm,aPair,bTokenNorm,bPair);
    }

    /* ===== 工具：余额/需求 ===== */
    function _bal(address token) internal view returns (uint256) {
        return token == NATIVE ? address(this).balance : IERC20(token).balanceOf(address(this));
    }
    function _needOn(Leg memory L, address token) internal pure returns (uint256 s) {
        if (L.swapAmount  > 0 && L.swapToken  == token) s += L.swapAmount;
        if (L.stakeAmount > 0 && L.stakeToken == token) s += L.stakeAmount;
    }
    function _uniq2(Leg memory L) internal pure returns (address t1, address t2) {
        t1 = (L.swapAmount  > 0) ? L.swapToken  : address(0);
        t2 = (L.stakeAmount > 0 && L.stakeToken != t1) ? L.stakeToken : address(0);
    }

    /* ===== Ready：确认（≥ 版本；首付 vs 次付） =====
       规则：
       - 对方未 paid（我是首付）：balance(token)               ≥ 我需
       - 对方已 paid（我是次付）：balance(token) − 对方应付(token) ≥ 我需
       - 两项都为 0：直接通过
    */
    function confirmAPaid() external onlyOperator inStatus(Status.Ready) {
        require(partyA != address(0), "A=0");
        require(!apaid, "A_PAID");

        if (a.swapAmount == 0 && a.stakeAmount == 0) {
            apaid = true; emit PaidConfirmed(true); _maybeLock(); return;
        }
        _confirmSideGE(true); // ≥ 判定
        apaid = true; emit PaidConfirmed(true); _maybeLock();
    }
    function confirmBPaid() external onlyOperator inStatus(Status.Ready) {
        require(partyB != address(0), "B=0");
        require(!bpaid, "B_PAID");

        if (b.swapAmount == 0 && b.stakeAmount == 0) {
            bpaid = true; emit PaidConfirmed(false); _maybeLock(); return;
        }
        _confirmSideGE(false);
        bpaid = true; emit PaidConfirmed(false); _maybeLock();
    }

    function _confirmSideGE(bool isA) internal view {
        Leg memory L = isA ? a : b;
        Leg memory O = isA ? b : a;
        bool otherPaid = isA ? bpaid : apaid;

        (address t1, address t2) = _uniq2(L);
        if (t1 != address(0)) {
            uint256 need = _needOn(L, t1);
            uint256 bal  = _bal(t1);
            uint256 sub  = otherPaid ? _needOn(O, t1) : 0;
            require(bal >= need + sub, "GE t1 fail");
        }
        if (t2 != address(0)) {
            uint256 need = _needOn(L, t2);
            uint256 bal  = _bal(t2);
            uint256 sub  = otherPaid ? _needOn(O, t2) : 0;
            require(bal >= need + sub, "GE t2 fail");
        }
    }

    function _maybeLock() internal {
        if (apaid && bpaid) {
            status = Status.Locked;
            voteA = Vote.Default; voteB = Vote.Default;
            voteStart = uint64(block.timestamp);
            emit Locked(voteStart, voteTimeout);
        }
    }

    /* ===== Ready：提现（第一支付者可提；对方未付） =====
       - 仅允许：A 已付且 B 未付（A 可提），或 B 已付且 A 未付（B 可提）
       - 校验：balance(token) ≥ 该方应付；按设定金额原样打回，多余忽略
       - 提现后将该方 paid=false
    */
    function withdrawForA() external onlyOperator inStatus(Status.Ready) nonReentrant {
        require(apaid && !bpaid, "A not sole payer");
        _withdrawSide(a, partyA);
        apaid = false;
    }
    function withdrawForB() external onlyOperator inStatus(Status.Ready) nonReentrant {
        require(bpaid && !apaid, "B not sole payer");
        _withdrawSide(b, partyB);
        bpaid = false;
    }
    function _withdrawSide(Leg memory L, address to) internal {
        (address t1, address t2) = _uniq2(L);
        if (t1 != address(0)) { uint256 need = _needOn(L, t1); require(_bal(t1) >= need, "bal<t1"); _out(t1, to, need); }
        if (t2 != address(0)) { uint256 need = _needOn(L, t2); require(_bal(t2) >= need, "bal<t2"); _out(t2, to, need); }
    }

    /* ===== Ready：未付款可废弃 ===== */
    function abandon() external onlyOperator inStatus(Status.Ready) {
        require(!apaid && !bpaid, "HAS_PAID");
        status = Status.Abandoned;
        emit Abandoned();
    }

    /* ===== Locked：投票 / 超时 ===== */
    function voteForA(Vote v) external onlyOperator inStatus(Status.Locked) {
        require(v != Vote.Default, "VOTE_DEFAULT");
        require(voteA == Vote.Default, "A_VOTED");
        voteA = v; emit Voted(true, v); _progress();
    }
    function voteForB(Vote v) external onlyOperator inStatus(Status.Locked) {
        require(v != Vote.Default, "VOTE_DEFAULT");
        require(voteB == Vote.Default, "B_VOTED");
        voteB = v; emit Voted(false, v); _progress();
    }
    function _progress() internal {
        if (voteA == Vote.Reject || voteB == Vote.Reject) _cancel();
        else if (voteA == Vote.Accept && voteB == Vote.Accept) _complete();
    }
    function forceExecuteOnTimeout() external onlyOperator inStatus(Status.Locked) {
        require(block.timestamp >= uint256(voteStart) + uint256(voteTimeout), "NOT_TIMEOUT");
        bool ok = !(voteA == Vote.Reject || voteB == Vote.Reject);
        if (ok) _complete(); else _cancel();
        emit ForcedExecute(ok);
    }

    /* ===== 结算：完成 / 取消（含手续费入池） ===== */
    function _complete() internal nonReentrant inStatus(Status.Locked) {
        require(partyA != address(0) && partyB != address(0), "PARTY_0");
        status = Status.Completed;

        uint256 aFee = _fee(a.swapToken, a.swapAmount);
        uint256 bFee = _fee(b.swapToken, b.swapAmount);

        if (aFee > 0) _inject(a.swapToken, aTokenNorm, aPair, aFee);
        if (bFee > 0) _inject(b.swapToken, bTokenNorm, bPair, bFee);

        uint256 netAtoB = a.swapAmount - aFee; // B 收 A 的净额
        uint256 netBtoA = b.swapAmount - bFee; // A 收 B 的净额

        if (netBtoA > 0) _out(b.swapToken, partyA, netBtoA);
        if (netAtoB > 0) _out(a.swapToken, partyB, netAtoB);
        if (a.stakeAmount > 0) _out(a.stakeToken, partyA, a.stakeAmount);
        if (b.stakeAmount > 0) _out(b.stakeToken, partyB, b.stakeAmount);

        emit Payout(partyA, b.swapToken, netBtoA);
        emit Payout(partyB, a.swapToken, netAtoB);
        emit Completed(block.timestamp);
    }

    function _cancel() internal nonReentrant inStatus(Status.Locked) {
        require(partyA != address(0) && partyB != address(0), "PARTY_0");
        status = Status.Cancelled;

        if (a.swapAmount  > 0) _out(a.swapToken, partyA, a.swapAmount);
        if (a.stakeAmount > 0) _out(a.stakeToken, partyA, a.stakeAmount);
        if (b.swapAmount  > 0) _out(b.swapToken, partyB, b.swapAmount);
        if (b.stakeAmount > 0) _out(b.stakeToken, partyB, b.stakeAmount);

        emit Cancelled(block.timestamp);
    }

    /* ===== 手续费：计算 / 入池 ===== */
    function _noFee(address token) internal view returns (bool) {
        address norm = (token == NATIVE) ? WNATIVE : token;
        if (norm == address(0)) return false;
        if (norm == dl) return true;
        if (specialNoFeeToken != address(0) && norm == specialNoFeeToken) return true;
        return false;
    }
    function _fee(address token, uint256 amount) internal view returns (uint256) {
        if (amount == 0 || feePermille == 0) return 0;
        if (_noFee(token)) return 0;
        return (amount * feePermille) / 1000;
    }
    function _inject(address token, address tokenNorm, address pair, uint256 feeAmount) internal {
        if (pair != address(0)) {
            uint256 minted;
            if (token == NATIVE) {
                IWNATIVE(WNATIVE).deposit{value: feeAmount}();
                IERC20(WNATIVE).safeTransfer(pair, feeAmount);
                minted = IDealPairLike(pair).mintOtherOnly();
            } else {
                IERC20(tokenNorm).safeTransfer(pair, feeAmount);
                minted = IDealPairLike(pair).mintOtherOnly();
            }
            emit FeesInjected(token, feeAmount, "PAIR", pair, minted);
        } else {
            address to = treasury; require(to != address(0), "treasury=0");
            if (token == NATIVE) { (bool ok,) = payable(to).call{value: feeAmount}(""); require(ok, "send"); }
            else { IERC20(tokenNorm == address(0) ? token : tokenNorm).safeTransfer(to, feeAmount); }
            emit FeesInjected(token, feeAmount, "TREASURY", to, 0);
        }
    }

    /* ===== 工具 ===== */
    function _out(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (token == NATIVE) { (bool ok,) = payable(to).call{value: amount}(""); require(ok, "native"); }
        else IERC20(token).safeTransfer(to, amount);
    }

    /* ===== 观测 ===== */
    function balances()
        external view
        returns (uint256 ethBal, uint256 aSwapBal, uint256 aStakeBal, uint256 bSwapBal, uint256 bStakeBal)
    {
        ethBal    = address(this).balance;
        aSwapBal  = a.swapToken == NATIVE ? ethBal : IERC20(a.swapToken).balanceOf(address(this));
        aStakeBal = a.stakeToken== NATIVE ? ethBal : IERC20(a.stakeToken).balanceOf(address(this));
        bSwapBal  = b.swapToken == NATIVE ? ethBal : IERC20(b.swapToken).balanceOf(address(this));
        bStakeBal = b.stakeToken== NATIVE ? ethBal : IERC20(b.stakeToken).balanceOf(address(this));
    }

    receive() external payable {}
}
