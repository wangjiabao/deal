
// File: @openzeppelin/contracts/utils/Context.sol


// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.20;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// File: @openzeppelin/contracts/access/Ownable.sol


// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

pragma solidity ^0.8.20;


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// File: @openzeppelin/contracts/utils/Errors.sol


// OpenZeppelin Contracts (last updated v5.1.0) (utils/Errors.sol)

pragma solidity ^0.8.20;

/**
 * @dev Collection of common custom errors used in multiple contracts
 *
 * IMPORTANT: Backwards compatibility is not guaranteed in future versions of the library.
 * It is recommended to avoid relying on the error API for critical functionality.
 *
 * _Available since v5.1._
 */
library Errors {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error InsufficientBalance(uint256 balance, uint256 needed);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedCall();

    /**
     * @dev The deployment failed.
     */
    error FailedDeployment();

    /**
     * @dev A necessary precompile is missing.
     */
    error MissingPrecompile(address);
}

// File: @openzeppelin/contracts/utils/Create2.sol


// OpenZeppelin Contracts (last updated v5.1.0) (utils/Create2.sol)

pragma solidity ^0.8.20;


/**
 * @dev Helper to make usage of the `CREATE2` EVM opcode easier and safer.
 * `CREATE2` can be used to compute in advance the address where a smart
 * contract will be deployed, which allows for interesting new mechanisms known
 * as 'counterfactual interactions'.
 *
 * See the https://eips.ethereum.org/EIPS/eip-1014#motivation[EIP] for more
 * information.
 */
library Create2 {
    /**
     * @dev There's no code to deploy.
     */
    error Create2EmptyBytecode();

    /**
     * @dev Deploys a contract using `CREATE2`. The address where the contract
     * will be deployed can be known in advance via {computeAddress}.
     *
     * The bytecode for a contract can be obtained from Solidity with
     * `type(contractName).creationCode`.
     *
     * Requirements:
     *
     * - `bytecode` must not be empty.
     * - `salt` must have not been used for `bytecode` already.
     * - the factory must have a balance of at least `amount`.
     * - if `amount` is non-zero, `bytecode` must have a `payable` constructor.
     */
    function deploy(uint256 amount, bytes32 salt, bytes memory bytecode) internal returns (address addr) {
        if (address(this).balance < amount) {
            revert Errors.InsufficientBalance(address(this).balance, amount);
        }
        if (bytecode.length == 0) {
            revert Create2EmptyBytecode();
        }
        assembly ("memory-safe") {
            addr := create2(amount, add(bytecode, 0x20), mload(bytecode), salt)
            // if no address was created, and returndata is not empty, bubble revert
            if and(iszero(addr), not(iszero(returndatasize()))) {
                let p := mload(0x40)
                returndatacopy(p, 0, returndatasize())
                revert(p, returndatasize())
            }
        }
        if (addr == address(0)) {
            revert Errors.FailedDeployment();
        }
    }

    /**
     * @dev Returns the address where a contract will be stored if deployed via {deploy}. Any change in the
     * `bytecodeHash` or `salt` will result in a new destination address.
     */
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) internal view returns (address) {
        return computeAddress(salt, bytecodeHash, address(this));
    }

    /**
     * @dev Returns the address where a contract will be stored if deployed via {deploy} from a contract located at
     * `deployer`. If `deployer` is this contract's address, returns the same value as {computeAddress}.
     */
    function computeAddress(bytes32 salt, bytes32 bytecodeHash, address deployer) internal pure returns (address addr) {
        assembly ("memory-safe") {
            let ptr := mload(0x40) // Get free memory pointer

            // |                   | ↓ ptr ...  ↓ ptr + 0x0B (start) ...  ↓ ptr + 0x20 ...  ↓ ptr + 0x40 ...   |
            // |-------------------|---------------------------------------------------------------------------|
            // | bytecodeHash      |                                                        CCCCCCCCCCCCC...CC |
            // | salt              |                                      BBBBBBBBBBBBB...BB                   |
            // | deployer          | 000000...0000AAAAAAAAAAAAAAAAAAA...AA                                     |
            // | 0xFF              |            FF                                                             |
            // |-------------------|---------------------------------------------------------------------------|
            // | memory            | 000000...00FFAAAAAAAAAAAAAAAAAAA...AABBBBBBBBBBBBB...BBCCCCCCCCCCCCC...CC |
            // | keccak(start, 85) |            ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑ |

            mstore(add(ptr, 0x40), bytecodeHash)
            mstore(add(ptr, 0x20), salt)
            mstore(ptr, deployer) // Right-aligned with 12 preceding garbage bytes
            let start := add(ptr, 0x0b) // The hashed data starts at the final garbage byte which we will set to 0xff
            mstore8(start, 0xff)
            addr := and(keccak256(start, 85), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }
}

// File: @openzeppelin/contracts/proxy/Clones.sol


// OpenZeppelin Contracts (last updated v5.4.0) (proxy/Clones.sol)

pragma solidity ^0.8.20;



/**
 * @dev https://eips.ethereum.org/EIPS/eip-1167[ERC-1167] is a standard for
 * deploying minimal proxy contracts, also known as "clones".
 *
 * > To simply and cheaply clone contract functionality in an immutable way, this standard specifies
 * > a minimal bytecode implementation that delegates all calls to a known, fixed address.
 *
 * The library includes functions to deploy a proxy using either `create` (traditional deployment) or `create2`
 * (salted deterministic deployment). It also includes functions to predict the addresses of clones deployed using the
 * deterministic method.
 */
library Clones {
    error CloneArgumentsTooLong();

    /**
     * @dev Deploys and returns the address of a clone that mimics the behavior of `implementation`.
     *
     * This function uses the create opcode, which should never revert.
     *
     * WARNING: This function does not check if `implementation` has code. A clone that points to an address
     * without code cannot be initialized. Initialization calls may appear to be successful when, in reality, they
     * have no effect and leave the clone uninitialized, allowing a third party to initialize it later.
     */
    function clone(address implementation) internal returns (address instance) {
        return clone(implementation, 0);
    }

    /**
     * @dev Same as {xref-Clones-clone-address-}[clone], but with a `value` parameter to send native currency
     * to the new contract.
     *
     * WARNING: This function does not check if `implementation` has code. A clone that points to an address
     * without code cannot be initialized. Initialization calls may appear to be successful when, in reality, they
     * have no effect and leave the clone uninitialized, allowing a third party to initialize it later.
     *
     * NOTE: Using a non-zero value at creation will require the contract using this function (e.g. a factory)
     * to always have enough balance for new deployments. Consider exposing this function under a payable method.
     */
    function clone(address implementation, uint256 value) internal returns (address instance) {
        if (address(this).balance < value) {
            revert Errors.InsufficientBalance(address(this).balance, value);
        }
        assembly ("memory-safe") {
            // Cleans the upper 96 bits of the `implementation` word, then packs the first 3 bytes
            // of the `implementation` address with the bytecode before the address.
            mstore(0x00, or(shr(0xe8, shl(0x60, implementation)), 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000))
            // Packs the remaining 17 bytes of `implementation` with the bytecode after the address.
            mstore(0x20, or(shl(0x78, implementation), 0x5af43d82803e903d91602b57fd5bf3))
            instance := create(value, 0x09, 0x37)
        }
        if (instance == address(0)) {
            revert Errors.FailedDeployment();
        }
    }

    /**
     * @dev Deploys and returns the address of a clone that mimics the behavior of `implementation`.
     *
     * This function uses the create2 opcode and a `salt` to deterministically deploy
     * the clone. Using the same `implementation` and `salt` multiple times will revert, since
     * the clones cannot be deployed twice at the same address.
     *
     * WARNING: This function does not check if `implementation` has code. A clone that points to an address
     * without code cannot be initialized. Initialization calls may appear to be successful when, in reality, they
     * have no effect and leave the clone uninitialized, allowing a third party to initialize it later.
     */
    function cloneDeterministic(address implementation, bytes32 salt) internal returns (address instance) {
        return cloneDeterministic(implementation, salt, 0);
    }

    /**
     * @dev Same as {xref-Clones-cloneDeterministic-address-bytes32-}[cloneDeterministic], but with
     * a `value` parameter to send native currency to the new contract.
     *
     * WARNING: This function does not check if `implementation` has code. A clone that points to an address
     * without code cannot be initialized. Initialization calls may appear to be successful when, in reality, they
     * have no effect and leave the clone uninitialized, allowing a third party to initialize it later.
     *
     * NOTE: Using a non-zero value at creation will require the contract using this function (e.g. a factory)
     * to always have enough balance for new deployments. Consider exposing this function under a payable method.
     */
    function cloneDeterministic(
        address implementation,
        bytes32 salt,
        uint256 value
    ) internal returns (address instance) {
        if (address(this).balance < value) {
            revert Errors.InsufficientBalance(address(this).balance, value);
        }
        assembly ("memory-safe") {
            // Cleans the upper 96 bits of the `implementation` word, then packs the first 3 bytes
            // of the `implementation` address with the bytecode before the address.
            mstore(0x00, or(shr(0xe8, shl(0x60, implementation)), 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000))
            // Packs the remaining 17 bytes of `implementation` with the bytecode after the address.
            mstore(0x20, or(shl(0x78, implementation), 0x5af43d82803e903d91602b57fd5bf3))
            instance := create2(value, 0x09, 0x37, salt)
        }
        if (instance == address(0)) {
            revert Errors.FailedDeployment();
        }
    }

    /**
     * @dev Computes the address of a clone deployed using {Clones-cloneDeterministic}.
     */
    function predictDeterministicAddress(
        address implementation,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(add(ptr, 0x38), deployer)
            mstore(add(ptr, 0x24), 0x5af43d82803e903d91602b57fd5bf3ff)
            mstore(add(ptr, 0x14), implementation)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73)
            mstore(add(ptr, 0x58), salt)
            mstore(add(ptr, 0x78), keccak256(add(ptr, 0x0c), 0x37))
            predicted := and(keccak256(add(ptr, 0x43), 0x55), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    /**
     * @dev Computes the address of a clone deployed using {Clones-cloneDeterministic}.
     */
    function predictDeterministicAddress(
        address implementation,
        bytes32 salt
    ) internal view returns (address predicted) {
        return predictDeterministicAddress(implementation, salt, address(this));
    }

    /**
     * @dev Deploys and returns the address of a clone that mimics the behavior of `implementation` with custom
     * immutable arguments. These are provided through `args` and cannot be changed after deployment. To
     * access the arguments within the implementation, use {fetchCloneArgs}.
     *
     * This function uses the create opcode, which should never revert.
     *
     * WARNING: This function does not check if `implementation` has code. A clone that points to an address
     * without code cannot be initialized. Initialization calls may appear to be successful when, in reality, they
     * have no effect and leave the clone uninitialized, allowing a third party to initialize it later.
     */
    function cloneWithImmutableArgs(address implementation, bytes memory args) internal returns (address instance) {
        return cloneWithImmutableArgs(implementation, args, 0);
    }

    /**
     * @dev Same as {xref-Clones-cloneWithImmutableArgs-address-bytes-}[cloneWithImmutableArgs], but with a `value`
     * parameter to send native currency to the new contract.
     *
     * WARNING: This function does not check if `implementation` has code. A clone that points to an address
     * without code cannot be initialized. Initialization calls may appear to be successful when, in reality, they
     * have no effect and leave the clone uninitialized, allowing a third party to initialize it later.
     *
     * NOTE: Using a non-zero value at creation will require the contract using this function (e.g. a factory)
     * to always have enough balance for new deployments. Consider exposing this function under a payable method.
     */
    function cloneWithImmutableArgs(
        address implementation,
        bytes memory args,
        uint256 value
    ) internal returns (address instance) {
        if (address(this).balance < value) {
            revert Errors.InsufficientBalance(address(this).balance, value);
        }
        bytes memory bytecode = _cloneCodeWithImmutableArgs(implementation, args);
        assembly ("memory-safe") {
            instance := create(value, add(bytecode, 0x20), mload(bytecode))
        }
        if (instance == address(0)) {
            revert Errors.FailedDeployment();
        }
    }

    /**
     * @dev Deploys and returns the address of a clone that mimics the behavior of `implementation` with custom
     * immutable arguments. These are provided through `args` and cannot be changed after deployment. To
     * access the arguments within the implementation, use {fetchCloneArgs}.
     *
     * This function uses the create2 opcode and a `salt` to deterministically deploy the clone. Using the same
     * `implementation`, `args` and `salt` multiple times will revert, since the clones cannot be deployed twice
     * at the same address.
     *
     * WARNING: This function does not check if `implementation` has code. A clone that points to an address
     * without code cannot be initialized. Initialization calls may appear to be successful when, in reality, they
     * have no effect and leave the clone uninitialized, allowing a third party to initialize it later.
     */
    function cloneDeterministicWithImmutableArgs(
        address implementation,
        bytes memory args,
        bytes32 salt
    ) internal returns (address instance) {
        return cloneDeterministicWithImmutableArgs(implementation, args, salt, 0);
    }

    /**
     * @dev Same as {xref-Clones-cloneDeterministicWithImmutableArgs-address-bytes-bytes32-}[cloneDeterministicWithImmutableArgs],
     * but with a `value` parameter to send native currency to the new contract.
     *
     * WARNING: This function does not check if `implementation` has code. A clone that points to an address
     * without code cannot be initialized. Initialization calls may appear to be successful when, in reality, they
     * have no effect and leave the clone uninitialized, allowing a third party to initialize it later.
     *
     * NOTE: Using a non-zero value at creation will require the contract using this function (e.g. a factory)
     * to always have enough balance for new deployments. Consider exposing this function under a payable method.
     */
    function cloneDeterministicWithImmutableArgs(
        address implementation,
        bytes memory args,
        bytes32 salt,
        uint256 value
    ) internal returns (address instance) {
        bytes memory bytecode = _cloneCodeWithImmutableArgs(implementation, args);
        return Create2.deploy(value, salt, bytecode);
    }

    /**
     * @dev Computes the address of a clone deployed using {Clones-cloneDeterministicWithImmutableArgs}.
     */
    function predictDeterministicAddressWithImmutableArgs(
        address implementation,
        bytes memory args,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        bytes memory bytecode = _cloneCodeWithImmutableArgs(implementation, args);
        return Create2.computeAddress(salt, keccak256(bytecode), deployer);
    }

    /**
     * @dev Computes the address of a clone deployed using {Clones-cloneDeterministicWithImmutableArgs}.
     */
    function predictDeterministicAddressWithImmutableArgs(
        address implementation,
        bytes memory args,
        bytes32 salt
    ) internal view returns (address predicted) {
        return predictDeterministicAddressWithImmutableArgs(implementation, args, salt, address(this));
    }

    /**
     * @dev Get the immutable args attached to a clone.
     *
     * - If `instance` is a clone that was deployed using `clone` or `cloneDeterministic`, this
     *   function will return an empty array.
     * - If `instance` is a clone that was deployed using `cloneWithImmutableArgs` or
     *   `cloneDeterministicWithImmutableArgs`, this function will return the args array used at
     *   creation.
     * - If `instance` is NOT a clone deployed using this library, the behavior is undefined. This
     *   function should only be used to check addresses that are known to be clones.
     */
    function fetchCloneArgs(address instance) internal view returns (bytes memory) {
        bytes memory result = new bytes(instance.code.length - 45); // revert if length is too short
        assembly ("memory-safe") {
            extcodecopy(instance, add(result, 32), 45, mload(result))
        }
        return result;
    }

    /**
     * @dev Helper that prepares the initcode of the proxy with immutable args.
     *
     * An assembly variant of this function requires copying the `args` array, which can be efficiently done using
     * `mcopy`. Unfortunately, that opcode is not available before cancun. A pure solidity implementation using
     * abi.encodePacked is more expensive but also more portable and easier to review.
     *
     * NOTE: https://eips.ethereum.org/EIPS/eip-170[EIP-170] limits the length of the contract code to 24576 bytes.
     * With the proxy code taking 45 bytes, that limits the length of the immutable args to 24531 bytes.
     */
    function _cloneCodeWithImmutableArgs(
        address implementation,
        bytes memory args
    ) private pure returns (bytes memory) {
        if (args.length > 24531) revert CloneArgumentsTooLong();
        return
            abi.encodePacked(
                hex"61",
                uint16(args.length + 45),
                hex"3d81600a3d39f3363d3d373d3d3d363d73",
                implementation,
                hex"5af43d82803e903d91602b57fd5bf3",
                args
            );
    }
}

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

// File: @openzeppelin/contracts/interfaces/IERC20.sol


// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC20.sol)

pragma solidity >=0.4.16;


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

// File: deal/contracts/DealFactory.sol


pragma solidity ^0.8.26;






interface IDLMint     { function mint(address to, uint256 amount) external; }
interface IDLBurnFrom { function burnFrom(address account, uint256 amount) external; }

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
    function mintInitial(uint256 _b1) external returns (uint amountDL, uint amountOther);
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
        require(amountInToken >= 1 * 10**18 && amountInToken <= 10 * 10**18);
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
    function initPair(address pair, uint256 _b1) external onlyOwner returns (uint amountDL, uint amountOther) {
        (amountDL, amountOther) = IDealPairInit(pair).mintInitial(_b1);
    }
    function setPairFee(address pair, uint32 newNum, uint32 newDen) external onlyOwner {
        IDealPairInit(pair).setFee(newNum, newDen);
        emit PairFeeUpdated(pair, newNum, newDen);
    }
    function setPairFeeByAdmin(address pair, uint32 newNum) external onlyAdmin {
         require(1 <= newNum && 200 >= newNum);
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

    /* ========= InfoNFT 锁代理（仅 Deal） ========= */
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
