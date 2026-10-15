// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract AMMPool is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidToken();
    error IdenticalTokens();
    error InvalidAmount();
    error PoolAlreadyInitialized();
    error UnsupportedToken();
    error PoolNotInitialized();
    error InsufficientOutputAmount();
    error InsufficientLiquidity();

    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;

    uint256 public reserveA;
    uint256 public reserveB;

    event InitialLiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB);
    event TokensSwapped(
        address indexed trader, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    constructor(address tokenA_, address tokenB_) {
        if (tokenA_ == address(0) || tokenB_ == address(0)) {
            revert InvalidToken();
        }

        if (tokenA_ == tokenB_) {
            revert IdenticalTokens();
        }

        if (tokenA_.code.length == 0 || tokenB_.code.length == 0) {
            revert InvalidToken();
        }

        tokenA = IERC20(tokenA_);
        tokenB = IERC20(tokenB_);
    }

    function addInitialLiquidity(uint256 amountA, uint256 amountB) external nonReentrant {
        if (reserveA != 0 || reserveB != 0) {
            revert PoolAlreadyInitialized();
        }

        if (amountA == 0 || amountB == 0) {
            revert InvalidAmount();
        }

        uint256 balanceABefore = tokenA.balanceOf(address(this));

        uint256 balanceBBefore = tokenB.balanceOf(address(this));

        tokenA.safeTransferFrom(msg.sender, address(this), amountA);

        tokenB.safeTransferFrom(msg.sender, address(this), amountB);

        uint256 receivedA = tokenA.balanceOf(address(this)) - balanceABefore;

        uint256 receivedB = tokenB.balanceOf(address(this)) - balanceBBefore;

        if (receivedA != amountA || receivedB != amountB) {
            revert UnsupportedToken();
        }

        reserveA = amountA;
        reserveB = amountB;

        emit InitialLiquidityAdded(msg.sender, amountA, amountB);
    }

    function getReserves() external view returns (uint256, uint256) {
        return (reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0) {
            revert InvalidAmount();
        }

        if (reserveIn == 0 || reserveOut == 0) {
            revert InsufficientLiquidity();
        }

        uint256 amountInWithFee = amountIn * 997;

        uint256 numerator = amountInWithFee * reserveOut;

        uint256 denominator = reserveIn * 1000 + amountInWithFee;

        amountOut = numerator / denominator;
    }

    function swapAForB(uint256 amountIn, uint256 amountOutMin) external nonReentrant returns (uint256 amountOut) {
        if (reserveA == 0 || reserveB == 0) {
            revert PoolNotInitialized();
        }

        amountOut = getAmountOut(amountIn, reserveA, reserveB);

        if (amountOut == 0 || amountOut < amountOutMin) {
            revert InsufficientOutputAmount();
        }

        uint256 balanceBefore = tokenA.balanceOf(address(this));

        tokenA.safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 received = tokenA.balanceOf(address(this)) - balanceBefore;

        if (received != amountIn) {
            revert UnsupportedToken();
        }

        reserveA += amountIn;
        reserveB -= amountOut;

        tokenB.safeTransfer(msg.sender, amountOut);

        emit TokensSwapped(msg.sender, address(tokenA), address(tokenB), amountIn, amountOut);
    }

    function swapBForA(uint256 amountIn, uint256 amountOutMin) external nonReentrant returns (uint256 amountOut) {
        if (reserveA == 0 || reserveB == 0) {
            revert PoolNotInitialized();
        }

        amountOut = getAmountOut(amountIn, reserveB, reserveA);

        if (amountOut == 0 || amountOut < amountOutMin) {
            revert InsufficientOutputAmount();
        }

        uint256 balanceBefore = tokenB.balanceOf(address(this));

        tokenB.safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 received = tokenB.balanceOf(address(this)) - balanceBefore;

        if (received != amountIn) {
            revert UnsupportedToken();
        }

        reserveB += amountIn;
        reserveA -= amountOut;

        tokenA.safeTransfer(msg.sender, amountOut);

        emit TokensSwapped(msg.sender, address(tokenB), address(tokenA), amountIn, amountOut);
    }
}
