# Liberland EVM Architecture

Liberland EVM is a modular governance operating system for constitution-aligned execution on the EVM.

The architecture is intentionally split into four layers:

- `contracts/core` for the privileged action lifecycle and canonical module pointers
- `contracts/registries` for stable fact storage
- `contracts/policies` for replaceable rule evaluation over registry facts
- `contracts/apps` for user-facing workflows that consume policies and registries

## Current scope

The repository implements the milestone stack through bounded decision execution:

- core module registry, governance router, and explicit action timelock
- identity, citizenship, stake, unstaking, and voting-power rules
- referendum creation, voting, finalization, and delayed Tier 1/Tier 2 enactment
- Congress election cycles, deterministic recurring cadence, incumbent auto-candidacy, standing signed weighted ballots, finalization, and runner-up replacement
- Senate queued-action cancellation, active-referendum veto, sub-legal measure repeal, President proxy voting for non-voting senators, and public veto flows
- treasury vault, referendum-approved budget envelopes, office roles, and payout queue routing
- land registry records for parcels, titles, disputes, and encumbrances, mediated by the Land Registry Office
- company registry records for incorporation submissions, approvals, directors, filings, share classes, and internal share balances, mediated by the Company Registry Office
- stablecoin liquidity, stake-backed borrowing, stake liens, utilization-based interest, treasury reserves, and liquidation into active staked LLM; risk parameters (LTV, liquidation threshold, votable liquidation bonus, reserve factor, per-person cap) and the price oracle are governed replaceable modules, and unrecoverable positions are cleared through a treasury-absorption bad-debt backstop (see `docs/Lending-And-Treasury.md`)
- office-keyed `MinistryTreasury` holding ERC20 funds per ministry/office, funded by Congress decision, spent by the minister (office admin) with clerks bound to a minister-set daily limit, and able to earn by supplying idle stablecoins to the lending pool in-house
- Congress and ministry decisions for wallet-approved ERC20 movement, office clerk decisions, LLM transfer-and-stake decisions, and Congress-approved creation of new government offices and ministries

The Sepolia demo script adds seeded read-state and live onboarding helpers without keeping bootstrap authority active after deployment.

The production deployment script registers a sealable `InitialSetupAuthority` before bootstrap is disabled. It is limited to deterministic genesis setup for citizens, stake additions, Senate seats, Congress terms, and offices. The script also sets the genesis President registry fact during bootstrap, then runs readiness checks and seals the setup authority before bootstrap is disabled, so no setup owner path remains after deployment.

The audit scope covers the repository's full contract set under `contracts/`, including the Milestone 8 lending modules and the Milestone 9 `DecisionApp`. Deployment scope is separate and script-dependent: the production `scripts/Deploy.s.sol` deploys the core governance set (neither lending nor `DecisionApp`), while the demo `scripts/DeployDemo.s.sol` also deploys `DecisionApp`.

## Post-audit remediation (2026-07)

The constitution-fidelity + security audit (`docs/Constitution-Code-Audit-2026-07-01.md`) and the owner's decisions were implemented across the stack; see `docs/Remediation-Log-2026-07-01.md` for the finding-by-finding record. Notable additions and model changes:

- Governance weight is intentionally stake-proportional (no equal base vote, no merit cap, no headcount quorum) — a documented design decision, not a defect. The one guarantee: a citizen drawing down stake is in "welfare" and does not vote.
- Unstaking is a discrete 30-day model: each `unstake()` immediately releases one 30-day portion of the current (shrinking) stake and enters a 30-day welfare period. The annual rate is tuned to 10.64%/yr so that twelve compounding monthly unstakes release ~10.00% of the original stake over 360 days; the rate cap is enforced on-chain so borrowing LLM only to vote is infeasible.
- One active wallet per person is enforced in the identity registry; a standing `IdentityApp` (registered as the identity-registry authority) provides office-gated onboarding, citizen self-renunciation, and a timelocked, office-approved wallet migration that carries person-keyed stake to a new wallet.
- The Head-of-State and Executive branches are modeled: `HeadOfStateApp` + `PresidentRegistry` (Senate-elected President, 5-year term, two Vice Presidents, resignation succession) and `CabinetApp` + `ExecutiveRegistry` (Congress-appointed Prime Minister with removal requiring at least the appointment tally, and PM-appointed Finance/Foreign-Affairs/Interior/Justice Ministers dismissible only by Congress).
- Senate negative powers hardened: a President-proxy participation floor (`proxy <= direct`) on all four negative-power paths, a temporary auto-lapsing disbursement suspension alongside the hard cancel, and a guaranteed minimum Senate review window even on emergency enactment.
- Module-governance referenda that repoint rule-defining or value-custody modules (`authority.*`, `policy.*`, `registry.*`, and the treasury vault) now require the constitutional-amendment double-threshold; core router/timelock remain fully un-repointable.

Still future work (acknowledged, not regressions): the Judiciary (Art III), Agents (Art V §5), a production staking-vault/redemption model, and linking political ministers to operational office admins.

## Milestone order

1. Core privileged action lifecycle
2. Identity, stake, and citizenship foundations
3. Legislation and referenda
4. Congress elections
5. Senate and public veto
6. Treasury and office systems
7. Land and company registries
8. LLM stake-backed USDC lending
9. Congress and ministry decisions

## Design constraints

- system money is ERC20: LLM (governance/merit) and stablecoins (USDC, later USDS). Native ETH is gas-only — the treasury vault holds and disburses only ERC20 assets, budget envelopes and payouts are ERC20-denominated, referendum proposal fees are collected in LLM via `safeTransferFrom`, and no contract in the stack accepts `msg.value`
- treasury spending assets are an explicit per-asset allowlist in the replaceable `TreasurySpendingPolicy`, with clerk limits configured per asset in that asset's smallest units; changing the asset set or limits means deploying a new policy and repointing the module through governance
- sensitive actions must use deterministic action identifiers
- queued actions pin the target module address at queue time and revert if that module pointer changes before execution
- queued actions must not execute twice
- no unrestricted arbitrary execution path may exist
- registries remain the source of truth for facts
- policies remain replaceable without collapsing registry integrity
- election cadence changes are bounded policy module updates, not arbitrary referendum execution
- ordinary referendum voting uses a 7 day minimum, with citizen-origin proposals using the standard 7 day adoption delay
- Congress-origin emergency referenda may use the 3 day voting minimum with immediate enactment, but constitutional amendments cannot use the emergency path
- constitutional-amendment referenda snapshot electorate headcount and voting power at creation time, avoiding finalization-time loops over mutable identity state
- budget approvals are treated as laws and enter the treasury system through successful budget-approval referenda
- legal measure tiers are represented as Tier 1 constitutional/international-treaty, Tier 2 law, Tier 3/4 sub-legal placeholders, and Tier 5 decisions
- Senate negative-power votes are finalized after the applicable review deadline; seats vote support-only — a seat either supports the proposal or abstains, as the explicit against seat vote was removed (a modest simplification that shifts a little weight toward the President proxy). A supporting seat is always counted directly rather than by proxy, and the President proxy may cover only silent occupied seats and only up to the participation floor (`proxy <= direct support`), so a missing or non-supporting President proxy never adds Senate support
- Senate may open a repeal vote at any time for enacted tiers below law; this is implemented as a 7 day Senate vote before finalization, with retryable failed attempts whose old votes do not carry forward
- land and company registries are fact registries; office apps authorize bounded registry mutations instead of exposing arbitrary execution
- lending liens are registry facts and are enforced in the stake registry's required active-stake floor, so borrowing cannot be used to bypass unstaking cooldowns
- lending liquidations transfer seized collateral as active staked LLM to the liquidator's person ID; no liquidation path releases liquid LLM directly. Once liquidators have seized all surplus above the citizenship floor, the residual is unrecoverable and is cleared by a permissionless `absorbBadDebt` write-off — protocol reserves absorb it first, and any remainder is restored by a governed treasury disbursement to the pool
- the lending pool resolves its risk-parameter policy and price oracle from the kernel, so a governance repoint can retune parameters or swap the launch manual oracle (1 LLM = 2 USDC) for a Uniswap V4 TWAP oracle without redeploying the pool and losing its deposit/debt/interest state
- the `MinistryTreasury` keys balances by office ID and resolves the controlling minister/clerks from the office registry, so it needs no per-ministry deployment and automatically covers offices created later; funding is gated to a Congress-decision funding-authority module, and one office can never spend or redeem another office's balance or pool shares
- decisions are bounded typed workflows, not arbitrary executors; token movement requires approval from the source wallet
- Congress decisions are bound to the Congress term that prepared them, so a later Congress cannot approve or execute stale decisions
- ministry decisions currently use the office admin wallet as the ministry signer/source wallet until a separate ministry treasury-account model is specified
- new government offices and ministries can be created after genesis by a Congress-majority `RegisterOffice` decision, because `DecisionApp` is a registered office-registry authority; the office set is therefore not frozen at bootstrap, and no reactivation of the retired office bootstrap authority is required. Office kinds remain enum-bounded, and the company/land/identity apps stay bound to their specific genesis office IDs, so a newly created office cannot hijack an existing registry or (absent a referendum-approved budget envelope) spend from the treasury

## Governed module evolution

Contracts evolve by deploying a new contract and updating the canonical module pointer in `ConstitutionKernel`
through a successful referendum and the action timelock. The system does not expose arbitrary calldata execution for
upgrades.

- Existing modules use `ModulePointerUpdate`.
- Brand-new module IDs use `ModuleRegistration`, allowing future modules such as a new registry or app to be added
  without reactivating bootstrap authority.
- Module registration and replacement share the module-governance delay and remain cancellable through the bounded
  Senate cancellation path.
- Governance origin authority is resolved through the current kernel module pointer for registered origins, so replacing an app module also replaces its routing authority.
- The generic module-governance referendum path currently blocks `core.governance-router` and `core.action-timelock`
  changes pending constitutional review of the threshold and migration rules for core upgrades.
- Stateful registry replacement still requires a separately reviewed migration plan; registries remain the source of
  truth for facts.
