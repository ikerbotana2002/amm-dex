// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockToken} from "../src/MockToken.sol";
import {AMMPool} from "../src/AMMPool.sol";

contract AMMSlippageTest is Test {
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

        tokenA.transfer(alice, 100 ether);
        tokenB.transfer(alice, 200 ether);

        vm.startPrank(alice);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        pool.addInitialLiquidity(100 ether, 200 ether);
        vm.stopPrank();

        tokenA.transfer(bob, 100 ether);
        tokenA.transfer(charlie, 100 ether);

        vm.prank(bob);
        tokenA.approve(address(pool), type(uint256).max);

        vm.prank(charlie);
        tokenA.approve(address(pool), type(uint256).max);
    }

    function testSwapBeforeDeadline() public {
        uint256 deadline = block.timestamp + 1 hours;
        vm.warp(block.timestamp + 30 minutes);

        vm.prank(bob);
        uint256 output = pool.swapAForB(10 ether, 0, deadline);

        assertGt(output, 0);
    }

    function testSwapExactlyAtDeadline() public {
        uint256 deadline = block.timestamp + 1 hours;
        vm.warp(deadline);

        vm.prank(bob);
        uint256 output = pool.swapAForB(10 ether, 0, deadline);

        assertGt(output, 0);
    }

    function test_RevertWhen_DeadlineExpired() public {
        uint256 deadline = block.timestamp + 1 hours;
        vm.warp(deadline + 1);

        vm.expectRevert(abi.encodeWithSelector(AMMPool.DeadlineExpired.selector, block.timestamp, deadline));

        vm.prank(bob);
        pool.swapAForB(10 ether, 0, deadline);

        assertEq(pool.reserveA(), 100 ether);
        assertEq(pool.reserveB(), 200 ether);
    }

    function test_RevertWhen_PriceChanges() public {
        uint256 deadline = block.timestamp + 1 hours;

        // Bob consulta el precio inicial.
        uint256 initialQuote = pool.getAmountOut(10 ether, pool.reserveA(), pool.reserveB());

        // Bob solo admite un 1% de slippage.
        uint256 minimumOutput = initialQuote * 99 / 100;

        // Charlie se adelanta y vende Token A.
        vm.prank(charlie);
        pool.swapAForB(20 ether, 0, deadline);

        uint256 bobBalanceBefore = tokenA.balanceOf(bob);

        // Ahora Bob recibiría menos del mínimo aceptado.
        vm.expectRevert(AMMPool.InsufficientOutputAmount.selector);

        vm.prank(bob);
        pool.swapAForB(10 ether, minimumOutput, deadline);

        // Bob no pierde sus Token A.
        assertEq(tokenA.balanceOf(bob), bobBalanceBefore);

        // Solo el intercambio de Charlie tuvo efecto.
        assertEq(pool.reserveA(), 120 ether);
    }

    function test_RevertWhen_ReverseSwapExpired() public {
        uint256 deadline = block.timestamp + 10 minutes;

        // Simulamos que la transacción llega un segundo tarde.
        vm.warp(deadline + 1);

        // Comprobamos el error personalizado y sus argumentos.
        vm.expectRevert(abi.encodeWithSelector(AMMPool.DeadlineExpired.selector, deadline + 1, deadline));

        vm.prank(bob);
        pool.swapBForA(10 ether, 0, deadline);
    }
}
