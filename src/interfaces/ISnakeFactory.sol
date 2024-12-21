// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

interface ISnakeFactory {
    function createPair(address token0, address token1, bool stable) external returns (address pair);

    /* ---------------------------------- VIEW ---------------------------------- */
    function allPairLength() external view returns (uint256);

    function getPair(address token0, address token1, bool stable) external view returns (address pair);

    function isPair(address pair) external view returns (bool);

    function pairCodeHash() external pure returns (bytes32);

    function voter() external view returns (address);

    function stakingFeeHandler() external view returns (address);

    function referrerFeeHandler() external view returns (address);

    function getInitializable() external view returns (address, address, bool);

    function getFee(bool _stable_) external view returns (uint256);
}
