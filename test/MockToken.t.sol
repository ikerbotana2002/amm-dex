// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockToken} from "../src/MockToken.sol";

contract MockTokenTest is Test {
    MockToken tokenA;
    MockToken tokenB;

    address alice = address(0xA1);
    address bob = address(0xB1);

    function setUp() public {
        tokenA = new MockToken("Token A", "TKA");
        tokenB = new MockToken("Token B", "TKB");
    }

    function testInitialSupply() public view {
        assertEq(tokenA.totalSupply(), 1_000_000 ether);
        assertEq(tokenB.totalSupply(), 1_000_000 ether);

        assertEq(tokenA.balanceOf(address(this)), 1_000_000 ether);
    }

    function testTokenMetadata() public view {
        assertEq(tokenA.name(), "Token A");
        assertEq(tokenA.symbol(), "TKA");

        assertEq(tokenB.name(), "Token B");
        assertEq(tokenB.symbol(), "TKB");

        assertEq(tokenA.decimals(), 18);
    }

    function testTransfer() public {
        tokenA.transfer(alice, 100 ether);

        assertEq(tokenA.balanceOf(alice), 100 ether);

        assertEq(tokenA.balanceOf(address(this)), 999_900 ether);
    }

    function testApproveAndTransferFrom() public {
        tokenA.transfer(alice, 500 ether);

        vm.prank(alice);
        tokenA.approve(bob, 200 ether);

        vm.prank(bob);
        tokenA.transferFrom(alice, bob, 150 ether);

        assertEq(tokenA.balanceOf(alice), 350 ether);
        assertEq(tokenA.balanceOf(bob), 150 ether);

        assertEq(tokenA.allowance(alice, bob), 50 ether);
    }

    function testCannotTransferWithoutBalance() public {
        vm.prank(alice);
        vm.expectRevert();

        tokenA.transfer(bob, 100 ether);
    }
}
