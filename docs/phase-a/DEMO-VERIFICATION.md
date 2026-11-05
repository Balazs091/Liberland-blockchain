# Existing Sepolia demo verification

Read-only observation on 29 October 2026, separate from the **fresh production deployment** selected by the user. No transactions were submitted, no wallet was connected, and no private keys were read. The historical demo is not a production deployment and is not established to contain current `dd0005c` source.

## Snapshot and method

- Public provider: `https://ethereum-sepolia-rpc.publicnode.com`.
- Chain ID: **11155111**, returned by `eth_chainId`.
- Requested block tag: **finalized**.
- Pinned block: **12,020,220** (`0xb769fc`).
- Pinned block hash: `0x9c77eb5eee0c60f06f23bfe9eae8ee89bb4afc5d27aeff40667c73ca34666054`.
- Block timestamp: **2026-10-29 14:51:00 UTC**.
- Probe started: `2026-10-29T15:06:52.705590+00:00`.
- All code and `eth_call` reads use this block number. The chain ID check precedes that selection.
- RPC allowlist: `eth_chainId`, `eth_getBlockByNumber`, `eth_getCode`, `eth_call` only.
- Sandbox DNS initially failed. A scoped read-only network escalation succeeded against the provider above; no fallback provider was needed.

Machine-readable raw call results, public address code sizes and Keccak-256 runtime hashes are in [DEMO-VERIFICATION.json](DEMO-VERIFICATION.json). Historical expectations come from [the demo deployment record](../Sepolia-Demo-Deployment.md) and local `deployments/sepolia-demo.json`. Their recorded source is `33f501417b7fd5cbba1f43f044d9f8348acd1c7c`, Solidity 0.8.36. These observations do not turn that historical revision into the current source revision.

## Observed results

| Check | Observation at the pinned block | Interpretation |
| --- | --- | --- |
| Manifest addresses | 62 public address labels queried; 50 unique manifest addresses contain runtime code | Identity app and gateway aliases share a contract; reviewer/admin/deployer addresses are not counted as contracts merely because they occur in the manifest |
| Child ranking store | `0x540c5431a1d0877eff9ee94d3c793f6beb7782b4`; 7,718 bytes; runtime hash `0x6a50c7db4812cdd34c30b968c728a89ed96ec8edf1a45d9dd176622313b7f87c` | Child found through `rankingStore()` and separately checked; total 51 unique observed contracts including child |
| Kernel | `0xb23e1b6186cCF3E270bcab888467834Ba1e51818` | Historical manifest kernel still has code; its queried pointers below were observed directly |
| Module lookup | 65 source identifiers queried; 63 returned registered addresses | The two remaining lookups revert with decoded `ModuleNotRegistered(bytes32)` selector `0x74fce405` |
| Setup module | `INITIAL_SETUP_AUTHORITY` unregistered; no returned module points at the historical demo setup address | Supports retirement within the queried module set; not a proof of every conceivable authorisation path |
| Optional review hook | `CONSTITUTIONAL_REVIEW` unregistered | Recorded explicitly; absence is not presented as an activated court/review mechanism |
| Bootstrap | Kernel, router and office executor return zero bootstrap authority | Those three bootstrap entrypoints are retired at this snapshot |
| Identity writer | Kernel `IDENTITY_REGISTRY_AUTHORITY` is `0xF79741031fEcf4b19143012347f3c03ff2457bDf` | Matches historical `identityApp` / `demoCitizenGateway` aliases; it is the existing demo workflow, not the proposed new writer |
| Civic review | `identityApp()` equals the historical gateway; all five `reviewerAt(i)` reads match manifest order | App binding and public reviewer accounts checked; independence and possession of signing keys are not proved |
| Electorate | `isReady()` returns true; identity/stake registry bindings match manifest | Readiness at this block; does not certify future membership-expiry semantics or every historical snapshot |
| Stake custody | Canonical vault LLM balance **45,000 LLM**; canonical aggregate active stake **45,000 LLM** | Balance covers aggregate active stake exactly; zero surplus at this snapshot |
| Lending | Historical pool total borrows **0**, available liquidity **0**, total reserves **0** | These pool totals were observed; they are not a full export proving no other retired pool or off-chain obligation exists |
| Policy closures | Voting policy identity/stake/citizen/electorate bindings, candidate policy identity/stake/citizen bindings, and election policy candidate/voting bindings match historical manifest | Immutable dependency addresses observed; a future single-policy pointer swap still does not update these bundles |
| Pool bindings | Pool identity/stake/lien registry getters match historical manifest | Confirms those pinned dependencies at this snapshot |
| Historical officer accounts | Manifest Finance, Identity, Land and Company admins return role `1`; Finance clerk returns `2` | Consistent with expected Admin/Clerk enum values. This checks these accounts only, not controller independence or exhaustive personnel membership |

The observed Finance/Identity/Land admin address remains the shared historical manifest account `0x6319d5531045fdA2E91fe43f363eE80b8BCD7DDc` under those `roleOf` reads. This concentration belongs to the existing demo configuration; it is not a recommended production configuration.

## Explicit limitations and unresolved checks

1. **Runtime presence and hashes are observed; revision equality is not verified.** No rebuilt 0.8.36 runtime/immutable-slot comparison or creation-input reproduction was performed here. Do not mark contracts as matching current `dd0005c` bytecode or refresh explorer Exact/Similar Match claims from these reads.
2. One public provider supplied the finalized block; no second-provider agreement was established. Future use should reconfirm the block hash and repeat relevant reads.
3. `DemoSetupAuthority.isSealed()` reverted. That historical demo helper does not provide a supported public sealing check through this selector. Its retirement observation instead uses the unregistered initial-setup ID, absence from returned current module pointers, and zero bootstrap authorities. The raw failure is retained.
4. A full historical event scan, every pending case/vote/signature, all person-level loans/liens, all retired pools, token proxy/upgrade controllers, land records/disputes and operational signing readiness were not enumerated. Keep their inventory rows pending until directly checked.
5. Demo public mint/self-registration surfaces are documented and intentional. Their presence cannot authorise equivalent production entrypoints.
6. The unrelated local `deployments/sepolia.json` contains chain ID **31337**. It was not used as Sepolia or production provenance in this probe.

## Consequence for Phase A

Maintain the fresh-production deployment plan. Treat these observations as a separate demo inventory snapshot, not a live production migration mandate. Preserve this JSON and block hash when deriving demo-only inventory updates; leave unobserved categories unverified. Fresh production still requires its own reviewed parameters, external token/proxy checks, legal rule approval, deployment receipts, source/runtime verification, genesis completion and authority retirement.
