// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

interface ISnakeRouter {
    function pairFor(
        address token0,
        address token1,
        bool stable
    ) external view returns (address pair);

    function swapExactTokensForTokensSimple(
        uint amountIn,
        uint amountOutMin,
        address tokenFrom,
        address tokenTo,
        bool stable,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountOut(
        uint amountIn,
        address tokenIn,
        address tokenOut,
        bool stable
    ) external view returns (uint amount);

    function getReserves(
        address tokenA,
        address tokenB,
        bool stable
    ) external view returns (uint, uint);

    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint, uint, uint);
}
