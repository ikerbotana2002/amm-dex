
# AMM DEX — Constant Product Decentralized Exchange

A decentralized exchange built from scratch with **Solidity, Foundry and OpenZeppelin**, inspired by the constant-product model of Uniswap V2.

This project implements ERC-20 token swaps, liquidity pools, LP shares, trading fees and transaction protection mechanisms.

**Status:** Educational prototype — not production-ready.

## Features

- Two-token ERC-20 liquidity pool
- Initial liquidity provisioning
- Additional proportional liquidity deposits
- ERC-20 liquidity provider (LP) shares
- Partial and full liquidity withdrawals
- Bidirectional token swaps (Token A ↔ Token B)
- Constant-product pricing (`x * y = k`)
- 0.3% trading fee retained in the pool
- Minimum output and transaction deadline protection
- SafeERC20 transfers and ReentrancyGuard
- Events, custom errors and reserve accounting
- Foundry unit, fuzz and adversarial tests

## Architecture

```text
                    Users
                      |
          +-----------+-----------+
          |                       |
   Liquidity Providers          Traders
          |                       |
   addLiquidity()          swapAForB()
   removeLiquidity()       swapBForA()
          |                       |
          +-----------+-----------+
                      |
                  AMMPool
                 /   |   \
                /    |    \
          Token A  LP ERC20  Token B
```

### Main contracts

| Contract | Purpose |
|---|---|
| `src/MockToken.sol` | Mock ERC-20 assets for testing |
| `src/AMMPool.sol` | Liquidity management, LP shares, swaps and reserve accounting |

The pool itself inherits from OpenZeppelin ERC20 and issues `AMM-LP` tokens to represent liquidity ownership.

## Swap mathematics

The pool uses the constant-product model:

`reserveA * reserveB = k`

For a swap with a 0.3% fee:

```text
amountInWithFee = amountIn * 997

amountOut =
    (amountInWithFee * reserveOut)
    /
    (reserveIn * 1000 + amountInWithFee)
```

The pool receives the full input amount. The trading fee reduces the output calculated for the trader and remains within the pool's assets.

For supported standard tokens, a successful swap updates reserves as follows:

```text
reserveIn  += amountIn
reserveOut -= amountOut
```

## Liquidity provider shares

The initial liquidity provider receives shares based on:

```text
initialShares = sqrt(amountA * amountB)
```

Additional liquidity is deposited in proportion to the existing reserves.

LP shares represent a proportional claim on the current pool reserves, not a promise to recover the exact token amounts originally deposited.

When liquidity is removed:

```text
amountA = shares * reserveA / totalSupply
amountB = shares * reserveB / totalSupply
```

The LP shares are burned, and the corresponding underlying tokens are transferred to the provider.

Trading fees remain in the pool and can affect the value represented by LP shares. Liquidity providing still carries market risk and may underperform simply holding the underlying tokens.

## Installation

Requirements:

- Foundry
- Git

Clone with dependencies:

```bash
git clone --recurse-submodules https://github.com/ikerbotana2002/amm-dex.git
cd amm-dex
```

Build:

```bash
forge build
```

Run all tests:

```bash
forge test -vv
```

Run security fuzz tests with 1,000 cases per fuzz test:

```bash
forge test --match-contract AMMSecurityTest --fuzz-runs 1000 -vv
```

Check contract sizes:

```bash
forge build --sizes
```

## Tests

**Latest verified local result: 54 passing tests, 0 failing.**

| Test file | Coverage |
|---|---|
| `MockToken.t.sol` | ERC-20 balances, allowances and transfers |
| `AMMPool.t.sol` | Pool initialization, deposits and validation |
| `AMMSwap.t.sol` | Bidirectional swaps, fee calculations and reserve changes |
| `AMMLiquidity.t.sol` | LP shares, proportional deposits and withdrawals |
| `AMMSlippage.t.sol` | Deadlines, price changes and execution limits |
| `AMMSecurity.t.sol` | Fuzzing, reserve properties, donations and reinitialization |
| `AMMReentrancy.t.sol` | Attempted reentrancy using a malicious test token |

Note: The currently verified 49-test result reflects the tests detected by Foundry in the local checkout. Check the repository's current test files before relying on the complete list above.

The four fuzz tests also passed with 1,000 runs each.

Latest measured `AMMPool` runtime size: **7,347 bytes**.

## Security considerations and limitations

This is an educational protocol and has not undergone an independent security audit.

Known limitations include:

1. **Direct token donations:** Tokens transferred directly to the pool do not automatically update recorded reserves or mint LP shares. Unaccounted balances may remain after complete liquidity withdrawal and reinitialization.

2. **Minimum liquidity lock:** The simplified LP minting system does not permanently lock minimum initial liquidity, unlike the classic Uniswap V2 design.

3. **Token compatibility:** The implementation targets ordinary ERC-20 tokens. Fee-on-transfer, rebasing and malicious tokens are not fully supported.

4. **Arithmetic and rounding:** Some intermediate multiplications may overflow for extreme values. Solidity integer division rounds down and small amounts may produce zero output or zero shares.

5. **MEV and slippage:** Minimum output and deadline protections do not eliminate sandwich attacks, transaction ordering risks or all forms of price manipulation.

6. **Oracle limitations:** Pool reserve ratios are not reliable standalone external price oracles.

7. **Event warnings:** Foundry reports `reentrancy-events` lint warnings for certain events emitted after external interactions. The associated execution paths require careful review before production use.

8. **Timestamp assumptions:** Deadline checks use `block.timestamp`, which is appropriate for coarse transaction expiry but not a perfectly precise time source.

9. **Liquidity protection:** Initial liquidity provisioning and additional deposits do not implement every protection expected of a production AMM/router design.

Do not use this contract to manage real funds.

## Technologies

- Solidity 0.8.x
- Foundry (Forge)
- OpenZeppelin Contracts 5.x
- ERC-20
- GitHub Actions

## Español — Resumen

Este proyecto implementa un exchange descentralizado educativo basado en una piscina de liquidez de dos tokens ERC-20.

Permite aportar y retirar liquidez, recibir LP tokens como representación de propiedad, realizar intercambios en ambas direcciones y aplicar una comisión del 0,3%.

Se han desarrollado pruebas funcionales, pruebas fuzz y escenarios de seguridad, incluyendo un intento de reentrancy y operaciones con tokens enviados directamente al contrato.

**Advertencia:** Es un proyecto de aprendizaje y portfolio. No está auditado ni preparado para utilizar dinero real.
