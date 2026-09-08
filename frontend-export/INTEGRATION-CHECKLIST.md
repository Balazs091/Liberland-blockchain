# Current Frontend Integration Checklist

Use this checklist with [FRONTEND-HOWTO.md](FRONTEND-HOWTO.md). It describes the current interfaces only; it is not
a migration history or evidence that any deployed address uses this source.

## Configuration and authority

- Validate the wallet chain against manifest `chainId`: mainnet 1 or Sepolia 11155111. Example JSON files are schemas,
  not deployments. Production requires `genesisComplete == true` and on-chain bootstrap retirement.
- Verify `civicAppealReview`, its five reviewer addresses and its exact IdentityApp binding against the kernel;
  an appealed case uses its pinned committee even after a module replacement.
- Match every ABI to the deployed bytecode/source. Read module classes and live addresses from the kernel; every
  policy, authority, state or extension replacement needs the constitutional threshold, including election policies.
- Keep a process's pinned policy and completed-block snapshot. Do not replace them with the latest policy when
  displaying a live vote. Senate negative-control processes intentionally use their current policy.
- Use atomic typed action batches for paired app/authority changes, with a reviewed migration. No arbitrary executor
  exists. Members remain individually executable, so intermediate states still require review. Constitutional review
  and Senate have narrowly scoped self-replacement exceptions, not protection against mutual blocking or a broken
  referendum/policy/electorate. See [Upgrade and Liveness](../docs/Upgrade-And-Liveness.md).

## Identity, stake and authority continuity

- Production onboarding uses `registerIdentity`, `linkWallet`, destination `acceptInitialWallet`, then an eligible
  citizenship grant. Metadata correction is separate from delayed civic changes.
- Migration requires the exact `walletMigrationId`, destination acceptance, officer approval and a two-day delay.
  Exceptional recovery needs evidence, a distinct second officer and seven days. Show cancellation and notice state.
- Civic notices allow one `appealCivicChange` before the seven-day deadline. Display the pinned committee, evidence,
  reviewer votes, 30-day ruling deadline and dismissal-on-timeout. Upholding retains the original notice and adds
  two days after the ruling. Use [Governance](../docs/Governance.md); the subject cannot cancel their own case.
- Renunciation retires initial citizenship granting. Reinstatement needs the civic process. Show appointment-bound
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
- Senate suspensions/renewals require a supporting seat index and published reason hash. Read `requiredSupport()`:
  every negative power needs a strict occupied-seat majority and at least two direct votes. No President proxy
  functions exist. Acquiring a Senate seat requires current citizenship.

## Treasury, lending and registries

- Payouts need an enacted budget and exact current permissions. Finance contribution rewards are LLM-only,
  admin-proposed, distinct-officer-approved and evidence-backed (`DisbursementType.ContributionReward == 7`); there is no Treasury mint path.
- Show proposer, approver and their appointment IDs; call `approvePayout(officeId, requestId)` before routing. A clerk may review or route
  a sensitive admin proposal. Revalidate the original proposer's class/limits, not just the routing signer's role.
  Removing an officer after routing does not cancel the action; use the cancellation path.
- Reconcile payouts with `syncPayoutState` on their original queue after execution/cancellation/expiry. The stable
  budget-ledger `isRequestExecuted(requestId)` marker may already be true while queue state remains Queued; the
  pinned old vault receipt remains the synchronization evidence. Preserve consumed IDs across any budget-ledger
  migration and do not treat a replacement vault's false local receipt as proof that an old request was unpaid.
- Pool positions are keyed by office and pool; support `poolSharesAt`/`withdrawFromPoolAt` for retired pools. Read `loanBookOf(personId)` and keep old
  loans tied to their originating pool until explicit closure, even if its lien reaches zero. Retired health,
  liquidation and bad-debt collateral are capped at the remaining lien; do not count later unpledged stake.
  New origination requires matching canonical identity/stake/lien registries and all three authority pointers.
  There is no debt/LP import.
- `currentDebtOf` previews interest; `totalBorrows`, `borrowIndex` and managed assets are stored checkpoints.
  `maxBorrowable` includes pending interest/reserves and scaled-debt rounding for the same state;
  still simulate before submission because other transactions or elapsed time can change capacity. There is no reserve claim.
- Land transfers bind both title and parcel version hashes, parties, nonce, deadline, chain and app. Follow the
  exact [cadastre signing schema](../docs/Land-Cadastre.md), with current EOA/EIP-1271 signers and registrar execution.
- Company child-state writes require Active/ComplianceWarning status. Office role reads must reflect term expiry,
  per-office clerk epochs and current signer authority. One wallet may administer several offices; display every
  appointment separately and never count shared control as a second approving officer.

## Handoff verification

Run `python3 scripts/check-docs.py --check-abis` from the repository root after the optimized build. Regenerate with
`bash scripts/export-frontend-abis.sh` when needed. Verify the generated public manifest on-chain; Sepolia requires
`identityApp == demoCitizenGateway`. Smoke-test the workflows above before handing an integration to another team.
