// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title DLToken (Unlimited Mintable, Burnable, Permit, Pausable, RBAC)
 * @notice - 无限增发（仅 MINTER_ROLE）
 *         - 可燃烧（burn/burnFrom）
 *         - EIP-2612 permit
 *         - 可暂停（PAUSER_ROLE）
 *         - 角色权限（AccessControl）
 */
contract DLToken is ERC20, ERC20Burnable, ERC20Permit, ERC20Pausable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @param name_  代币名
     * @param symbol_ 代币符号
     * @param initialSupply 初始铸造量（18位精度），会发给管理员地址（若为0则不铸造）
     * @param initialAdmin 初始管理员（DEFAULT_ADMIN_ROLE）；若传 0 则使用部署者
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address initialAdmin
    )
        ERC20(name_, symbol_)
        ERC20Permit(name_) // EIP-2612 域名使用 token name
    {
        // 传 0 时回退到部署者，避免 _mint(address(0), ...) 造成的 revert
        address admin = (initialAdmin == address(0)) ? msg.sender : initialAdmin;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        if (initialSupply > 0) {
            _mint(admin, initialSupply);
        }
    }

    /// @notice 无限增发（仅 MINTER_ROLE）
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice 暂停/恢复（建议授予 DAO 执行合约）
    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    // Pausable 钩子（OZ v5：所有转账/增发/燃烧都会走 _update）
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }

    // AccessControl 的 IERC165 支持
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
