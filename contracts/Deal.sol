// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20}            from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721}           from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver}   from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SafeERC20}         from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable}     from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard}   from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/* ---------- 工厂侧接口（最小化） ---------- */
interface IFactoryMinter { function mintDL(address to, uint256 amount) external; }
interface IWNATIVE is IERC20 { function deposit() external payable; function withdraw(uint256) external; }
interface IDealInfoNFT {
    function totalMintedOf(uint256 tokenId) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function addMinted(uint256 tokenId, uint256 amount) external;
    function maxPartnerOf(uint256 tokenId) external view returns (uint256);
    function setMaxPartnerOf(uint256 tokenId, uint256 partnerTokenId) external;
}
interface IDealPairLike { function mintOtherOnly() external returns (uint amountOther); }
interface IFactoryTwap   { function updateAndQuoteToDL(address pair, uint256 amountIn) external returns (uint256 dlOut); }
interface IFactoryIndex {
    function onCreated(address creator, bool trackCreator) external;
    function onJoined(address participant, bool trackParticipant) external;
    function onParticipantRemoved(address prevParticipant) external;
    function onAbandoned(address creator, address prevParticipant) external;
    function onClosedFor(address user) external;
}

/* ========================================================== */
contract Deal is Initializable, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    address public constant NATIVE = address(0);

    enum Status { Ready, Active, Locked, Completed, Canceled, Abandoned }
    enum JoinMode { Open, ExactAddress, NftGated }
    enum Vote { Unset, Accept, Reject }
    enum CompletionReason { BothAccepted, ForcedByA, ForcedByB }

    /* 基本信息 */
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

    // 置换 & 保证金
    address public aSwapToken;   uint256 public aSwapAmount;
    address public aMarginToken; uint256 public aMarginAmount;
    address public bSwapToken;   uint256 public bSwapAmount;
    address public bMarginToken; uint256 public bMarginAmount;

    // 支付标记
    bool public aPaid; bool public bPaid;

    // 锁定/投票/超时
    uint64 public lockedAt;
    uint64 public timeoutSeconds;
    uint64 public aAcceptAt; uint64 public bAcceptAt;
    Vote   public aVote;     Vote   public bVote;

    // 提取标记
    bool public aClaimed; bool public bClaimed;

    // 完成后的净置换额
    uint256 public aSwapNetForB;
    uint256 public bSwapNetForA;

    /* 固化配置 */
    address public dl;
    address public infoNft;
    address public treasury;
    address public WNATIVE;
    address public aTokenNorm; address public bTokenNorm;
    address public aPair;      address public bPair;

    uint16  public feePermilleNonDL;
    uint16  public mintPermilleOnFees;
    address public specialNoFeeToken;

    bool private _trackA;
    bool private _trackBActive;

    /* 事件（精简） */
    event Initialized(address indexed initiator, address indexed factory);
    event Joined(address indexed b, bool stakedNft);
    event Locked();
    event Completed(CompletionReason reason);
    event Canceled();
    event Claimed(address indexed who, address swapToken, uint256 swapAmt, address marginToken, uint256 marginAmt);
    event ANFTStaked(address indexed nft, uint256 indexed tokenId);
    event BNFTStaked(address indexed nft, uint256 indexed tokenId);
    event ANFTReturned(address indexed nft, uint256 indexed tokenId);
    event BNFTReturned(address indexed nft, uint256 indexed tokenId);
    event FeesProcessed(address indexed tokenA, uint256 aFee, address indexed tokenB, uint256 bFee);
    event RewardsMinted(address indexed a, uint256 toA, address indexed b, uint256 toB, address indexed cAddr, uint256 toC);

    modifier onlyA()  { require(msg.sender == a); _; }
    modifier onlyAB() { require(msg.sender == a || msg.sender == b); _; }
    modifier inState(Status s) { require(status == s); _; }

    /* ------------ 初始化 ------------ */
    struct InitParams {
        address aSwapToken;   uint256 aSwapAmount;
        address aMarginToken; uint256 aMarginAmount;
        address bSwapToken;   uint256 bSwapAmount;
        address bMarginToken; uint256 bMarginAmount;
        uint8   joinMode;     address expectedB;
        address gateNft;      uint256 gateNftId;
        address aNft;         uint256 aNftId;
        string  title;        uint64  timeoutSeconds;
    }
    struct ConfigParams {
        address dl;           address infoNft;     address treasury; address WNATIVE;
        address aTokenNorm;   address bTokenNorm;  address aPair;    address bPair;
        uint16  feePermilleNonDL;
        uint16  mintPermilleOnFees;
        address specialNoFeeToken;
        bool    trackCreator;
    }

    function initialize(address _factory, address _initiator, InitParams calldata p, ConfigParams calldata c)
        external initializer
    {
        require(_factory != address(0) && _initiator != address(0));
        require(p.timeoutSeconds > 0);
        require(c.dl != address(0) && c.WNATIVE != address(0));

        factory = _factory; a = _initiator;
        dl=c.dl; infoNft=c.infoNft; treasury=c.treasury; WNATIVE=c.WNATIVE;
        aTokenNorm=c.aTokenNorm; bTokenNorm=c.bTokenNorm; aPair=c.aPair; bPair=c.bPair;
        feePermilleNonDL=c.feePermilleNonDL; mintPermilleOnFees=c.mintPermilleOnFees; specialNoFeeToken=c.specialNoFeeToken;

        aSwapToken=p.aSwapToken; aSwapAmount=p.aSwapAmount; aMarginToken=p.aMarginToken; aMarginAmount=p.aMarginAmount;
        bSwapToken=p.bSwapToken; bSwapAmount=p.bSwapAmount; bMarginToken=p.bMarginToken; bMarginAmount=p.bMarginAmount;

        require(p.joinMode <= uint8(JoinMode.NftGated));
        joinMode  = JoinMode(p.joinMode);
        expectedB = p.expectedB;

        gateNft   = p.gateNft; gateNftId = p.gateNftId;
        if (joinMode == JoinMode.NftGated) { require(gateNft != address(0)); bNft = gateNft; bNftId = gateNftId; }

        aNft=p.aNft; aNftId=p.aNftId;
        title=p.title; timeoutSeconds=p.timeoutSeconds;

        status = Status.Ready;

        address aNorm = (aSwapToken == NATIVE) ? WNATIVE : aSwapToken;
        address bNorm = (bSwapToken == NATIVE) ? WNATIVE : bSwapToken;
        require(aNorm == aTokenNorm && bNorm == bTokenNorm);

        _trackA = c.trackCreator;
        if (_trackA) IFactoryIndex(factory).onCreated(a, true);

        emit Initialized(a, factory);
    }

    /* ========== A：改四数 / 废弃 ========== */
    function updateAmounts(uint256 _aSwapAmount, uint256 _aMarginAmount, uint256 _bSwapAmount, uint256 _bMarginAmount)
        external onlyA inState(Status.Ready)
    {
        aSwapAmount=_aSwapAmount; aMarginAmount=_aMarginAmount;
        bSwapAmount=_bSwapAmount; bMarginAmount=_bMarginAmount;
    }

    function abandonByA() external nonReentrant onlyA {
        require(status == Status.Ready || status == Status.Active);
        address prevB = b;

        _refundAllToParties();

        if (_trackA && _trackBActive) IFactoryIndex(factory).onAbandoned(a, prevB);
        else if (_trackA)             IFactoryIndex(factory).onAbandoned(a, address(0));
        else if (_trackBActive)       IFactoryIndex(factory).onParticipantRemoved(prevB);
        _trackA=false; _trackBActive=false;

        status = Status.Abandoned;
    }

    /* ========== B：进入 ========== */
    function join(address optNft, uint256 optId, bool trackMe) external inState(Status.Ready) {
        require(b == address(0));
        if (joinMode == JoinMode.ExactAddress) {
            require(msg.sender == expectedB, "not expectedB");
            b = msg.sender;
            if (optNft != address(0)) {
                require(IERC721(optNft).ownerOf(optId) == msg.sender);
                _pendingBNft=optNft; _pendingBNftId=optId;
                IERC721(optNft).safeTransferFrom(msg.sender, address(this), optId);
                require(bNftStaked);
            }
        } else if (joinMode == JoinMode.NftGated) {
            // 谁持有谁能进
            require(IERC721(gateNft).ownerOf(gateNftId) == msg.sender, "not nft owner");
            b = msg.sender;
            _pendingBNft=gateNft; _pendingBNftId=gateNftId;
            IERC721(gateNft).safeTransferFrom(msg.sender, address(this), gateNftId);
            require(bNftStaked);
        } else {
            b = msg.sender;
            if (optNft != address(0)) {
                require(IERC721(optNft).ownerOf(optId) == msg.sender);
                _pendingBNft=optNft; _pendingBNftId=optId;
                IERC721(optNft).safeTransferFrom(msg.sender, address(this), optId);
                require(bNftStaked);
            }
        }

        _trackBActive = trackMe;
        if (_trackBActive) IFactoryIndex(factory).onJoined(b, true);

        status = Status.Active;
        emit Joined(b, bNftStaked);
        _tryLock();
    }

    /* ========== Active：支付 / 撤回 / 退出 / 踢人 ========== */
    function pay() external payable nonReentrant inState(Status.Active) onlyAB {
        if (msg.sender == a) {
            require(!aPaid);
            require(msg.value == nativeRequiredForA());
            if (aSwapToken   != NATIVE) _pullExactERC20(IERC20(aSwapToken), aSwapAmount, msg.sender);
            if (aMarginToken != NATIVE) _pullExactERC20(IERC20(aMarginToken), aMarginAmount, msg.sender);
            if (aSwapAmount > 0 || aMarginAmount > 0) aPaid = true;
        } else {
            require(b != address(0) && !bPaid);
            require(msg.value == nativeRequiredForB());
            if (bSwapToken   != NATIVE) _pullExactERC20(IERC20(bSwapToken), bSwapAmount, msg.sender);
            if (bMarginToken != NATIVE) _pullExactERC20(IERC20(bMarginToken), bMarginAmount, msg.sender);
            if (bSwapAmount > 0 || bMarginAmount > 0) bPaid = true;
        }
        _tryLock();
    }

    function withdrawInActive() external nonReentrant inState(Status.Active) onlyAB {
        if (msg.sender == a) {
            require(aPaid); aPaid = false;
            _sendOut(aSwapToken, a, aSwapAmount);
            _sendOut(aMarginToken, a, aMarginAmount);
        } else {
            require(bPaid); bPaid = false;
            _sendOut(bSwapToken, b, bSwapAmount);
            _sendOut(bMarginToken, b, bMarginAmount);
        }
    }

    function exitByB() external nonReentrant inState(Status.Active) {
        require(msg.sender == b);
        address prevB = b;
        _refundFundsA(); _refundFundsB(); _returnBNFTIfAny();

        if (_trackBActive) { IFactoryIndex(factory).onParticipantRemoved(prevB); _trackBActive = false; }

        b = address(0); status = Status.Ready;
    }

    function kickBByA() external nonReentrant onlyA inState(Status.Active) {
        address prevB = b;
        _refundFundsA(); _refundFundsB(); _returnBNFTIfAny();
        if (_trackBActive) { IFactoryIndex(factory).onParticipantRemoved(prevB); _trackBActive = false; }
        b = address(0); status = Status.Ready;
    }

    /* ========== Locked：投票 / 强制完成 / 取消 ========== */
    function setMyVote(Vote v) external nonReentrant inState(Status.Locked) onlyAB {
        require(v != Vote.Unset);
        if (msg.sender == a) { aVote = v; aAcceptAt = (v == Vote.Accept) ? uint64(block.timestamp) : 0; }
        else { bVote = v; bAcceptAt = (v == Vote.Accept) ? uint64(block.timestamp) : 0; }

        if (aVote == Vote.Accept && bVote == Vote.Accept) _complete(CompletionReason.BothAccepted);
        else if (aVote == Vote.Reject && bVote == Vote.Reject) _cancel();
    }

    function forceComplete() external nonReentrant inState(Status.Locked) onlyAB {
        if (msg.sender == a && aVote == Vote.Accept && bVote == Vote.Unset) {
            require(block.timestamp >= uint256(aAcceptAt) + uint256(timeoutSeconds));
            _complete(CompletionReason.ForcedByA);
        } else if (msg.sender == b && bVote == Vote.Accept && aVote == Vote.Unset) {
            require(block.timestamp >= uint256(bAcceptAt) + uint256(timeoutSeconds));
            _complete(CompletionReason.ForcedByB);
        } else { revert(); }
    }

    /* ========== 完成 / 取消 / 提取 ========== */
    struct Fees    { uint256 aFee; uint256 bFee; }
    struct Rewards { uint256 toA;  uint256 toB;  uint256 toC; address cAddr; uint256 cToken; }

    function _complete(CompletionReason reason) internal {
        Fees memory f = _computeFees();
        _processFees(f); emit FeesProcessed(aSwapToken, f.aFee, bSwapToken, f.bFee);

        Rewards memory r = _computeRewardsFromFees(f);
        _mintAndRecord(r);               // <== 补回
        _refreshMaxPointers();           // <== 补回

        status = Status.Completed;
        emit Completed(reason);
    }

    function _cancel() internal { status = Status.Canceled; emit Canceled(); }

    function claimA() external nonReentrant {
        require(msg.sender == a);
        require(status == Status.Completed || status == Status.Canceled);
        require(!aClaimed); aClaimed = true;

        if (status == Status.Completed) { _sendOut(bSwapToken, a, bSwapNetForA); _sendOut(aMarginToken, a, aMarginAmount); }
        else { _sendOut(aSwapToken, a, aSwapAmount); _sendOut(aMarginToken, a, aMarginAmount); }
        _returnANFTIfAny();

        emit Claimed(a,
            status == Status.Completed ? bSwapToken : aSwapToken,
            status == Status.Completed ? bSwapNetForA : aSwapAmount,
            aMarginToken, aMarginAmount
        );

        if (_trackA) { IFactoryIndex(factory).onClosedFor(a); _trackA = false; }
    }

    function claimB() external nonReentrant {
        require(msg.sender == b);
        require(status == Status.Completed || status == Status.Canceled);
        require(!bClaimed); bClaimed = true;

        if (status == Status.Completed) { _sendOut(aSwapToken, b, aSwapNetForB); _sendOut(bMarginToken, b, bMarginAmount); }
        else { _sendOut(bSwapToken, b, bSwapAmount); _sendOut(bMarginToken, b, bMarginAmount); }
        _returnBNFTIfAny();

        emit Claimed(b,
            status == Status.Completed ? aSwapToken : bSwapToken,
            status == Status.Completed ? aSwapNetForB : bSwapAmount,
            bMarginToken, bMarginAmount
        );

        if (_trackBActive) { IFactoryIndex(factory).onClosedFor(b); _trackBActive = false; }
    }

    /* ========== 手续费 & 入池 ========== */
    function _isNoFeeToken(address token) internal view returns (bool) {
        address tNorm = (token == NATIVE) ? WNATIVE : token;
        if (tNorm == dl) return true;
        if (specialNoFeeToken != address(0) && tNorm == specialNoFeeToken) return true;
        return false;
    }

    function _computeFees() internal returns (Fees memory f) {
        f.aFee = _isNoFeeToken(aSwapToken) ? 0 : (aSwapAmount * feePermilleNonDL) / 1000;
        f.bFee = _isNoFeeToken(bSwapToken) ? 0 : (bSwapAmount * feePermilleNonDL) / 1000;
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
            IDealPairLike(pair).mintOtherOnly();
        } else {
            if (token == NATIVE) { (bool ok, ) = payable(treasury).call{value: fee}(""); require(ok); }
            else IERC20(tokenNorm).safeTransfer(treasury, fee);
        }
    }

    /* ========== 奖励（基于“已计提手续费(折 DL) * 千1”） ========== */
    function _computeRewardsFromFees(Fees memory f) internal returns (Rewards memory r) {
        if (mintPermilleOnFees == 0) return r;

        bool hasA = (infoNft != address(0)) && aNftStaked;
        bool hasB = (infoNft != address(0)) && bNftStaked;
        if (!hasA && !hasB) return r;

        uint256 totalFeeDL =
            _quoteAggToDL(aSwapToken, aPair, f.aFee) +
            _quoteAggToDL(bSwapToken, bPair, f.bFee);
        if (totalFeeDL == 0) return r;

        uint256 totalToMint = (totalFeeDL * mintPermilleOnFees) / 1000;
        if (totalToMint == 0) return r;

        uint256 share = totalToMint / 3;
        r.toA = share; r.toB = share;

        uint256 cToken = _selectC(hasA, hasB);
        if (cToken != 0) {
            r.cToken = cToken;
            r.cAddr  = IDealInfoNFT(infoNft).ownerOf(cToken);
            r.toC    = share;
        }

        uint256 rem = totalToMint - share * 3;
        if (rem > 0) r.toA += rem;
    }

    function _selectC(bool hasA, bool hasB) internal view returns (uint256 cToken) {
        IDealInfoNFT inf = IDealInfoNFT(infoNft);

        if (hasA && hasB) {
            uint256 maxA = inf.maxPartnerOf(aNftId);
            uint256 maxB = inf.maxPartnerOf(bNftId);

            uint256 sA  = inf.totalMintedOf(aNftId);
            uint256 sB  = inf.totalMintedOf(bNftId);
            uint256 sMA = inf.totalMintedOf(maxA);
            uint256 sMB = inf.totalMintedOf(maxB);

            (uint256 win4, bool unique4) = _uniqueMax4(aNftId, sA, bNftId, sB, maxA, sMA, maxB, sMB);
            if (unique4) return win4;
            if (sA == sB && sA == sMA && sA == sMB) return aNftId;
            return 0;
        }

        if (hasA) {
            uint256 maxA = inf.maxPartnerOf(aNftId);
            uint256 sA   = inf.totalMintedOf(aNftId);
            uint256 sMA  = inf.totalMintedOf(maxA);
            return (sMA > sA) ? maxA : aNftId;
        }

        if (hasB) {
            uint256 maxB = inf.maxPartnerOf(bNftId);
            uint256 sB   = inf.totalMintedOf(bNftId);
            uint256 sMB  = inf.totalMintedOf(maxB);
            return (sMB > sB) ? maxB : bNftId;
        }

        return 0;
    }

    /* ---------- 小工具：最大选择 & 并列策略（补回） ---------- */
    function _preferFirstMax2(uint256 id1, uint256 s1, uint256 id2, uint256 s2) internal pure returns (uint256) {
        if (s2 > s1) return id2; return id1;
    }
    function _preferFirstMax3(
        uint256 id1, uint256 s1,
        uint256 id2, uint256 s2,
        uint256 id3, uint256 s3
    ) internal pure returns (uint256) {
        if (s1 >= s2 && s1 >= s3) return id1;
        if (s2 >= s3) return id2;
        return id3;
    }
    function _uniqueMax4(
        uint256 id1, uint256 s1,
        uint256 id2, uint256 s2,
        uint256 id3, uint256 s3,
        uint256 id4, uint256 s4
    ) internal pure returns (uint256 id, bool unique) {
        uint256 best = s1; uint256 cnt = 1; uint256 win = id1;
        if (s2 > best) { best = s2; win = id2; cnt = 1; } else if (s2 == best) { cnt++; }
        if (s3 > best) { best = s3; win = id3; cnt = 1; } else if (s3 == best) { cnt++; }
        if (s4 > best) { best = s4; win = id4; cnt = 1; } else if (s4 == best) { cnt++; }
        if (cnt == 1) return (win, true);
        return (0, false);
    }

    /* ---------- 铸币 & 统计（补回） ---------- */
    function _mintAndRecord(Rewards memory r) internal {
        if (r.toA > 0) IFactoryMinter(factory).mintDL(a, r.toA);
        if (r.toB > 0) IFactoryMinter(factory).mintDL(b, r.toB);
        if (r.toC > 0 && r.cAddr != address(0)) IFactoryMinter(factory).mintDL(r.cAddr, r.toC);
        emit RewardsMinted(a, r.toA, b, r.toB, r.cAddr, r.toC);

        if (infoNft != address(0)) {
            if (aNftStaked && r.toA > 0) IDealInfoNFT(infoNft).addMinted(aNftId, r.toA);
            if (bNftStaked && r.toB > 0) IDealInfoNFT(infoNft).addMinted(bNftId, r.toB);
            if (r.cToken != 0 && r.toC > 0) IDealInfoNFT(infoNft).addMinted(r.cToken, r.toC);
        }
    }

    /* ---------- 完成后更新 maxA / maxB（补回） ---------- */
    function _refreshMaxPointers() internal {
        if (infoNft == address(0)) return;
        IDealInfoNFT inf = IDealInfoNFT(infoNft);
        bool hasA = aNftStaked; bool hasB = bNftStaked;

        if (hasA) {
            uint256 curMaxA = inf.maxPartnerOf(aNftId);
            uint256 winA = hasB
                ? _preferFirstMax3(
                    aNftId, inf.totalMintedOf(aNftId),
                    bNftId, inf.totalMintedOf(bNftId),
                    curMaxA, inf.totalMintedOf(curMaxA)
                )
                : _preferFirstMax2(
                    aNftId, inf.totalMintedOf(aNftId),
                    curMaxA, inf.totalMintedOf(curMaxA)
                );
            if (winA != curMaxA) inf.setMaxPartnerOf(aNftId, winA);
        }
        if (hasB) {
            uint256 curMaxB = inf.maxPartnerOf(bNftId);
            uint256 winB = hasA
                ? _preferFirstMax3(
                    bNftId, inf.totalMintedOf(bNftId),
                    aNftId, inf.totalMintedOf(aNftId),
                    curMaxB, inf.totalMintedOf(curMaxB)
                )
                : _preferFirstMax2(
                    bNftId, inf.totalMintedOf(bNftId),
                    curMaxB, inf.totalMintedOf(curMaxB)
                );
            if (winB != curMaxB) inf.setMaxPartnerOf(bNftId, winB);
        }
    }

    /* ========== 折算 ========== */
    function _quoteAggToDL(address token, address pair, uint256 amountIn) internal returns (uint256 dlOut) {
        if (amountIn == 0) return 0;
        if (token == dl) return amountIn;
        if (pair == address(0)) return 0;
        try IFactoryTwap(factory).updateAndQuoteToDL(pair, amountIn) returns (uint256 x) { return x; } catch { return 0; }
    }

    /* ========== 自动锁定判定 ========== */
    function _tryLock() internal {
        if (status != Status.Active) return;
        if (_isSideReadyA() && _isSideReadyB()) {
            status = Status.Locked;
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
        uint256 n=0; if (aSwapToken==NATIVE) n+=aSwapAmount; if (aMarginToken==NATIVE) n+=aMarginAmount; return n;
    }
    function nativeRequiredForB() public view returns (uint256) {
        uint256 n=0; if (bSwapToken==NATIVE) n+=bSwapAmount; if (bMarginToken==NATIVE) n+=bMarginAmount; return n;
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
                require(msg.sender == gateNft && tokenId == gateNftId);
                bNft = gateNft; bNftId = gateNftId;
            } else {
                require(msg.sender == _pendingBNft && tokenId == _pendingBNftId);
                bNft = _pendingBNft; bNftId = _pendingBNftId;
            }
            bNftStaked = true; _pendingBNft = address(0);
            emit BNFTStaked(msg.sender, tokenId);
            return IERC721Receiver.onERC721Received.selector;
        }
        revert();
    }

    /* ========== 工具：资金清退/发送/拉取 ========== */
    function _pullExactERC20(IERC20 token, uint256 amount, address from) internal {
        if (amount == 0) return;
        uint256 beforeBal = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);
        uint256 delta = token.balanceOf(address(this)) - beforeBal;
        require(delta == amount);
    }
    function _sendOut(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (token == NATIVE) { (bool ok, ) = payable(to).call{value: amount}(""); require(ok); }
        else IERC20(token).safeTransfer(to, amount);
    }
    function _returnANFTIfAny() internal {
        if (aNftStaked) { aNftStaked=false; IERC721(aNft).safeTransferFrom(address(this), a, aNftId); emit ANFTReturned(aNft, aNftId); }
    }
    function _returnBNFTIfAny() internal {
        if (bNftStaked) { bNftStaked=false; IERC721(bNft).safeTransferFrom(address(this), b, bNftId); emit BNFTReturned(bNft, bNftId); }
    }
    function _refundFundsA() internal {
        if (aPaid) { aPaid=false; _sendOut(aSwapToken,a,aSwapAmount); _sendOut(aMarginToken,a,aMarginAmount); }
    }
    function _refundFundsB() internal {
        if (bPaid) { bPaid=false; _sendOut(bSwapToken,b,bSwapAmount); _sendOut(bMarginToken,b,bMarginAmount); }
    }
    function _refundAllToParties() internal { _refundFundsA(); _refundFundsB(); _returnBNFTIfAny(); _returnANFTIfAny(); b = address(0); }

    // 接收原生
    receive() external payable {}
}
