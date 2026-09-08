# Auditor Handoff

This is a local release candidate for independent human-led audit, not production authorization.
Preparation and internal triage were AI-assisted. Do not rely on internal dispositions without reproducing them.

## Exact target

The package's `PROVENANCE.json` records the commit, tree, local tag, toolchain and recursive submodule revisions.
`SOURCE-SHA256.txt` binds every packaged source/dependency file; `PACKAGE-SHA256.txt` also binds evidence.
The outer ZIP has a separate SHA-256 file. The Git commit and tag are local only; they were not pushed.

`source/` contains the entire tracked current source, tests, scripts, constitutional input, documentation and
52 generated frontend ABIs, plus the exact pinned dependency sources. No production keys, actual genesis personal
data, live deployment manifests, build caches, Git history, previous review reports or backups are included.
The source archive intentionally has no `.git`; provenance records its originating commit rather than pretending
that a new repository initialization reproduces that commit.

## Scope and reading order

1. [External Scope](Audit-Scope.md), [Architecture](Architecture.md) and [Governance](Governance.md).
2. [Internal Review](Internal-Audit-Report.md) for actual verification, corrections and retained risks.
3. [Static Triage](Static-Analysis-Triage.md); full unsuppressed JSON is in package evidence.
4. [Constitution Alignment](Constitution-Alignment.md) and the pinned PDF, independently of internal legal assumptions.
5. Both deployment scripts/manifests and [Frontend Checklist](../frontend-export/INTEGRATION-CHECKLIST.md).

Review every production source and deployment path, not only new committee, payout, Senate and lending changes.
Mocks/demo modules are in scope for separation and misuse risks, but they are not production assets or authorities.

## Trust boundaries to challenge

- Immutable router/timelock trust root versus constitutional-threshold replaceable authority, policy and state pointers.
- Canonical registries versus pinned policy snapshots and derived election-ranking state.
- Person identity versus wallets, term/occupancy/appointment nonces and historical alias reassignment.
- Civic proposer/approver versus independent fixed review committee; exact case binding, conflicts, lost keys,
  deadline edges, competing rulings, timeout, committee rotation and app migration.
- Treasury budget commitments versus office approvals, routed historical actions and independent vault execution.
- Lending scaled-debt/reserve arithmetic, token custody, current/historical stake floors, quote execution, bad debt,
  donations, policy replacement and fixed-price economic failure.
- Atomic land consent/version transitions versus company lifecycle, director loss and off-chain legal evidence.
- Prepared production genesis versus confirmed-block completion and irreversible bootstrap retirement.

No permanent superadmin, generic delegatecall executor, unrestricted referendum calldata or committee asset
custody is intended. Prove that every reachable path respects these boundaries.

## Reproduction

Use Forge 1.7.1, Solidity 0.8.36 and Slither 0.11.5 with the included pinned dependencies.
The deployable profile uses Osaka, optimizer 200; do not raise code-size or transaction-gas limits to hide failures.

For a clean Git checkout of the frozen commit, run `bash scripts/audit-freeze-check.sh`. For the ZIP's source tree,
verify checksums from the package root, then run these equivalent checks from `source/`:

```bash
bash scripts/verify-constitution-source.sh
python3 -m unittest discover -s scripts -p 'test_*.py'
forge fmt --check
forge build --sizes
forge test -vvv
forge coverage --report summary --no-match-test test_Governance_OpenAdmissionFinalizes1000CandidatesInBoundedChunks
FOUNDRY_PROFILE=audit forge test --match-path 'test/invariant/*.t.sol' --fuzz-seed 0x709 -vvv
python3 scripts/check-docs.py --check-abis
python3 scripts/check-slither-baseline.py
```

The coverage-only exclusion is deliberate and visible: instrumentation exhausts the harness budget while setting up
1,000 candidates. The optimized full test suite requires those two inherited stress instances; coverage uses the
100-candidate fixture for the same code path. Broad coverage percentages include test/script instrumentation.
Run additional seeds, property models and adversarial cases; this bounded campaign is not formal verification.

`bash scripts/rehearse-local-genesis.sh` creates an isolated temporary source copy, launches a loopback-only Anvil
on port 18560, uses a publicly known test key with mock assets, and exercises both production genesis invocations.
It does not load the source checkout's `.env` or use a public RPC. It retains synthetic evidence and stops its node
on exit. Do not fund that key with real assets. Local mock deployment is not a production-state fork.

## Expected deliverables from independent review

Report reproducible, revision-bound findings with preconditions, impact, exact code paths, regression tests and
remediation verification. Separate privileged-governance trust assumptions, constitutional choices, economic risks
and exploitable implementation defects. Include fresh bytecode/gas measurements, asset/proxy review, migration and
genesis validation, and limitations of the audit. Do not infer AI authorship from writing style or a detector label.

The owner must separately provide verified real genesis data, intended production token addresses/configuration,
reviewer/office-controller attestations, legal procedures and the frontend/operations environment. These are not
fabricated or substituted by the synthetic fixtures in this package. A fresh reviewed deployment or explicit
state/custody/process migration is necessary before any existing chain can use this revision.
