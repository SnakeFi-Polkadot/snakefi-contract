// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

interface IBribeFactory {
    function createExternalBribe(address[] memory) external returns (address);
}
