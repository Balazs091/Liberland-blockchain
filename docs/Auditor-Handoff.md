# Auditor handoff

Audit the implemented contracts and deployment paths against the exact submitted source revision. The
Phase A justice profile adds a separate charter, roster, signed decision and compensation scope.
See [Justice procedures](phase-a/JUSTICE.md) for the current implementation and private case workflow.
[Comprehensive Review](Comprehensive-Review.md) records the 5 November candidate and verification;
[Release Readiness](Release-Readiness.md) lists the retained controls and launch requirements.

## Identify the target

For a Git submission, record the complete commit and tree, toolchain and recursive submodule revisions. Include all
new contracts, tests and scripts before creating that commit. A tracked-only archive of an earlier commit can omit
untracked implementation files.

For a source archive, identify the immutable artifact by its SHA-256 and complete source inventory. Its
`PROVENANCE.json` must distinguish a published commit from a working-tree snapshot based on an older commit.
A working-tree snapshot must record its base commit, state that no candidate commit has been published, and bind
all included project and dependency files. Do not label the base commit as the revision containing the changes.

Use `SOURCE-SHA256.txt` for source/dependency contents, `PACKAGE-SHA256.txt` for the full package and a separate
checksum for the outer archive. Verify those files before reproducing the checks. The source archive excludes Git
metadata, local settings, production keys, real genesis personal data, credential caches and generated build output.

The export manifest contains **63 frontend ABIs**, including the 10 November justice profile. The source uses Solidity 0.8.38 and the dependencies
recorded in [Toolchain Upgrade](Toolchain-Upgrade.md), following the internal changes in
[Complexity Review](Complexity-Review.md). Earlier audit archives and public Sepolia records refer to different
source and toolchain revisions.

## Package contents

| Path | Contents |
| --- | --- |
| `source/` | Complete contracts, interfaces, tests, scripts/configuration, docs, constitutional input, 58 ABIs and exact recursive dependency sources |
| `evidence/` | Source inventories, validation summaries, full and invariant test logs, build sizes, ABI/storage comparisons, measured gas changes, coverage/limitations, raw Slither/triage and local rehearsal receipts/manifests/runtime checks |
| `PROVENANCE.json` | Target identity, source-inventory digest, tool/dependency versions, evidence revisions and publication status |
| Checksum files | Source/dependency, package and archive integrity checks |

Supply every file claimed by the package notes. Local workspace paths in historical reports are context; the
submission needs the corresponding portable evidence files. The package-level README explains its relative paths.
A complete Git checkout instead uses pinned submodules and generates fresh evidence with the freeze script.

Historical public Sepolia records may be supplied separately and labelled with their deployed revision. The
8 September deployment's explorer results do not verify current bytecode. Local synthetic deployment receipts also
do not establish public deployment or authenticate real production controllers.

## Scope and reading order

1. [Audit Scope](Audit-Scope.md), [Architecture](Architecture.md), [Governance](Governance.md) and
   [Upgrade and Liveness](Upgrade-And-Liveness.md).
2. [Comprehensive Review](Comprehensive-Review.md) for current checks, and [Release Readiness](Release-Readiness.md)
   for retained limits; [Toolchain Upgrade](Toolchain-Upgrade.md) and [Complexity Review](Complexity-Review.md)
   for preceding toolchain and implementation changes.
3. [Phase A status](phase-a/README.md), [engineering progress](phase-a/ENGINEERING-PROGRESS.md) and
   [legal decisions](phase-a/LEGAL-DECISIONS.md) for implemented/proposed boundaries.
4. [Static Analysis Notes](Static-Analysis-Triage.md), with the full unsuppressed report in the evidence.
5. [Constitution Alignment](Constitution-Alignment.md), the pinned PDF, applicable deployment guides and
   [Frontend Checklist](../frontend-export/INTEGRATION-CHECKLIST.md).

Review every production source and deployment path, including custody, lending, replacement and optional hooks.
Include demo/test modules for misuse and separation risks. The membership ledger is implemented, but its official
writer, collective legal procedures and complete rights-to-policy integration remain future work. The Sepolia
Congress controller can record effects only for its fixed synthetic subjects.

## Trust boundaries to challenge

- Permanent kernel/router/timelock versus constitutionally governed replaceable policies, authorities and state pointers.
- Stable registries versus process-pinned policies, snapshots and derived election rankings.
- People versus wallets, term/occupancy/appointment nonces and reassigned historical addresses.
- Civic notice/approval versus the pinned 3-of-5 review committee, conflicts, consent, expiry and app replacement.
- Budget commitments versus office approvals, queued actions, vault receipts and original-writer reconciliation.
- Exact-successor asset handoff versus record/process migration and permanent consumed payout IDs.
- Lending debt/reserve arithmetic, quote execution, fixed-price economic failure, donations, policy faults, retired
  collateral bounds and debt-free/final-global-loan settlement.
- Land consent/versioning versus company lifecycle, director availability and off-chain evidence.
- Prepared genesis versus confirmed-block completion and permanent bootstrap retirement.

The separate recovery ballot remains deferred. Broken governance dependencies and Senate/review cross-lock can
prevent repair. Check those limits against the project's launch assumptions.

Legacy `executeActions` batches have independently executable members. A `ModuleBundleUpdate` instead approves and
executes one indivisible plan of at most 16 eligible existing pointers. It retains delays and negative controls,
excludes Core/Senate/review replacements, and does not copy records or custody. Verify both behaviors.

## Reproduce the checks

Use Forge 1.9.0, Solidity 0.8.38, Slither 0.11.6 and crytic-compile 0.4.2 with the pinned dependencies.
Dependencies are forge-std 1.17.0 and OpenZeppelin Contracts 5.7.0, at the exact revisions in `foundry.lock`.
Project Python checks require Python 3.10 or later; CI verifies Python 3.15.2. With Python 3.15, the current `ckzg`
dependency builds from source and needs a C compiler (CI uses GCC). Install the pinned analyzer in a virtual environment.
The deployable profile uses Osaka and optimizer 200. Keep normal code-size and transaction-gas limits.

For a complete clean Git checkout of the candidate commit:

```bash
git submodule update --init --recursive
bash scripts/audit-freeze-check.sh
```

For an archive, first verify its package/source checksums, then run from `source/`:

```bash
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
three seeds, each with 256 runs × 256 calls across eight test contracts. All 24 predicates must pass per seed,
including a single-predicate result that has no grouped `invariant_count` field. This retains the earlier aggregate
handler-call budget while adding seed diversity; old and new framework test totals are not directly comparable.
Run further seeds and adversarial cases as part of the independent audit.

The local rehearsal scripts create temporary source copies, use loopback-only Anvil chains and known test keys,
and stop their nodes on exit. They exercise production genesis, governed Sepolia upgrades/rollback, or the isolated
foundation profile. They do not load the checkout's local settings or use public RPCs. Production rehearsal uses a
local USDC test double and synthetic genesis; a production-state fork remains separate work.

## Findings and remaining inputs

Report each finding with the target revision, preconditions, impact, exact code path, reproducing test and remediation
verification. Distinguish exploitable defects from governance trust assumptions, economic exposure and constitutional
choices. Include bytecode/gas measurements and the limits of the audit.

Production still needs verified genesis identities/stake/roles, exact asset code and controller review, independent
reviewer/office-controller attestations, approved notice/evidence procedures, liquidity/funding and operational
approval. [Recovery Decisions](Recovery-Decisions.md) records unresolved powers and the deferred repair-ballot choice.
