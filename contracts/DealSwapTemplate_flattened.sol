
// File: deal/contracts/interfaces/IERC20.sol


pragma solidity ^0.8.26;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address who) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}
// File: deal/contracts/utils/SafeTransfer.sol


pragma solidity ^0.8.26;


library SafeTransfer {
    error SafeTransferFailed();
    error SafeTransferFromFailed();
    error SafeApproveFailed();

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        (bool ok, bytes memory data) =
            address(token).call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert SafeTransferFailed();
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        (bool ok, bytes memory data) = address(token).call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value)
        );
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert SafeTransferFromFailed();
    }

    /// 可选：安全 approve（注意前置将额度清零或只做“调大/调小”以避免竞态）
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        (bool ok, bytes memory data) =
            address(token).call(abi.encodeWithSelector(IERC20.approve.selector, spender, value));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert SafeApproveFailed();
    }
}

// File: deal/contracts/utils/ReentrancyGuard.sol


pragma solidity ^0.8.26;

/// @title Minimal ReentrancyGuard
/// @notice 与 OpenZeppelin 语义一致：nonReentrant 不能嵌套；建议只标注在 external/public 函数上
abstract contract ReentrancyGuard {
    uint256 private _entered;

    modifier nonReentrant() {
        require(_entered == 0, "REENTRANCY");
        _entered = 1;
        _;
        _entered = 0;
    }
}

// File: @openzeppelin/contracts/proxy/utils/Initializable.sol


// OpenZeppelin Contracts (last updated v5.3.0) (proxy/utils/Initializable.sol)

pragma solidity ^0.8.20;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```solidity
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 *
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Storage of the initializable contract.
     *
     * It's implemented on a custom ERC-7201 namespace to reduce the risk of storage collisions
     * when using with upgradeable contracts.
     *
     * @custom:storage-location erc7201:openzeppelin.storage.Initializable
     */
    struct InitializableStorage {
        /**
         * @dev Indicates that the contract has been initialized.
         */
        uint64 _initialized;
        /**
         * @dev Indicates that the contract is in the process of being initialized.
         */
        bool _initializing;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    /**
     * @dev The contract is already initialized.
     */
    error InvalidInitialization();

    /**
     * @dev The contract is not initializing.
     */
    error NotInitializing();

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint64 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that in the context of a constructor an `initializer` may be invoked any
     * number of times. This behavior in the constructor can be useful during testing and is not expected to be used in
     * production.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        // Cache values to avoid duplicated sloads
        bool isTopLevelCall = !$._initializing;
        uint64 initialized = $._initialized;

        // Allowed calls:
        // - initialSetup: the contract is not in the initializing state and no previous version was
        //                 initialized
        // - construction: the contract is initialized at version 1 (no reinitialization) and the
        //                 current contract is just being deployed
        bool initialSetup = initialized == 0 && isTopLevelCall;
        bool construction = initialized == 1 && address(this).code.length == 0;

        if (!initialSetup && !construction) {
            revert InvalidInitialization();
        }
        $._initialized = 1;
        if (isTopLevelCall) {
            $._initializing = true;
        }
        _;
        if (isTopLevelCall) {
            $._initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: Setting the version to 2**64 - 1 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint64 version) {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing || $._initialized >= version) {
            revert InvalidInitialization();
        }
        $._initialized = version;
        $._initializing = true;
        _;
        $._initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        _checkInitializing();
        _;
    }

    /**
     * @dev Reverts if the contract is not in an initializing state. See {onlyInitializing}.
     */
    function _checkInitializing() internal view virtual {
        if (!_isInitializing()) {
            revert NotInitializing();
        }
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing) {
            revert InvalidInitialization();
        }
        if ($._initialized != type(uint64).max) {
            $._initialized = type(uint64).max;
            emit Initialized(type(uint64).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint64) {
        return _getInitializableStorage()._initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _getInitializableStorage()._initializing;
    }

    /**
     * @dev Pointer to storage slot. Allows integrators to override it with a custom storage location.
     *
     * NOTE: Consider following the ERC-7201 formula to derive storage locations.
     */
    function _initializableStorageSlot() internal pure virtual returns (bytes32) {
        return INITIALIZABLE_STORAGE;
    }

    /**
     * @dev Returns a pointer to the storage namespace.
     */
    // solhint-disable-next-line var-name-mixedcase
    function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
        bytes32 slot = _initializableStorageSlot();
        assembly {
            $.slot := slot
        }
    }
}

// File: deal/contracts/DealSwapTemplate.sol


pragma solidity ^0.8.26;

/// ===== Minimal IERC20 =====


/// ===== DL must be burnable =====
interface IDLBurnable is IERC20 { function burn(uint256 value) external; }

/// ===== SafeTransfer =====


/// ===== Minimal ReentrancyGuard =====


/// ===== Initializable =====


contract DealSwapTemplate is Initializable, ReentrancyGuard {
    using SafeTransfer for IERC20;

    /* ---------------- Storage (initialize 设置) ---------------- */
    address public factory; // 仅此地址可做初始化、调费率等治理操作
    address public token0;  // DL
    address public token1;  // OTHER

    uint256 public token1BalanceInit; // 系统初始化默认token1的余额

    /* ---------------- Reserves / TWAP ---------------- */
    uint112 private reserve0; // DL
    uint112 private reserve1; // OTHER
    uint32  private blockTimestampLast;

    // TWAP cumulatives (UQ112x112)
    uint256 public price0CumulativeLast; // token1/token0
    uint256 public price1CumulativeLast; // token0/token1

    /* ---------------- Params ---------------- */
    // fee (DL-side, as num/den) —— 由 Factory 管理
    uint32  public feeNum;
    uint32  public feeDen;
    bool    public liquidityInited;

    /* ---------------- Events ---------------- */
    event FeeChanged(uint32 oldNum, uint32 oldDen, uint32 newNum, uint32 newDen);
    event Sync(uint112 reserve0, uint112 reserve1);
    event MintInitial(uint256 amountDL, uint256 amountOther);
    event MintOtherOnly(uint256 amountOther);
    event DustPurged(uint256 dlAmount);
    event FeeBurned(uint256 dlAmount);

    // amount0In/Out 表示 DL，amount1In/Out 表示 OTHER，amount0OutNet（仅买 DL 时有意义）
    event Swap(
        address indexed sender,
        uint256 amount0In,        // DL in
        uint256 amount1In,        // OTHER in
        uint256 amount0OutGross,  // DL out (gross)
        uint256 amount0OutNet,    // DL out (net = gross - feeOut)
        uint256 amount1OutGross,  // OTHER out (net)
        address indexed to
    );

    /* ---------------- Modifiers ---------------- */
    modifier onlyFactory() {
        require(msg.sender == factory, "NOT_FACTORY");
        _;
    }

    /* ---------------- initialize ---------------- */
    function initialize(
        address dlToken,
        address otherToken,
        address factory_,
        uint32  feeNum_,
        uint32  feeDen_
    ) external initializer {
        require(dlToken != address(0) && otherToken != address(0), "ZERO_ADDR");
        require(dlToken != otherToken, "IDENTICAL_ADDR");
        require(factory_ != address(0), "ZERO_FACTORY");
        require(feeDen_ > 0 && feeNum_ < feeDen_, "BAD_FEE");

        token0  = dlToken;
        token1  = otherToken;
        factory = factory_;
        feeNum  = feeNum_;
        feeDen  = feeDen_;
    }

    /* ---------------- Views ---------------- */
    function getReserves() public view returns (uint112 _r0, uint112 _r1, uint32 _ts) {
        _r0 = reserve0; _r1 = reserve1; _ts = blockTimestampLast;
    }
    function getPriceCumulatives() external view returns (uint256 p0Cum, uint256 p1Cum, uint32 ts) {
        return (price0CumulativeLast, price1CumulativeLast, blockTimestampLast);
    }
    function token1Balance() public view returns (uint256) {
        return IERC20(token1).balanceOf(address(this)) + token1BalanceInit;
    }

    /* ---------------- Internal math ---------------- */
    function _ceilDiv(uint256 a, uint256 b) private pure returns (uint256) {
        return (a + b - 1) / b;
    }

    /* ---------------- Quotes (front-end helpers) ---------------- */

    function quoteBuyGivenGross(uint256 amount0OutGross)
        external view
        returns (uint256 in1Min, uint256 feeOut, uint256 out0Net)
    {
        require(liquidityInited, "NOT_INIT");
        (uint112 r0, uint112 r1,) = getReserves();
        require(amount0OutGross > 0 && amount0OutGross < r0, "BAD_GROSS");

        // in1_min = ceil(r1 * gross / (r0 - gross))
        uint256 denom = uint256(r0) - amount0OutGross;
        in1Min = _ceilDiv(uint256(r1) * amount0OutGross, denom);

        feeOut = (amount0OutGross * feeNum) / feeDen; // floor
        out0Net = amount0OutGross - feeOut;
    }

    function quoteBuyGivenNet(uint256 out0NetTarget)
        external view
        returns (uint256 grossMin, uint256 feeOut, uint256 in1Min)
    {
        require(liquidityInited, "NOT_INIT");
        (uint112 r0, uint112 r1,) = getReserves();
        require(out0NetTarget > 0 && out0NetTarget < r0, "BAD_NET");

        uint256 denom = uint256(feeDen) - feeNum; // >0
        grossMin = _ceilDiv(out0NetTarget * feeDen, denom); // ceil
        feeOut = (grossMin * feeNum) / feeDen;
        if (grossMin - feeOut < out0NetTarget) {
            unchecked { grossMin += 1; }
            feeOut = (grossMin * feeNum) / feeDen;
        }
        require(grossMin < r0, "INSUFFICIENT_LIQ");

        // in1_min = ceil(r1 * grossMin / (r0 - grossMin))
        uint256 d = uint256(r0) - grossMin;
        in1Min = _ceilDiv(uint256(r1) * grossMin, d);
    }

    function quoteBuyGivenIn1(uint256 amount1In)
        external view
        returns (uint256 grossMax, uint256 feeOut, uint256 out0Net)
    {
        require(liquidityInited, "NOT_INIT");
        (uint112 r0, uint112 r1,) = getReserves();
        require(amount1In > 0, "ZERO_IN");

        grossMax = (uint256(r0) * amount1In) / (uint256(r1) + amount1In); // floor
        require(grossMax < r0, "INSUFFICIENT_LIQ");
        require(grossMax > 0, "INSUFFICIENT_IN");

        feeOut = (grossMax * feeNum) / feeDen; // floor
        out0Net = grossMax - feeOut;
    }

    function quoteSell(uint256 amount0In)
        external view
        returns (uint256 feeIn, uint256 out1)
    {
        require(liquidityInited, "NOT_INIT");
        (uint112 r0, uint112 r1,) = getReserves();
        require(amount0In > 0, "ZERO_IN");

        feeIn = (amount0In * feeNum) / feeDen;
        uint256 in0Eff = amount0In - feeIn;
        out1 = (uint256(r1) * in0Eff) / (uint256(r0) + in0Eff); // floor
    }

    function quoteSellGivenOut1(uint256 out1Target)
        external view
        returns (uint256 in0Min, uint256 feeIn, uint256 in0EffMin)
    {
        require(liquidityInited, "NOT_INIT");
        (uint112 r0, uint112 r1,) = getReserves();
        require(out1Target > 0 && out1Target < r1, "BAD_OUT");

        // 有效输入（已扣费）下限：ceil(r0 * out1 / (r1 - out1))
        uint256 denom = uint256(r1) - out1Target;
        in0EffMin = _ceilDiv(uint256(r0) * out1Target, denom);

        // 把有效输入还原成毛输入（考虑 fee 向下取整，做一次校正）
        uint256 denom2 = uint256(feeDen) - feeNum; // >0
        in0Min = _ceilDiv(in0EffMin * feeDen, denom2);
        feeIn  = (in0Min * feeNum) / feeDen;
        if (in0Min - feeIn < in0EffMin) {
            unchecked { in0Min += 1; }
            feeIn = (in0Min * feeNum) / feeDen;
        }
    }

    /* ---------------- Governance (Factory only) ---------------- */
    function setFactory(address f) external onlyFactory {
        factory = f;
    }

    /// Factory 调整本 Pair 的手续费
    function setFee(uint32 newNum, uint32 newDen) external onlyFactory {
        require(newDen > 0 && newNum < newDen, "BAD_FEE");
        emit FeeChanged(feeNum, feeDen, newNum, newDen);
        feeNum = newNum;
        feeDen = newDen;
    }

    /// 由 Factory 完成初始化（需先把 DL 与 OTHER 转入本合约）
    function mintInitial(uint256 _b1) external nonReentrant onlyFactory returns (uint amountDL, uint amountOther) {
        require(!liquidityInited, "ALREADY_INIT");

        token1BalanceInit = _b1;

        (uint112 r0, uint112 r1,) = getReserves(); // 预期(0,0)，但用差值更稳
        uint256 b0 = IERC20(token0).balanceOf(address(this));
        uint256 b1 = token1Balance();

        amountDL    = b0 - r0;
        amountOther = b1 - r1;
        require(amountDL > 0 && amountOther > 0, "NEED_BOTH_SIDES");

        liquidityInited = true;
        _updateReserves();
        emit MintInitial(amountDL, amountOther);
    }

    /* ---------------- Liquidity (Deal only) ---------------- */
    function mintOtherOnly() external nonReentrant returns (uint amountOther) {
        require(liquidityInited, "NOT_INIT");

        (uint112 r0, uint112 r1,) = getReserves();

        // 1) 自动清灰（burn 储备之外多余的 DL）
        uint256 b0Pre = IERC20(token0).balanceOf(address(this));
        if (b0Pre > r0) {
            uint256 extraDL = b0Pre - r0;
            IDLBurnable(token0).burn(extraDL);
            emit DustPurged(extraDL);
        }

        // 2) 仅按 OTHER 净流入增储
        uint256 b1 = token1Balance();
        uint256 in1 = b1 - r1;
        require(in1 > 0, "NO_OTHER_IN");

        amountOther = in1;

        // 3) 刷新储备（含 TWAP 累积）
        _updateReserves();
        emit MintOtherOnly(amountOther);
    }

    /* ---------------- Swap (public) ---------------- */
    function swap(uint256 amount0OutGross, uint256 amount1OutGross, address to)
        external
        nonReentrant
    {
        require(liquidityInited, "NOT_INIT");
        require(to != address(0), "ZERO_TO");
        require(to != token0 && to != token1 && to != address(this), "INVALID_TO");
        require(amount0OutGross > 0 || amount1OutGross > 0, "ZERO_OUT");
        require(amount0OutGross == 0 || amount1OutGross == 0, "ONE_SIDE_ONLY");

        (uint112 r0, uint112 r1,) = getReserves();
        require(amount0OutGross < r0 && amount1OutGross < r1, "INSUFFICIENT_LIQ");

        // ======= 买 DL（OTHER -> DL）路径 =======
        if (amount0OutGross > 0) {
            // 1) 买前清灰 DL（防止外部预存 DL 被当作输入或纳入储备）
            {
                uint256 b0Pre = IERC20(token0).balanceOf(address(this));
                if (b0Pre > r0) {
                    uint256 dust = b0Pre - r0;
                    IDLBurnable(token0).burn(dust);
                    emit DustPurged(dust);
                }
            }

            // 2) 计算输出净额与手续费，转出净额并燃烧手续费
            uint256 dlOutFee = (amount0OutGross * feeNum) / feeDen;
            uint256 out0Net  = amount0OutGross - dlOutFee;

            if (out0Net > 0) IERC20(token0).safeTransfer(to, out0Net);
            if (dlOutFee > 0) {
                IDLBurnable(token0).burn(dlOutFee);
                emit FeeBurned(dlOutFee);
            }

            // 3) 反推输入（余额差）
            uint256 b0 = IERC20(token0).balanceOf(address(this));
            uint256 b1 = token1Balance();
            uint256 in0 = b0 > r0 - amount0OutGross ? b0 - (r0 - amount0OutGross) : 0; // DL in（通常为0）
            uint256 in1 = b1 > r1 ? b1 - r1 : 0;                                       // OTHER in
            require(in0 > 0 || in1 > 0, "INSUFFICIENT_INPUT");

            // 4) 溢出防护 + K 校验（按真实余额）
            require(b0 <= type(uint112).max && b1 <= type(uint112).max, "OVERFLOW");
            require(b0 * b1 >= uint256(r0) * uint256(r1), "K");

            _updateReserves();
            emit Swap(msg.sender, in0, in1, amount0OutGross, out0Net, 0, to);
            return;
        }

        // ======= 卖 DL（DL -> OTHER）路径 =======
        {
            // 1) 先转出 OTHER（exact-out 风格）
            IERC20(token1).safeTransfer(to, amount1OutGross);

            // 2) 反推输入（余额差）
            uint256 b0 = IERC20(token0).balanceOf(address(this));
            uint256 b1 = token1Balance();
            uint256 in0 = b0 > r0 ? b0 - r0 : 0;                                       // DL in
            uint256 in1 = b1 > r1 - amount1OutGross ? b1 - (r1 - amount1OutGross) : 0; // OTHER in（通常为0）
            require(in0 > 0 || in1 > 0, "INSUFFICIENT_INPUT");

            // 3) 对 DL 输入扣费并燃烧，再用净额参与 K 校验
            uint256 feeIn = (in0 * feeNum) / feeDen;
            if (feeIn > 0) {
                IDLBurnable(token0).burn(feeIn);
                emit FeeBurned(feeIn);
                unchecked { b0 -= feeIn; }
            }

            // 4) 溢出防护 + K 校验（按真实余额）
            require(b0 <= type(uint112).max && b1 <= type(uint112).max, "OVERFLOW");
            require(b0 * b1 >= uint256(r0) * uint256(r1), "K");

            _updateReserves();
            emit Swap(msg.sender, in0, in1, 0, 0, amount1OutGross, to);
            return;
        }
    }

    function sync() external nonReentrant {
        (uint112 r0,,) = getReserves();
        uint256 b0 = IERC20(token0).balanceOf(address(this));
        if (b0 > r0) {
            uint256 extra = b0 - r0;
            IDLBurnable(token0).burn(extra);
            emit DustPurged(extra);
        }
        _updateReserves();
    }

    /* ---------------- internal ---------------- */
    function _updateReserves() internal {
        uint256 b0 = IERC20(token0).balanceOf(address(this));
        uint256 b1 = token1Balance();
        require(b0 <= type(uint112).max && b1 <= type(uint112).max, "OVERFLOW");

        uint32 ts = uint32(block.timestamp);
        uint32 elapsed = ts - blockTimestampLast; // uint32 wrap-safe

        if (elapsed > 0 && reserve0 != 0 && reserve1 != 0) {
            unchecked {
                // UQ112x112 prices
                uint256 price0 = (uint256(uint224(reserve1)) << 112) / reserve0; // token1/token0
                uint256 price1 = (uint256(uint224(reserve0)) << 112) / reserve1; // token0/token1
                price0CumulativeLast += price0 * elapsed;
                price1CumulativeLast += price1 * elapsed;
            }
        }

        reserve0 = uint112(b0);
        reserve1 = uint112(b1);
        blockTimestampLast = ts;
        emit Sync(reserve0, reserve1);
    }
}
