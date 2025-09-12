// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;

    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}
