# Phase A design package

Prepared 29 October 2026 against source `dd0005c15d20754c50a0495cf6d48298b795e1a4`.

Status: in progress; recommendations accepted on 3 November 2026. Contract development is authorised. Implemented
foundation components include decision primitives, reference models, Liberland Merit and the independent-restriction
registry. The registry has no official legal writer workflow or electorate integration and is absent from the
production deployment. The [governed Sepolia profile](../Sepolia-Governed-Deployment.md) exercises it with a synthetic
controller and ordinary governance upgrades. Legal rule tables, genesis records and integration/release evidence
remain outstanding. The new deployment profiles have been rehearsed on localhost. See [accepted decisions](IMPLEMENTATION-DECISIONS.md),
[engineering milestones](ENGINEERING-PROGRESS.md), the earlier [Complexity Review](../Complexity-Review.md) and the
[Toolchain Upgrade](../Toolchain-Upgrade.md) and current [comprehensive review](../Comprehensive-Review.md).

## Review order

| Deliverable | Purpose |
| --- | --- |
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

## What can be reviewed now

The proposed architecture preserves stable facts and the permanent governance core. It calls for specific legal
workflows, a sole typed identity writer and atomic consumption of approved effects. The implemented restriction
registry already stores independent orders; the official workflows and writer remain to be built. Shared internal
libraries cover common mechanics without introducing a general case interpreter or permanent migration administrator.

The complete policy dependency bundle and all permission consumers are in scope. Before integration, prove that
membership expiry and historical snapshots remain correct. Financial provenance must cover direct liquidation
transfers as well as vault entrypoints. Land remedies must preserve owner consent, current versions and unrelated
dispute locks.

The recommendations have been accepted. Their requirements to identify bodies, define deadlines, approve public fields and specify claim priority still need the actual tables and governing evidence. [Legal decisions](LEGAL-DECISIONS.md) separates those concrete inputs from accepted principles.

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

## Concrete inputs needed first

1. Which complete legal text/version and effective date govern the implementation? L01.
2. Which membership restrictions change voting permission, and do they change constitutional headcount? L02.
3. Who appoints each body, how are conflicts/shortfalls handled, and when do votes remain valid? L03/L04.
4. What constitutes notice, an effective order, finality and a stay? L05.
5. Which existing records, cases and votes must continue unchanged through cutover? L09/L10.
6. Must case subjects remain private, or only their evidence? L11.

Recovery authority, exposure/compensation priority, constitutional-office protections, special roles and land regulation have separate decisions. An unrelated later-phase blocker need not prevent an approved admission design from proceeding. Each affected feature remains blocked until its own prerequisites are satisfied.

## Completion and permission boundaries

The documents and implemented foundation do not complete Phase A. The user has authorised development and accepted the recommendations; legal powers lacking their exact governing rules remain unavailable. A Phase A review can accept an owned unresolved feature without authorising that feature's effects. Resolve the necessary legal and S gates before the relevant production integration. Deployment/activation additionally needs audited bytecode, rehearsed genesis/import, custody and operational evidence.

The earlier ten-working-day allowance is a planning estimate with dedicated engineering and timely reviewer/operator input. It does not guarantee that external legal decisions, loan run-off or confidential-architecture research finish within ten days.
