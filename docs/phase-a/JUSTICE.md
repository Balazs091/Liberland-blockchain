# Justice procedures and limits

The 10 November 2026 instructions select simple majority, the Council and Panel for exceptional wallet recovery,
execution by any caller as soon as an approved effect may take effect, confidential proceedings, and exclusion
of people whose membership has ended from the voting roll. Welfare following unpooling also excludes a person
from the roll until the welfare period ends. Fresh genesis starts with an empty case history. Land adjudication
belongs to a separate release.

These rules are implementation defaults for the justice profile. The adopted charter, named appointees and
genesis records are production inputs.

## Who may decide

Each appointed body has 3 to 15 distinct verified adult citizens. A majority means more than half of the
appointed roster. Absence, abstention, conflicts and vacancies do not reduce that number. The subject cannot
vote on their own case. A signer must hold the person's current active wallet. Removed membership and a current
restriction on holding an appointment prevent service. Off-chain review handles other conflicts and recusal.

The public charter fixes the roster, term end, permitted rights and maximum duration per restriction.
The appointing authority publishes the charter and binds its hash to the application. It can choose narrower
limits. The application caps temporary restrictions at one year. Roster or charter replacement requires the
constitutional module governance route. Change `JUSTICE_APP` and `IDENTITY_WRITER` together, retain the stable
decision, membership and compensation records, and collect fresh signatures for unexecuted decisions.

| Effect | Required approval | Limit |
| --- | --- | --- |
| Citizenship acquisition | Admission Commission majority, sitting Interior Minister, sitting President and destination consent | Signed regular, descent or birth route. An existing applicant keeps their active wallet. The approved mandate is bound to the current President sequence and minister's term record. |
| Fraud annulment | Two disjoint Commission review stages, each with its own majority | At least 21 days from service. No recorded original Commission approver may vote. Preserves the person's wallet and assets. |
| Citizenship restoration | Both Commission review majorities | Reverses only the exact active annulment recorded by this system. |
| Adulthood recognition | Admission Commission majority and active wallet consent | Updates a verified minor's age classification after evidence review. |
| Exceptional wallet recovery | Council majority, separate Panel majority and destination consent | At least 30 days from service. Current active link required. Changes one protocol wallet link for the same person. The case record includes any objections and their resolution. |
| Temporary restriction | Council and Panel majorities | At least 21 days from service. Exact person, rights and exclusive end. Only charter rights may be affected. |
| Membership removal | Council and Panel majorities | At least 21 days from service. Ends membership without a timer. Citizenship and property are separate. |
| Membership restoration and order relief | Council and Panel majorities | Restore membership or stay, resume or revoke one named order. Resumption keeps its original expiry. Other orders retain their independent effects. |
| Compensation | Council and Panel majorities on a separate financial decision | At least 21 days from service. A final award can use only the signed amount of an eligible voluntary LLM deposit. |
| Funded restoration | Council and Panel majorities on a separate financial decision | Credit the original subject using funds allocated to the exact award, up to its unrestored amount. |

The admission, annulment and annulment review rosters are disjoint. The Council and Panel rosters are also
disjoint. Shortfalls require a valid appointment through governance. Expired terms stop new executions. The private
conflict check covers earlier admissions whose signers are absent from the new public ledger.
The code refers adverse restrictions, removal and annulment involving current constitutional office holders
outside these case powers. Ordinary voluntary wallet changes use direct old and new wallet consent, and an
active citizen can renounce citizenship through the typed identity writer.

## Private cases and public decisions

Keep the case file, service proofs, submissions and ballots in a private document store. The parties, their
authorised representatives and assigned decision makers receive access. Before signing, each deciding body
checks lawful service, the opportunity to answer, hearing and review where applicable, and any stay. A
cryptographic commitment identifies the reviewed record. The signatures attest those procedural facts.

Prepare a redacted public ruling that identifies the subject and explains the decision. Use a durable
content-addressed URI and preserve copies. Sign the exact URI hash and a salted commitment to the private
record. Submit only the public ruling URI, decision fields, typed effect and approvals to Ethereum. The
execution event publishes the ruling URI and the two commitments. Transaction submission can expose the
packet even if it reverts, so publish and relay only after the case has reached its disclosure point. Keep
private documents, witness details and unneeded identifying information out of the public packet.

Each certificate is signed under the `Liberland Justice` EIP-712 domain, version `1`, with the target chain ID
and application address. The ABI exposes `decisionDigest` and `destinationConsentDigest`. Use the field order
in `JusticeTypes.Decision`, with `action` encoded as `uint8`. Compute `effectHash` as
`keccak256(abi.encode(effect))` with the typed entry point's effect tuple, and `reasonHash` as the Keccak hash
of the UTF-8 URI. Use unpredictable unique decision IDs and sort each body's signatures by ascending person
ID. Read `stateRevision` using `decisionStateRevision`. For recovery it changes only when an exceptional
recovery succeeds. The decision replaces the named person's current active link, so the holder of the
compromised key cannot defeat recovery by moving that link first. Other decisions use the identity revision. Use the order or membership revision where
specified for membership effects. Admission also binds the presidency sequence and the ABI hash of the
current Interior Minister record. A recipient signs the separate destination digest.

Any relayer can execute the final signed decision once its notice window has elapsed. All checks, replay
recording and the effect run in the same transaction. Reverted effects leave the decision available for
retry until its deadline. Sign only after legal finality. A signed final certificate can execute immediately.
The bodies decide objections and stays before issuing that certificate. Executed temporary orders have
separate stay and relief effects. The stable ledger preserves decision IDs across app replacements.

### Operator handoff

Use the [synthetic packet example](../../frontend-export/justice-decision.example.json) for the field layout.
Replace every example value with the reviewed public inputs; never sign or submit the example. Take the
chain ID and Justice address from the verified deployment and read `decisionStateRevision(action, personId)`.
For admission, also read the current presidency nonce and Interior Minister record as described above.
The `effect` object must use the fields of `IdentityEffect`, `MembershipEffect` or `FinancialEffect` from
[JusticeTypes](../../contracts/types/JusticeTypes.sol), according to the action.

Prepare locally using Python 3 and the repository's Foundry `cast`:

```sh
python3 scripts/prepare-justice-decision.py public-decision.json > unsigned-decision.json
```

The helper computes the effect, reason and decision hashes and outputs `authorityTypedData`, plus
`destinationTypedData` when the action requires wallet consent. It rejects unknown fields and ruling URLs
with credentials, queries or fragments. It makes no RPC calls, reads no signing keys and neither signs nor
submits anything. The helper checks the encoding; it cannot check whether the ruling is redacted, the
record commitment is salted, the signers are authorised or the decision is executable. Keep private files,
salt, evidence, credentials and private notes out of its input and output.

After disclosure is authorised, check the chain and address against the verified deployment, confirm
`isCurrent()`, and compare the local digest against the contract on a trusted node:

```sh
cast call "$JUSTICE_ADDRESS" \
  'decisionDigest((uint8,bytes32,bytes32,bytes32,bytes32,bytes32,uint64,uint64,uint256))(bytes32)' \
  "$(jq -r '.decisionTuple' unsigned-decision.json)" --rpc-url "$TRUSTED_RPC_URL"
jq -r '.decisionDigest' unsigned-decision.json
```

When destination consent is required, compare `destinationConsentDigest` with the same tuple and return
type. An RPC call reveals its arguments to the provider. Only collect signatures over the exact reviewed
typed data; do not change the effect, ruling URI, revision or destination after signing. Keep the signed
packet private until the approved submission point and simulate the complete call only on a trusted node.

## Voting, stake and custody

The justice policy excludes membership removal, insufficient pooled stake and active welfare from
constitutional headcount and voting weight. Temporary political restrictions affect live participation.
The existing electorate records completed-block snapshots. Existing ballots keep the eligibility snapshot they originally selected. A new ballot requires a certified
current-epoch snapshot. Arbitrary historical reads during an unprocessed expiry gap are diagnostic.
Process due welfare expiries with bounded
`syncExpired` calls, then let a block complete before relying on the new snapshot. An uncertified headcount
blocks new snapshots. Congress candidacy and Cabinet appointments also check appointment eligibility. Other restriction bits
remain explicit facts for their respective institutions. Lending keeps its separate identity, stake and
welfare checks.

Compensation runs in a separate LLM escrow. A person deposits a fixed lot with a terms hash and expiry.
An award identifies one lot and an earlier completed-block cutoff. Later deposits are separate lots.
The first final award to execute uses the available balance. After expiry the depositor may withdraw what
remains. Beneficiaries claim from their current active wallet. Restoration funding is an irrevocable,
award-specific allocation and awaits a separate approved restoration. Existing pooled stake, loans and
collateral remain in their original ledgers.

## Fresh genesis and review

The production script selects this profile with `JUSTICE_ENABLED=true`. Supply the charter hash, term end,
rights mask, duration limit and all five rosters of official genesis person IDs. The identity writer takes
standing authority at completion, and the case app requires bootstrap retirement. Admission becomes
available once the normal Cabinet process fills the Interior Ministry.

Verify the complete genesis, canonical module bindings, private case operations and control of appointed
wallets before public activation. The 5 November audit and CI results describe the earlier source.

### Reproduce the source-level genesis fixture

From the repository root, run the tracked [Forge integration test](../../test/scripts/DeployGenesis.t.sol).

```bash
forge test --match-path test/scripts/DeployGenesis.t.sol \
  --match-test test_DeploySeedsDeterministicGenesisBeforeSeal -vv
```

The test runs both stages for the Justice profile with nine synthetic citizens, five rosters and mock assets.
It rejects changed stage-one inputs at completion and checks the parked setup authority, final module
bindings, electorate initialization, retirement of bootstrap and the typed renunciation path. It invokes
the deployment helpers in Forge without RPC or transaction broadcasts. This exercise covers source-level
integration. The transaction receipts and gas figures below are from a separate localhost rehearsal.

## Historical verification of the initial Justice release

These 10 November 2026 results apply to commit `00da5bc`. Use revision-specific evidence for later changes.

The optimized suite passed 892 Foundry results across 73 suites, including the grouped invariant campaigns.
The coverage run passed 891 results with the established instrumentation exclusion for the 1,000-candidate
stress test. JusticeApp reached 94.47% line and 60.78% branch coverage. All 63 ABI exports matched compilation.
The reviewed Slither gate passed with the full [detector inventory](../Static-Analysis-Triage.md).

JusticeApp runtime size was 17,418 bytes. The final fresh genesis rehearsal used nine synthetic citizens on
localhost. All 93 transactions and 56 read-back checks passed. The largest transaction used 6,926,942 gas.
The rehearsal verified the parked writer, completion, charter, rosters, electorate readiness and bootstrap
retirement.
