# Current Documentation

This documentation describes the current protocol, its verification evidence and requirements for external review.
The pinned constitutional PDF is retained because it is an active design input, not an old code manual.

| Document | Purpose |
| --- | --- |
| [Architecture](Architecture.md) | Components, authority boundaries, custody and module evolution |
| [Governance](Governance.md) | Current identity, appeal, public repeal, election and office rules |
| [Upgrade and Liveness](Upgrade-And-Liveness.md) | Replaceability, dependency closure, supported custody/loan retirement and recovery limits |
| [Protocol Parameters](Protocol-Parameters.md) | Production/demo values and units |
| [Release Readiness](Release-Readiness.md) | Current controls, verification evidence and launch requirements |
| [Compiler Upgrade](Compiler-Upgrade.md) | Solidity 0.8.37 scope, measured comparison and deployment separation |
| [Auditor Handoff](Auditor-Handoff.md) | Exact target, trust boundaries and reproduction |
| [Static Triage](Static-Analysis-Triage.md) | Unsuppressed detector context and review questions |
| [External Audit Scope](Audit-Scope.md) | Independent review surface and limitations |
| [Constitution Alignment](Constitution-Alignment.md) | Current differences from the pinned draft |
| [Constitutional Source](constitutional-sources/README.md) | Immutable source and hash verification |
| [User Journeys](User-Journeys.md) | Citizen, officer and elected-role workflows |
| [Lending and Treasury](Lending-And-Treasury.md) | Custody, accounting, loans and retained risks |
| [Land Cadastre](Land-Cadastre.md) | Legal parties, versioned records and signing schema |
| [Mainnet Deployment](Ethereum-Mainnet-Deployment.md) | Two-stage production setup and migration gates |
| [Sepolia Deployment](Sepolia-Demo-Deployment.md) | Demo-only setup and seed behavior |
| [Frontend Checklist](../frontend-export/INTEGRATION-CHECKLIST.md) | Current integration requirements |
| [Frontend Howto](../frontend-export/FRONTEND-HOWTO.md) | Contract calls and screen behavior |

Solidity and verified deployed bytecode take precedence over prose. Source changes do not upgrade deployments.
Run `python3 scripts/check-docs.py --check-abis` from the repository root to check local links, referenced contract
functions and generated ABI parity; it does not prove that every prose statement matches protocol behavior.
