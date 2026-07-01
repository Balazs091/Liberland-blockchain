# Milestone 07

## Goal
Build first-pass land and company registries behind explicit office workflows.

## Contracts
- LandTypes
- CompanyTypes
- ILandRegistry
- ILandRegistryApp
- ICompanyRegistry
- ICompanyRegistryApp
- LandRegistry
- LandRegistryApp
- CompanyRegistry
- CompanyRegistryApp

## Accepted defaults
- land and company registries are stable fact registries, not governance executors
- write access goes through app authorities registered in the kernel
- Land Registry Office admins and clerks can manage parcel, title, accepted dispute, and encumbrance records
- parcel and spatial data is stored as hashes; GeoJSON, cadastral files, legal documents, and other evidence remain off-chain
- parcel titles are registry records, not ERC721 tokens in this milestone
- title transfers are office-recorded mutations backed by a required document hash; v1 does not require an on-chain holder signature
- any wallet can file a land dispute notice through `LandRegistryApp`, but only the Land Registry Office can accept or resolve it
- filed-but-not-accepted land disputes do not block title transfers
- accepted land disputes block title transfers
- multiple active encumbrances can exist for one parcel, and any active encumbrance blocks title transfers
- Company Registry Office admins and clerks can approve or reject incorporations, maintain directors, maintain share classes, record filings, and operate the official internal share ledger
- incorporation submission is public, but approval and subsequent registry mutations are office actions
- registration numbers can be submitted as a pre-reserved hash or assigned by the Company Registry Office at approval
- company legal/KYC/beneficial-owner data is represented by hashes; raw private/legal data stays off-chain
- company shares are not ERC20 clones in this milestone; the registry keeps an official internal ledger until the legal and operational model is specified
- share operations are allowed for `Active` and `ComplianceWarning` companies, and blocked for pending, suspended, dissolving, dissolved, or rejected companies
- directors are recorded without enforcing a minimum count, citizenship requirement, or signature requirement until those legal rules are specified
- no company or land registry fees are implemented in this milestone
- no UUPS upgrade admin, pause switch, arbitrary registry executor, or emergency backdoor was added

## Still Open
- land survey authority, parcel subdivision/merge rules, court-linked dispute adjudication, and appeal mechanics
- whether land titles should later be mirrored by non-transferable or transferable token wrappers
- company fees, KYC/AML hooks, final registry-number issuance policy, director eligibility, beneficial-owner disclosure rules, and liquidation process
- whether company shares should later be represented by token contracts, and if so under which legal transfer restrictions
- Constitutional Court workflow and court/emergency suspension or repeal mechanics

## Done when
- all touched contracts compile
- tests pass
- deployment scripts wire the registries, apps, office roles, and kernel authorities
- documentation states both the implemented behavior and unresolved legal-policy questions
