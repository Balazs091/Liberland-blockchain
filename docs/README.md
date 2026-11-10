# Current Documentation

Protocol rules, deployment guides and external audit scope. See the pinned constitutional PDF for the design source.

| Document | Purpose |
| --- | --- |
| [Comprehensive Review](Comprehensive-Review.md) | Governance safeguards and remaining risks |
| [Architecture](Architecture.md) | Components, authority boundaries, custody and module evolution |
| [Governance](Governance.md) | Current identity, appeal, public repeal, election and office rules |
| [Upgrade and Liveness](Upgrade-And-Liveness.md) | Replaceability, dependency closure, supported custody/loan retirement and recovery limits |
| [Protocol Parameters](Protocol-Parameters.md) | Production/demo values and units |
| [Predeployment Review](Predeployment-Review.md) | User journeys, upgrade checks and lock risks |
| [Governance and Recovery Review](Governance-Recovery-Review.md) | Upgrade plans, governed staging and financial exits |
| [Recovery Plan](Recovery-Plan.md) | Upgrade inventory, rollback, incident routes and reconciliation |
| [Complexity Review](Complexity-Review.md) | Contract changes and safeguards to preserve |
| [Recovery Decisions](Recovery-Decisions.md) | Forwardable unresolved authority and economic choices, with options and recommendations |
| [Release Readiness](Release-Readiness.md) | Protocol limits and launch requirements |
| [Toolchain Upgrade](Toolchain-Upgrade.md) | Solidity 0.8.38 and pinned dependencies |
| [Earlier Compiler Upgrade](Compiler-Upgrade.md) | Historical Solidity 0.8.37 comparison and deployment separation |
| [Auditor Handoff](Auditor-Handoff.md) | Exact target, trust boundaries and reproduction |
| [Publication and Audit](Publication-And-Audit.md) | Source provenance and submission requirements |
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
Run `python3 scripts/check-docs.py --check-abis` from the repository root to check links, contract references and ABI parity.

## Phase A design and implementation

The [Phase A package](phase-a/README.md) records the proposed collective citizenship, membership, recovery,
financial and land procedures, alongside implemented foundation components. It includes the authority map,
interfaces, migration plan and unresolved legal inputs. Check each component's implementation status before
treating a workflow sketch as a callable feature. The current-behavior documents above describe the shared protocol;
[Release Readiness](Release-Readiness.md) records deployment requirements.
