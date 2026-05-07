# Milestone 04

## Goal
Build Congress elections.

## Contracts
- CongressCandidateRegistry
- CandidateEligibilityPolicy
- CongressElectionPolicy
- CongressElectionApp

## Accepted defaults
- top N become congressmen
- next N become runner-ups
- vacancies are filled from runner-ups
- voting weight is determined by policy and active political stake
- finalized cycles create the next deterministic recurring election cycle
- recurring election cadence is read from a replaceable Congress election policy

## Done when
- all touched contracts compile
- tests pass
- election results and replacement flows are auditable
- cadence changes remain bounded to policy replacement through governance
