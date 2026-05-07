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

## Done when
- all touched contracts compile
- tests pass
- treasury and office permissions are bounded and auditable