# Liberland EVM contributor guide

## Mission
Build and maintain the Liberland EVM smart contract system as an auditable, constitution-aligned protocol.

## Toolchain
- Primary framework: Foundry 1.9.0
- Local node: Anvil 1.9.0
- Compiler: Solidity 0.8.38
- Dependencies: forge-std 1.17.0, OpenZeppelin Contracts 5.7.0
- Tests: Forge
- Deployment scripts: Forge scripts
- Static analysis: Slither 0.11.6, crytic-compile 0.4.2
- Additional invariant fuzzing: Echidna later

## Core principles
- No hidden super-admin
- Separate facts from rules
- Separate governance execution from application logic
- Sensitive actions must be transparent, delayed, and vetoable where applicable
- Prefer simple, explicit, auditable code over clever abstraction
- Never add arbitrary execution paths for convenience

## Working rules
1. Read `docs/Architecture.md` and `docs/Audit-Scope.md` before making architectural changes.
2. Keep each change narrowly scoped and independently reviewable.
3. Do not broaden deployment scope without updating the deployment and audit documentation.
4. Define interfaces first, then concrete contracts, then tests.
5. Keep registries stable and policies replaceable.
6. Emit events for every governance-relevant state transition.
7. Use pinned `pragma solidity 0.8.38;` consistently.
8. Use NatSpec on public and external functions.
9. Use custom errors where practical.
10. Do not use `onlyOwner` as a long-term authority model.
11. Do not add emergency backdoors.
12. Do not allow referenda to execute arbitrary unrestricted calldata.
13. If the constitution or politics are unclear, choose the more conservative interpretation and leave a `TODO-CONSTITUTIONAL-REVIEW` comment.
14. Keep recovery small and auditable. Use existing governed repair, bounded typed changes, stable ledgers and rehearsed operational procedures. A separate recovery ballot requires explicit approval.
15. Consolidate genuinely identical internal logic, while preserving independent checks at authorization, queue, execution and custody boundaries. Measure bytecode and gas tradeoffs; avoid general-purpose recovery or migration frameworks.

## Delivery standard for each task
- Scope the change clearly
- Implement the smallest correct set of contracts
- Add or update tests
- Compile all touched contracts
- Summarize assumptions and open questions
- Stop when the requested change is complete and verified

## Preferred repository layout
- `/contracts/core`
- `/contracts/registries`
- `/contracts/policies`
- `/contracts/apps`
- `/contracts/interfaces`
- `/contracts/libraries`
- `/contracts/types`
- `/contracts/mocks`
- `/test`
- `/docs`

## Non-negotiable invariants
- No arbitrary all-powerful executor exists
- No sensitive action bypasses the queue if it belongs to a queued class
- No queued action executes twice
- Senate remains bounded to negative powers
- Congress does not gain unrestricted technical control
- Treasury funds cannot leave except through the authorized path
- Registries remain the source of truth for facts

## Commands to run frequently
- `forge fmt`
- `forge build`
- `forge test -vvv`
- `forge coverage`
- `slither .`

## When blocked
Choose the simpler and safer design.
Continue implementation without inventing broad new powers.
Document the assumption and move on.
