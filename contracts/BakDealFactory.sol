// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable}   from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones}    from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20}    from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* ---------------- 与新模板 DealABTemplateFinal 对齐的最小接口 ---------------- */
interface IDealTemplate {
    struct StaticConfig {
        string  title;
        address operator;              // 代理者（本次创建指定，或使用工厂默认）
        address factory;               // 本工厂地址
        address dl;                    // DL token（免手续费）
        address WNATIVE;               // 原生币包装
        address treasury;              // 无 pair 时手续费去向
        uint16  feePermille;           // 手续费（千分比，<=1000）
        address specialNoFeeToken;     // 特殊免手续费（规范化后比较）
        uint64  voteTimeoutSeconds;    // 投票超时秒数（>= minTimeoutSeconds）
    }
    function initialize(StaticConfig calldata c) external;
}

/* ---------------- 与 Pair(DealSwapTemplate) 对齐的最小接口 ---------------- */
interface IDealPairInit {
    function initialize(address dlToken, address otherToken, address factory_, uint16 feeBps_) external;
    function setFeeBps(uint16 newFee) external;
    function mintInitial() external returns (uint amountDL, uint amountOther);
}

/**
 * @title DealFactory
 * @notice 精简版工厂：
 *   - 保留 Pair 管理（createPair/initPair/setPairFeeBps/getPair/isTokenSupported）
 *   - 创建 Deal：按新版模板（DealABTemplateFinal）调用 initialize(StaticConfig)
 *   - 移除：价格观察/TWAP、代理增发、热索引、创建销毁规则等无关逻辑
 */
contract DealFactory is Ownable {
    using Clones for address;

    /* ---------------- 实现代币/合约地址 ---------------- */
    address public dealImplementation;     // 模板合约（DealABTemplateFinal）的实现地址
    address public pairImplementation;     // Pair 实现地址（如 DealSwapTemplate）

    /* ---------------- 全局依赖（由 Owner 配置） ---------------- */
    address public dlToken;                // DL
    address public wrappedNative;          // WNATIVE
    address public treasury;               // 手续费归集地址

    /* ---------------- Pair 映射：OTHER(规范化) => pair(DL↔OTHER) ---------------- */
    mapping(address => address) public pairForToken;

    /* ---------------- 创建 Deal 的默认参数 ---------------- */
    uint16 public defaultFeePermille   = 5;      // 5‰，<=1000
    address public specialNoFeeToken   = address(0);
    uint64  public minTimeoutSeconds   = 3600;   // 创建时的最小超时时间
    address public defaultOperator     = address(0); // 可选：默认代理者
    bool    public onlyDefaultOperator = false;      // true 时强制使用 defaultOperator

    /* ---------------- 事件 ---------------- */
    event DealImplUpdated(address indexed impl);
    event PairImplUpdated(address indexed impl);

    event DLTokenSet(address indexed token);
    event WrappedNativeSet(address indexed token);
    event TreasurySet(address indexed treasury);
    event DefaultFeePermilleSet(uint16 permille);
    event SpecialNoFeeTokenSet(address indexed token);
    event MinTimeoutSet(uint64 seconds_);
    event DefaultOperatorSet(address indexed op, bool onlyDefault);

    event PairCreated(address indexed pair, address indexed otherToken, uint16 feeBps);
    event PairFeeUpdated(address indexed pair, uint16 newFee);
    event PairMapped(address indexed otherToken, address indexed pair);

    event DealCreated(address indexed deal, address indexed operator, string title, uint64 voteTimeoutSeconds);

    constructor(address _dealImpl, address _pairImpl, address _dl, address _wnative, address _treasury)
        Ownable(msg.sender)
    {
        require(_dealImpl != address(0) && _pairImpl != address(0), "impl=0");
        require(_dl != address(0) && _wnative != address(0) && _treasury != address(0), "globals=0");

        dealImplementation = _dealImpl;
        pairImplementation = _pairImpl;
        dlToken            = _dl;
        wrappedNative      = _wnative;
        treasury           = _treasury;

        emit DealImplUpdated(_dealImpl);
        emit PairImplUpdated(_pairImpl);
        emit DLTokenSet(_dl);
        emit WrappedNativeSet(_wnative);
        emit TreasurySet(_treasury);
    }

    /* ========== Owner：实现/全局参数 ========== */

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

    function setDLToken(address token) external onlyOwner {
        require(token != address(0), "0");
        dlToken = token;
        emit DLTokenSet(token);
    }

    function setWrappedNative(address token) external onlyOwner {
        require(token != address(0), "0");
        wrappedNative = token;
        emit WrappedNativeSet(token);
    }

    function setTreasury(address to) external onlyOwner {
        require(to != address(0), "0");
        treasury = to;
        emit TreasurySet(to);
    }

    function setDefaultFeePermille(uint16 permille) external onlyOwner {
        require(permille <= 1000, ">1000");
        defaultFeePermille = permille;
        emit DefaultFeePermilleSet(permille);
    }

    function setSpecialNoFeeToken(address token) external onlyOwner {
        specialNoFeeToken = token; // 允许清零
        emit SpecialNoFeeTokenSet(token);
    }

    function setMinTimeoutSeconds(uint64 seconds_) external onlyOwner {
        require(seconds_ >= 1, "too small");
        minTimeoutSeconds = seconds_;
        emit MinTimeoutSet(seconds_);
    }

    function setDefaultOperator(address op, bool onlyDefault) external onlyOwner {
        defaultOperator     = op;          // 可为 0：只在 onlyDefault=false 下允许外部传入
        onlyDefaultOperator = onlyDefault; // true 则强制使用 defaultOperator
        emit DefaultOperatorSet(op, onlyDefault);
    }

    /* ========== Pair：创建 / 初始化 / 改费率 / 查询 ========== */

    function createPair(address tokenOther, uint16 feeBps) external onlyOwner returns (address pair) {
        require(pairForToken[tokenOther] == address(0), "PAIR_EXISTS");
        require(pairImplementation != address(0) && dlToken != address(0), "impl/dl=0");
        require(tokenOther != address(0) && tokenOther != dlToken, "bad token");
        require(feeBps <= 1000, "fee>1000");

        pair = pairImplementation.clone();
        require(pair != address(0), "PAIR_CLONE_ERR");
        IDealPairInit(pair).initialize(dlToken, tokenOther, address(this), feeBps);
        emit PairCreated(pair, tokenOther, feeBps);

        pairForToken[tokenOther] = pair;
        emit PairMapped(tokenOther, pair);
    }

    function initPair(address pair) external onlyOwner returns (uint amountDL, uint amountOther) {
        (amountDL, amountOther) = IDealPairInit(pair).mintInitial();
    }

    function setPairFeeBps(address pair, uint16 newFee) external onlyOwner {
        IDealPairInit(pair).setFeeBps(newFee);
        emit PairFeeUpdated(pair, newFee);
    }

    /// @notice Deal 模板在 setLegs 时会传“规范化后的 OTHER”（NATIVE→WNATIVE），这里也做一次同样的规范化以兼容外部查询。
    function getPair(address token) external view returns (address) {
        address t = (token == address(0)) ? wrappedNative : token;
        return pairForToken[t];
    }

    function isTokenSupported(address token) external view returns (bool) {
        address t = (token == address(0)) ? wrappedNative : token;
        return pairForToken[t] != address(0);
    }

    /* ========== Deal：创建（仅 clone + initialize(StaticConfig)） ========== */

    struct CreateParams {
        string  title;               // 标题
        address operator;            // 建议传代理者合约地址；若 onlyDefaultOperator=true 则忽略此字段
        uint64  voteTimeoutSeconds;  // 投票超时（需 >= minTimeoutSeconds）
        // 未来若要扩展，可在此加字段；但当前模板只需要上面三项
    }

    function createDeal(CreateParams calldata p) external returns (address deal) {
        require(dealImplementation != address(0), "impl=0");
        require(dlToken != address(0) && wrappedNative != address(0) && treasury != address(0), "globals=0");
        require(bytes(p.title).length > 0, "title");
        require(p.voteTimeoutSeconds >= minTimeoutSeconds, "timeout<min");

        address op = onlyDefaultOperator ? defaultOperator : p.operator;
        require(op != address(0), "operator=0");

        deal = dealImplementation.clone();
        require(deal != address(0), "DEAL_CLONE_ERR");

        IDealTemplate.StaticConfig memory cfg = IDealTemplate.StaticConfig({
            title:               p.title,
            operator:            op,
            factory:             address(this),
            dl:                  dlToken,
            WNATIVE:             wrappedNative,
            treasury:            treasury,
            feePermille:         defaultFeePermille,
            specialNoFeeToken:   specialNoFeeToken,
            voteTimeoutSeconds:  p.voteTimeoutSeconds
        });

        IDealTemplate(deal).initialize(cfg);

        emit DealCreated(deal, op, p.title, p.voteTimeoutSeconds);
    }
}
