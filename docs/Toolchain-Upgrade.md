# Toolchain upgrade — 3 November 2026

The 3 November 2026 upgrade pins Solidity 0.8.38 and the toolchain below. The earlier archive uses Solidity 0.8.37.

## Pinned releases

| Component | Previous version | Updated version |
| --- | --- | --- |
| Solidity | 0.8.37 | [0.8.38](https://www.soliditylang.org/blog/2026/10/22/solidity-0.8.38-release-announcement/) |
| Foundry: Forge, Cast, Anvil and Chisel | 1.7.1 | [1.9.0](https://github.com/foundry-rs/foundry/releases/tag/v1.9.0) |
| Slither | 0.11.5 | [0.11.6](https://github.com/crytic/slither/releases/tag/0.11.6) |
| crytic-compile | 0.3.11 | [0.4.2](https://pypi.org/project/crytic-compile/0.4.2/) |
| OpenZeppelin Contracts | 5.6.1 | [5.7.0](https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v5.7.0) |
| forge-std | 1.16.2 | [1.17.0](https://github.com/foundry-rs/forge-std/releases/tag/v1.17.0) |
| Isolated analyzer and CI Python | CI 3.12 | 3.15.2 |

The dependency lock pins forge-std to `f3dae6e6ee381f25eb6a246f7da9b85c91a68219` and OpenZeppelin to
`cab19933c33c2ad1d4c7a84864a3601dddfd16f3`. Project sources pin `pragma solidity 0.8.38;`. Foundry compiles
the imported upstream code with the same compiler, targeting Osaka with optimizer 200 and the legacy pipeline.

CI pins checkout 7.0.1, setup-python 7.1.0 and foundry-toolchain 1.9.2 by full commit hash. GCC builds the
`ckzg` dependency where a Python 3.15 binary wheel is unavailable.

## Compatibility changes

Solidity 0.8.38 fixes stale optimizer bookkeeping that could affect generated Yul or inline assembly. The
production source changes are the pragma updates and one indentation change.

The imported OpenZeppelin update changes ERC-1271 signature encoding: dynamic signature bytes are zero-padded to a
32-byte boundary. `LandRegistryApp` is the only compared runtime whose instruction bytes change after removing
trailing compiler metadata. It decreases from 12,576 to 12,374 bytes. Other runtime hashes can still change with
compiler/source metadata, so new deployments must use freshly generated manifests and code hashes.

The [land signature cases](../test/apps/LandRegistry.t.sol) cover strict contract-wallet title transfer,
signature and digest mismatch, malformed padding and nonce preservation on failure.

The fixed EIP-712 domain names fit OpenZeppelin's new 31-byte bound. Deprecated fallback storage slots remain in
the upstream contract. The upgrade preserves the compared ABIs and storage layouts, ignoring compiler-generated
declaration identifiers.

Foundry 1.9 compatibility required small test/tooling changes:

- Rehearsal scripts accept Cast's JSON `data` envelope and the separate `completeGenesis-latest.json` receipt file.
  They retain and verify the mined receipts and exported runtime hashes.
- The new default transaction isolation makes the artificial 1,000-person election fixture exceed its aggregate
  test gas budget. Only prior identity/stake seeding is excluded from metering. All 1,000 candidate admissions and
  every finalization call remain metered. The 12-million-gas chunk assertion, maximum 32 processed candidates,
  round bound and exact winners are unchanged. No deployment gas or code-size limit is raised.
- Invariant predicates now share one campaign per test contract. Additional seeds retain the earlier aggregate
  handler-call budget.

## Verification

Reproduce the build, ABI comparison and invariant campaigns on the submitted revision using
[Auditor Handoff](Auditor-Handoff.md#reproduce-the-checks). The optimized suite runs the 1,000-candidate stress
case. The coverage profile instruments the 100-candidate equivalent. Review branch coverage and failure
assertions separately. Invariant handlers can catch expected rejections.

At this snapshot the largest runtime is 23,904 bytes, leaving 672 bytes under the runtime limit. Slither 0.11.6
removes two Medium findings for return values that the source already forwards. The other findings and their
assumptions are in [Static Analysis Notes](Static-Analysis-Triage.md).

## Evidence and handoff

Identify the submitted source and dependency revisions together. Use the earlier archive's checksum only with its
0.8.37 toolchain. See [Release Readiness](Release-Readiness.md) for the current deployment requirements.
