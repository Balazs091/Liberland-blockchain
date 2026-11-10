# Publication and external-audit preparation

The 3 November 2026 archive predates the [Solidity 0.8.38 upgrade](Toolchain-Upgrade.md) and the
[5 November source snapshot](Comprehensive-Review.md). Use [Auditor Handoff](Auditor-Handoff.md) for the current
submission procedure.

## Publication target

The archive is an unpublished source snapshot based on `dd0005c15d20754c50a0495cf6d48298b795e1a4`. GitHub
CI for that base commit covers the September source. Identify the archive by its source inventory and SHA-256
checksum.

Contract sources declare MIT through SPDX identifiers. At this snapshot the public repository had no
repository-level license notice and main branch protection was off.

## Changes made

- The mainnet configuration example includes the production plan registry and validator fields.
- The ignore rules cover private environment files, signing files and generated output. Configuration examples,
  ABIs and the pinned constitutional PDF remain part of the source.
- The repository hygiene scan reports the path and finding category for known credential patterns.
- CI and the freeze script share the deeper invariant campaign. The freeze script pins Slither and
  crytic-compile, checks the tree at completion and accepts an explicit analyzer interpreter.

## Evidence and handoff for the earlier snapshot

The archive includes project source, pinned recursive dependencies, provenance and source, package and archive
checksums. Its checksums identify the pre-upgrade source. For the current source, record the submitted commit and
tree and run `bash scripts/audit-freeze-check.sh` on a clean checkout.
