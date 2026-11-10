# Existing Sepolia demo verification

Read-only snapshot of the historical Sepolia demo on 29 October 2026. Fresh production genesis uses a separate inventory.

## Snapshot and method

- Public provider: `https://ethereum-sepolia-rpc.publicnode.com`.
- Chain ID: **11155111**, returned by `eth_chainId`.
- Requested block tag: **finalized**.
- Pinned block: **12,020,220** (`0xb769fc`).
- Pinned block hash: `0x9c77eb5eee0c60f06f23bfe9eae8ee89bb4afc5d27aeff40667c73ca34666054`.
- Block timestamp: **2026-10-29 14:51:00 UTC**.
- All code and `eth_call` reads use this block number. The chain ID check precedes that selection.
- RPC methods: `eth_chainId`, `eth_getBlockByNumber`, `eth_getCode`, and `eth_call`.

The raw call results include public address code sizes and Keccak-256 runtime hashes. The demo deployment record and `deployments/sepolia-demo.json` identify source `33f501417b7fd5cbba1f43f044d9f8348acd1c7c` and Solidity 0.8.36. [Raw call results](DEMO-VERIFICATION.json), [demo deployment record](../Sepolia-Demo-Deployment.md)

## Observed results

| Check | Observation at the pinned block | Interpretation |
| --- | --- | --- |
| Manifest addresses | Of 62 public address labels queried, 50 unique addresses contain runtime code | Identity app and gateway aliases share a contract. The count uses observed code at each address. |
| Child ranking store | `0x540c5431a1d0877eff9ee94d3c793f6beb7782b4`; 7,718 bytes; runtime hash `0x6a50c7db4812cdd34c30b968c728a89ed96ec8edf1a45d9dd176622313b7f87c` | Child found through `rankingStore()` and separately checked; total 51 unique observed contracts including child |
| Kernel | `0xb23e1b6186cCF3E270bcab888467834Ba1e51818` | Historical manifest kernel still has code; its queried pointers below were observed directly |
| Module lookup | 65 source identifiers queried; 63 returned registered addresses | The two remaining lookups revert with decoded `ModuleNotRegistered(bytes32)` selector `0x74fce405` |
| Setup module | `INITIAL_SETUP_AUTHORITY` unregistered. No returned module points at the historical demo setup address. | Retirement evidence covers the queried module set. |
| Optional review hook | `CONSTITUTIONAL_REVIEW` unregistered | The kernel has no registered constitutional review hook at this block. |
| Bootstrap | Kernel, router and office executor return zero bootstrap authority | Those three bootstrap entrypoints are retired at this snapshot |
| Identity writer | Kernel `IDENTITY_REGISTRY_AUTHORITY` is `0xF79741031fEcf4b19143012347f3c03ff2457bDf` | Matches historical `identityApp` / `demoCitizenGateway` aliases; it is the existing demo workflow, not the proposed new writer |
| Civic review | `identityApp()` equals the historical gateway; all five `reviewerAt(i)` reads match manifest order | App binding and public reviewer accounts checked; independence and possession of signing keys are not proved |
| Electorate | `isReady()` returns true; identity/stake registry bindings match manifest | Readiness at this block; does not certify future membership-expiry semantics or every historical snapshot |
| Stake custody | Canonical vault LLM balance **45,000 LLM**; canonical aggregate active stake **45,000 LLM** | Balance covers aggregate active stake exactly; zero surplus at this snapshot |
| Lending | Historical pool total borrows **0**, available liquidity **0**, total reserves **0** | These pool totals were observed; they are not a full export proving no other retired pool or off-chain obligation exists |
| Policy closures | Voting policy identity/stake/citizen/electorate bindings, candidate policy identity/stake/citizen bindings, and election policy candidate/voting bindings match historical manifest | Immutable dependency addresses observed; a future single-policy pointer swap still does not update these bundles |
| Pool bindings | Pool identity/stake/lien registry getters match historical manifest | Confirms those pinned dependencies at this snapshot |
| Historical officer accounts | Manifest Finance, Identity, Land and Company admins return role `1`; Finance clerk returns `2` | Consistent with expected Admin/Clerk enum values. This checks these accounts only, not controller independence or exhaustive personnel membership |

At this block, Finance, Identity and Land share the admin address `0x6319d5531045fdA2E91fe43f363eE80b8BCD7DDc`.

## Explicit limitations and unresolved checks

1. Establish source parity by rebuilding the recorded Solidity 0.8.36 revision and comparing runtime, immutables and creation inputs. Explorer match labels require separate evidence.
2. One public provider supplied the finalized block. Reconfirm the hash and relevant reads before relying on it again.
3. `DemoSetupAuthority.isSealed()` reverted. The available retirement checks are the unregistered setup ID, absence from returned pointers and zero bootstrap authorities. The raw results include the revert.
4. The inventory still needs a historical event scan, pending cases/votes/signatures, person-level loans/liens, retired pools, token controllers, land records/disputes and signing readiness.
5. Public minting and self-registration are part of the demo's test setup.
6. `deployments/sepolia.json` contains local chain ID **31337**. The historical Sepolia manifest is `deployments/sepolia-demo.json`.

## Consequence for Phase A

Attach the raw results and block hash to any demo inventory update. For fresh production, verify the official parameters, token controllers, legal approvals, receipts, runtime, genesis completion and authority retirement independently.
