# Publication and external-audit preparation

The [5 November comprehensive review](Comprehensive-Review.md) supersedes this publication pass for the current
candidate. The following account and its archive describe the earlier source and remain unchanged evidence.

Reviewed 3 November 2026, before the Solidity 0.8.38 and dependency update. This pass covered the source verified in
[Complexity Review](Complexity-Review.md), its documentation and repository verification tools. The later
[Toolchain Upgrade](Toolchain-Upgrade.md) records the current candidate. The complete proposed legal workflows and
production activation remain separate milestones.

## Publication target

At review time, GitHub `main` and local HEAD point to `dd0005c15d20754c50a0495cf6d48298b795e1a4`. GitHub CI passed
for that September commit. The November contracts, scripts, tests and documentation remain working-tree changes,
including new untracked files. That older CI result does not test these changes.

Include all reviewed new files before making the publication commit. A `git archive HEAD` or cleanup patch alone
would omit parts of the current implementation. Commit-based audit submission needs the resulting exact commit/tree,
fresh CI and the clean-tree freeze gate. A checksummed working-tree snapshot can instead identify the complete audit
target by its inventory and archive digest, with its unpublished status stated in provenance.

The remote repository is public. Main branch protection is off, and the repository root has no LICENSE file;
contract sources declare MIT through SPDX identifiers. Required CI/review settings and a repository-level license
notice are owner decisions. This review reads remote settings without changing them.

## Changes made

- Applied the no-ai-slop editing skill to all eight project README files: root, documentation index, Phase A,
  frontend export, deployment outputs, constitutional sources and the two reference-model guides. Removed repeated
  disclaimers and feature lists, shortened tangled sentences, retained technical qualifications and added usable links.
- Corrected the four deployment profiles, fixed-supply versus demo minting, base-unit approvals, implemented versus
  proposed Phase A work and indivisible upgrade plans versus independently executable action batches.
- Updated auditor handoff/current verification figures and labelled older engineering milestones as historical.
  Added the production plan-registry/validator fields to the mainnet configuration example.
- Broadened private environment/signing/generated-output ignore rules while preserving examples, ABIs and the pinned PDF.
- Added a location/category-only publication/history pattern scan and its regression tests. It does not print matched
  credential values or prove that every possible secret format is detected.
- Aligned CI and the freeze script's deeper invariant campaign, pinned Slither/crytic-compile versions and final
  working-tree check. Added an explicit interpreter override for stale analyzer entrypoints.

## Evidence and handoff for the earlier snapshot

At this review, contract evidence comprised the source-specific 816-test suite, 24-property extended campaign, coverage, raw Slither,
ABI/storage comparisons and local deployment rehearsals in the complexity review. All 148 contract-file
hashes matched that frozen source. The publication pass also checks README links, exact ABI parity, tooling/reference tests,
published/history credential patterns, ignored-file behavior and unchanged constitutional-source bytes.

The local audit snapshot includes complete project and pinned recursive dependency source plus selected raw evidence,
provenance and source/package/archive checksums. Its extraction check builds and runs the complete contract suite
from those included files, with isolated build output and no project credentials. See [Auditor Handoff](Auditor-Handoff.md)
for archive versus Git-checkout reproduction. The snapshot's provenance identifies it as a working-tree artifact;
it does not invent a published candidate commit or a clean Git freeze result. The archive and its checksums remain
unchanged historical artifacts. They do not contain the later compiler/dependency update; prepare a new package
for that audit target rather than relabelling the existing archive.

Remaining audit attention includes 52.83% first-party branch coverage, recorded coverage-anchor warnings, 465 retained
scanner labels, governance dependency/cross-veto limits, external-asset/economic assumptions and unfinished legal
workflows. These are part of the submission scope and limitations, not evidence of production approval.

For a commit-based handoff, commit the complete reviewed tree, require CI for that commit, run
`bash scripts/audit-freeze-check.sh` on a clean checkout, and bind that commit/tree to the final audit package.
