// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

interface IZodiacNotify {
    function notify(uint256 _amount) external; // after transfer is done zodiac token is doing the strategy
}
