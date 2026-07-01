# Milestone 05

## Goal
Build Senate and public veto modules.

## Contracts
- SenateSeatRegistry
- SenatePowersPolicy
- PresidentRegistry
- SenateApp
- PublicVetoApp

## Accepted defaults
- exactly 100 seats
- equal seat weight
- inheritance-first model
- no permanent personal tie-break hardcoded
- Senate remains a negative-control body
- Senate action-cancellation and referendum-veto ballots are recorded during the applicable review window
- Senate action cancellation is finalized after the queued action review deadline and cancels the action only if the support threshold is met
- Senate referendum veto is finalized after the referendum voting deadline and cancels only non-constitutional active referenda
- Senate can open a repeal vote at any time for enacted measures below Tier 2 law
- sub-legal repeal uses a fixed 7 day Senate voting period, then finalizes and records `Senate` as repeal origin if threshold is met
- failed sub-legal repeal attempts can be retried, and support from earlier attempts is not counted in the new attempt
- President status is a registry fact, not an NFT or broad execution role
- the President can cast a proxy For/Against vote for non-voting senators on every current Senate power
- if the President does not cast a proxy vote, the proxy defaults to Against the Senate proposal and adds no support
- seats vote support-only: a seat either supports the proposal or abstains (the explicit against seat vote was removed to reduce contract size). A supporting seat is counted directly and is never covered by the President proxy; the proxy fills only silent occupied seats, bounded by the participation floor (`proxy <= direct support`)
- on-chain finalization still requires a transaction after the deadline; the EVM cannot automatically execute at the literal last second

## Done when
- all touched contracts compile
- tests pass
- veto flows and repeal flows are bounded and auditable

## Not implemented yet
- Constitutional Court review/take-up flow
- court/emergency suspension and repeal flows
