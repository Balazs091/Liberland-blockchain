// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title KernelModuleIds
/// @notice Canonical module identifiers used by the current milestone contracts.
library KernelModuleIds {
    bytes32 internal constant GOVERNANCE_ROUTER = keccak256("core.governance-router");
    bytes32 internal constant ACTION_TIMELOCK = keccak256("core.action-timelock");
    bytes32 internal constant IDENTITY_REGISTRY = keccak256("registry.identity");
    bytes32 internal constant CONGRESS_CANDIDATE_REGISTRY = keccak256("registry.congress-candidate");
    bytes32 internal constant LEGISLATION_REGISTRY = keccak256("registry.legislation");
    bytes32 internal constant REFERENDUM_REGISTRY = keccak256("registry.referendum");
    bytes32 internal constant SENATE_SEAT_REGISTRY = keccak256("registry.senate-seat");
    bytes32 internal constant STAKE_REGISTRY = keccak256("registry.stake");
    bytes32 internal constant STAKE_LIEN_REGISTRY = keccak256("registry.stake-lien");
    bytes32 internal constant LAND_REGISTRY = keccak256("registry.land");
    bytes32 internal constant COMPANY_REGISTRY = keccak256("registry.company");
    bytes32 internal constant TREASURY_VAULT = keccak256("registry.treasury-vault");
    bytes32 internal constant BUDGET_ENVELOPE_REGISTRY = keccak256("registry.budget-envelope");
    bytes32 internal constant OFFICE_REGISTRY = keccak256("registry.office");
    bytes32 internal constant PRESIDENT_REGISTRY = keccak256("registry.president");
    bytes32 internal constant EXECUTIVE_REGISTRY = keccak256("registry.executive");
    bytes32 internal constant BUDGET_ENVELOPE_ACCOUNTING_AUTHORITY = keccak256("authority.budget-envelope-accounting");
    bytes32 internal constant BUDGET_ENVELOPE_REGISTRY_AUTHORITY = keccak256("authority.budget-envelope-registry");
    bytes32 internal constant COMPANY_REGISTRY_AUTHORITY = keccak256("authority.company-registry");
    bytes32 internal constant CONGRESS_CANDIDATE_REGISTRY_AUTHORITY =
        keccak256("authority.congress-candidate-registry");
    bytes32 internal constant IDENTITY_REGISTRY_AUTHORITY = keccak256("authority.identity-registry");
    bytes32 internal constant INITIAL_SETUP_AUTHORITY = keccak256("authority.initial-setup");
    bytes32 internal constant LAND_REGISTRY_AUTHORITY = keccak256("authority.land-registry");
    bytes32 internal constant LEGISLATION_REGISTRY_AUTHORITY = keccak256("authority.legislation-registry");
    bytes32 internal constant LEGISLATION_REPEAL_AUTHORITY = keccak256("authority.legislation-repeal");
    bytes32 internal constant OFFICE_REGISTRY_AUTHORITY = keccak256("authority.office-registry");
    bytes32 internal constant PRESIDENT_REGISTRY_AUTHORITY = keccak256("authority.president-registry");
    bytes32 internal constant EXECUTIVE_REGISTRY_AUTHORITY = keccak256("authority.executive-registry");
    bytes32 internal constant REFERENDUM_REGISTRY_AUTHORITY = keccak256("authority.referendum-registry");
    bytes32 internal constant SENATE_SEAT_REGISTRY_AUTHORITY = keccak256("authority.senate-seat-registry");
    bytes32 internal constant STAKE_LIEN_REGISTRY_AUTHORITY = keccak256("authority.stake-lien-registry");
    bytes32 internal constant STAKE_DEPOSIT_AUTHORITY = keccak256("authority.stake-deposit");
    bytes32 internal constant STAKE_LIQUIDATION_AUTHORITY = keccak256("authority.stake-liquidation");
    bytes32 internal constant STAKE_REGISTRY_AUTHORITY = keccak256("authority.stake-registry");
    bytes32 internal constant CANDIDATE_ELIGIBILITY_POLICY = keccak256("policy.candidate-eligibility");
    bytes32 internal constant CITIZEN_ELIGIBILITY_POLICY = keccak256("policy.citizen-eligibility");
    bytes32 internal constant CONGRESS_ELECTION_POLICY = keccak256("policy.congress-election");
    bytes32 internal constant OFFICE_PERMISSION_POLICY = keccak256("policy.office-permission");
    bytes32 internal constant REFERENDUM_POLICY = keccak256("policy.referendum");
    bytes32 internal constant SENATE_POWERS_POLICY = keccak256("policy.senate-powers");
    bytes32 internal constant TREASURY_SPENDING_POLICY = keccak256("policy.treasury-spending");
    bytes32 internal constant VOTING_POWER_POLICY = keccak256("policy.voting-power");
    bytes32 internal constant UNSTAKING_POLICY = keccak256("policy.unstaking");
    bytes32 internal constant LLM_USDC_PRICE_ORACLE_POLICY = keccak256("policy.llm-usdc-price-oracle");
    bytes32 internal constant USDC_INTEREST_RATE_POLICY = keccak256("policy.usdc-interest-rate");
    bytes32 internal constant LENDING_RISK_PARAMETER_POLICY = keccak256("policy.lending-risk-parameter");
    bytes32 internal constant CABINET_APP = keccak256("app.cabinet");
    bytes32 internal constant CONGRESS_ELECTION_APP = keccak256("app.congress-election");
    bytes32 internal constant COMPANY_REGISTRY_APP = keccak256("app.company-registry");
    bytes32 internal constant DECISION_APP = keccak256("app.decision");
    bytes32 internal constant HEAD_OF_STATE_APP = keccak256("app.head-of-state");
    bytes32 internal constant LAND_REGISTRY_APP = keccak256("app.land-registry");
    bytes32 internal constant OFFICE_EXECUTOR = keccak256("app.office-executor");
    bytes32 internal constant PAYOUT_QUEUE = keccak256("app.payout-queue");
    bytes32 internal constant PUBLIC_VETO_APP = keccak256("app.public-veto");
    bytes32 internal constant REFERENDUM_APP = keccak256("app.referendum");
    bytes32 internal constant SENATE_APP = keccak256("app.senate");
    bytes32 internal constant USDC_LENDING_POOL_APP = keccak256("app.usdc-lending-pool");
    bytes32 internal constant CONSTITUTIONAL_REVIEW = keccak256("app.constitutional-review");
}
