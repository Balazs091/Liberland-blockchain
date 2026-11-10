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

A director or office administrator may be an EIP-1271 contract wallet such as a Safe. A person's wallet migration
changes authorization for their personal title without rewriting it. The Company Registry Office records changes to
a director's registered wallet separately. Unknown namespaces fail closed today. A future reviewed
`LandPartyPolicy` can recognize ownership groups, trusts, foreign entities, or another legal-party registry without
changing existing title storage.

Acquisition eligibility is intentionally stricter than disposition authority. A person/company/office must have a
current signer to acquire, and a company must have at least one active director. An existing holder's authorized
signer remains recognized if the party later becomes ineligible to acquire, so it can dispose of property.

The Company Registry rejects removal of the last active director and final dissolution while a company holds an
active title. The Land Registry tracks that count through registration, transfer, expiry closure, splits, and merges.
An expired lease remains counted until the registrar closes it. During suspension or dissolution in progress, a
current director may still sign a disposition with an eligible buyer. While the company is operating, the Company
Registry Office can record a replacement director before removing the last one. Historical cases with no authorized
signer still need an approved succession process before import.

Company identity facts are office-mediated: a public incorporation submission is only pending; it grants no
director or land-acquisition authority. Pending submissions cannot accumulate directors, share classes, shares or
filings that survive rejection and resubmission. Compliance filings remain possible for previously approved
suspended or dissolving companies. Company-office administrators and clerks can record directors under the current
office permission policy; land registrars must treat that fact source as an operational trust boundary.

Person acquisition checks read the fixed-size citizenship summary, identity existence and active-wallet link.
They do not copy the person's unrelated dynamic metadata URI into a land-authorization call.

## Versioned records

Every cadastral payload uses a `RecordAnchor`:

- `schemaId` and `schemaVersion` identify the canonical serialization rules;
- `contentHash` identifies the complete off-chain record;
- `sourceDocumentHash` identifies the legal instrument, decision, or survey supporting the change; and
- `lineageHash` binds the new record to its predecessor or source records.

Parcel and title writes generate a chain- and registry-domain-separated on-chain `versionHash`, increment a revision,
store a nonzero `transactionId`, and emit content/source hashes for indexing. Encumbrance registration also emits its
nonzero `transactionId`, so an indexer can bind the fact to the same external transaction dossier even though the
compact encumbrance record does not duplicate that field in storage. Ordinary revisions must name the previous `versionHash` as their
lineage. This detects stale writes and creates a tamper-evident chain without storing large documents or geometry.
The schema definition, canonicalization algorithm, document retention rules, and URI resolution belong in the
external cadastre specification and must be versioned alongside the frontend/backend release.
For an imported/genesis record, `lineageHash` should commit to the source-system record or signed migration manifest.

## Office workflow

- A Land Registry clerk may submit and update parcel drafts and approve exact dispute actions.
- The Land Registry administrator acts as registrar and may activate/revise/retire parcels, register titles, close
  expired leaseholds, finalize transfers, perform structural parcel operations and register/release encumbrances.
- A party may file a dispute only through a signer currently authorized for that stable party.
- Acceptance, dismissal and resolution each require a Land Office clerk's approval and the registrar's
  finalization. Both must be current, verified identity holders using their active wallets, with distinct person IDs.
- A filed dispute becomes a transfer and structural lock only on acceptance. Resolution releases only that dispute's
  lock and records the outcome. A lock persists until resolution. Active encumbrances have their own release path.

The current app cannot close a live freehold/provisional/customary/communal title and recreate it for another party;
that would bypass dual consent. A future court-order, surrender, or compensation workflow must be implemented and
audited explicitly. An encumbrance's `validUntil` is evidence metadata and does not release the lock automatically;
the registrar must record its release.

The clerk approves a commitment to the action, case, evidence or ruling hash, and transaction ID. Use an
unpredictable transaction ID and keep the underlying documents in the case file. The app also binds approval to
the current dispute, parcel and title state. Record a fresh approval if that state changes, the clerk's mandate or
wallet changes, a relevant module changes, or the approval is withdrawn or expires. After a module change, wait
until a later block to approve. An approval expires at the chosen deadline, at most 14 days after it was recorded.
Office appointment procedures must ensure that the two wallets have independent controllers.

## Title transfers

A title transfer requires all of the following in one registrar transaction:

1. the title's current `versionHash` and its parcel's current `versionHash`;
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
  bytes32 expectedParcelVersionHash,
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
signatures. EOAs and EIP-1271 wallets are supported. `expectedParcelVersionHash` comes from
`getParcel(getTitle(titleId).parcelId).versionHash`. Any parcel revision, including boundary adjustment, invalidates
existing transfer intent even if the title itself is unchanged. Refresh both versions and obtain both signatures again.

Signer removal prevents execution while that address is unauthorized; it does not permanently cancel earlier
signatures. If the same director or office administrator is reappointed before the deadline, an old consent can
become usable again when its versions and nonce are still current. There is no appointment epoch in the signed
payload. Use short consent deadlines and review outstanding signatures before reappointment. Permanent cancellation
on removal would need an explicitly approved and tested change to the authorization model.

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
whole transaction. An expired leasehold cannot be subdivided or merged; it must follow the explicit expired-lease
closure workflow. Geometry validity, non-overlap, area conservation, and CRS transformation are deliberately not
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

Fresh deployments wire `LandRegistry`, `LandPartyPolicy` and `LandRegistryApp` together. A compatible app-only
replacement can keep stable registry facts, but app-domain signatures, pending transfer nonces and every authority
pointer still need review. The company title count and final-director safeguard require the new versions of both
stable registries. An existing deployment needs reconciled title counts and a reviewed record migration before it
can adopt those safeguards. Both registries reject writes after their canonical address changes. Removing the last
director or finalizing dissolution also requires the current Land Registry writer to point to the canonical land
ledger. This keeps an incomplete cutover from treating an empty replacement as evidence of zero titles.

Replacing the Company Registry also requires a LandPartyPolicy built against the new registry. Reconcile records,
then activate the affected registries, policy, apps and writers together through a reviewed atomic module upgrade
plan. A matching set of addresses does not prove that the records were migrated. See
[Upgrade and Liveness](Upgrade-And-Liveness.md); a pointer vote alone cannot migrate a cadastre.
