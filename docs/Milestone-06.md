# Milestone 06

## Goal
Build treasury and office systems.

## Contracts
- TreasuryVault
- TreasurySpendingPolicy
- BudgetEnvelopeRegistry
- PayoutQueue
- OfficeRegistry
- OfficePermissionPolicy
- OfficeExecutor

## Accepted defaults
- sensitive payouts are delayed and vetoable where applicable
- office roles authorize explicit action classes, not arbitrary target calls
- Congress may override executive action only through explicit lawful action classes
- budget approvals are laws and must come through successful budget-approval referenda
- office-origin direct budget approval is disabled
- budget-law execution remains subject to the referendum adoption/review delay before the budget envelope is recorded
- treasury payouts remain queued for Senate review before funds leave the vault
- Land Registry Office and Company Registry Office exist as office kinds; their registry business logic is implemented in Milestone 07

## Done when
- all touched contracts compile
- tests pass
- treasury and office permissions are bounded and auditable
