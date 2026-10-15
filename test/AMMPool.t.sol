// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockToken} from "../src/MockToken.sol";
import {AMMPool} from "../src/AMMPool.sol";

contract AMMPoolTest is Test {
    MockToken tokenA;
    MockToken tokenB;
    AMMPool pool;

    address alice = address(0xA1);
    address bob = address(0xB1);

    function setUp() public {
        tokenA = new MockToken("Token A", "TKA");
        tokenB = new MockToken("Token B", "TKB");

        pool = new AMMPool(address(tokenA), address(tokenB));

        tokenA.transfer(alice, 1_000 ether);
        tokenB.transfer(alice, 2_000 ether);

        vm.startPrank(alice);

        tokenA.approve(address(pool), type(uint256).max);

        tokenB.approve(address(pool), type(uint256).max);

        vm.stopPrank();
    }

    function testPoolTokens() public view {
        assertEq(address(pool.tokenA()), address(tokenA));

        assertEq(address(pool.tokenB()), address(tokenB));
    }

    function testInitialReservesAreZero() public view {
        (uint256 reserveA, uint256 reserveB) = pool.getReserves();

        assertEq(reserveA, 0);
        assertEq(reserveB, 0);
    }

    function testAddInitialLiquidity() public {
        vm.prank(alice);
        pool.addInitialLiquidity(100 ether, 200 ether);

        (uint256 reserveA, uint256 reserveB) = pool.getReserves();

        assertEq(reserveA, 100 ether);
        assertEq(reserveB, 200 ether);

        assertEq(tokenA.balanceOf(address(pool)), 100 ether);

        assertEq(tokenB.balanceOf(address(pool)), 200 ether);

        assertEq(tokenA.balanceOf(alice), 900 ether);

        assertEq(tokenB.balanceOf(alice), 1_800 ether);
    }

    function testCannotAddZeroLiquidity() public {
        vm.prank(alice);

        vm.expectRevert(AMMPool.InvalidAmount.selector);

        pool.addInitialLiquidity(100 ether, 0);
    }

    function testCannotInitializeTwice() public {
        vm.prank(alice);
        pool.addInitialLiquidity(100 ether, 200 ether);

        vm.prank(bob);

        vm.expectRevert(AMMPool.PoolAlreadyInitialized.selector);

        pool.addInitialLiquidity(50 ether, 100 ether);
    }

    function testCannotUseIdenticalTokens() public {
        vm.expectRevert(AMMPool.IdenticalTokens.selector);

        new AMMPool(address(tokenA), address(tokenA));
    }

    function testCannotUseZeroAddress() public {
        vm.expectRevert(AMMPool.InvalidToken.selector);

        new AMMPool(address(tokenA), address(0));
    }

    function testCannotDepositWithoutApproval() public {
        tokenA.transfer(bob, 100 ether);
        tokenB.transfer(bob, 200 ether);

        vm.prank(bob);
        vm.expectRevert();

        pool.addInitialLiquidity(100 ether, 200 ether);

        assertEq(tokenA.balanceOf(address(pool)), 0);
        assertEq(tokenB.balanceOf(address(pool)), 0);
    }

    function testDirectTransferDoesNotUpdateReserves() public {
        tokenA.transfer(address(pool), 10 ether);

        (uint256 reserveA, uint256 reserveB) = pool.getReserves();

        assertEq(reserveA, 0);
        assertEq(reserveB, 0);

        assertEq(tokenA.balanceOf(address(pool)), 10 ether);
    }

    function testEmitsInitialLiquidityEvent() public {
        vm.expectEmit(true, false, false, true);

        emit AMMPool.InitialLiquidityAdded(alice, 100 ether, 200 ether);

        vm.prank(alice);
        pool.addInitialLiquidity(100 ether, 200 ether);
    }

    function test_RevertWhen_SecondTokenNotApproved() public {
        vm.prank(alice);
        tokenB.approve(address(pool), 0);

        uint256 aliceBalanceA = tokenA.balanceOf(alice);

        uint256 aliceBalanceB = tokenB.balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert();

        pool.addInitialLiquidity(100 ether, 200 ether);

        assertEq(tokenA.balanceOf(alice), aliceBalanceA);

        assertEq(tokenB.balanceOf(alice), aliceBalanceB);

        assertEq(tokenA.balanceOf(address(pool)), 0);

        assertEq(tokenB.balanceOf(address(pool)), 0);
    }
}
