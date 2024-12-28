// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.20;

// import {Test, console} from "lib/forge-std/src/Test.sol";
// import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// import {SnakeForFun} from "../src/snakeForFun/SnakeForFun.sol";
// import {Snake} from "../src/Snake.sol";

// contract SnakeForFunTest is Test {
//     address public owner;
//     Snake public snakeToken;
//     SnakeForFun public snakeForFun;

//     vm.Wallet public signer;

//     function setUp() public {
//         owner = makeAddr("owner");
//         signer = vm.createWallet();
//         snakeToken = new Snake(owner);
//         snakeForFun = new SnakeForFun(owner, address(snakeToken));
//     }

//     function test_forFun() public {
//         address guy = makeAddr("guy");
//         uint256 amount = 1000;

//         // _biteForFun(signer., totalSnake, allocation);
//     }

//     function _biteForFun(
//         address _signer,
//         uint256 totalSnake,
//         uint256[] memory allocation
//     ) internal {
//         vm.prank(owner);
//         snakeForFun.biteForFun(_signer, totalSnake, allocation);
//     }

//     function _sign(
//         bytes32 digest,
//         uint256 privateKey
//     ) internal returns (bytes32 signature) {
//         (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

//         signature = abi.encodePacked(r, s, v);
//     }
// }
