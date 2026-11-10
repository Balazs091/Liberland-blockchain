# Current Frontend Integration Checklist

Use the [frontend guide](FRONTEND-HOWTO.md) for call sequences. Check deployed addresses and runtime code before
enabling writes.

## Configuration and authority

- Validate the wallet chain against manifest `chainId`: mainnet 1 or Sepolia 11155111. Example JSON files are schemas,
  not deployments. Production requires `genesisComplete == true` and on-chain bootstrap retirement.
- For the legacy identity profile, verify `civicAppealReview`, its five reviewer addresses and its IdentityApp
  binding against the kernel. An appealed case keeps its pinned committee after replacement.
- When `justiceEnabled` is true, verify the current Justice app and identity writer before enabling writes. Follow
  the [Justice operator handoff](../docs/phase-a/JUSTICE.md#operator-handoff) for signed decisions.
- Match every ABI to the deployed bytecode/source. Read module classes and live addresses from the kernel; every
  policy, authority, state or extension replacement needs the constitutional threshold, including election policies.
- Keep a process's pinned policy and completed-block snapshot. Do not replace them with the latest policy when
  displaying a live vote. Senate negative-control processes intentionally use their current policy.
- Use one typed module bundle for paired app and authority changes after reviewing the migration.
  Append-only enum values are referendum class `ModuleBundle = 7` and action type `ModuleBundleUpdate = 13`.
  Publish an immutable `ModuleUpgradePlanRegistry` plan, then call the citizen/Congress bundle proposal method with
  its exact registry and plan ID. Show all expected incumbents, successors, runtime hashes and evidence commitment;
  plan publication itself is not approval. Bundles always require constitutional thresholds and contain at most
  16 sorted distinct non-Core IDs, excluding Senate and constitutional review.
- Legacy `executeActions` batches retain individually executable members. A bundle instead has one action ID and
  cannot be partly executed. Senate/review have narrowly scoped single-replacement exceptions, not protection
  against mutual blocking or a broken referendum/policy/electorate. See
  [Upgrade and Liveness](../docs/Upgrade-And-Liveness.md) and [Recovery Plan](../docs/Recovery-Plan.md).

## Identity, stake and authority continuity

- Legacy onboarding uses `registerIdentity`, `linkWallet`, destination `acceptInitialWallet`, then an eligible
  citizenship grant. The Justice profile uses signed identity decisions and a separate voluntary wallet migration.
- Legacy wallet migration requires the exact `walletMigrationId`, destination acceptance, officer approval and a two-day delay.
  Exceptional recovery needs evidence, a distinct second officer and seven days. Show cancellation and notice state.
- Legacy civic notices allow one `appealCivicChange` before the seven-day deadline. Display the pinned committee, evidence,
  reviewer votes, 30-day ruling deadline and dismissal-on-timeout. Upholding retains the original notice and adds
  two days after the ruling. Use [Governance](../docs/Governance.md); the subject cannot cancel their own case.
- In the legacy profile, renunciation retires initial citizenship granting. Reinstatement needs the civic process. Show appointment-bound
  approvals as stale after revocation/regrant or office reactivation; never silently reuse them.
- Resolve elected/executive signers through `IdentityRegistry.activeWalletOf(personId)`, not historical record wallets.
  Executive/Congress support receipts may require recasting after migration; reassigned wallets inherit no support.
- LLM has 18 decimals and a 70,000,000-token cap. `unstake()` is discrete and starts welfare; there is no request/claim
  unstake balance. Person-keyed lending liens are released fully on debt repayment, not proportionally per payment.
- New vote creation requires a ready current-epoch electorate and the last completed block. Allow the full bounded
  electorate callback gas budget; after catch-up/rebuild, wait for the next block before retrying creation.

## Elections, referenda and public repeal

- Zero `maxCandidateCount` means open admission. Candidate metadata URIs are limited to 2,048 bytes, not characters.
- Preserve the canonical application address across migration. Use person identity for withdrawal and current
  qualification. Handle `BallotWalletOwnedByAnotherPerson`; old live receipts cannot be overwritten by reassignment.
- Ballots are cycle-scoped; recasting replaces that cycle's entire ballot. A clear operation follows the current
  person's prior receipt. Do not carry preferences into the next cycle without a new user submission.
- Counting is resumable. Read ranking-store progress/events; intermediate success is not finality. The original
  `finalizeElection(uint256)` defaults to 32; the overload accepts a workload of 1..32. Select explicit overloaded
  signatures and estimate mandatory final activation/revalidation too. After Finalized, separately call
  `createNextElectionCycle()` when current policy/electorate permit; render chain-returned/previewed timestamps.
- New voters need historical eligibility/stake at the process snapshot, not just current onboarding/eligibility.
- Optional Senate/review probes require canonical ABI and fit within 100,000 gas. Deliberately underfunded callers
  revert; valid active records cannot be bypassed by lowering transaction gas.
- Two public signatures initiate a repeal referendum; they are neither referendum votes nor final repeal. Show the
  vote, queue delay, action execution and registry result. Failed/canceled rounds need fresh petition signatures.
  The ordinary absolute-stake quorum has no electorate-headcount condition: two sufficiently weighted eligible
  voters can pass if others abstain. This is not limited to Sepolia.
- Senate suspensions/renewals require a supporting seat index and published reason hash. Read `requiredSupport()`:
  every negative power needs a strict occupied-seat majority and at least two direct votes. No President proxy
  functions exist. Seats need not belong to distinct people. Acquiring a Senate seat requires current citizenship;
  Senate repeal-origin metadata cannot bypass the registry's sub-legal scope.
- Congress decisions use their stored `supportRequired` and same-cycle lock, not today's new-decision threshold.
  PM removal uses the historical appointment tally. Show unavailable removal when vacancies leave too few members;
  eligible runner-up succession is conditional, not a guarantee. PM and President are distinct offices.
- Use loss of citizenship for `recallMember`. Low stake and unstaking affect candidacy and voting eligibility
  under their respective rules. A sitting member keeps their seat.
- Handle `InvalidAdoptionSchedule` / `InvalidActionSchedule` by correcting timestamp inputs, not increasing gas.

## Treasury, lending and registries

- Payouts need an approved budget envelope and exact current permissions. Finance contribution rewards are LLM-only,
  admin-proposed, distinct-officer-approved and evidence-backed (`DisbursementType.ContributionReward == 7`); there is no Treasury mint path.
- Budget approvals are Law-tier referendum decisions but do not create `LegislationRegistry` records. Public
  repeal cannot revoke an envelope; there is no generic budget-revocation button. Keep budget expiry/accounting and
  Senate controls over individual queued payouts distinct from legislation repeal.
- Show proposer, approver and their appointment IDs; call `approvePayout(officeId, requestId)` before routing. A clerk may review or route
  a sensitive admin proposal. Revalidate the original proposer's class/limits, not just the routing signer's role.
  Removing an officer after routing does not cancel the action; use the cancellation path.
- Reconcile payouts with `syncPayoutState` on their original queue after execution/cancellation/expiry. The stable
  budget-ledger `isRequestExecuted(requestId)` marker may already be true while queue state remains Queued; the
  pinned old vault receipt remains the synchronization evidence. Preserve consumed IDs across any budget-ledger
  migration and do not treat a replacement vault's false local receipt as proof that an old request was unpaid.
  `cancelPayout` in the current source also reconciles an already Senate-canceled action without canceling it twice.
- Pool positions are keyed by office and pool; support `poolSharesAt`/`withdrawFromPoolAt` for retired pools. Read `loanBookOf(personId)` and keep old
  loans tied to their originating pool until explicit closure, even if its lien reaches zero. Retired health,
  liquidation and bad-debt collateral are capped at the remaining lien; do not count later unpledged stake.
  New origination requires matching canonical identity/stake/lien registries and all three authority pointers.
  There is no debt/LP import.
- `currentDebtOf` previews interest; `totalBorrows`, `borrowIndex` and managed assets are stored checkpoints.
  `maxBorrowable` includes pending interest/reserves and scaled-debt rounding for the same state;
  still simulate before submission because other transactions or elapsed time can change capacity. There is no reserve claim.
- Rates are nominal APR compounded per second, not APY. A policy's combined nominal ceiling is 200%; replacement
  policies must report RAY and an accepted borrow rate. Handle `UnsupportedInterestRateScale` / `UnsupportedBorrowRate`.
  `EmptyBookIndexReset` returns the index to RAY only at zero scaled debt without changing cash, shares or reserves.
- Land transfers bind both title and parcel version hashes, parties, nonce, deadline, chain and app. Follow the
  exact [cadastre signing schema](../docs/Land-Cadastre.md), with current EOA/EIP-1271 signers and registrar execution.
- Land dispute acceptance and resolution require an exact approval from a verified clerk and finalization by a
  verified registrar with a different person ID. Refresh the case state before requesting approval.
- Director and share changes require `Active` or `ComplianceWarning`. Approved companies can record compliance
  filings while `Suspended` or `Dissolving`. Check the active title count before removing the last director or
  finalizing dissolution. Office role reads must reflect term expiry,
  per-office clerk epochs and current signer authority. One wallet may administer several offices; display every
  appointment separately and never count shared control as a second approving officer.

## Handoff verification

Run `python3 scripts/check-docs.py --check-abis` from the repository root after the optimized build. Regenerate with
`bash scripts/export-frontend-abis.sh` when needed. Verify the generated public manifest on-chain; Sepolia requires
`identityApp == demoCitizenGateway`. Smoke-test the workflows above before handing an integration to another team.
