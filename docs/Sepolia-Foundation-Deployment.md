# Sepolia token and membership test deployment

This profile isolates Liberland Merit and membership restrictions. A public deployment requires a funded,
dedicated Sepolia operator and a Sepolia RPC endpoint.

## What this deployment contains

| Component | Purpose in this test environment |
| --- | --- |
| `LiberlandMerit` | The actual fixed-supply token implementation, with 18 decimals and the existing 70 million cap |
| `ConstitutionKernel` | Pins this test environment's registries and controller; temporary setup authority is retired |
| `IdentityRegistry` | Holds exactly three synthetic people and their dummy wallet links |
| `MembershipRegistry` | Stores independent restrictions, stays, resumptions, revocations and expiry |
| `SepoliaMembershipController` | Explicit test-only operator for creating those synthetic restriction scenarios |

The entry point is `scripts/DeploySepoliaFoundation.s.sol:DeploySepoliaFoundation`. It requires Sepolia chain ID
`11155111`. The controller has its own Sepolia-only construction guard. The mainnet token deployment guard and the
existing [Sepolia governance demo](Sepolia-Demo-Deployment.md) remain separate.

This environment does not deploy voting, staking, lending, USDC, a citizenship admission procedure, a recovery
procedure or a disciplinary decision body. A token balance here is liquid test LLM, not active stake or proof of
political rights. Restriction scenarios test storage and execution behaviour; they do not represent real legal
decisions. Real genesis records and final legal procedure tables are not required for these synthetic fixtures.

## Synthetic people, balances and control

The token's fixed test supply is **1,000,000 LLM**. Each of three fixed dummy wallet addresses receives **10,000 LLM**;
the deployment operator retains **970,000 LLM**. No additional LLM can be minted after construction. The amount below
the 70 million cap is deliberate test configuration; unused capacity is permanently unmintable in this contract.

The dummy wallets are deterministic fixture addresses derived from public labels. No private keys are provided or
assumed for them. Their balances make test records visible; they are not ready-made signing accounts. The operator
can transfer reserve LLM to real tester-controlled addresses through the ordinary token `transfer` function.
Those transfers do not create additional synthetic identities or grant membership rights.

The controller's operator is the address derived from `SEPOLIA_FOUNDATION_PRIVATE_KEY`. It can submit only the
controller's named restriction operations for the fixed synthetic subjects. It has no arbitrary call, token mint,
custody or production legal authority. Each operation produces a distinct synthetic receipt commitment; these are
test provenance, not signed legal judgments.

Synthetic identity seeding occurs once while the kernel's temporary setup authority is active. The script then
retires that authority. The controller cannot seed again or rewrite identities after setup retirement. This isolated
kernel has no standing governance router/timelock, so it is not an upgradeable governance deployment; start a fresh
test environment when its deployment configuration must change.

## Prepare the operator environment

Use the repository's pinned Foundry/compiler configuration and a Sepolia-funded test operator. Configure
`SEPOLIA_RPC_URL` and `SEPOLIA_FOUNDATION_PRIVATE_KEY` locally using
[the example configuration](../sepolia-foundation.env.example). `.env.local` is ignored by Git. If it already exists,
merge the needed values instead of replacing it.

```bash
cp -n sepolia-foundation.env.example .env.local
# Edit .env.local locally to replace the placeholders.
set -a
source .env.local
set +a
```

The script reads the dedicated Sepolia key variable. It does not reuse the production `PRIVATE_KEY` setting.
Explorer credentials are optional for a later source-verification submission; they are not needed for the local
rehearsal or deployment simulation.

## Check and rehearse

Run from the repository root:

```bash
forge fmt --check
forge build --sizes
forge test --fuzz-seed 0x1103 -vv
python3 -m unittest discover -s test/reference -p 'test_*.py' -v
bash scripts/rehearse-sepolia-foundation.sh
```

The rehearsal runs on localhost Anvil with Sepolia's chain ID and synthetic accounts. Check module bindings,
allocation, setup retirement, independent orders and expiry before broadcasting to public Sepolia.

## Simulate against Sepolia

```bash
forge script scripts/DeploySepoliaFoundation.s.sol:DeploySepoliaFoundation \
  --rpc-url "$SEPOLIA_RPC_URL" --slow -vv
```

This command does **not** contain `--broadcast` and does not send transactions. Review its chain, operator, expected
addresses, balances and gas estimate. The script writes `deployments/sepolia-foundation.json`; simulation can write
that file too, so its existence is not proof of a public deployment. Keep the simulation output labelled as such.

## Later public deployment

After explicitly choosing to deploy to public Sepolia, run the same reviewed source with:

```bash
forge script scripts/DeploySepoliaFoundation.s.sol:DeploySepoliaFoundation \
  --rpc-url "$SEPOLIA_RPC_URL" --broadcast --slow -vv
```

This is the transaction-sending command. It has been prepared for later use; preparation does not execute it.
Retain the confirmed transaction receipts, creation arguments, source revision/build settings and runtime code
hashes with the manifest. The output is separate from both the existing demo manifest and the mainnet manifest.

For explorer source verification during that later deployment, configure `ETHERSCAN_API_KEY` locally and add
`--verify`:

```bash
forge script scripts/DeploySepoliaFoundation.s.sol:DeploySepoliaFoundation \
  --rpc-url "$SEPOLIA_RPC_URL" --broadcast --slow --verify -vv
```

Forge reads the explorer credential from the environment. This command still sends deployment transactions; do not
run it merely to inspect the prepared source. Retain the verification results and check the explorer's exact-match
status for each contract rather than assuming deployment success also means verification success.

The manifest identifies the five deployed contracts, operator, fixture/version commitment, fixed supply/allocation
and test-only status. Check its addresses against confirmed receipts, then independently read the chain to confirm
the controller/registry bindings, three synthetic records, balances and zero kernel bootstrap authority. Compare
the deployed runtime against the reviewed build and verify the source on the explorer before sharing it as a
verified public test deployment. An address or simulation manifest alone does not establish that verification.

Set `FOUNDATION_KERNEL` and `FOUNDATION_LLM` to the confirmed kernel and token addresses, then run the prepared
read-only check:

```bash
forge script scripts/DeploySepoliaFoundation.s.sol:DeploySepoliaFoundation \
  --sig 'verify(address,address)' "$FOUNDATION_KERNEL" "$FOUNDATION_LLM" \
  --rpc-url "$SEPOLIA_RPC_URL" -vv
```

This call sends no transaction and does not require the deployment key. It checks the **fresh deployment**, including
the initial token allocation. Run it before testers intentionally transfer their LLM. A later allocation change can
legitimately fail this initial-state check; that does not by itself mean the changed test deployment is broken.

## Exercise the prepared components

The token supports ordinary transfers and allowances. The operator reserve can fund actual test wallets; no mint
command is available. For membership, use the controller ABI's `recordRestriction`, `stayRestriction`,
`resumeRestriction` and `revokeRestriction` methods, then read `MembershipRegistry.rightsNow` and `orderOf`.
Each relief operation names one order and its expected revision, preserving unrelated orders.

The controller accepts these exact calls:

```solidity
recordRestriction((bytes32 personId, bytes32 orderId, uint16 restrictedMask,
    uint64 effectiveAt, uint64 expiresAt, bool indefinite))
stayRestriction(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
resumeRestriction(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
revokeRestriction(bytes32 personId, bytes32 orderId, uint256 expectedRevision)
```

Use the exported controller ABI for transaction encoding; the notation above describes the tuple rather than a
copy-paste Solidity source declaration. Each call returns its generated synthetic receipt ID. Controller getters
expose the operator, pinned registry/kernel addresses, seeded state and next receipt nonce. Failed registry writes
roll back the nonce as well as the attempted state change.

Finite restrictions stop applying at their exclusive expiry without a cleanup transaction. A stay does not extend
the original end, and an expired order cannot be resumed. Read-time expiry does not advance mutation counters;
those counters are not historical electorate certificates. Zero current restrictions do not themselves establish
citizenship, membership, voting or borrowing eligibility.

Only synthetic data belongs in this environment. Public transactions, order subjects and receipt references are
visible. The actual collective appointment, admission, recovery and disciplinary workflows remain unfinished and
are not demonstrated by this test controller.
