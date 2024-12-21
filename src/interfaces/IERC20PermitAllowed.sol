// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IERC20PermitAllowed {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bool allowed, // true = approve (type(uint256).max), false = revoke(0)
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
