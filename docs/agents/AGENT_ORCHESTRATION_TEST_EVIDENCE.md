# Agent orchestration — test evidence

**14 August 2026.** `node --test scripts/checks/org_reorg_behaviour.test.mjs` — **48 tests, 48 pass,
0 fail**, 24 assertions run twice: once against production `htdblwldjkcgjvmqkbeh` and once against
staging `pglpqrhvozwepymcuunn`.

None of these asserts on a source string, on a function merely existing, or on a row count a seed
could satisfy. Each runs the real runtime path. Where a behaviour must **not** occur, the test
constructs the input that would make it occur and asserts the refusal — a new guard returning zero
proves nothing until you force it to fire.

Writes run inside an aborted transaction: perform the write, count the effect, `raise exception`
with the counts so the transaction rolls back and the numbers still come out.

## What each test exercises

### Unique role resolution
`select` over `org_role` asserting 0 agents holding two active canonical roles, 0 active employees
with no canonical role, exactly 86 overlays, ≥176 active roles. The uniqueness is also a constraint
— `org_role_one_per_agent_ux` — so a duplicate is unrepresentable, not merely absent.

### Old IDs still resolve
18 legacy and merged ids (`brief`, `followup`, `procurement`, `marketing`, `legal`, `analytics`,
`it`, `security`, `onboarding`, `docs`, `sales_director`, `ops_director`, `bookkeeper`,
`innovation_mgr`, `analytics_director`, `supplier_intel_analyst`, `notification_ops`,
`marketing_copy`) are each pushed through `fn_org_agent_resolve`, `fn_org_role_resolve` and
`fn_org_role_agent`; all three must return non-null for every one. 15 canonical names are pushed the
other way. **This test failed first**: `site_reliability_engineer` and `data_protection_officer`
resolved at the role layer and not at the agent layer, and a null addressee is silently rewritten to
`brief` and marked escalated. Fixed in `org_reorg_08_findings.sql`.

### Manager chains and cycles
A recursive walk asserts every one of the 176 roles reaches `ceo` and no chain runs past depth 40.
Then the cycle is **constructed**: `update org_role set manager_role_id='chief_of_staff' where
role_id='ceo'` must raise `reporting cycle: ceo -> chief_of_staff would close a loop`. It does.

### Department ownership
Exactly ten active departments; every head is a member of the department it leads; zero active
employees in a closed department; zero open tasks in a closed department.

### Knowledge retrieval survived the merge
`fn_agent_context_v3` is called for eight employees who changed department, asserting each still
retrieves department knowledge (>0 slices), carries a canonical `role_id`, owned decisions,
forbidden decisions, authority, and >10 knowledge records. Measured: `marketing` 72 records,
`procurement` 71, `cfo` 72, `security` 71.

A separate test asserts the authority block holds **one row per action class** — before the fix a
Growth role read 157 entries covering 67 classes, the same class appearing at up to three different
tiers, and would have taken whichever it saw first.

### Independent review
For all ten departments, `fn_pick_reviewer(dept, head)` must not return the head. Measured:

| department | head | reviewer when the head authored |
|---|---|---|
| exec | ceo | *(refuses — escalate)* |
| growth | sales_director | brief |
| customer_experience | followup | brief |
| marketplace | procurement | supplier_verification |
| product_eng | cto | model_evaluator |
| data_intel | intel_director | knowledge_validator |
| finance | cfo | brief |
| legal | legal | compliance_mgr |
| people_ops | ops_director | brief |
| assurance | qa_manager | ai_qa_specialist |

`fn_pick_reviewer('marketplace')` with no author still returns `procurement`, so no existing
one-argument caller changed meaning.

`fn_review_submit('social_post', …, author='procurement', …)` is then run in an aborted
transaction and every `review_chain` row it writes is counted: **0 of them have
`reviewer_agent = author_agent`.**

Finally the constraint is forced: inserting a row with `author_agent = reviewer_agent = 'procurement'`
must be refused by `review_chain_no_self_approval_ck`. It is.

### Specialist as a tool, handoff as a record
`fn_specialist_invoke('rfq_qualification_manager','spec_fitout',…)` returns `ok:true`, names the
manager as `accountable_owner`, sets `customer_visible:false` and leaves exactly one
`specialist_invocation` row. Invoking a `scheduled_manager` (`cfo`) as a tool is **refused** with
`use: fn_role_handoff` — a standing manager is not a tool, because two agents holding the same
subject is exactly the "no accountable owner" failure.

`fn_role_handoff('customer_support','general_counsel','dispute',…)` transfers ownership, returns
`accountable_owner: general_counsel`, records whether the handoff was declared in the role's
`handoff_targets`, and leaves one `handoff` row. A role handing off to itself is refused.

### Overlay invocation
All 86 categories resolve through `fn_overlay_for_category` to an existing overlay role invoked by
`inquiry_router`. All 86 overlays have `runtime_agent_key is null` — no standing model instance —
and all 86 carry `dispatching to suppliers` and `exposing customer identity` in
`forbidden_decisions`.

### Task assignment
Zero open non-review tasks sit with an independent reviewer. **This test failed first**, at 44 —
`knowledge_validator` 10, `ai_qa_specialist` 6, `test_automation_eng` 6, `compliance_mgr` 5,
`security` 5, `risk_governance_mgr` 5, `supplier_verification` 4, `fraud_analyst` 3. Those were
released and `fn_org_task_assign` re-placed them under the ordinary capacity rules.

Zero open tasks are assigned to an inactive employee. **This test also failed first**, at 5 —
tasks left with `supplier_intel_analyst` and `notification_ops` after the merge.

### Completeness and committees
`fn_org_role_violations()` returns 0 rows on both projects. It checks: department active, exactly
one primary manager, manager active, a runtime executor for every non-overlay role, that executor
active, KPIs, knowledge, authority, tools, a named evaluation suite, an independent reviewer
actually holding stop authority, no duplicate role per runtime agent, and no active employee without
a canonical role.

Committee seats exceed the number of roles holding them (37 seats, fewer distinct roles), no seat is
orphaned, and no two active roles share a display name.

### The objective cascade
`fn_objective_cascade()` returns `revenue_objective_aed: 1000000` and must expose
`unlinked_department_objectives` and `unlinked_role_kpis` as first-class fields. The test asserts
the keys are present, not that they are zero — a cascade that hides what it could not link is worse
than one that names it.

### Absent input never scores as satisfied
`fn_category_specialist_scorecard(1)` over a one-day window with no inquiries must return `null` for
`routing_accuracy`, `supplier_response_rate` and `valid_quotations`, each with a stated basis, and
never 0 or 100. `pct(got, 0) = 100` is how 56 unmeasured company goals once scored as perfect.

### Authority refusal
Inserting an `org_authority` row that raises a tier without `app.change_reason` set in the same
transaction must be refused by `fn_org_authority_guard`. It is. And every one of the 10 independent
reviewers holds `review_block` at tier `autonomous` — a reviewer that can only advise cannot block a
failed release gate, a privacy violation or an unsafe model regression.

## Realistic workflows, run end to end

| workflow | path exercised | result |
|---|---|---|
| customer inquiry → supplier-ready brief | `inquiry_router` → `fn_overlay_for_category` → `fn_specialist_invoke('rfq_qualification_manager','spec_fitout')` → manager retains ownership | one accountable owner, one trace row, customer not bounced |
| supplier acquisition and verification | `business_development` → `supplier_onboarding_specialist` → `supplier_verification` (independent) | the desk that recruits cannot confirm; verification holds stop authority |
| social campaign → visual review → publishing | `marketing_director` → `visual_design` → `fn_review_submit` → publish gate on the artifact digest | head-authored drafts no longer self-approve |
| revenue underperformance diagnosis | `chief_revenue_officer` owns marketing, sales and business development in one funnel; `revenue_council` is one committee, not four department readings | one reading of one funnel |
| refund / financial exception | `payments_and_billing_manager` forbidden from issuing a refund; escalates to `cfo`, which is forbidden from issuing one without the founder | refund stays a founder decision |
| legal / compliance escalation | `customer_support` → `fn_role_handoff` → `general_counsel`; `compliance_and_privacy_officer` holds stop authority and data-protection ownership | declared handoff, single owner |
| production incident | `it_operations_engineer` (Assurance) executes; `code_selfheal` and `incident_fix` moved to Product/Engineering so the gate does not author the fix | reviewer no longer certifies its own change |
| knowledge-gap discovery and remediation | `knowledge_director` → `knowledge_engineer` → `knowledge_validator` (independent) → `learning_and_development_manager` opens a remediation | validator cannot validate what it authored |

## Behaviour under multiple trials

`agent_train` grades traces against each case's own required professional moves, over five cases per
run, and both when a move should appear and when an automatic-fail behaviour should not. Two
remediations were driven to `passed` on both projects with real scores:

| project | role | baseline | retest 1 | retest 2 | status |
|---|---|---|---|---|---|
| production | `spec_fitout` | 0.525 | 0.776 | **0.882** | passed |
| production | `spec_mep` | 0.625 | 0.648 | **0.872** | passed |
| staging | `spec_fitout` | 0.525 | **0.818** | — | passed |
| staging | `spec_mep` | 0.638 | 0.638 | **0.848** | passed |

`fn_remediation_step` only writes `passed` on a score ≥ 0.8 that is also ≥ the baseline. Every score
above was read out of `agent_train`'s response; none was supplied by hand. Cost across all runs:
AED 1.03.

## What the tests do not cover

- **Live marketplace throughput.** With one confirmed supplier company-wide, `routing_accuracy`,
  `supplier_response_rate` and `valid_quotations` have no population in any recent window. The
  scorecard returns null with a stated reason rather than a number.
- **The 86 overlays' individual category knowledge.** The tests assert every overlay exists, is
  invoked by the router, has no standing instance and carries the forbidden set. They do not grade
  the content of each category's eight knowledge modules; that is the pack scorecard's job.
- **Cost and model routing per role.** `model_policy` is recorded on every role from its routing
  tier, but no test asserts that a given role's call actually used that tier.
