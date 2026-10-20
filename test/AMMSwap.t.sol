// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockToken} from "../src/MockToken.sol";
import {AMMPool} from "../src/AMMPool.sol";

contract AMMSwapTest is Test {
    MockToken tokenA;
    MockToken tokenB;
    AMMPool pool;

    address alice = address(0xA1);
    address bob = address(0xB1);

    function setUp() public {
        tokenA = new MockToken("Token A", "TKA");
        tokenB = new MockToken("Token B", "TKB");

        pool = new AMMPool(address(tokenA), address(tokenB));

        // Alice provides the initial liquidity.
        tokenA.transfer(alice, 1_000 ether);
        tokenB.transfer(alice, 1_000 ether);

        vm.startPrank(alice);

        tokenA.approve(address(pool), 100 ether);
        tokenB.approve(address(pool), 200 ether);

        pool.addInitialLiquidity(100 ether, 200 ether);

        vm.stopPrank();

        // Bob will perform the swaps.
        tokenA.transfer(bob, 100 ether);
        tokenB.transfer(bob, 100 ether);

        vm.startPrank(bob);

        tokenA.approve(address(pool), type(uint256).max);

        tokenB.approve(address(pool), type(uint256).max);

        vm.stopPrank();
    }

    function testGetAmountOut() public view {
        uint256 amountOut = pool.getAmountOut(10 ether, 100 ether, 200 ether);

        assertGt(amountOut, 18 ether);
        assertLt(amountOut, 19 ether);
    }

    function testSwapAForB() public {
        uint256 expectedOut = pool.getAmountOut(10 ether, 100 ether, 200 ether);

        uint256 bobBalanceBefore = tokenB.balanceOf(bob);

        vm.prank(bob);
        uint256 amountOut = pool.swapAForB(10 ether, 18 ether, block.timestamp + 1 hours);

        assertEq(amountOut, expectedOut);

        assertEq(tokenB.balanceOf(bob), bobBalanceBefore + amountOut);

        assertEq(pool.reserveA(), 110 ether);

        assertEq(pool.reserveB(), 200 ether - amountOut);
    }

    function testSwapBForA() public {
        uint256 expectedOut = pool.getAmountOut(20 ether, 200 ether, 100 ether);

        vm.prank(bob);
        uint256 amountOut = pool.swapBForA(20 ether, 0, block.timestamp + 1 hours);

        assertEq(amountOut, expectedOut);

        assertEq(pool.reserveB(), 220 ether);

        assertEq(pool.reserveA(), 100 ether - amountOut);
    }

    function testSwapFeeIncreasesK() public {
        uint256 kBefore = pool.reserveA() * pool.reserveB();

        vm.prank(bob);
        pool.swapAForB(10 ether, 0, block.timestamp + 1 hours);

        uint256 kAfter = pool.reserveA() * pool.reserveB();

        assertGt(kAfter, kBefore);
    }

    function test_RevertWhen_SlippageExceeded() public {
        vm.expectRevert(AMMPool.InsufficientOutputAmount.selector);

        vm.prank(bob);
        pool.swapAForB(10 ether, 20 ether, block.timestamp + 1 hours);
    }

    function test_RevertWhen_AmountInIsZero() public {
        vm.expectRevert(AMMPool.InvalidAmount.selector);

        vm.prank(bob);
        pool.swapAForB(0, 0, block.timestamp + 1 hours);
    }

    function test_RevertWhen_PoolNotInitialized() public {
        AMMPool emptyPool = new AMMPool(address(tokenA), address(tokenB));

        vm.expectRevert(AMMPool.PoolNotInitialized.selector);

        vm.prank(bob);
        emptyPool.swapAForB(10 ether, 0, block.timestamp + 1 hours);
    }

    function test_RevertWhen_TraderHasNoApproval() public {
        vm.prank(bob);
        tokenA.approve(address(pool), 0);

        vm.expectRevert();

        vm.prank(bob);
        pool.swapAForB(10 ether, 0, block.timestamp + 1 hours);

        assertEq(pool.reserveA(), 100 ether);
        assertEq(pool.reserveB(), 200 ether);
    }

    function testTwoConsecutiveSwaps() public {
        vm.prank(bob);
        pool.swapAForB(10 ether, 0, block.timestamp + 1 hours);

        uint256 reserveABefore = pool.reserveA();
        uint256 reserveBBefore = pool.reserveB();

        vm.prank(bob);
        pool.swapBForA(10 ether, 0, block.timestamp + 1 hours);

        assertLt(pool.reserveA(), reserveABefore);
        assertGt(pool.reserveB(), reserveBBefore);
    }

    function testExactSwapOutputWithFee() public view {
        uint256 amountIn = 10 ether;

        uint256 reserveIn = 100 ether;
        uint256 reserveOut = 200 ether;

        uint256 amountInWithFee = amountIn * 997;

        uint256 expectedOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);

        uint256 actualOut = pool.getAmountOut(amountIn, reserveIn, reserveOut);

        assertEq(actualOut, expectedOut);
    }

    function testReservesMatchTokenBalancesAfterSwap() public {
        vm.prank(bob);
        pool.swapAForB(10 ether, 0, block.timestamp + 1 hours);

        uint256 actualBalanceA = tokenA.balanceOf(address(pool));

        uint256 actualBalanceB = tokenB.balanceOf(address(pool));

        assertEq(pool.reserveA(), actualBalanceA);
        assertEq(pool.reserveB(), actualBalanceB);
    }

    function test_RevertWhen_SwapApprovalMissingKeepsBalances() public {
        vm.prank(bob);
        tokenA.approve(address(pool), 0);

        uint256 bobBalanceBefore = tokenA.balanceOf(bob);

        uint256 poolBalanceBefore = tokenA.balanceOf(address(pool));

        uint256 reserveABefore = pool.reserveA();
        uint256 reserveBBefore = pool.reserveB();

        vm.prank(bob);
        vm.expectRevert();

        pool.swapAForB(10 ether, 0, block.timestamp + 1 hours);

        assertEq(tokenA.balanceOf(bob), bobBalanceBefore);

        assertEq(tokenA.balanceOf(address(pool)), poolBalanceBefore);

        assertEq(pool.reserveA(), reserveABefore);
        assertEq(pool.reserveB(), reserveBBefore);
    }

    function testInvariantKDoesNotDecrease() public {
        uint256 kBefore = pool.reserveA() * pool.reserveB();

        vm.prank(bob);
        pool.swapAForB(10 ether, 0, block.timestamp + 1 hours);

        uint256 kAfterFirstSwap = pool.reserveA() * pool.reserveB();

        assertGe(kAfterFirstSwap, kBefore);

        vm.prank(bob);
        pool.swapBForA(20 ether, 0, block.timestamp + 1 hours);

        uint256 kAfterSecondSwap = pool.reserveA() * pool.reserveB();

        assertGe(kAfterSecondSwap, kAfterFirstSwap);
    }
}
