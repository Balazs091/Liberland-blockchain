"""Exploratory Phase A financial oracle, not deployable contract code.

L07 remains open: classification, transfer treatment and integer rounding.
L08 remains open: compensation/loan priority and cohort settlement rules.
This explicit-lot model deliberately favours inspectability over bounded gas.
It models units, not ERC20 transfers, mandate checks, adjudication or interest.
"""
from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction
import random
import unittest
from typing import Callable

LEGACY, EXPOSED = "Legacy", "Exposed"


def require_amount(amount: int) -> None:
    if type(amount) is not int or amount <= 0:
        raise ValueError("amount must be a positive integer number of base units")


def apportion(amount: int, balances: list[int], *, ties_first: bool) -> list[int]:
    """Hamilton allocation: floor exact fractions, then largest remainders.

    Tie order is an explicit EXPLORATORY assumption, not a settled legal rule.
    The allocation is exact in total, within one base unit of each ideal share,
    and never consumes more than a bucket owns. It is not splitting-neutral.
    """
    require_amount(amount)
    if any(type(x) is not int or x < 0 for x in balances):
        raise ValueError("invalid balances")
    total = sum(balances)
    if amount > total:
        raise ValueError("insufficient balance")
    allocation = [amount * x // total for x in balances]
    order = sorted(
        range(len(balances)),
        key=lambda i: (amount * balances[i] % total, -i if ties_first else i),
        reverse=True,
    )
    for i in order[: amount - sum(allocation)]:
        allocation[i] += 1
    return allocation


@dataclass(frozen=True)
class Assumptions:
    # Class order is Legacy, Exposed. Every constructor must choose tie order.
    ties_first: bool
    # A transfer preserves its source class or creates recipient Legacy units.
    # Neither is asserted to be the authorised L07 rule. No implicit consent.
    transfer_classification: str

    def __post_init__(self) -> None:
        if self.transfer_classification not in {"preserve", "recipient_legacy"}:
            raise ValueError("select an explicit exploratory transfer scenario")


@dataclass(frozen=True)
class Lot:
    serial: int
    amount: int
    kind: str
    origin_step: int
    acquired_step: int
    exposed_step: int | None


class LotLedger:
    """Integer lot oracle; ordinary outflows allocate by class, then by lot.

    Allocating by class first prevents fragmentation of a class into many tiny
    lots from changing that class's share of a single withdrawal. Allocation
    WITHIN a class still needs an explicit rounding rule for cutoff cohorts.
    """

    def __init__(self, assumptions: Assumptions):
        self.assumptions = assumptions
        self.clock = 0
        self.serial = 0
        self.accounts: dict[str, list[Lot]] = {}
        self.backing = 0

    def lots(self, person: str) -> list[Lot]:
        return list(self.accounts.get(person, ()))

    def balance(self, person: str, kind: str | None = None) -> int:
        return sum(x.amount for x in self.lots(person) if kind is None or x.kind == kind)

    def eligible_at_cutoff(self, person: str, cutoff: int) -> int:
        """Still-present Exposed units both acquired and exposed by cutoff."""
        if cutoff < 0 or cutoff > self.clock:
            raise ValueError("cutoff must refer to an existing model step")
        return sum(
            x.amount for x in self.lots(person)
            if x.kind == EXPOSED and x.acquired_step <= cutoff
            and x.exposed_step is not None and x.exposed_step <= cutoff
        )

    def _new(self, amount: int, kind: str, origin: int,
             acquired: int, exposed: int | None) -> Lot:
        self.serial += 1
        return Lot(self.serial, amount, kind, origin, acquired, exposed)

    def deposit(self, person: str, amount: int, kind: str) -> None:
        require_amount(amount)
        if not person or kind not in {LEGACY, EXPOSED}:
            raise ValueError("invalid person/class")
        self.clock += 1
        self.accounts.setdefault(person, []).append(
            self._new(amount, kind, self.clock, self.clock,
                      self.clock if kind == EXPOSED else None)
        )
        self.backing += amount

    def accept_terms_for_all_legacy(self, person: str, *, accepted: bool) -> None:
        """Scenario only: conversion begins NOW, not at the original deposit."""
        if not accepted or self.balance(person, LEGACY) == 0:
            raise ValueError("explicit acceptance and Legacy units required")
        self.clock += 1
        self.accounts[person] = [
            Lot(x.serial, x.amount, EXPOSED, x.origin_step, x.acquired_step, self.clock)
            if x.kind == LEGACY else x for x in self.lots(person)
        ]

    def _consume(self, person: str, amount: int, required_floor: int) -> list[Lot]:
        require_amount(amount)
        if type(required_floor) is not int or required_floor < 0:
            raise ValueError("invalid required floor")
        if self.balance(person) - amount < required_floor:
            raise ValueError("outflow breaches balance/protection")
        split = apportion(
            amount, [self.balance(person, LEGACY), self.balance(person, EXPOSED)],
            ties_first=self.assumptions.ties_first,
        )
        consumed: list[Lot] = []
        remaining: list[Lot] = []
        for kind, share in zip((LEGACY, EXPOSED), split):
            lots = [x for x in self.lots(person) if x.kind == kind]
            per_lot = apportion(share, [x.amount for x in lots],
                                ties_first=self.assumptions.ties_first) if share else [0] * len(lots)
            for lot, take in zip(lots, per_lot):
                if take:
                    consumed.append(Lot(lot.serial, take, lot.kind, lot.origin_step,
                                        lot.acquired_step, lot.exposed_step))
                if lot.amount > take:
                    remaining.append(Lot(lot.serial, lot.amount - take, lot.kind,
                                         lot.origin_step, lot.acquired_step, lot.exposed_step))
        self.accounts[person] = sorted(remaining, key=lambda x: x.serial)
        return consumed

    def withdraw(self, person: str, amount: int, *, required_floor: int) -> None:
        self._consume(person, amount, required_floor)
        self.clock += 1
        self.backing -= amount

    def transfer_active(self, source: str, recipient: str, amount: int,
                        *, required_floor: int) -> None:
        """Direct ledger transfer, including a liquidation-like route: no vault cash flow.

        Debt recalculation/priority is outside this oracle. The caller supplies
        the required post-settlement floor from its explicit scenario.
        Recipient acquisition is always new, even if origin/class is preserved.
        """
        if not recipient or source == recipient:
            raise ValueError("distinct recipient required")
        parts = self._consume(source, amount, required_floor)
        self.clock += 1
        for lot in parts:
            kind = lot.kind if self.assumptions.transfer_classification == "preserve" else LEGACY
            self.accounts.setdefault(recipient, []).append(
                self._new(lot.amount, kind, lot.origin_step, self.clock,
                          lot.exposed_step if kind == EXPOSED else None)
            )


@dataclass(frozen=True)
class LoanProtection:
    protected: int
    retained: int
    lien: int

    def __post_init__(self) -> None:
        if any(type(x) is not int or x < 0 for x in (self.protected, self.retained, self.lien)):
            raise ValueError("invalid existing loan protection")

    def existing_floor(self) -> int:
        return max(self.protected, self.retained) + self.lien


# Input/output shape only. No function here determines which creditor is senior.
ReservationComposer = Callable[[LoanProtection, list[int]], int]


def additive_scenario(p: LoanProtection, amounts: list[int]) -> int:
    return max(p.protected + sum(amounts), p.retained) + p.lien


def overlapping_scenario(p: LoanProtection, amounts: list[int]) -> int:
    return max(p.protected, p.retained, sum(amounts)) + p.lien


class Reservations:
    """Independent receipts; injected composition is NOT an approved priority rule."""

    def __init__(self):
        self.orders: dict[str, int] = {}
        self.seen: set[str] = set()

    def reserve(self, order: str, amount: int) -> None:
        require_amount(amount)
        if not order or order in self.seen:
            raise ValueError("missing or replayed reservation ID")
        self.orders[order] = amount
        self.seen.add(order)

    def release(self, order: str) -> None:
        if order not in self.orders:
            raise ValueError("no active reservation")
        del self.orders[order]

    def required_floor(self, protection: LoanProtection, compose: ReservationComposer) -> int:
        floor = compose(protection, list(self.orders.values()))
        if type(floor) is not int or floor < protection.existing_floor():
            raise ValueError("scenario erased existing loan protection")
        return floor


class FundedRestoration:
    """Cash/receipt conservation only; no authority, legal entitlement or priority model."""

    def __init__(self):
        self.cash = 0
        self.receipts: dict[str, int] = {}

    def fund(self, amount: int) -> None:
        require_amount(amount)
        self.cash += amount

    def pay(self, decision: str, amount: int) -> None:
        require_amount(amount)
        if not decision or decision in self.receipts or amount > self.cash:
            raise ValueError("unfunded or replayed payout")
        self.cash -= amount
        self.receipts[decision] = amount


class ExposureReferenceTests(unittest.TestCase):
    def ledger(self, ties_first: bool = True, transfer: str = "preserve") -> LotLedger:
        return LotLedger(Assumptions(ties_first, transfer))

    def test_scalar_cap_reuses_later_deposit_but_lots_exclude_it(self):
        m = self.ledger()
        m.deposit("A", 100, EXPOSED)
        cutoff, historical_stake = m.clock, m.balance("A")
        m.withdraw("A", 100, required_floor=0)
        m.deposit("A", 100, EXPOSED)
        scalar_cap = min(100, m.balance("A", EXPOSED), historical_stake)
        self.assertEqual(scalar_cap, 100)  # Counterexample to the proposed scalar cap.
        self.assertEqual(m.eligible_at_cutoff("A", cutoff), 0)

    def test_partial_old_consumption_is_not_replenished(self):
        m = self.ledger()
        m.deposit("A", 100, EXPOSED)
        cutoff = m.clock
        m.withdraw("A", 40, required_floor=0)
        m.deposit("A", 500, EXPOSED)
        self.assertEqual(m.eligible_at_cutoff("A", cutoff), 60)
        self.assertEqual(m.balance("A"), 560)

    def test_terms_acceptance_does_not_backdate_exposure(self):
        m = self.ledger()
        m.deposit("A", 100, LEGACY)
        cutoff = m.clock
        m.accept_terms_for_all_legacy("A", accepted=True)
        self.assertEqual(m.eligible_at_cutoff("A", cutoff), 0)
        self.assertEqual(m.eligible_at_cutoff("A", m.clock), 100)

    def test_converting_requires_explicit_acceptance(self):
        m = self.ledger()
        m.deposit("A", 100, LEGACY)
        before = (m.clock, m.lots("A"), m.backing)
        with self.assertRaises(ValueError):
            m.accept_terms_for_all_legacy("A", accepted=False)
        self.assertEqual((m.clock, m.lots("A"), m.backing), before)

    def test_exact_legacy_exposed_proportion(self):
        m = self.ledger()
        m.deposit("A", 700, LEGACY)
        m.deposit("A", 300, EXPOSED)
        m.withdraw("A", 100, required_floor=0)
        self.assertEqual((m.balance("A", LEGACY), m.balance("A", EXPOSED)), (630, 270))
        self.assertEqual(m.backing, 900)

    def test_tie_rounding_is_an_explicit_scenario(self):
        self.assertEqual(apportion(1, [1, 1], ties_first=True), [1, 0])
        self.assertEqual(apportion(1, [1, 1], ties_first=False), [0, 1])

    def test_fraction_oracle_checks_all_small_allocations(self):
        for a in range(11):
            for b in range(11):
                for amount in range(1, a + b + 1):
                    for ties in (True, False):
                        result = apportion(amount, [a, b], ties_first=ties)
                        self.assertEqual(sum(result), amount)
                        for got, balance in zip(result, (a, b)):
                            self.assertLessEqual(got, balance)
                            self.assertGreaterEqual(got, 0)
                            self.assertLess(abs(Fraction(amount * balance, a + b) - got), 1)

    def test_class_allocation_does_not_depend_on_deposit_fragmentation(self):
        whole, fragmented = self.ledger(), self.ledger()
        whole.deposit("A", 2, LEGACY)
        fragmented.deposit("A", 1, LEGACY)
        fragmented.deposit("A", 1, LEGACY)
        for m in (whole, fragmented):
            m.deposit("A", 2, EXPOSED)
            m.withdraw("A", 1, required_floor=0)
        self.assertEqual(whole.balance("A", LEGACY), fragmented.balance("A", LEGACY))
        self.assertEqual(whole.balance("A", EXPOSED), fragmented.balance("A", EXPOSED))

    def test_split_withdrawal_bias_remains_an_explicit_unsolved_rounding_issue(self):
        single, split = self.ledger(), self.ledger()
        for m in (single, split):
            m.deposit("A", 1, LEGACY)
            m.deposit("A", 3, EXPOSED)
        single.withdraw("A", 2, required_floor=0)
        split.withdraw("A", 1, required_floor=0)
        split.withdraw("A", 1, required_floor=0)
        self.assertEqual(single.backing, split.backing)
        self.assertEqual((single.balance("A", LEGACY), single.balance("A", EXPOSED)), (0, 2))
        self.assertEqual((split.balance("A", LEGACY), split.balance("A", EXPOSED)), (1, 1))
        # A successful test exposes this candidate's limitation; it does not endorse that bias.

    def test_direct_liquidation_like_transfer_updates_both_people_without_cash_exit(self):
        m = self.ledger()
        m.deposit("borrower", 80, LEGACY)
        m.deposit("borrower", 120, EXPOSED)
        before_cutoff, backing = m.clock, m.backing
        m.transfer_active("borrower", "liquidator", 50, required_floor=100)
        self.assertEqual((m.balance("borrower", LEGACY), m.balance("borrower", EXPOSED)), (60, 90))
        self.assertEqual((m.balance("liquidator", LEGACY), m.balance("liquidator", EXPOSED)), (20, 30))
        self.assertEqual(m.backing, backing)
        self.assertEqual(m.eligible_at_cutoff("borrower", before_cutoff), 90)
        self.assertEqual(m.eligible_at_cutoff("liquidator", before_cutoff), 0)

    def test_transfer_classification_is_not_silently_chosen(self):
        m = self.ledger(transfer="recipient_legacy")
        m.deposit("A", 100, EXPOSED)
        m.transfer_active("A", "B", 40, required_floor=0)
        self.assertEqual((m.balance("A", EXPOSED), m.balance("B", LEGACY)), (60, 40))
        self.assertEqual(m.balance("B", EXPOSED), 0)

    def test_floor_breach_and_bad_inputs_leave_ledger_unchanged(self):
        m = self.ledger()
        m.deposit("A", 100, EXPOSED)
        before = (m.clock, m.lots("A"), m.backing)
        for amount, floor in ((51, 50), (101, 0), (0, 0), (-1, 0), (1, -1)):
            with self.assertRaises(ValueError):
                m.withdraw("A", amount, required_floor=floor)
            self.assertEqual((m.clock, m.lots("A"), m.backing), before)

    def test_independent_reservation_release_preserves_other_receipts(self):
        r, p = Reservations(), LoanProtection(10, 20, 30)
        r.reserve("claim-1", 40)
        r.reserve("claim-2", 15)
        self.assertEqual(r.required_floor(p, additive_scenario), 95)
        self.assertEqual(r.required_floor(p, overlapping_scenario), 85)
        r.release("claim-1")
        self.assertEqual(r.orders, {"claim-2": 15})
        self.assertEqual(r.required_floor(p, additive_scenario), 55)
        self.assertEqual(r.required_floor(p, overlapping_scenario), 50)

    def test_floor_composer_cannot_erase_existing_lien_or_retained_floor(self):
        r, p = Reservations(), LoanProtection(5, 50, 30)
        r.reserve("claim", 2)
        for scenario in (additive_scenario, overlapping_scenario):
            self.assertGreaterEqual(r.required_floor(p, scenario), 80)
        with self.assertRaises(ValueError):
            r.required_floor(p, lambda protection, amounts: 0)
        # This is conservative preservation for the model, not a ruling on L08 priority.

    def test_released_reservation_id_cannot_be_replayed(self):
        r = Reservations()
        r.reserve("claim", 20)
        r.release("claim")
        with self.assertRaises(ValueError):
            r.reserve("claim", 200)
        self.assertEqual(r.orders, {})

    def test_reservation_and_loan_composition_controls_withdrawal(self):
        m, r, p = self.ledger(), Reservations(), LoanProtection(10, 20, 30)
        m.deposit("A", 100, EXPOSED)
        r.reserve("claim", 25)
        floor = r.required_floor(p, additive_scenario)
        self.assertEqual(floor, 65)
        with self.assertRaises(ValueError):
            m.withdraw("A", 36, required_floor=floor)
        m.withdraw("A", 35, required_floor=floor)
        self.assertEqual(m.balance("A"), 65)
        r.release("claim")
        self.assertEqual(r.required_floor(p, additive_scenario), 50)

    def test_restoration_cannot_pay_unfunded_or_replayed_receipts(self):
        f = FundedRestoration()
        with self.assertRaises(ValueError):
            f.pay("decision", 100)
        self.assertEqual(f.receipts, {})
        f.fund(120)
        f.pay("decision", 100)
        with self.assertRaises(ValueError):
            f.pay("decision", 10)
        self.assertEqual(f.cash, 20)
        self.assertEqual(f.cash + sum(f.receipts.values()), 120)

    def test_seeded_sequences_conserve_backing_and_do_not_replenish_old_cohorts(self):
        for seed in (7, 91, 2026, 0xA07):
            rng, m = random.Random(seed), self.ledger()
            expected_backing = 0
            snapshots: dict[tuple[str, int], int] = {}
            for step in range(500):
                person = rng.choice(("A", "B", "C"))
                choice = rng.randrange(4)
                if choice == 0 or m.balance(person) == 0:
                    amount = rng.randint(1, 200)
                    m.deposit(person, amount, rng.choice((LEGACY, EXPOSED)))
                    expected_backing += amount
                elif choice == 1:
                    amount = rng.randint(1, m.balance(person))
                    m.withdraw(person, amount, required_floor=0)
                    expected_backing -= amount
                elif choice == 2:
                    recipient = rng.choice([x for x in ("A", "B", "C") if x != person])
                    m.transfer_active(person, recipient, rng.randint(1, m.balance(person)), required_floor=0)
                elif m.balance(person, LEGACY):
                    m.accept_terms_for_all_legacy(person, accepted=True)
                self.assertEqual(m.backing, expected_backing, (seed, step))
                self.assertEqual(sum(m.balance(p) for p in ("A", "B", "C")), expected_backing)
                all_lots = [lot for p in ("A", "B", "C") for lot in m.lots(p)]
                self.assertEqual(len({x.serial for x in all_lots}), len(all_lots))
                self.assertTrue(all(x.amount > 0 and x.origin_step <= x.acquired_step <= m.clock for x in all_lots))
                for key, previous in list(snapshots.items()):
                    now = m.eligible_at_cutoff(*key)
                    self.assertLessEqual(now, previous, (seed, step, key))
                    snapshots[key] = now
                if step % 40 == 0:
                    for p in ("A", "B", "C"):
                        snapshots[p, m.clock] = m.eligible_at_cutoff(p, m.clock)


if __name__ == "__main__":
    unittest.main(verbosity=2)
