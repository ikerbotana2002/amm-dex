// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MockToken} from "../src/MockToken.sol";
import {AMMPool} from "../src/AMMPool.sol";

contract AMMLiquidityTest is Test {
    MockToken tokenA;
    MockToken tokenB;
    AMMPool pool;

    address alice = address(0xA1);
    address bob = address(0xB1);
    address charlie = address(0xC1);

    function setUp() public {
        tokenA = new MockToken("Token A", "TKA");
        tokenB = new MockToken("Token B", "TKB");

        pool = new AMMPool(address(tokenA), address(tokenB));

        tokenA.transfer(alice, 1_000 ether);
        tokenB.transfer(alice, 1_000 ether);

        tokenA.transfer(bob, 1_000 ether);
        tokenB.transfer(bob, 1_000 ether);

        vm.startPrank(alice);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function _initializePool() internal {
        vm.prank(alice);
        pool.addInitialLiquidity(100 ether, 200 ether);
    }

    function testInitialProviderReceivesLPShares() public {
        _initializePool();

        uint256 expectedShares = Math.sqrt(uint256(100 ether) * uint256(200 ether));

        assertEq(pool.balanceOf(alice), expectedShares);
        assertEq(pool.totalSupply(), expectedShares);

        assertEq(pool.name(), "AMM Liquidity Provider");
        assertEq(pool.symbol(), "AMM-LP");
    }

    function testAdditionalLiquidityMintsProportionalShares() public {
        _initializePool();

        uint256 initialSupply = pool.totalSupply();

        vm.prank(bob);

        (uint256 amountA, uint256 amountB, uint256 shares) = pool.addLiquidity(50 ether, 100 ether, 50 ether, 100 ether);

        uint256 expectedShares = Math.mulDiv(50 ether, initialSupply, 100 ether);

        assertEq(amountA, 50 ether);
        assertEq(amountB, 100 ether);
        assertEq(shares, expectedShares);

        assertEq(pool.balanceOf(bob), expectedShares);
        assertEq(pool.totalSupply(), initialSupply + shares);

        assertEq(pool.reserveA(), 150 ether);
        assertEq(pool.reserveB(), 300 ether);
    }

    function testExcessDesiredTokensAreNotTransferred() public {
        _initializePool();

        uint256 bobBalanceBefore = tokenB.balanceOf(bob);

        vm.prank(bob);

        (uint256 amountA, uint256 amountB,) = pool.addLiquidity(50 ether, 150 ether, 0, 0);

        assertEq(amountA, 50 ether);
        assertEq(amountB, 100 ether);

        assertEq(tokenB.balanceOf(bob), bobBalanceBefore - 100 ether);
    }

    function testRemoveAllLiquidity() public {
        _initializePool();

        uint256 shares = pool.balanceOf(alice);

        vm.prank(alice);

        (uint256 amountA, uint256 amountB) = pool.removeLiquidity(shares, 100 ether, 200 ether);

        assertEq(amountA, 100 ether);
        assertEq(amountB, 200 ether);

        assertEq(pool.balanceOf(alice), 0);
        assertEq(pool.totalSupply(), 0);

        assertEq(pool.reserveA(), 0);
        assertEq(pool.reserveB(), 0);

        assertEq(tokenA.balanceOf(address(pool)), 0);
        assertEq(tokenB.balanceOf(address(pool)), 0);
    }

    function testTwoProvidersWithdrawTheirShares() public {
        _initializePool();

        vm.prank(bob);
        pool.addLiquidity(100 ether, 200 ether, 100 ether, 200 ether);

        uint256 bobShares = pool.balanceOf(bob);
        uint256 totalSharesBefore = pool.totalSupply();

        uint256 expectedA = Math.mulDiv(bobShares, pool.reserveA(), totalSharesBefore);

        uint256 expectedB = Math.mulDiv(bobShares, pool.reserveB(), totalSharesBefore);

        vm.prank(bob);

        (uint256 amountA, uint256 amountB) = pool.removeLiquidity(bobShares, 0, 0);

        assertEq(amountA, expectedA);
        assertEq(amountB, expectedB);

        assertEq(pool.balanceOf(bob), 0);
        assertGt(pool.balanceOf(alice), 0);
    }

    function testLPSharesCanBeTransferred() public {
        _initializePool();

        uint256 sharesToTransfer = pool.balanceOf(alice) / 2;

        vm.prank(alice);
        pool.transfer(charlie, sharesToTransfer);

        assertEq(pool.balanceOf(charlie), sharesToTransfer);

        uint256 charlieBalanceBefore = tokenA.balanceOf(charlie);

        vm.prank(charlie);
        (uint256 amountA,) = pool.removeLiquidity(sharesToTransfer, 0, 0);

        assertGt(amountA, 0);

        assertEq(tokenA.balanceOf(charlie), charlieBalanceBefore + amountA);
    }

    function testProviderRedeemsPoolReservesAfterSwap() public {
        _initializePool();

        // Bob trades Token A for Token B.
        vm.prank(bob);
        pool.swapAForB(10 ether, 0, block.timestamp + 1 hours);

        assertEq(pool.reserveA(), 110 ether);

        uint256 shares = pool.balanceOf(alice);

        vm.prank(alice);

        (uint256 amountA, uint256 amountB) = pool.removeLiquidity(shares, 0, 0);

        // Alice owned all the LP shares.
        assertEq(amountA, 110 ether);

        // Output includes the effect of the 0.3% fee.
        uint256 swapOut = pool.getAmountOut(10 ether, 100 ether, 200 ether);

        assertEq(amountB, 200 ether - swapOut);
    }

    function test_RevertWhen_NoLPShares() public {
        _initializePool();

        vm.prank(bob);

        vm.expectRevert(AMMPool.InsufficientLPShares.selector);

        pool.removeLiquidity(1 ether, 0, 0);
    }

    function test_RevertWhen_ZeroSharesBurned() public {
        _initializePool();

        vm.prank(alice);

        vm.expectRevert(AMMPool.InvalidAmount.selector);

        pool.removeLiquidity(0, 0, 0);
    }

    function test_RevertWhen_DepositMinimumNotMet() public {
        _initializePool();

        vm.prank(bob);

        vm.expectRevert(AMMPool.SlippageExceeded.selector);

        pool.addLiquidity(50 ether, 150 ether, 50 ether, 101 ether);
    }

    function test_RevertWhen_WithdrawalMinimumNotMet() public {
        _initializePool();

        uint256 shares = pool.balanceOf(alice);

        vm.prank(alice);

        vm.expectRevert(AMMPool.SlippageExceeded.selector);

        pool.removeLiquidity(shares, 101 ether, 200 ether);
    }

    function test_RevertWhen_AdditionalLiquidityBeforeInit() public {
        vm.prank(bob);

        vm.expectRevert(AMMPool.PoolNotInitialized.selector);

        pool.addLiquidity(50 ether, 100 ether, 0, 0);
    }
}
