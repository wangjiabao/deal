// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable}    from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones}     from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20}     from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}  from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721}    from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/* ---------------- Token interfaces ---------------- */
interface IDLBurnFrom { function burnFrom(address account, uint256 amount) external; }
interface IDLMint     { function mint(address to, uint256 amount) external; }

/* ---------------- Deal initializer interface ---------------- */
interface IDeal {
    struct InitParams {
        address aSwapToken;   uint256 aSwapAmount;
        address aMarginToken; uint256 aMarginAmount;
        address bSwapToken;   uint256 bSwapAmount;
        address bMarginToken; uint256 bMarginAmount;
        uint8   joinMode;     // 0 Open, 1 ExactAddress, 2 NftGated
        address expectedB;
        uint256 gateNftId;    // 门禁 NFT 的 tokenId（仅在 NftGated 模式使用）
        uint256 aNftId;       // A 侧自愿/要求绑定的 tokenId（0 代表不需要）
        string  title;
        uint64  timeoutSeconds;
    }
    struct ConfigParams {
        address dl; address infoNft; address treasury; address WNATIVE;
        address aTokenNorm; address bTokenNorm; address aPair; address bPair;
        uint32  feeNonDLNum;      uint32 feeNonDLDen;
        uint32  mintOnFeesNum;    uint32 mintOnFeesDen;
        address specialNoFeeToken;
        bool    trackCreator;

        // 留言计费
        bool    msgPriceEnabled;
        address msgPriceTokenNorm;
        address msgPricePair;
        uint256 msgPriceAmountInToken;
    }
    function initialize(address _factory, address _initiator, InitParams calldata p, ConfigParams calldata c) external;
}

/* ---------------- Pair light & init interfaces ---------------- */
interface IDealPairLight {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getPriceCumulatives() external view returns (uint256 p0Cum, uint256 p1Cum, uint32 ts);
    function getReserves() external view returns (uint112 r0, uint112 r1, uint32 ts);
}
interface IDealPairInit {
    function initialize(address dlToken, address otherToken, address factory_, uint32 feeNum_, uint32 feeDen_) external;
    function setFactory(address f) external;
    function setFee(uint32 newNum, uint32 newDen) external;
    function mintInitial() external returns (uint amountDL, uint amountOther);
}

/* ---------------- DealInfoNFT (写操作由 Factory 代理) ---------------- */
interface IDealInfoNFT {
    function totalMintedOf(uint256 tokenId) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function addMinted(uint256 tokenId, uint256 amount) external;
    function maxPartnerOf(uint256 tokenId) external view returns (uint256);
    function setMaxPartnerOf(uint256 tokenId, uint256 partnerTokenId) external;
}

/* ========= 新增：InfoNFT 锁操作接口（Factory 调用） ========= */
interface IDealInfoNFTLock {
    function lockByFactory(uint256 tokenId, address deal, address owner) external;
    function unlockByFactory(uint256 tokenId, address deal) external;
}
/* ========================================================== */
contract DealFactory is Ownable {
    using Clones for address;
    using SafeERC20 for IERC20;

    address public admin;

    /* ---------- 数学工具 ---------- */
    error RatioInvalid();
    struct Ratio { uint32 num; uint32 den; }
    function _assertRatio(Ratio memory r) internal pure {
        if (r.den == 0 || r.num >= r.den) revert RatioInvalid();
    }

    /* ---------- 实现地址 ---------- */
    address public dealImplementation;
    address public pairImplementation;

    /* ---------- Deal 控制 ---------- */
    uint64  public minTimeoutSeconds;     // ≥ 3600
    mapping(address => bool) public isDeal;

    /* ---------- 全局依赖 ---------- */
    address public dlToken;
    address public infoNft;     // 唯一 NFT
    address public treasury;
    address public wrappedNative;

    // 归一化 token(OTHER 或 WNATIVE) => pair(DL↔token)
    mapping(address => address) public pairForToken;

    /* ---------- 默认参数 ---------- */
    Ratio  public defaultFeeNonDL        = Ratio({num: 5, den: 1000}); // 5‰
    Ratio  public defaultMintOnFees      = Ratio({num: 1, den: 1000}); // 千1
    address public specialNoFeeToken     = address(0);

    /* ---------- 创建销毁规则（可选） ---------- */
    bool    public createBurnEnabled;
    address public createBurnPricingToken;        // 0 原生
    uint256 public createBurnAmountInToken;

    /* ---------- 留言计费规则（全局） ---------- */
    bool    public msgPriceEnabled;
    address public msgPriceToken;                 // 0 原生
    uint256 public msgPriceAmountInToken;

    /* ---------- TWAP（带最小窗口粘性） ---------- */
    struct Obs { uint256 p1Cumulative; uint32 timestamp; bool inited; uint256 lastAvgQ112; }
    mapping(address => Obs) public obsByPair;
    uint32 public minWindowSec = 30;

    /* ---------- 事件 ---------- */
    event DealImplUpdated(address indexed impl);
    event PairImplUpdated(address indexed impl);
    event MinTimeoutUpdated(uint64 seconds_);
    event MinWindowSet(uint32 sec);
    event GlobalSet(string indexed key, address value);
    event PairCreated(address indexed pair, address indexed otherToken, uint32 feeNum, uint32 feeDen);
    event PairFeeUpdated(address indexed pair, uint32 newNum, uint32 newDen);
    event PairMapped(address indexed otherToken, address indexed pair);
    event FeesAndMintOnFeesUpdated(uint32 feeNonDLNum, uint32 feeNonDLDen, uint32 mintOnFeesNum, uint32 mintOnFeesDen);
    event SpecialNoFeeTokenUpdated(address indexed token);
    event CreateBurnRuleUpdated(bool enabled, address pricingToken, uint256 amountInToken);
    event CreateBurnExecuted(address indexed creator, address indexed pair, address pricingToken, uint256 amountInToken, uint256 dlBurned);
    event DealCreated(address indexed deal, address indexed initiator);
    event DealCreatedV2(address indexed initiator, address indexed deal, uint256 indexed aNftId);
    event DLMinted(address indexed to, uint256 amount, address indexed deal);
    event MessagePriceRuleUpdated(bool enabled, address pricingToken, uint256 amountInToken);
    event TwapRolled(address indexed pair, uint256 avgQ112, uint32 ts, uint32 elapsed);
    event TrackedAdded(address indexed user, address indexed deal);
    event TrackedRemoved(address indexed user, address indexed deal);

    /* ---------- 热索引（活跃） ---------- */
    mapping(address => address[]) private _trackedDealsByUser;
    mapping(address => mapping(address => uint256)) private _trackedIndexByUser;

    /* ---------- 完成热索引（每用户固定 10 个，环形缓冲） ---------- */
    uint8 public constant COMPLETED_MAX = 10;

    struct CompletedRing {
        address[COMPLETED_MAX] items; // 以逻辑顺序铺放在环上
        uint8 start;                  // 指向最旧元素的位置
        uint8 size;                   // 当前数量
    }
    mapping(address => CompletedRing) private _completedByUser;
    event CompletedAdded(address indexed user, address indexed deal);

    /* ---------------- Modifiers ---------------- */
    modifier onlyAdmin() {
        require(msg.sender == admin, "NOT_ADMIN");
        _;
    }
    modifier onlyDeal() { require(isDeal[msg.sender]); _; }

    constructor(address _dealImpl, address _pairImpl, uint64 _minTimeoutSeconds) Ownable(msg.sender) {
        require(_dealImpl != address(0) && _pairImpl != address(0));
        require(_minTimeoutSeconds >= 3600);
        dealImplementation = _dealImpl; pairImplementation = _pairImpl; minTimeoutSeconds = _minTimeoutSeconds; admin = msg.sender;
        emit DealImplUpdated(_dealImpl); emit PairImplUpdated(_pairImpl); emit MinTimeoutUpdated(_minTimeoutSeconds);
    }

    /* ========== Owner Admin 配置 ========== */
    function setDealImplementation(address impl) external onlyOwner { require(impl != address(0)); dealImplementation = impl; emit DealImplUpdated(impl); }
    function setPairImplementation(address impl) external onlyOwner { require(impl != address(0)); pairImplementation = impl; emit PairImplUpdated(impl); }
    function setMinTimeoutSeconds(uint64 s) external onlyOwner { require(s >= 1800); minTimeoutSeconds = s; emit MinTimeoutUpdated(s); }
    
    function setAdmin(address _admin) external onlyAdmin { admin = _admin; }
    function setMinTimeoutSecondsByAdmin(uint64 s) external onlyAdmin { require(s >= 3600); minTimeoutSeconds = s; emit MinTimeoutUpdated(s); }

    /// key ∈ {"dlToken","infoNft","treasury","wrappedNative"}
    function setGlobal(string calldata key, address value) external onlyOwner {
        bytes32 k = keccak256(bytes(key));
        if      (k == keccak256("dlToken"))       dlToken = value;
        else if (k == keccak256("infoNft"))       infoNft = value;
        else if (k == keccak256("wrappedNative")) wrappedNative = value;
        else revert();
        emit GlobalSet(key, value);
    }

    function setMinWindowSec(uint32 sec_) external onlyOwner { require(sec_ >= 5); minWindowSec = sec_; emit MinWindowSet(sec_); }
    function setMinWindowSecByAdmin(uint32 sec_) external onlyAdmin { require(sec_ >= 30); minWindowSec = sec_; emit MinWindowSet(sec_); }

    function setFeesAndMintOnFees(uint32 feeNonDLNum, uint32 feeNonDLDen, uint32 mintOnFeesNum, uint32 mintOnFeesDen) external onlyOwner {
        Ratio memory r1 = Ratio({num: feeNonDLNum, den: feeNonDLDen});
        Ratio memory r2 = Ratio({num: mintOnFeesNum, den: mintOnFeesDen});
        _assertRatio(r1); _assertRatio(r2);
        defaultFeeNonDL = r1;
        defaultMintOnFees = r2;
        emit FeesAndMintOnFeesUpdated(feeNonDLNum, feeNonDLDen, mintOnFeesNum, mintOnFeesDen);
    }
    function setFeesAndMintOnFeesByAdmin(uint32 feeNonDLNum, uint32 mintOnFeesNum) external onlyAdmin {
        require(1 <= feeNonDLNum && 10 >= feeNonDLNum);
        require(1 <= mintOnFeesNum && 10 >= mintOnFeesNum);
        Ratio memory r1 = Ratio({num: feeNonDLNum, den: 1000});
        Ratio memory r2 = Ratio({num: mintOnFeesNum, den: 1000});
        _assertRatio(r1); _assertRatio(r2);
        defaultFeeNonDL = r1;
        defaultMintOnFees = r2;
        emit FeesAndMintOnFeesUpdated(feeNonDLNum, 1000, mintOnFeesNum, 1000);
    }
    function setSpecialNoFeeTokenByAdmin(address token) external onlyAdmin { specialNoFeeToken = token; emit SpecialNoFeeTokenUpdated(token); }
    function setTreasuryByAdmin(address _treasury) external onlyAdmin { treasury =  _treasury; }

    /* ---------- 留言计费规则 ---------- */
    function setMessagePriceRule(bool enabled, address pricingToken, uint256 amountInToken) external onlyOwner {
        msgPriceEnabled = enabled; msgPriceToken = pricingToken; msgPriceAmountInToken = amountInToken;
        emit MessagePriceRuleUpdated(enabled, pricingToken, amountInToken);
    }
    function setMessagePriceRuleByAdmin(uint256 amountInToken) external onlyAdmin {
        require(amountInToken >= 1 * 10**16 && amountInToken <= 10 * 10**18);
        msgPriceAmountInToken = amountInToken;
        emit MessagePriceRuleUpdated(msgPriceEnabled, msgPriceToken, amountInToken);
    }

    /* ---------- 创建销毁规则（可选） ---------- */
    function setCreateBurnRule(bool enabled, address pricingToken, uint256 amountInToken) external onlyOwner {
        createBurnEnabled = enabled; createBurnPricingToken = pricingToken; createBurnAmountInToken = amountInToken;
        emit CreateBurnRuleUpdated(enabled, pricingToken, amountInToken);
    }
    function setCreateBurnRuleByAdmin(uint256 amountInToken) external onlyAdmin {
        require(amountInToken >= 1 * 10**16 && amountInToken <= 100 * 10**18);
        createBurnAmountInToken = amountInToken;
        emit CreateBurnRuleUpdated(createBurnEnabled, createBurnPricingToken, amountInToken);
    }

    /* ========== Pair：创建 / 初始化 / 改费率 ========== */
    function createPair(address tokenOther, uint32 feeNum, uint32 feeDen) external onlyOwner returns (address pair) {
        require(pairForToken[tokenOther] == address(0), "PAIR_EXISTS");
        require(pairImplementation != address(0) && dlToken != address(0));
        require(tokenOther != address(0) && tokenOther != dlToken);
        Ratio memory r = Ratio({num: feeNum, den: feeDen}); _assertRatio(r);

        pair = pairImplementation.clone();
        require(pair != address(0), "CLONE_FAILED");
        require(pair.code.length > 0, "CLONE_NO_CODE");

        IDealPairInit(pair).initialize(dlToken, tokenOther, address(this), feeNum, feeDen);
        _assertDlPair(pair);

        emit PairCreated(pair, tokenOther, feeNum, feeDen);

        pairForToken[tokenOther] = pair;
        emit PairMapped(tokenOther, pair);
    }

    function setPairFactory(address pair, address f) external onlyOwner {
        IDealPairInit(pair).setFactory(f);
    }
    function initPair(address pair) external onlyOwner returns (uint amountDL, uint amountOther) {
        (amountDL, amountOther) = IDealPairInit(pair).mintInitial();
    }
    function setPairFee(address pair, uint32 newNum, uint32 newDen) external onlyOwner {
        IDealPairInit(pair).setFee(newNum, newDen);
        emit PairFeeUpdated(pair, newNum, newDen);
    }
     function setPairFeeByAdmin(address pair, uint32 newNum) external onlyAdmin {
         require(1 <= newNum && 100 >= newNum);
        IDealPairInit(pair).setFee(newNum, 10000);
        emit PairFeeUpdated(pair, newNum, 10000);
    }
    function getPair(address token) external view returns (address) { address t = (token == address(0)) ? wrappedNative : token; return pairForToken[t]; }
    function isTokenSupported(address token) external view returns (bool) { address t = (token == address(0)) ? wrappedNative : token; return pairForToken[t] != address(0); }

    /* ========== TWAP：供 Deal 调用报价 ========== */
    function updateAndQuoteToDL(address pair, uint256 amountIn) external returns (uint256 dlOut) {
        require(isDeal[msg.sender] || infoNft == msg.sender); _assertDlPair(pair); return _updateAndQuoteInternal(pair, amountIn);
    }
    function _currentP1CumulativeWithSpot(address pair) internal view returns (uint256 p1CumNow, uint32 nowTs, uint256 spotQ112) {
        (, p1CumNow, ) = IDealPairLight(pair).getPriceCumulatives();
        (uint112 r0, uint112 r1, uint32 tsRes) = IDealPairLight(pair).getReserves();
        require(r0 > 0 && r1 > 0);
        nowTs = uint32(block.timestamp); uint32 elapsed = nowTs - tsRes;
        spotQ112 = (uint256(uint224(r0)) << 112) / uint256(uint224(r1));
        if (elapsed > 0) { unchecked { p1CumNow += spotQ112 * elapsed; } }
    }
    function _updateAndQuoteInternal(address pair, uint256 amountIn) internal returns (uint256 dlOut) {
        if (amountIn == 0 || pair == address(0)) return 0;
        (uint256 cumNow, uint32 nowTs, uint256 spotQ112) = _currentP1CumulativeWithSpot(pair);
        Obs storage o = obsByPair[pair];
        if (!o.inited) {
            o.p1Cumulative = cumNow; o.timestamp = nowTs; o.inited = true; o.lastAvgQ112 = spotQ112;
            emit TwapRolled(pair, o.lastAvgQ112, nowTs, 0);
            return (spotQ112 * amountIn) >> 112;
        }
        uint32 elapsed = nowTs - o.timestamp;
        if (elapsed < minWindowSec) return (o.lastAvgQ112 * amountIn) >> 112;
        uint256 avgQ112 = (cumNow - o.p1Cumulative) / elapsed;
        o.p1Cumulative = cumNow; o.timestamp = nowTs; o.lastAvgQ112 = avgQ112;
        emit TwapRolled(pair, avgQ112, nowTs, elapsed);
        return (avgQ112 * amountIn) >> 112;
    }

    /* ========== 创建 Deal ========== */
    struct CreateParams { IDeal.InitParams init; bool trackCreator; }

    function createDeal(CreateParams calldata p) external returns (address deal) {
        require(dealImplementation != address(0));
        require(p.init.timeoutSeconds >= minTimeoutSeconds);
        require(dlToken != address(0) && wrappedNative != address(0));

        if (createBurnEnabled) {
            address pricingNormC = (createBurnPricingToken == address(0)) ? wrappedNative : createBurnPricingToken;
            address pairC = pairForToken[pricingNormC];
            require(pairC != address(0), "CREATE_BURN_NO_PAIR");
            _assertDlPair(pairC);
            uint256 dlNeed = _updateAndQuoteInternal(pairC, createBurnAmountInToken);
            require(dlNeed > 0, "CREATE_BURN_QTY_0");
            IDLBurnFrom(dlToken).burnFrom(msg.sender, dlNeed);
            emit CreateBurnExecuted(msg.sender, pairC, pricingNormC, createBurnAmountInToken, dlNeed);
        }

        deal = dealImplementation.clone();
        require(deal != address(0), "CLONE_FAILED");
        require(deal.code.length > 0, "CLONE_NO_CODE");
        isDeal[deal] = true;

        address aNorm = (p.init.aSwapToken == address(0)) ? wrappedNative : p.init.aSwapToken;
        address bNorm = (p.init.bSwapToken == address(0)) ? wrappedNative : p.init.bSwapToken;

        address msgNorm = (msgPriceToken == address(0)) ? wrappedNative : msgPriceToken;
        address msgPair = (msgNorm == dlToken) ? address(0) : pairForToken[msgNorm];

        IDeal.ConfigParams memory cfg = IDeal.ConfigParams({
            dl: dlToken,
            infoNft: infoNft,
            treasury: treasury,
            WNATIVE: wrappedNative,
            aTokenNorm: aNorm,
            bTokenNorm: bNorm,
            aPair: pairForToken[aNorm],
            bPair: pairForToken[bNorm],
            feeNonDLNum: defaultFeeNonDL.num,
            feeNonDLDen: defaultFeeNonDL.den,
            mintOnFeesNum: defaultMintOnFees.num,
            mintOnFeesDen: defaultMintOnFees.den,
            specialNoFeeToken: specialNoFeeToken,
            trackCreator: p.trackCreator,

            msgPriceEnabled: msgPriceEnabled,
            msgPriceTokenNorm: msgNorm,
            msgPricePair: msgPair,
            msgPriceAmountInToken: msgPriceAmountInToken
        });

        IDeal(deal).initialize(address(this), msg.sender, p.init, cfg);

        emit DealCreated(deal, msg.sender);
        emit DealCreatedV2(msg.sender, deal, p.init.aNftId);
    }

    /* ========== 代理：增发 DL（仅 Deal） ========== */
    function mintDL(address to, uint256 amount) external onlyDeal { require(to != address(0) && amount > 0); IDLMint(dlToken).mint(to, amount); emit DLMinted(to, amount, msg.sender); }

    /* ========== 代理：写 InfoNFT（仅 Deal） ========== */
    function infoAddMinted(uint256 tokenId, uint256 amount) external onlyDeal {
        require(infoNft != address(0) && amount > 0, "INFO_NFT/AMOUNT");
        IDealInfoNFT(infoNft).addMinted(tokenId, amount);
    }
    function infoSetMaxPartnerOf(uint256 tokenId, uint256 partnerTokenId) external onlyDeal {
        require(infoNft != address(0), "INFO_NFT_ZERO");
        IDealInfoNFT(infoNft).setMaxPartnerOf(tokenId, partnerTokenId);
    }

    /* ========= 新增：InfoNFT 锁代理（仅 Deal） ========= */
    function infoLock(uint256 tokenId, address holder) external onlyDeal {
        require(infoNft != address(0), "INFO_NFT_ZERO");
        IDealInfoNFTLock(infoNft).lockByFactory(tokenId, msg.sender, holder);
    }
    function infoUnlock(uint256 tokenId) external onlyDeal {
        require(infoNft != address(0), "INFO_NFT_ZERO");
        IDealInfoNFTLock(infoNft).unlockByFactory(tokenId, msg.sender);
    }

    /* ========== 热索引回调（仅 Deal） ========== */
    function onCreated(address creator, bool trackCreator) external onlyDeal { if (trackCreator) _addTracked(creator, msg.sender); }
    function onJoined(address participant, bool trackParticipant) external onlyDeal { if (trackParticipant && participant != address(0)) _addTracked(participant, msg.sender); }
    function onParticipantRemoved(address prevParticipant) external onlyDeal { if (prevParticipant != address(0)) _removeTracked(prevParticipant, msg.sender); }
    function onAbandoned(address creator, address prevParticipant) external onlyDeal { if (creator != address(0)) _removeTracked(creator, msg.sender); if (prevParticipant != address(0)) _removeTracked(prevParticipant, msg.sender); }
    function onClosedFor(address user) external onlyDeal { if (user != address(0)) _removeTracked(user, msg.sender); }

    // 完成回调（仅完成态 & 仅 Deal 可调）
    function onCompletedFor(address user) external onlyDeal {
        if (user == address(0)) return;
        _addCompleted(user, msg.sender);
    }

    /* ========== 热索引只读（活跃） ========== */
    function trackedCount(address user) external view returns (uint256) { return _trackedDealsByUser[user].length; }
    function getTracked(address user, uint256 offset, uint256 limit) external view returns (address[] memory list) {
        address[] storage arr = _trackedDealsByUser[user]; uint256 len = arr.length;
        if (offset >= len) return new address[](0);
        uint256 end = offset + limit; if (end > len) end = len; uint256 n = end - offset;
        list = new address[](n); for (uint256 i = 0; i < n; ++i) list[i] = arr[offset + i];
    }
    function isTracked(address user, address deal) external view returns (bool) { return _trackedIndexByUser[user][deal] != 0; }

    /* ========== 完成热索引只读 ========== */
    function completedCount(address user) external view returns (uint256) {
        return _completedByUser[user].size;
    }

    /**
     * @param newestFirst true: newest->older；false: oldest->newer
     */
    function getCompleted(
        address user,
        uint256 offset,
        uint256 limit,
        bool newestFirst
    ) external view returns (address[] memory list) {
        CompletedRing storage r = _completedByUser[user];
        uint256 sz = r.size;
        if (offset >= sz) return new address[](0);
        uint256 end = offset + limit;
        if (end > sz) end = sz;
        uint256 n = end - offset;

        list = new address[](n);
        if (newestFirst) {
            for (uint256 i = 0; i < n; ++i) {
                uint256 logical = sz - 1 - (offset + i);
                uint8 idx = uint8((uint16(r.start) + uint16(logical)) % uint16(COMPLETED_MAX));
                list[i] = r.items[idx];
            }
        } else {
            for (uint256 i = 0; i < n; ++i) {
                uint8 idx = uint8((uint16(r.start) + uint16(offset + i)) % uint16(COMPLETED_MAX));
                list[i] = r.items[idx];
            }
        }
    }

    /* ---------- 辅助（活跃热索引） ---------- */
    function _addTracked(address user, address deal) internal {
        mapping(address => uint256) storage idx = _trackedIndexByUser[user];
        if (idx[deal] != 0) return;
        _trackedDealsByUser[user].push(deal);
        idx[deal] = _trackedDealsByUser[user].length;
        emit TrackedAdded(user, deal);
    }
    function _removeTracked(address user, address deal) internal {
        mapping(address => uint256) storage idx = _trackedIndexByUser[user];
        uint256 pos = idx[deal]; if (pos == 0) return;
        address[] storage arr = _trackedDealsByUser[user]; uint256 i = pos - 1; uint256 last = arr.length - 1;
        if (i != last) { address lastDeal = arr[last]; arr[i] = lastDeal; _trackedIndexByUser[user][lastDeal] = i + 1; }
        arr.pop(); delete _trackedIndexByUser[user][deal];
        emit TrackedRemoved(user, deal);
    }

    /* ---------- 辅助（完成热索引） ---------- */
    function _addCompleted(address user, address deal) internal {
        CompletedRing storage r = _completedByUser[user];
        if (r.size < COMPLETED_MAX) {
            uint8 idx = uint8((uint16(r.start) + uint16(r.size)) % uint16(COMPLETED_MAX));
            r.items[idx] = deal;
            unchecked { r.size += 1; }
        } else {
            r.items[r.start] = deal;
            r.start = uint8((r.start + 1) % uint16(COMPLETED_MAX));
        }
        emit CompletedAdded(user, deal);
    }

    function _assertDlPair(address pair) internal view { require(pair != address(0) && IDealPairLight(pair).token0() == dlToken); }
}
