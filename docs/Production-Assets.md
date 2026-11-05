# Production assets

Updated 3 November 2026. Ethereum mainnet, chain ID 1, is the user-confirmed production target. No production
token or protocol deployment has been performed by this implementation work.

## Liberland Merit

[LiberlandMerit](../contracts/tokens/LiberlandMerit.sol) is a non-upgradeable ERC20 built from the pinned
OpenZeppelin implementation. Its name/symbol are Liberland Merit / LLM. Eighteen decimals preserve the current
staking, voting and lending units; changing denomination would require coordinated changes throughout the protocol.

The existing cap is 70 million whole LLM. Construction requires an explicit nonzero recipient and a positive supply
at or below that cap. All supply is created once, in the constructor. There is no subsequent issuance, burn entrypoint,
owner, proxy, blacklist, pause, transfer fee or transfer hook. An amount below the cap makes the remainder permanently
unmintable. The user will supply the actual amount, allocation custodian, distribution and stake backing before
deployment; this implementation does not allocate the supply or silently appoint the deployer as custodian.

The token carries no vote delegation/checkpoints. Existing protocol voting continues to use person-bound canonical
active stake and snapshots. A liquid token balance is not automatically political eligibility. Wallet recovery changes
protocol identity links and does not move privately held LLM or other external balances.

[DeployMerit](../scripts/DeployMerit.s.sol) deploys the asset separately from protocol genesis. It records the supplied
allocation-document hash, constructor arguments and runtime hash in a token manifest. That document reference is
provenance supplied by the operator, not an on-chain determination of lawful allocation. Verify actual broadcast
receipts and code before the address is supplied to the protocol script; a simulation can also write output files.
`cap()`/`decimals()`/`totalSupply()` checks alone cannot establish the absence of arbitrary minting in another token.

Existing rewards transfer Treasury reserves. The Treasury receives no token-issuance authority. After allocation,
the genesis operator must hold or receive the exact token backing needed by the existing staking preparation flow.

## USDC

The production lending asset is native Ethereum L1 USDC at
`0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48`, checked against
[Circle's official contract list](https://developers.circle.com/stablecoins/usdc-contract-addresses) on 3 November 2026.
The mainnet parameter manifest pins the address; an optional legacy environment value must match it. The production
preflight also requires deployed code and 6 decimals before sending a preparation transaction. It rejects another
six-decimal token rather than relying on the symbol or denomination alone.

USDC remains controlled by its issuer: use of the canonical address does not remove its upgrade, pause or blocklisting
assumptions. Review current controllers and transfer behaviour at the release fork. See
[Circle's blocklisting explanation](https://help.circle.com/support/en/understand-circle-s-stablecoin-blocklisting-process?id=support_article_view&sysparm_article=KB0011513).
An issuer refusal must revert value/accounting atomically; no alternative token is silently substituted.

## Local fixtures and release checks

Tests and the disposable local rehearsal use a clearly labelled USDC test double at the canonical address. They do
not establish real-USDC runtime parity, live controller state or mainnet transaction success. The rehearsal now uses
the actual fixed-supply LLM contract, funds the seven synthetic genesis people, completes the separate activation
stage and verifies bootstrap retirement. Sepolia continues to use its separate public-mint demo assets.

The compiler target remains Osaka. Ethereum's official roadmap records
[Fusaka/Osaka activation on 3 December 2025](https://ethereum.org/roadmap/fusaka/); this is compatible with the selected
mainnet target. Final release verification must still use the actual reviewed build, exact assets, approved genesis
records, funding and a pinned mainnet fork. No release approval is inferred from local tests.
