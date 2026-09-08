# Lending and Treasury

System money is ERC20: LLM for governance/merit and stablecoins for spending and lending. Native ETH is gas-only; protocol contracts do not accept `msg.value`.

LLM uses 18 decimals and is hard-capped at `70_000_000e18`. Production requires the external token to expose that
exact `cap()`. The Treasury is a holder and spender, never an issuer: it has no minting or arbitrary token-call path.

## Treasury vault and spending

- `TreasuryVault` holds and disburses ERC20 assets only.
- Budget envelopes and disbursement payloads bind a nonzero asset address.
- `TreasurySpendingPolicy` is an explicit per-asset allowlist with per-asset clerk limits.
- Referendum proposal fees are pulled in the policy's fee asset into the treasury.
- Treasury disbursements execute only through the typed router/timelock path.
- The current vault independently requires the payload request ID, budget ID, amount, and asset to match an active
  stable-registry budget commitment. It marks `BudgetEnvelopeRegistry.isRequestExecuted(requestId)` before the
  transfer; token failure rolls back both this permanent marker and the vault-local execution receipt.
- Outbound transfers require the recipient's balance to increase by the exact requested amount; fee-on-transfer and
  otherwise non-exact assets revert instead of silently underpaying the recipient.
- `ContributionReward` payouts are LLM-only, Finance-admin-proposed, independently officer-approved, evidence-backed, and use the sensitive queue delay.
- An office cancellation of a routed payout first cancels its queued timelock action; only then may `PayoutQueue`
  mark it canceled and release the budget commitment.
- Anyone may call `syncPayoutState` to reconcile an executed, Senate-canceled, or expired timelock action. For
  execution, it checks `isDisbursementExecuted(requestId)` on the vault address pinned into that action rather than
  a replacement live vault pointer.

### Execution receipts and deferred reconciliation

Execution and queue accounting are separate observable stages:

| Stage | Stable execution marker | Budget accounting / queue |
| --- | --- | --- |
| Routed, not executed | False | Amount committed; request Queued |
| Executed, not synchronized | True | Amount remains committed; request may still read Queued |
| Executed and synchronized | True permanently | Amount becomes spent; request Executed |
| Canceled/expired and synchronized without payment | False | Commitment released; request canceled/vetoed/expired |

`BudgetEnvelopeRegistry.isRequestExecuted(requestId)` prevents a paid ID from being reserved or paid again through
replacement queues and vaults that retain this ledger. It is request-ID replay protection, not proof that two
different IDs do not refer to the same real invoice. Canceled unexecuted IDs are not permanently consumed at the
ledger level, but each queue's own uniqueness rules still apply. Frontends must not call `markExecution` directly;
only the current vault records it as part of the atomic payment.

Call `syncPayoutState(requestId)` on the queue that actually owns the request. That queue checks the action's pinned
vault-local receipt before moving committed budget to spent. Replacement vaults may correctly return false for an
old payment while the stable ledger returns true. Commitments retain their original accounting writer for bounded
settlement after writer rotation; only the current accounting authority can make new reservations. Both the current
and original writer must obey the stable execution receipt: `releaseBudget` rejects a paid commitment, while
`recordDisbursement` requires payment. Paid committed capacity can become spent, never released for reuse.

Before queue/executor/vault replacement, inventory proposed and routed requests. `OfficeExecutor` immutably pins
its queue, so moving only the kernel `PAYOUT_QUEUE` ID does not redirect it. Prefer completing/canceling requests
before transition. Unexecuted actions pinned to a replaced vault cannot silently execute on its successor; cancel
through an available authorized route or wait for expiry, then synchronize the original queue. Pending proposals
and officer approvals are not copied into a new queue. A budget-registry migration must separately preserve consumed
request IDs as well as envelopes and commitments.

### Contribution rewards

Official rewards for verified donations of time or money use the ordinary treasury safeguards rather than a new
issuance path. A referendum first approves an LLM-denominated `ContributionReward` budget. The Finance Office admin
then submits a recipient, amount, evidence hash, and evidence URI. A distinct current Finance officer must approve
before a policy-permitted officer routes it; both appointment IDs and the proposer's policy are revalidated. After the sensitive queue and treasury timelock,
the vault transfers existing LLM. Senate controls apply like any other treasury disbursement.

The responsible operational office determines contribution validity off-chain and is expected to be identified in
the evidence document. V1 does not encode contribution valuation or automatically exchange a stablecoin donation for
LLM. Finance clerks cannot propose this class but may supply the independent approval or route an approved admin proposal. The source is always the pre-funded Treasury Vault LLM balance.

## Political stake custody

`LLMStakingVault` holds the LLM backing every redeemable active-stake unit in `StakeRegistry`.

- deposits check the exact token balance delta
- a person ID must already exist before stake can be credited
- genesis credits can consume only already funded backing surplus
- unstaking reduces aggregate active stake before transferring the exact LLM amount to the active wallet
- unstaking, liquidation, and slashing cannot move active stake below the required protected/lien floor
- `StakeRegistry.totalActiveStake()` is the aggregate accounting side of the backing invariant
- liquidation transfers active stake between person IDs and never releases liquid LLM

The ordinary-operation backing invariant is:

`LLM.balanceOf(stakingVault) >= StakeRegistry.totalActiveStake()`

During a reviewed pointer/handoff transition, backing may temporarily remain in the retired vault. Complete and
verify handoff before treating the successor as operational; a pointer vote alone does not establish its backing.

## Stake-backed lending pool

`USDCLendingPoolApp` lets anyone supply stablecoins and lets currently eligible citizens borrow against active LLM stake above their required retained floor. Stake liens raise that floor, so borrowed-against stake cannot be unstaked or slashed. Anyone may call `repayFor(personId, amount)`, allowing debt repayment after the borrower's wallet is revoked or migrated.

Debt accounting uses per-person scaled debt under one global RAY (`1e27`) borrow index. Interest compounds
deterministically through that index instead of being accrued independently per borrower. `currentDebtOf(personId)`
previews index growth through the current timestamp; `totalBorrows()` and `borrowIndex()` intentionally return stored
checkpoint values until `accrueInterest()` or another state-changing pool operation updates them.

`maxBorrowable` previews aggregate debt, borrower limits and reserve-adjusted cash at one current borrow index.
It conservatively inverts scaled-debt rounding and returns zero for ineligible people. Positive quotes are
executable against unchanged state, not guaranteed against intervening transactions or elapsed time. Simulate
`borrow` before submission.
Ordinary partial repayment does not proportionally release the lien; full repayment clears it. Liquidation
recalculates it against remaining debt and collateral.

The pool resolves these modules live from the kernel:

- `LendingRiskParameterPolicy`: max LTV, liquidation threshold, liquidation bonus, reserve factor, and per-person borrow cap
- `KinkedInterestRatePolicy`: utilization-based borrow and supply rates
- `LLM_USDC_PRICE_ORACLE_POLICY`: the collateral price source

The pool checkpoints the borrow rate and reserve factor governing each elapsed interval. A direct USDC donation,
utilization change, or governed policy replacement affects a new checkpoint; it does not retroactively apply the
new configuration to time already elapsed. The constructor therefore takes six arguments and does not pin an
interest-policy address.

Both launch manifests use 30% LTV, a 40% liquidation threshold, a 15% liquidation bonus, a 15% reserve factor, a
1,000,000 USDC total borrow cap, and a fixed 1 LLM = 2 USDC oracle. Production additionally caps debt at 100,000
USDC per person; the demo leaves that cap unlimited to simplify testing. The fixed value cannot be manipulated
through a market feed, but it can become economically wrong as market conditions change. This is an explicitly
accepted launch risk. Governance can replace the oracle policy after review without redeploying the pool.

`LendingRiskParameterPolicy` rejects a configuration where
`liquidationThreshold * (1 + liquidationBonus) > 100%`. This ensures a liquidation performed exactly at the
threshold cannot require more collateral, including bonus, than the position's full quoted collateral value.

When a person's first lien is created, `StakeLienRegistry` snapshots the current citizenship retained-stake floor.
That value and the pool's loan ownership remain until explicit loan closure after full repayment or bad-debt
absorption. Liquidation can exhaust the lien while debt remains; a zero lien alone does not clear ownership or the floor. A later citizenship-policy increase therefore
does not retroactively make the old position impossible to liquidate. The ordinary protected stake floor still
applies if it is higher, and protected-floor updates cannot raise the effective required floor above active stake.

Liquidation moves seized collateral to the liquidator as active stake. `absorbBadDebt(personId)` first computes the
smallest asset repayment that actually reduces the borrower's scaled debt at the current index, applies the
liquidation bonus and oracle conversion with the same conservative rounding as liquidation, and rejects the
write-off while the position's recoverable collateral can cover that seizure. The active pool uses the existing
all-active-surplus model; a retired pool caps recoverable collateral at its remaining recorded lien. The protected/retained floor is not available
to a liquidator and is therefore not treated as recoverable collateral. Once that recoverable collateral cannot fund that minimum
effective liquidation, absorption clears the residual scaled debt: protocol reserves absorb loss first, and any
remaining deficit lowers LP share value; an independently approved treasury backstop could recapitalize it but is
not guaranteed or automatic.

Protocol reserves accrue from borrow interest and remain locked in the pool as first-loss capital. There is no reserve-withdrawal entrypoint. A future withdrawal would require a new bounded governance action and separate review.

## Retirement and custody transitions

`StakeLienRegistry.loanBookOf(personId)` identifies the sole pool for an open loan. Only the pool jointly selected
by the current pool, lien-authority and liquidation-authority IDs may add borrowing, and its immutable
identity/stake/lien registries must match the canonical ledger IDs. Retired pools cannot originate
or top up loans; `maxBorrowable` returns zero for retirement or an open loan owned by another pool. A successor must
wait for the old book to close. Debt and LP shares remain in their original pool rather than migrating.

Retired owners can repay, liquidate or absorb their own old positions through typed lien-registry settlement.
A retired origin's settlement requires `seizedStake + remainingLien <= priorLien` and checks retained/protected
floors before the atomic collateral transfer. Its health/liquidation/bad-debt calculations use at most the lesser of
current surplus and recorded lien, so newly added unpledged stake cannot revive or enlarge old liquidation rights.
The active pool's prior all-active-surplus collateral economics are unchanged.
Pools have no general direct stake-transfer permission. Old deposits/withdrawals remain callable, subject to
liquidity, token and policy constraints. Do not market a retired pool as the current source of new loans.

After approved same-ledger LLM vault replacement, anyone may call the retired vault's `handoffBacking()` to send its
complete balance to the exact current governed successor, with matching kernel, token and identity/stake ledgers,
exact receipt and aggregate-backing checks. Treasury `handoffAsset(asset)` similarly has one exact same-kernel
successor and exact token receipt; its historical disbursement receipts remain in the old vault. Neither operation
imports facts, debt, LP shares or cases. Original budget accounting writers can reconcile only their own existing
commitments after replacement, not reserve new budget capacity.

See [Upgrade and Liveness](Upgrade-And-Liveness.md) for dependency closure, temporary transition availability,
individually executable batch members and the retained governance recovery limits.

## Ministry treasury

`MinistryTreasury` is a shared ERC20 treasury keyed by office ID.

- Funding is gated to `MINISTRY_TREASURY_FUNDING_AUTHORITY` (both manifests wire `DecisionApp`).
  `fund(officeId, asset, from, amount)` pulls tokens only after the source has authorized the exact Congress decision
  and approved the treasury.
- The office admin may spend the office's balance.
- Clerks are limited by a minister-configured per-asset UTC-day allowance; zero blocks clerk spending.
- Clerk spend accounting uses full-width values and resets by UTC day bucket.
- The minister may supply stablecoin balances to the lending pool and withdraw them.
- Idle balances are isolated by office ID. Pool shares are isolated by both office ID and lending-pool address.
- `poolSharesOf(officeId)` and the ordinary supply/withdraw functions use the current kernel-governed pool.
- After a pool replacement, `poolSharesAt(officeId, oldPool)` and
  `withdrawFromPoolAt(officeId, oldPool, amount)` let the office recover its own remaining old-pool shares without
  mixing them with another office or the replacement pool.

Pool withdrawals remain limited by available pool liquidity. An office that needs guaranteed short-term liquidity must retain an operating-cash buffer outside the pool.

## Deployment

Both `scripts/Deploy.s.sol` and `scripts/DeployDemo.s.sol` deploy the lending pool, launch oracle, risk/interest
policies, stake-lien registry, `MinistryTreasury`, and `DecisionApp`. Production requires an explicit deployed
six-decimal `USDC_TOKEN`; Sepolia deploys `MockUSDC`.

## Deferred production work

- later replace the fixed oracle with a reviewed market oracle, including TWAP window, staleness, spot-vs-TWAP deviation handling, and manipulation-cost analysis
- consider auction liquidation only if fixed-bonus liquidation proves insufficient
- perform independent economic and invariant review, plus a final mainnet-fork deployment rehearsal, before launch
