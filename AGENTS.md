# Liberland EVM - AGENTS.md

## Mission
Build and maintain the Liberland EVM smart contract system as an auditable, constitution-aligned protocol.

This repository is a constitution-aligned governance system, not a generic DAO.

## Toolchain
- OS: Ubuntu 25.10
- Editor: VS Code
- Coding agent: official Codex extension
- Primary framework: Foundry
- Local node: Anvil
- Compiler: Solidity 0.8.36
- Tests: Forge
- Deployment scripts: Forge scripts
- Static analysis: Slither
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
7. Use pinned `pragma solidity 0.8.36;` consistently.
8. Use NatSpec on public and external functions.
9. Use custom errors where practical.
10. Do not use `onlyOwner` as a long-term authority model.
11. Do not add emergency backdoors.
12. Do not allow referenda to execute arbitrary unrestricted calldata.
13. If the constitution or politics are unclear, choose the more conservative interpretation and leave a `TODO-CONSTITUTIONAL-REVIEW` comment.

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
