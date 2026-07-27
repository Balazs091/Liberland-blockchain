# External Audit Scope

This document defines the review surface for an external security, economic, deployment, and constitution-fidelity
audit. It does not assert mainnet approval. Solidity and deployed bytecode are authoritative when documentation
disagrees.

## In scope

- every Solidity source under `contracts/`, including mocks where they expose demo/test trust assumptions;
- both deployment scripts, `scripts/DeploymentScriptBase.sol`, and both network parameter manifests;
- bootstrap, authority retirement, module registration, and generated address-manifest correctness;
- external LLM/USDC assumptions, stake and treasury custody, lending economics, and contribution-reward funding;
- cross-module authorization, replacement/migration paths, denial-of-service bounds, and accounting invariants;
- all Foundry tests as evidence, not as a substitute for independent review; and
- the deliberate draft-constitution differences recorded in `docs/Constitution-Alignment.md`.

The production target is Ethereum mainnet (chain ID 1). Sepolia (chain ID 11155111) is an accelerated demonstration
environment with mock assets and demo-only onboarding powers.

## Build profile

- Solidity: pinned `0.8.36`
- EVM target: pinned `osaka`
- optimizer: enabled, 200 runs
- framework: Foundry
- static analysis: Slither, without source-level finding suppressions
- dependencies: `forge-std` and OpenZeppelin Contracts, pinned as Git submodules
- generated frontend ABIs: `frontend-export/abis/`

Auditors should record exact tool and submodule revisions, then independently run `forge fmt --check`,
`forge build --sizes`, `forge test -vvv`, coverage, static analysis, invariant/fuzz campaigns, and a production-state
fork rehearsal. Generated `out/`, `cache/`, `broadcast/`, and live `deployments/` files are not source of truth.

## Verification baseline

Revision-specific tool versions, test and coverage results, static-analysis output, runtime sizes, and deployment
integration evidence are recorded only in `docs/Internal-Audit-Report.md`. They are deliberately not duplicated
here because those values change during remediation. Auditors must verify that report against the exact commit and
rerun its commands independently before relying on any result.

Slither is intentionally unsuppressed. Expected review classifications include:

- `arbitrary-send-erc20`: allowance-based `DecisionApp`/`MinistryTreasury` flows; source authorization is bound to
  the exact decision, and operators must use exact allowances;
- `weak-prng`: timestamp modulo computes a deterministic UTC boundary; no outcome uses randomness;
- `calls-loop`: bounded seats/candidates or caller-supplied atomic action batches; each action is independently
  validated and failure reverts the transaction;
- strict equality: enum, nonce, UTC-day, zero-debt, and exact-accounting checks; and
- reentrancy reports around external modules: value-moving entrypoints use `nonReentrant`, checks/effects precede
  interactions, and accounting mismatch reverts atomically.

These are internal dispositions for orientation, not instructions for an auditor to accept them. Branch and failure
coverage should be expanded during remediation.

## Deployment matrix

| Component | Ethereum mainnet | Sepolia demo | Audit scope |
| --- | --- | --- | --- |
| Core governance, identity/stake, elections, referenda, Senate/public veto | Yes | Yes | In scope |
| Treasury vault, budgets, offices, land/company registries | Yes | Yes | In scope |
| `DecisionApp` | Yes | Yes | In scope |
| `MinistryTreasury` | Yes | Yes | In scope |
| Stake-backed USDC lending | Yes, external USDC | Yes, mock USDC | In scope |
| Demo citizen gateway and mock tokens | No | Yes | Demo/test trust surface |

## Congress deployment invariants

- production has seven occupied genesis seats and 90-day recurring cycles;
- the imported continuity cycle uses an explicit future 17:00 UTC end, preserves full nomination/voting minimums,
  and cannot exceed one ordinary cycle;
- Sepolia has two seats and 3-day recurring cycles;
- late finalization advances to the next 17:00 UTC boundary and cannot permanently drift; and
- production seals `InitialSetupAuthority` and disables kernel, router, and office bootstrap authorities.

## Pre-audit focus and disposition

1. **Stake custody, historical weight, and backing — hardened; retain in focus.** `LLMStakingVault` is the sole
   active-stake custody boundary. Exact token deltas, aggregate backing checks, protected/lending floors, and
   person stake checkpoints are enforced. The electorate checkpoints aggregate readiness/headcount/power and
   historical person eligibility. Each source write advances per-person and aggregate mutation revisions, then
   attempts a bounded best-effort electorate callback without making the canonical write depend on a replaceable
   module. New referenda/elections require the current voting policy's immutable electorate pointer to match the
   kernel electorate and call `snapshotAtCurrentEpoch(lastCompletedBlock)`; voting requires current good standing
   plus historical eligibility and stake. `snapshotAt` remains a historical API for already-pinned processes.
   `DemoSetupAuthority` instead pins seeded state to its current transaction block; later same-block checkpoints can
   still change that block's read, so it is illustrative and never deployed in production. Review same-block
   checkpoint behavior, the separate production genesis import, source-revision catch-up, liquidation transfers,
   and the invariant `LLM balance >= aggregate active stake` independently.
2. **Upgrade consistency — accepted audited-module trust model.** Every non-core replacement identifies an exact
   address and passes its referendum threshold, timelock, and Senate window. State, policy, authority, and new
   extension IDs require the constitutional double threshold; known bounded apps use the ordinary module threshold.
   Active referenda and elections pin their starting policies. Senate negative-control processes intentionally use
   the live Senate policy, so a policy replacement may immediately affect their threshold or duration. Atomic action
   batches support coordinated pointer changes. A pointer does not migrate storage/custody, and defective approved
   `ReferendumApp` bytecode can disable the only current referendum path. The project rejects a permanent recovery
   admin and requires bytecode, interface, paired-pointer, state/custody migration, and fork review instead. The
   incumbent Senate cannot cancel or hold open the active referendum for its exact replacement, and its queued-action
   cancellation hook is skipped only for the resulting `SENATE_APP` replacement. The review-pause hook is skipped
   only for the exact `CONSTITUTIONAL_REVIEW` replacement, so neither module can make itself irreplaceable.
3. **Electorate checkpoint liveness — hardened operational model.** Constitutional totals are O(1). A citizen-policy
   replacement begins a bounded permissionless rebuild. A failed best-effort source callback makes `isReady()` false
   through aggregate mutation-count mismatch; `syncPerson` or bounded `rebuild` catches up the affected state. New
   process creation is unavailable during either gap and in the block that completes catch-up/rebuild because it
   snapshots the last completed block; it resumes in the following block. Historical reads remain usable by
   processes already pinned to their old policy/electorate. Review epoch replacement, current-policy/current-
   electorate consistency, revision arithmetic, gas bounds, unknown-person rejection, completion-block behavior,
   and frontend/keeper recovery.
4. **Fixed-price lending — intentionally accepted launch risk.** Mainnet deploys a fixed 1 LLM = 2 USDC oracle, 30%
   LTV, 40% liquidation threshold, 15% bonus, 15% reserves, 1,000,000 USDC aggregate cap, and 100,000 USDC
   per-person cap. There is no market-feed manipulation or staleness path, but the price can become economically
   wrong. Debt uses one compounded RAY index; effective interest/reserve inputs are checkpointed by interval, and a
   lien snapshots its citizenship floor until cleared. Risk-policy construction requires
   `threshold * (1 + bonus) <= 100%`. Independently review rounding, delayed accrual, donations, policy changes,
   economics, real USDC bytecode, liquidation/bad-debt edges, and fork rehearsal. In particular, `absorbBadDebt`
   remains blocked only while surplus stake can cover the rounded seizure for the smallest repayment that reduces
   scaled debt; protected/retained floor stake is not recoverable collateral. The oracle/risk/rate policies are
   replaceable; replacing the pool itself requires state/custody migration.
5. **Production deployment parity — resolved in code; retain script review.** Both manifests deploy `DecisionApp`,
   `MinistryTreasury`, and lending. Production requires a six-decimal `USDC_TOKEN`, registers the pool as lien and
   liquidation authority, wires `DecisionApp` as ministry funding authority, and exports every address. Review
   module-batch completeness and environment/output parity independently. During production genesis,
   `InitialSetupAuthority` exclusively controls the Congress registry until the continuity cycle is seeded; the
   script then activates `CongressElectionApp` before readiness and sealing.
6. **Genesis and asset verification — open operator launch blocker.** Identities, stake, Senate, seven Congress
   incumbents, President, offices, admins, treasury assets/limits, reward reserve, and continuity time are inputs.
   The deployer must hold exact stake backing. The script checks LLM decimals/cap/supply and USDC decimals, but an
   independent reviewer must prove exact token bytecode and proxy/upgrade surfaces cannot bypass assumptions.
7. **Person-bound authority and office lifecycle — hardened; retain in focus.** Congress, Senate, President, Prime
   Minister, minister, and term-bound ministry-office authority follows the identity registry's active wallet.
   Candidacy is person-bound within each cycle: its canonical application wallet remains a stable ballot target even
   if reassigned, while withdrawal follows the caller's current active-person link and eligibility/seat assignment
   follow that person's current active wallet. Expiry,
   dismissal, resignation, or replacement removes office authority; read paths invalidate expired clerks without a
   cleanup transaction, and administration epochs invalidate old clerks in O(1). President ballots cannot be
   preloaded while an incumbent remains in term. A permissionless `recallUnrepresentedSeat` vacates a Congress seat
   only after proving its person has no active wallet; it reverts while the person is represented. Generic offices
   intentionally remain wallet-bound. Review role displays, zero-active-wallet behavior, succession, and all
   frontend resolution paths.
8. **Treasury and negative-control reconciliation — hardened; retain in focus.** Routed payout cancellation cancels
   the timelock action before releasing its budget; permissionless synchronization verifies execution against the
   action's pinned vault. Ministry lending shares are keyed by office and pool so retired pools remain withdrawable.
   Before repeal, public-veto reads exclude currently ineligible supporters and the next cast prunes them; completed
   repeals preserve their final count. Review state reconciliation, replacement boundaries, bounded supporter
   iteration, and exact budget accounting.

## Known omissions and accepted boundaries

The repository does not implement a Judiciary branch or constitutional Agents. Foreign Affairs, Interior, and
Justice have political minister records but no v1 operational offices/domain apps. Other draft-to-code differences,
including equal-base voting, Public Veto official removal, Senate scope, treaty classification, and Vice-President
succession, are classified in `docs/Constitution-Alignment.md`.

The fixed launch oracle is intentionally accepted. The following are not accepted substitutes for launch review:

- unverified genesis or token bytecode;
- an unrehearsed state/custody migration;
- an independently upgradeable replacement proxy or generic delegatecall executor;
- a production deployment without the final external audit and mainnet-fork rehearsal; or
- treating the current internal review as mainnet approval.

## Required handoff refresh

Before the external-audit package or any new public demo is treated as current:

- complete the revision-specific build, full test, coverage, Slither, runtime-size, and deployment-integration run
  recorded in `docs/Internal-Audit-Report.md`;
- regenerate the entire `frontend-export/abis/` directory from the same commit rather than merging individual files;
- make a fresh Sepolia deployment, replace the ignored live manifest, and confirm
  `identityApp == demoCitizenGateway`; and
- smoke-test onboarding, candidacy across wallet migration, voting, office expiry, payout cancellation/sync, public
  veto eligibility changes, ministry withdrawals from a retired pool, and lending accrual reads through the
  frontend integration.

## Documentation hierarchy

- `docs/Architecture.md`: system model and design constraints
- `docs/Protocol-Parameters.md`: boss-review production/demo parameter table
- `docs/Internal-Audit-Report.md`: internal findings, fixes, residual risks, and readiness verdict
- `docs/Audit-Scope.md`: external review boundary and focus
- `docs/Constitution-Alignment.md`: draft comparison and accepted deviations
- `docs/Ethereum-Mainnet-Deployment.md`: production procedure
- `docs/Sepolia-Demo-Deployment.md`: demo procedure and seeded state
- `docs/Lending-And-Treasury.md`: money, lending, and ministry treasury
- `docs/User-Journeys.md`: role-by-role workflows
- `frontend-export/`: frontend handoff; never protocol authority
