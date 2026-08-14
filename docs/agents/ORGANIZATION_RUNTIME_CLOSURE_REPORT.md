# Organization runtime closure report

**Session:** 14 Aug 2026, 15:18–17:20 UTC (19:18–21:20 Dubai)
**Branch:** `repair/v3-certification-remediation-1` → [PR #385](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/385)
**Projects:** production `htdblwldjkcgjvmqkbeh`, staging `pglpqrhvozwepymcuunn`

> **No independent V3 certification material was accessed.** No file under
> `docs/knowledge/certification/` was read, opened, listed for content, or referenced by any script,
> query or document produced in this session. Every regression case, scenario and register below is
> built from the role contracts already in the database — `org_role.owned_decisions`,
> `forbidden_decisions`, `activation_conditions`, `output_contracts`, `escalation_targets` — and
> from `org_category_identity`, `department_objective`, `employee_authority` and `ops_knowledge`.

---

## The headline

Six defects were found and fixed, all of them live on production, none of which had ever failed.
Every one is the same shape the last several sessions have been finding: **a decision addressed to
an identity the resolver knows, taken by a path that compares raw strings instead of asking.**

The behavioural suite went from **56 tests to 68**, all passing on both projects.

The two sections that need the model — the 90-role runtime smoke test and the behavioural half of
the 86 overlays and 10 workflows — **could not be executed**. That is a credit limit, not a code
limit, and it is the one thing in this report that needs the founder.

---

## The spend meter (done first, as instructed)

The brief said `spent_aed` is never incremented, "so the halt compares against a number no path
increments and can never fire". **Re-measured, that is half right, and the half that is wrong
matters.**

`fn_ai_route` — the enforcing path inside `ai_gateway` — never read `spent_aed`. It sums
`ai_cost_log` live and always could fire. It was simply looking at a third of the money.

| | staging before | production before |
|---|---|---|
| month-to-date AI spend | AED 106.17 | AED 187.04 |
| visible to any ceiling | AED 38.42 (36%) | AED 148.56 (79%) |
| no `dept_key` at all | AED 29.87 | AED 2.70 |
| under a department key the merge removed | AED 37.87 (22 keys) | AED 35.78 |

Two causes, neither of them "the counter is not incremented":

1. **Exact-match scoping breaks on merge.** Both ceiling readers matched `dept_key = <canonical>`,
   so every row logged under one of the 22 absorbed keys — `procurement`, `marketing`, `sales`,
   `hr`, `engineering` … — fell outside every ceiling. Fixed by scoping the **read** through
   `fn_dept_scope`. No cost row was rewritten.
2. **A sibling path that never got the lexicon.** `fn_ai_route` attributes an un-departmented call
   from `fn_task_class.dept_key`, and `trg_ai_cost_attribute` — which fills `dept_key` on the way
   *into* `ai_cost_log` — consulted three *other* tables and not that one. 132 `drawing_redact_verify`,
   74 `drawing_redact`, 23 `inquiry_intake` and 21 `drawing_boq` calls landed NULL while the table
   nobody read mapped every one of them to `marketplace`.

`fn_budget_available` **did** read the dead column, and `fn_check_spend` authorises *business* spend
through it — so every department looked untouched. It now computes live over the same scope, so all
three paths answer with the same number.

**Verified by execution, in an aborted transaction:** a NULL-dept `drawing_redact` row now stores
`marketplace`; a row logged `marketing` stores `growth`; and after burning 96% of `growth`'s budget,
`fn_ai_route` returned `use_llm=false`, *"HALTED. growth is at 98.06% of its monthly AI budget"*.
**The halt bites.** It is now a permanent test.

---

## §1 — Canonical invariants

All measured on **both** projects and now asserted by `scripts/checks/org_reorg_behaviour.test.mjs`.

| invariant | result |
|---|---|
| active departments | **10** |
| merged (inactive) department rows | **22** |
| accountable runtime roles | **90** |
| category overlays | **86** |
| canonical roles total | **176** |
| distinct packaged roles held | **96** |
| employees holding an identity | **90** |
| `org_role_identity` rows | **127** |
| department merged into a dead department | **0** |
| accountable role with no packaged identity | **0** |
| identity naming an employee the merge deactivated | **0** (was **6**) |
| orphaned runtime-eligible knowledge | **0** |
| self-management | **0** |
| `fn_org_role_violations()` | **0 rows** |

### Why the identity table holds more rows than packaged roles — the 133 explained

`org_role_identity` is **(employee, packaged role)**, not one row per packaged role, so its count was
never comparable to 96. At the start of the session it held 133:

- **94** distinct employees holding **96** distinct packaged roles
- **37** rows are the second and later holders of an archetype that several real desks share
- **3** were added earlier the same day, transferring packaged identities off merged-away employees
- **6** named an employee the merge had deactivated — `analytics_director` (×3), `marketing_copy`,
  `notification_ops`, `supplier_intel_analyst`. All were `readiness='blocked'` and all resolved
  correctly through `fn_org_agent_resolve`, which is exactly why nothing had failed and no watcher
  had seen them.

Those 6 were removed (`org_reorg_17`). **Five were deleted rather than transferred** because the
successor already held that packaged role — a transfer would have written a duplicate of a row
already present. **The sixth was deleted for a stronger reason:** `intel_director` does not hold
`data-analytics-and-intelligence-reviewer-auditor`; `knowledge_validator` does, and
`knowledge_validator` is `data_intel`'s independent reviewer. Transferring `analytics_director`'s
claim to `intel_director` would have handed the **department head** the reviewer-auditor identity for
its own department — the creator/reviewer conflict §1 requires to be zero, created by the act of
tidying up.

The table now holds **127** rows on both projects: 90 employees, 96 packaged roles, 0 dead.

### The ambiguity, decided rather than reported

The brief said 17 packaged roles resolve to more than one active employee. **Measured: 22**, in three
mapping types (`package_composite`, `runtime_composite`, and one `one_to_one` that should not have
been sharing at all).

**Decision: `package_composite` is legitimate, and the ambiguity is confined to it by a test.**

The knowledge pack ships *archetypes*; the company has *desks*. `marketing-operations-specialist` is
genuinely five marketing desks (`brand_mgr`, `marketing_content`, `marketing_copy`,
`marketing_design`, `marketing_social`). Giving each of the 22 a single accountable holder would mean
either deleting real desks or inventing fake archetypes, and the ten-department structure is frozen.

So the boundary is **not** "one holder per packaged role". It is: **a packaged role may be shared only
through a mapping that declares itself composite.** A `one_to_one` row sharing its archetype is a
contradiction, because `one_to_one` is the claim that it is not shared. That is now a permanent test,
and there is exactly one such contradiction fewer than there was.

---

## §2 — Identity-resolution coverage

`docs/agents/IDENTITY_RESOLUTION_COVERAGE.csv` · guard at `scripts/checks/org_identity_coverage.mjs`

| | count |
|---|---|
| routines taking an agent/actor/assignee/reviewer/manager/role/employee identifier | **101** |
| resolve canonically | **11** |
| **compare** an identity (equality or table filter) | **40** |
| of those, compare **without** resolving — the ones an alias defeats | **34** |

The brief said 68; the wider figure includes `p_by`, `p_owner`, `p_author` and `p_addressee`, because
an approver recorded as `decided_by` is an identity and comparing it to an author is precisely the
check the 182 historical self-approvals needed.

**The most consequential one was fixed.** `fn_agent_context_v3('chief_of_staff')` returned
`{"error":"unknown agent"}` — and `chief_of_staff` is not a stale string, it is `brief`'s own
`role_id` in `org_role`. The function looked up `org_agents` by `agent_key` and nothing else, so an
employee addressed by its canonical role id, a merged-away key, a packaged role id or a job title
**assembled no context at all** — not an error the caller sees, an empty prompt. `agent_brain`,
`action_worker`, `dept_plan`, `agent_act` and `exec_agents` all reach context through this function.
It now resolves before assembly, and `coalesce` keeps an unknown key unknown so the existing refusal
still fires.

**The guard.** The 34 are baselined so the list can only shrink, and CI fails when a new routine joins
them. Verified by forcing it: removing one name from the baseline exits **1**, restoring it exits
**0**. (The first version exited 127 — a libuv teardown crash on Windows that reads like "node not
found"; it now sets `exitCode` and ends naturally so CI gets a real 0/1.)

**Not fixed, and named rather than hidden:** the remaining 33. Eight of them are approval routines —
`fn_kb_approve`, `fn_kb_gov_approve`, `fn_po_approve`, `fn_prompt_approve_draft`, `fn_review_decide`,
`fn_approval_decide`, `fn_trade_confirm`, `fn_outcome_open` — and the finding there is stronger than
"they do not resolve": **none of them contains a self-approval check at all.** They record
`approved_by = p_by` without ever comparing the approver to the author. That is a larger piece of work
than this session could finish honestly, and it is written down rather than left implied.

---

## §3 — Historical self-review

`docs/agents/HISTORICAL_SELF_REVIEW_REGISTER.csv` — all **285** rows preserved, none rewritten.

Recomputed on the **canonical** identity of both sides rather than the raw strings: still **285**, so
no self-review was hiding behind an alias in history. The count in the brief was right.

| classification | rows | subjects |
|---|---|---|
| non-consequential (98 `ownership`/`owned` claims + 5 `request_revision`) | **103** | 102 |
| already independently reviewed | **182** | 147 |
| superseded | 0 | 0 |
| **requires independent re-review** | **0** | 0 |

The 182 approvals are the ones the brief flagged. Checked **per subject** rather than per row — a
subject can be self-reviewed at every stage — **all 147 subjects carrying a self-approval also passed
an independent approval at another stage of the same chain.** Zero were approved only by their own
author across every stage, so zero required re-review. That is a better answer than the brief feared,
and it is the per-subject check that establishes it; the per-row check would have looked identical
for a subject that was never independently seen.

### The hole that was still open, and is now closed

§3 asks for proof that merged aliases cannot make one employee appear as two reviewers. **Measured on
production, they could — in all ten departments, every time.**

`fn_pick_reviewer` compares the author to the department head as a **raw string**, and all ten heads
carry aliases. An author passed as `Finance Director` is not equal to `cfo`, so the guard added when
the 182 self-approvals were found did not fire, and the function returned the author as its own
reviewer:

| department | head | author passed as | reviewer returned |
|---|---|---|---|
| assurance | `qa_manager` | `qa-and-testing-analyst-controller` | `qa_manager` |
| customer_experience | `followup` | `customer_success` | `followup` |
| data_intel | `intel_director` | `analytics_director` | `intel_director` |
| exec | `ceo` | `CEO AI` | `ceo` |
| finance | `cfo` | `Finance Director` | `cfo` |
| growth | `sales_director` | `chief_revenue_officer` | `sales_director` |
| legal | `legal` | `general_counsel` | `legal` |
| marketplace | `procurement` | `marketplace_director` | `procurement` |
| people_ops | `ops_director` | `administration-and-operations-director` | `ops_director` |
| product_eng | `cto` | `CTO AI` | `cto` |

`fn_org_agent_resolve` resolves every one of those aliases correctly. The picker never called it.

The same hole ran through `fn_review_submit`, which wrote `author_agent` raw while `reviewer_agent`
was resolved — so a self-review would have been stored as two different strings, and **every
self-review count in this system is `author_agent = reviewer_agent`**. The reported zero would have
been a property of the spelling.

**Fixed and proven, on both projects:**

- one line in each function resolves the author before any comparison;
- a `BEFORE INSERT/UPDATE` trigger on `review_chain` canonicalises both sides and refuses when they
  are the same employee, so **a function writing the table directly cannot bypass it** — verified by
  inserting an alias self-review straight into the table and being refused, while an independent
  review passed and was **stored canonical** (`Finance Director` → `cfo`), so counts now measure
  employees rather than spelling;
- **0 of 10** departments self-approve through an alias, on production;
- **0** new self-review rows on production since the fix landed.

---

## §4 — 90-role runtime smoke test

`docs/agents/ROLE_RUNTIME_SMOKE_RESULTS.csv` — **270 rows** (90 roles × 3 scenarios: normal in-scope,
insufficient evidence, outside authority). Every scenario is generated from that role's own contract.

**Preconditions: 270/270 PASS.** Section 4 lists twelve requirements per execution; eight are
properties of the runtime *before* the model is called and are all measured here — canonical role id,
active department, active manager, role knowledge, department knowledge, tool policy, authority
result, declared output contract.

**Execution: blocked.** All 90 roles route to `anthropic/claude-sonnet-5` (large tier), and OpenRouter
returns **HTTP 402** for it. Six live runtime calls were made and all six recorded
`blocked_upstream`; `llm_attempt` shows `class_key = insufficient_credit`,
`breaker_state = opened_by_this`. The small tier succeeds at the same token size, so this is credit,
not an outage or a dead key.

Two instrument faults in my own harness were caught and fixed before they became findings — both by
the rule that **a check failing for 100% of a population is measuring the wrong thing**:

- `active_manager` reported 270/270 failing. Inside the `EXISTS`, unqualified `manager_role_id` bound
  to `org_role m`'s *own* column, so it asked "is this manager its own manager", which is false for
  everybody. Name capture.
- The remaining 3 failures were the CEO, who legitimately has no manager because above the AI chief
  executive is the founder. The check now says so rather than demanding the company invent an AI
  above its own CEO.

---

## §5 — Role-quality remediation

**Not run.** The four sampled roles (`brief` 0.885, `intel_director` 0.796, `knowledge_validator`
0.863, `channel_specialist` 0.850) cannot be retested: retesting is a model call on the large tier,
which is the blocked path. No score in this report is claimed as remediated, and nothing is labelled
independently certified.

---

## §6 — 86 category-overlay smoke test

`docs/agents/CATEGORY_OVERLAY_SMOKE_RESULTS.csv` — **86/86 preconditions PASS**, **86/86 structurally
cannot dispatch**.

Overlay resolution, canonical category, category knowledge retrieved, mandatory fields present,
regulatory material present, output contract, escalation path and return-to-accountable-role: all
86/86. The safety property is structural rather than behavioural — an overlay carries **no
`runtime_agent_key` at all**, so there is no identity for a dispatch authority to attach to. It is
knowledge the accountable role reads, never an actor that can send anything.

### One real gap, found and closed

**0 of 86 overlays carried a never-infer rule** — not in `forbidden_decisions`, and not anywhere in
their category knowledge (a search of every runtime-eligible `category_specialist` record for "never
infer", "do not infer", "never assume", "do not assume" and "must not assume" returned nothing).

All 86 declared a real forbidden list — dispatching to suppliers, approving a supplier, exposing
customer identity, unsupported legal conclusions, overriding a regulatory gate, taking over the
conversation. But that is a list of forbidden **actions**, and *inventing a missing fact is not an
action*, so it fell outside every clause. An overlay could not dispatch an RFQ, but nothing stopped it
supplying the specification, quantity, grade or tolerance the customer never stated — and the
accountable role would then dispatch that.

The single most consequential thing a category specialist can get wrong was the one thing its contract
did not mention, and it survived for the usual reason: an overlay that quietly fills a gap produces a
confident, complete-looking brief. Nothing fails.

`org_reorg_18` appends one clause to all 86, naming the specific facts that must come from the
customer, on both projects.

The behavioural half — minimum-sufficient questioning, incomplete brief blocked, unsupported claims
refused, regulatory escalation — needs the model and is blocked.

---

## §7 — Ten department workflows

Full results in [`DEPARTMENT_WORKFLOW_RESULTS.md`](DEPARTMENT_WORKFLOW_RESULTS.md). Every link of the
chain except execution is proven for all ten departments. Three findings there are **not** failures —
five departments legitimately escalate review outside themselves, `exec` correctly refuses to approve
the CEO's own work because above the CEO is the founder, and the `exec` backlog is the founder's own
standing decision.

---

## §8 — Both-project consistency

| | production `htdblwldjkcgjvmqkbeh` | staging `pglpqrhvozwepymcuunn` |
|---|---|---|
| git commit | see PR #385 head | same |
| active roles | 176 | 176 |
| active departments | 10 | 10 |
| runtime-eligible current knowledge | 8,256 | 8,256 |
| `org_role_identity` rows | 127 | 127 |
| `fn_org_role_violations()` | 0 | 0 |
| behavioural tests | 68/68 pass | 68/68 pass |

Every routine promoted this session matched **byte-for-byte** on both projects
(`md5(prosrc)` equal): `fn_context_slice`, `fn_knowledge_gap`, `fn_retrieval_probe`,
`fn_retrieval_leak_check`, `fn_task_tsquery`, `fn_agent_context_v3`, `fn_ai_route`,
`fn_ai_spend_guard`, `fn_budget_available`, `trg_ai_cost_attribute`, `fn_pick_reviewer`,
`fn_review_submit`, `trg_review_chain_no_self_review`.

**Production confirmations:**

- **No synthetic fixtures introduced.** The only fixture-shaped rows are the pre-existing
  `zz_probe_saturated` budget row (which is what proves the guard fires when a number is present) and
  the `ZZ DEMO` / `@example.invalid` supplier convention that predates this session.
- **No test notification reached a real user.** `founder_alerts` rows created since session start:
  **0**.
- **No real financial action occurred.** No Stripe call was made. Every spend-meter probe ran inside
  an aborted transaction; `ai_cost_log` rows matching `zz_probe%` remaining on production: **0**.
- **No route or automation unintentionally activated.** `org_tasks` created since session start: **0**;
  `review_chain` rows with a `zz_` subject: **0**.

### Production was running with its retrieval filter disabled — and now is not

`fn_context_slice` on production ended `tsv @@ p_q or true`, a tautology that disabled filtering
entirely. Confirmed by testing the **predicate with comments stripped**, because a substring search
for `or true` also matches the comment that says it was removed. All four helper routines
(`fn_task_tsquery`, `fn_knowledge_gap`, `fn_retrieval_probe`, `fn_retrieval_leak_check`) were absent
from production. All are now deployed and byte-identical, promoted in dependency order because the
new pre-flight correctly refuses to promote a body ahead of the routine it calls.

---

## Cost of this pass

| section | model calls | AED |
|---|---|---|
| spend meter, §1, §2, §3, §8 | 0 (all SQL and aborted-transaction probes) | **0.00** |
| §4 90-role smoke — preconditions | 0 | **0.00** |
| §4 live runtime probes | 6, all refused upstream | **0.00** |
| §6 86 overlays — preconditions | 0 | **0.00** |
| §7 ten workflows — chain | 0 | **0.00** |
| upstream credit probes | 6 (5 small tier, 1 refused large) | **< 0.01** |
| **total** | | **≈ 0.00** |

The budgeted AED 40–60 for §4 was not spent, because §4's model half did not run.

---

## What is unfinished, and why

**One thing, and it is the founder's:** OpenRouter has credit for the small tier but not enough to
afford a large-tier request. All 90 accountable roles route to `claude-sonnet-5`. Until that changes,
§4's execution half, §5 entirely, and the behavioural halves of §6 and §7 cannot run.

I did **not** work around it, and each refusal was deliberate:

- **Not by lowering `max_tokens`** to squeeze under the affordable ceiling. Measured over seven days
  of successful large-tier calls, p95 output is 3,499 tokens and the maximum 5,976; the currently
  affordable ceiling is ~1,454. That would truncate real answers mid-sentence, and §4 counts
  truncation as a failure. It would have been fabricating a pass.
- **Not by rerouting the 90 roles to a cheaper tier.** All 24 Reviewer/Auditor rows in the pack name a
  large model deliberately, and a reviewer on the cheap model is a green check that means nothing.
- **Not by substituting my own answers** for a disconnected runtime role, which §4 explicitly forbids.

The harnesses are built, committed and were exercised end to end against the live runtime. The moment
credit is available, `node scripts/agents/role_runtime_smoke.mjs --ref=<ref> --live=270` produces the
real §4 result with no further work.

**Also open, and named rather than implied:** 33 routines still compare an identity without resolving
it, 8 of which are approval routines that contain no self-approval check at all. The CI guard means
the list cannot grow.
