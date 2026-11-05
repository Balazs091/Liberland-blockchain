# Liberland EVM

Solidity contracts for Liberland governance, identity, staking, treasury, lending, company records and land records
on Ethereum. Governance executes typed actions after the required votes and delays. Officers carry out their
assigned identity, treasury and registration duties through separate permission checks.

## Status

The source is ready for implementation review. Mainnet launch still requires an independent audit, approved legal
procedures, verified genesis and asset inputs, and operational sign-off. A separate recovery ballot is deferred.

The [comprehensive review](docs/Comprehensive-Review.md) records the 5 November code review and publication checks.
[Toolchain Upgrade](docs/Toolchain-Upgrade.md) records the compiler and dependency update verified on 3 November.
[Complexity Review](docs/Complexity-Review.md) records the earlier internal cleanup and its measurements.
[Release Readiness](docs/Release-Readiness.md) records the audit handoff requirements and known limits.
The [Phase A package](docs/phase-a/README.md) distinguishes implemented foundations from proposed legal workflows.

## Implemented contracts

| Area | Current behavior |
| --- | --- |
| Governance | Referenda, constitutional double thresholds, adoption delays, typed enactment, Senate negative powers and public repeal petitions |
| Elections and offices | Open Congress candidacy, signed allocation ballots, resumable counting, runner-up succession, President and Cabinet procedures |
| Identity and stake | Consent-based onboarding and wallet migration, two-officer lost-key recovery, civic notices/appeals, one active wallet, backed LLM stake and historical electorate snapshots |
| Treasury and decisions | Budget envelopes, office approvals, queued payouts and bounded Congress/ministry decisions with source consent |
| Lending | Stake-backed USDC loans, indexed debt, retained stake floors, interest/reserves, liquidation and retired-book settlement |
| Land and companies | Versioned land records, stable legal parties, dual-consent transfers, atomic parcel operations, company directors, filings and share ledgers |
| Assets and new foundations | Fixed-supply `LiberlandMerit` with a 70-million cap and 18 decimals; independent membership-restriction records; immutable module-upgrade plans |

Registries hold canonical records; replaceable policies evaluate them; applications coordinate workflows. The
kernel, router and timelock form the permanent execution core. Elections and referenda retain their pinned policies
and completed-block snapshots. Elected authority follows a person's active wallet.

Related existing modules can change through one indivisible upgrade plan. A pointer change does not move records,
assets or unfinished proceedings. Governance dependency failures and Senate/review deadlocks remain documented
limits. See [Architecture](docs/Architecture.md) and [Upgrade and Liveness](docs/Upgrade-And-Liveness.md).

Membership restrictions are not yet integrated into every eligibility policy. Collective admission, discipline and
annulment procedures still need their approved rules and implementation; the staging controller uses synthetic data.

## Build and test

Use Foundry **1.9.0**, Solidity **0.8.38**, Slither **0.11.6** and crytic-compile **0.4.2**.
Dependencies are pinned to forge-std **1.17.0** and OpenZeppelin Contracts **5.7.0**.
The deployable profile targets Osaka with optimizer 200 and no via-IR. Python verification tools require Python
3.10 or later; CI uses Python 3.15.2 for Slither. Install the analyzer versions in a virtual environment.
Python 3.15 installations need a C compiler to build the current `ckzg` dependency; CI uses GCC.

After cloning:

```bash
git submodule update --init --recursive
forge fmt --check
forge build --sizes
forge test -vvv
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 -m unittest discover -s test/reference -p 'test_*.py'
python3 scripts/check-repository-hygiene.py --history
python3 scripts/check-docs.py --check-abis
python3 scripts/check-slither-baseline.py
```

The hygiene check reports locations and categories without printing credential values. Its pattern scan does not
cover every possible secret format. Slither runs without suppressions; changed counts or finding identities require
manual review before updating the baseline.

For coverage and the deeper stateful campaigns:

```bash
forge coverage --report summary --no-match-test test_Governance_OpenAdmissionFinalizes1000CandidatesInBoundedChunks
for invariant_seed in 0x709 0x110338 0x381; do
  FOUNDRY_PROFILE=audit forge test --match-path 'test/invariant/*.t.sol' --fuzz-seed "$invariant_seed" -vvv
done
```

The 1,000-candidate stress test remains in the complete optimized suite. Coverage uses the 100-candidate fixture
because instrumentation exceeds the larger fixture's test gas budget. Coverage warnings and branch gaps are recorded
with the results. Foundry groups each contract's invariant predicates into one campaign. The audit profile runs
three seeds, each at 256 runs × 256 calls across eight test contracts; all 24 predicates must pass in every seed.
This retains the earlier number of handler calls across three seeds. Compare predicate coverage and handler calls
when comparing results from different Foundry versions.

For a frozen, clean Git commit, run `bash scripts/audit-freeze-check.sh`. It checks source/history hygiene, pinned
dependencies, build/test/coverage/static results, ABI parity and working-tree cleanliness before and after the run.
If a moved virtual environment leaves stale analyzer entrypoints, set `SLITHER_PYTHON` to that environment's Python
executable for the baseline or freeze command. See [Auditor Handoff](docs/Auditor-Handoff.md).

## Deployment profiles

| Profile | Guide | Assets and authority |
| --- | --- | --- |
| Ethereum mainnet | [Production deployment](docs/Ethereum-Mainnet-Deployment.md) | Fixed-supply LLM, canonical L1 USDC, user-supplied genesis and sealed two-stage setup |
| Governed Sepolia | [Governed staging](docs/Sepolia-Governed-Deployment.md) | Fixed-supply test LLM, mock USDC, controlled synthetic voters and real governed upgrade/rollback exercises |
| Isolated Sepolia foundation | [Foundation test](docs/Sepolia-Foundation-Deployment.md) | Five-contract token/restriction fixture with three synthetic people and a test operator; no governance route |
| Original Sepolia demo | [Demo deployment](docs/Sepolia-Demo-Deployment.md) | Public-mint mock assets, seeded state and live demo onboarding |

Mainnet setup has two invocations. Preparation seeds citizens, stake, Senate, President and offices. After confirmed
seeding blocks, `completeGenesis(address)` installs the seven Congress incumbents and continuity cycle, activates
standing writers, checks readiness, seals setup and retires bootstrap authority.

Scripts write generated manifests under `deployments/`. A simulation can also write these files. Use confirmed
receipts and runtime/source checks before handing addresses to a frontend. Generated manifests are ignored by Git;
tracked examples describe the configuration shape.

The recorded public Sepolia deployment runs an earlier revision. Source edits do not change its bytecode.
[Deployment records](docs/Sepolia-Demo-Deployment.md#recorded-public-deployment) identify that historical revision.

## Repository and review guides

Contracts are under `contracts/apps`, `core`, `interfaces`, `libraries`, `policies`, `registries`, `tokens` and `types`.
`contracts/mocks` contains test/demo code. Tests, reference models and invariant handlers are under `test`.
`scripts` contains deployment and verification tools; `frontend-export` contains compiled ABI exports and examples.

Start with [Auditor Handoff](docs/Auditor-Handoff.md), [Audit Scope](docs/Audit-Scope.md) and the
[documentation index](docs/README.md). Frontend work starts with the
[integration checklist](frontend-export/INTEGRATION-CHECKLIST.md) and [frontend guide](frontend-export/FRONTEND-HOWTO.md).
The [constitutional source](docs/constitutional-sources/README.md) has its own hash check.
