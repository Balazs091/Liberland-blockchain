# Financial reference model

[test_exposure_model.py](test_exposure_model.py) explores Phase A financial rules using Python's standard library.
It runs independently of the Solidity contracts, deployment scripts and demo.

Run from the repository root:

```sh
python3 -B test/reference/test_exposure_model.py
```

The model tracks integer lots and scans their provenance. A production algorithm still needs approved allocation
rules, gas bounds and financial-safety analysis.

## Explicit unresolved assumptions

- L07, classification and rounding: deposits are labelled Legacy or Exposed by the test scenario. Legacy conversion requires an explicit acceptance input and takes effect at conversion, not at the original deposit. The model does not implement legal terms, signatures or provider authentication.
- L07, ordinary outflows: allocate the requested outflow between Legacy and Exposed first, then among lots in each class. Largest-remainder rounding and tie order are exploratory choices. The constructor requires a tie choice.
- L07, transfers: scenarios either preserve the source class or create recipient Legacy units. Neither is asserted to be legally approved. Receipt by another person always has a new acquisition step, so a recipient's earlier cutoff cannot acquire newly received collateral retroactively.
- L08, reservations and loans: reservation receipts are independent. Two injected floor-composition examples deliberately produce different totals. Neither decides creditor priority, identifies which exact units are pledged, or implements judicial stays. Both conservatively preserve `max(protected, retained) + lien`; a compositor that erases that floor is rejected. This test assumption leaves legal priority between loans and compensation undecided.
- L08, restoration: the small fund model tests real available units and receipt replay only. It does not establish legal entitlement, recipient identity, funding source approval or a treasury backstop.

The [legal decision register](../../docs/phase-a/LEGAL-DECISIONS.md) records the remaining L07/L08 inputs.

## What the examples establish

1. **Historical scalar cap counterexample:** 100 Exposed exists at finality, is fully withdrawn, and 100 new Exposed is deposited. A cap based on current balance and historical total incorrectly allows 100. Remaining eligible old lots correctly total zero.
2. **Partial consumption:** withdrawing 40 of an old 100 and depositing 500 later leaves only 60 eligible old units.
3. **Exact ratios:** a withdrawal of 100 from 700 Legacy plus 300 Exposed consumes 70 and 30. Exhaustive small two-bucket allocations are checked independently against `fractions.Fraction`, including both tie orders.
4. **Class fragmentation:** splitting a class into several deposit lots does not change that class's share of a single withdrawal because allocation happens by class first. Rounding within a class still matters to historical cohorts.
5. **A deliberate rounding limitation:** with Legacy 1 and Exposed 3, withdrawing 2 once leaves `(0, 2)`, while withdrawing 1 twice leaves `(1, 1)` under the shown tie rule. The passing counterexample test exposes splitting bias; it does not approve it. An accumulator or another approved remainder policy needs separate analysis before production selection.
6. **Direct active-stake transfer:** a liquidation-like route consumes source lots and credits recipient lots while leaving custody unchanged. It cannot silently leave exposure only on the source, as a vault-only hook would. Debt recalculation is deliberately external to this example.
7. **Reservations and loans:** releasing one claim leaves another intact; scenario-specific composed floors limit withdrawal; existing loan protection cannot disappear through the injected floor function.
8. **Funding and replay:** an unfunded restoration receipt cannot pay; failure does not consume the receipt; successful payout cannot be replayed.
9. **Deterministic mixed sequences:** four fixed random seeds, 500 steps each, check independently tracked net external funding against aggregate balances/backing, unique positive lots, and non-increasing eligibility for already recorded historical cutoffs.

These tests do not exercise EVM gas, ERC20 callbacks, actual registry authority paths, interest, LP loss allocation, compensation priorities, permissionless execution, court finality or live chain state. A Solidity implementation would need differential tests against a legally selected reference model plus its own integration and invariant coverage.
