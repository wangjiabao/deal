// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20}          from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721}         from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SafeERC20}       from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable}         from "@openzeppelin/contracts/access/Ownable.sol";

/* ---------- Deal 模板（只用到必要只读/写） ---------- */
interface IDealCore {
    enum Status { Ready, Abandoned, Locked, Completed, Cancelled }
    enum Vote   { Default, Accept, Reject }

    struct Leg { address swapToken; uint256 swapAmount; address stakeToken; uint256 stakeAmount; }

    /* setters (only operator) */
    function setPartyA(address _a) external;
    function setPartyB(address _b) external;
    function setLegs(
        address aSwap,  uint256 aSwapAmt,
        address aStake, uint256 aStakeAmt,
        address bSwap,  uint256 bSwapAmt,
        address bStake, uint256 bStakeAmt
    ) external;

    function confirmAPaid() external;
    function confirmBPaid() external;
    function withdrawForA() external;
    function withdrawForB() external;
    function abandon() external;

    function voteForA(Vote v) external;
    function voteForB(Vote v) external;
    function forceExecuteOnTimeout() external;

    /* views */
    function status() external view returns (Status);
    function partyA() external view returns (address);
    function partyB() external view returns (address);

    function a() external view returns (address,uint256,address,uint256);
    function b() external view returns (address,uint256,address,uint256);

    function dl() external view returns (address);
    function WNATIVE() external view returns (address);
    function specialNoFeeToken() external view returns (address);
    function feePermille() external view returns (uint16);

    function aTokenNorm() external view returns (address);
    function bTokenNorm() external view returns (address);
    function aPair() external view returns (address);
    function bPair() external view returns (address);
}

/* ---------- Factory 只读 / 交互最小接口 ---------- */
interface IDealFactory {
    struct CreateParams { string title; address operator; uint64 voteTimeoutSeconds; }
    function createDeal(CreateParams calldata p) external returns (address);

    function dlToken() external view returns (address);
    function wrappedNative() external view returns (address);
    function getPair(address token) external view returns (address);

    // 代理在创建时：approve 给 factory 后，由 factory 代为 burnFrom(代理)
    function burnDLFrom(address from, uint256 amount) external;
}

/* ---------- Pair 读接口（现价报价） ---------- */
interface IDealPairLight {
    function token0() external view returns (address); // 约定 token0=DL
    function token1() external view returns (address); // token1=OTHER
    function getReserves() external view returns (uint112 r0, uint112 r1, uint32 ts);
}

/* ---------- InfoNFT（可选） ---------- */
interface IDealInfoNFT {
    function totalMintedOf(uint256 tokenId) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function addMinted(uint256 tokenId, uint256 amount) external;
    function maxPartnerOf(uint256 tokenId) external view returns (uint256);
    function setMaxPartnerOf(uint256 tokenId, uint256 partnerTokenId) external;
}

/* ---------- DL mint 权限将授予代理 ---------- */
interface IDLMint { function mint(address to, uint256 amount) external; }

contract DealAgent is Ownable, IERC721Receiver {
    using SafeERC20 for IERC20;

    /* ===== 依赖 ===== */
    IDealFactory public immutable factory;

    /* ===== 全局配置（代理侧） ===== */
    address public infoNft;               // 可选：信息 NFT（如果用到 C 的选择与统计）
    uint16  public mintPermilleOnFees = 1;// 手续费(折 DL) * 千1
    bool    public createBurnEnabled;     // 创建时是否燃烧 DL
    address public burnPricingToken;      // 以此计价（如 U；0 表原生）
    uint256 public burnAmountInToken;     // 需要折算的 U 数量

    event InfoNftSet(address nft);
    event MintPermilleOnFeesSet(uint16 v);
    event CreateBurnRuleSet(bool enabled, address pricingToken, uint256 amountInToken);

    /* ===== 模式 / NFT 元数据 ===== */
    enum JoinMode { Open, ExactAddress, NftGated }
    struct NftRef { address nft; uint256 id; bool staked; }
    struct DealMeta {
        bool     inited;
        JoinMode mode;
        address  creatorA;
        address  expectedB;      // ExactAddress
        NftRef   gate;           // NftGated 用
        NftRef   aNft;           // A 的信息 NFT（可选）
        NftRef   bNft;           // B 的信息 NFT（可选）
        bool     rewardsMinted;  // 结算后只发一次
    }
    mapping(address => DealMeta) public meta; // deal => meta

    /* ===== 热索引 ===== */
    mapping(address => address[]) private _tracked;
    mapping(address => mapping(address => uint256)) private _idx; // user=>deal=>idx+1
    event TrackedAdded(address indexed user, address indexed deal);
    event TrackedRemoved(address indexed user, address indexed deal);

    /* ===== 事件 ===== */
    event DealCreated(address indexed deal, address indexed creator, JoinMode mode);
    event BJoined(address indexed deal, address indexed b);
    event ANftStaked(address indexed deal, address indexed nft, uint256 id);
    event BNftStaked(address indexed deal, address indexed nft, uint256 id);
    event BNftUnstaked(address indexed deal, address indexed nft, uint256 id);
    event BurnOnCreate(address indexed creator, uint256 dlBurned);
    event RewardsMinted(address indexed deal, uint256 toA, uint256 toB, address indexed cAddr, uint256 toC, uint256 total);

    constructor(address factory_) Ownable(msg.sender) {
        require(factory_ != address(0), "factory=0");
        factory = IDealFactory(factory_);
    }

    /* ========== 管理配置 ========== */
    function setInfoNft(address nft) external onlyOwner { infoNft = nft; emit InfoNftSet(nft); }
    function setMintPermilleOnFees(uint16 v) external onlyOwner { require(v<=1000,">1000"); mintPermilleOnFees=v; emit MintPermilleOnFeesSet(v); }
    function setCreateBurnRule(bool enabled, address pricingToken, uint256 amountInToken) external onlyOwner {
        createBurnEnabled = enabled; burnPricingToken=pricingToken; burnAmountInToken=amountInToken;
        emit CreateBurnRuleSet(enabled, pricingToken, amountInToken);
    }

    /* ========== 只读报价（现价，不更新） ========== */

    /// @notice 用 otherToken 的现价（pair 储备）把 amountIn 折成 DL，0 表示原生
    function quoteToDLByTokenView(address otherToken, uint256 amountIn) public view returns (uint256 dlOut, address pair) {
        address normOther = (otherToken == address(0)) ? factory.wrappedNative() : otherToken;
        pair = factory.getPair(normOther);
        if (pair == address(0) || amountIn == 0) return (0, pair);
        return (quoteToDLByPairView(pair, amountIn), pair);
    }

    /// @notice 按 pair 储备现价：token0=DL, token1=OTHER，返回 amountIn(OTHER) 可折 DL
    function quoteToDLByPairView(address pair, uint256 amountIn) public view returns (uint256 dlOut) {
        (uint112 r0, uint112 r1, ) = IDealPairLight(pair).getReserves();
        require(r0 > 0 && r1 > 0, "empty");
        // dlOut = amountIn * r0 / r1
        dlOut = (uint256(amountIn) * uint256(r0)) / uint256(r1);
    }

    /* ========== 创建 & 初始化（含创建时燃烧 DL） ========== */

    struct CreateReq {
        string  title;
        uint64  voteTimeoutSeconds;
        uint8   joinMode;        // 0/1/2
        address expectedB;       // mode=ExactAddress
        address gateNft;         // mode=NftGated
        uint256 gateNftId;       // mode=NftGated
        address aNft;            // A 信息 NFT（可选）
        uint256 aNftId;
    }

    /// @notice 由用户 A 调用：代理负责创建 Deal（如开启规则则先燃烧 DL），登记元数据 + 热索引
    function createDeal(CreateReq calldata req) external returns (address deal) {
        // 0) 创建前燃烧（可选）
        if (createBurnEnabled) {
            (uint256 dlNeed, ) = quoteToDLByTokenView(burnPricingToken, burnAmountInToken);
            require(dlNeed > 0, "dlNeed=0");
            // 从 A 拉 DL 到代理
            IERC20(factory.dlToken()).safeTransferFrom(msg.sender, address(this), dlNeed);
            // 代理 approve 给 factory（只用于 burn）
            _safeApprove(factory.dlToken(), address(factory), dlNeed);
            // 由 factory 代为 burnFrom(代理)
            factory.burnDLFrom(address(this), dlNeed);
            emit BurnOnCreate(msg.sender, dlNeed);
        }

        // 1) 让工厂创建（operator=本代理 或由 onlyDefaultOperator 强制为默认代理）
        IDealFactory.CreateParams memory p = IDealFactory.CreateParams({
            title: req.title,
            operator: address(this),
            voteTimeoutSeconds: req.voteTimeoutSeconds
        });
        deal = factory.createDeal(p);

        // 2) 记录 meta
        DealMeta storage m = meta[deal];
        m.inited    = true;
        m.creatorA  = msg.sender;
        m.mode      = JoinMode(req.joinMode);
        m.expectedB = req.expectedB;
        if (m.mode == JoinMode.NftGated) { m.gate = NftRef({nft: req.gateNft, id: req.gateNftId, staked: false}); }
        if (req.aNft != address(0))      { m.aNft  = NftRef({nft: req.aNft,   id: req.aNftId,   staked: false}); }

        // 3) 在 Deal 中登记 A
        IDealCore(deal).setPartyA(msg.sender);

        // 4) 热索引
        _trackAdd(msg.sender, deal);

        emit DealCreated(deal, msg.sender, m.mode);
    }

    /* ========== A 设四数 ========== */
    function setLegsByA(
        address deal,
        address aSwap,  uint256 aSwapAmt,
        address aStake, uint256 aStakeAmt,
        address bSwap,  uint256 bSwapAmt,
        address bStake, uint256 bStakeAmt
    ) external {
        _requireDeal(deal); require(IDealCore(deal).partyA() == msg.sender, "not A");
        IDealCore(deal).setLegs(aSwap, aSwapAmt, aStake, aStakeAmt, bSwap, bSwapAmt, bStake, bStakeAmt);
    }

    /* ========== 三种进场 ========== */
    function joinOpen(address deal) external { _requireDeal(deal); _joinCommon(deal, msg.sender); }
    function joinExactAddress(address deal) external {
        _requireDeal(deal);
        DealMeta storage m = meta[deal]; require(m.mode == JoinMode.ExactAddress && msg.sender == m.expectedB, "deny");
        _joinCommon(deal, msg.sender);
    }
    function joinNftGated(address deal) external {
        _requireDeal(deal);
        DealMeta storage m = meta[deal]; require(m.mode == JoinMode.NftGated, "mode");
        require(IERC721(m.gate.nft).ownerOf(m.gate.id) == msg.sender, "not gate owner");
        _joinCommon(deal, msg.sender);
    }
    function _joinCommon(address deal, address b) internal {
        IDealCore(deal).setPartyB(b);
        _trackAdd(b, deal);
        emit BJoined(deal, b);
    }

    /* ========== 可选：信息 NFT 质押 ========== */
    function stakeANft(address deal, address nft, uint256 id) external {
        _requireDeal(deal);
        require(IDealCore(deal).partyA() == msg.sender, "not A");
        meta[deal].aNft = NftRef({nft: nft, id: id, staked: true});
        IERC721(nft).safeTransferFrom(msg.sender, address(this), id);
        emit ANftStaked(deal, nft, id);
    }
    function stakeBNft(address deal, address nft, uint256 id) external {
        _requireDeal(deal);
        require(IDealCore(deal).partyB() == msg.sender, "not B");
        meta[deal].bNft = NftRef({nft: nft, id: id, staked: true});
        IERC721(nft).safeTransferFrom(msg.sender, address(this), id);
        emit BNftStaked(deal, nft, id);
    }
    function unstakeBNft(address deal) external {
        _requireDeal(deal);
        DealMeta storage m = meta[deal];
        require(IDealCore(deal).partyB() == msg.sender && m.bNft.staked, "deny");
        IERC721(m.bNft.nft).safeTransferFrom(address(this), msg.sender, m.bNft.id);
        m.bNft.staked = false;
        emit BNftUnstaked(deal, m.bNft.nft, m.bNft.id);
    }
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /* ========== 支付 & 确认（代理拉币 → 转 Deal → confirm） ========== */
    function payA(address deal) external payable {
        _requireDeal(deal); require(IDealCore(deal).partyA() == msg.sender, "not A");
        _pullAndForward(deal, true, msg.sender, msg.value);
        IDealCore(deal).confirmAPaid();
    }
    function payB(address deal) external payable {
        _requireDeal(deal); require(IDealCore(deal).partyB() == msg.sender, "not B");
        _pullAndForward(deal, false, msg.sender, msg.value);
        IDealCore(deal).confirmBPaid();
    }
    function _pullAndForward(address deal, bool isA, address from, uint256 msgValue) internal {
        (address sToken, uint256 sAmt, address mToken, uint256 mAmt) = isA ? IDealCore(deal).a() : IDealCore(deal).b();
        // ERC20
        if (sAmt>0 && sToken!=address(0)) { IERC20(sToken).safeTransferFrom(from, address(this), sAmt); IERC20(sToken).safeTransfer(deal, sAmt); }
        if (mAmt>0 && mToken!=address(0)) { IERC20(mToken).safeTransferFrom(from, address(this), mAmt); IERC20(mToken).safeTransfer(deal, mAmt); }
        // 原生
        uint256 needNative = 0;
        if (sAmt>0 && sToken==address(0)) needNative += sAmt;
        if (mAmt>0 && mToken==address(0)) needNative += mAmt;
        if (needNative > 0) {
            require(msgValue >= needNative, "native<need");
            (bool ok,) = payable(deal).call{value: needNative}(""); require(ok,"send");
            if (msgValue > needNative) { (ok,) = payable(from).call{value: msgValue - needNative}(""); require(ok,"refund"); }
        } else {
            require(msgValue == 0, "no native");
        }
    }

    /* ========== 提现（第一付款者可提） ========== */
    function withdrawForA(address deal) external { _requireDeal(deal); require(IDealCore(deal).partyA()==msg.sender,"not A"); IDealCore(deal).withdrawForA(); }
    function withdrawForB(address deal) external { _requireDeal(deal); require(IDealCore(deal).partyB()==msg.sender,"not B"); IDealCore(deal).withdrawForB(); }

    /* ========== 废弃 ========== */
    function abandon(address deal) external {
        _requireDeal(deal);
        require(IDealCore(deal).partyA() == msg.sender, "only A");
        IDealCore(deal).abandon();
        _trackRemove(msg.sender, deal);
        address b = IDealCore(deal).partyB();
        if (b != address(0)) _trackRemove(b, deal);
    }

    /* ========== 投票 / 超时（完成后增发奖励） ========== */
    function voteAccept(address deal) external {
        _requireDeal(deal);
        if (msg.sender == IDealCore(deal).partyA()) IDealCore(deal).voteForA(IDealCore.Vote.Accept);
        else if (msg.sender == IDealCore(deal).partyB()) IDealCore(deal).voteForB(IDealCore.Vote.Accept);
        else revert("not A/B");
        _tryFinalizeRewards(deal);
    }
    function voteReject(address deal) external {
        _requireDeal(deal);
        if (msg.sender == IDealCore(deal).partyA()) IDealCore(deal).voteForA(IDealCore.Vote.Reject);
        else if (msg.sender == IDealCore(deal).partyB()) IDealCore(deal).voteForB(IDealCore.Vote.Reject);
        else revert("not A/B");
        _tryFinalizeRewards(deal);
    }
    function forceExecuteOnTimeout(address deal) external {
        _requireDeal(deal);
        require(msg.sender == IDealCore(deal).partyA() || msg.sender == IDealCore(deal).partyB(), "not A/B");
        IDealCore(deal).forceExecuteOnTimeout();
        _tryFinalizeRewards(deal);
    }

    /* ---------- 完成后按手续费(折 DL) * 千分比增发（由代理直接 mint） ---------- */
    function _tryFinalizeRewards(address deal) internal {
        if (IDealCore(deal).status() != IDealCore.Status.Completed) return;
        DealMeta storage m = meta[deal];
        if (m.rewardsMinted) return;
        m.rewardsMinted = true;

        (address aSwap, uint256 aSwapAmt, , ) = IDealCore(deal).a();
        (address bSwap, uint256 bSwapAmt, , ) = IDealCore(deal).b();
        address aNorm = IDealCore(deal).aTokenNorm();
        address bNorm = IDealCore(deal).bTokenNorm();
        address aPair = IDealCore(deal).aPair();
        address bPair = IDealCore(deal).bPair();

        address dl    = IDealCore(deal).dl();
        address special = IDealCore(deal).specialNoFeeToken();
        uint16  feePermille = IDealCore(deal).feePermille();

        uint256 aFee = _isNoFee(aNorm, dl, special) ? 0 : (aSwapAmt * feePermille) / 1000;
        uint256 bFee = _isNoFee(bNorm, dl, special) ? 0 : (bSwapAmt * feePermille) / 1000;

        uint256 totalFeeDL = 0;
        if (aFee > 0 && aPair != address(0)) totalFeeDL += quoteToDLByPairView(aPair, aFee);
        if (bFee > 0 && bPair != address(0)) totalFeeDL += quoteToDLByPairView(bPair, bFee);
        if (totalFeeDL == 0 || mintPermilleOnFees == 0) { _indexClose(deal); return; }

        uint256 totalToMint = (totalFeeDL * mintPermilleOnFees) / 1000;
        if (totalToMint == 0) { _indexClose(deal); return; }

        address A = IDealCore(deal).partyA();
        address B = IDealCore(deal).partyB();

        uint256 share = totalToMint / 3;
        uint256 toA = share;
        uint256 toB = share;
        (address cAddr, uint256 toC) = _selectCAndShare(deal, share);

        uint256 rem = totalToMint - share*3;
        toA += rem;

        if (toA > 0) IDLMint(dl).mint(A, toA);
        if (toB > 0) IDLMint(dl).mint(B, toB);
        if (toC > 0 && cAddr != address(0)) IDLMint(dl).mint(cAddr, toC);

        emit RewardsMinted(deal, toA, toB, cAddr, toC, totalToMint);

        _indexClose(deal);
        _updateInfoNftStats(deal, toA, toB, cAddr, toC);
        _refreshMaxPointers(deal);
    }

    function _isNoFee(address norm, address dl, address special) internal pure returns (bool) {
        if (norm == address(0)) return false;
        if (norm == dl) return true;
        if (special != address(0) && norm == special) return true;
        return false;
    }

    /* ---------- 选择 C & InfoNFT 交互（可选） ---------- */
    function _selectCAndShare(address deal, uint256 share) internal view returns (address cAddr, uint256 toC) {
        if (infoNft == address(0)) return (address(0), 0);
        DealMeta storage m = meta[deal];
        bool hasA = (m.aNft.nft != address(0));
        bool hasB = (m.bNft.nft != address(0));
        if (!hasA && !hasB) return (address(0), 0);

        IDealInfoNFT inf = IDealInfoNFT(infoNft);
        uint256 cToken;

        if (hasA && hasB) {
            uint256 maxA = inf.maxPartnerOf(m.aNft.id);
            uint256 maxB = inf.maxPartnerOf(m.bNft.id);
            uint256 sA  = inf.totalMintedOf(m.aNft.id);
            uint256 sB  = inf.totalMintedOf(m.bNft.id);
            uint256 sMA = inf.totalMintedOf(maxA);
            uint256 sMB = inf.totalMintedOf(maxB);
            (uint256 win, bool unique) = _uniqueMax4(m.aNft.id, sA, m.bNft.id, sB, maxA, sMA, maxB, sMB);
            if (unique) cToken = win;
            else if (sA == sB && sA == sMA && sA == sMB) cToken = m.aNft.id;
        } else if (hasA) {
            uint256 maxA = inf.maxPartnerOf(m.aNft.id);
            uint256 sA   = inf.totalMintedOf(m.aNft.id);
            uint256 sMA  = inf.totalMintedOf(maxA);
            cToken = (sMA > sA) ? maxA : m.aNft.id;
        } else {
            uint256 maxB = inf.maxPartnerOf(m.bNft.id);
            uint256 sB   = inf.totalMintedOf(m.bNft.id);
            uint256 sMB  = inf.totalMintedOf(maxB);
            cToken = (sMB > sB) ? maxB : m.bNft.id;
        }

        if (cToken != 0) {
            cAddr = IDealInfoNFT(infoNft).ownerOf(cToken);
            toC   = share;
        }
    }

    function _uniqueMax4(
        uint256 id1, uint256 s1, uint256 id2, uint256 s2, uint256 id3, uint256 s3, uint256 id4, uint256 s4
    ) internal pure returns (uint256 id, bool unique) {
        uint256 best = s1; uint256 cnt = 1; uint256 win = id1;
        if (s2 > best) { best = s2; win = id2; cnt = 1; } else if (s2 == best) { cnt++; }
        if (s3 > best) { best = s3; win = id3; cnt = 1; } else if (s3 == best) { cnt++; }
        if (s4 > best) { best = s4; win = id4; cnt = 1; } else if (s4 == best) { cnt++; }
        if (cnt == 1) return (win, true);
        return (0, false);
    }

    function _updateInfoNftStats(address deal, uint256 toA, uint256 toB, address cAddr, uint256 toC) internal {
        if (infoNft == address(0)) return;
        IDealInfoNFT inf = IDealInfoNFT(infoNft);
        DealMeta storage m = meta[deal];
        if (m.aNft.nft != address(0) && toA > 0) inf.addMinted(m.aNft.id, toA);
        if (m.bNft.nft != address(0) && toB > 0) inf.addMinted(m.bNft.id, toB);
        if (cAddr != address(0) && toC > 0) {
            // 如果要给 cToken 也累计，可在 _selectCAndShare 返回 cToken 并在此 inf.addMinted(cToken, toC)；此处按旧版习惯不重复累计
        }
    }

    function _refreshMaxPointers(address deal) internal {
        if (infoNft == address(0)) return;
        IDealInfoNFT inf = IDealInfoNFT(infoNft);
        DealMeta storage m = meta[deal];
        bool hasA = (m.aNft.nft != address(0));
        bool hasB = (m.bNft.nft != address(0));
        if (!hasA && !hasB) return;

        if (hasA) {
            uint256 curMaxA = inf.maxPartnerOf(m.aNft.id);
            uint256 winA = hasB
                ? _preferFirstMax3(m.aNft.id, inf.totalMintedOf(m.aNft.id), m.bNft.id, inf.totalMintedOf(m.bNft.id), curMaxA, inf.totalMintedOf(curMaxA))
                : _preferFirstMax2(m.aNft.id, inf.totalMintedOf(m.aNft.id), curMaxA, inf.totalMintedOf(curMaxA));
            if (winA != curMaxA) inf.setMaxPartnerOf(m.aNft.id, winA);
        }
        if (hasB) {
            uint256 curMaxB = inf.maxPartnerOf(m.bNft.id);
            uint256 winB = hasA
                ? _preferFirstMax3(m.bNft.id, inf.totalMintedOf(m.bNft.id), m.aNft.id, inf.totalMintedOf(m.aNft.id), curMaxB, inf.totalMintedOf(curMaxB))
                : _preferFirstMax2(m.bNft.id, inf.totalMintedOf(m.bNft.id), curMaxB, inf.totalMintedOf(curMaxB));
            if (winB != curMaxB) inf.setMaxPartnerOf(m.bNft.id, winB);
        }
    }
    function _preferFirstMax2(uint256 id1, uint256 s1, uint256 id2, uint256 s2) internal pure returns (uint256) {
        if (s2 > s1) return id2; return id1;
    }
    function _preferFirstMax3(uint256 id1, uint256 s1, uint256 id2, uint256 s2, uint256 id3, uint256 s3) internal pure returns (uint256) {
        if (s1 >= s2 && s1 >= s3) return id1;
        if (s2 >= s3) return id2;
        return id3;
    }

    /* ========== 热索引 ========== */
    function trackedCount(address user) external view returns (uint256) { return _tracked[user].length; }
    function getTracked(address user, uint256 offset, uint256 limit) external view returns (address[] memory list) {
        address[] storage arr = _tracked[user]; uint256 len = arr.length;
        if (offset >= len) return new address[](0);
        uint256 end = offset + limit; if (end > len) end = len; uint256 n = end - offset;
        list = new address[](n); for (uint256 i=0;i<n;++i) list[i] = arr[offset + i];
    }
    function _trackAdd(address user, address deal) internal {
        mapping(address=>uint256) storage I = _idx[user];
        if (I[deal] != 0) return;
        _tracked[user].push(deal);
        I[deal] = _tracked[user].length;
        emit TrackedAdded(user, deal);
    }
    function _trackRemove(address user, address deal) internal {
        mapping(address=>uint256) storage I = _idx[user];
        uint256 pos = I[deal]; if (pos == 0) return;
        address[] storage arr = _tracked[user]; uint256 i = pos - 1; uint256 last = arr.length - 1;
        if (i != last) { address lastDeal = arr[last]; arr[i] = lastDeal; _idx[user][lastDeal] = i + 1; }
        arr.pop(); delete _idx[user][deal];
        emit TrackedRemoved(user, deal);
    }
    function _indexClose(address deal) internal {
        address A = IDealCore(deal).partyA(); if (A != address(0)) _trackRemove(A, deal);
        address B = IDealCore(deal).partyB(); if (B != address(0)) _trackRemove(B, deal);
    }

    /* ========== 工具 ========== */
    function _requireDeal(address deal) internal view { require(meta[deal].inited, "unknown deal"); }
    function _safeApprove(address token, address spender, uint256 amount) internal {
        IERC20 t = IERC20(token);
        uint256 cur = t.allowance(address(this), spender);
        if (cur < amount) { if (cur > 0) t.safeApprove(spender, 0); t.safeApprove(spender, amount); }
    }
}
