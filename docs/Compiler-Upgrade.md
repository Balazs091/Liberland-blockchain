# Solidity 0.8.37 Upgrade

Measured on 11 September 2026 against commit `ccea1facde0cedb491dc864a2f4dc00e3a04c4bd`.
This is a historical compiler-only comparison, not a measurement of the subsequent application changes in the
current checkout. That isolated upgrade reduced compilation time, but did not reduce measured transaction execution
gas or contract sizes. Current verification is recorded separately in [Release Readiness](Release-Readiness.md).

## Scope and compiler changes

All 175 first-party Solidity files in that comparison, including tests and deployment scripts, pinned `pragma solidity 0.8.37;`.
Foundry uses `0.8.37+commit.f401782d`, replacing `0.8.36+commit.8a079791`. Dependency revisions and their upstream
pragmas are unchanged. Both comparisons use Forge 1.7.1, Osaka, optimizer enabled with 200 runs and no via-IR.
The downloaded Linux compiler's SHA-256 was checked against the official binary manifest:
`5de843c2c93563cc66425c99a4fb13fdbf32b4c4ae07469480faaf126e14404a`.

The release principally fixes compiler defects. Its ordinary optimizer improvements apply without changing our
configuration; experimental compiler modes are not enabled. [Official release notes](https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/).

| Change | Relevance and decision |
| --- | --- |
| Memory byte-element deletion fix | The legacy pipeline previously cleared too much memory for `delete b[i]` on `bytes memory`. The typed AST scan found no such operations in the 148-file production import closure, including dependencies. Adopt the corrected compiler; no application workaround is needed. [Compiler advisory](https://www.soliditylang.org/blog/2026/09/10/memory-byte-array-element-delete-clears-whole-word-bug/) |
| Via-IR recursion, custom-error argument ordering and checked/unchecked constant fixes | These do not affect our configured legacy pipeline. Do not switch compilation pipelines as part of this upgrade. [Release notes](https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/) |
| Packed internal-function-pointer and stale return-data optimizer fixes | No first-party state function-pointer declarations or `returndatacopy` operations were found. Current production code generation is unchanged in the metadata-free comparison below. [Release notes](https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/) |
| Compiler data structures, block deduplication and Yul optimizations | Available automatically under supported settings. Measured build-time benefit; no measured on-chain benefit here. [Release notes](https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/) |
| `block.slotnum` and SSA CFG stack planning | Slot access requires experimental Amsterdam support; SSA CFG is also experimental. Neither is adopted. Existing timestamp-based constitutional deadlines remain unchanged. [Release notes](https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/) |
| Signed positive custom-storage-layout expressions | No use in the current design; storage locations are not changed. [Release notes](https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/) |

The production import closure also contains no function-type declarations. Its only explicit `returndatacopy`
operations are the three OpenZeppelin SafeERC20 failure-bubbling paths, which use the current return-data size
without an intervening call. No stale-size pattern was identified there. Existing compiler/Forge warnings remain;
this upgrade does not claim a warning-free build or silently rewrite pinned libraries.

These checks do not identify a newly confirmed application vulnerability in the baseline. They are not a general
security audit, and the documented governance, deployment and economic limitations remain applicable.

## Measured results

| Metric | Solidity 0.8.36 | Solidity 0.8.37 | Difference |
| --- | ---: | ---: | ---: |
| Production compilation, median wall time | 9.498 s | 8.246 s | 13.2% less time |
| Summed runtime size, 68 nonempty first-party production contracts/libraries | 398,219 bytes | 398,219 bytes | 0 |
| Summed creation size, same inventory | 441,267 bytes | 441,267 bytes | 0 |
| Largest production runtime: CongressCandidateRegistry | 23,904 bytes | 23,904 bytes | 0 |
| Full optimized suite | 533 passing | 533 passing | No failures |
| Unit-test scenario gas | 493 measurements | All 493 identical | 0 |
| ABI and normalized storage-layout differences, 128 first-party artifacts including mocks/interfaces | — | None | 0 |

Compilation measurements use the same 148-file production import closure, including dependencies and excluding
mocks, tests and deployment scripts. Each native compiler ran once to warm the filesystem cache, then three
uncached compilations were measured in alternating order. Times were 9.785/9.498/9.132 seconds for 0.8.36 and
8.813/8.053/8.246 seconds for 0.8.37. Input serialization, process execution and compiler output are timed;
artifact persistence is not. This is a small local sample, not a guarantee for other machines or configurations.

Both full suites used seed `0x837` and two threads: 493 unit tests, 17 fuzz tests and 23 invariants across 46 suites.
Counts include inherited tests. Unit-test gas includes harness work and is not a user transaction fee estimate.
The separately rerun execution probes below measure the call itself against cold, persisted fixtures, excluding
transaction intrinsic gas. They are unchanged with both compilers:

| Election execution probe | 0.8.36 gas | 0.8.37 gas |
| --- | ---: | ---: |
| 32 inserts into a 960-entry heap | 4,813,154 | 4,813,154 |
| One insert into that heap | 363,554 | 363,554 |
| Revalidate 31 disqualified provisional candidates | 2,936,510 | 2,936,510 |
| Scan 31 maximum-metadata runner-ups | 1,627,332 | 1,627,332 |
| Activate 31 seats and one runner-up | 14,431,650 | 14,431,650 |

The largest runtime still has only 672 bytes of headroom under the 24,576-byte limit. The compiler upgrade does
not solve that maintenance constraint. Reducing gas or increasing headroom requires a separate, measured change.

Additional 0.8.37 checks passed: 23 extended invariants plus two non-vacuity tests (256 runs, depth 256,
seed `0x709`), formatting, 11 verification-tool tests and checks of 23 Markdown documents and 52 ABI exports.
Slither's 430 unsuppressed results were unchanged except for the pragma warning's version text; the updated
fingerprint baseline passes. See [Static Analysis Notes](Static-Analysis-Triage.md) for that exact change.

## Bytecode and reproducibility

Normal bytecode hashes change because source/compiler metadata changes. In an additional diagnostic compilation,
CBOR and the metadata hash were disabled for both versions, including embedded child creation code. Creation and
runtime bytecode then matched exactly across all 121 first-party production contract/library/interface artifacts.
Metadata remains enabled in the real deployment configuration. This diagnostic is not a replacement deployment build.

Raw evidence is in the workspace directory `Solidity-0.8.37-Upgrade-2026-09-11`, alongside the repository:
`comparison.json`, `compiler-benchmark.json`, `release-patterns.json`, standard-JSON compiler inputs/outputs, build logs, test JSON,
gas-probe logs and the comparison scripts. The baseline is an isolated archive of the commit above with the same
pinned dependency sources, not a modified checkout or a comparison against deployed state.

Core reproduction commands, run in separate baseline/candidate trees with their respective compiler pins:

```bash
forge build --force --ast --extra-output storageLayout
forge test --json --fuzz-seed 0x837 --threads 2
forge test --match-path 'test/security/EfficiencyAudit.t.sol' --match-test 'test_EfficiencyAudit_Cold' -vv --json
```

The benchmark script submits the preserved production standard-JSON inputs directly to each native compiler.
Do not compare cached `forge build` calls as a compiler-performance benchmark. See [Release Readiness](Release-Readiness.md)
for verification scope and the distinction between current checks and historical deployment/coverage evidence.

## Deployment status

Nothing was committed, pushed or deployed as part of this upgrade. Existing Sepolia addresses still refer to the
0.8.36 deployment described in [Sepolia Deployment](Sepolia-Demo-Deployment.md). Reproducing their verification
requires the deployed revision and compiler. A new audit submission must record a new frozen revision and fresh
provenance; previous source archives and verification records must not be presented as this build.
