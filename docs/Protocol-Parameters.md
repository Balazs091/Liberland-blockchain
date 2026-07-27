# Protocol Parameters

This is the boss-review manifest for the current code. Values are denominated in whole tokens unless a base-unit
suffix is shown. The executable sources remain `scripts/parameters/EthereumMainnetParameters.sol`,
`scripts/parameters/SepoliaDemoParameters.sol`, and the immutable policy constructors referenced below.

## Network and Congress

| Parameter | Ethereum mainnet | Sepolia demo |
| --- | ---: | ---: |
| Chain ID | 1 | 11155111 |
| Congress seats | 7 | 2 |
| Runner-up slots | 2 | 2 |
| Maximum candidates | 9 | 8 |
| Nomination minimum | 2 days | 1 day |
| Voting minimum | 3 days | 2 days |
| Maximum scheduling lead | 14 days | 3 days |
| Recurring cycle | 90 days | 3 days |
| Election end boundary | 17:00 UTC | 17:00 UTC |

The boundary is 18:00 in fixed CET (UTC+1), not daylight-saving CEST. Production first imports the remaining
pre-migration cycle through `GENESIS_CONGRESS_CYCLE_END_TIMESTAMP`; it must be in the future, preserve the complete
nomination/voting minimums, be no more than one 90-day cycle away, and land at 17:00 UTC. All seven production seats
are populated from the first seven of seven-to-nine ranked genesis candidates. Later cycles use the full 90 days.
Late finalization advances to the next 17:00 UTC boundary and does not drift to the transaction hour.

## LLM, identity, and stake

| Parameter | Both networks |
| --- | ---: |
| LLM decimals | 18 |
| LLM hard cap | 70,000,000 LLM |
| Minimum citizen stake | 5,000 LLM |
| Minimum candidate stake | 6,000 LLM |
| Candidate bond requirement | 6,000 LLM |
| Citizen referendum proposal bond | 6,000 LLM |
| Unstake welfare period | 30 days |
| Annual unstake rate input | 1,064 bps |
| Wallet-migration delay | 2 days |

The 1,064 bps annual input releases approximately 10% of the original stake over twelve 30-day unstake operations
because each operation applies to the then-current balance. A protected or lending-lien floor can reduce the actual
release. LLM is not minted by Treasury; contribution rewards spend an existing Treasury reserve.

## Referenda and constitutional thresholds

| Parameter | Both networks |
| --- | ---: |
| Citizen-origin ordinary quorum | 10,000 LLM turnout |
| Congress-origin ordinary quorum | 8,000 LLM turnout |
| Citizen proposal fee | 0 LLM |
| Congress proposal fee | 0 LLM |
| Ordinary voting minimum | 7 days |
| Emergency voting duration | 3 days |
| Standard/maximum adoption delay | 7 days |
| Constitutional supporting headcount | max(2, 50% of electorate, rounded up) |
| Constitutional supporting stake | 65% of weighted turnout, rounded up |

State-bearing modules, policies, authorities, and new extension IDs use the constitutional double threshold. Known
bounded workflow apps use the ordinary module-governance threshold. The dedicated Congress-election-policy
referendum may change timing only; a breaking election-policy replacement uses constitutional module governance.
Each referendum and election stores its starting policy and the last completed block used for individual historical
stake weight. New creation requires the voting policy's immutable electorate pointer to match the current kernel
electorate and `snapshotAtCurrentEpoch` to certify that block against the current policy epoch and live identity/stake
source revisions. A voter must also be in current good standing and have been eligible at that block. Completion of
a policy rebuild or missed-callback catch-up takes effect for creation in the following block because the completion
block is not yet the last completed block. Historical `snapshotAt`/`wasEligibleAt` reads are retained for processes
that already pinned an older policy/electorate. `DemoSetupAuthority` pins illustrative seeded records to its current
transaction block, where a later same-block checkpoint can still change the read. Production never deploys that demo
path; after setup, new live processes on both networks use the current-epoch last-completed-block path.

## Senate, executive, and public veto

| Parameter | Both networks |
| --- | ---: |
| Senate capacity | 100 seats |
| Minimum Senate cancellation support | 2 seats |
| Disbursement suspension period | 30 days, bounded by action expiry |
| Public veto threshold | 2 eligible citizens |
| President term | 1,825 days |
| Prime Minister term | 1,825 days |
| Minister term | 1,825 days |

President proxy support is capped by direct Senate support: proxy votes may amplify participation but cannot create
the required support alone. Production genesis must occupy at least two Senate seats. Political role authority
follows the person's current active wallet after an approved migration. President-election ballots cannot be cast
while a President remains in term. Pending public-veto support counts only currently eligible supporters; a
completed repeal retains its final count.

## Timelocks and treasury

| Parameter | Both networks |
| --- | ---: |
| Module governance delay | 2 days |
| Budget approval delay | 1 day |
| Legislation enactment delay | 1 day |
| Treasury disbursement delay | 2 days |
| Default execution window | 7 days |
| Standard office payout pre-route delay | 6 hours |
| Sensitive payout pre-route delay | 1 day |

Sensitive office payouts are grants, contribution rewards, and capital expenditure. Their earliest end-to-end
execution is normally 3 days (1-day office delay plus 2-day treasury timelock); standard payouts are normally 54
hours. Every asset is explicitly allowlisted, and production clerk limits are environment inputs in the asset's
smallest unit. Sepolia seeds these per-payout clerk limits:

| Demo clerk limit | Operations/refund | Salary |
| --- | ---: | ---: |
| LLM | 3,000 LLM | 2,000 LLM |
| Mock USDC | 3,000 USDC | 2,000 USDC |

## Launch lending

| Parameter | Ethereum mainnet | Sepolia demo |
| --- | ---: | ---: |
| Borrow asset | External 6-decimal `USDC_TOKEN` | Deployed `MockUSDC` |
| Fixed launch price | 1 LLM = 2 USDC | 1 LLM = 2 USDC |
| Maximum LTV | 30% | 30% |
| Liquidation threshold | 40% | 40% |
| Liquidation bonus | 15% | 15% |
| Reserve factor | 15% | 15% |
| Aggregate borrow cap | 1,000,000 USDC | 1,000,000 USDC |
| Per-person debt cap | 100,000 USDC | Unlimited (0) |
| Utilization kink | 80% | 80% |
| Borrow APR at 0% utilization | 5% | 5% |
| Borrow APR at kink | 13% | 13% |
| Borrow APR at 100% utilization | 113% | 113% |

The fixed oracle is an intentional launch decision. It has no market-feed manipulation or staleness mechanism, but
the configured price can become economically wrong. The initial 30% LTV means approximately 333% collateralization
at borrowing; the 40% threshold corresponds to 250% collateralization at liquidation. Oracle, interest, and risk
policies can be replaced by governance. Replacing the state-bearing pool itself requires a reviewed custody/debt
migration; changing its kernel pointer does not migrate state.

The 15% bonus makes a fixed-price liquidation break even at an external LLM price of approximately 1.74 USDC before
gas, execution risk, and the active-stake release delay. It does not make the fixed oracle react to a market decline:
until the oracle is replaced or repriced, falling external LLM value alone does not lower on-chain health factors.

The risk-policy constructor also requires
`liquidationThreshold * (1 + liquidationBonus) <= 100%`; the configured values satisfy it at 46%. Debt is stored as
per-person scaled debt under one global `1e27` borrow index. The rate and reserve factor effective for an elapsed
interval are checkpointed, so later cash donations or policy replacement do not retroactively reprice that interval.
The citizenship retained-stake floor is snapshotted when a lien first becomes nonzero and cleared when that lien is
fully repaid. For bad-debt absorption, protected/retained floor stake is not recoverable collateral.
`absorbBadDebt` rejects only while the available surplus can cover the rounded seizure for the smallest asset
repayment that actually reduces scaled debt.

## Production values supplied at deployment

These are not safe defaults and must be independently signed off before broadcast:

- exact LLM and USDC addresses and bytecode/proxy status;
- four office-admin wallets, all different from the deployer;
- treasury asset allowlist and per-asset clerk limits;
- seven or more genesis citizens, every person/wallet/metadata record, and exact stake backing;
- Senate occupants, seven-to-nine ranked Congress candidates, President, and mandate hash;
- imported Congress cycle end timestamp; and
- Treasury LLM contribution-reward reserve and the first enacted budget envelopes.
