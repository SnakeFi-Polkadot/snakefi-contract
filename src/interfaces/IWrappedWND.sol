// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

interface IWrappedWND {

    function balanceOf(address) external view returns (uint256);

    function allowance(address, address) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function transfer(address, uint256) external returns (bool);

    function transferFrom(address, address, uint256) external returns (bool);

    function approve(address, uint256) external returns (bool);

    function withdraw(uint256) external;

    function deposit() external payable;
}