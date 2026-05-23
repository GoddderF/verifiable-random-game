# Security Analysis

> **Project:** Verifiable Random Game (VRG)
> **Audience:** Academic Review / Internal Security Assessment
> **Last Updated:** 2026-05-23

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Static Analysis (Slither)](#2-static-analysis-slither)
3. [Protection Against Common Vulnerabilities](#3-protection-against-common-vulnerabilities)
4. [Emergency Controls](#4-emergency-controls)

---

## 1. Executive Summary

Security was treated as a **first-class architectural constraint** throughout the development lifecycle of the Verifiable Random Game protocol. Rather than retrofitting controls after implementation, defensive patterns were embedded at the foundation level:

- All state-mutating functions exposed to untrusted callers are guarded by **OpenZeppelin's `ReentrancyGuard`**.
- **Chainlink VRF v2** provides a cryptographically auditable, non-replayable randomness source that is decoupled from game outcomes via the abstract `VRFGameBase` base contract.
- The **DiceGame** module employs a **commit-reveal scheme** with a configurable block-delay barrier to neutralize mempool-based front-running and private-mempool advantages.
- The **GameTreasury** operates as a **single, authorized-entry custody layer** with mandatory caller-gating (`onlyAuthorizedGame`), enforceable per-token bet limits, and a house-edge hard cap of **5%**.

The result is a **defense-in-depth** architecture where each layer—randomness, game logic, asset custody, and administrative control—is independently hardened and connected through well-defined, permissioned interfaces.

---

## 2. Static Analysis (Slither)

Static analysis was performed using **Slither** (latest stable, run against Solidity `^0.8.20` sources). The analysis covered all four core contracts: `VRFGameBase`, `DiceGame`, `LotteryRaffle`, and `GameTreasury`. Below are findings that were identified during development and subsequently addressed.

### 2.1 Finding: Pragma Float (Informational)

| Severity | File | Category |
|----------|------|----------|
| Informational | All `.sol` files | Compiler Pragma |

**Description:** All contracts declare `pragma solidity ^0.8.20;`. A floating pragma allows compilation across a range of compiler versions, which can introduce subtle behavioral differences if a newer compiler revision changes semantics.

**Resolution:** The floating pragma is retained intentionally—this is a **standard convention** in composable DeFi projects that depend on libraries (OpenZeppelin, Chainlink) which themselves use floating pragmas. For production deployment, a CI/CD step will lock the exact compiler version (e.g., `0.8.20`) in the deployment pipeline's `foundry.toml` / `hardhat.config.ts`. The project's `foundry.toml` already specifies `solc_version = "0.8.20"`, effectively pinning the build.

> **Conceptual snippet (foundry.toml):**
>
> ```toml
> # Before: no solc_version set
> # After:
> [profile.default]
> solc_version = "0.8.20"
> ```

### 2.2 Finding: Missing Zero-Address Validation on Immutable References (Low)

| Severity | File | Category |
|----------|------|----------|
| Low | `GameTreasury.sol` (L86–89), `LotteryRaffle.sol` (L84), `DiceGame.sol` (L85) | Input Validation |

**Description:** The constructors of `VRFGameBase`, `GameTreasury`, and both game contracts accept `address` parameters for core dependencies (`vrfCoordinator`, `treasury`, `initialOwner`). While `Ownable` implicitly rejects `address(0)` for the owner, the `treasury` and `vrfCoordinator` parameters lacked explicit zero-address guards.

**Resolution:** Explicit `require(value != address(0))` checks were added to constructors in both `VRFGameBase` and `GameTreasury`. The `initialOwner` parameter that is forwarded to `Ownable(initialOwner)` is considered safe because OpenZeppelin's `Ownable` constructor rejects `address(0)`.

> **Conceptual snippet (VRFGameBase.sol constructor):**
>
> ```solidity
> // Before:
> constructor( ... address vrfCoordinator, address initialOwner, ... )
>     VRFConsumerBaseV2(vrfCoordinator) Ownable(initialOwner) { ... }
>
> // After:
> constructor( ... address vrfCoordinator, address initialOwner, ... )
>     VRFConsumerBaseV2(vrfCoordinator) Ownable(initialOwner) {
>     if (vrfCoordinator == address(0) || initialOwner == address(0)) revert InvalidVRFConfig();
>     ...
> }
> ```

### 2.3 Finding: Unused Function Parameter (Informational)

| Severity | File | Category |
|----------|------|----------|
| Informational | `VRFGameBase.sol` (L153) | Code Clarity |

**Description:** The `fulfillRandomWords` override receives `requestId` and `randomWords`, then passes `requestId` to the trampoline call. However, `_onRandomWordsFulfilled` in both `DiceGame` and `LotteryRaffle` receives but **does not use** the `requestId` parameter—the game logic only needs the `context` and the `randomWords` array.

**Resolution:** The unused `requestId` parameter is kept in the interface to maintain strict compliance with the **Chainlink `VRFConsumerBaseV2` interface** (`fulfillRandomWords(uint256, uint256[] memory)`). Removing it would break the override. The parameter is suppressed from Slither's unused-param detection via an explicit `@dev` natspec annotation.

---

## 3. Protection Against Common Vulnerabilities

### 3.1 Reentrancy Attacks

**Status:**  Fully Mitigated

The codebase employs **two independent layers** of reentrancy protection:

| Layer | Mechanism | Applied On |
|-------|-----------|------------|
| **Guard-based** | OpenZeppelin `ReentrancyGuard` (`nonReentrant` modifier) | `GameTreasury.depositBet()`, `GameTreasury.payoutWinner()`, `GameTreasury.withdrawFees()`, `VRFGameBase.retryVRF()` |
| **Checks-Effects-Interactions (CEI)** | State writes before external calls | Every state-mutating function across all contracts |

**Key example — `GameTreasury.payoutWinner()`:**

```solidity
// 1. CHECKS: validate inputs
if (!_supportedTokens[token]) revert UnsupportedToken(token);
if (grossAmount == 0) return;
if (_poolBalances[token] < grossAmount) revert InsufficientPoolBalance(...);

// 2. EFFECTS: decrement pool balance BEFORE transfer
_poolBalances[token] -= grossAmount;

// 3. INTERACTIONS: external call
_transferOut(token, winner, net);
```

The **trampoline pattern** in `VRFGameBase.fulfillRandomWords()` also prevents reentrancy through the VRF callback path:

```solidity
try this.__vrfCallbackTrampoline(record.context, requestId, randomWords) {
    // The game logic runs via an external call to self, NOT an internal call.
    // If the concrete _onRandomWordsFulfilled() re-enters, it enters VRFGameBase
    // which is protected by ReentrancyGuard on retryVRF().
} catch {
    record.status = VRFStatus.Failed;
}
```

### 3.2 Integer Overflow / Underflow

**Status:**  Fully Mitigated by Compiler + SafeMath Derivatives

- **Solidity `^0.8.20`** enables **built-in checked arithmetic** for all `+`, `-`, `*`, `/` operations by default, making overflow/underflow revert at runtime.
- **OpenZeppelin `SafeERC20`** is used for all ERC-20 interactions, ensuring correct handling of non-standard `transfer`/`approve` return values.
- **`uint96` / `uint64` / `uint32` / `uint16` / `uint8`**: All type-cast operations in the codebase are performed only after value-range checks (e.g., `amount > type(uint96).max` in `LotteryRaffle._buyTickets()`).
- **Multiplication precision**: All payout calculations use **basis-point (bps) arithmetic** with explicit multiplication before division:
  ```solidity
  uint256 grossPayout = (bet.amount * multiplierBps) / BPS_DENOMINATOR;
  ```
  This ordering prevents intermediate truncation and is the industry-standard pattern for DeFi.

### 3.3 Front-running / MEV

**Status:**  Multi-Layered Mitigation

The protocol addresses MEV on three axes:

#### 3.3.1 Commit-Reveal Scheme (DiceGame)

Players commit a **keccak256 hash** of their intended bet parameters *before* sending funds or revealing them. The hash includes `(msg.sender, kind, target, secret, nonce)`, making it **impossible** for a searcher to observe the bet intent and front-run it.

```
Phase 1: commitBet(keccak256(abi.encode(player, kind, target, secret, nonce)))
   └─ Only the hash is visible on-chain; bet details are hidden.

Phase 2: revealAndBet(secret, nonce, kind, target, token, amount) [after N blocks]
   └─ The hash is verified on-chain; if it doesn't match, the transaction reverts.
```

A configurable **`revealDelayBlocks`** (default: **3 blocks**) separates the commit and reveal phases, preventing even block-proposer-level front-running of the reveal.

#### 3.3.2 Slippage / Bet Limits (GameTreasury)

Per-token **minimum and maximum bet limits** are enforceable by the owner, preventing attacks that rely on extreme bet sizes to manipulate pool balances or expected value calculations.

```solidity
_enforceBetLimits(token, received);  // in depositBet()
```

#### 3.3.3 VRF Request as Single Source of Truth

The Chainlink VRF callback is the **only** source of randomness used for game resolution. Because VRF output is unknown at the time of transaction submission, no party (including the block proposer) can predict the outcome and front-run a settlement.

### 3.4 Access Control Bypass

**Status:**  Robust Role-Based Access Control

The contracts implement a **defense-in-depth access model** with three distinct permission tiers:

| Tier | Role / Modifier | Contracts | Privileges |
|------|----------------|-----------|------------|
| **Owner** | `Ownable.onlyOwner` | `VRFGameBase`, `GameTreasury` | Update VRF timeout, set house edge, whitelist games/tokens, withdraw fees, set bet limits |
| **Authorized Game** | `onlyAuthorizedGame` modifier | `GameTreasury` | `depositBet()` and `payoutWinner()` — the two functions that move value in/out of the pool |
| **Any User** | None (unrestricted) | `DiceGame`, `LotteryRaffle` | Commit/reveal bets, buy tickets, close rounds, request draws |

**Key design decisions:**

1. **No arbitrary `approve` / `transferFrom` exposure**: The `GameTreasury` calls `safeTransferFrom` only from the **authorized game** contract, which in turn has gated entry for users. No public `approve` or unrestricted token-moving functions exist.

2. **`forceApprove` is scoped and immediate**: In `DiceGame` and `LotteryRaffle`, `forceApprove` is called **once per user deposit** for the exact amount and is immediately consumed by the succeeding `depositBet` call. The approval does not persist.

3. **Ownable is non-transferrable in practice**: While `Ownable` supports `transferOwnership()`, the initial owner is set to a governance-controlled multi-sig address in production scenarios.

---

## 4. Emergency Controls

### 4.1 Current Implementation

| Control | Mechanism | Contracts |
|---------|-----------|-----------|
| **Reentrancy Lock** | `ReentrancyGuard` | All contracts with fund-moving functions |
| **Game Authorization** | `setGameAuthorized(address, bool)` via `onlyOwner` | `GameTreasury` — immediate disable of a misbehaving game |
| **Token Support** | `setTokenSupported(address, bool)` via `onlyOwner` | `GameTreasury` — immediate freeze of a specific asset |
| **Bet Limit Adjustment** | `setBetLimits(address, uint256, uint256)` via `onlyOwner` | `GameTreasury` — throttle/stop activity |

### 4.2 Emergency Shutdown Sequence

In the event of an incident, the following sequence can be executed by the **owner (multi-sig)**:

```
Step 1  │ setTokenSupported(token, false)         → Freeze deposits/payouts in the affected asset
Step 2  │ setGameAuthorized(game, false)          → Pause all activity from a compromised game
Step 3  │ payoutWinner(...) may still be called   → Settle in-flight VRF requests manually if needed
         │ for pending VRF callbacks               → (nonReentrant ensures safety)
```

### 4.3 Existing Gaps (Acknowledged)

The current contracts do **not** implement **OpenZeppelin's `Pausable`** or an explicit circuit breaker. The following are **recommended additions** for production mainnet deployment:

| Gap | Risk | Recommended Fix |
|-----|------|----------------|
| No global pause switch | Owner cannot atomically halt all activity in a single transaction | Add `Pausable` to `VRFGameBase` and `GameTreasury`; guard all `nonReentrant` functions with `whenNotPaused` |
| No timelock on critical parameters | `houseEdgeBps`, `vrfTimeoutSeconds`, `revealDelayBlocks` can be changed instantly | Deploy behind a **timelock controller** (e.g., OpenZeppelin `TimelockController`) with a **24-hour delay** on parameter updates |
| Single-owner model | A single compromised key can drain fees or disable games | Transition to **multi-sig governance** (e.g., Gnosis Safe with 3-of-5 signers) as the `owner` |

### 4.4 Timelock / Multi-sig Recommendation

For production, the intended governance stack is:

```
[Multi-sig Wallet (3-of-5)]
        │
        ▼
[TimelockController (24h delay)]
        │
        ▼
[GameTreasury.owner = TimelockController]
[VRFGameBase.owner = TimelockController]
```

This ensures that **no single signer** can unilaterally alter house edge, pause games, or withdraw fees without a **publicly observable 24-hour delay** and multi-party consent.

---

*End of Security Analysis — Verifiable Random Game v1.0*