// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20}            from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721}           from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver}   from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SafeERC20}         from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable}     from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard}   from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/* ---------- 外部依赖接口（最小化） ---------- */
// Deal 不再直接 mint DL；由 Factory 代理增发
interface IFactoryMinter { function mintDL(address to, uint256 amount) external; }

interface IWNATIVE is IERC20 { function deposit() external payable; function withdraw(uint256) external; }
interface IDealInfoNFT {
    function partnersOf(uint256 tokenId) external view returns (uint256[] memory);
    function totalMintedOf(uint256 tokenId) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function addMinted(uint256 tokenId, uint256 amount) external;
    function recordPartner(uint256 tokenId, uint256 partnerTokenId) external;
}

/* ---------- Pair 接口（白名单单边注入） ---------- */
interface IDealPairLike { function mintOtherOnly() external returns (uint amountOther); }

/* ---------- Factory TWAP ---------- */
interface IFactoryTwap { function updateAndQuoteToDL(address pair, uint256 amountIn) external returns (uint256 dlOut); }

/* ---------- Factory “热索引”钩子 ---------- */
interface IFactoryIndex {
    function onCreated(address creator, bool trackCreator) external;
    function onJoined(address participant, bool trackParticipant) external;
    function onParticipantRemoved(address prevParticipant) external;
    function onAbandoned(address creator, address prevParticipant) external;
    function onClosedFor(address user) external;
}

/* ==========================================================
 * Deal
 * ========================================================== */
contract Deal is Initializable, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    address public constant NATIVE = address(0);

    enum Status { Ready, Active, Locked, Completed, Canceled, Abandoned }
    enum JoinMode { Open, ExactAddress, NftGated }
    enum Vote { Unset, Accept, Reject }
    enum CompletionReason { BothAccepted, ForcedByA, ForcedByB }

    /* ------------ 错误 ------------ */
    error NotInitiator();
    error NotParticipant();
    error InvalidState();
    error AlreadyJoined();
    error NotPaid();
    error AlreadyPaid();
    error NetAmountMismatch();
    error MsgValueMismatch();
    error NotEligibleToJoin();
    error NotJoined();
    error TimeoutNotReached();
    error AlreadyClaimed();
    error UnexpectedERC721();
    error BadVote();
    error GateMismatch();
    error EmptyMessage();
    error OutOfBounds();

    /* ------------ 基本信息（存储） ------------ */
    address public factory;

    string  public title;
    address public a;
    address public b;

    Status   public status;
    JoinMode public joinMode;
    address  public expectedB;

    // 门禁 & 质押 NFT
    address public gateNft;   uint256 public gateNftId;
    address public aNft;      uint256 public aNftId;   bool public aNftStaked;
    address public bNft;      uint256 public bNftId;   bool public bNftStaked;
    address private _pendingBNft; uint256 private _pendingBNftId;

    // 四个数字（置换 & 保证金）
    address public aSwapToken;   uint256 public aSwapAmount;
    address public aMarginToken; uint256 public aMarginAmount;
    address public bSwapToken;   uint256 public bSwapAmount;
    address public bMarginToken; uint256 public bMarginAmount;

    // 已支付标记
    bool public aPaid;
    bool public bPaid;

    // 锁定/投票/超时
    uint64 public lockedAt;
    uint64 public timeoutSeconds;
    uint64 public aAcceptAt;
    uint64 public bAcceptAt;
    Vote   public aVote;
    Vote   public bVote;

    // 提取标记
    bool public aClaimed;
    bool public bClaimed;

    // 完成后的净置换额（给对方）
    uint256 public aSwapNetForB;
    uint256 public bSwapNetForA;

    string public memo;

    /* ------------ 固化配置 ------------ */
    address public dl;
    address public infoNft;
    address public treasury;
    address public WNATIVE;

    address public aTokenNorm;
    address public bTokenNorm;
    address public aPair;
    address public bPair;

    // 手续费与奖励（permille）
    uint16  public feePermilleNonDL;        // 默认 5（Factory 下发）
    uint16  public rewardPermillePerSide;   // 默认 3（Factory 下发）

    // 免手续费代币（与 DL 一样免收一切费用）
    address public specialNoFeeToken;

    /* ------------ 跟踪开关（按需调用 Factory） ------------ */
    bool private _trackA;        // 创建者是否选择“跟踪”
    bool private _trackBActive;  // 当前 B 是否选择“跟踪”（随 join/离开复位）

    /* ------------ 事件 ------------ */
    event Initialized(address indexed initiator, address indexed factory);
    event StatusChanged(Status indexed from, Status indexed to, uint64 ts);

    event JoinModeUpdated(JoinMode indexed mode, address indexed expectedB, address indexed gateNft, uint256 gateNftId);
    event AmountsUpdated(uint256 aSwapAmount, uint256 aMarginAmount, uint256 bSwapAmount, uint256 bMarginAmount);
    event Joined(address indexed b, bool stakedNft);
    event Paid(address indexed who);
    event WithdrawnInActive(address indexed who);
    event BExited(address indexed b);
    event KickedByA(address indexed prevB);
    event AbandonedByA();
    event Locked();
    event VoteSet(address indexed who, Vote vote);
    event Completed(CompletionReason reason);
    event Canceled();
    event Claimed(address indexed who, address swapToken, uint256 swapAmt, address marginToken, uint256 marginAmt);

    event ANFTStaked(address indexed nft, uint256 indexed tokenId);
    event BNFTStaked(address indexed nft, uint256 indexed tokenId);
    event ANFTReturned(address indexed nft, uint256 indexed tokenId);
    event BNFTReturned(address indexed nft, uint256 indexed tokenId);

    // 简化后的手续费事件
    event FeesProcessed(address indexed tokenA, uint256 aFee, address indexed tokenB, uint256 bFee);
    event RewardsMinted(address indexed a, uint256 toA, address indexed b, uint256 toB, address indexed cAddr, uint256 toC);

    // 消息事件
    event MessagePosted(uint256 indexed index, address indexed from, uint64 ts);
    address[] public msgFrom; uint64[] public msgTime; string[] public msgText;

    /* ------------ 修饰符 ------------ */
    modifier onlyA()  { if (msg.sender != a) revert NotInitiator(); _; }
    modifier onlyAB() { if (msg.sender != a && msg.sender != b) revert NotParticipant(); _; }
    modifier inState(Status s) { if (status != s) revert InvalidState(); _; }

    /* ------------ 初始化 ------------ */
    struct InitParams {
        address aSwapToken;   uint256 aSwapAmount;
        address aMarginToken; uint256 aMarginAmount;
        address bSwapToken;   uint256 bSwapAmount;
        address bMarginToken; uint256 bMarginAmount;
        uint8   joinMode;     address expectedB;
        address gateNft;      uint256 gateNftId;
        address aNft;         uint256 aNftId;
        string  title;        uint64  timeoutSeconds; string memo;
    }
    struct ConfigParams {
        address dl;           address infoNft;     address treasury; address WNATIVE;
        address aTokenNorm;   address bTokenNorm;  address aPair;    address bPair;
        uint16  feePermilleNonDL;
        uint16  rewardPermillePerSide;
        address specialNoFeeToken;
        bool    trackCreator; // 创建者是否纳入 Factory “热索引”
    }

    function initialize(address _factory, address _initiator, InitParams calldata p, ConfigParams calldata c)
        external initializer
    {
        require(_factory != address(0) && _initiator != address(0), "ZERO_ADDR");
        require(p.timeoutSeconds > 0, "timeout=0");
        require(c.dl != address(0) && c.WNATIVE != address(0), "cfg addr");

        factory  = _factory;
        a        = _initiator;

        dl       = c.dl;      infoNft  = c.infoNft;  treasury = c.treasury;  WNATIVE  = c.WNATIVE;
        aTokenNorm = c.aTokenNorm; bTokenNorm = c.bTokenNorm; aPair = c.aPair; bPair = c.bPair;

        // 新参数装载
        feePermilleNonDL      = c.feePermilleNonDL;       // 默认 5（来自 Factory）
        rewardPermillePerSide = c.rewardPermillePerSide;  // 默认 3
        specialNoFeeToken     = c.specialNoFeeToken;

        aSwapToken = p.aSwapToken;     aSwapAmount = p.aSwapAmount;
        aMarginToken = p.aMarginToken; aMarginAmount = p.aMarginAmount;
        bSwapToken = p.bSwapToken;     bSwapAmount = p.bSwapAmount;
        bMarginToken = p.bMarginToken; bMarginAmount = p.bMarginAmount;

        require(p.joinMode <= uint8(JoinMode.NftGated), "joinMode");
        joinMode  = JoinMode(p.joinMode);
        expectedB = p.expectedB;

        gateNft   = p.gateNft; gateNftId = p.gateNftId;
        if (joinMode == JoinMode.NftGated) {
            require(gateNft != address(0), "gate nft required");
            bNft = gateNft; bNftId = gateNftId;
        }

        aNft   = p.aNft;  aNftId = p.aNftId;
        title  = p.title; timeoutSeconds = p.timeoutSeconds;
        memo   = p.memo;

        status = Status.Ready;

        address aNorm = (aSwapToken == NATIVE) ? WNATIVE : aSwapToken;
        address bNorm = (bSwapToken == NATIVE) ? WNATIVE : bSwapToken;
        require(aNorm == aTokenNorm && bNorm == bTokenNorm, "norm mismatch");

        emit Initialized(a, factory);
        emit JoinModeUpdated(joinMode, expectedB, gateNft, gateNftId);
        emit AmountsUpdated(aSwapAmount, aMarginAmount, bSwapAmount, bMarginAmount);

        // 创建者跟踪：仅当选择了才调用 Factory
        _trackA = c.trackCreator;
        if (_trackA) {
            IFactoryIndex(factory).onCreated(a, true);
        }
    }

    /* ========== A：改四数 / 废弃 ========== */
    function updateAmounts(
        uint256 _aSwapAmount, uint256 _aMarginAmount,
        uint256 _bSwapAmount, uint256 _bMarginAmount
    ) external onlyA inState(Status.Ready) {
        aSwapAmount = _aSwapAmount; aMarginAmount = _aMarginAmount;
        bSwapAmount = _bSwapAmount; bMarginAmount = _bMarginAmount;
        emit AmountsUpdated(aSwapAmount, aMarginAmount, bSwapAmount, bMarginAmount);
    }

    /// Ready/Active 均可废弃：清退资产/NFT 后，从 Factory 索引删除（按选择）
    function abandonByA() external nonReentrant onlyA {
        if (status != Status.Ready && status != Status.Active) revert InvalidState();
        address prevB = b;
        _refundAllToParties();

        // 按需删除：同时跟踪/仅 A 跟踪/仅 B 跟踪
        if (_trackA && _trackBActive) {
            IFactoryIndex(factory).onAbandoned(a, prevB);
        } else if (_trackA) {
            IFactoryIndex(factory).onAbandoned(a, address(0));
        } else if (_trackBActive) {
            IFactoryIndex(factory).onParticipantRemoved(prevB);
        }
        _trackA = false;
        _trackBActive = false;

        _setStatus(Status.Abandoned);
        emit AbandonedByA();
    }

    /* ========== B：进入（trackMe 选择是否纳入索引） ========== */
    function join(address optNft, uint256 optId, bool trackMe) external inState(Status.Ready) {
        if (b != address(0)) revert AlreadyJoined();

        if (joinMode == JoinMode.ExactAddress) {
            if (msg.sender != expectedB) revert NotEligibleToJoin();
            b = msg.sender;
            if (optNft != address(0)) {
                if (IERC721(optNft).ownerOf(optId) != msg.sender) revert NotEligibleToJoin();
                _pendingBNft   = optNft;
                _pendingBNftId = optId;
                IERC721(optNft).safeTransferFrom(msg.sender, address(this), optId);
                require(bNftStaked, "B_NFT_NOT_STAKED");
            }
        } else if (joinMode == JoinMode.NftGated) {
            if (IERC721(gateNft).ownerOf(gateNftId) != msg.sender) revert NotEligibleToJoin();
            b = msg.sender;
            _pendingBNft   = gateNft;
            _pendingBNftId = gateNftId;
            IERC721(gateNft).safeTransferFrom(msg.sender, address(this), gateNftId);
            require(bNftStaked, "B_NFT_NOT_STAKED");
        } else {
            b = msg.sender;
            if (optNft != address(0)) {
                if (IERC721(optNft).ownerOf(optId) != msg.sender) revert NotEligibleToJoin();
                _pendingBNft   = optNft;
                _pendingBNftId = optId;
                IERC721(optNft).safeTransferFrom(msg.sender, address(this), optId);
                require(bNftStaked, "B_NFT_NOT_STAKED");
            }
        }

        // 参与者跟踪：仅当选择了才调用 Factory
        _trackBActive = trackMe;
        if (_trackBActive) {
            IFactoryIndex(factory).onJoined(b, true);
        }

        _setStatus(Status.Active);
        emit Joined(b, bNftStaked);
        _tryLock();
    }

    /* ========== Active：支付 / 撤回 / 退出 / 踢人 ========== */

    function pay() external payable nonReentrant inState(Status.Active) onlyAB {
        if (msg.sender == a) {
            if (aPaid) revert AlreadyPaid();
            uint256 need = nativeRequiredForA();
            if (msg.value != need) revert MsgValueMismatch();
            if (aSwapToken != NATIVE) _pullExactERC20(IERC20(aSwapToken), aSwapAmount, msg.sender);
            if (aMarginToken != NATIVE) _pullExactERC20(IERC20(aMarginToken), aMarginAmount, msg.sender);
            if (aSwapAmount > 0 || aMarginAmount > 0) aPaid = true;
            emit Paid(a);
        } else {
            if (b == address(0)) revert NotJoined();
            if (bPaid) revert AlreadyPaid();
            uint256 need = nativeRequiredForB();
            if (msg.value != need) revert MsgValueMismatch();
            if (bSwapToken != NATIVE) _pullExactERC20(IERC20(bSwapToken), bSwapAmount, msg.sender);
            if (bMarginToken != NATIVE) _pullExactERC20(IERC20(bMarginToken), bMarginAmount, msg.sender);
            if (bSwapAmount > 0 || bMarginAmount > 0) bPaid = true;
            emit Paid(b);
        }
        _tryLock();
    }

    function withdrawInActive() external nonReentrant inState(Status.Active) onlyAB {
        if (msg.sender == a) {
            if (!aPaid) revert NotPaid();
            aPaid = false;
            _sendOut(aSwapToken, a, aSwapAmount);
            _sendOut(aMarginToken, a, aMarginAmount);
            emit WithdrawnInActive(a);
        } else {
            if (!bPaid) revert NotPaid();
            bPaid = false;
            _sendOut(bSwapToken, b, bSwapAmount);
            _sendOut(bMarginToken, b, bMarginAmount);
            emit WithdrawnInActive(b);
        }
    }

    function exitByB() external nonReentrant inState(Status.Active) {
        if (msg.sender != b) revert NotParticipant();
        address prevB = b;
        _refundFundsA();
        _refundFundsB();
        _returnBNFTIfAny();

        // 仅当 B 开启过跟踪时才通知 Factory
        if (_trackBActive) {
            IFactoryIndex(factory).onParticipantRemoved(prevB);
            _trackBActive = false;
        }

        b = address(0);
        _setStatus(Status.Ready);
        emit BExited(msg.sender);
    }

    function kickBByA() external nonReentrant onlyA inState(Status.Active) {
        address prevB = b;
        _refundFundsA();
        _refundFundsB();
        _returnBNFTIfAny();

        if (_trackBActive) {
            IFactoryIndex(factory).onParticipantRemoved(prevB);
            _trackBActive = false;
        }

        b = address(0);
        _setStatus(Status.Ready);
        emit KickedByA(prevB);
    }

    /* ========== Locked：投票 / 强制完成 / 取消 ========== */

    function setMyVote(Vote v) external nonReentrant inState(Status.Locked) onlyAB {
        if (v == Vote.Unset) revert BadVote();

        if (msg.sender == a) {
            aVote = v; aAcceptAt = (v == Vote.Accept) ? uint64(block.timestamp) : 0;
            emit VoteSet(a, v);
        } else {
            bVote = v; bAcceptAt = (v == Vote.Accept) ? uint64(block.timestamp) : 0;
            emit VoteSet(b, v);
        }

        if (aVote == Vote.Accept && bVote == Vote.Accept) {
            _complete(CompletionReason.BothAccepted);
        } else if (aVote == Vote.Reject && bVote == Vote.Reject) {
            _cancel();
        }
    }

    function forceComplete() external nonReentrant inState(Status.Locked) onlyAB {
        if (aVote == Vote.Accept && bVote == Vote.Unset && msg.sender == a) {
            if (block.timestamp < uint256(aAcceptAt) + uint256(timeoutSeconds)) revert TimeoutNotReached();
            _complete(CompletionReason.ForcedByA);
        } else if (bVote == Vote.Accept && aVote == Vote.Unset && msg.sender == b) {
            if (block.timestamp < uint256(bAcceptAt) + uint256(timeoutSeconds)) revert TimeoutNotReached();
            _complete(CompletionReason.ForcedByB);
        } else {
            revert InvalidState();
        }
    }

    /* ========== 完成 / 取消 / 提取 ========== */

    struct Fees { uint256 aFee; uint256 bFee; }
    struct Rewards { uint256 toA; uint256 toB; uint256 toC; address cAddr; uint256 cToken; }

    function _complete(CompletionReason reason) internal {
        Fees memory f = _computeFees();
        _processFees(f);
        emit FeesProcessed(aSwapToken, f.aFee, bSwapToken, f.bFee);

        Rewards memory r = _computeRewardsAndMaybeChooseC();
        _mintAndRecord(r);

        _setStatus(Status.Completed);
        emit Completed(reason);
    }

    function _cancel() internal {
        _setStatus(Status.Canceled);
        emit Canceled();
    }

    function claimA() external nonReentrant {
        if (msg.sender != a) revert NotParticipant();
        if (!(status == Status.Completed || status == Status.Canceled)) revert InvalidState();
        if (aClaimed) revert AlreadyClaimed();
        aClaimed = true;

        if (status == Status.Completed) {
            _sendOut(bSwapToken, a, bSwapNetForA);
            _sendOut(aMarginToken, a, aMarginAmount);
        } else {
            _sendOut(aSwapToken, a, aSwapAmount);
            _sendOut(aMarginToken, a, aMarginAmount);
        }
        _returnANFTIfAny();

        emit Claimed(a,
            status == Status.Completed ? bSwapToken : aSwapToken,
            status == Status.Completed ? bSwapNetForA : aSwapAmount,
            aMarginToken, aMarginAmount
        );

        // A 开启过跟踪才清理
        if (_trackA) {
            IFactoryIndex(factory).onClosedFor(a);
            _trackA = false;
        }
    }

    function claimB() external nonReentrant {
        if (msg.sender != b) revert NotParticipant();
        if (!(status == Status.Completed || status == Status.Canceled)) revert InvalidState();
        if (bClaimed) revert AlreadyClaimed();
        bClaimed = true;

        if (status == Status.Completed) {
            _sendOut(aSwapToken, b, aSwapNetForB);
            _sendOut(bMarginToken, b, bMarginAmount);
        } else {
            _sendOut(bSwapToken, b, bSwapAmount);
            _sendOut(bMarginToken, b, bMarginAmount);
        }
        _returnBNFTIfAny();

        emit Claimed(b,
            status == Status.Completed ? aSwapToken : bSwapToken,
            status == Status.Completed ? aSwapNetForB : bSwapAmount,
            bMarginToken, bMarginAmount
        );

        if (_trackBActive) {
            IFactoryIndex(factory).onClosedFor(b);
            _trackBActive = false;
        }
    }

    /* ========== 费用计算 & 执行（同时计算净额） ========== */

    function _isNoFeeToken(address token) internal view returns (bool) {
        address tNorm = (token == NATIVE) ? WNATIVE : token;
        if (tNorm == dl) return true; // DL 永远免收费
        if (specialNoFeeToken != address(0) && tNorm == specialNoFeeToken) return true;
        return false;
    }

    function _computeFees() internal returns (Fees memory f) {
        // A 侧
        if (_isNoFeeToken(aSwapToken)) { f.aFee = 0; }
        else { f.aFee = (aSwapAmount * feePermilleNonDL) / 1000; }
        // B 侧
        if (_isNoFeeToken(bSwapToken)) { f.bFee = 0; }
        else { f.bFee = (bSwapAmount * feePermilleNonDL) / 1000; }

        aSwapNetForB = aSwapAmount - f.aFee;
        bSwapNetForA = bSwapAmount - f.bFee;
    }

    function _processFees(Fees memory f) internal {
        _handleOneSideFees(aSwapToken, aTokenNorm, aPair, f.aFee);
        _handleOneSideFees(bSwapToken, bTokenNorm, bPair, f.bFee);
    }

    function _handleOneSideFees(address token, address tokenNorm, address pair, uint256 fee) internal {
        if (fee == 0) return;

        if (pair != address(0)) {
            if (token == NATIVE) { IWNATIVE(WNATIVE).deposit{value: fee}(); IERC20(WNATIVE).safeTransfer(pair, fee); }
            else { IERC20(tokenNorm).safeTransfer(pair, fee); }
            try IDealPairLike(pair).mintOtherOnly() returns (uint amountOther) { amountOther; } catch {
                if (token == NATIVE) { IERC20(WNATIVE).safeTransfer(treasury, fee); }
                else { IERC20(tokenNorm).safeTransfer(treasury, fee); }
            }
        } else {
            if (token == NATIVE) { (bool ok, ) = payable(treasury).call{value: fee}(""); require(ok, "send fee eth fail"); }
            else { IERC20(tokenNorm).safeTransfer(treasury, fee); }
        }
    }

    /* ========== 奖励计算（总比例 3‰，按 2/3 人等分） ========== */
    function _computeRewardsAndMaybeChooseC() internal returns (Rewards memory r) {
        if (rewardPermillePerSide == 0) return r;

        // 先按单侧 3‰ 折算为 DL，再汇总后等分
        uint256 aBase = (aSwapAmount * rewardPermillePerSide) / 1000;
        uint256 bBase = (bSwapAmount * rewardPermillePerSide) / 1000;

        uint256 aDL = _quoteAggToDL(aSwapToken, aPair, aBase);
        uint256 bDL = _quoteAggToDL(bSwapToken, bPair, bBase);

        uint256 total = aDL + bDL;
        if (total == 0) return r;

        bool bothStaked = (aNftStaked && bNftStaked);
        bool canChooseC = bothStaked && (infoNft != address(0));

        uint256 cToken; address cOwner;
        if (canChooseC) {
            (cToken, cOwner) = _chooseC(aNftId, bNftId);
            if (cOwner == address(0)) { canChooseC = false; }
        }

        uint256 recipients = canChooseC ? 3 : 2;
        uint256 share = total / recipients;
        uint256 rem   = total - share * recipients;

        r.toA = share;
        r.toB = share;
        if (canChooseC) { r.toC = share; r.cToken = cToken; r.cAddr = cOwner; }

        // 余数给 A（避免精度丢失）
        if (rem > 0) { r.toA += rem; }
    }

    function _quoteAggToDL(address token, address pair, uint256 amountIn) internal returns (uint256 dlOut) {
        if (amountIn == 0) return 0;
        if (token == dl) return amountIn;
        if (pair == address(0)) return 0;
        try IFactoryTwap(factory).updateAndQuoteToDL(pair, amountIn) returns (uint256 x) { return x; } catch { return 0; }
    }

    function _chooseC(uint256 tokenA, uint256 tokenB) internal view returns (uint256 cToken, address cOwner) {
        uint256[] memory aList = IDealInfoNFT(infoNft).partnersOf(tokenA);
        uint256[] memory bList = IDealInfoNFT(infoNft).partnersOf(tokenB);
        if (aList.length == 0 || bList.length == 0) return (0, address(0));
        uint256 aMint = IDealInfoNFT(infoNft).totalMintedOf(tokenA);
        uint256 bMint = IDealInfoNFT(infoNft).totalMintedOf(tokenB);
        uint256 threshold = aMint > bMint ? aMint : bMint;
        uint256[] memory outer = aList; uint256[] memory inner = bList;
        if (outer.length > inner.length) { outer = bList; inner = aList; }
        uint256 best = 0; uint256 bestScore = 0;
        for (uint256 i = 0; i < outer.length; i++) {
            uint256 t = outer[i]; bool inInner = false;
            for (uint256 j = 0; j < inner.length; j++) { if (inner[j] == t) { inInner = true; break; } }
            if (!inInner) continue;
            uint256 score = IDealInfoNFT(infoNft).totalMintedOf(t);
            if (score <= threshold) continue;
            if (score > bestScore) { bestScore = score; best = t; }
        }
        if (best == 0) return (0, address(0));
        return (best, IDealInfoNFT(infoNft).ownerOf(best));
    }

    function _mintAndRecord(Rewards memory r) internal {
        // 由 Factory 代理增发（Deal 无 mint 权限）
        if (r.toA > 0) { try IFactoryMinter(factory).mintDL(a, r.toA) {} catch {} }
        if (r.toB > 0) { try IFactoryMinter(factory).mintDL(b, r.toB) {} catch {} }
        if (r.toC > 0 && r.cAddr != address(0)) { try IFactoryMinter(factory).mintDL(r.cAddr, r.toC) {} catch {} }

        emit RewardsMinted(a, r.toA, b, r.toB, r.cAddr, r.toC);

        // NFT 统计（失败不回滚）
        if (infoNft != address(0)) {
            if (aNftStaked && r.toA > 0) { try IDealInfoNFT(infoNft).addMinted(aNftId, r.toA) {} catch {} }
            if (bNftStaked && r.toB > 0) { try IDealInfoNFT(infoNft).addMinted(bNftId, r.toB) {} catch {} }
            if (r.cToken != 0 && r.toC > 0) { try IDealInfoNFT(infoNft).addMinted(r.cToken, r.toC) {} catch {} }
            if (aNftStaked && bNftStaked) {
                try IDealInfoNFT(infoNft).recordPartner(aNftId, bNftId) {} catch {}
                try IDealInfoNFT(infoNft).recordPartner(bNftId, aNftId) {} catch {}
            }
        }
    }

    /* ========== 消息系统 ========== */
    function postMessage(string calldata text) external nonReentrant {
        if (msg.sender != a && msg.sender != b) revert NotParticipant();
        if (bytes(text).length == 0) revert EmptyMessage();
        msgFrom.push(msg.sender); msgTime.push(uint64(block.timestamp)); msgText.push(text);
        emit MessagePosted(msgFrom.length - 1, msg.sender, uint64(block.timestamp));
    }
    function messagesCount() external view returns (uint256) { return msgFrom.length; }
    function getMsgPaginated(uint256 offset, uint256 limit)
        external view returns (address[] memory msgFromPage, uint64[] memory msgTimePage, string[] memory msgTextPage)
    {
        uint256 len = msgFrom.length;
        if (offset >= len) return (new address[](0), new uint64[](0), new string[](0));
        uint256 end = offset + limit; if (end > len) end = len; uint256 n = end - offset;
        msgFromPage = new address[](n); msgTimePage = new uint64[](n); msgTextPage = new string[](n);
        for (uint256 i = offset; i < end; i++) { msgFromPage[i-offset]=msgFrom[i]; msgTimePage[i-offset]=msgTime[i]; msgTextPage[i-offset]=msgText[i]; }
    }

    /* ========== 自动锁定判定 ========== */
    function _tryLock() internal {
        if (status != Status.Active) return;
        if (_isSideReadyA() && _isSideReadyB()) {
            _setStatus(Status.Locked);
            lockedAt = uint64(block.timestamp);
            aVote = Vote.Unset; bVote = Vote.Unset; aAcceptAt = 0; bAcceptAt = 0;
            emit Locked();
        }
    }
    function _isSideReadyA() internal view returns (bool) {
        bool tokensReady = (aSwapAmount == 0 && aMarginAmount == 0) || aPaid;
        bool nftReady    = (aNft == address(0)) || aNftStaked;
        return tokensReady && nftReady;
    }
    function _isSideReadyB() internal view returns (bool) {
        bool tokensReady = (bSwapAmount == 0 && bMarginAmount == 0) || bPaid;
        bool nftNeeded   = (joinMode == JoinMode.NftGated) || (bNft != address(0));
        bool nftReady    = (!nftNeeded) || bNftStaked;
        return tokensReady && nftReady;
    }

    /* ========== 只读：原生需求 ========== */
    function nativeRequiredForA() public view returns (uint256) {
        uint256 n = 0;
        if (aSwapToken   == NATIVE) n += aSwapAmount;
        if (aMarginToken == NATIVE) n += aMarginAmount;
        return n;
    }
    function nativeRequiredForB() public view returns (uint256) {
        uint256 n = 0;
        if (bSwapToken   == NATIVE) n += bSwapAmount;
        if (bMarginToken == NATIVE) n += bMarginAmount;
        return n;
    }

    /* ========== ERC721 接收（严格白名单） ========== */
    function onERC721Received(address, address from, uint256 tokenId, bytes calldata)
        external override nonReentrant returns (bytes4)
    {
        if (msg.sender == aNft && tokenId == aNftId && from == a && !aNftStaked) {
            aNftStaked = true; emit ANFTStaked(msg.sender, tokenId);
            return IERC721Receiver.onERC721Received.selector;
        }
        if (from == b && !bNftStaked) {
            if (joinMode == JoinMode.NftGated) {
                if (msg.sender != gateNft || tokenId != gateNftId) revert GateMismatch();
                bNft = gateNft; bNftId = gateNftId;
            } else {
                if (msg.sender != _pendingBNft || tokenId != _pendingBNftId) revert UnexpectedERC721();
                bNft = _pendingBNft; bNftId = _pendingBNftId;
            }
            bNftStaked = true; _pendingBNft = address(0);
            emit BNFTStaked(msg.sender, tokenId);
            return IERC721Receiver.onERC721Received.selector;
        }
        revert UnexpectedERC721();
    }

    /* ========== 工具：资金清退/发送/拉取 ========== */
    function _pullExactERC20(IERC20 token, uint256 amount, address from) internal {
        if (amount == 0) return;
        uint256 beforeBal = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);
        uint256 delta = token.balanceOf(address(this)) - beforeBal;
        if (delta != amount) revert NetAmountMismatch();
    }
    function _sendOut(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (token == NATIVE) { (bool ok, ) = payable(to).call{value: amount}(""); require(ok, "NATIVE_SEND_FAIL"); }
        else { IERC20(token).safeTransfer(to, amount); }
    }
    function _returnANFTIfAny() internal {
        if (aNftStaked) { aNftStaked = false; IERC721(aNft).safeTransferFrom(address(this), a, aNftId); emit ANFTReturned(aNft, aNftId); }
    }
    function _returnBNFTIfAny() internal {
        if (bNftStaked) { bNftStaked = false; IERC721(bNft).safeTransferFrom(address(this), b, bNftId); emit BNFTReturned(bNft, bNftId); }
    }
    function _refundFundsA() internal {
        if (aPaid) { aPaid = false; _sendOut(aSwapToken, a, aSwapAmount); _sendOut(aMarginToken, a, aMarginAmount); }
    }
    function _refundFundsB() internal {
        if (bPaid) { bPaid = false; _sendOut(bSwapToken, b, bSwapAmount); _sendOut(bMarginToken, b, bMarginAmount); }
    }
    function _refundAllToParties() internal {
        _refundFundsA(); _refundFundsB(); _returnBNFTIfAny(); _returnANFTIfAny(); b = address(0);
    }

    /* ========== 状态统一入口 ========== */
    function _setStatus(Status next) internal {
        Status prev = status;
        if (prev == next) return;
        status = next;
        emit StatusChanged(prev, next, uint64(block.timestamp));
    }

    // 接收原生
    receive() external payable {}
}
