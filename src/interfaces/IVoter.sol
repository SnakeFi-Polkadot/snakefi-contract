// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

interface IVoter {
    function attachTokenToGauge(uint _tokenId, address account) external;

    function detachTokenFromGauge(uint _tokenId, address account) external;

    function emitDeposit(uint _tokenId, address account, uint amount) external;

    function emitWithdraw(uint _tokenId, address account, uint amount) external;

    function notifyRewardAmount(uint amount) external;

    function distribute(address _gauge) external;

    /* ----------------------------- VIEW FUNCTIONS ----------------------------- */

    function isWhitelisted(address token) external view returns (bool);

    function VOTING_ESCROW() external view returns (address);

    function governor() external view returns (address);

    function emergencyCouncil() external view returns (address);

    function gauges(address) external view returns (address);

    function external_bribes(address) external view returns (address);

    function isAlive(address) external view returns (bool);

    function length() external view returns (uint256);

    function activeGaugeNumber() external view returns (uint256);
}
