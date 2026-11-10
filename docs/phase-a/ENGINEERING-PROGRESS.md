# Engineering progress

The 3 November 2026 foundation added the fixed-supply token, independent restriction registry and supporting
primitives. The 10 November Justice profile adds the standing writer, signed case effects and fresh-genesis
integration. [Justice procedures](JUSTICE.md)

## Current verification

Use the release checklist and reviewed Slither findings for the submitted source. The predeployment review
records fixes in Cabinet, Decision and Referendum, and covers policy and application replacement, rollback,
wallet round trips, settlement and stuck states. [Release readiness](../Release-Readiness.md),
[static triage](../Static-Analysis-Triage.md), [predeployment review](../Predeployment-Review.md)

## Sepolia foundation

The isolated Sepolia fixture deploys LiberlandMerit, IdentityRegistry, MembershipRegistry,
ConstitutionKernel and SepoliaMembershipController. Three synthetic people receive 10,000 liquid LLM each.
The operator retains 970,000 LLM of the one-million supply. Use a dedicated Sepolia credential.

The controller seeds only the three fixed identities while bootstrap is active. After bootstrap retirement,
it can apply named restriction operations only to those subjects. The fixture omits governance,
staking, USDC and legal case proceedings. The separate governed Sepolia deployment exercises upgrades
and rollback. Run the foundation verifier before deliberate token transfers change the initial allocation.
[Foundation deployment](../Sepolia-Foundation-Deployment.md), [governed Sepolia deployment](../Sepolia-Governed-Deployment.md)

## Foundation contracts

| Component | Behaviour | Integration boundary |
| --- | --- | --- |
| [LiberlandMerit](../../contracts/tokens/LiberlandMerit.sol) | Non-upgradeable ERC20, 18 decimals, existing 70 million cap; positive configured supply minted once to an explicit recipient | Actual supply, allocation recipient and backing await genesis inputs; unused cap is permanently unmintable |
| [DeployMerit](../../scripts/DeployMerit.s.sol) | Separate mainnet-only asset deployment with explicit supply/recipient/provenance inputs and constructor/runtime manifest | Release requires the actual supply, recipient and constructor/runtime evidence |
| [Mainnet preflight](../../scripts/Deploy.s.sol) | Pins native Ethereum USDC; rejects a substituted environment address, missing code or wrong decimals before broadcasts | Release requires exact LLM runtime and live USDC controller verification |
| [MembershipRegistry](../../contracts/registries/MembershipRegistry.sol) | Person-bound, independent fixed-right orders; named stays/resumptions/revocations; current expiry without cleanup; scoped revision checks | The kernel-selected writer applies orders. Separate Justice effects govern membership removal, citizenship and compensation. |
| [Kernel classifications](../../contracts/core/ConstitutionKernel.sol) | Membership registry is State; IdentityWriter is Authority | Classes govern replacement. Standing permissions come from the individual registry gates. |
| Frontend exports | Separate production token and restriction registry ABIs | The demo token has its own ABI. The frontend must select the right deployment and workflow. |

The registry tracks five rights bits. Check citizenship, membership and eligibility separately from the restriction
mask. Each order keeps its original scope, interval and receipt. Lifting one order preserves the others. An order
must already be effective and unexpired when added. A stay preserves the original end.

Recorded writes advance source revisions. Clock expiry changes direct reads without advancing those revisions.
A writer must authenticate and consume the exact decision receipt in the same transaction as the effect.
The 10 November Justice profile integrates the writer, case decisions and completed-block electorate checks.
[Justice procedures](JUSTICE.md)

## Genesis fixtures

The legacy localhost script uses the production LLM implementation, seven synthetic citizens and a USDC
test double at the canonical address. It runs protocol preparation and confirmed-block completion, then
checks setup sealing and retirement of kernel, router and office executor bootstrap. The separate Justice
fixture uses nine synthetic citizens and five appointed rosters. Mainnet release requires official genesis data,
production asset verification and a reviewed rehearsal with those inputs. [Deployment runbook](../Ethereum-Mainnet-Deployment.md),
[Justice fixture](JUSTICE.md#reproduce-the-source-level-genesis-fixture)

## Remaining inputs and integration

Record the adopted charter, named appointees, official genesis data and the operating rules for notice and
private case records. The 3 November design register retains the earlier questions and requirements for
financial provenance, loan priority and land adjudication. [Accepted decisions](IMPLEMENTATION-DECISIONS.md),
[legal register](LEGAL-DECISIONS.md), [acceptance gates](ACCEPTANCE.md)

## Foundation primitives

| Component | Implemented responsibility | Limit |
| --- | --- | --- |
| [DecisionThresholds](../../contracts/libraries/DecisionThresholds.sol) | Overflow-safe strict-majority and two-thirds arithmetic; rejects support above denominator; zero denominator never passes | Chooses no quorum, eligible set, abstention rule or legal majority |
| [DeterminationHash](../../contracts/libraries/DeterminationHash.sol) | Fixed EIP-712 struct commitment to matter, subject commitment, rules/type/effect/scoped state, issuer/writer, nonce, body epoch, roster revision, revision and stage | Caller must compose a chain/contract domain, validate typed payload and authenticate lawful approval |
| [ReceiptConsumption](../../contracts/libraries/ReceiptConsumption.sol) | Canonical one-time marker for a nonzero full domain-separated digest | Supplies no authorisation, finality or stay check; new deployments do not inherit old consumed state |
| [TimedRestrictionSet](../../contracts/libraries/TimedRestrictionSet.sol) | Indexed maximum-expiry set with arbitrary physical removal, explicit indefinite entries and cleanup-free current reads | Only already-effective OR-combined restrictions; no legal rights catalog, future activation or historical certification |

These libraries were introduced as internal components. EIP-712 binds the struct to the chain and application.
The application still needs an authenticated decision and a one-time consumption marker.
[EIP-712 standard](https://eips.ethereum.org/EIPS/eip-712)

### Models and adversarial examples

The snapshot examples cover both denominator choices, clock-only expiry, missed callbacks, same-block
writes, late catch-up and completed-block certification. The voting examples distinguish seat weight,
distinct people and wallet rotation. The financial models demonstrate why a balance at finality cannot
identify eligible funds after withdrawal and redeposit. A vault-only hook misses direct stake transfers,
and split withdrawals expose a rounding bias in the candidate allocation. The allocation and priority
rules still require a decision. [Reference models and commands](../../test/reference/README.md)

The Solidity tests use a scanning oracle for the heap and exercise arithmetic boundaries, chain and app
separation, stale and substituted effects, replay, stays and atomic rollback. [Decision primitive tests](../../test/unit/DecisionPrimitives.t.sol),
[timed restriction tests](../../test/unit/TimedRestrictionSet.t.sol)

### Gas interpretation

The cold-state benchmarks measure only the external call segment. They compare persisted sets of 8, 64
and 256 entries. The same maximum-expiry ID is the heap root and the scan-array tail. This pairs an expensive
heap removal with the cheapest scan removal. Both use the same descending-ID tie-break.

The heap makes current reads independent of entry count and spends more gas updating its index. The benchmark
prints per-operation gas for the checked-out revision. Measure histories, future activation, keeper work and
membership callbacks separately.

```bash
forge test --match-path test/unit/TimedRestrictionSet.t.sol --match-contract TimedRestrictionSetGasTest -vv
```
