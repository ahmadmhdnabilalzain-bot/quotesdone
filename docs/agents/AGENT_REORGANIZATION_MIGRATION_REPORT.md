# Agent reorganisation — migration report

**14 August 2026.** Applied to both projects, byte-identical, each file inside one transaction:
production `htdblwldjkcgjvmqkbeh` and staging `pglpqrhvozwepymcuunn`.

## What changed, in numbers

| | before | after |
|---|---|---|
| active departments | 25 | **10** |
| department rows (nothing deleted) | 25 | 32 (10 active, 22 marked `merged_into`) |
| active employees (`org_agents`) | 93 | **90** (3 merged, kept inactive for history) |
| canonical roles (`org_role`) | — | **176** (90 accountable + 86 category overlays) |
| scheduled managers | — | 12 |
| event-driven operators | — | 33 |
| on-demand specialists | — | 35 |
| independent reviewers | — | 10 |
| knowledge overlays | — | 86 |
| committee seats (`org_role_committee`) | — | 37 across 5 committees |
| role aliases | — | 157 |
| agent aliases | 27 | 183 |
| roles with no authority record | 24 | **0** |
| roles with no tools | 11 | **0** |
| self-approvals possible | yes | **refused by constraint** |
| `fn_org_role_violations()` | — | **0** |

## The department merge

| target | absorbed |
|---|---|
| `exec` Executive & Strategy | `evolution` (strategy half) |
| `growth` Growth & Revenue | `marketing`, `sales`, `bizdev` |
| `customer_experience` Customer Experience & Communications | `customer_success`, `comms` |
| `marketplace` Marketplace & Supplier Network | `procurement`, `rfq_intelligence`, `supplier_success`, `supplier_knowledge`, `doc_intelligence` |
| `product_eng` Product, Engineering & AI | `engineering`, `ai_dept`, `evolution` (product half) |
| `data_intel` Data, Intelligence & Knowledge | `intelligence`, `analytics`, `knowledge_eng` |
| `finance` Finance & Payments | `payments` |
| `legal` Legal, Compliance, Risk & Trust | `trust_safety` |
| `people_ops` People & Company Operations | `knowledge` (Administration & Operations), `hr` |
| `assurance` Independent Assurance, Security & Reliability | `qa`, `it` |

Nothing was deleted. An absorbed department keeps its row, keeps every historical foreign key
pointing at it, and gains `merged_into` plus `merged_at`. `active` goes false, so `dept_plan`,
`dept_learn` and `intent_router` — all three of which fan out over `org_departments where active` —
now see ten charters instead of twenty-five overlapping ones.

## Why the physical agent keys were not renamed

The brief asks for ten renames and, in the same paragraph, says **"do not rename blindly — find
every caller, foreign key, task assignment, log, policy, knowledge mapping, KPI and tool permission
first."** Measured on production before touching anything:

- the ten "vague" keys appear as **string literals inside 51 sites across 40+ live SQL routines**
  (`security` 8, `brief` 7, `it` 7, `marketing` 7, `procurement` 6, `legal` 6, `onboarding` 5,
  `docs` 3, `followup` 1, `analytics` 1);
- agent keys are held in **~50 text columns across 25 tables**, of which **only 5 carry a foreign
  key** — the rest would be orphaned by a primary-key rename and no constraint would say so.

So the canonical identity moved up a layer instead. `org_role.role_id` carries the unambiguous name
(`chief_of_staff`, `general_counsel`, `marketplace_director`, `cybersecurity_engineer`…),
`org_agents.agent_key` keeps the physical runtime key, and both directions resolve:

```
fn_org_role_resolve('brief')            -> chief_of_staff
fn_org_agent_resolve('chief_of_staff')  -> brief
fn_org_role_agent('site_reliability_engineer') -> it
```

Every rename in the brief is implemented as a canonical role id plus a bidirectional alias:
`brief`→`chief_of_staff`, `followup`→`customer_success_director`,
`procurement`→`marketplace_director`, `marketing`→`marketing_director`,
`legal`→`general_counsel`, `it`→`it_operations_engineer`, `security`→`cybersecurity_engineer`,
`onboarding`→`supplier_onboarding_specialist`, `docs`→`document_operations_specialist`.

`analytics`→`business_intelligence_analyst` is the one deliberate departure: `bi_analyst` already
holds that title, and `analytics` is titled *Data & Analytics Engineer*. It became `data_engineer`
— the role the brief lists as missing — and `bi_analyst` became
`business_intelligence_analyst`. Naming both the same thing would have recreated the ambiguity
this exercise exists to remove.

## Ownership roles the brief named as missing

| role asked for | how it was filled | headcount added |
|---|---|---|
| Chief Revenue Officer | `sales_director` repurposed; Marketing and Business Development now report to it | 0 |
| Product Manager | `innovation_mgr` repurposed — its recorded responsibilities were already intake, scoring, business case and outcome tracking | 0 |
| Data Engineer | `analytics`, already titled Data & Analytics Engineer | 0 |
| Financial Controller | replaces the `bookkeeper` identity | 0 |
| Site Reliability Engineer | a named second identity of `it_operations_engineer`, aliased | 0 |
| Chief of Staff | `brief`, renamed at the canonical layer | 0 |
| Privacy / data-protection ownership | `compliance_and_privacy_officer`, aliased from `data_protection_officer` and `privacy_officer` | 0 |
| one accountable Marketplace Director | `procurement`, now owning intake→reveal end to end | 0 |
| COO | `ops_director`, which already held company-wide process, quality and delivery with the widest non-executive authority set | 0 |

## Duplicate identities removed

Three, each merged rather than deleted, each with the survivor chosen on measured runtime:

- **`analytics_director` → `data_intelligence_director` (`intel_director`).** Both mapped to the
  same packaged role `data-analytics-and-intelligence-director` in the same packaged department and
  both were named by `fn_delete_proposer`. `intel_director` carries the live runtime (8 agent_runs,
  14 open tasks, 2 routines) against `analytics_director`'s 1 run and 0 tasks.
- **`supplier_intel_analyst` → `supplier_intelligence_analyst` (`supplier_analyst`).** One desk.
  The surviving row is the one that carries the 15 knowledge rows; it took the clearer name.
- **`notification_ops` → `lifecycle_channel_operations` (`channel_specialist`).** A message queued
  and never sent, and a message sent into spam, are the same failure to the customer.

`marketing_copy` was already inactive and `blocked`; it maps to the same packaged role as
`marketing_content` and has no distinct caller, task, run or knowledge row. Merged into
`content_strategy_and_copy`.

**`cpo` was NOT de-duplicated.** It has exactly one `org_agents` row. What existed was
`org_departments.evolution.lead_agent = 'cpo'` — cross-department leadership, not a duplicate. That
pattern is now modelled explicitly: Evolution is dissolved, `cpo` sits in Executive & Strategy as
Chief Performance Officer, and cross-functional participation is a committee seat.

## The defect this found: 182 self-approvals

`fn_review_submit` receives the author and never passed it to `fn_pick_reviewer`, which takes only a
department and answers with that department's head. Whenever the head was the author, the head
approved itself.

Measured on production before the fix: **285 of 1,882 `review_chain` rows have
`author_agent = reviewer_agent`, and 182 of those are approvals** — the most recent at
**06:40 UTC on 14 August 2026**, five hours before this migration.

Fixed in three places:

1. `fn_pick_reviewer(dept, author)` never returns the author. When the head is the author, review
   routes to that department's independent reviewer; if there is none, it climbs one level; if
   neither is available it refuses and escalates rather than approving.
2. `fn_review_submit` passes the author, and the Chief of Staff's own drafts counter-sign to the
   CEO instead of to itself.
3. `review_chain_no_self_approval_ck` makes it unrepresentable going forward. It is `NOT VALID` on
   purpose: the 285 historical rows stay exactly as they happened, because deleting them would be
   erasing the evidence that the defect was real.

Self-review rows written since the fix: **0**.

## Other measured corrections

- **44 open tasks sat with independent reviewers** and 5 with employees merged away this morning.
  A reviewer carrying the department's routine queue is not independent of it. Those were released
  and re-assigned under the ordinary capacity rules; `fn_org_task_assign` now skips independent
  reviewers for anything that is not a review class.
- **`code_selfheal` and `incident_fix` sat with Assurance**, the function that gates releases. The
  reviewer must not author the fix it then certifies; both moved to Product, Engineering & AI, along
  with `evolution_scan`, which is product discovery.
- **`it` and `security` reported to the CTO**, whose department they gate. Both now report to the
  Assurance head, which reports to the Chief of Staff, outside engineering.
- **The OS map collapsed arbitrarily.** Merging 25 department rows into 10 left `os_department`
  holding whichever predecessor's OS survived de-duplication: Marketplace pointed at the Knowledge
  OS. `fn_owning_os` and `fn_org_task_cross_os_guard` both read that map. Reassigned deliberately.
- **Two canonical aliases resolved at the role layer but not the agent layer**, so
  `fn_org_agent_resolve('site_reliability_engineer')` returned null — and a null addressee is
  rewritten to `brief` and marked escalated, which looks like a routing decision and is a missing
  row. Every `org_role_alias` entry now has an `org_agent_alias` counterpart.

## Knowledge did not move, and did not have to

5,775 `ops_knowledge` rows are tagged with the 22 department keys that no longer name a department.
Retrieval matched `dept_key = agent.department` exactly, so on the day of the merge every moved
employee would have retrieved nothing from its own history.

`fn_dept_scope(dept)` returns the department plus everything merged into it, and
`fn_context_slice`, the authority block, the live-data bindings and the tool list all scope through
it. **No knowledge row was rewritten.** Measured after the merge, `marketing` (now in `growth`)
assembles 72 knowledge records with 6 department-shared slices; before the merge it assembled 72.

The authority block is de-duplicated to one row per action class at the most restrictive tier —
without that, a Growth role read 157 authority entries covering 67 action classes, three tiers deep
for the same class, and would have taken whichever it saw first.

## What the agents now read

`fn_agent_context_v3` carries the canonical role into every prompt: `role_id`, `runtime_mode`,
`authority_level`, `owned_decisions`, `forbidden_decisions`, `activation_conditions`,
`output_contracts`, `handoff_targets`, `escalation_targets`, `manager_role_id`, `budget_limit`,
`evaluation_suite` and committee seats. A reorganisation the agents cannot read is a document, not
an organisation.

That change is measurable in the training loop. `spec_fitout` and `spec_mep` — the two lowest
scorers and the two trade families that qualify the core product inquiries — carried an open
remediation through a real retest:

| role | baseline | retest 1 | retest 2 | status |
|---|---|---|---|---|
| `spec_fitout` | 0.525 | 0.776 | **0.882** | `passed`, `blocks_autonomy` false |
| `spec_mep` | 0.625 | 0.648 | **0.872** | `passed`, `blocks_autonomy` false |

Total cost AED 0.52. The scores are the grader's, read out of `agent_train`'s response; nothing was
supplied by hand. Between retest 1 and retest 2 one thing changed: `agent_train`'s answer prompt now
states the role's **standing output contract** — name the objective served, weigh at least two
options, give one measurable next action with an owner and a date, restate the decision and its
business consequence, and say when it will be reviewed. Those are the moves the grader recorded as
missing on every failing case, and they are professional practice rather than case answers. No
case-specific content was added to the prompt.

`fn_role_readiness_recompute()` moved the ceiling from `decision_trace_connected` to
**`independent_certification_pending`** for those two roles — the highest rung any role has reached.

## Deployment

```
scripts/sql/org_reorg_01_canonical_schema.sql       tables, constraints, no-cycle trigger, resolvers
scripts/sql/org_reorg_02_departments.sql            25 -> 10, agents moved, config repointed
scripts/sql/org_reorg_03_roles.sql                  90 canonical roles, committees, aliases
scripts/sql/org_reorg_04_runtime.sql                retrieval scope, review independence, assignment,
                                                    specialist-as-tool, structured handoff
scripts/sql/org_reorg_05_overlays_and_cascade.sql   86 overlays, authority backfill, tool ownership,
                                                    objective cascade, category scorecard
scripts/sql/org_reorg_06_compat_gaps.sql            merged-key aliases, OS coverage
scripts/sql/org_reorg_07_os_map.sql                 OS map assigned deliberately
scripts/sql/org_reorg_08_findings.sql               three findings the tests produced
```

Each was applied with `node scripts/apply_sql.mjs <file> --promote --ddl`, which posts identical
text to staging and then production and asserts the resulting shape digest matches. Every file was
first run against staging inside an aborted transaction; that probe caught two real errors before
either project saw them — a `text` literal where a `text[]` was required, and a
`org_department_alias` primary-key collision created because `data_analytics` already pointed at
both `analytics` and `intelligence`, which now canonicalise to the same department.

`node scripts/checks/project_parity.mjs` → **BOTH PROJECTS IN SYNC**.

## What is not done

- **29 department objectives and 26 role KPIs have no upward link.** Links were written only where a
  department owns exactly one active goal or objective; the rest are reported by
  `fn_objective_cascade()` as unlinked rather than guessed. A fabricated link would make the cascade
  look complete while explaining nothing.
- **111 open tasks on production have no assignee.** `fn_org_task_assign` places what capacity
  allows and names the oversubscribed departments (`exec 62/38`, `assurance 32/28`) rather than
  forcing an owner. `max_open_tasks` is the founder's decision and was not touched.
- **Four departments have no independent reviewer of their own** — Growth, Customer Experience,
  Finance and People Ops (Executive & Strategy has none by design; the CEO's own work refuses rather
  than routing). Head-authored work in those four climbs to the Chief of Staff instead, which is
  correct but a thinner control than in Marketplace, Product/Engineering, Data/Intelligence, Legal
  and Assurance, each of which has a reviewer inside the department. Measured, all ten:
  exec→refuses, growth→brief, customer_experience→brief, marketplace→supplier_verification,
  product_eng→model_evaluator, data_intel→knowledge_validator, finance→brief,
  legal→compliance_mgr, people_ops→brief, assurance→ai_qa_specialist.
- **`mandatory_field_completeness` is unmeasurable.** `inquiries.completeness` is jsonb and holds no
  non-null value anywhere: the column exists and no path writes it. The scorecard reports null and
  says so rather than printing a number that would describe the schema.
