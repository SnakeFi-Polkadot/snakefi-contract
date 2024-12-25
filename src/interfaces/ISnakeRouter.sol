// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

interface ISnakeRouter {
    function pairFor(address token0, address token1, bool stable) external view returns (address pair);
}
