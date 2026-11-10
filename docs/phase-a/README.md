# Phase A design package

The [10 November justice implementation](JUSTICE.md) describes the current rules, signed effects, privacy
boundary and fresh-genesis profile. The October design uses source `dd0005c15d20754c50a0495cf6d48298b795e1a4`.
Use the dates and revisions in each record when comparing earlier proposals with the Justice profile.

## Review order

| Deliverable | Purpose |
| --- | --- |
| [Justice procedures](JUSTICE.md) | Implemented decision powers, charter and case handling |
| [Architecture](ARCHITECTURE.md) | Components, authority boundaries, alternatives, state ownership and gas constraints |
| [Authority map](AUTHORITY-MAP.md) and [CSV](AUTHORITY-MAP.csv) | Current gates versus proposed powers, including setup and original settlement exceptions |
| [Interfaces and proposals](INTERFACES.md) | Implemented token/restriction interfaces clearly separated from future typed workflow sketches |
| [Rights consumers](RIGHTS-CONSUMERS.csv) | Current readers and future permission decisions |
| [Migration plan](MIGRATION.md) | Genesis/demo/live branches, process preservation, safe partial states and custody |
| [Manifest template](MIGRATION-MANIFEST.template.json) and [schema](MIGRATION-MANIFEST.schema.json) | Review structure for a genesis or migration manifest |
| [Legal decisions](LEGAL-DECISIONS.md) | Accepted L01–L14 principles and concrete rule/evidence inputs still needed |
| [Accepted implementation decisions](IMPLEMENTATION-DECISIONS.md) | Development approval, mainnet, production assets and release requirements |
| [Financial and land design](FINANCIAL-AND-LAND-DESIGN.md) | Canonical mutation coverage, provenance, loan compatibility and supported remedies |
| [Deployment inventory](DEPLOYMENT-INVENTORY.csv) | Source declarations and selected block-pinned demo code observations; production inputs remain unverified |
| [Separate demo verification](DEMO-VERIFICATION.md) | Block-pinned Sepolia observations and their limits |
| [Acceptance](ACCEPTANCE.md) | Worked scenarios, proof obligations and implementation/activation gates |
| [Provenance](PROVENANCE.json) | Source revisions, original input hashes, production inputs and the public Sepolia snapshot |
| [Engineering progress](ENGINEERING-PROGRESS.md) | Foundation contracts, reference models and integration limits |
| [Decision-maker questions](DECISION-MAKER-QUESTIONS.md) | Rule choices and genesis inputs from the 3 November review |

The original implementation guide and presentation supplied design requirements. The legal review still needs
the controlling texts and their effective dates. For the current code, see [Architecture](../Architecture.md),
[Governance](../Governance.md) and [Audit scope](../Audit-Scope.md).

Production starts with fresh genesis on Ethereum mainnet, chain ID 1. Verify the existing demo separately.
Liberland Merit uses 18 decimals and the existing 70 million cap. Canonical Ethereum USDC uses 6 decimals.
Genesis requires official records, allocations and backing supplied for production.

## Remaining work and proposed owners

Assign a named owner for each responsibility before release.

| Work | Proposed accountable role | Evidence to return |
| --- | --- | --- |
| Verify production assets and separate demo | Operator with independent reviewer | Mainnet asset/code/controller verification and official source records; separate block-pinned demo facts |
| Supply genesis inputs | [Genesis input owner](IMPLEMENTATION-DECISIONS.md#user-decision) and independent checker | Official people/stake/appointment records, allocation/backing, applicable process rights and source evidence |
| Authenticate controlling rules | Legal lead and constitution reviewer | Full versioned text, enactment/commencement evidence, approvals for affected L items |
| Assign legal/technical decision owners | Project lead | Named owners, target dates and decision records |
| Verify interfaces and write permissions | Engineering lead and independent security reviewer | Reviewed effect schemas, caller/writer map and dependency graph |
| Verify S01–S07 | Engineering lead | Reference model, integration and scaling evidence for each affected workflow |
| Complete selected genesis plan | Operator, legal lead and engineering lead | Reconciled records, process-rights treatment, safe staged setup and manifest commitment |
| Review privacy and operations | Privacy/service owner | Approved public fields, evidence access, service proof and keeper responsibilities |

The justice profile uses the defaults recorded in [Justice procedures](JUSTICE.md). Production still needs the
adopted charter, real appointees and genesis evidence, a rehearsal with those inputs and independent review.
