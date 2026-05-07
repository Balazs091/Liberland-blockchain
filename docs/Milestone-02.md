# Milestone 02

## Goal
Build identity, staking, and citizenship eligibility foundations.

## Contracts
- IdentityRegistry
- StakeRegistry
- CitizenEligibilityPolicy
- VotingPowerPolicy
- UnstakingPolicy

## Accepted defaults
- identity stores statuses, hashes, and references only
- citizen in good standing requires verified citizen, adult status, staked merits >= 5000, no active unstaking cooldown, and no final suspension flag
- political stake is non-transferable registry state

## Done when
- all touched contracts compile
- tests pass
- political rights are computed by policy, not ad hoc app logic