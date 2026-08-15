# Phase C — Authority and Approval

**`founder approval requests where action_class != refund_decision = 0`**

Measured on `htdblwldjkcgjvmqkbeh`, 15 Aug 2026: **0**.

## The one gate

`fn_phase_c_authority_check(action_class, actor, reviewer)` returns a row, always populated:

```
allowed | mode | requires_reviewer | reviewer_independent | founder_approval | founder_initiated_only | reason
```

It never returns null, and an **unknown action class fails closed** — `allowed = false`, reason
"unknown action class … — fail closed". Injected and refused.

26 action classes are registered from the authority matrix. Exactly **one** carries
`founder_approval_required`, and it is `refund_decision`. Five are `founder_initiated_only`:
`commercial_model_change`, `company_target_change`, `country_expansion`,
`equity_fundraising_transaction`, `workflow_or_role_change`.

## Three guards, not a policy sentence

The founder-autonomy invariant is held three independent ways. Two of them would have to be
forgotten at once for a non-refund approval queue to appear.

1. **Foreign key** — `founder_approval_request.action_class` references
   `phase_c_action_class(action_class)`.
2. **CHECK** — pinned to the literal `'refund_decision'`, validated.
3. **Trigger** — `z10_founder_approval_refund_only` re-reads
   `phase_c_action_class.founder_approval_required` at write time, so the rule survives a future
   migration that flipped that flag on some other class.

And a fourth, on the registry itself: a **unique partial index** means a second action class
cannot be marked as requiring founder approval at all. Injected — `update phase_c_action_class set
founder_approval_required = true where action_class = 'production_release'` — and refused by
`phase_c_action_class_single_founder_approval_uk`.

## The counter-evidence, measured rather than conflated

The founder asked specifically that `notifies_human` not be treated as "creates a founder approval
request". They are different fields and they stay different here.

| surface | rows | awaiting the founder | what it is |
| --- | --- | --- | --- |
| `founder_approval_request` | 0 | **0** | the Phase C queue; refund-only by four guards |
| `founder_release_approval` | 1 | **0** | one **completed** record, 10 Aug 2026 18:12 UTC |
| `procurement_approval_request` | 0 | **0** | — |
| `org_action_executor.notifies_human` | 10 active | **0** | executors that **send a human a message**. Not a queue. |

The ten that message a human, none of them a refund: `capability_review`, `collections_chase`,
`escalate_founder`, `expense_log`, `forecast`, `health_report`, `money_verify`, `nudge`,
`outreach_send`, `security_review`. Phase C **did not disable any of them** and did not change
their activation. Sending mail is not an approval queue, and pretending otherwise to make a number
look better would be the wrong repair.

### The one historical release approval

`founder_release_approval` id=1: approved 2026-08-10 18:12:28 UTC by
`management@quotesdone.com`, release `f756bcb`, with the scope and the evidence recorded on the
row. It is a **completed, dated, attributed record of an approval the founder actually gave** —
evidence, not something he still owes.

Phase C **does not delete it.** Deleting the founder's own approval record to make a count look
better is exactly the fabrication this project forbids.

What Phase C does is close the door so a second one cannot be created. Both
`founder_release_approval` and `procurement_approval_request` now refuse INSERT
(`z10_phase_c_no_new_release_approval`, `z10_phase_c_no_new_procurement_approval`), with an error
that names the internal gate to use instead. Both injected and both refused.

A release approval is now the internal gate the autonomy policy names:
`quality_and_release_director` accountable, `cybersecurity_engineer` and `model_evaluator`
reviewing. A procurement approval is `company_payment_within_budget` under `accounts_payable`
with `financial_controller` reviewing.

### What the invariant counts, and what it does not

`fn_phase_c_non_refund_founder_approvals()` counts what is **waiting** for the founder and is not a
refund. It does not count the completed historical record.

That boundary is deliberate and worth defending: counting a past decision would make the number
permanently non-zero and therefore permanently uninformative — an instrument reporting on the wrong
subject. The insert triggers are what stop the historical set from growing, and they are the part
that had to be enforced.

## Refund semantics

| rule | enforcement | injected and refused |
| --- | --- | --- |
| only the founder decides | `z10_phase_c_refund_decision_guard` checks `phase_c_founder_identity` | `chief_of_staff` approving a refund |
| execution requires an **approved** decision | trigger | execution recorded against a rejected decision |
| the executor and the reconciler differ | CHECK | both set to `payments_and_billing_manager` |
| reconciliation follows execution | trigger | reconciled before executed |
| an employee cannot authorise a refund | authority gate | `payments_and_billing_manager` with `financial_controller` reviewing → refused, "requires the founder's own decision" |

Default executor `payments_and_billing_manager`, default reconciler `financial_controller` — the
authority matrix's own separation, enforced by a constraint rather than by convention.

## Founder-reserved matters are not a queue

A `founder_initiated_only` action returns `allowed = false` with the reason:

> *research and recommendation are autonomous, commitment requires an explicit founder command*

Agents may analyse and propose. They cannot commit, and they cannot open an approval task to ask.
Injected: `commercial_model_change` by the CEO with the CFO reviewing → refused.

CC-011 ("Change the reveal fee to 2 percent") and CC-020 ("Research whether we should enter Saudi
Arabia") both route as founder-initiated work with **zero founder approval requests**.

## Reviewer independence

`fn_phase_c_reviewer_independent(creator, reviewer)` resolves **both sides through the alias table
before comparing**, so two spellings of one employee collide. It is false when no reviewer is
named — absence is not independence.

Enforced on `phase_c_task` at write time, and asserted across all 257 step bindings by the
invariant `step_bindings_with_self_review = 0`.

Injected and refused: a task reviewed by its own owner; a task reviewed by an `org_role_alias` of
its own owner.

## The one overlay exception, and why it is stated separately

Exactly one of the 257 frozen steps has an owner that is not a standing employee: **W14-S05**, an
`analysis` step in W14, owned by `relevant_category_overlay`. Master spec §12 permits an overlay to
hold accountability for an analysis step inside W05, W06, W07, W10 and W14.

`fn_phase_c_step_owner_valid(step_id, owner)` encodes that and nothing wider. It is a **separate
function** from `fn_phase_c_actor_may_own` on purpose: an overlay may never own a **task**, and
folding the exception into the general predicate would have weakened the absolute rule to
accommodate the narrow one.

Both directions asserted:

- `fn_phase_c_step_owner_valid('W14-S05','relevant_category_overlay')` → **true**
- `fn_phase_c_step_owner_valid('W01-S01','category_overlay_004_…')` → **false**

## Step ownership is frozen at runtime too

`fn_phase_c_step_advance` refuses an actor who is not the step's frozen accountable owner —
Phase B froze ownership and Phase C does not reassign it at runtime. Injected:
`chief_of_staff` attempting `W01-S02` (owned by `strategy_director`) → `not_the_accountable_owner`.
