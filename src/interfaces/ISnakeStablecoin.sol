// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

interface ISnakeStablecoin {
    function setMinter(address _minter) external;

    function mint(address receiver) external;

    function approve(address spender, uint256 amount) external;

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function initialSupply(address receiver, uint256 supply) external;

    /* ---------------------------------- VIEW ---------------------------------- */

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function totalSupply() external view returns (uint256);
}
