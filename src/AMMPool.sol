// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract AMMPool is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidToken();
    error IdenticalTokens();
    error InvalidAmount();
    error PoolAlreadyInitialized();
    error PoolNotInitialized();
    error InsufficientLiquidity();
    error InsufficientOutputAmount();
    error UnsupportedToken();
    error InsufficientLPShares();
    error SlippageExceeded();
    error DeadlineExpired(uint256 currentTimestamp, uint256 deadline);

    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;

    uint256 public reserveA;
    uint256 public reserveB;

    event InitialLiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB);

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 shares);

    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB, uint256 shares);

    event TokensSwapped(
        address indexed trader, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut
    );

    constructor(address tokenA_, address tokenB_) ERC20("AMM Liquidity Provider", "AMM-LP") {
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

    // ---------------------------------------------------------
    // INITIAL LIQUIDITY
    // ---------------------------------------------------------

    function addInitialLiquidity(uint256 amountA, uint256 amountB) external nonReentrant {
        if (totalSupply() != 0) {
            revert PoolAlreadyInitialized();
        }

        if (amountA == 0 || amountB == 0) {
            revert InvalidAmount();
        }

        // Initial shares are based on the geometric mean.
        uint256 shares = Math.sqrt(amountA * amountB);

        if (shares == 0) {
            revert InsufficientLPShares();
        }

        _receiveTokens(amountA, amountB);

        reserveA = amountA;
        reserveB = amountB;

        _mint(msg.sender, shares);

        emit InitialLiquidityAdded(msg.sender, amountA, amountB);

        emit LiquidityAdded(msg.sender, amountA, amountB, shares);
    }

    // ---------------------------------------------------------
    // ADD MORE LIQUIDITY
    // ---------------------------------------------------------

    function addLiquidity(uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin)
        external
        nonReentrant
        returns (uint256 amountA, uint256 amountB, uint256 shares)
    {
        if (reserveA == 0 || reserveB == 0) {
            revert PoolNotInitialized();
        }

        if (amountADesired == 0 || amountBDesired == 0) {
            revert InvalidAmount();
        }

        uint256 supply = totalSupply();

        // Determine the correct deposit amounts using
        // the pool's current reserve ratio.
        uint256 amountBOptimal = Math.mulDiv(amountADesired, reserveB, reserveA);

        if (amountBOptimal <= amountBDesired) {
            amountA = amountADesired;
            amountB = amountBOptimal;
        } else {
            amountA = Math.mulDiv(amountBDesired, reserveA, reserveB);

            amountB = amountBDesired;
        }

        if (amountA == 0 || amountB == 0) {
            revert InvalidAmount();
        }

        if (amountA < amountAMin || amountB < amountBMin) {
            revert SlippageExceeded();
        }

        uint256 sharesFromA = Math.mulDiv(amountA, supply, reserveA);

        uint256 sharesFromB = Math.mulDiv(amountB, supply, reserveB);

        shares = Math.min(sharesFromA, sharesFromB);

        if (shares == 0) {
            revert InsufficientLPShares();
        }

        _receiveTokens(amountA, amountB);

        reserveA += amountA;
        reserveB += amountB;

        _mint(msg.sender, shares);

        emit LiquidityAdded(msg.sender, amountA, amountB, shares);
    }

    // ---------------------------------------------------------
    // REMOVE LIQUIDITY
    // ---------------------------------------------------------

    function removeLiquidity(uint256 shares, uint256 amountAMin, uint256 amountBMin)
        external
        nonReentrant
        returns (uint256 amountA, uint256 amountB)
    {
        if (shares == 0) {
            revert InvalidAmount();
        }

        uint256 supply = totalSupply();

        if (supply == 0) {
            revert PoolNotInitialized();
        }

        if (balanceOf(msg.sender) < shares) {
            revert InsufficientLPShares();
        }

        amountA = Math.mulDiv(shares, reserveA, supply);

        amountB = Math.mulDiv(shares, reserveB, supply);

        if (amountA == 0 || amountB == 0) {
            revert InsufficientLiquidity();
        }

        if (amountA < amountAMin || amountB < amountBMin) {
            revert SlippageExceeded();
        }

        _burn(msg.sender, shares);

        reserveA -= amountA;
        reserveB -= amountB;

        tokenA.safeTransfer(msg.sender, amountA);
        tokenB.safeTransfer(msg.sender, amountB);

        emit LiquidityRemoved(msg.sender, amountA, amountB, shares);
    }

    // ---------------------------------------------------------
    // SWAP CALCULATION
    // ---------------------------------------------------------

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

    // ---------------------------------------------------------
    // SWAP TOKEN A FOR TOKEN B
    // ---------------------------------------------------------

    function swapAForB(uint256 amountIn, uint256 amountOutMin, uint256 deadline)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        // 1. Rechazar transacciones caducadas.
        if (block.timestamp > deadline) {
            revert DeadlineExpired(block.timestamp, deadline);
        }

        // 2. Comprobar que hay liquidez.
        if (reserveA == 0 || reserveB == 0) {
            revert PoolNotInitialized();
        }

        // 3. Calcular la salida con la comisión del 0,3%.
        amountOut = getAmountOut(amountIn, reserveA, reserveB);

        // 4. Proteger al usuario frente a slippage.
        if (amountOut == 0 || amountOut < amountOutMin) {
            revert InsufficientOutputAmount();
        }

        // 5. Registrar el saldo de Token A anterior.
        uint256 balanceBefore = tokenA.balanceOf(address(this));

        // 6. Recibir la cantidad completa de Token A.
        tokenA.safeTransferFrom(msg.sender, address(this), amountIn);

        // 7. Comprobar que hemos recibido lo esperado.
        uint256 received = tokenA.balanceOf(address(this)) - balanceBefore;

        if (received != amountIn) {
            revert UnsupportedToken();
        }

        // 8. Actualizar las reservas.
        reserveA += amountIn;
        reserveB -= amountOut;

        // 9. Entregar Token B.
        tokenB.safeTransfer(msg.sender, amountOut);

        emit TokensSwapped(msg.sender, address(tokenA), address(tokenB), amountIn, amountOut);
    }

    // ---------------------------------------------------------
    // SWAP TOKEN B FOR TOKEN A
    // ---------------------------------------------------------

    function swapBForA(uint256 amountIn, uint256 amountOutMin, uint256 deadline)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (block.timestamp > deadline) {
            revert DeadlineExpired(block.timestamp, deadline);
        }

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

    // ---------------------------------------------------------
    // INTERNAL TOKEN RECEIPT
    // ---------------------------------------------------------

    function _receiveTokens(uint256 amountA, uint256 amountB) internal {
        uint256 balanceABefore = tokenA.balanceOf(address(this));

        uint256 balanceBBefore = tokenB.balanceOf(address(this));

        tokenA.safeTransferFrom(msg.sender, address(this), amountA);

        tokenB.safeTransferFrom(msg.sender, address(this), amountB);

        uint256 receivedA = tokenA.balanceOf(address(this)) - balanceABefore;

        uint256 receivedB = tokenB.balanceOf(address(this)) - balanceBBefore;

        if (receivedA != amountA || receivedB != amountB) {
            revert UnsupportedToken();
        }
    }

    function getReserves() external view returns (uint256, uint256) {
        return (reserveA, reserveB);
    }
}
