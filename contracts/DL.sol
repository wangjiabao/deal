// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract DCToken is ERC20, ERC20Burnable, ERC20Permit, ERC20Pausable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @param name_  代币名
     * @param symbol_ 代币符号
     * @param initialSupply 初始铸造量（18位精度）
     * @param initialAdmin 初始管理员（DEFAULT_ADMIN_ROLE）
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply,
        address initialAdmin,
        address minterFirst_
    )
        ERC20(name_, symbol_)
        ERC20Permit(name_) // EIP-2612 域名使用 token name
    {
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);

        if (initialSupply > 0) {
            _mint(initialAdmin, initialSupply);
        }

        _grantRole(MINTER_ROLE, minterFirst_);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

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
