# Recovery decisions to send to decision makers

Prepared 3 November 2026. These are new choices exposed by the stuck-state review. They do not reopen the accepted
architecture, Ethereum mainnet/asset choices or user-supplied genesis plan. Engineering can continue with governed
Sepolia, compatible upgrades, preplanned rollback and bounded atomic transitions. No emergency authority or economic
fallback becomes active merely because it appears below.

The user's subsequent instruction is to follow the minimal approach and **defer a separate recovery ballot**.
RC01 remains a future design/authority question; it is not an instruction to implement another voting path. The
[complexity review](Complexity-Review.md) records the small internal simplifications and safeguards retained.

Please answer by RC ID, naming the legally competent approving body, supporting decision/text, effective date and
the exact exceptions. “An independent body” or “a reasonable deadline” needs the actual body and rule before code
can enforce it.

| ID | Decision in plain language | Options | Recommendation |
| --- | --- | --- | --- |
| RC01 | If the normal voting software breaks, may citizens use a separate route solely to repair it? | Rely on the normal route and preplanned rollback; or authorise a separate, narrowly limited citizen repair ballot | If recovery from broken voting software is required, authorise the narrow citizen route. Keep the existing constitutional participation/approval standard and module delay; approve exact replacement code and allowed non-core targets. Give it no power to pay money, alter citizenship or execute arbitrary instructions |
| RC02 | Who settles a conflict when Senate and constitutional review each block replacement of the other? | Accept that mutual block; or define a competent constitutional adjudication/escalation procedure | Name the lawful final decision body and a hearing/response timetable. No administrator override or approval by silence. Any expiry of a temporary hold or exception to a veto must be express in the governing rule |
| RC03 | What should repayments and withdrawals use while loans remain outstanding if a replaceable rate/risk rule stops responding? | Wait for normal repair; or permit a defined exit-only fallback using previously validated terms | Prefer a limited exit-only fallback, with new borrowing unavailable during the fault. Decide the rate/reserve terms, maximum period and lawful rule after that period, and how liquidation works if pricing is also unavailable. Do not give an operator discretion to choose interest or erase debt |
| RC04 | How can an accepted land dispute progress if its deciding authority becomes unavailable? | Keep the lock until that authority acts; or give a named court/body an escalation route and deadline | Provide an independent escalation route with notice and a reasoned decision. If an interim lock may expire, identify precisely which lock and when; do not automatically transfer title or clear unrelated disputes |
| RC05 | Which unfinished proceedings must continue through an upgrade rather than wait for completion? | Finish before cutover; or preserve specified cases, votes/appeals and deadlines through a reviewed migration | Finish first where practical. For unavoidable transitions, list the actual categories and preserve their rights, clocks, evidence and consumed approvals. No blanket cancellation or restarting legal deadlines. This asks for the concrete transition table, not reapproval of that accepted principle |
| RC06 | What lawful succession applies when the required officials lose their keys or too few can act? | Existing succession only; or explicitly authorised reserve appointments/new elections or another narrow process | Define person-bound succession and reserve procedures for each affected role. State who activates them and the proof required. Do not silently lower voting thresholds or install a permanent guardian key |
| RC07 | Who recognises and funds valid claims if the immutable core or an external asset cannot be repaired in place? | A pre-agreed lawful redeployment/claims process; or a separately designed change to the permanent trust root | Retain the accepted immutable-core design and approve a documented disaster/claims process. Identify the recognising body, record source, duplicate-claim rules and any actual funding. Redeployment does not free frozen USDC, recover private keys or automatically transfer assets/liabilities |

## Details needed for a separate citizen repair route

If RC01 is selected, the approval must specify all of these together:

- The exact eligible electorate and vote weight, including wallet changes and any protected/excluded identities.
  A current broken identity or electorate module cannot also be its sole recovery dependency.
- Which independently certified pre-fault snapshot may be used, its maximum age, how it was certified, and who can
  challenge an incorrect snapshot. An operator must not choose a convenient population or balance root.
- The permitted repair targets and effects. Recommendation: only listed governance/policy/authority replacements;
  no core replacement, record rewriting or asset spending through this route.
- The voting, notice, execution delay and expiry rules; exact approved bytecode and manifest commitment; review and
  Senate treatment; and RC02's dispute outcome. A new route that retains an unresolved mutual veto does not solve
  that particular lock.
- How completed actions, active ballots and approvals are preserved, and how the route itself is audited and
  prevented from becoming routine administration.

The existing code's constitutional threshold is a design reference, not proof that a new recovery route is already
legally authorised. A snapshot and an extra ballot also cannot repair arbitrary corruption of the permanent core.

## Financial fallback detail

The pool already stores the last validated rate/reserve configuration for accrual intervals. The bounded technical
fix allows debt-free withdrawals and repayment that closes the entire global loan book without selecting future
terms. It preserves elapsed interest, reserves, exact token receipt and lien closure. Partial repayment, closing
one of several loans and withdrawal while debt remains still require working live rules. Reusing cached terms for
those ongoing-debt exits is a possible design, but its economic duration and liquidation consequences must be chosen. Please
include worked examples for borrower interest, lender claims and reserves before/through/after the fault. Specify
the treatment of a revoked borrower and retired loan book as well as a current eligible borrower.

Until that rule is authorised and tested, remaining-debt recovery requires an exact compatible policy repair through
a working governance route. No ongoing-debt fallback, discretionary asset release, debt forgiveness, veto override
or new land remedy is activated by this document.

## Reply format

```text
RC ID:
Chosen option and exact rule/values:
Competent approving body:
Supporting decision/text and effective date:
Exceptions and affected existing rights:
Responsible owner:
```
