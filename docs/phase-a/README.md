# Phase A design package

Prepared 29 October 2026 against source `dd0005c15d20754c50a0495cf6d48298b795e1a4`.

The [10 November justice implementation](JUSTICE.md) records the rules, signed effects, privacy boundary and
fresh-genesis profile selected for this round. The remaining documents in this folder capture the earlier design
and decision history. Their outstanding questions and validation results refer to the dates and source they name.

## Review order

| Deliverable | Purpose |
| --- | --- |
| [Justice procedures](JUSTICE.md) | Implemented decision powers, charter and case handling |
| [Architecture](ARCHITECTURE.md) | Components, authority boundaries, alternatives, state ownership and gas constraints |
| [Authority map](AUTHORITY-MAP.md) and [CSV](AUTHORITY-MAP.csv) | Current gates versus proposed powers, including setup and original settlement exceptions |
| [Interfaces and proposals](INTERFACES.md) | Implemented token/restriction interfaces clearly separated from future typed workflow sketches |
| [Rights consumers](RIGHTS-CONSUMERS.csv) | Current readers and future permission decisions |
| [Migration plan](MIGRATION.md) | Genesis/demo/live branches, process preservation, safe partial states and custody |
| [Manifest template](MIGRATION-MANIFEST.template.json) and [schema](MIGRATION-MANIFEST.schema.json) | Draft review structure with execution explicitly unauthorised |
| [Legal decisions](LEGAL-DECISIONS.md) | Accepted L01–L14 principles and concrete rule/evidence inputs still needed |
| [Accepted implementation decisions](IMPLEMENTATION-DECISIONS.md) | User acceptance, mainnet/assets/token direction and remaining boundaries |
| [Financial and land design](FINANCIAL-AND-LAND-DESIGN.md) | Canonical mutation coverage, provenance, loan compatibility and supported remedies |
| [Deployment inventory](DEPLOYMENT-INVENTORY.csv) | Source declarations and selected block-pinned demo code observations; production inputs remain unverified |
| [Separate demo verification](DEMO-VERIFICATION.md) | Read-only Sepolia observations and their limits; no production input approval |
| [Acceptance](ACCEPTANCE.md) | Worked scenarios, proof obligations and implementation/activation gates |
| [Provenance](PROVENANCE.json) | Source/input hashes and distinction between prior checks and this documentation pass |
| [Engineering progress](ENGINEERING-PROGRESS.md) | Implemented contracts and models, validation and limits |
| [Remaining inputs to forward](DECISION-MAKER-QUESTIONS.md) | Concrete missing rule choices and genesis inputs; accepted recommendations are not reopened |

The original implementation guide and presentation supplied design requirements; their legal authority still needs
authentication. The October 29 implementation analysis supplied the architecture findings. [Architecture](../Architecture.md),
[Governance](../Governance.md) and [Audit scope](../Audit-Scope.md) describe the existing code. This folder distinguishes
implemented foundation components from future workflow proposals.

The user selected a fresh production deployment, with separate verification of the existing demo. The migration plan
therefore uses genesis as the planning branch. Ethereum mainnet, chain ID 1, is confirmed. Liberland Merit has 18
decimals and the existing 70 million cap; USDC is the canonical Ethereum token with 6 decimals. The user will supply
genesis records, allocations and backing. Their values and legal import facts remain pending; genesis does not
automatically import demo state or parameters.

## Remaining work and proposed owners

Roles below are proposed responsibilities. No individual has been appointed by these documents.

| Work | Proposed accountable role | Evidence to return |
| --- | --- | --- |
| Verify production assets and separate demo | Operator with independent reviewer | Mainnet asset/code/controller verification and official source records; separate block-pinned demo facts |
| Supply genesis inputs | User, with an independent checker to be named | Official people/stake/appointment records, allocation/backing, applicable process rights and source evidence |
| Authenticate controlling rules | Legal lead and constitution reviewer | Full versioned text, enactment/commencement evidence, approvals for affected L items |
| Assign legal/technical decision owners | Project lead | Named owners, target dates and decision records |
| Finalise interfaces and authority closure | Engineering lead and independent security reviewer | Reviewed effect schemas, caller/writer map and dependency graph |
| Prove hard algorithms | Engineering lead | Review the new models/primitives and complete S01–S07 integration and growth evidence for affected slices |
| Complete selected genesis plan | Operator, legal lead and engineering lead | Reconciled records, process-rights treatment, safe staged setup and manifest commitment |
| Review privacy and operations | Privacy/service owner | Approved public fields, evidence access, service proof and keeper responsibilities |

The justice profile uses the defaults recorded in [Justice procedures](JUSTICE.md). Production still needs the
adopted charter, real appointees and genesis evidence, a rehearsal with those inputs and independent review.
