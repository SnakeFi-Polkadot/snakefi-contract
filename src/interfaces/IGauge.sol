// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

interface IGauge {
    function notifyRewardAmount(address token, uint256 amount) external;

    function getReward(address account, address[] memory tokens) external;

    function left(address token) external view returns (uint256);

    function depositWithLock(
        address account,
        uint256 amount,
        uint256 _lockDuration
    ) external;

    function depositFor(address account, uint256 amount) external;
}
