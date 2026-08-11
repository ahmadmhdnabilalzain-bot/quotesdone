# NEXT SESSION — the AED 1M target cannot reach a single employee

Written 2026-08-11 ~17:20 UTC, immediately after the founder set the governing principle:

> THE COMPANY CAN OPERATE, LEARN, MANAGE ITSELF, IDENTIFY PROBLEMS, MAKE PROFESSIONAL DECISIONS,
> IMPROVE ITS PERFORMANCE, AND ACTIVELY WORK TOWARD AED 1,000,000 IN REVENUE BY AUGUST 2027 WITH
> MINIMAL FOUNDER INVOLVEMENT.

Measured against that standard on production the same hour. **This is not a list of weaknesses. It
is one defect, and it is structural.**

---

## THE FINDING — the goal→department→employee chain has no edges

```
company_goals                63 rows, 8 measurable
  └─ revenue_annual  "Reach AED 1,000,000 annual revenue"  target 1,000,000 AED
     owner_dept finance · measure_sql PRESENT · horizon year_1        <-- the target EXISTS
        |
        |   NO LINK.  os_objective has no column referencing company_goals at all.
        v
os_objective                 50 rows, 50 of 50 measurable, keyed by os_key
        |
        |   NO LINK.  org_tasks.objective_id is NULL on ALL 839 rows.
        v
org_tasks                    839 rows, 0 with an objective
        |
        |   NO LINK.  org_tasks carries dept_key but no employee assignment column.
        v
employees                    93 active · 14 with NO responsibilities recorded
                             agent_expectations: 121 rows / 121 distinct "agents" — CRON JOB NAMES,
                             not employees. Employee KPIs are effectively ZERO.
```

**Every layer the founder described exists and is individually healthy. Not one of them is connected
to the layer above it.** The company has a revenue target it can measure and 839 open tasks, and
nothing in the database says those tasks are for that target.

This is, verbatim, three items from his own failure list:

- *"management cannot translate company goals into departmental objectives"*
- *"KPIs are missing or meaningless"*
- *"departments cannot identify their own performance problems"*

---

## WHY THIS IS THE FIRST THING, AHEAD OF EVERY REMAINING PHASE-8 ITEM

His social-media example is the test. The department is supposed to notice engagement falling,
decide it costs conversions, and change what it posts. It cannot: no objective it owns is linked to
revenue, so "engagement fell" and "revenue is short" are two unrelated facts in two unrelated tables.

His category-specialist example is the same test from the other end. A thin inquiry spec →
suppliers cannot quote → conversion drops → revenue lost. Management is supposed to trace that back
to the employee, the prompt or the knowledge source. **There is no path to trace along.**
`org_tasks.root_cause` exists as a column and the graph it would need does not.

Every other outstanding item — OCR, vision routing, the exception scenarios, model cascading —
makes an individual employee better at its job. **None of them lets management find out that the job
was the wrong one.** Do this first.

---

## THE WORK, in order

### 1. Give the chain its edges (the whole point)

- `os_objective.company_goal_key` → `company_goals.key`. 50 objectives, 63 goals; the mapping is a
  judgement call per objective and is mine to make, not the founder's.
- `org_tasks.objective_id` is already there and is NULL 839/839. **Find out why nothing sets it**
  before adding anything — a column that exists and is never written is usually a writer that was
  never finished, not a missing column.
- `org_tasks.assigned_agent` → `org_agents.agent_key`. Today a task belongs to a department, so no
  employee owns anything and "report results back to management" has no subject.
- Backfill is not optional: 839 existing tasks with no objective are 839 pieces of work nobody can
  justify.

### 2. Make the target flow down, by routine and not by hand

`fn_goal_attainment` already reports honestly (8 of 63 measurable — the `least(100,NULL)` fix
landed). What does not exist is the **decomposition**: a routine that takes `revenue_annual`, splits
it across the departments that can move it, and writes departmental objectives with their own
`measure_sql`. Management must derive the method — the founder said explicitly he will not define it.

**The 55 unmeasurable company goals are the same defect one level up.** A goal with no `measure_sql`
cannot be missed, so it cannot pull anything down, so no department can be told it is failing.
Either give each one a measure or retire it. Do not leave 55 goals that are decorative.

### 3. Employee KPIs that are about employees

`agent_expectations` holds cron job names. This is the fourth vocabulary collision in this database
(see the audit's identity table). An employee KPI needs: the employee key, the metric, the target,
the measure, and the objective it serves. Then `fn_agent_context` can put "your KPI, your current
number, your department's objective, and the company goal it serves" in front of every employee —
which is what turns his twelve bullet points from aspiration into prompt text.

### 4. The 14 employees with no responsibilities

They cannot have a role, expertise, or a KPI. Either write their responsibilities or remove them.
93 employees of whom 14 do not know what they are for is not an org chart.

---

## THE 96 `model_policy_by_identity` ROWS — decided, per the authority granted 11 Aug

The founder handed this back as an engineering decision. **Neither delete nor alias nor wire as-is.**

Measured: 47 of the 96 name `deepseek/deepseek-v4-flash`, 35 name `claude-sonnet-5`. Everything on
the expensive path runs sonnet-5 today, so honouring them would likely REDUCE spend — the earlier
framing of "changes the model for 94 employees, therefore money" had the direction unexamined and is
corrected here.

But the shape is wrong for the operating model. Per-employee model policy addressed to a
`<department-slug>-<role>` text key that nothing maintains is a second identity vocabulary, and this
codebase already has four. **The decision: the policy belongs on the employee record.** `org_agents`
already carries department, title, seniority, manager_key and resolves 100%. The pack's 4-role
taxonomy — Director / Analyst-Controller / Operations Specialist / Reviewer-Auditor — is genuinely
good config and becomes the SEED for a `routing_tier` on `org_agents`, mapped from seniority and
title, then read by `fn_ai_route`.

**Sequenced behind §1–§3 deliberately.** Routing an employee to a cheaper model is worth money;
management being able to see what that employee is FOR is worth the company. The 96 rows are inert
and labelled in the table's own comment, so nothing degrades while they wait.

---

## WHAT IS ALREADY GOOD AND MUST NOT BE REBUILT

Stated because the founder's instruction is explicit that working components are not to be rebuilt.

- **`os_objective`: 50 of 50 measurable.** The OS layer got measurement right. Copy its pattern
  upward to `company_goals`, do not replace it.
- **`org_agents.manager_key`: 93 of 94 set, every one resolving, acyclic.** The reporting line is
  real. Departmental objectives can hang off it today.
- **The review chain** — 1,557 rows across 7 stages, with rejections, revision requests and holds.
  Management already refuses bad work; it just cannot yet say which goal the work served.
- **`fn_agent_context`** now delivers identity, company genome, risk register, authority limits,
  live state, retrieved department knowledge and (as of today) external UAE regulations, in 765 ms.
  It is the delivery mechanism for everything in §3. Extend it; it is not the problem.
- **The dress rehearsal harness** (`scripts/rehearsal/`) proves a chain end to end and tears it down
  with score equality. Every change in §1–§3 should be proved through it.

---

## STATE AT WRITING

```
employees 93 active (14 without responsibilities) · departments 25
company_goals 63 (8 measurable) · os_objective 50 (50 measurable) · org_tasks 839 (0 with objective)
AED 1M goal: company_goals.revenue_annual — EXISTS and IS measurable, owner_dept finance
Row #3 126/152 · gates 23/23 both · parity IN SYNC · corpus integrity ok
kb_chunks 95,841 · 0 duplicates · trade/regulation/material/library 100% embedded
```
