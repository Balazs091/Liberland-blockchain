# Lending & Treasury (ERC20 money model)

This document describes the implemented money, lending, and ministry-treasury design. System money is ERC20 — **LLM** (governance/merit) and **stablecoins** (USDC, later USDS). Native ETH is gas-only and has no treasury role; no contract in this stack accepts `msg.value`.

## Treasury vault and spending

- `TreasuryVault` holds and disburses ERC20 assets only. Deposits come in through `receiveTokenDeposit` (or a plain transfer); disbursement is timelock-executed against a specific asset and recipient.
- Budget envelopes (`BudgetEnvelopeRegistry`) and disbursement payloads are ERC20-denominated; the zero-address asset is rejected at the registry, timelock, and referendum layers.
- `TreasurySpendingPolicy` carries an explicit per-asset allowlist (e.g. LLM, USDC) with per-asset clerk limits; the asset is bound into the payout policy reference. Changing the asset set or limits is a governed policy replacement.
- Referendum proposal fees are collected in the policy's fee asset (LLM) via `safeTransferFrom` into the treasury.

## Stake-backed lending pool (`USDCLendingPoolApp`)

Citizens borrow stablecoins against **active LLM stake above the 5,000-LLM citizenship floor** (a citizen with 6,000 staked LLM has 1,000 of usable collateral). Anyone may supply stablecoins and earn the utilization-driven supply rate. Liens raise the borrower's required active-stake floor, so borrowed-against stake cannot be unstaked — borrowing cannot bypass the ~10%/yr unstake limit. Liquidation transfers seized collateral to the liquidator as *active staked LLM* (never liquid); the seized stake then exits only through the normal rate-limited unstake path.

Two properties make the risk model governable and safe for a thin, transfer-restricted collateral:

- **Governed risk parameters** — `LendingRiskParameterPolicy` (`policy.lending-risk-parameter`) holds max LTV, liquidation threshold, **liquidation bonus** (votable), reserve factor, and a **per-person borrow cap** (0 = unlimited), with invariant-checked bounds (max-LTV < threshold ≤ 90%, bonus ≤ 20%, reserve ≤ 50%). The pool reads it live from the kernel, so a module-governance referendum retunes parameters on a live pool without redeploying it. Launch values: 25% LTV, 35% threshold, 10% bonus, 15% reserve.
- **Swappable oracle** — the pool resolves `LLM_USDC_PRICE_ORACLE_POLICY` live from the kernel. At launch (no liquid pair) it is a manual `FixedLlmUsdcPriceOraclePolicy` at **1 LLM = 2 USDC** (`assetUnitsPerLlm = 2_000_000`), repriced by referendum repoint (no trusted price key). When the Uniswap V4 LLM/USDC pair has liquidity, governance repoints to a V4 TWAP oracle without redeploying the pool.

**Bad-debt backstop** — once liquidators have seized all surplus and only the untouchable citizenship floor remains, a position's residual debt is unrecoverable. `absorbBadDebt(personId)` writes it off: protocol reserves absorb it first (first-loss capital), and any remainder lowers LP share value until governance restores it with a referendum-approved treasury disbursement to the pool (treasury absorption, not silent supplier socialization). The `PositionNotBadDebt` guard forces liquidators to seize seizable collateral first.

Revenue: 15% of borrow interest accrues as protocol reserves, claimable to the `TreasuryVault`. From there governance can route it (operations, an idle-yield allocation, or LLM buybacks distributed to stakers) — the intended loop for "the platform earns, and earnings strengthen LLM."

## Ministry treasury (`MinistryTreasury`)

A single shared contract holding ERC20 balances **per office ID**, so idle ministry/office stablecoins earn instead of sitting. Balances and the controlling roles are keyed by office ID and resolved live from the `OfficeRegistry`, so offices Congress creates later work with no change to this contract.

- **Funding — Congress-controlled.** `fund(officeId, asset, amount)` is gated to the `MINISTRY_TREASURY_FUNDING_AUTHORITY` module, which is `DecisionApp`. Congress funds a ministry through a `createCongressFundMinistryDecision` Congress decision: on majority approval it pulls the source wallet's tokens and credits the office's balance, keeping the regular money flow out of citizen-referendum friction.
- **Spending — minister + limited clerks.** The office admin (minister) spends any amount. Clerks are bound by a per-asset daily limit the minister sets (`setClerkDailyLimit`; default 0 = blocked), with a rolling daily-window reset.
- **In-house yield.** The minister can `supplyToPool` / `withdrawFromPool` against the lending pool, with per-office share accounting so one office can never redeem another office's shares.

Idle government stablecoins earn the pool's supply rate. The supply side is a free market: any address (citizen or not) may supply and withdraw, and there is no cap on the ministry share of the pool. The one inherent constraint is that funds earning the borrow spread are withdrawable only up to the pool's available liquidity — a large, fast withdrawal raises utilization and pushes the borrow rate up. That is left to the market: the kinked rate is self-correcting (a spike pulls in suppliers and pushes borrowers to repay), and a ministry that needs guaranteed short-term liquidity simply keeps an operating-cash buffer outside the pool by choice.

## Deployment

The demo script (`scripts/DeployDemo.s.sol`) deploys and wires the full stack end-to-end: the stake-lien registry, the launch oracle (1 LLM = 2 USDC), the kinked interest and risk-parameter policies, the lending pool (as its own stake-lien and liquidation authority), and the `MinistryTreasury` (with `DecisionApp` set as its funding authority). Congress can fund a ministry end-to-end via a `FundMinistry` decision. The production script (`scripts/Deploy.s.sol`) still deploys only the core governance set.

## Remaining work

- **Uniswap V4 TWAP oracle** — build when the pair has liquidity: long TWAP window, spot-vs-TWAP deviation circuit-breaker that pauses borrows (never liquidations), staleness bounds, and a manipulation-cost analysis before raising LTV above 25%.
- **Optional** — Dutch-auction liquidation if fixed-bonus liquidations stall; partial lien release (deliberately deferred — full-surplus lock keeps positions maximally over-collateralized, which suits illiquid collateral).

The lending supply side is intentionally an open free market: anyone may supply/withdraw, and there is no ministry-share cap — utilization and rates are market-driven, with the kinked rate as the self-correcting shock absorber.
