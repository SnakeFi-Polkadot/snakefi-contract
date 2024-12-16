// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

interface ISnakePair {
    function claimFees() external returns(uint256, uint256);

    function tokens() external view returns(address, address);

    function transferFrom(address from, address to, uint256 amount) external returns(bool);

    function permit(address owner, address spender, uint256 amount, uint256 deadline, uint8 v, uint8 r, bytes32 s) external;

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;

    function mint(address receiver, uint256 amount) external returns(uint256 lpAmount);

    function burn(address burner, uint256 amount) external returns(uint256 amount0, uint256 amount1);

    /* ----------------------------- VIEW FUNCTIONS ----------------------------- */
    function metadata() external view returns (
        uint256 decimal0,
        uint256 decimal1,
        uint256 reserve0,
        uint256 reserve1,
        bool stable,
        address token0,
        address token1
    );

    function getReserves() external view returns (uint256 reserve0, uint256 reserve1);

    function getAmountOut(uint256 amountIn, address tokenIn) external view returns(uint256 amountOut);
}