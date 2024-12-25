// // SPDX-Identifier-License: MIT
// pragma solidity 0.8.20;

// import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// import {IERC404Operator} from "./interfaces/IERC404Operator.sol";

// contract ERC404Operator is Ownable{

//     address public snakeForFun;

//     mapping(address => bool) public override nftApproved;

//     mapping(address => mapping(address => bool)) public override isOperator;

//     constructor(address _snakeForFun) Ownable(msg.sender) {
//         snakeForFun = _snakeForFun;
//     }

//     function approveNFT(address nft) external override{
//         require(msg.sender == snakeForFun, "Not authorized");
//         nftApproved[nft] = true;
//     }

//     function approveOperator(address nft, address operator) external override{
//         require(nftApproved[nft], "NFT not approved");
//         isOperator[nft][operator] = true;
//     }
// }