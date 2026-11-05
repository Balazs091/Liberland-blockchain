# Current Documentation

This documentation describes the current protocol, its verification evidence and requirements for external review.
The pinned constitutional PDF remains an active design input.

| Document | Purpose |
| --- | --- |
| [Comprehensive Review](Comprehensive-Review.md) | 5 November internal audit, publication checks and remaining findings |
| [Architecture](Architecture.md) | Components, authority boundaries, custody and module evolution |
| [Governance](Governance.md) | Current identity, appeal, public repeal, election and office rules |
| [Upgrade and Liveness](Upgrade-And-Liveness.md) | Replaceability, dependency closure, supported custody/loan retirement and recovery limits |
| [Protocol Parameters](Protocol-Parameters.md) | Production/demo values and units |
| [Predeployment Review](Predeployment-Review.md) | User journeys, five corrected defects, upgrade evidence and retained lock risks |
| [Governance and Recovery Review](Governance-Recovery-Review.md) | Later source checks for indivisible upgrade plans, governed staging and bounded financial exits |
| [Recovery Plan](Recovery-Plan.md) | Before-upgrade inventory, rehearsed rollback, incident routes and reconciliation |
| [Complexity Review](Complexity-Review.md) | Minimal internal cleanup, retained safeguards and measured size/gas tradeoffs |
| [Recovery Decisions](Recovery-Decisions.md) | Forwardable unresolved authority and economic choices, with options and recommendations |
| [Release Readiness](Release-Readiness.md) | Current controls, verification evidence and launch requirements |
| [Toolchain Upgrade](Toolchain-Upgrade.md) | Solidity 0.8.38 compiler and dependency update verified on 3 November |
| [Earlier Compiler Upgrade](Compiler-Upgrade.md) | Historical Solidity 0.8.37 comparison and deployment separation |
| [Auditor Handoff](Auditor-Handoff.md) | Exact target, trust boundaries and reproduction |
| [Publication and Audit](Publication-And-Audit.md) | Source completeness, README cleanup, hygiene checks and the submission target |
| [Static Triage](Static-Analysis-Triage.md) | Unsuppressed detector context and review questions |
| [External Audit Scope](Audit-Scope.md) | Independent review surface and limitations |
| [Constitution Alignment](Constitution-Alignment.md) | Current differences from the pinned draft |
| [Constitutional Source](constitutional-sources/README.md) | Immutable source and hash verification |
| [User Journeys](User-Journeys.md) | Citizen, officer and elected-role workflows |
| [Lending and Treasury](Lending-And-Treasury.md) | Custody, accounting, loans and retained risks |
| [Land Cadastre](Land-Cadastre.md) | Legal parties, versioned records and signing schema |
| [Production Assets](Production-Assets.md) | Fixed-supply Liberland Merit, canonical USDC and deployment provenance |
| [Mainnet Deployment](Ethereum-Mainnet-Deployment.md) | Two-stage production setup and migration gates |
| [Sepolia Demo](Sepolia-Demo-Deployment.md) | Original full demo, public-mint test token and seeded workflows |
| [Sepolia Foundation](Sepolia-Foundation-Deployment.md) | Isolated fixed-supply token and synthetic restriction tests, without governance |
| [Governed Sepolia](Sepolia-Governed-Deployment.md) | Fresh full staging profile, real voting upgrades and retained restriction orders |
| [Frontend Checklist](../frontend-export/INTEGRATION-CHECKLIST.md) | Current integration requirements |
| [Frontend Howto](../frontend-export/FRONTEND-HOWTO.md) | Contract calls and screen behavior |

Confirm documented behavior against Solidity and verified deployed bytecode. Source changes do not upgrade deployments.
Run `python3 scripts/check-docs.py --check-abis` from the repository root to check local links, referenced contract
functions and generated ABI parity; it does not prove that every prose statement matches protocol behavior.

## Phase A design and implementation

The [Phase A package](phase-a/README.md) records the proposed collective citizenship, membership, recovery,
financial and land procedures, alongside implemented foundation components. It includes the authority map,
interfaces, migration plan and unresolved legal inputs. Check each component's implementation status before
treating a workflow sketch as a callable feature. The current-behavior documents above describe the shared protocol;
[Release Readiness](Release-Readiness.md) records deployment requirements.
