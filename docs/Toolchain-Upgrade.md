# Toolchain upgrade — 3 November 2026

The project now compiles with Solidity 0.8.38. This review covers the updated working source; the earlier
checksummed audit archive remains a record of the previous toolchain. A new publication or audit submission
must freeze this source and its updated dependencies.

## Pinned releases

Stable releases were checked against their official release records on 3 November 2026.

| Component | Previous version | Updated version |
| --- | --- | --- |
| Solidity | 0.8.37 | [0.8.38](https://www.soliditylang.org/blog/2026/10/22/solidity-0.8.38-release-announcement/) |
| Foundry: Forge, Cast, Anvil and Chisel | 1.7.1 | [1.9.0](https://github.com/foundry-rs/foundry/releases/tag/v1.9.0) |
| Slither | 0.11.5 | [0.11.6](https://github.com/crytic/slither/releases/tag/0.11.6) |
| crytic-compile | 0.3.11 | [0.4.2](https://pypi.org/project/crytic-compile/0.4.2/) |
| OpenZeppelin Contracts | 5.6.1 | [5.7.0](https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v5.7.0) |
| forge-std | 1.16.2 | [1.17.0](https://github.com/foundry-rs/forge-std/releases/tag/v1.17.0) |
| Isolated analyzer and CI Python | CI 3.12 | 3.15.2 |

The dependency lock records forge-std `f3dae6e6ee381f25eb6a246f7da9b85c91a68219` and OpenZeppelin
`cab19933c33c2ad1d4c7a84864a3601dddfd16f3`. Recursive submodules match those releases. Upstream source and
its compatible pragma ranges remain unchanged; the complete imported code is compiled with 0.8.38.

All 216 project Solidity files use the exact `pragma solidity 0.8.38;`: 148 contract/interface/library files,
eight deployment/parameter files and 60 test files. `foundry.toml`, contributor instructions, current deployment
guides, README files, CI and freeze checks agree on the versions. Osaka, optimizer 200 and the deployment profile's
non-IR compiler pipeline remain the comparison settings.

CI also pins checkout 7.0.1, setup-python 7.1.0 and foundry-toolchain 1.9.2 by full commit hash. Python 3.15.2,
Slither and crytic-compile were tested together; GCC builds the current `ckzg` dependency where a Python 3.15
binary wheel is unavailable. The local analyzer uses an isolated Python installation. System Python is unchanged.
The previous local Foundry binaries are backed up outside the repository.

## Compatibility changes

Solidity 0.8.38 fixes stale optimizer bookkeeping that could affect generated Yul or inline assembly in earlier
releases. No compiler workaround or new contract authority was added. First-party production source changes in this
pass are the exact pragma updates and one formatting-only indentation change.

The imported OpenZeppelin update changes ERC-1271 signature encoding: dynamic signature bytes are zero-padded to a
32-byte boundary. `LandRegistryApp` is the only compared runtime whose instruction bytes change after removing
trailing compiler metadata; it decreases from 12,576 to 12,374 bytes. Other runtime hashes can still change with
compiler/source metadata, so new deployments must use freshly generated manifests and code hashes.

Three new land tests exercise a strict contract wallet through a real title transfer, reject a changed signature
or digest without consuming the title nonce, and reject malformed padding. All 17 land tests pass. As a negative
control, restoring only the previous SignatureChecker in an isolated test copy makes both new transfer tests fail;
restoring 5.7.0 passes again. Existing EOA and contract-wallet paths remain in the complete suite.

The fixed EIP-712 domain names fit OpenZeppelin's new 31-byte bound. Deprecated fallback storage slots remain in
the upstream contract. All 148 compared artifact ABIs are unchanged, and all 73 available contract storage layouts
match after removing compiler-generated declaration identifiers. All 58 frontend ABI exports retain exact parity.

Foundry 1.9 compatibility required small test/tooling changes:

- Rehearsal scripts accept Cast's JSON `data` envelope and the separate `completeGenesis-latest.json` receipt file.
  They retain and verify the mined receipts and exported runtime hashes.
- The new default transaction isolation makes the artificial 1,000-person election fixture exceed its aggregate
  test gas budget. Only prior identity/stake seeding is excluded from metering. All 1,000 candidate admissions and
  every finalization call remain metered. The 12-million-gas chunk assertion, maximum 32 processed candidates,
  round bound and exact winners are unchanged. No deployment gas or code-size limit is raised.
- Invariant predicates now share one campaign per test contract. Results below distinguish campaign counts from
  property counts; additional seeds retain the earlier overall handler-call budget.

## Verification

Checks run in isolated copies of the working source, with pinned dependency checkouts and without loading the
repository's private environment file. Public-chain credentials are not used.

| Check | Result |
| --- | --- |
| Complete optimized suite | 795 ordinary/fuzz test instances and 24 invariant properties passed in 67 suites; no failures or skips. Foundry reports 803 results because the properties share eight campaigns. Seed `0x110338`. |
| Extended stateful campaign | All 24 properties and six supporting tests pass under each of three seeds (`0x709`, `0x110338`, `0x381`), 256 runs at depth 256: 1,572,864 handler calls, zero handler-level reverts. |
| Coverage | 818 test/property checks passed; the same one 1,000-candidate instrumentation exclusion is retained, with that stress test required in the optimized suite. |
| First-party non-mock coverage | 62 reported source files: lines 89.04% (7,011/7,874), functions 94.02% (1,116/1,187), branches 54.27% (819/1,509). No coverage-anchor warnings were emitted. |
| Static analysis | 176 contracts, 102 detectors, 464 unsuppressed reports: 6 High, 70 Medium, 292 Low and 96 Informational; 459 distinct normalized fingerprints. Every delta and all High labels reviewed; exact baseline gate passes. |
| Reference and tooling checks | 34 reference-model tests and 20 verification-tool tests pass on Python 3.15.2. |
| Local deployment rehearsals | Production genesis 85/85 receipts, isolated Sepolia foundation 18/18 and governed Sepolia 117/117: 220 successful transactions, 14 runtime-hash checks, including citizen-approved upgrade and rollback with preserved membership records. |

The largest deployed runtime remains 23,904 bytes, below the 24,576-byte limit. The largest mined rehearsal
transaction uses 6,926,942 gas, below the enforced Osaka transaction cap of 16,777,216. These are measured fixtures,
not bounds for every possible future state.

The refreshed [function coverage inventory](review/FUNCTION-COVERAGE.csv) retains 71 zero-hit instrumented functions.
Coverage is finite and its measurement changed with Foundry; changes in percentages do not establish additional
security by themselves. Expected handler rejections can be caught internally, so zero handler-level reverts does
not mean every attempted operation succeeded. The public API inventory remains compatible with the unchanged ABIs.

Slither's two removed Medium reports concern return values already forwarded by the source. They are analyzer
changes, not vulnerability fixes. The retained High labels and remaining assumptions are described in
[Static Analysis Notes](Static-Analysis-Triage.md). Python 3.14 and 3.15 scans produce identical normalized findings.

Compiler diagnostics retain four warnings about upstream deprecated `Checkpoints.at` aliases, one bounded test
shift and one mutability suggestion. Foundry reports 71 simulated-environment warnings at 54 test locations.
These were reviewed without finding a demonstrated current production defect. Compiler/optimizer changes still
require care around simulated time, block and chain mutations; the raw diagnostics are retained.

## Evidence and handoff

Raw logs, release records, verified download checksums, dependency revisions, source hashes, ABI/layout comparisons,
coverage, scanner triage, regression negative controls and local mined receipts are in the sibling workspace
directory `Toolchain-Upgrade-2026-11-03`. It contains no claim that this working candidate is a published Git commit.
The earlier `GitHub-Audit-Readiness-2026-11-03` archive has not been overwritten or relabelled.

Use the updated commands in the [README](../README.md) and [Auditor Handoff](Auditor-Handoff.md). For a commit-based
handoff, include every new source file and both updated dependency pointers, require CI for that commit, then run
the clean-tree freeze gate. No commit, push or public deployment was performed during this update.

The legal workflow, economic and governance-availability limits in [Release Readiness](Release-Readiness.md) still
apply. Passing this toolchain update is not independent audit approval or permission to activate production.
