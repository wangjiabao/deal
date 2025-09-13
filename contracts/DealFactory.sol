// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable}    from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones}     from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20}     from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}  from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/* ---------- 最小 DL 接口 ---------- */
interface IDLBurnFrom { function burnFrom(address account, uint256 amount) external; }
interface IDLMint     { function mint(address to, uint256 amount) external; }

/* ---------- Deal 接口（与 Deal.sol 对齐） ---------- */
interface IDealV4 {
    struct InitParams {
        address aSwapToken;   uint256 aSwapAmount;
        address aMarginToken; uint256 aMarginAmount;
        address bSwapToken;   uint256 bSwapAmount;
        address bMarginToken; uint256 bMarginAmount;
        uint8   joinMode;
        address expectedB;
        address gateNft;      uint256 gateNftId;
        address aNft;         uint256 aNftId;
        string  title;
        uint64  timeoutSeconds;
        string  memo;
    }
    struct ConfigParams {
        address dl;
        address infoNft;
        address treasury;
        address WNATIVE;
        address aTokenNorm;
        address bTokenNorm;
        address aPair;
        address bPair;
        uint16  feePermilleNonDL;       // 默认 5
        uint16  rewardPermillePerSide;  // 默认 3
        address specialNoFeeToken;      // 与 DL 一样免收费
        bool    trackCreator;           // 创建者是否加入“热索引”
    }
    function initialize(address _factory, address _initiator, InitParams calldata p, ConfigParams calldata c) external;
}

/* ---------- Pair 轻接口 ---------- */
interface IDealPairLight {
    function token0() external view returns (address); // DL
    function token1() external view returns (address); // OTHER
    function getPriceCumulatives() external view returns (uint256 p0Cum, uint256 p1Cum, uint32 ts);
    function getReserves() external view returns (uint112 r0, uint112 r1, uint32 ts);
}

/* ---------- Pair 初始化/治理接口 ---------- */
interface IDealPairInit {
    function initialize(address dlToken, address otherToken, address factory_, uint16 feeBps_) external;
    function setFeeBps(uint16 newFee) external;
    function mintInitial() external returns (uint amountDL, uint amountOther);
}

/* ==========================================================
 * DealFactory
 * ========================================================== */
contract DealFactory is Ownable {
    using Clones for address;
    using SafeERC20 for IERC20;

    /* ---------- 实现地址 ---------- */
    address public dealImplementation;
    address public pairImplementation;

    /* ---------- Deal 控制 ---------- */
    uint64  public minTimeoutSeconds;     // ≥ 3600
    mapping(address => bool) public isDeal;

    /* ---------- 全局依赖 ---------- */
    address public dlToken;               // DL 合约
    address public infoNft;               // DealInfoNFT
    address public treasury;              // 手续费接收
    address public wrappedNative;         // WETH/WBNB

    // 归一化 token(OTHER 或 WNATIVE) => pair(DL↔token)
    mapping(address => address) public pairForToken;

    /* ---------- 默认 Deal 参数（owner 可调） ---------- */
    uint16 public defaultFeePermilleNonDL       = 5; // 5‰
    uint16 public defaultRewardPermillePerSide  = 3; // 3‰
    address public specialNoFeeToken = address(0);   // 免收费代币（与 DL 一样免）

    /* ---------- 创建销毁（DL）规则 ---------- */
    bool    public createBurnEnabled;            // 默认关闭
    address public createBurnPricingToken;       // 计价代币（例如 USDT/USDC）
    uint256 public createBurnAmountInToken;      // 以计价代币精度计（如 1u）

    /* ---------- TWAP（带最小窗口粘性） ---------- */
    struct Obs { uint256 p1Cumulative; uint32 timestamp; bool inited; uint256 lastAvgQ112; }
    mapping(address => Obs) public obsByPair;
    uint32 public minWindowSec = 30;
    event TwapRolled(address indexed pair, uint256 avgQ112, uint32 ts, uint32 elapsed);

    /* ---------- 历史检索事件（按创建者 / NFT） ---------- */
    event DealCreated(address indexed deal, address indexed initiator);
    event DealCreatedV2(address indexed initiator, address indexed aNft, uint256 indexed aNftId, address deal);

    /* ---------- 管理事件 ---------- */
    event DealImplUpdated(address indexed impl);
    event PairImplUpdated(address indexed impl);
    event MinTimeoutUpdated(uint64 seconds_);
    event MinWindowSet(uint32 sec);
    event GlobalSet(string indexed key, address value);
    event PairCreated(address indexed pair, address indexed otherToken, uint16 feeBps);
    event PairFeeUpdated(address indexed pair, uint16 newFee);
    event PairMapped(address indexed otherToken, address indexed pair);

    // 新增管理事件（无 burn）
    event FeesAndRewardsUpdated(uint16 nonDLFeePermille, uint16 rewardPermille);
    event SpecialNoFeeTokenUpdated(address indexed token);
    event CreateBurnRuleUpdated(bool enabled, address pricingToken, uint256 amountInToken);
    event CreateBurnExecuted(address indexed creator, address indexed pair, address pricingToken, uint256 amountInToken, uint256 dlBurned);

    // 代理增发事件
    event DLMinted(address indexed to, uint256 amount, address indexed deal);

    /* ---------- “热索引”：用户 -> 进行中/待提取 deals ---------- */
    mapping(address => address[]) private _trackedDealsByUser;                 // user => deals[]
    mapping(address => mapping(address => uint256)) private _trackedIndexByUser; // user => (deal => 1-based index)

    event TrackedAdded(address indexed user, address indexed deal);
    event TrackedRemoved(address indexed user, address indexed deal);

    constructor(address _dealImpl, address _pairImpl, uint64 _minTimeoutSeconds) Ownable(msg.sender) {
        require(_dealImpl != address(0) && _pairImpl != address(0), "impl=0");
        require(_minTimeoutSeconds >= 3600, "min<1h");
        dealImplementation = _dealImpl;
        pairImplementation = _pairImpl;
        minTimeoutSeconds  = _minTimeoutSeconds;
        emit DealImplUpdated(_dealImpl);
        emit PairImplUpdated(_pairImpl);
        emit MinTimeoutUpdated(_minTimeoutSeconds);
    }

    /* ========== Owner 配置 ========== */
    function setDealImplementation(address impl) external onlyOwner {
        require(impl != address(0), "impl=0");
        dealImplementation = impl;
        emit DealImplUpdated(impl);
    }
    function setPairImplementation(address impl) external onlyOwner {
        require(impl != address(0), "impl=0");
        pairImplementation = impl;
        emit PairImplUpdated(impl);
    }
    function setMinTimeoutSeconds(uint64 s) external onlyOwner {
        require(s >= 3600, "min<1h");
        minTimeoutSeconds = s;
        emit MinTimeoutUpdated(s);
    }
    /// key ∈ {"dlToken","infoNft","treasury","wrappedNative"}
    function setGlobal(string calldata key, address value) external onlyOwner {
        bytes32 k = keccak256(bytes(key));
        if      (k == keccak256("dlToken"))       dlToken = value;
        else if (k == keccak256("infoNft"))       infoNft = value;
        else if (k == keccak256("treasury"))      treasury = value;
        else if (k == keccak256("wrappedNative")) wrappedNative = value;
        else revert("unknown key");
        emit GlobalSet(key, value);
    }
    function setMinWindowSec(uint32 sec_) external onlyOwner {
        require(sec_ >= 5, "too small");
        minWindowSec = sec_;
        emit MinWindowSet(sec_);
    }

    // 新：手续费与奖励全局默认值（无 burn）
    function setFeesAndRewards(uint16 nonDLFeePermille, uint16 rewardPermillePerSide) external onlyOwner {
        require(nonDLFeePermille <= 1000 && rewardPermillePerSide <= 1000, "permille");
        defaultFeePermilleNonDL      = nonDLFeePermille;      // 默认 5
        defaultRewardPermillePerSide = rewardPermillePerSide; // 默认 3
        emit FeesAndRewardsUpdated(nonDLFeePermille, rewardPermillePerSide);
    }

    // 新：设置免手续费代币
    function setSpecialNoFeeToken(address token) external onlyOwner {
        specialNoFeeToken = token;
        emit SpecialNoFeeTokenUpdated(token);
    }

    // 新：创建销毁规则
    function setCreateBurnRule(bool enabled, address pricingToken, uint256 amountInToken) external onlyOwner {
        createBurnEnabled       = enabled;
        createBurnPricingToken  = pricingToken;
        createBurnAmountInToken = amountInToken;
        emit CreateBurnRuleUpdated(enabled, pricingToken, amountInToken);
    }

    /* ========== Pair：创建 / 初始化 / 改费率 ========== */
    function createPair(address tokenOther, uint16 feeBps) external onlyOwner returns (address pair) {
        require(pairImplementation != address(0) && dlToken != address(0), "cfg");
        require(tokenOther != address(0), "other=0");
        require(tokenOther != dlToken, "same token");
        require(feeBps <= 1000, "fee too high");

        pair = pairImplementation.clone();
        IDealPairInit(pair).initialize(dlToken, tokenOther, address(this), feeBps);
        emit PairCreated(pair, tokenOther, feeBps);

        pairForToken[tokenOther] = pair; // 注意：原生请传 wrappedNative
        emit PairMapped(tokenOther, pair);
    }
    function initPair(address pair) external onlyOwner returns (uint amountDL, uint amountOther) {
        (amountDL, amountOther) = IDealPairInit(pair).mintInitial();
    }
    function setPairFeeBps(address pair, uint16 newFee) external onlyOwner {
        IDealPairInit(pair).setFeeBps(newFee);
        emit PairFeeUpdated(pair, newFee);
    }
    function getPair(address token) external view returns (address) {
        address t = (token == address(0)) ? wrappedNative : token;
        return pairForToken[t];
    }
    function isTokenSupported(address token) external view returns (bool) {
        address t = (token == address(0)) ? wrappedNative : token;
        return pairForToken[t] != address(0);
    }

    /* ========== TWAP：供 Deal 调用报价 ========== */
    function updateAndQuoteToDL(address pair, uint256 amountIn) external returns (uint256 dlOut) {
        require(isDeal[msg.sender], "NOT_DEAL");
        _assertDlPair(pair);
        return _updateAndQuoteInternal(pair, amountIn);
    }

    function _assertDlPair(address pair) internal view {
        require(pair != address(0), "PAIR=0");
        require(IDealPairLight(pair).token0() == dlToken, "NOT_DL_PAIR");
    }

    function _currentP1CumulativeWithSpot(address pair)
        internal view returns (uint256 p1CumNow, uint32 nowTs, uint256 spotQ112)
    {
        (, p1CumNow, ) = IDealPairLight(pair).getPriceCumulatives();
        (uint112 r0, uint112 r1, uint32 tsRes) = IDealPairLight(pair).getReserves();
        require(r0 > 0 && r1 > 0, "NO_LIQ");

        nowTs = uint32(block.timestamp);
        uint32 elapsed = nowTs - tsRes;
        // 现货价（Q112）
        spotQ112 = (uint256(uint224(r0)) << 112) / uint256(uint224(r1));
        if (elapsed > 0) {
            unchecked { p1CumNow += spotQ112 * elapsed; }
        }
    }

    function _updateAndQuoteInternal(address pair, uint256 amountIn) internal returns (uint256 dlOut) {
        if (amountIn == 0 || pair == address(0)) return 0;

        (uint256 cumNow, uint32 nowTs, uint256 spotQ112) = _currentP1CumulativeWithSpot(pair);
        Obs storage o = obsByPair[pair];

        if (!o.inited) {
            o.p1Cumulative = cumNow;
            o.timestamp    = nowTs;
            o.inited       = true;
            o.lastAvgQ112  = spotQ112;
            emit TwapRolled(pair, o.lastAvgQ112, nowTs, 0);
            return (spotQ112 * amountIn) >> 112;
        }

        uint32 elapsed = nowTs - o.timestamp;
        if (elapsed < minWindowSec) {
            return (o.lastAvgQ112 * amountIn) >> 112;
        }

        uint256 avgQ112 = (cumNow - o.p1Cumulative) / elapsed;
        o.p1Cumulative = cumNow;
        o.timestamp    = nowTs;
        o.lastAvgQ112  = avgQ112;
        emit TwapRolled(pair, avgQ112, nowTs, elapsed);

        dlOut = (avgQ112 * amountIn) >> 112;
    }

    /* ========== 创建 Deal（事件化 + isDeal 标记 + 可选销毁 DL） ========== */
    struct CreateParams {
        IDealV4.InitParams init;
        bool trackCreator; // 创建者是否加入热索引
    }

    function createDeal(CreateParams calldata p) external returns (address deal) {
        require(dealImplementation != address(0), "impl=0");
        require(p.init.timeoutSeconds >= minTimeoutSeconds, "timeout<min");
        require(dlToken != address(0) && wrappedNative != address(0), "globals");

        // （可选）创建前销毁一定数量的 DL：按计价代币数量经 TWAP 折算
        if (createBurnEnabled) {
            require(createBurnPricingToken != address(0) && createBurnAmountInToken > 0, "burn rule cfg");
            address pricingNorm = (createBurnPricingToken == address(0)) ? wrappedNative : createBurnPricingToken;
            address pair = pairForToken[pricingNorm];
            require(pair != address(0), "burn pair=0");
            _assertDlPair(pair);

            uint256 dlNeed = _updateAndQuoteInternal(pair, createBurnAmountInToken);
            require(dlNeed > 0, "dlNeed=0");

            // 直接从创建者地址烧（需 approve 给 DL 合约或采用角色许可）
            IDLBurnFrom(dlToken).burnFrom(msg.sender, dlNeed);
            emit CreateBurnExecuted(msg.sender, pair, pricingNorm, createBurnAmountInToken, dlNeed);
        }

        deal = dealImplementation.clone();
        isDeal[deal] = true; // 提前标记，便于 Deal.initialize 内回调本工厂

        // 归一化两端 token
        address aNorm = (p.init.aSwapToken == address(0)) ? wrappedNative : p.init.aSwapToken;
        address bNorm = (p.init.bSwapToken == address(0)) ? wrappedNative : p.init.bSwapToken;

        // 狭域作用域，避免 stack too deep
        {
            IDealV4.ConfigParams memory cfg = IDealV4.ConfigParams({
                dl:       dlToken,
                infoNft:  infoNft,
                treasury: treasury,
                WNATIVE:  wrappedNative,
                aTokenNorm: aNorm,
                bTokenNorm: bNorm,
                aPair:    pairForToken[aNorm],
                bPair:    pairForToken[bNorm],
                feePermilleNonDL:       defaultFeePermilleNonDL,      // 5‰
                rewardPermillePerSide:  defaultRewardPermillePerSide,  // 3‰
                specialNoFeeToken:      specialNoFeeToken,             // 与 DL 一样免收费
                trackCreator:           p.trackCreator
            });
            IDealV4(deal).initialize(address(this), msg.sender, p.init, cfg);
        }

        emit DealCreated(deal, msg.sender);
        emit DealCreatedV2(msg.sender, p.init.aNft, p.init.aNftId, deal);
    }

    /* ========== 代理增发：仅允许 Deal 调用 ========== */
    modifier onlyDeal() { require(isDeal[msg.sender], "NOT_DEAL"); _; }

    function mintDL(address to, uint256 amount) external onlyDeal {
        require(to != address(0) && amount > 0, "bad mint");
        IDLMint(dlToken).mint(to, amount);
        emit DLMinted(to, amount, msg.sender);
    }

    /* ==========================================================
     * “热索引”维护回调（仅 Deal 可调用）
     * ========================================================== */
    // Deal.initialize：若 trackCreator=true，则把 A 纳入索引
    function onCreated(address creator, bool trackCreator) external onlyDeal {
        if (trackCreator) _addTracked(creator, msg.sender);
    }

    // Deal.join：若 trackParticipant=true，则把 B 纳入索引
    function onJoined(address participant, bool trackParticipant) external onlyDeal {
        if (trackParticipant && participant != address(0)) {
            _addTracked(participant, msg.sender);
        }
    }

    // B 被踢 / 主动退出：立刻移除 B
    function onParticipantRemoved(address prevParticipant) external onlyDeal {
        if (prevParticipant != address(0)) _removeTracked(prevParticipant, msg.sender);
    }

    // A 放弃：按传入参数删除（Deal 已按是否跟踪选择性调用）
    function onAbandoned(address creator, address prevParticipant) external onlyDeal {
        if (creator != address(0)) _removeTracked(creator, msg.sender);
        if (prevParticipant != address(0)) _removeTracked(prevParticipant, msg.sender);
    }

    // 完成/取消后，各自 claim 时删除
    function onClosedFor(address user) external onlyDeal {
        if (user != address(0)) _removeTracked(user, msg.sender);
    }

    /* ---------- 只读：分页 ---------- */
    function trackedCount(address user) external view returns (uint256) {
        return _trackedDealsByUser[user].length;
    }

    function getTracked(address user, uint256 offset, uint256 limit)
        external view returns (address[] memory list)
    {
        address[] storage arr = _trackedDealsByUser[user];
        uint256 len = arr.length;
        if (offset >= len) return new address[](0);
        uint256 end = offset + limit; if (end > len) end = len;
        uint256 n = end - offset;
        list = new address[](n);
        for (uint256 i = 0; i < n; ++i) list[i] = arr[offset + i];
    }

    function isTracked(address user, address deal) external view returns (bool) {
        return _trackedIndexByUser[user][deal] != 0;
    }

    /* ---------- 内部：增删（swap-with-last + 1-based 索引） ---------- */
    function _addTracked(address user, address deal) internal {
        mapping(address => uint256) storage idx = _trackedIndexByUser[user];
        if (idx[deal] != 0) return; // 已存在
        _trackedDealsByUser[user].push(deal);
        idx[deal] = _trackedDealsByUser[user].length; // 1-based
        emit TrackedAdded(user, deal);
    }

    function _removeTracked(address user, address deal) internal {
        mapping(address => uint256) storage idx = _trackedIndexByUser[user];
        uint256 pos = idx[deal];
        if (pos == 0) return; // 不存在
        address[] storage arr = _trackedDealsByUser[user];
        uint256 i = pos - 1;
        uint256 last = arr.length - 1;
        if (i != last) {
            address lastDeal = arr[last];
            arr[i] = lastDeal;
            _trackedIndexByUser[user][lastDeal] = i + 1;
        }
        arr.pop();
        delete _trackedIndexByUser[user][deal];
        emit TrackedRemoved(user, deal);
    }
}
