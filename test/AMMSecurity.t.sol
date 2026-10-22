// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockToken} from "../src/MockToken.sol";
import {AMMPool} from "../src/AMMPool.sol";

contract AMMSecurityTest is Test {
    MockToken tokenA;
    MockToken tokenB;
    AMMPool pool;

    address alice = address(0xA1);
    address bob = address(0xB1);

    function setUp() public {
        tokenA = new MockToken("Token A", "TKA");
        tokenB = new MockToken("Token B", "TKB");

        pool = new AMMPool(address(tokenA), address(tokenB));

        // Alice proporciona liquidez inicial.
        tokenA.transfer(alice, 1_000 ether);
        tokenB.transfer(alice, 2_000 ether);

        vm.startPrank(alice);

        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);

        pool.addInitialLiquidity(500 ether, 1_000 ether);

        vm.stopPrank();

        // Bob recibe tokens para efectuar swaps.
        tokenA.transfer(bob, 500 ether);
        tokenB.transfer(bob, 1_000 ether);

        vm.startPrank(bob);

        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);

        vm.stopPrank();
    }

    // ---------------------------------------------------------
    // FUZZ TESTING: SWAP A -> B
    // ---------------------------------------------------------

    function testFuzzSwapAForB(uint256 amountIn) public {
        amountIn = bound(amountIn, 1 ether, 100 ether);

        uint256 kBefore = pool.reserveA() * pool.reserveB();

        uint256 bobABefore = tokenA.balanceOf(bob);
        uint256 bobBBefore = tokenB.balanceOf(bob);

        uint256 expectedOut = pool.getAmountOut(amountIn, pool.reserveA(), pool.reserveB());

        vm.prank(bob);
        uint256 amountOut = pool.swapAForB(amountIn, 0, block.timestamp + 1 hours);

        assertEq(amountOut, expectedOut);

        // Bob entrega exactamente amountIn Token A.
        assertEq(tokenA.balanceOf(bob), bobABefore - amountIn);

        // Bob recibe exactamente amountOut Token B.
        assertEq(tokenB.balanceOf(bob), bobBBefore + amountOut);

        // Las reservas coinciden con los saldos reales.
        assertEq(pool.reserveA(), tokenA.balanceOf(address(pool)));

        assertEq(pool.reserveB(), tokenB.balanceOf(address(pool)));

        // El producto de las reservas no disminuye.
        uint256 kAfter = pool.reserveA() * pool.reserveB();

        assertGe(kAfter, kBefore);
    }

    // ---------------------------------------------------------
    // FUZZ TESTING: SWAP B -> A
    // ---------------------------------------------------------

    function testFuzzSwapBForA(uint256 amountIn) public {
        amountIn = bound(amountIn, 1 ether, 200 ether);

        uint256 kBefore = pool.reserveA() * pool.reserveB();

        vm.prank(bob);
        pool.swapBForA(amountIn, 0, block.timestamp + 1 hours);

        assertEq(pool.reserveA(), tokenA.balanceOf(address(pool)));

        assertEq(pool.reserveB(), tokenB.balanceOf(address(pool)));

        assertGe(pool.reserveA() * pool.reserveB(), kBefore);
    }

    // ---------------------------------------------------------
    // FUZZ TESTING: DOS SWAPS CONSECUTIVOS
    // ---------------------------------------------------------

    function testFuzzTwoSwaps(uint256 amountA, uint256 amountB) public {
        amountA = bound(amountA, 1 ether, 50 ether);
        amountB = bound(amountB, 1 ether, 100 ether);

        uint256 kBefore = pool.reserveA() * pool.reserveB();

        vm.startPrank(bob);

        pool.swapAForB(amountA, 0, block.timestamp + 1 hours);

        uint256 kMiddle = pool.reserveA() * pool.reserveB();

        pool.swapBForA(amountB, 0, block.timestamp + 1 hours);

        vm.stopPrank();

        uint256 kAfter = pool.reserveA() * pool.reserveB();

        assertGe(kMiddle, kBefore);
        assertGe(kAfter, kMiddle);

        assertEq(pool.reserveA(), tokenA.balanceOf(address(pool)));

        assertEq(pool.reserveB(), tokenB.balanceOf(address(pool)));
    }

    // ---------------------------------------------------------
    // FUZZ TESTING: RETIRAR LP TOKENS
    // ---------------------------------------------------------

    function testFuzzRemoveLiquidity(uint256 sharesToBurn) public {
        uint256 aliceShares = pool.balanceOf(alice);

        sharesToBurn = bound(sharesToBurn, 1 ether, aliceShares);

        uint256 supplyBefore = pool.totalSupply();

        uint256 aliceABefore = tokenA.balanceOf(alice);
        uint256 aliceBBefore = tokenB.balanceOf(alice);

        vm.prank(alice);
        (uint256 amountA, uint256 amountB) = pool.removeLiquidity(sharesToBurn, 0, 0);

        assertEq(pool.totalSupply(), supplyBefore - sharesToBurn);

        assertEq(pool.balanceOf(alice), aliceShares - sharesToBurn);

        assertEq(tokenA.balanceOf(alice), aliceABefore + amountA);

        assertEq(tokenB.balanceOf(alice), aliceBBefore + amountB);

        assertEq(pool.reserveA(), tokenA.balanceOf(address(pool)));

        assertEq(pool.reserveB(), tokenB.balanceOf(address(pool)));
    }

    // ---------------------------------------------------------
    // DONACION DIRECTA
    // ---------------------------------------------------------

    function testDirectDonationDoesNotMintLPTokens() public {
        uint256 supplyBefore = pool.totalSupply();
        uint256 sharesBefore = pool.balanceOf(bob);

        vm.prank(bob);
        tokenA.transfer(address(pool), 10 ether);

        // Los tokens llegan al contrato.
        assertEq(tokenA.balanceOf(address(pool)), 510 ether);

        // Pero las reservas registradas siguen igual.
        assertEq(pool.reserveA(), 500 ether);

        // Bob no recibe participaciones por donar.
        assertEq(pool.balanceOf(bob), sharesBefore);
        assertEq(pool.totalSupply(), supplyBefore);
    }

    function testDonationRemainsUnaccountedAfterFullWithdrawal() public {
        // Donación no registrada.
        vm.prank(bob);
        tokenA.transfer(address(pool), 10 ether);

        uint256 aliceShares = pool.balanceOf(alice);

        vm.prank(alice);
        pool.removeLiquidity(aliceShares, 0, 0);

        // Se han retirado todas las reservas registradas.
        assertEq(pool.reserveA(), 0);
        assertEq(pool.reserveB(), 0);
        assertEq(pool.totalSupply(), 0);

        // Pero los tokens donados siguen en el contrato.
        assertEq(tokenA.balanceOf(address(pool)), 10 ether);
    }
}
