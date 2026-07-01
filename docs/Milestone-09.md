# Milestone 09

## Goal
Add bounded Congress and ministry decisions without introducing arbitrary execution.

## Contracts
- DecisionTypes
- IDecisionApp
- DecisionApp

## Accepted defaults
- Congress decisions can transfer any ERC20 from a specified source wallet to a recipient after majority support from the active Congress term.
- The proposer support is recorded automatically.
- Required Congress support is `occupiedSeatCount / 2 + 1` at preparation time.
- Congress decisions are bound to the Congress cycle that prepared them; a later Congress cannot add support or execute them.
- Source wallets must approve `DecisionApp` before token movement can execute.
- Ministry decisions can be prepared by the office admin or an active clerk.
- Ministry decisions can be executed only by the current office admin, and only while that admin is still the recorded source wallet.
- Ministry ERC20 decisions transfer from the office admin wallet to the requested recipient.
- Ministry LLM transfer-and-stake decisions pull liquid LLM from the office admin wallet, hold it in `DecisionApp`, and increase the recipient person ID's active stake.
- Clerk add/remove decisions update `OfficeRegistry` through the registered `DecisionApp` module pointer.
- `StakeRegistry.increaseStake` now accepts a narrow `STAKE_DEPOSIT_AUTHORITY` module so deposit workflows can add active stake without gaining unstake, slash, claim, recover, or transfer authority.
- There is no arbitrary calldata execution, owner backdoor, pause switch, or emergency withdrawal path.

## Still Open
- Whether offices should have a separate ministry treasury/source wallet instead of using the current office admin wallet.
- Whether Congress decisions need a formal voting period, against/abstain votes, cancellation, or expiry before the next election cycle.
- Whether Congress budget-to-ministry transfers should be linked to approved budget laws and budget-envelope accounting, or remain wallet-funded transfers.
- Whether LLM stake deposits should use a canonical staking vault that also handles future unstake claims instead of `DecisionApp` custody.
- Whether native ETH transfers should be supported, or ERC20-only should remain the rule.
- Whether Tier 3 and Tier 4 sub-legal measures need their own creator apps and metadata schema.

## Done when
- all touched contracts compile
- decision tests pass
- full Forge test suite passes
- frontend ABIs include `DecisionApp`
- documentation states the implemented decision model and remaining policy/accounting questions
