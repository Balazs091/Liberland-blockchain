# Reference models

These Python examples explore Phase A rules before production integration. They use small reference models that
scan their data freely. Gas bounds, adopted legal rules and full protocol behavior require separate validation.

Run all examples from the repository root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s test/reference -p 'test_*.py' -v
```

## Snapshot and voting examples

[The snapshot model](test_snapshot_model.py) compares two scenarios: restrictions affect constitutional roll totals,
or they affect current voting permission only. [L02](../../docs/phase-a/LEGAL-DECISIONS.md) leaves that choice open.
Eligibility uses a simplified citizen-and-positive-stake predicate; age, verification, wallet links, lawful minimum
stake and welfare are outside this model.

The examples demonstrate the source-counter-only expiry gap, exact expiry boundaries, late keeper processing, same-block mutation invalidation, completed-block certification, missed callbacks, policy epochs and the empty-population rebuild case. A deterministic 600-step exploration across both branches compares certificates to a full-population oracle. An on-chain implementation still needs bounded indexing, callback budgets and its own differential/integration tests.

The certification model rejects some histories conservatively. Production integration still needs the
`IElectorateRegistry` API, keeper-failure analysis and tests that a pinned referendum/election remains operational
after replacement. Retaining an old certificate object alone does not establish that behavior. L10 and the full
consumer integration remain open.

Separate person/seat examples show why weighted Senate support and distinct people are different counts, why abstention does not change an all-eligible denominator, and how person-keyed ballots can survive a wallet replacement without creating a second person. These examples do not select a constitutional threshold or implement a production mandate system.

## Financial examples

[The exposure model](test_exposure_model.py) tracks explicit lots, acquisition and exposure steps, exact backing,
direct active-stake transfers, reservations and funded restoration scenarios. See [financial assumptions](README-finance.md)
for the L07/L08 choices and limits.

The model deliberately exhibits both the old-balance cutoff defect and a split-withdrawal rounding bias. A passing counterexample test means the defect is demonstrated; it does not approve the candidate allocation rule. This model is not selected for production.

## Solidity primitives

The independent timed-restriction scanning oracle, fuzz scenarios, threshold boundaries and synthetic
receipt-authorisation/rollback tests are in [Decision primitives](../unit/DecisionPrimitives.t.sol) and
[Timed restriction set](../unit/TimedRestrictionSet.t.sol). These authorities, writers and approval records
exist only in tests.
