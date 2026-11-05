# Implementation decisions — 3 November 2026

Status: **Recommendations accepted; implementation authorised; production deployment not authorised.**

## User decision

The user accepted all recommendations in [the decision-maker questions](DECISION-MAKER-QUESTIONS.md) and instructed engineering to continue implementation. The user also confirmed:

- **O01:** Ethereum mainnet, chain ID `1`, is the production network.
- **O02:** Liberland Merit has not been deployed on Ethereum. This project will implement it and choose its decimal precision. The spending/lending asset is canonical Ethereum L1 USDC.
- **O03:** The user will supply all genesis inputs. The records, allocations, appointments and supporting evidence have not yet been supplied.

The acceptance applies to the recommendations presented on 2 November. It is not limited to another round of design work: contract development is authorised. No further approval of those engineering principles is requested here. The original guide and presentation remain proposal sources; acceptance does not supply a missing statutory text, exact voting table or factual genesis record.

## Adopted implementation direction

The architecture keeps stable person-bound facts in registries, separate replaceable policies, and narrow applications for specific procedures. Citizenship, membership, individual restrictions, financial claims and honorary recognition remain separate. An exact approved effect is consumed once by its authorised writer in the same transaction as its execution. There is no generic administrator, arbitrary call executor or emergency bypass.

Membership restrictions identify their own rights, interval and decision. Staying, reversing or expiring one must preserve every unrelated restriction. Political restrictions do not automatically prevent property signing, repayment, access to a defence or other unrelated rights. Constitutional office removal follows its own competent procedure.

Appointments and ballots identify people, valid terms and mandates. Senate seat weight and distinct people are counted separately. Each procedure uses its own defined quorum, deadline, notice, finality and stay rules. Appointment shortfalls cannot be solved by an operator selecting substitutes or lowering thresholds.

Recovery requires destination consent, current link/nonce checks, independent authorised review and a defined contested hearing. Old-key objections receive an explicit process; the implementation must not silently substitute automatic override or indefinite veto. Recovery concerns protocol identity links, not external assets or private keys.

Financial accounting preserves provenance, informed acceptance of exposure terms, finality cutoffs and existing loan rights. Later deposits cannot refill an old claim's exhausted cohort. Independent reservations must prevent double pledging. Settlement and any reversal restoration require real allocated assets; restricted stake is not described as liquid compensation.

Land judgments and registry recording remain separate, ordinary sales keep dual consent, and independent dispute locks remain independent. Special offices, collective Cabinet acts and judicial decisions use specific authenticated powers. Fresh production genesis does not import demo proceedings by default or erase valid official process rights.

## Production assets

### Liberland Merit

Use `Liberland Merit` / `LLM`, **18 decimals**, retaining the repository's existing maximum of **70,000,000 LLM** (`70_000_000e18` base units). Eighteen decimals match existing stake, threshold and collateral arithmetic and avoid a protocol-wide denomination migration.

The implementation direction is a small non-upgradeable ERC20 with a constructor-funded fixed genesis supply. The genesis recipient and actual amount are explicit inputs, not invented allocations. There is no post-deployment mint authority, owner, proxy, blacklist or pause control. Any unused portion of the cap is permanently unavailable in that design. A future desire for staged issuance would require a separately specified issuance mechanism before deployment; no hidden minter is reserved for it. Voting weight remains the existing canonical stake accounting, not token-level vote checkpoints.

### USDC

Use Ethereum's canonical USDC at `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`, with 6 decimals. The address was checked against [Circle's official contract list](https://developers.circle.com/stablecoins/usdc-contract-addresses) on 3 November 2026. USDC is an external issuer-controlled asset; this project does not deploy or control its token contract. A release check must verify the actual chain, address, token behaviour and controller assumptions.

## Details still required

Some accepted recommendations expressly require a precise table, named authority or supporting text rather than selecting a value. In particular, the prior recommendations did not choose whether restrictions change constitutional headcount, the recovery second body, exact quorum/notice rules, public case fields, exposure allocation/rounding or claim priority. Acceptance therefore authorises their conservative engineering boundaries but does not choose an unstated rule.

[The legal register](LEGAL-DECISIONS.md) records accepted principles and the remaining inputs under the existing L01–L14 IDs. [The forwardable input list](DECISION-MAKER-QUESTIONS.md) asks only for those concrete details. Engineering continues on components independent of them. A dependent legal effect will not be activated by guessing a value.

## Verification boundaries

The implementation work and local tests are recorded separately in [engineering progress](ENGINEERING-PROGRESS.md). This decision record is not a test result or production readiness certificate. No public-network deployment or production activation is authorised by this record; synthetic local tests are separate. The earlier demo probe remains an observation at the recorded **29 October 2026 Sepolia block**; it is not a new mainnet or demo verification.
