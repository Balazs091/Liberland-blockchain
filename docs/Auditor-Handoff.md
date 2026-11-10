# Auditor handoff

Audit the contracts, deployment paths and tooling at the submitted revision. Include both genesis profiles and
the company and land registry changes in scope. See [Justice procedures](phase-a/JUSTICE.md),
[Land Cadastre](Land-Cadastre.md) and [Release Readiness](Release-Readiness.md).

## Identify the target

For a Git submission, include all contracts, tests and scripts in the submitted commit. Record the full commit
and tree hashes, toolchain versions and recursive submodule revisions.

For a source archive, identify the immutable artifact by its SHA-256 and complete source inventory. Its
`PROVENANCE.json` must distinguish a published commit from a working-tree snapshot based on an older commit.
A working-tree snapshot must record its base commit, state that no candidate commit has been published, and bind
all included project and dependency files. Do not label the base commit as the revision containing the changes.

Use `SOURCE-SHA256.txt` for source/dependency contents, `PACKAGE-SHA256.txt` for the full package and a separate
checksum for the outer archive. Verify those files before reproducing the checks. The source archive excludes Git
metadata, local settings, production keys, real genesis personal data, credential caches and generated build output.

The export manifest contains 63 frontend ABIs. The source uses Solidity 0.8.38 and the dependencies in
`foundry.lock`. The 5 November archive, the 10 November published justice baseline and the historical public
Sepolia deployment each carry their own revision-specific evidence. See [Release Readiness](Release-Readiness.md).

## Package contents

| Path | Contents |
| --- | --- |
| `source/` | Complete contracts, interfaces, tests, scripts/configuration, docs, constitutional input, 63 ABIs and exact recursive dependency sources |
| `evidence/` | Source inventories, validation summaries, full and invariant test logs, build sizes, ABI/storage comparisons, measured gas changes, coverage/limitations, raw Slither/triage and local rehearsal receipts/manifests/runtime checks |
| `PROVENANCE.json` | Target identity, source-inventory digest, tool/dependency versions, evidence revisions and publication status |
| Checksum files | Source/dependency, package and archive integrity checks |

Include the evidence files listed in the package README. For a Git submission, use the pinned submodules and
generate fresh evidence with the freeze script.

Historical public Sepolia records may be supplied separately and labelled with their deployed revision. The
8 September deployment's explorer results do not verify current bytecode. Local synthetic deployment receipts also
do not establish public deployment or authenticate real production controllers.

## Scope and reading order

1. [Audit Scope](Audit-Scope.md), [Architecture](Architecture.md), [Governance](Governance.md) and
   [Upgrade and Liveness](Upgrade-And-Liveness.md).
2. [Release Readiness](Release-Readiness.md) for submission checks and launch limits.
3. [Justice procedures](phase-a/JUSTICE.md) and [legal decisions](phase-a/LEGAL-DECISIONS.md) for the powers,
   authorization checks and procedures the contracts leave to operators.
4. [Static Analysis Notes](Static-Analysis-Triage.md), with the full unsuppressed report in the evidence.
5. [Constitution Alignment](Constitution-Alignment.md), the pinned PDF, applicable deployment guides and
   [Frontend Checklist](../frontend-export/INTEGRATION-CHECKLIST.md).

Review every production source and deployment path, including custody, lending, replacement and optional hooks.
With `JUSTICE_ENABLED=true`, fresh mainnet genesis installs `JusticeIdentityWriter`, `JusticeApp`, the membership
eligibility policy and the decision and compensation ledgers. Completion activates the standing writer. Review the
legacy profile separately, along with the synthetic-only Sepolia controller and the unsigned decision-packet tool.
Private proceedings, notice and evidence belong to the off-chain case process.

## Trust boundaries to challenge

- Permanent kernel/router/timelock versus constitutionally governed replaceable policies, authorities and state pointers.
- Stable registries versus process-pinned policies, snapshots and derived election rankings.
- People versus wallets, term/occupancy/appointment nonces and reassigned historical addresses.
- Legacy civic review and its pinned 3-of-5 committee, plus justice roster authority, consent, replay and expiry.
- Budget commitments versus office approvals, queued actions, vault receipts and original-writer reconciliation.
- Exact-successor asset handoff versus record/process migration and permanent consumed payout IDs.
- Lending debt/reserve arithmetic, quote execution, fixed-price economic failure, donations, policy faults, retired
  collateral bounds and debt-free/final-global-loan settlement.
- Land consent and versions, distinct verified dispute officers, company title counts and director availability.
- Prepared genesis versus confirmed-block completion and permanent bootstrap retirement.

The separate recovery ballot remains deferred. Broken governance dependencies and Senate/review cross-lock can
prevent repair. Check those limits against the project's launch assumptions.

Legacy `executeActions` batches have independently executable members. A `ModuleBundleUpdate` instead approves and
executes one indivisible plan of at most 16 eligible existing pointers. It retains delays and negative controls,
excludes Core/Senate/review replacements, and does not copy records or custody. Verify both behaviors.

For an existing company and land deployment, reconcile every active title against the per-company index, including
expired leases until closure. Reconcile company directors, parcels, dispute and encumbrance locks and pending cases.
Each registry rejects writes to an obsolete ledger. Final dissolution and last-director removal pause if the
canonical land ledger and its writer disagree.
Rebind the registry, policy, app and writer pointers as a coordinated cutover after record reconciliation. Review
transfer nonces and collect fresh app-bound signatures and dispute approvals after cutover. The dispute app requires
the block time to advance beyond module activation and binds each approval to the current module and clerk
authority. See [Land Cadastre](Land-Cadastre.md).

## Reproduce the checks

Use Forge 1.9.0, Solidity 0.8.38, Slither 0.11.6 and crytic-compile 0.4.2 with the pinned dependencies.
Dependencies are forge-std 1.17.0 and OpenZeppelin Contracts 5.7.0, at the exact revisions in `foundry.lock`.
Project Python checks require Python 3.10 or later; CI verifies Python 3.15.2. With Python 3.15, the current `ckzg`
dependency builds from source and needs a C compiler (CI uses GCC). Install the pinned analyzer in a virtual environment.
The deployable profile uses Osaka and optimizer 200. Keep normal code-size and transaction-gas limits.

In a fresh clone, set `AUDIT_COMMIT` to the full submitted commit SHA and run the clean-tree gate. The log and
analyzer environment are kept outside the checkout.

```bash
set -euo pipefail
git checkout --detach "$AUDIT_COMMIT"
git submodule update --init --recursive
audit_evidence_dir=$(mktemp -d)
python3 -m venv "$audit_evidence_dir/slither"
CC=gcc "$audit_evidence_dir/slither/bin/python" -m pip install slither-analyzer==0.11.6 crytic-compile==0.4.2
git submodule status --recursive > "$audit_evidence_dir/submodules.txt"
SLITHER_PYTHON="$audit_evidence_dir/slither/bin/python" \
  bash scripts/audit-freeze-check.sh 2>&1 | tee "$audit_evidence_dir/audit-freeze.log"
```

For an archive, verify its outer SHA-256 before extracting. From the extracted package root run
`sha256sum -c PACKAGE-SHA256.txt` and `sha256sum -c SOURCE-SHA256.txt`, then run the checks from `source/`.

```bash
set -e
bash scripts/verify-constitution-source.sh
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 -m unittest discover -s test/reference -p 'test_*.py'
forge fmt --check
forge build --sizes
forge test -vvv
forge coverage --report summary --no-match-test test_Governance_OpenAdmissionFinalizes1000CandidatesInBoundedChunks
for invariant_seed in 0x709 0x110338 0x381; do
  FOUNDRY_PROFILE=audit forge test --match-path 'test/invariant/*.t.sol' --fuzz-seed "$invariant_seed" -vvv
done
python3 scripts/check-docs.py --check-abis
python3 scripts/check-slither-baseline.py
```

The archive has no Git history, so repository-history and clean-tree checks apply to the Git submission. Archive
checksums bind its files. The reference/tooling tests and contract checks above work without Git metadata.

If analyzer entrypoints have stale installation paths, point `SLITHER_PYTHON` at the virtual environment's Python
executable. Both the baseline checker and freeze script support it:

```bash
SLITHER_PYTHON=/path/to/slither-venv/bin/python python3 scripts/check-slither-baseline.py
```

Slither runs without suppressions. Baseline counts and normalized finding identities must both match; review a
changed report before changing the baseline. Coverage excludes only the 1,000-candidate instrumentation fixture;
the optimized suite includes it and coverage runs the 100-candidate path. Raw anchor warnings and branch gaps stay
with the results. Foundry groups each contract's invariant predicates into one campaign. The audit profile uses
three seeds, each with 256 runs × 256 calls across eight test contracts. All 24 predicates must pass per seed.
Count the single-predicate result even though it has no grouped `invariant_count` field.

Run the synthetic genesis and upgrade checks from the submitted source.

```bash
JUSTICE_ENABLED=false bash scripts/rehearse-local-genesis.sh
bash scripts/rehearse-sepolia-governed.sh
bash scripts/rehearse-sepolia-foundation.sh
forge test --match-path test/scripts/DeployGenesis.t.sol --match-test test_DeploySeedsDeterministicGenesisBeforeSeal -vv
```

The shell scripts create disposable Anvil chains bound to loopback and use synthetic inputs. The first exercises
legacy mainnet genesis with a USDC test double. The Forge genesis test also exercises the optional justice profile
with synthetic rosters and a parked writer. For a justice broadcast rehearsal, supply the exact synthetic fixture
and capture receipts, manifests and read-backs separately. Public deployment requires separate authorization.

## Findings and remaining inputs

Report each finding with the target revision, preconditions, impact, exact code path, reproducing test and remediation
verification. Distinguish exploitable defects from governance trust assumptions, economic exposure and constitutional
choices. Include bytecode/gas measurements and the limits of the audit.

Production still needs verified genesis identities/stake/roles, exact asset code and controller review, independent
reviewer/office-controller attestations, approved notice/evidence procedures, liquidity/funding and operational
approval. [Recovery Decisions](Recovery-Decisions.md) records unresolved powers and the deferred repair-ballot choice.
