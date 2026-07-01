# Milestone 03

## Goal
Build legislation and referendum systems.

## Contracts
- LegislationRegistry
- ReferendumRegistry
- ReferendumPolicy
- ReferendumApp

## Hard rules
- referendum is the ordinary path for lawmaking
- no arbitrary unrestricted calldata execution
- legislation text and enactment metadata must be recorded in registries
- ordinary referendum voting has a 7 day minimum duration
- citizen-origin referenda use the standard 7 day adoption delay before enactment
- Congress-origin non-emergency referenda may choose an adoption delay up to 7 days
- Congress-origin emergency referenda may use a 3 day voting period with immediate enactment
- constitutional amendments cannot use the emergency path and require Congress origin, 50% citizen headcount support, and 65% supporting stake

## Done when
- all touched contracts compile
- tests pass
- successful referendum can queue legislation enactment, bounded policy updates, or budget-law approval without arbitrary calldata execution
