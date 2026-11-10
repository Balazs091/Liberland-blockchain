# Solidity 0.8.37 Upgrade

The 11 September 2026 comparison uses commit `ccea1facde0cedb491dc864a2f4dc00e3a04c4bd` and changes only the
compiler. The current source uses [Solidity 0.8.38](Toolchain-Upgrade.md).

## Scope and compiler changes

All 175 first-party Solidity files in that comparison, including tests and deployment scripts, pinned `pragma solidity 0.8.37;`.
That comparison used `0.8.37+commit.f401782d`, replacing `0.8.36+commit.8a079791`. Dependency revisions and their upstream
pragmas are unchanged. Both comparisons use Forge 1.7.1, Osaka, optimizer enabled with 200 runs and no via-IR.
The official Linux binary manifest gives this SHA-256.
`5de843c2c93563cc66425c99a4fb13fdbf32b4c4ae07469480faaf126e14404a`.

The release fixes compiler defects and changes the default optimizer. The project uses the legacy pipeline and
keeps experimental modes disabled. [Official release notes](https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/)

| Change | Relevance and decision |
| --- | --- |
| Memory byte-element deletion fix | The legacy pipeline previously cleared too much memory for `delete b[i]` on `bytes memory`. The 148-file production import closure, including dependencies, contains no such operation. [Compiler advisory](https://www.soliditylang.org/blog/2026/09/10/memory-byte-array-element-delete-clears-whole-word-bug/) |
| Via-IR recursion, custom-error argument ordering and checked/unchecked constant fixes | These fixes apply to the via-IR pipeline. The project uses the legacy pipeline. [Release notes](https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/) |
| Packed internal-function-pointer and stale return-data optimizer fixes | No first-party state function-pointer declarations or `returndatacopy` operations were found. Current production code generation is unchanged in the metadata-free comparison below. [Release notes](https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/) |
| Compiler data structures, block deduplication and Yul optimizations | Compare build time with identical standard-JSON inputs. [Release notes](https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/) |
| `block.slotnum` and SSA CFG stack planning | Slot access requires experimental Amsterdam support. SSA CFG is also experimental. The project uses timestamp-based constitutional deadlines and the legacy pipeline. [Release notes](https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/) |
| Signed positive custom-storage-layout expressions | The compared source uses the original storage locations. [Release notes](https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/) |

The production import closure also contains no function-type declarations. Its only explicit `returndatacopy`
operations are the three OpenZeppelin SafeERC20 failure-bubbling paths, which use the current return-data size
without an intervening call.

## Build comparison

| Metric | Solidity 0.8.36 | Solidity 0.8.37 | Difference |
| --- | ---: | ---: | ---: |
| Summed runtime size, 68 nonempty first-party production contracts/libraries | 398,219 bytes | 398,219 bytes | 0 |
| Summed creation size, same inventory | 441,267 bytes | 441,267 bytes | 0 |
| Largest production runtime: CongressCandidateRegistry | 23,904 bytes | 23,904 bytes | 0 |
| ABI and normalized storage-layout differences, 128 first-party artifacts including mocks/interfaces | — | None | 0 |

The largest runtime has 672 bytes of headroom under the 24,576-byte limit. The compiler upgrade preserves that
margin. Only the pragma warning's version text changes in the [Slither baseline](Static-Analysis-Triage.md).

## Bytecode and reproducibility

Normal bytecode hashes change because source/compiler metadata changes. In an additional diagnostic compilation,
CBOR and the metadata hash were disabled for both versions, including embedded child creation code. Creation and
runtime bytecode then matched exactly across all 121 first-party production contract/library/interface artifacts.
Keep metadata enabled for deployment. To reproduce the comparison, use separate baseline and candidate trees
with their respective compiler pins and the same dependency sources.

```bash
forge build --force --ast --extra-output storageLayout
forge test --json --fuzz-seed 0x837 --threads 2
forge test --match-path 'test/security/EfficiencyAudit.t.sol' --match-test 'test_EfficiencyAudit_Cold' -vv --json
```

Compare compiler timing with identical production standard-JSON inputs and the same filesystem conditions. The
election fixtures measure the call against persisted state and exclude transaction intrinsic gas.

## Deployment status

The [historical Sepolia addresses](Sepolia-Demo-Deployment.md) refer to the 0.8.36 deployment. Use its source
revision and compiler to reproduce the deployed bytecode. Use the frozen submission revision for a source audit.
