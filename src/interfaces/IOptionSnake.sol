// SPDX-Identifier-License: MITs
pragma solidity ^0.8.20;

interface IOptionSnake {

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function nft() external view returns (address);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;
}