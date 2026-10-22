// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {MockToken} from "../src/MockToken.sol";
import {AMMPool} from "../src/AMMPool.sol";

// Token ERC-20 creado exclusivamente para probar ataques.
// NO debe utilizarse como token normal de producción.
contract MaliciousToken is ERC20 {
    AMMPool public pool;

    bool public attackEnabled;
    bool public attackAttempted;
    bool public attackSucceeded;

    constructor() ERC20("Malicious Token", "MAL") {
        _mint(msg.sender, 1_000_000 ether);
    }

    function configureAttack(address pool_) external {
        pool = AMMPool(pool_);
    }

    function enableAttack() external {
        attackEnabled = true;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        if (attackEnabled && to == address(pool) && from != address(0)) {
            // Evitar intentar el ataque repetidamente.
            attackEnabled = false;
            attackAttempted = true;

            // Intentar reentrar mientras se procesa
            // la transferencia del token malicioso.
            (bool success,) =
                address(pool).call(abi.encodeCall(AMMPool.swapBForA, (1 ether, 0, block.timestamp + 1 hours)));

            attackSucceeded = success;
        }
    }
}

contract AMMReentrancyTest is Test {
    MaliciousToken maliciousToken;
    MockToken tokenB;
    AMMPool pool;

    address alice = address(0xA1);
    address bob = address(0xB1);

    function setUp() public {
        maliciousToken = new MaliciousToken();
        tokenB = new MockToken("Token B", "TKB");

        pool = new AMMPool(address(maliciousToken), address(tokenB));

        maliciousToken.configureAttack(address(pool));

        maliciousToken.transfer(alice, 500 ether);
        tokenB.transfer(alice, 1_000 ether);

        vm.startPrank(alice);

        maliciousToken.approve(address(pool), type(uint256).max);

        tokenB.approve(address(pool), type(uint256).max);

        pool.addInitialLiquidity(100 ether, 200 ether);

        vm.stopPrank();

        maliciousToken.transfer(bob, 100 ether);

        vm.prank(bob);
        maliciousToken.approve(address(pool), type(uint256).max);
    }

    function testReentrancyAttemptIsBlocked() public {
        maliciousToken.enableAttack();

        uint256 expectedOut = pool.getAmountOut(10 ether, 100 ether, 200 ether);

        vm.prank(bob);
        uint256 amountOut = pool.swapAForB(10 ether, 0, block.timestamp + 1 hours);

        // El token malicioso intentó reentrar.
        assertTrue(maliciousToken.attackAttempted());

        // Pero el intento de reentrancy no funcionó.
        assertFalse(maliciousToken.attackSucceeded());

        // La operación exterior sí se completó.
        assertEq(amountOut, expectedOut);

        assertEq(pool.reserveA(), 110 ether);
        assertEq(pool.reserveB(), 200 ether - expectedOut);

        assertEq(tokenB.balanceOf(bob), expectedOut);
    }
}
