"""Exploratory oracle for timed roll eligibility and completed-block certificates.

This deliberately scans a tiny population. It specifies safety examples, not a
gas-bounded Solidity algorithm. Its citizen-and-positive-stake predicate is a
simplified scenario, not the approved roll rule (age, verification, minimum
stake, wallet links and welfare are outside this model). L02 chooses whether
restrictions affect the roll; L10 chooses existing-process semantics. Neither
choice is made by these tests, which do not prove full pinned-process continuity.
"""

from dataclasses import dataclass
import random
import unittest


class NotReady(ValueError):
    """A source gap, due transition or uncertified block prevents creation."""


@dataclass(frozen=True)
class Person:
    stake: int
    restricted_until: int = 0
    citizen: bool = True


@dataclass(frozen=True)
class Certificate:
    block: int
    timestamp: int
    epoch: int
    headcount: int
    weight: int
    eligible: frozenset[str]


class SnapshotModel:
    """Conservative explicit-certification candidate; no production integration."""

    def __init__(self, restrictions_affect_roll: bool):
        self.affects_roll = restrictions_affect_roll
        self.block = 1
        self.now = 1
        self.epoch = 1
        self.minimum_snapshot_block = 1
        self.people: dict[str, Person] = {}
        self.materialized: dict[str, tuple[bool, int]] = {}
        self.dirty: set[str] = set()
        self.expiries: dict[str, int] = {}
        self.source_revision = 0
        self.synchronized_revision = 0
        self.certificates: dict[int, Certificate] = {}

    def advance(self, timestamp: int, blocks: int = 1):
        if timestamp <= self.now or blocks < 1:
            raise ValueError("time and block must advance")
        self.now = timestamp
        self.block += blocks

    def may_vote_now(self, person: str) -> bool:
        p = self.people[person]
        return p.citizen and p.stake > 0 and p.restricted_until <= self.now

    def _roll_value(self, person: str) -> tuple[bool, int]:
        p = self.people[person]
        eligible = p.citizen and p.stake > 0
        if self.affects_roll:
            eligible = eligible and p.restricted_until <= self.now
        return eligible, p.stake if eligible else 0

    def put(self, person: str, facts: Person, callback_succeeds: bool = True):
        if facts.stake < 0 or facts.restricted_until < 0:
            raise ValueError("negative facts")
        self.people[person] = facts
        self.source_revision += 1
        self.dirty.add(person)
        self.certificates.pop(self.block, None)
        self.expiries.pop(person, None)
        if self.affects_roll and facts.restricted_until > self.now:
            self.expiries[person] = facts.restricted_until
        if callback_succeeds:
            self.materialized[person] = self._roll_value(person)
            self.dirty.remove(person)
            if not self.dirty:
                self.synchronized_revision = self.source_revision

    def due_people(self) -> list[str]:
        return sorted(p for p, expiry in self.expiries.items() if expiry <= self.now)

    def source_counters_match(self) -> bool:
        return self.source_revision == self.synchronized_revision

    def catch_up(self):
        """Late source sync never certifies a prior block retroactively."""
        if self.dirty or not self.source_counters_match():
            for person in self.dirty:
                self.materialized[person] = self._roll_value(person)
            self.dirty.clear()
            self.synchronized_revision = self.source_revision
            self.minimum_snapshot_block = self.block
            self.certificates.pop(self.block, None)

    def process_expiries(self, maximum: int) -> int:
        if maximum < 1:
            raise ValueError("positive work limit required")
        selected = self.due_people()[:maximum]
        if selected:
            self.minimum_snapshot_block = self.block
            self.certificates.pop(self.block, None)
        for person in selected:
            self.materialized[person] = self._roll_value(person)
            del self.expiries[person]
        return len(selected)

    def change_policy_epoch(self):
        self.epoch += 1
        self.dirty = set(self.people)
        self.source_revision += 1
        self.minimum_snapshot_block = self.block
        self.certificates.pop(self.block, None)

    def _ready(self):
        if self.dirty or not self.source_counters_match() or self.due_people():
            raise NotReady("source or timed transition incomplete")

    def certify(self) -> Certificate:
        self._ready()
        people = frozenset(p for p, (eligible, _) in self.materialized.items() if eligible)
        certificate = Certificate(
            self.block, self.now, self.epoch, len(people),
            sum(value[1] for value in self.materialized.values()), people,
        )
        self.certificates[self.block] = certificate
        return certificate

    def create_process(self) -> Certificate:
        self._ready()
        previous = self.block - 1
        certificate = self.certificates.get(previous)
        if (
            certificate is None
            or certificate.epoch != self.epoch
            or certificate.block < self.minimum_snapshot_block
        ):
            raise NotReady("last completed block lacks a valid certificate")
        return certificate


class SnapshotSafetyTests(unittest.TestCase):
    def test_counters_alone_miss_time_expiry(self):
        model = SnapshotModel(True)
        model.put("alice", Person(100, restricted_until=10))
        model.certify()
        model.advance(10)
        self.assertTrue(model.source_counters_match())
        self.assertTrue(model.may_vote_now("alice"))
        self.assertEqual(model.materialized["alice"], (False, 0))
        with self.assertRaises(NotReady):
            model.certify()

    def test_exact_expiry_is_effective_without_keeper(self):
        model = SnapshotModel(True)
        model.put("alice", Person(100, restricted_until=10))
        model.advance(9)
        self.assertFalse(model.may_vote_now("alice"))
        model.advance(10)
        self.assertTrue(model.may_vote_now("alice"))
        self.assertEqual(model.due_people(), ["alice"])

    def test_late_keeper_never_backdates_missing_interval(self):
        model = SnapshotModel(True)
        model.put("alice", Person(100, restricted_until=10))
        model.certify()
        model.advance(50, blocks=10)
        self.assertEqual(model.process_expiries(1), 1)
        current = model.certify()
        self.assertEqual(current.headcount, 1)
        with self.assertRaises(NotReady):
            model.create_process()
        self.assertNotIn(model.block - 1, model.certificates)
        model.advance(51)
        self.assertEqual(model.create_process(), current)

    def test_current_block_certificate_cannot_start_process(self):
        model = SnapshotModel(True)
        model.put("alice", Person(100))
        certificate = model.certify()
        with self.assertRaises(NotReady):
            model.create_process()
        model.advance(2)
        self.assertEqual(model.create_process(), certificate)

    def test_same_block_mutation_invalidates_tentative_certificate(self):
        model = SnapshotModel(True)
        model.put("alice", Person(100))
        model.certify()
        model.put("bob", Person(200))
        self.assertNotIn(model.block, model.certificates)
        model.advance(2)
        with self.assertRaises(NotReady):
            model.create_process()

    def test_recertification_in_same_block_uses_final_facts(self):
        model = SnapshotModel(True)
        model.put("alice", Person(100))
        model.certify()
        model.put("bob", Person(200))
        certificate = model.certify()
        model.advance(2)
        self.assertEqual(model.create_process().weight, 300)
        self.assertEqual(certificate.headcount, 2)

    def test_timely_current_change_preserves_valid_previous_snapshot(self):
        model = SnapshotModel(True)
        model.put("alice", Person(100))
        certificate = model.certify()
        model.advance(2)
        model.put("bob", Person(200))
        self.assertEqual(model.create_process(), certificate)
        self.assertEqual(model.create_process().eligible, frozenset({"alice"}))

    def test_failed_callback_blocks_creation_then_catchup_moves_boundary(self):
        model = SnapshotModel(True)
        model.put("alice", Person(100))
        model.certify()
        model.advance(2)
        model.put("bob", Person(200), callback_succeeds=False)
        with self.assertRaises(NotReady):
            model.create_process()
        model.catch_up()
        model.certify()
        with self.assertRaises(NotReady):
            model.create_process()
        model.advance(3)
        self.assertEqual(model.create_process().headcount, 2)

    def test_partial_expiry_processing_remains_unready(self):
        model = SnapshotModel(True)
        for person in ("alice", "bob", "carol"):
            model.put(person, Person(100, restricted_until=10))
        model.advance(10)
        self.assertEqual(model.process_expiries(2), 2)
        with self.assertRaises(NotReady):
            model.certify()
        self.assertEqual(model.process_expiries(2), 1)
        self.assertEqual(model.certify().weight, 300)

    def test_policy_epoch_rejects_old_certificate_for_new_process(self):
        model = SnapshotModel(True)
        model.put("alice", Person(100))
        old = model.certify()
        model.advance(2)
        model.change_policy_epoch()
        model.catch_up()
        model.certify()
        with self.assertRaises(NotReady):
            model.create_process()
        self.assertEqual(old.epoch, 1)  # pinned historical facts are not rewritten
        model.advance(3)
        self.assertEqual(model.create_process().epoch, 2)

    def test_empty_population_epoch_rebuild_can_finish(self):
        model = SnapshotModel(True)
        model.change_policy_epoch()
        model.catch_up()
        certificate = model.certify()
        self.assertEqual((certificate.headcount, certificate.weight), (0, 0))
        self.assertTrue(model.source_counters_match())
        model.advance(2)
        self.assertEqual(model.create_process().epoch, 2)

    def test_roll_independent_branch_does_not_change_denominator(self):
        model = SnapshotModel(False)
        model.put("alice", Person(100, restricted_until=10))
        before = model.certify()
        self.assertFalse(model.may_vote_now("alice"))
        self.assertEqual(before.headcount, 1)
        model.advance(10)
        self.assertTrue(model.may_vote_now("alice"))
        self.assertEqual(model.due_people(), [])
        self.assertEqual(model.certify().weight, before.weight)

    def test_ordinary_random_sequence_matches_full_population_oracle(self):
        for affects_roll in (False, True):
            model = SnapshotModel(affects_roll)
            rng = random.Random(20261102)
            for _ in range(300):
                model.advance(model.now + rng.randrange(1, 4))
                person = str(rng.randrange(20))
                restriction = model.now + rng.randrange(1, 20) if rng.randrange(2) else 0
                model.put(person, Person(rng.randrange(500), restriction, bool(rng.randrange(2))))
                while model.process_expiries(3):
                    pass
                certificate = model.certify()
                eligible = {
                    p for p, facts in model.people.items()
                    if facts.citizen and facts.stake > 0
                    and (not affects_roll or facts.restricted_until <= model.now)
                }
                self.assertEqual(certificate.eligible, eligible)
                self.assertEqual(certificate.weight, sum(model.people[p].stake for p in eligible))


class VotingIdentityExamples(unittest.TestCase):
    """Explicit threshold scenarios; none selects a legal threshold for deployment."""

    @staticmethod
    def supporters(seats, ballots):
        weighted_yes = sum(1 for person in seats if ballots.get(person) == "yes")
        distinct_yes = {person for person in seats if ballots.get(person) == "yes"}
        return weighted_yes, distinct_yes

    def test_weighted_seats_do_not_create_multiple_people(self):
        seats = ["alice"] * 8 + ["bob", "carol"]
        weight, people = self.supporters(seats, {"alice": "yes"})
        self.assertGreaterEqual(weight * 3, len(seats) * 2)
        self.assertEqual(len(people), 1)
        self.assertLess(len(people), 3)

    def test_wallet_replacement_keeps_one_person_ballot(self):
        wallet_to_person = {"old": "alice"}
        ballots = {wallet_to_person["old"]: "yes"}
        del wallet_to_person["old"]
        wallet_to_person["new"] = "alice"
        ballots[wallet_to_person["new"]] = "no"
        self.assertEqual(ballots, {"alice": "no"})
        self.assertNotIn("old", wallet_to_person)

    def test_abstention_does_not_change_all_eligible_majority(self):
        eligible = {"alice", "bob", "carol", "dan", "eve"}
        ballots = {"alice": "yes", "bob": "yes", "carol": "abstain"}
        yes = sum(v == "yes" for v in ballots.values())
        self.assertLessEqual(yes * 2, len(eligible))
        self.assertGreater(yes * 2, sum(v != "abstain" for v in ballots.values()))


if __name__ == "__main__":
    unittest.main()
