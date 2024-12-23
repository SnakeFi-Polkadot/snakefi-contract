// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import "@forge-std/Test.sol";

import {SnakeStablecoin} from "../src/SnakeStablecoin.sol";

contract BaseTest is Test {
    uint256 public constant INITIAL_SUPPLY = 1000000 * 10 ** 18;

    uint256 public moonbaseFork;

    SnakeStablecoin public snakeStablecoin;

    address public owner;
    address public stablecoinMinter;
    address[] public users;

    function setUp() public virtual {
        // moonbaseFork = vm.createFork('moonbase');
        // vm.selectFork(moonbaseFork);

        // owner = makeAddr("owner");
        // stablecoinMinter = makeAddr("stablecoinMinter");

        // snakeStablecoin = new SnakeStablecoin(stablecoinMinter);

        // vm.prank(owner);
        // snakeStablecoin.initialSupply(owner, INITIAL_SUPPLY);
    }
}
