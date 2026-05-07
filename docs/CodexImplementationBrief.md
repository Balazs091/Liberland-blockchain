# Codex Implementation Brief

## Scope

Liberland EVM is a constitution-aligned governance system, not a generic DAO.

Implementation should proceed in small, auditable milestones:

1. Core privileged action lifecycle
2. Identity, stake, and citizenship foundations
3. Legislation and referenda
4. Congress elections
5. Senate and public veto
6. Treasury and office systems

## Architecture Rules

- Keep registries as stable fact stores.
- Keep policies replaceable rule evaluators.
- Keep apps as workflow entrypoints over registries and policies.
- Keep privileged execution routed through explicit action classes and the timelock.
- Do not add arbitrary target-call executors or hidden emergency powers.
- Do not use long-term `onlyOwner` authority for governance-critical state.

## Demo Rules

Demo-only bootstrap helpers may seed realistic read-state before bootstrap authority is disabled.

After demo seeding:

- registry authority slots must be switched back to production-like modules
- bootstrap authorities must be permanently disabled
- live onboarding must go through `DemoCitizenGateway`
- Congress election registry authority must end at `CongressElectionApp`

## Current Demo Focus

The Sepolia demo should be usable by external testers for:

- wallet registration and registrar citizenship confirmation
- demo `LLM` minting, staking, unstaking, and claim flow
- referendum read and vote flows
- Congress election reads and voting against the latest cycle
- Senate, public veto, treasury, and office read-state
