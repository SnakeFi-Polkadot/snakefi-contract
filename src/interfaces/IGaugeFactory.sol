// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

interface IGaugeFactory {
    function createGauge(
        address,
        address,
        address,
        bool,
        address[] memory
    ) external returns (address);
}
