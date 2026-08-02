# Land Cadastre

This document describes the implemented cadastral trust boundary. The EVM records compact, verifiable facts and
workflow state. Legal instruments, signatures on source documents, surveys, maps, and GIS validation remain in the
document and geospatial systems whose hashes are anchored on-chain.

## Contract split

- `LandRegistry` is the stable source of truth for parcels, titles, disputes, and encumbrances.
- `LandRegistryApp` is the replaceable, bounded workflow used by the Land Registry Office and title parties.
- `LandPartyPolicy` is the replaceable rule layer that resolves stable legal-party IDs to current authorized
  signers and decides whether a party may acquire land.
- `OfficePermissionPolicy` separates preparation, finalization, and dispute-resolution permissions.

The registry accepts writes only from the current kernel `LAND_REGISTRY_AUTHORITY`. The deployed authority is the
app. Frontends must use the app for writes and the registry for canonical reads and event indexing.

## Stable parties

Titles contain `PartyRef(namespace, id)`, never a wallet address. The initial policy supports:

| Namespace | Stable ID | Acquisition rule | Authorized signer |
| --- | --- | --- | --- |
| `keccak256("party.person")` | Identity `personId` | `Verified` identity with active wallet | current active wallet |
| `keccak256("party.company")` | `companyId` | `Active`/`ComplianceWarning` with director | any current active director |
| `keccak256("party.office")` | `officeId` | active office with current administrator | current office administrator |

A director or office administrator may be an EIP-1271 contract wallet such as a Safe. A person wallet migration
changes authorization without rewriting the title. Unknown namespaces fail closed today. A future reviewed
`LandPartyPolicy` can recognize ownership groups, trusts, foreign entities, or another legal-party registry without
changing existing title storage.

Acquisition eligibility is intentionally stricter than disposition authority. A person/company/office must have a
current signer to acquire, and a company must have at least one active director. An existing holder's authorized
signer remains recognized if the party later becomes ineligible to acquire, so it can dispose of property. Do not
remove a company's final director or finalize dissolution while it still holds land; a terminal signer-less company
would require a separately reviewed receiver/successor policy before it could transfer.

## Versioned records

Every cadastral payload uses a `RecordAnchor`:

- `schemaId` and `schemaVersion` identify the canonical serialization rules;
- `contentHash` identifies the complete off-chain record;
- `sourceDocumentHash` identifies the legal instrument, decision, or survey supporting the change; and
- `lineageHash` binds the new record to its predecessor or source records.

Parcel and title writes generate a chain- and registry-domain-separated on-chain `versionHash`, increment a revision,
store a nonzero `transactionId`,
and emit content/source hashes for indexing. Ordinary revisions must name the previous `versionHash` as their
lineage. This detects stale writes and creates a tamper-evident chain without storing large documents or geometry.
The schema definition, canonicalization algorithm, document retention rules, and URI resolution belong in the
external cadastre specification and must be versioned alongside the frontend/backend release.
For an imported/genesis record, `lineageHash` should commit to the source-system record or signed migration manifest.

## Office workflow

- A Land Registry clerk may submit and update parcel drafts.
- The Land Registry administrator acts as registrar and may activate/revise/retire parcels, register titles, close
  expired leaseholds,
  finalize transfers, perform structural parcel operations, register/release encumbrances, and accept/resolve
  disputes.
- A party may file a dispute only through a signer currently authorized for that stable party.
- A filed dispute becomes a transfer/structure lock only after the registrar accepts it. An active encumbrance also
  locks transfer and structural operations. Release/resolution is explicit and anchored.

The current app cannot close a live freehold/provisional/customary/communal title and recreate it for another party;
that would bypass dual consent. A future court-order, surrender, or compensation workflow must be implemented and
audited explicitly. An encumbrance's `validUntil` is evidence metadata and does not release the lock automatically;
the registrar must record its release.

Office inactivity and appointment expiry are enforced through the live office policy. Clerk authority is limited to
preparation; it cannot create a live parcel or change ownership.

## Title transfers

A title transfer requires all of the following in one registrar transaction:

1. the title's current `versionHash`;
2. a buyer that the live party policy currently permits to acquire land;
3. an EIP-712 authorization signed by a current authorized signer for both the seller and buyer;
4. a title-scoped nonce and deadline;
5. a new anchor whose lineage is the current title version; and
6. registrar finalization through `LandRegistryApp`.

The EIP-712 domain is name `Liberland Land Registry`, version `1`, the connected chain ID, and the deployed app
address. The signed struct is:

```text
TitleTransfer(
  bytes32 titleId,
  bytes32 expectedVersionHash,
  bytes32 sellerPartyKey,
  bytes32 newHolderPartyKey,
  bytes32 anchorHash,
  bytes32 transactionId,
  uint256 nonce,
  uint64 deadline
)
```

Use `hashTitleTransferAuthorization(request)` to reproduce the digest and
`titleTransferNonce(titleId)` immediately before signing. The seller party is derived from the current title; it is
not caller-supplied. The same digest is signed by both sides. The registrar submits both signer addresses and
signatures. EOAs and EIP-1271 wallets are supported.

`sellerPartyKey` and `newHolderPartyKey` are `keccak256(abi.encode(namespace, id))`. `anchorHash` is
`keccak256(abi.encode(schemaId, schemaVersion, contentHash, sourceDocumentHash, lineageHash))`. Frontends should call
the app's digest helper instead of duplicating EIP-712 encoding when possible.

## Parcel operations

Subdivision, merge, and two-parcel boundary adjustment are atomic:

- subdivision retires one parcel/title and creates 2-16 active child parcels/titles for the same holder and tenure;
- merge retires 2-16 active parcels/titles and creates one replacement, but all source titles must have the same
  holder and tenure; and
- boundary adjustment revises exactly two active parcels together while leaving their titles unchanged.

Source revisions and version lineage are checked before any write. A failed child/source validation reverts the
whole transaction. Geometry validity, non-overlap, area conservation, and CRS transformation are deliberately not
computed by Solidity; the registrar must validate them in the GIS system, then anchor the canonical result.

## Intentionally deferred extensions

The current system does not invent law for transaction fees, insurance, compensation, adjudication, or multi-party
ownership. It also does not tokenize titles as NFTs or store raw maps/documents on-chain.

These features can be added later without weakening the stable registry:

- a reviewed replacement app can require a typed fee receipt, escrow settlement, insurance proof, compensation
  decision, or court-order reference before it invokes a registry write;
- a replaceable party policy can recognize a stable ownership-group namespace for shares and co-ownership;
- dedicated registries can store fee schedules, insurance/compensation claims, court orders, or richer RRR
  (rights, restrictions, responsibilities) facts; and
- an OGC-compatible backend can serve geometry and documents whose canonical hashes remain in `RecordAnchor`.

No generic calldata executor, administrator override, or placeholder fee/insurance custody exists. Adding a module
requires an explicit audited deployment and the normal kernel registration/replacement process. If a future feature
changes registry storage, it also requires an independently reviewed state migration; changing a pointer does not
copy records.

## Deployment compatibility

This is a breaking replacement of the earlier land ABI and storage model. Existing deployments do not acquire it by
upgrading only `LandRegistryApp`. Deploy a new `LandRegistry`, `LandPartyPolicy`, and `LandRegistryApp`, migrate and
verify records, then activate the app, authority, policy, and state pointers in one reviewed atomic action batch.
Fresh Sepolia and mainnet deployments wire the complete set directly.
