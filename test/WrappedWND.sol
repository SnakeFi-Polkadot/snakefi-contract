// SPDX-Identifier-License: MIT
pragma solidity 0.8.20;

import "@forge-std/Test.sol";

import {WrappedWND} from "../src/dex/WrappedWND.sol";

contract WrappedWNDTest is Test {

    WrappedWND public wrappedWND;

    address public owner = makeAddr("owner");

    address public user = makeAddr("user");

    function setUp() public {
        vm.prank(owner);
        wrappedWND = new WrappedWND();
    }

    function test_deposit() public {
        uint256 amount = 1000 ether;
        uint256 balanceBefore = wrappedWND.balanceOf(user);
        assertEq(balanceBefore, 0);
        vm.deal(user, amount);
        vm.prank(user);
        wrappedWND.deposit{value: amount}();
        assertEq(wrappedWND.balanceOf(user), amount);
    }

    function test_withdraw() public {
        uint256 amount = 1000 ether;
        vm.deal(user, amount);
        vm.prank(user);
        wrappedWND.deposit{value: amount}();
        assertEq(wrappedWND.balanceOf(user), amount);
        
        vm.prank(user);
        wrappedWND.withdraw(amount);
        assertEq(wrappedWND.balanceOf(user), 0);
    }
}