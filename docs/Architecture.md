# Liberland EVM Architecture

Liberland EVM is a modular governance operating system for constitution-aligned execution on the EVM.

The architecture is intentionally split into four layers:

- `contracts/core` for the privileged action lifecycle and canonical module pointers
- `contracts/registries` for stable fact storage
- `contracts/policies` for replaceable rule evaluation over registry facts
- `contracts/apps` for user-facing workflows that consume policies and registries

## Current scope

The repository implements the milestone stack through treasury and office workflows:

- core module registry, governance router, and explicit action timelock
- identity, citizenship, stake, unstaking, and voting-power rules
- referendum creation, voting, finalization, and legislation enactment
- Congress election cycles, deterministic recurring cadence, candidacy, signed weighted ballots, finalization, and runner-up replacement
- Senate cancellation and public veto flows
- treasury vault, budget envelopes, office roles, and payout queue routing

The Sepolia demo script adds seeded read-state and live onboarding helpers without keeping bootstrap authority active after deployment.

## Milestone order

1. Core privileged action lifecycle
2. Identity, stake, and citizenship foundations
3. Legislation and referenda
4. Congress elections
5. Senate and public veto
6. Treasury and office systems

## Design constraints

- sensitive actions must use deterministic action identifiers
- queued actions must not execute twice
- no unrestricted arbitrary execution path may exist
- registries remain the source of truth for facts
- policies remain replaceable without collapsing registry integrity
- election cadence changes are bounded policy module updates, not arbitrary referendum execution
