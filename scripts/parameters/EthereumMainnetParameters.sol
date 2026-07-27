// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {LLMTokenConstants} from "../../contracts/libraries/LLMTokenConstants.sol";

/// @title EthereumMainnetParameters
/// @notice Canonical production deployment parameters for Ethereum mainnet.
library EthereumMainnetParameters {
    uint256 internal constant CHAIN_ID = 1;

    uint256 internal constant ONE_LLM = 1e18;
    uint256 internal constant ONE_USDC = 1e6;
    uint8 internal constant LLM_DECIMALS = LLMTokenConstants.DECIMALS;
    uint256 internal constant LLM_MAX_SUPPLY = LLMTokenConstants.MAX_SUPPLY;
    uint256 internal constant MINIMUM_CITIZEN_STAKE = 5_000 * ONE_LLM;
    uint256 internal constant MINIMUM_CANDIDATE_STAKE = 6_000 * ONE_LLM;
    uint256 internal constant CANDIDATE_BOND_REQUIREMENT = 6_000 * ONE_LLM;
    uint64 internal constant WELFARE_PERIOD = 30 days;
    uint16 internal constant ANNUAL_UNSTAKE_RATE_BPS = 1_064;

    uint256 internal constant CITIZEN_QUORUM = 10_000 * ONE_LLM;
    uint256 internal constant CONGRESS_QUORUM = 8_000 * ONE_LLM;
    uint256 internal constant CITIZEN_PROPOSAL_BOND = 6_000 * ONE_LLM;
    uint256 internal constant CONSTITUTIONAL_FOR_VOTER_QUORUM = 2;
    uint16 internal constant CONSTITUTIONAL_FOR_STAKE_BPS = 6_500;

    uint32 internal constant CONGRESS_SEAT_COUNT = 7;
    uint32 internal constant CONGRESS_RUNNER_UP_COUNT = 2;
    uint32 internal constant CONGRESS_MAX_CANDIDATE_COUNT = 9;
    uint64 internal constant MINIMUM_NOMINATION_DURATION = 2 days;
    uint64 internal constant MINIMUM_ELECTION_VOTING_DURATION = 3 days;
    uint64 internal constant MAX_SCHEDULE_LEAD_TIME = 14 days;
    uint64 internal constant ELECTION_CYCLE_DURATION = 90 days;

    /// @dev 18:00 CET is 17:00 UTC. CET is treated as the fixed UTC+1 timezone, not daylight-saving CEST.
    uint64 internal constant CONGRESS_CYCLE_END_UTC_SECONDS = 17 hours;

    uint32 internal constant SENATE_CANCELLATION_THRESHOLD = 2;
    uint64 internal constant DISBURSEMENT_SUSPENSION_PERIOD = 30 days;
    uint256 internal constant PUBLIC_VETO_THRESHOLD = 2;
    uint64 internal constant IDENTITY_MIGRATION_DELAY = 2 days;
    uint64 internal constant PRESIDENT_TERM = 5 * 365 days;

    // Conservative fixed-price launch lending parameters. Each policy remains replaceable through governed module
    // updates, so a market oracle and revised risk model can be installed without migrating the lending pool.
    uint256 internal constant LAUNCH_LLM_USDC_PRICE = 2 * ONE_USDC;
    uint256 internal constant LENDING_BORROW_CAP = 1_000_000 * ONE_USDC;
    uint256 internal constant LENDING_PER_PERSON_DEBT_CAP = 100_000 * ONE_USDC;
    uint16 internal constant LENDING_BASE_RATE_BPS = 500;
    uint16 internal constant LENDING_SLOPE_TO_KINK_BPS = 800;
    uint16 internal constant LENDING_SLOPE_AFTER_KINK_BPS = 10_000;
    uint256 internal constant LENDING_KINK_UTILIZATION_RAY = 8e26;
    uint16 internal constant LENDING_MAX_LTV_BPS = 3_000;
    uint16 internal constant LENDING_LIQUIDATION_THRESHOLD_BPS = 4_000;
    uint16 internal constant LENDING_LIQUIDATION_BONUS_BPS = 1_500;
    uint16 internal constant LENDING_RESERVE_FACTOR_BPS = 1_500;

    uint64 internal constant MODULE_GOVERNANCE_DELAY = 2 days;
    uint64 internal constant TREASURY_BUDGET_APPROVAL_DELAY = 1 days;
    uint64 internal constant LEGISLATION_ENACTMENT_DELAY = 1 days;
    uint64 internal constant TREASURY_DISBURSEMENT_DELAY = 2 days;
    uint64 internal constant DEFAULT_EXECUTION_WINDOW = 7 days;
}
