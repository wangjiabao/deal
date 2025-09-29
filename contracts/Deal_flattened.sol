
// File: @openzeppelin/contracts/token/ERC20/IERC20.sol


// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/IERC20.sol)

pragma solidity >=0.4.16;

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// File: @openzeppelin/contracts/utils/introspection/IERC165.sol


// OpenZeppelin Contracts (last updated v5.4.0) (utils/introspection/IERC165.sol)

pragma solidity >=0.4.16;

/**
 * @dev Interface of the ERC-165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[ERC].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// File: @openzeppelin/contracts/token/ERC721/IERC721.sol


// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC721/IERC721.sol)

pragma solidity >=0.6.2;


/**
 * @dev Required interface of an ERC-721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
     *   a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC-721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must have been allowed to move this token by either {approve} or
     *   {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
     *   a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Note that the caller is responsible to confirm that the recipient is capable of receiving ERC-721
     * or else they may be permanently lost. Usage of {safeTransferFrom} prevents loss, though the caller must
     * understand this adds an external call which potentially creates a reentrancy vulnerability.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the address zero.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

// File: @openzeppelin/contracts/interfaces/IERC20.sol


// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC20.sol)

pragma solidity >=0.4.16;


// File: @openzeppelin/contracts/interfaces/IERC165.sol


// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC165.sol)

pragma solidity >=0.4.16;


// File: @openzeppelin/contracts/interfaces/IERC1363.sol


// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC1363.sol)

pragma solidity >=0.6.2;



/**
 * @title IERC1363
 * @dev Interface of the ERC-1363 standard as defined in the https://eips.ethereum.org/EIPS/eip-1363[ERC-1363].
 *
 * Defines an extension interface for ERC-20 tokens that supports executing code on a recipient contract
 * after `transfer` or `transferFrom`, or code on a spender contract after `approve`, in a single transaction.
 */
interface IERC1363 is IERC20, IERC165 {
    /*
     * Note: the ERC-165 identifier for this interface is 0xb0202a11.
     * 0xb0202a11 ===
     *   bytes4(keccak256('transferAndCall(address,uint256)')) ^
     *   bytes4(keccak256('transferAndCall(address,uint256,bytes)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256,bytes)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256,bytes)'))
     */

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @param data Additional data with no specified format, sent in call to `spender`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value, bytes calldata data) external returns (bool);
}

// File: @openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol


// OpenZeppelin Contracts (last updated v5.3.0) (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.20;



/**
 * @title SafeERC20
 * @dev Wrappers around ERC-20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    /**
     * @dev An operation with an ERC-20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Variant of {safeTransfer} that returns a bool instead of reverting if the operation is not successful.
     */
    function trySafeTransfer(IERC20 token, address to, uint256 value) internal returns (bool) {
        return _callOptionalReturnBool(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Variant of {safeTransferFrom} that returns a bool instead of reverting if the operation is not successful.
     */
    function trySafeTransferFrom(IERC20 token, address from, address to, uint256 value) internal returns (bool) {
        return _callOptionalReturnBool(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `requestedDecrease`. If `token` returns no
     * value, non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeDecreaseAllowance(IERC20 token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     *
     * NOTE: If the token implements ERC-7674, this function will not modify any temporary allowance. This function
     * only sets the "standard" allowance. Any temporary allowance will remain active, in addition to the value being
     * set here.
     */
    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeCall(token.approve, (spender, value));

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeCall(token.approve, (spender, 0)));
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Performs an {ERC1363} transferAndCall, with a fallback to the simple {ERC20} transfer if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            safeTransfer(token, to, value);
        } else if (!token.transferAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} transferFromAndCall, with a fallback to the simple {ERC20} transferFrom if the target
     * has no code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferFromAndCallRelaxed(
        IERC1363 token,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (to.code.length == 0) {
            safeTransferFrom(token, from, to, value);
        } else if (!token.transferFromAndCall(from, to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} approveAndCall, with a fallback to the simple {ERC20} approve if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * NOTE: When the recipient address (`to`) has no code (i.e. is an EOA), this function behaves as {forceApprove}.
     * Opposedly, when the recipient address (`to`) has code, this function only attempts to call {ERC1363-approveAndCall}
     * once without retrying, and relies on the returned value to be true.
     *
     * Reverts if the returned value is other than `true`.
     */
    function approveAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            forceApprove(token, to, value);
        } else if (!token.approveAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturnBool} that reverts if call fails to meet the requirements.
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            let success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            // bubble errors
            if iszero(success) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        if (returnSize == 0 ? address(token).code.length == 0 : returnValue != 1) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silently catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        bool success;
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            returnSize := returndatasize()
            returnValue := mload(0)
        }
        return success && (returnSize == 0 ? address(token).code.length > 0 : returnValue == 1);
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

// File: @openzeppelin/contracts/security/ReentrancyGuard.sol


// OpenZeppelin Contracts (last updated v4.9.0) (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }
}

// File: deal/contracts/Deal.sol


pragma solidity ^0.8.26;






/* ---------- 工厂侧接口（最小化） ---------- */
interface IFactoryMinter { function mintDL(address to, uint256 amount) external; }
interface IFactoryTwap   { function updateAndQuoteToDL(address pair, uint256 amountIn) external returns (uint256 dlOut); }
interface IFactoryIndex {
    function onCreated(address creator, bool trackCreator) external;
    function onJoined(address participant, bool trackParticipant) external;
    function onParticipantRemoved(address prevParticipant) external;
    function onAbandoned(address creator, address prevParticipant) external;
    function onClosedFor(address user) external;

    // 仅在 Completed 时写入 “完成热索引 ring”
    function onCompletedFor(address user) external;
}
interface IFactoryInfo {
    function infoAddMinted(uint256 tokenId, uint256 amount) external;
    function infoSetMaxPartnerOf(uint256 tokenId, uint256 partnerTokenId) external;
}
/* 通过 Factory 锁/解锁 InfoNFT（仅 Deal 可调） */
interface IFactoryLock {
    function infoLock(uint256 tokenId, address holder) external;
    function infoUnlock(uint256 tokenId) external;
}

interface IWNATIVE is IERC20 { function deposit() external payable; function withdraw(uint256) external; }
interface IDLBurnFrom { function burnFrom(address account, uint256 amount) external; }

/* ---------- DealInfoNFT（只读） ---------- */
interface IDealInfoNFTView {
    function totalMintedOf(uint256 tokenId) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function maxPartnerOf(uint256 tokenId) external view returns (uint256);
}

/* ========================================================== */
contract Deal is Initializable, ReentrancyGuard {
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

    // 门禁 & NFT（仅锁引用）
    uint256 public gateNftId;
    uint256 public aNftId;
    uint256 public bNftId;
    bool    public aNftLocked;
    bool    public bNftLocked;

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
    uint64 public aAt; uint64 public bAt;
    Vote   public aVote;     Vote   public bVote;

    // 兼容旧逻辑（自动结算后置 true）
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

    // 手续费/奖励比例
    uint32  public feeNonDLNum;    uint32 public feeNonDLDen;
    uint32  public mintOnFeesNum;  uint32  public mintOnFeesDen;
    address public specialNoFeeToken;

    bool private _trackA;
    bool private _trackBActive;

    /* ===== 留言计费 ===== */
    bool    public msgPriceEnabled;
    address public msgPriceTokenNorm;
    address public msgPricePair;
    uint256 public msgPriceAmountInToken;

    /* ===== 留言存储 ===== */
    string[]  private _msgContents;
    uint64[]  private _msgTimes;
    address[] private _msgSenders;

    /* 事件 */
    event Initialized(address indexed initiator, address indexed factory);
    event Joined(address indexed b, bool nftLockedB);
    event Locked();
    event Completed(CompletionReason reason);
    event Canceled();
    event Claimed(address indexed who, address swapToken, uint256 swapAmt, address marginToken, uint256 marginAmt);
    event FeesProcessed(address indexed tokenA, uint256 aFee, address indexed tokenB, uint256 bFee);
    event RewardsMinted(address indexed a, uint256 toA, address indexed b, uint256 toB, address indexed cAddr, uint256 toC);

    event MessagePosted(address indexed from, uint256 indexed idx, uint64 ts, string content);
    event MessageFeeCharged(address indexed from, uint256 dlBurned, address indexed tokenNorm, uint256 tokenAmount);

    modifier onlyA()  { require(msg.sender == a, "ONLY_A"); _; }
    modifier onlyAB() { require(msg.sender == a || msg.sender == b, "ONLY_AB"); _; }
    modifier inState(Status s) { require(status == s, "BAD_STATE"); _; }

    /* ------------ 初始化 ------------ */
    struct InitParams {
        address aSwapToken;   uint256 aSwapAmount;
        address aMarginToken; uint256 aMarginAmount;
        address bSwapToken;   uint256 bSwapAmount;
        address bMarginToken; uint256 bMarginAmount;
        uint8   joinMode;     address expectedB;
        uint256 gateNftId;
        uint256 aNftId;
        string  title;        uint64  timeoutSeconds;
    }
    struct ConfigParams {
        address dl;           address infoNft;     address treasury; address WNATIVE;
        address aTokenNorm;   address bTokenNorm;  address aPair;    address bPair;
        uint32  feeNonDLNum;  uint32 feeNonDLDen;
        uint32  mintOnFeesNum; uint32 mintOnFeesDen;
        address specialNoFeeToken;
        bool    trackCreator;
        bool    msgPriceEnabled; address msgPriceTokenNorm; address msgPricePair; uint256 msgPriceAmountInToken;
    }

    function initialize(address _factory, address _initiator, InitParams calldata p, ConfigParams calldata c)
        external initializer
    {
        require(_factory != address(0) && _initiator != address(0), "ZERO");
        require(p.timeoutSeconds > 0, "TIMEOUT");
        require(c.dl != address(0) && c.WNATIVE != address(0), "DL/WNATIVE");

        factory = _factory; a = _initiator;
        dl=c.dl; infoNft=c.infoNft; treasury=c.treasury; WNATIVE=c.WNATIVE;
        aTokenNorm=c.aTokenNorm; bTokenNorm=c.bTokenNorm; aPair=c.aPair; bPair=c.bPair;
        feeNonDLNum=c.feeNonDLNum; feeNonDLDen=c.feeNonDLDen; mintOnFeesNum=c.mintOnFeesNum; mintOnFeesDen=c.mintOnFeesDen;
        require(feeNonDLDen>0 && feeNonDLNum<feeNonDLDen, "FEE_RATIO");
        require(mintOnFeesDen>0 && mintOnFeesNum<mintOnFeesDen, "MINT_RATIO");
        specialNoFeeToken=c.specialNoFeeToken;

        msgPriceEnabled=c.msgPriceEnabled; msgPriceTokenNorm=c.msgPriceTokenNorm;
        msgPricePair=c.msgPricePair; msgPriceAmountInToken=c.msgPriceAmountInToken;

        aSwapToken=p.aSwapToken; aSwapAmount=p.aSwapAmount; aMarginToken=p.aMarginToken; aMarginAmount=p.aMarginAmount;
        bSwapToken=p.bSwapToken; bSwapAmount=p.bSwapAmount; bMarginToken=p.bMarginToken; bMarginAmount=p.bMarginAmount;

        require(p.joinMode <= uint8(JoinMode.NftGated), "JOIN_MODE");
        joinMode  = JoinMode(p.joinMode);
        expectedB = p.expectedB;

        gateNftId = p.gateNftId;
        aNftId    = p.aNftId;
        bNftId    = 0;

        title=p.title; timeoutSeconds=p.timeoutSeconds;

        status = Status.Ready;

        _lockNftForAIfAny();

        address aNorm = (aSwapToken == NATIVE) ? WNATIVE : aSwapToken;
        address bNorm = (bSwapToken == NATIVE) ? WNATIVE : bSwapToken;
        require(aNorm == aTokenNorm && bNorm == bTokenNorm, "TOKEN_NORM_MISMATCH");

        _trackA = c.trackCreator;
        if (_trackA) IFactoryIndex(factory).onCreated(a, true);

        emit Initialized(a, factory);
    }

    /* ======================= 留言 ======================= */
    function postMessage(string calldata content) external nonReentrant onlyAB returns (uint256 idx) {
        require(bytes(content).length > 0, "EMPTY");
        _chargeMessageFee(msg.sender);
        uint64 ts = uint64(block.timestamp);
        _msgContents.push(content); _msgTimes.push(ts); _msgSenders.push(msg.sender);
        idx = _msgContents.length - 1;
        emit MessagePosted(msg.sender, idx, ts, content);
    }
    function getMessages(uint256 offset, uint256 limit)
        external view returns (string[] memory contents, uint64[] memory times, address[] memory senders)
    {
        uint256 len = _msgContents.length;
        if (offset >= len) return (new string[](0), new uint64[](0), new address[](0));
        uint256 end = offset + limit; if (end > len) end = len; uint256 n = end - offset;
        contents = new string[](n); times = new uint64[](n); senders = new address[](n);
        for (uint256 i=0; i<n; ++i) { contents[i]=_msgContents[offset+i]; times[i]=_msgTimes[offset+i]; senders[i]=_msgSenders[offset+i]; }
    }
    function messagesCount() external view returns (uint256) { return _msgContents.length; }

    function _chargeMessageFee(address payer) internal {
        if (!msgPriceEnabled || msgPriceAmountInToken == 0) return;
        uint256 dlNeed = (msgPriceTokenNorm == dl)
            ? msgPriceAmountInToken
            : _quoteAggToDL(msgPriceTokenNorm, msgPricePair, msgPriceAmountInToken);
        if (dlNeed > 0) IDLBurnFrom(dl).burnFrom(payer, dlNeed);
        emit MessageFeeCharged(payer, dlNeed, msgPriceTokenNorm, msgPriceAmountInToken);
    }

    /* ========== A：改四数 / 废弃 ========== */
    function updateAmounts(uint256 _aSwapAmount, uint256 _aMarginAmount, uint256 _bSwapAmount, uint256 _bMarginAmount)
        external onlyA inState(Status.Ready)
    { aSwapAmount=_aSwapAmount; aMarginAmount=_aMarginAmount; bSwapAmount=_bSwapAmount; bMarginAmount=_bMarginAmount; }

    function abandonByA() external nonReentrant onlyA {
        require(status == Status.Ready || status == Status.Active);
        address prevB = b;

        _refundAllToParties();

        _unlockNftIfLocked(true);
        _unlockNftIfLocked(false);
        bNftId = 0;

        if (_trackA && _trackBActive) IFactoryIndex(factory).onAbandoned(a, prevB);
        else if (_trackA)             IFactoryIndex(factory).onAbandoned(a, address(0));
        else if (_trackBActive)       IFactoryIndex(factory).onParticipantRemoved(prevB);
        _trackA=false; _trackBActive=false;

        status = Status.Abandoned;
    }

    /* ========== B：进入 ========== */
    function join(uint256 optId, bool trackMe) external nonReentrant inState(Status.Ready) {
        require(b == address(0));
        require(a != msg.sender, "is a");
        if (joinMode == JoinMode.NftGated) {
            require(gateNftId != 0, "GATE_ID_0");
            require(IERC721(infoNft).ownerOf(gateNftId) == msg.sender, "not nft owner");
            b = msg.sender; bNftId = gateNftId;
        } else {
            if (joinMode == JoinMode.ExactAddress) require(msg.sender == expectedB, "not expectedB");
            b = msg.sender;
            if (optId > 0) {
                require(IERC721(infoNft).ownerOf(optId) == msg.sender, "not nft owner");
                bNftId = optId;
            }
        }

        _lockNftForBIfAny();
        
        _trackBActive = trackMe;
        if (_trackBActive) IFactoryIndex(factory).onJoined(b, true);
        status = Status.Active;
        emit Joined(b, bNftLocked);
        _tryLock();
    }

    /* ========== Active：支付 / 撤回 / 退出 / 踢人 ========== */
    function pay() external payable nonReentrant inState(Status.Active) onlyAB {
        if (msg.sender == a) {
            require(!aPaid);
            require(msg.value == nativeRequiredForA(), "NATIVE_NEQ_A");
            if (aSwapToken   != NATIVE) _pullExactERC20(IERC20(aSwapToken), aSwapAmount, msg.sender);
            if (aMarginToken != NATIVE) _pullExactERC20(IERC20(aMarginToken), aMarginAmount, msg.sender);
            if (aSwapAmount > 0 || aMarginAmount > 0) aPaid = true;
        } else {
            require(b != address(0) && !bPaid);
            require(msg.value == nativeRequiredForB(), "NATIVE_NEQ_B");
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
        _refundFundsA(); _refundFundsB();
        _unlockNftIfLocked(false);
        bNftId = 0;
        if (_trackBActive) { IFactoryIndex(factory).onParticipantRemoved(prevB); _trackBActive = false; }
        b = address(0); status = Status.Ready;
    }

    function kickBByA() external nonReentrant onlyA inState(Status.Active) {
        address prevB = b;
        _refundFundsA(); _refundFundsB();
        _unlockNftIfLocked(false);
        bNftId = 0;
        if (_trackBActive) { IFactoryIndex(factory).onParticipantRemoved(prevB); _trackBActive = false; }
        b = address(0); status = Status.Ready;
    }

    /* ========== Locked：投票 / 强制完成 / 取消 ========== */
    function setMyVote(Vote v) external nonReentrant inState(Status.Locked) onlyAB {
        require(v == Vote.Accept || v == Vote.Reject, "V_UNSET");
        if (msg.sender == a) { aVote = v; aAt = uint64(block.timestamp); }
        else { bVote = v; bAt = uint64(block.timestamp); }

        if (aVote == Vote.Accept && bVote == Vote.Accept) _complete(CompletionReason.BothAccepted);
        else if (aVote == Vote.Reject && bVote == Vote.Reject) _cancel();
    }

    function forceComplete() external nonReentrant inState(Status.Locked) onlyAB {
        if (msg.sender == a && bVote == Vote.Unset) {
            require(block.timestamp >= uint256(aAt) + uint256(timeoutSeconds), "A_NOT_TIMEOUT");
            if (aVote == Vote.Accept) {
                _complete(CompletionReason.ForcedByA); return;
            } else if (aVote == Vote.Reject) {
                _cancel(); return;
            }
        } else if (msg.sender == b && aVote == Vote.Unset) {
            require(block.timestamp >= uint256(bAt) + uint256(timeoutSeconds), "B_NOT_TIMEOUT");
            if (bVote == Vote.Accept) {
                _complete(CompletionReason.ForcedByB); return;
            } else if (bVote == Vote.Reject) {
                _cancel(); return;
            }
        } 
        
        revert("BAD_FORCE");
    }

    /* ========== 完成 / 取消（自动结算） ========== */
    struct Fees    { uint256 aFee; uint256 bFee; }
    struct Rewards { uint256 toA;  uint256 toB;  uint256 toC; address cAddr; uint256 cToken; }

    // 完成：当场派发 & 清理
    function _complete(CompletionReason reason) internal {
        Fees memory f = _computeFees();
        _processFees(f); emit FeesProcessed(aSwapToken, f.aFee, bSwapToken, f.bFee);

        Rewards memory r = _computeRewardsFromFees(f);
        _mintAndRecord(r);
        _refreshMaxPointers();

        // 内部标记
        aPaid = false; bPaid = false;
        aClaimed = true; bClaimed = true;

        // === 结算派发（完成态） ===
        _sendOut(bSwapToken, a, bSwapNetForA);
        _sendOut(aMarginToken, a, aMarginAmount);
        emit Claimed(a, bSwapToken, bSwapNetForA, aMarginToken, aMarginAmount);

        _sendOut(aSwapToken, b, aSwapNetForB);
        _sendOut(bMarginToken, b, bMarginAmount);
        emit Claimed(b, aSwapToken, aSwapNetForB, bMarginToken, bMarginAmount);

        // 仅当该侧开启过热索引追踪，才写入“完成热索引 ring”
        if (_trackA)       { IFactoryIndex(factory).onCompletedFor(a); }
        if (_trackBActive) { IFactoryIndex(factory).onCompletedFor(b); }

        // 解锁 NFT + 清理“活跃热索引”
        _unlockNftIfLocked(true);
        _unlockNftIfLocked(false);
        if (_trackA)       { IFactoryIndex(factory).onClosedFor(a); _trackA = false; }
        if (_trackBActive) { IFactoryIndex(factory).onClosedFor(b); _trackBActive = false; }

        status = Status.Completed;
        emit Completed(reason);
    }

    // 取消：当场退款 & 清理
    function _cancel() internal {
        if (aPaid) {
            aPaid = false; aClaimed = true;
            _sendOut(aSwapToken, a, aSwapAmount);
            _sendOut(aMarginToken, a, aMarginAmount);
            emit Claimed(a, aSwapToken, aSwapAmount, aMarginToken, aMarginAmount);
        }
        if (bPaid) {
            bPaid = false; bClaimed = true;
            _sendOut(bSwapToken, b, bSwapAmount);
            _sendOut(bMarginToken, b, bMarginAmount);
            emit Claimed(b, bSwapToken, bSwapAmount, bMarginToken, bMarginAmount);
        }

        _unlockNftIfLocked(true);
        _unlockNftIfLocked(false);
        if (_trackA)       { IFactoryIndex(factory).onClosedFor(a); _trackA = false; }
        if (_trackBActive) { IFactoryIndex(factory).onClosedFor(b); _trackBActive = false; }

        status = Status.Canceled;
        emit Canceled();
    }

    /* ========== 手续费 & 入池 ========== */
    function _isNoFeeToken(address token) internal view returns (bool) {
        address tNorm = (token == NATIVE) ? WNATIVE : token;
        if (tNorm == dl) return true;
        if (specialNoFeeToken != address(0) && tNorm == specialNoFeeToken) return true;
        return false;
    }
    function _computeFees() internal returns (Fees memory f) {
        f.aFee = _isNoFeeToken(aSwapToken) ? 0 : (aSwapAmount * feeNonDLNum) / feeNonDLDen;
        f.bFee = _isNoFeeToken(bSwapToken) ? 0 : (bSwapAmount * feeNonDLNum) / feeNonDLDen;
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
            (bool ok, bytes memory data) = pair.call(abi.encodeWithSignature("mintOtherOnly()"));
            require(ok && (data.length == 32 || data.length == 0), "PAIR_MINT_FAIL");
        } else {
            if (token == NATIVE) { (bool ok2, ) = payable(treasury).call{value: fee}(""); require(ok2); }
            else IERC20(tokenNorm).safeTransfer(treasury, fee);
        }
    }

    /* ========== 奖励（基于“已计提手续费(折 DL) * 比例”） ========== */
    function _computeRewardsFromFees(Fees memory f) internal returns (Rewards memory r) {
        if (mintOnFeesNum == 0) return r;

        bool hasA = (infoNft != address(0)) && aNftLocked && aNftId != 0 && IDealInfoNFTView(infoNft).ownerOf(aNftId) == a;
        bool hasB = (infoNft != address(0)) && bNftLocked && bNftId != 0 && IDealInfoNFTView(infoNft).ownerOf(bNftId) == b;
        if (!hasA && !hasB) return r;

        uint256 totalFeeDL =
            _quoteAggToDL(aSwapToken, aPair, f.aFee) +
            _quoteAggToDL(bSwapToken, bPair, f.bFee);
        if (totalFeeDL == 0) return r;

        uint256 totalToMint = (totalFeeDL * mintOnFeesNum) / mintOnFeesDen;
        if (totalToMint == 0) return r;

        uint256 share = totalToMint / 3;
        if (hasA) r.toA = share;
        if (hasB) r.toB = share;

        uint256 cToken = _selectC(hasA, hasB);
        if (cToken != 0) {
            r.cToken = cToken;
            r.cAddr  = IDealInfoNFTView(infoNft).ownerOf(cToken);
            r.toC    = share;
        }

        uint256 used = (hasA ? share : 0) + (hasB ? share : 0) + (r.toC);
        uint256 rem = (totalToMint > used) ? (totalToMint - used) : 0;
        if (rem > 0 && hasA) r.toA += rem;
    }

    function _selectC(bool hasA, bool hasB) internal view returns (uint256 cToken) {
        IDealInfoNFTView inf = IDealInfoNFTView(infoNft);

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

    function _preferFirstMax2(uint256 id1, uint256 s1, uint256 id2, uint256 s2) internal pure returns (uint256) {
        if (s2 > s1) return id2; return id1;
    }
    function _preferFirstMax3(uint256 id1, uint256 s1, uint256 id2, uint256 s2, uint256 id3, uint256 s3)
        internal pure returns (uint256)
    {
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

    /* ---------- 铸币 & 统计（通过 Factory 代理写 InfoNFT） ---------- */
    function _mintAndRecord(Rewards memory r) internal {
        if (r.toA > 0) IFactoryMinter(factory).mintDL(a, r.toA);
        if (r.toB > 0) IFactoryMinter(factory).mintDL(b, r.toB);
        if (r.toC > 0 && r.cAddr != address(0)) IFactoryMinter(factory).mintDL(r.cAddr, r.toC);
        emit RewardsMinted(a, r.toA, b, r.toB, r.cAddr, r.toC);

        if (infoNft != address(0)) {
            if (aNftLocked && aNftId != 0 && r.toA > 0) IFactoryInfo(factory).infoAddMinted(aNftId, r.toA);
            if (bNftLocked && bNftId != 0 && r.toB > 0) IFactoryInfo(factory).infoAddMinted(bNftId, r.toB);
            if (r.cToken != 0 && r.toC > 0) IFactoryInfo(factory).infoAddMinted(r.cToken, r.toC);
        }
    }

    /* ---------- 完成后更新 maxA / maxB（通过 Factory 代理） ---------- */
    function _refreshMaxPointers() internal {
        if (infoNft == address(0)) return;
        IDealInfoNFTView inf = IDealInfoNFTView(infoNft);
        bool hasA = aNftLocked && aNftId != 0;
        bool hasB = bNftLocked && bNftId != 0;

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
            if (winA != curMaxA) IFactoryInfo(factory).infoSetMaxPartnerOf(aNftId, winA);
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
            if (winB != curMaxB) IFactoryInfo(factory).infoSetMaxPartnerOf(bNftId, winB);
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
            aVote = Vote.Unset; bVote = Vote.Unset; aAt = 0; bAt = 0;
            emit Locked();
        }
    }
    function _isSideReadyA() internal view returns (bool) {
        bool tokensReady = (aSwapAmount == 0 && aMarginAmount == 0) || aPaid;
        bool nftReady    = (aNftId == 0) || aNftLocked;
        return tokensReady && nftReady;
    }
    function _isSideReadyB() internal view returns (bool) {
        bool tokensReady = (bSwapAmount == 0 && bMarginAmount == 0) || bPaid;
        bool nftNeeded   = (joinMode == JoinMode.NftGated) || (bNftId != 0);
        bool nftReady    = (!nftNeeded) || bNftLocked;
        return tokensReady && nftReady;
    }

    /* ========== 只读：原生需求 ========== */
    function nativeRequiredForA() public view returns (uint256) {
        uint256 n=0; if (aSwapToken==NATIVE) n+=aSwapAmount; if (aMarginToken==NATIVE) n+=aMarginAmount; return n;
    }
    function nativeRequiredForB() public view returns (uint256) {
        uint256 n=0; if (bSwapToken==NATIVE) n+=bSwapAmount; if (bMarginToken==NATIVE) n+=bMarginAmount; return n;
    }

    /* ========== 工具：资金清退/发送/拉取 ========== */
    function _pullExactERC20(IERC20 token, uint256 amount, address from) internal {
        if (amount == 0) return;
        uint256 beforeBal = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);
        uint256 delta = token.balanceOf(address(this)) - beforeBal;
        require(delta == amount, "FOT_NOT_ALLOWED");
    }
    function _sendOut(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (token == NATIVE) { (bool ok, ) = payable(to).call{value: amount}(""); require(ok, "NATIVE_SEND_FAIL"); }
        else IERC20(token).safeTransfer(to, amount);
    }
    function _refundFundsA() internal {
        if (aPaid) { aPaid=false; _sendOut(aSwapToken,a,aSwapAmount); _sendOut(aMarginToken,a,aMarginAmount); }
    }
    function _refundFundsB() internal {
        if (bPaid) { bPaid=false; _sendOut(bSwapToken,b,bSwapAmount); _sendOut(bMarginToken,b,bMarginAmount); }
    }
    function _refundAllToParties() internal { _refundFundsA(); _refundFundsB(); b = address(0); }

    // 加锁/解锁辅助
    function _lockNftForAIfAny() internal {
        if (aNftId == 0 || aNftLocked) return;
        require(IERC721(infoNft).ownerOf(aNftId) == a, "A_NFT_NOT_OWNER");
        IFactoryLock(factory).infoLock(aNftId, a);
        aNftLocked = true;
    }
    function _lockNftForBIfAny() internal {
        if (bNftId == 0 || bNftLocked) return;
        require(IERC721(infoNft).ownerOf(bNftId) == b, "B_NFT_NOT_OWNER");
        IFactoryLock(factory).infoLock(bNftId, b);
        bNftLocked = true;
    }
    function _unlockNftIfLocked(bool isA) internal {
        if (isA) {
            if (aNftLocked && aNftId != 0) { aNftLocked=false; IFactoryLock(factory).infoUnlock(aNftId); }
        } else {
            if (bNftLocked && bNftId != 0) { bNftLocked=false; IFactoryLock(factory).infoUnlock(bNftId); }
        }
    }

    // 接收原生
    receive() external payable {}
}
