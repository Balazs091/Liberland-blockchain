# Lending Module Research — Staked LLM as Working Collateral

Research date: 2026-07-03. Sources were fetched and adversarially verified (3-vote refutation panel per claim; 22 of 25 top claims confirmed, 3 refuted and excluded). This document analyzes the existing Milestone 8 implementation against Sky protocol's Staking Engine and comparable designs, and recommends the v2 direction for lending, revenue routing, and idle-stablecoin yield.

## 1. What already exists in this repository

The core idea — "staked LLM sits idle, let it collateralize stablecoin loans" — is already implemented as Milestone 8:

- `USDCLendingPoolApp`: pooled USDC supply side (anyone deposits, receives `llUSDC` shares, earns the utilization-driven supply rate), borrow side keyed by person ID against active stake above the retained floor.
- Collateral rule: exactly the requested model — only active stake above `MINIMUM_RETAINED_STAKE = 5,000 LLM` counts, so a citizen with 6,000 staked LLM has 1,000 LLM of usable collateral. The floor equals `MINIMUM_CITIZEN_STAKE`, so borrowing can never cost citizenship.
- `StakeLienRegistry` + `StakeRegistry.requiredActiveStakeFloorOf`: borrowing locks the full surplus stake as a lien; liened stake cannot be unstaked, so loans cannot bypass the ~10%/yr unstake limit.
- Parameters: 25% max LTV, 35% liquidation threshold, 10% liquidation bonus, 15% reserve factor, kinked rates (2% base, +8% to the 80% kink, +100% to full utilization).
- Liquidation transfers seized collateral as *active staked LLM* into the liquidator's person ID — no path mints liquid LLM.
- Borrowers keep full voting power on liened stake; staked LLM earns nothing natively today.

So the question is not "build it" but "is the design right, and what is missing." Three real gaps were found:

1. **Revenue was stranded (fixed 2026-07-03).** `claimProtocolReserves` sweeps the platform's 15% interest cut as USDC into the `TreasuryVault`, but the vault was native-ETH-only with no ERC20 disbursement path. The ERC20 treasury rewrite (see §6) fixes this: the vault, budget envelopes, payout queue, and spending policy are now ERC20-native, so lending revenue is spendable through the normal referendum→budget→payout pipeline.
2. **Staked LLM still earns nothing.** Collateral utility alone is weak motivation; Sky's answer (revenue-funded staking rewards) is directly adaptable (§4).
3. **No yield on idle government stablecoins.** No savings-vault module exists (§5).

## 2. How Sky's Staking Engine actually works (verified)

Sky's LockStake Engine is the single production precedent for what Liberland wants: staked governance tokens that simultaneously back a stablecoin loan, keep their political function, and earn.

- **One deposit, three uses.** A SKY deposit in a per-user vault ("urn") can at once: collateralize a USDS loan, be staked into one reward farm (100% of rewards continue during an active loan), and delegate the full deposit's voting power. Borrowing forfeits nothing. [developers.sky.money/protocol/rewards/staking-engine, github.com/sky-ecosystem/lockstake — verified 3-0]
- **Non-transferability.** Urns cannot be transferred between addresses — validating Liberland's person-keyed positions. But the V1 exit fee on withdrawing collateral (5% burned) was **removed by governance ~5 months after launch due to user friction**, and staked SKY has no lockup at all. There is no production precedent for politically rate-limited (~10%/yr) unstaking or for liquidation into a liquidator's staked balance — those remain novel Liberland mechanisms. [verified 3-0, incl. on-chain `fee()=0` check]
- **Leverage.** Sky lends at a 125% liquidation ratio (~80% max borrow); the documented fee-coupled variant required ≥133%. That is 2–3× Liberland's leverage — justified by SKY's deep, freely tradeable market and auction liquidations. Key formula worth keeping: if any fee/haircut is burned from collateral at liquidation, the liquidation threshold must be derated by 1/(1−fee) or auctions go insolvent. [verified 3-0]
- **Revenue routing (since Nov 2025).** Protocol profits (stability fees + Sky Agent income) programmatically buy back SKY on the open market; bought-back SKY is distributed to Staking Engine participants as manually-claimed rewards that are explicitly *not* part of the collateral and survive liquidation. [verified 3-0]
- **Sky Savings Rate / sUSDS.** A governance-set (not utilization-derived) rate, ~3.6–3.75% APY at access, paid from the protocol surplus buffer, tokenized as the non-rebasing ERC-4626 vault sUSDS. Warning attached: an administered rate can outrun revenue — Sky posted a ~$5M quarterly loss in Q1 2025 when savings interest exceeded profits. [verified 3-0]

## 3. Architecture verdict: keep the current shape

- The evidence supports the **isolated CDP-style collateral engine + pooled stablecoin supply side** that v1 already has. Nothing found argues for switching to a general money market.
- **Curve's LLAMMA soft liquidation is structurally excluded**: it requires an AMM that custodies collateral and sells it to arbitrageurs mid-loan on external markets. Both legs break for non-transferable, rate-limited staked LLM. Threshold liquidation into the liquidator's staked balance — v1's approach — is the viable mechanism. [verified 3-0]
- **Keep v1's conservative parameters, but make them replaceable.** Sky's 80% max borrow is not the benchmark for LLM; the Nov 2022 Aave/CRV incident is: liquidating a 92M-CRV position left $1.78M bad debt, with the post-mortem arguing the *liquidation logic itself* (incentives, close factors) caused a toxic spiral — the treasury repaid it. Gauntlet's doctrine ("no fixed parameter setting stays safe; recalibrate on a schedule") applies. **Shipped 2026-07-03:** the four risk parameters are no longer compiled into the pool — they now live in a replaceable `LendingRiskParameterPolicy` module resolved live from the kernel, so a module-governance referendum can retune LTV/threshold/bonus/reserve without redeploying the pool (see §6). The policy enforces hard bounds so no repoint can set nonsensical values. [verified 3-0]
- **Supply side and citizenship**: the pool currently accepts deposits from anyone. If "stablecoin provided by citizens" is a hard requirement, gate `deposit` on an active wallet link — but consider leaving supply open: more liquidity lowers borrow rates, and lien/borrow rules already restrict the politically sensitive side to citizens. Recommendation: leave supply open, gate nothing.

## 4. Making the platform money work: revenue routing (the "reinvest into LLM" idea)

Sky's post-Nov-2025 template maps almost 1:1 onto the goal "platform earns, and earnings strengthen LLM":

1. **Earn**: the 15% reserve factor keeps accruing to `totalReserves`; `claimProtocolReserves` sweeps it to the (now ERC20-capable) `TreasuryVault`.
2. **Split by governed budget**: from the treasury, referendum-approved budget envelopes route the stablecoin revenue to (a) operations, (b) a savings-rate budget (§5), and (c) an **LLM buyback envelope**.
3. **Buy back and reward stakers**: a bounded buyback module purchases LLM with treasury stablecoins and distributes it to stakers — Sky's exact "profits → buy back token → distribute to stakers" loop. Two design constraints learned from Sky: rewards must be **claimed, not auto-staked into collateral** (keeps reward accounting out of lien/liquidation math), and rewards should survive liquidation. This simultaneously answers "staked LLM earns nothing" and "strengthen LLM price" — buy pressure plus staking yield.

A cheaper interim step (no DEX dependency): distribute part of the reserves *in stablecoin* pro-rata to active stakers, and only move to buybacks when LLM has a liquid on-chain market. The buyback leg needs a real oracle and market first (§7).

## 5. Idle-stablecoin yield for government wallets (ministries, congress)

The verified reference design is the **non-rebasing ERC-4626 savings vault** (sUSDS/sDAI pattern): deposit the stablecoin, hold shares whose redemption value rises; no rebasing, standard interfaces, drop-in for contract-held balances. The segment grew past $19B by Sept 2025, so the product shape is proven. [verified 3-0]

Recommended Liberland design — a `TreasurySavingsVault` module:

- ERC-4626 vault holding USDC (later USDS), rate **administered by governance** (a replaceable savings-rate policy), funded from the lending pool's reserve revenue via a budget envelope — i.e., the platform's own earnings pay the government's savings rate. Cap the payable rate at what reserves actually fund (Sky's Q1 2025 loss shows administered rates can outrun revenue); a simple rule is "rate ≤ trailing reserve inflow".
- Government balances: with the ERC20 treasury rewrite, the `TreasuryVault` itself can hold vault shares — the treasury deposits idle USDC into the savings vault and disburses by withdrawing. Since ministries are currently minister EOAs (no ministry treasury contracts yet), the practical v2 ordering is: first give ministries contract-held accounts (already an open Milestone 9 question), then plug those accounts into the savings vault.
- If USDS is bridged to the chain, holding sUSDS directly is an alternative — but it imports Sky governance/upgrade risk (sUSDS is DAO-upgradeable; the "fees can never be enabled" claim was refuted 0-3), so a native vault funded by native revenue is the cleaner sovereign design.
- **Regulatory note** (BIS FSI Brief 27, GENIUS Act §4(a)(11), verified 3-0): every major regime bans *issuer-paid* yield on payment stablecoins; intermediary-layer yield is treated more leniently (US: not explicitly prohibited as of mid-2026; EU/HK: prohibited). Liberland is not directly subject to these, but cross-border users and counterparties are. Design implication: never build yield into a stablecoin itself; keep it in a separate opt-in vault wrapper — which is exactly the recommended design.

## 6. Shipped 2026-07-03

### Governable lending risk parameters

`LendingRiskParameterPolicy` (`policy.lending-risk-parameter`) holds max LTV, liquidation threshold, liquidation bonus, reserve factor, and a per-person borrow cap, with invariant-checked bounds (max-LTV < threshold ≤ 90%, bonus ≤ 20%, reserve ≤ 50%; per-person cap 0 = unlimited). `USDCLendingPoolApp` resolves it live from the kernel on every borrow, health-factor, liquidation, and accrual read — so a module-governance referendum retunes parameters on a live pool without redeploying it (a repoint takes effect on the next interaction, gated by the timelock review window). This closes open question #4, and makes the liquidation bonus votable (owner decision, 2026-07). The per-person cap closes the concentration half of open question #3.

### Swappable price oracle (launch → Uniswap V4 TWAP)

The pool no longer fixes its price oracle at construction — it resolves `LLM_USDC_PRICE_ORACLE_POLICY` live from the kernel. At launch there is no liquid LLM/USDC pair, so the oracle is a manual `FixedLlmUsdcPriceOraclePolicy` whose price is changed by a module-governance repoint (referendum is the deliberate, review-gated update path — no trusted price key). When the Uniswap V4 LLM/USDC pair has enough liquidity, governance repoints the module to a V4 TWAP oracle without redeploying the pool. This implements the launch phase of open question #1.

### ERC20-money treasury

The lending/revenue design above also requires the treasury stack to handle ERC20s. This was implemented and tested (full suite green — 204 tests):

- `TreasuryVault`: ERC20-only custody and disbursement (`receiveTokenDeposit`, `treasuryBalanceOf`, ERC20 `executeDisbursement`); no payable path remains.
- `BudgetEnvelopeRegistry`, `ActionTimelock`, `ReferendumApp`/`ReferendumRegistry`: budget envelopes and disbursements are ERC20-denominated; native assets rejected.
- `TreasurySpendingPolicy`: explicit per-asset allowlist (LLM, USDC, later USDS) with per-asset clerk limits; asset is bound into the payout policy reference.
- Referendum proposal fees are collected in LLM via `safeTransferFrom` into the treasury.
- Deploy scripts: production takes `LLM_TOKEN` + `TREASURY_ASSET_*` env config; the demo deploys mock LLM + USDC and seeds a USDC budget.

## 7. Open questions for v2 (ranked)

1. **Oracle.** *Launch phase shipped 2026-07-03:* the oracle is now kernel-resolved, so the manual launch oracle can be repriced or swapped for a Uniswap V4 TWAP oracle by referendum without redeploying the pool (§6). Remaining work is the **V4 TWAP oracle contract itself** — to be built when the pair exists, with a long TWAP window, a spot-vs-TWAP deviation circuit-breaker that pauses *borrows* (never liquidations), staleness bounds, and a manipulation-cost analysis before any LTV increase above 25%. Concrete TWAP-window/staleness numbers did not survive verification and need their own design pass against real pool liquidity.
2. **Liquidation economics for illiquid seized collateral.** The 10% bonus pays liquidators in an asset they cannot exit for ~10%/yr. Either accept that only long-term LLM accumulators will liquidate (arguably aligned with citizenship), raise the bonus, or move to a Dutch-auction discount. Decide the bad-debt backstop explicitly: treasury absorption (Aave's choice in Jan 2023) vs. socializing across suppliers; v1 currently has no mechanism.
3. **Borrow caps vs. market depth.** Aave/CRV lesson: cap total borrows against thin collateral relative to what liquidators can actually absorb. v1's global `borrowCap` exists — set it deliberately, not generously. *Per-person cap shipped 2026-07-03* as a governed risk parameter (0 = unlimited), so no single borrower can concentrate past what liquidators absorb, independent of stake size.
4. **Parameter governance. (Shipped 2026-07-03.)** LTV/threshold/bonus/reserve-factor now live in the replaceable `LendingRiskParameterPolicy` module, resolved live from the kernel and repointable by module-governance referendum. Remaining work is process, not code: set a scheduled recalibration cadence. Caveat: because the pool reads params live, a repoint that lowers the liquidation threshold can make existing positions liquidatable on the next interaction — the timelock review window is the warning buffer.
5. **Partial lien release** on partial repayment (v1 releases only at full repayment) — UX improvement, safe to defer.
6. **Aave GHO stkAAVE discount mechanics** were refuted in verification (0-3) — if a "staked LLM lowers your borrow rate" feature is attractive, research it separately before citing it.

## 8. Refuted/negative results worth remembering

- "sUSDS can never enable fees" — false (0-3); it is upgradeable by Sky governance.
- Sky's exit-fee restriction was abandoned for friction — locked-collateral UX has real costs.
- No production system anywhere lends against *politically rate-limited* collateral; Liberland's lien-over-unstake-limit design is novel and must carry its own analysis rather than leaning on precedent.
