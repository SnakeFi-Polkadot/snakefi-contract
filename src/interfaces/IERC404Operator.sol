// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

interface IERC404Operator {

    function nftApproved(address nft) external view returns (bool);

    function isOperator(address nft, address operator) external view returns (bool);

    function approveNFT(address nft) external;

    function approveOperator(address nft, address operator) external;
}