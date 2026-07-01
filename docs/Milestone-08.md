# Milestone 08

## Goal
Add a first-pass USDC lending pool where citizens can borrow against already-active LLM stake above the retained citizenship floor.

## Contracts
- LendingTypes
- IStakeLienRegistry
- ILLMPriceOraclePolicy
- IInterestRatePolicy
- IUSDCLendingPoolApp
- StakeLienRegistry
- FixedLlmUsdcPriceOraclePolicy
- KinkedInterestRatePolicy
- USDCLendingPoolApp
- MockUSDC

## Accepted defaults
- v1 supports USDC only; additional borrow assets should be added later through explicit module registration or replacement referenda, not arbitrary calldata
- only active LLM stake above 5,000 can support borrowing
- borrowing locks the borrower's full current surplus stake above 5,000 as a lending lien
- pending unstake blocks new borrowing
- stake liens are enforced by `StakeRegistry.requiredActiveStakeFloorOf`, so direct authorized unstake calls cannot bypass lending locks
- max LTV is 25%
- liquidation threshold is 35%
- liquidation bonus is 10%
- protocol reserve factor is 15%
- borrow rates use a kinked utilization model: 2% base APR, +8% at 80% utilization, then up to +100% APR at full utilization
- v1 uses a fixed LLM/USDC oracle policy for demo and test deployments; production deployment needs a governed oracle policy with staleness and circuit-breaker rules
- liquidators receive seized LLM immediately as active staked LLM, not liquid tokens
- the liquidator must have an active wallet link, and the borrower person ID cannot liquidate itself through another wallet
- protocol reserves can be claimed by anyone, but only to the canonical treasury module
- there is no owner, pause switch, emergency withdrawal, arbitrary executor, or hidden admin path

## Still Open
- production LLM price oracle source, staleness windows, circuit breakers, and emergency market-freeze rules
- whether future risk-parameter changes should be their own referendum action class or should use module replacement for policy contracts
- whether future borrow assets should use separate isolated pools or a governed market registry
- whether liquidator eligibility should require citizenship rather than only an active wallet link
- whether partial repayments should later release part of the lien or keep the safer v1 rule of releasing liens only after full repayment
- bad-debt handling if LLM price/liquidity fails and seized stake is insufficient to cover debt plus liquidation bonus

## Done when
- all touched contracts compile
- USDC lending tests pass
- full Forge test suite passes
- coverage and Slither results are reviewed
- documentation states both the implemented behavior and unresolved financial-policy questions
