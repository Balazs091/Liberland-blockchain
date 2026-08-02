# Internal Smart Contract Audit Report

Date: 2026-08-02
Target: pre-external-audit repository state
Verdict: ready for external-audit intake; not approved for Ethereum mainnet launch

## Scope and method

The internal review covered all Solidity contracts, interfaces, libraries, network parameter manifests, deployment
and setup scripts, authority retirement, cross-module replacement paths, accounting and custody flows, user and
government journeys, and the frontend documentation handoff. The methods included manual cross-contract tracing,
adversarial lifecycle review, Foundry build/unit/fuzz/integration runs, coverage, runtime-size inspection, full
unsuppressed Slither analysis, deployment-manifest comparison, and draft-constitution comparison.

This report is internal engineering evidence. It is not an independent audit, a lending-economic certification, or
mainnet approval.

## Verified baseline

- Foundry `1.7.1`, Slither `0.11.5`, and Solc `0.8.36`; every project pragma is pinned to `0.8.36`.
- The optimized build targets EVM `osaka` with 200 optimizer runs.
- `forge build --sizes`: pass.
- `forge test -vvv`: 315 passed, 0 failed, including the 256-run fuzz campaign.
- `forge coverage --report summary`: pass, 315 passed and 0 failed.
  - lines: 77.76% (6,324 / 8,133)
  - statements: 81.27% (7,200 / 8,859)
  - branches: 40.16% (512 / 1,275)
  - functions: 85.55% (1,018 / 1,190)
- Foundry emitted the known anchor/source-mapping warnings during coverage; the test run still completed
  successfully.

### Runtime sizes

The EIP-170 runtime limit is 24,576 bytes.

| Contract | Runtime size | Remaining margin |
| --- | ---: | ---: |
| `SenateApp` | 24,232 bytes | 344 bytes |
| `CongressCandidateRegistry` | 21,647 bytes | 2,929 bytes |
| `ReferendumApp` | 20,278 bytes | 4,298 bytes |
| `CongressElectionApp` | 17,385 bytes | 7,191 bytes |
| `LandRegistry` | 18,601 bytes | 5,975 bytes |
| `LandRegistryApp` | 12,096 bytes | 12,480 bytes |
| `LandPartyPolicy` | 4,809 bytes | 19,767 bytes |
| `ElectorateRegistry` | 6,453 bytes | 18,123 bytes |

`SenateApp` remains deployable but has little upgrade headroom. Any remediation or later feature that touches it
must rerun the size check immediately and may require deliberate decomposition.

### Slither

- Full unsuppressed `slither .`: 151 contracts, 101 detectors, 366 raw results.
- Project-only high/medium view
  (`--exclude-dependencies --exclude-low --exclude-informational`): 151 contracts, 63 detectors, 43 results.
- Manual triage found no concrete launch blocker in these results. The arbitrary-send findings are explicitly
  authorized source pulls; weak-PRNG is UTC-boundary modulo arithmetic, not randomness; equality findings are
  intentional state/zero checks; reentrancy findings are covered by `nonReentrant`, trusted fixed registries, or
  bounded best-effort callbacks; and unused-return findings are deliberate validation/checkpoint calls.

The raw output remains audit evidence, not a suppression list. External auditors should independently classify every
result.

## Resolved findings and implemented hardening

| Risk | Resolution |
| --- | --- |
| Replaceable electorate callbacks could brick canonical identity or stake writes | Identity and stake sources now advance per-person plus aggregate mutation revisions before a bounded-gas best-effort callback. Callback failure defers synchronization and is observable through electorate readiness; it does not revert the fact write. |
| A new vote could rely on stale or replacement-mismatched electorate state | `VotingPowerPolicy` immutably pins its electorate. New referendum/Congress creation requires that pointer to match the current kernel electorate and calls `snapshotAtCurrentEpoch(lastCompletedBlock)`, which verifies the current policy epoch and live source revisions. |
| Rebuild/catch-up completion could be selected before its checkpoint was a completed block | New creation remains unavailable in the completion block and resumes in the following block. Historical `snapshotAt`/`wasEligibleAt` remain available only for processes that already pinned their policy/electorate. |
| Political stake could be counted, transferred/unstaked/liquidated, and counted again in one process | Referenda and elections pin the last completed block; person eligibility and active stake are read at that block, while current good standing remains required at cast time. |
| A negative-control module could make its own pointer replacement impossible | Exact self-replacement exceptions prevent the incumbent Senate/review hook from canceling or indefinitely pausing only its own approved replacement. Referendum threshold, exact target, queue delay, and all other checks remain. |
| Wallet migration could duplicate candidacy or make ballot meaning depend on later address reassignment | Candidacy is person-bound. The original application address is a durable canonical ballot target; withdrawal follows the caller's current active-person link, and eligibility/seat assignment follow that person's active wallet. |
| A seat could remain occupied after its person lost every active wallet | `recallUnrepresentedSeat(seatIndex)` is permissionless but proves the zero-active-wallet condition and otherwise reverts; it then uses ordinary eligible runner-up succession. |
| Expired or migrated political roles could retain operational authority | Congress, Senate, President, Prime Minister, minister, and term-bound ministry authority follows the current active wallet. Office authorization expires in reads, and administration epochs invalidate stale clerks in O(1). |
| Payout cancellation/replacement boundaries could leave budget or custody state inconsistent | Routed cancellation cancels the timelock action first; permissionless synchronization checks the action's pinned vault. Treasury disbursement also revalidates the exact active budget commitment and exact recipient token delta. |
| Lending accrual/configuration changes could retroactively reprice debt | Debt uses one RAY-scaled global index and checkpoints the effective rate/reserve configuration by interval. Current debt has a preview getter; state-changing accrual remains explicit. |
| Bad-debt absorption could be blocked by collateral dust or incorrectly treat protected stake as recoverable | `absorbBadDebt` rejects only while surplus stake can cover the rounded seizure for the smallest repayment that actually reduces scaled debt. Protected/retained floor stake is not recoverable collateral. Reserves absorb eligible write-offs before supplier share value. |
| Replacing a ministry lending pool could strand an office's prior shares | Positions are keyed by office and pool, with explicit reads/withdrawal for retired pools. |
| Wallet-held land titles and registrar-only transfers could lose party continuity or bypass consent | Titles now store stable namespaced person/company/office IDs. The live replaceable party policy resolves current signers. Transfers require seller and buyer EIP-712/EIP-1271 authorization, a title nonce, deadline, expected version, anchored instrument, and registrar finalization. The current app cannot administratively close a non-expired title and recreate it around consent. |
| Multi-parcel cadastral changes could leave partial or untraceable state | Parcel/title revisions are domain-separated and source-document chained. Subdivision, merge, and two-parcel boundary adjustment validate the full bounded set before applying one atomic transaction. Clerk preparation and registrar finalization are separate permission classes. |

Regression coverage includes source-callback failure and catch-up, current-electorate creation checks, completion-block
rejection, historical pinned-process continuity, stake-transfer vote reuse, candidacy/address reassignment,
zero-active-wallet seat recovery, governance self-replacement liveness, payout reconciliation, office lifecycle,
global lending accrual, liquidation rounding, bad-debt dust, cadastral lineage, EIP-1271 consent, signer migration,
and atomic parcel operations.

## Accepted risks and external-auditor focus

1. **Audited-module replacement trust.** The protocol deliberately permits voters to approve future breaking module
   designs. A pointer vote does not prove bytecode correctness, migrate state/custody, or protect against voters
   approving a defective `ReferendumApp`. Exact bytecode/interface review, paired-pointer planning, migration
   evidence, atomic activation where needed, and fork rehearsal are the mitigation; no hidden recovery administrator
   exists.
2. **Fixed launch oracle.** Production intentionally starts with a fixed 1 LLM = 2 USDC policy. It has no feed
   manipulation or staleness path, but it can become economically wrong and external price decline alone does not
   change on-chain health. Launch limits are 30% LTV, 40% liquidation threshold, 15% liquidation bonus, 15% reserve
   factor, 1,000,000 USDC aggregate debt, and 100,000 USDC per person. Oracle/risk/rate policies are replaceable after
   review.
3. **Bad debt and protected floor.** The retained/protected political floor is intentionally unavailable to
   liquidators. Once no effective scaled-debt reduction is liquidatable from surplus stake, absorption can consume
   reserves and reduce supplier share value. Stress liquidation incentives, rounding, low-liquidity behavior, and
   treasury recapitalization.
4. **External assets and genesis facts.** Independently verify exact LLM/USDC bytecode, proxy/admin surfaces,
   decimals, LLM 70,000,000-token cap and supply, transfer behavior, stake backing, and every imported identity,
   office, role, balance, and continuity timestamp.
5. **Electorate operations.** Source writes remain live when synchronization fails, but creation intentionally pauses
   until permissionless catch-up/rebuild completes and its block becomes historical. Review revision arithmetic,
   callback gas bounds, replacement sequencing, keeper/frontend recovery, and worst-case population growth.
6. **Gas and code size.** Review bounded Senate/candidate loops, caller-supplied atomic action batches, worst-case
   election finalization, and the 344-byte `SenateApp` margin. Branch coverage is materially lower than line/function
   coverage, so external review should prioritize adversarial state transitions and failure paths.
7. **Current-policy exceptions.** Referenda and Congress cycles pin their policy bundle, but active Senate
   negative-control processes intentionally read the current `SenatePowersPolicy`. A replacement proposal must
   disclose its effect on open Senate processes.
8. **v1 scope.** Judiciary/Agents and operational Foreign Affairs, Interior, and Justice domain apps are not present.
   Their absence does not grant those powers through a generic executor.
9. **Cadastre law and off-chain data.** Solidity does not validate geometry, retain legal documents, determine
   co-ownership, calculate transaction fees, provide insurance/compensation, or enforce court judgments. The
   registrar anchors canonical records and source instruments. Later features require defined law/data standards
   and reviewed replacement apps/policies or dedicated registries; no generic placeholder custody or override is
   deployed.

The boss-review values and accepted policy choices are collected in `docs/Protocol-Parameters.md`; the external
review boundary and focus are in `docs/Audit-Scope.md`.

## Remaining launch prerequisites

The code is ready to enter an external audit, but mainnet remains blocked on:

1. a fresh Sepolia redeployment from the reviewed revision, explorer source verification, regenerated address
   manifest, and frontend smoke test of onboarding, migration, election/referendum creation, office work, payouts,
   lending, cadastral EIP-712/EIP-1271 transfers, parcel operations, and recovery paths;
2. final production parameter-manifest and genesis/migration values, independently checked and signed off, including
   real token addresses/bytecode, seven occupied Congress seats, stake backing, offices/roles, treasury limits,
   contribution-reward reserve, and the 17:00 UTC continuity endpoint;
3. a mainnet-fork deployment and lifecycle rehearsal with those exact values, including bootstrap retirement,
   invariant checks, lending liquidation/bad debt, wallet migration with active roles and land titles, election
   rollover, treasury reward flow, cadastral record migration, and a representative module/state migration;
4. an independent smart-contract and lending-economic audit, remediation, and rerun of build, tests, coverage,
   Slither, sizes, deployment integration, source verification, and frontend smoke tests.

## Readiness conclusion

No concrete unresolved critical/high source-code blocker is known from this internal review. The repository is ready
for external-audit intake because the current behavior, parameters, trust assumptions, operational pauses, and
frontend integration requirements are explicit and verified against the current test/build baseline. This verdict
must not be presented as production approval: fresh deployment evidence, final production inputs, fork rehearsal,
and independent audit are still required before Ethereum mainnet use.
