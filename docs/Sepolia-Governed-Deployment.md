# Governed Sepolia staging

This profile installs the demo protocol, fixed-supply `LiberlandMerit`, `MembershipRegistry` and a replaceable
synthetic membership controller on Sepolia, chain ID `11155111`.

The isolated `DeploySepoliaFoundation` profile retires bootstrap and has no governance path. Use a fresh
deployment for governed staging.

## What this profile contains

The shared deployment builds the kernel, router, timelock, identity and stake ledgers, electorate checkpoints, referenda, Congress elections, offices, treasury, and the other demo applications. New extensions are installed before sealing bootstrap:

| Canonical pointer | Initial contract | Purpose |
| --- | --- | --- |
| `registry.membership` | `MembershipRegistry` | Stable synthetic restriction orders and their revisions |
| `authority.identity-writer` | `SepoliaGovernedMembershipController` | Typed test-only order effects submitted by current Congress members |
| `registry.module-upgrade-plan` | `ModuleUpgradePlanRegistry` | Immutable replacement plans approved through constitutional module-bundle referenda |

The LLM token is `LiberlandMerit`, with 18 decimals and a one-time synthetic allocation of 1,000,000 LLM. It has no subsequent mint or upgrade authority. Its maximum cap remains the production token's 70,000,000 LLM. The USDC contract remains the demo's **public-mint mock USDC**. These are test assets with no implied financial value.

| Initial recipient | LLM amount |
| --- | ---: |
| Staking vault, backing the four synthetic stake records | 45,000 |
| Treasury vault | 100,000 |
| Three tester wallets, each | 10,000 |
| Deployer's remaining liquid test allocation | 825,000 |

The four seeded person IDs are `bytes32(uint256(1))` through `bytes32(uint256(4))`. Their stakes are 20,000, 7,500, 12,000 and 5,500 LLM respectively. The active wallets are the deployer followed by tester 1, tester 2 and tester 3. Their two initial Congress seats belong to the deployer and tester 2; tester 1 and tester 3 are runners-up. This initial membership is an explicit synthetic genesis import matching the seeded election ballot totals. Subsequent elections use the ordinary election workflow.

All kernel, router and office-executor bootstrap authority is retired at the end. The deployer retains only the explicitly listed synthetic citizen, President, Congress, office and token-holder roles; possession of its key does not permit direct module replacement. In particular, the controller contains no immutable deployer/operator permission, fixture reseeding method or arbitrary execution method.

## Inputs before deployment

Use [sepolia-governed.env.example](../sepolia-governed.env.example) as the input template. Required operational inputs are:

1. A Sepolia RPC endpoint and a funded, testnet-only deployment key in `SEPOLIA_GOVERNED_PRIVATE_KEY`.
2. Three public tester wallet addresses, distinct from the deployer and each other. The wallets must be controlled by people who can sign test transactions.
3. Five public civic-review wallet addresses, all distinct and separate from the four office administrators. The script validates this before broadcasting.

Tester 1 is the identity-office administrator, tester 2 the land-office administrator, and tester 3 the company-office administrator and finance clerk. The deployer is the finance-office administrator. Reviewers need not be synthetic citizens to exercise the existing review fixture role. Fund tester and reviewer wallets with Sepolia ETH separately; the script does not send ETH to them.

No real person records, identity evidence or production genesis allocations belong in this profile. Private keys must stay in an ignored local file or local signing setup. Do not paste keys into messages, commit them, or package Foundry cache directories.

## Rehearse before publishing

```sh
forge test --match-path test/scripts/DeploySepoliaGoverned.t.sol -vv
bash scripts/rehearse-sepolia-governed.sh
```

The rehearsal copies source into a disposable directory and launches only a localhost chain using publicly known Anvil fixtures. It does not read the checkout's `.env`. It mines the full deployment, verifies the runtime hashes, fixed token supply and retired bootstrap, records a restriction, and replaces the controller through a real public referendum, the adoption wait and permissionless timelock execution. Tester 1 and tester 2 vote; the deployer does not vote. It then repeats the ordinary vote to restore the original controller and revokes the same order. The membership ledger and order provenance survive both changes. Local time jumps shorten elapsed wall-clock time only; contract waiting periods stay enabled.

The resulting evidence directory contains public receipts and read-back results. It is rehearsal evidence, not proof of a public Sepolia deployment.

## Public Sepolia deployment, when instructed

Load the prepared local environment without printing keys, then simulate:

```sh
forge script scripts/DeploySepoliaGoverned.s.sol:DeploySepoliaGoverned \
  --rpc-url "$SEPOLIA_RPC_URL" --slow -vv
```

Review the simulation and the actor addresses before adding `--broadcast`. The script checks the chain before reading the key. It writes a distinct `deployments/sepolia-governed.json` manifest. Confirm mined public receipts separately; a simulation-generated manifest does not prove deployment. Verify source code and record the Git revision, compiler settings, transaction hashes and observed runtime hashes before inviting testers.

Check the kernel, router and office executor return zero bootstrap authority; the token supply is 1,000,000 LLM; the staking vault holds at least the 45,000 LLM stake liability; all four active wallet links match the chosen actors; the electorate is ready; Congress has two initial members; and all three extension pointers match the manifest. Read each recorded runtime hash from actual mined contract code. Each tester must confirm access by signing a harmless read or test transaction. A newly deployed electorate must have a completed block before a fresh live proposal can take its snapshot.

## Upgrade and recovery exercises

Controller replacement keeps the existing membership and identity ledgers. Deploy a replacement with constructor `(identityRegistry, membershipRegistry)` pointing at those same ledgers, review its runtime, then propose a constitutional module-replacement referendum for `authority.identity-writer`. After successful voting and the delay, anyone may execute the queued action. The old controller immediately loses permission; the replacement can stay, resume or revoke existing orders with their current expected revision. Receipt domains include the controller address, so a fresh controller's nonce cannot collide with receipts from the prior controller.

Restoring an earlier controller requires another constitutional vote and delay. Restoring a pointer does not undo order changes made between votes. Review and correct each order through the current controller with its actual revision. Never reseed identity or membership data to make a replacement work.

For mutually dependent application and authority pointers, publish and vote on one exact atomic module plan. The bundle mechanism validates the expected old pointers and replacement runtime hashes and executes all approved pointer writes together. A pointer bundle does not migrate storage. Stateful replacement requires a separate reviewed data migration and verification plan; fixed-supply LLM is not a module and cannot be upgraded this way. See [Recovery-Plan.md](Recovery-Plan.md) for queued, expired, canceled, stale, governance and immutable-dependency failure cases.

## Scope and remaining production work

The test controller permits current Congress members to submit typed effects **only for the four fixed synthetic person IDs**. It is a staging fixture, not the proposed Commission, panel, court, or identity-verifier workflow. Membership restrictions are stored and evaluated by the membership ledger; they are not yet wired into every existing voting, candidacy, company, land or office policy. Existing demo self-registration, identity, wallet migration and authority assumptions remain test fixtures and must not be read as the new legally approved process.

Do not use this profile as a mainnet blueprint. Production still needs the legally approved workflow implementation and rights integration, production genesis, canonical mainnet USDC, production token allocation, an independent audit, and the release checks in [Release-Readiness.md](Release-Readiness.md). If governance participation becomes unavailable, this deployment offers no hidden administrator bypass; the recovery boundaries and any proposed new emergency authority must be decided explicitly.
