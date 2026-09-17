# Current Governance Rules

These rules describe the current source,
not a deployed upgrade or independent security certification. See [Protocol Parameters](Protocol-Parameters.md)
and [Release Readiness](Release-Readiness.md).

## Identity, citizenship and wallet custody

New non-citizen onboarding uses `registerIdentity`, initial `linkWallet` proposal and destination
`acceptInitialWallet`. The one-time `setCitizenship` grant requires a verified adult without final suspension or
a pending civic case. Renunciation retires that grant path; reinstatement and adjudicated civic changes require
the two-officer procedure. Metadata correction cannot alter civic fields.

Ordinary wallet migration requires the current wallet's proposal, exact nonce-bound destination consent, officer
approval and two days. Exceptional recovery requires an admin's evidence-backed proposal, destination consent,
a distinct current officer and seven days; the old wallet can challenge by cancellation. Request IDs bind chain,
app, person, old/new wallets and nonce. Finalization rechecks wallet bindings and the officers' appointment IDs.
Revocation/regrant, administration changes and office deactivation/reactivation invalidate earlier approvals,
including changes in the same block. Different known wallets of one person are not distinct officers.

The migration-delay constructor rejects zero or more than `uint32.max` seconds (about 136 years). This is an
arithmetic safety boundary, not the selected notice period; both network manifests still select two days.

### Binding civic notice and appeal

1. An Identity admin proposes exact civic fields with a nonzero evidence hash. A distinct officer approves the
   unchanged request and starts seven days' notice. Approval pins the current `CIVIC_APPEAL_AUTHORITY` committee.
2. The affected active wallet can call `appealCivicChange` once, with a nonzero evidence hash, strictly before the
   notice ends. The appeal stays execution; it does not delete the case or restart the notice.
3. `CivicAppealReview` has exactly five immutable reviewer accounts. Three must approve the identical
   person/request/outcome/reason-hash digest, bound to chain, committee and app. Votes may be withdrawn before
   execution. The committee cannot alter the proposed fields, create cases, recover wallets, move assets or
   execute arbitrary calls.
4. Reviewers cannot be the subject, proposing/approving officer, or a current Identity officer. Known person
   aliases cannot count twice, and historical inactive identity wallets cannot vote. These checks run again when
   a ruling executes. Independent human control and evidence quality require off-chain verification.
5. A reasoned ruling must execute strictly before 30 days from appeal filing. Dismissal closes the case without
   changing status. Upholding permits permissionless finalization after the later of the original notice deadline
   and two days after the ruling. There is no second appeal of that request.
6. At the 30-day deadline, anyone may call `expireCivicAppeal`; an unanswered appeal is dismissed, never
   automatically upheld. This protects due process but requires a responsive review committee for enforcement.
7. Current Identity officers may withdraw a case, but the subject cannot use an officer appointment to withdraw
   their own case. Renunciation remains immediate and invalidates pending civic requests; returning to citizenship
   then requires the civic procedure, not the one-off onboarding grant.

Off-chain case records must define the grounds, evidence access, notice delivery and signed reasons. Only hashes
are on-chain; a hash does not prove truth or document availability. This is a narrow civic adjudication workflow,
not a general Judiciary or permission for slashing, property seizure or emergency intervention.

Committee rotation requires a constitutional-threshold, exact-address module replacement. Existing approved
notices retain their original committee; replacement does not hijack open cases. Unresponsive old committees
remain subject to the fixed timeout. Replacing IdentityApp itself requires a separately reviewed state/process
migration, and the new committee must bind the matching app.

## Public repeal

Two currently eligible, distinct people initiate a Law-tier repeal referendum. They do not repeal the law or
automatically cast referendum votes. The normal citizen-origin quorum/majority, seven-day voting duration, pinned
policy/snapshot and standard adoption delay apply.

The ordinary citizen quorum is 10,000 LLM of turnout and passage requires weighted For > Against; there is no
separate ordinary headcount quorum. Consequently, two eligible people with at least 5,000 LLM each at the snapshot
can also pass the resulting referendum if everyone else abstains, subject to the usual delays and negative checks.
This low-turnout rule applies on mainnet as well as Sepolia. Raising participation requirements needs an explicit
governance-policy decision; the current requirements are retained. The two-person petition is not itself an
immediate veto or repeal.

Passage queues the exact `(measureId, referendumId)` as a typed `LegislationRepeal` action. The timelock verifies
referendum origin and matching reference; execution is delayed, Senate-cancelable and replay-protected. The
legislation registry accepts this public-origin repeal only from the timelock and only for Law tier. Constitutional,
Treaty and sub-legal exclusions remain. `PublicVetoApp` is an Authority-class module.

Only one petition can be live for a measure. Before submission, eligibility is rechecked and stale signatures are
pruned. Submitted signatures are historical. After defeat/cancellation, or cancellation/expiry of an unexecuted
successful action, `resetPublicPetition` clears the bounded two-signature collection, advances its nonce and requires
fresh signatures. An active vote or executable successful action cannot be reset.

## Congress admission and counting

There is no first-come policy admission quota. `maxCandidateCount() == 0` means open admission; the retained
constructor argument and record field do not enforce a cap. Production keeps seven seats, two runner-up slots and
the 6,000-LLM candidacy requirement. Incumbents automatically enter without consuming challenger slots. The
separate one-time genesis import remains bounded to seven-to-nine ranked members.

Each candidate registry creates one immutable `CongressRankingStore`. It has no owner key, replacement setter or
arbitrary-call surface. The registry's kernel-approved writer controls both registries; users call the permissionless
`CongressElectionApp.finalizeElection` workflow, not the ranking-store mutators.

- Voting closes under the pinned cycle window. Finalization freezes the candidate set and reads fixed-width scores.
- `finalizeElection(uint256)` processes at most 32 candidates into a durable maximum heap, then considers at most 32 heap heads
  once insertion is complete. Each heap insertion/removal is O(log N); the seat/runner-up set is separately bounded.
  The overload `finalizeElection(uint256,uint256)` accepts a workload of 1 through 32 for each phase; use a smaller
  workload when gas estimates require it. Selected outcomes are still revalidated before completion.
- Ordering is net votes descending, application time ascending, then canonical application address ascending.
  Negative-score candidates receive no seat. Only elected and runner-up ordinal ranks are materialized; other
  unselected candidates read as Lost with rank zero.
- Current eligibility is checked on selection and immediately before activation. A candidate disqualified during
  counting cannot re-enter that count. Stake is not separately reserved; temporary eligibility loss can forfeit
  candidacy for this cycle.
- A successful intermediate transaction is progress, not finality. Read `rankingStore()` on the candidate registry
  and `progress(cycleId)` on that helper, and continue until the canonical cycle is Finalized.
- Final activation completes only the pinned cycle. Anyone then explicitly calls `createNextElectionCycle()` once
  current policy and electorate are ready with a certified completed-block snapshot. A failed future-cycle creation
  cannot roll back the completed outcome; synchronize/rebuild the electorate when needed.
- Missing identity wiring fails closed instead of granting authority to a historical seat wallet.

The multi-transaction count needs independent adversarial review, including interrupted counting, policy changes,
wallet migration, eligibility changes, ordering and gas at substantially larger populations.

Voting still requires both current good standing and eligibility/stake at the process's completed-block snapshot.
Snapshot weight cannot manufacture present rights for a suspended or otherwise ineligible wallet. Eligibility
evaluation reads fixed-size civic facts rather than copying metadata URIs, keeping metadata size out of the bounded
electorate synchronization and voting path. Permissionless electorate rebuild calls clamp an oversized requested
workload to the remaining identities before adding indices; callers should still choose gas-appropriate batches.

Congress schedule durations and the unstaking welfare period reject values above `uint32.max` seconds. These are
technical constructor limits; the production 90-day Congress cadence, 30-day welfare and existing voting rules are
unchanged. A reviewed policy replacement is still required to choose different operational values.

Prime Minister removal retains the number of supporting votes recorded at appointment, not a newly computed
majority of a shrunken Congress. Congress decisions likewise retain their prepared support threshold within the
same Congress term, while execution rechecks current eligible supporters; a later term cannot inherit the old
approval. Runner-up succession normally fills vacancies, but the contracts cannot guarantee enough eligible
runner-ups. If occupied seats fall below the Prime Minister's recorded appointment tally, ordinary removal cannot
meet that threshold until sufficient representation returns or the term expires. A decision can be freshly
prepared under the current membership instead of reusing an impractical old threshold. These limitations are
retained policy, not an undisclosed administrative recovery power.

## Office appointments, Finance and Senate

One wallet or known person may administer multiple offices. Roles, clerk epochs, appointment identifiers,
revocation, activity and expiry remain office-scoped; changing one office does not alter the others. Generic
appointments remain wallet-bound; term-bound executive appointments follow the current active wallet and expire
in read paths, including when that wallet already administers another office.

Holding several offices does not turn one person into two approving officers or an independent civic reviewer.
Shared administration concentrates the powers of the appointed offices. The mainnet deployment script requires
distinct initial admin addresses and production operations require independent controllers; the registry does not
enforce continuing cross-office separation. Different addresses alone do not prove independent control.

Every Finance payout requires an immutable proposal plus `approvePayout` from a distinct current officer.
The original proposer's spending class, asset limits, exact policy reference and appointment must remain valid
at routing. The second officer may be a clerk, including for admin-proposed sensitive payouts. Grants,
contribution rewards and capital expenditure still require an admin proposal; ordinary clerk proposals retain
their per-payout limits. Both known-person separation and appointment IDs are rechecked before routing.
The proposer or approver may withdraw the second approval before routing. Once routed, cancel the queued action
through the existing cancellation path; revoking an officer alone does not cancel a historical queued action.

The pre-route delay begins at proposal; the normal timelock follows routing. Budget commitments and exact
treasury transfer checks remain unchanged. Approval is not a mint authority or permission to exceed budgets.

All Senate negative powers require `max(2, configuredMinimum, floor(occupiedSeats / 2) + 1)` direct seat approvals.
The current implementation counts each occupied seat once and has no President proxy substitution entry points.
At 100 occupied seats, 51 direct approvals are required; at two occupied seats, both are required. Transfers and
vacancies invalidate the previous occupancy's receipt. Thresholds and occupancy are rechecked at finalization
or suspension/renewal; records/events retain the support and required threshold used. Tally iteration is bounded by
the stable registry's 100 seats, not a replaceable policy's reported seat count.

## Compatibility and release

The design provides no permanent second upgrade ballot and no general exemption
from negative powers. Optional hooks have bounded gas/canonical ABI handling, but broken referendum dependencies
and mutual Senate/review blocking remain recovery limits. See [Upgrade and Liveness](Upgrade-And-Liveness.md).

Deployment requires a fresh instance or separately reviewed state/custody/process migration.
Committee pointers, appointment nonces, payout approvals and Senate interfaces must be included in the
deployment manifest, frontend ABI bundle and migration scope. No pointer update copies storage or retires old code.

Production requires independently controlled office administrators, five independent civic review accounts,
operational Identity/Finance clerks, verified genesis inputs, economic/token review, external adversarial audit
and a production-state fork rehearsal. The audit candidate is not mainnet authorization.
