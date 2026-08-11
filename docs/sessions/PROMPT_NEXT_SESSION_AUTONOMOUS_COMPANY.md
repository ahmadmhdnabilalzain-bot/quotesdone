# SESSION PROMPT — build the company that can reach AED 1M on its own

Copy everything below the line into a new session.

---

Read `docs/sessions/NEXT_SESSION_THE_COMPANY_CANNOT_SEE_ITS_OWN_TARGET.md` first — it carries the
measurement, the ordering and the decisions already made, so you do not re-derive them. Then
`docs/sessions/HANDOVER_2026_08_11_PHASES_1_TO_7.md` for what landed on 11 Aug and what did not.
The `quotesdone-session` skill applies automatically.

The specs are the contract, all eight:

```
C:\Users\Opera\OneDrive\Desktop\quotesdone archeticture.txt
C:\Users\Opera\OneDrive\Desktop\OS.txt
C:\Users\Opera\OneDrive\Desktop\OS 2.txt
C:\Users\Opera\OneDrive\Desktop\customer portal.txt
C:\Users\Opera\OneDrive\Desktop\supplier portal.txt
C:\Users\Opera\OneDrive\Desktop\suppliers categories.txt
C:\Users\Opera\OneDrive\Desktop\quotesdone agents and knowledge.txt
C:\Users\Opera\OneDrive\Desktop\open router.txt
C:\Users\Opera\Downloads\QuotesDone_*_v2026.07.31.zip   (all six)
```

Start with the clock: `select now() at time zone 'utc';` — Dubai is UTC+4. Do not report the
OpenRouter balance; I top it up and it does not gate your work.

## THE STANDARD — this is the only definition of done

> THE COMPANY CAN OPERATE, LEARN, MANAGE ITSELF, IDENTIFY PROBLEMS, MAKE PROFESSIONAL DECISIONS,
> IMPROVE ITS PERFORMANCE, AND ACTIVELY WORK TOWARD AED 1,000,000 IN REVENUE BY AUGUST 2027 WITH
> MINIMAL FOUNDER INVOLVEMENT.

Not "the agent exists". Not "the workflow runs". Not "the table was created".

The one business objective is **AED 1,000,000 revenue by August 2027**, and it must flow downward:
management decides what departments must achieve, departments decide what employees must achieve,
employees decide how to execute. I do not define the method. The system derives it.

Every AI employee belongs to a department, has defined responsibilities, develops real expertise,
knows its department's objectives, receives tasks and priorities from management, reports results
back, has measurable KPIs, is monitored against them, learns from outcomes and failures, improves
its methods, coordinates with other employees, and owns the operational decisions in its scope.
Management operates the same way. A failure is traced up the chain to the employee, workflow,
knowledge source, prompt or rule that caused it, corrected, and the KPI re-checked.

A knowledge gap is never answered with a weak guess: retrieve company knowledge, consult a
specialist, research through an approved tool, request what is missing, raise a knowledge-gap task,
escalate to a manager, then learn from the outcome.

## YOUR AUTHORITY

Technical architecture, agent design, role allocation, org structure, workflow design, KPI
implementation, learning mechanisms, management hierarchy, observability and orchestration are
**yours to decide and do**. If an agent is missing, if two should be one, if one should be several,
if a department is wrong, if responsibilities sit with the wrong agent, if KPIs are meaningless, if
management cannot supervise, if agents cannot learn or communicate, if decisions are untraceable, if
knowledge does not reach the employee that needs it, or if a workflow blocks autonomy — **correct
it.** Build on good work, repair bad work, connect disconnected work, replace what fundamentally
prevents the intended behaviour. Do not preserve bad architecture because it exists. Do not rebuild
working components for tidiness.

Escalate only what cannot be inferred from the AED 1M objective, existing policies, commercial
rules, the business model, the specs, or the operating model above. Stripe refunds still need me.

## THE FIRST THING — measured on production 11 Aug 2026

Every layer exists and is individually healthy. **Not one is connected to the layer above it.**

```
company_goals    63 rows, 8 measurable
  revenue_annual "Reach AED 1,000,000 annual revenue" — EXISTS, measure_sql PRESENT, owner finance
     |  NO LINK — os_objective has no column referencing company_goals at all
os_objective     50 rows, 50 of 50 measurable, keyed by os_key
     |  NO LINK — org_tasks.objective_id is NULL on ALL 839 rows
org_tasks        839 rows, 0 with an objective
     |  NO LINK — org_tasks carries dept_key, no employee assignment
employees        93 active, 14 with NO responsibilities recorded
                 agent_expectations = 121 CRON JOB NAMES, not employees. Employee KPIs ~ zero.
```

The company has a revenue target it can measure and 839 open tasks, and nothing says those tasks are
for that target. Work in this order:

1. **Give the chain its edges.** `os_objective` → `company_goals`. Find out why
   `org_tasks.objective_id` is NULL on all 839 rows *before* adding anything — a column that exists
   and is never written is a writer that was never finished. Add employee assignment to `org_tasks`.
   Backfill the 839.
2. **Make the target decompose by routine, not by hand.** A routine that splits `revenue_annual`
   across the departments that can move it and writes departmental objectives with their own
   `measure_sql`. The 55 unmeasurable company goals are the same defect one level up: measure them
   or retire them, but do not leave 55 decorative goals.
3. **Employee KPIs that are about employees** — employee key, metric, target, measure, and the
   objective it serves — then put "your KPI, your number, your department's objective, the company
   goal it serves" into `fn_agent_context` so every employee sees it.
4. **The 14 employees with no responsibilities.** Write them or remove them.
5. Then the rest of the 171 ABSENT, in value order: OCR + Drawing Intelligence, inbound WhatsApp
   that can *act* (design is in the hand-over §7 — it needs `EdgeRuntime.waitUntil`, because
   `agent_brain` runs to 70s against Twilio's 15s wall and `wa_inbound` has no `MessageSid`
   idempotency), vision routing, the 13 uncovered exception scenarios, the 5 missing workflows,
   `fn_edit_inquiry` leaving quotes live after a post-quote requirements change (spec #7 L1351),
   cost per OS, Maturity Index, delete-proposer, remaining spec #3 UI gaps. Model cascading only
   after the output contract carries a confidence.

Already decided, do not re-open: the 96 `model_policy_by_identity` rows are neither deleted nor
aliased nor wired as-is — the policy moves onto `org_agents` as a `routing_tier` seeded from the
pack's four-role taxonomy, sequenced after 1–4.

## WHAT MUST NOT BE REBUILT

`os_objective` (50 of 50 measurable — copy its pattern upward). `org_agents.manager_key` (93 of 94,
all resolving, acyclic). The review chain (1,557 rows, 7 stages, real rejections and holds).
`fn_agent_context` (765 ms, carries identity, company genome, risk register, authority limits, live
state, retrieved department knowledge and external UAE regulations — extend it). `kb_search` (already
hybrid; probed, six of six results semantic). The rehearsal harness in `scripts/rehearsal/` — use it
to prove every change end to end and tear it down with score equality.

## HOW TO WORK

**Verify by execution in the same turn**, on a non-zero effect, never on an HTTP 200 —
`quote_compare` returned `{ok:false}` at HTTP 200 for weeks. Use the aborted-transaction probe for
writes. Deploy to **both** Supabase projects. Merge via **PR**, never straight to main. Never weaken
a check; if a fix makes one harder because the old pass was false, say so in the commit.

**Never state anything you are not 100% sure of.** A narrow check never licenses a broad claim.
Session briefs carry reliable counts and unreliable diagnoses — **five diagnoses died on measurement
on 11 Aug**, two of which would have cost a day each. Re-measure before building the fix a brief
proposes.

**Traps.** `least(100.0, NULL)` = 100.0. BEFORE triggers fire in **name** order. `revoke … from
anon` is a silent no-op under PUBLIC; revoke from PUBLIC. Every SECURITY DEFINER function you
**CREATE** is granted EXECUTE to PUBLIC — `CREATE OR REPLACE` preserves the ACL, and a new signature
is a new CREATE (that is how the 3-arg context function ended up anon-readable). `fn_agent_context`
ignores any `p_max_chars` below 22,000 — always call `fn_agent_context_capped`. PostgREST runs as
`authenticator` with `statement_timeout=8s`. A PARTIAL scorer run is not a score — look for
`N/152`. Do not run the pack scorecard against a project while the Row #3 scorer runs. Vercel builds
fail non-deterministically on a `next/font/google` module; a Redeploy with build cache unchecked
clears it, mechanism unknown, do not assert one. The PR edge-function typecheck resolves the root
`package.json` against Deno's 24-hour dependency-age floor — pin, never disable. Signature parity is
not behaviour parity.

**End-of-session sweep, every time:** GitHub Actions (a zero-step job means quota, not code), Vercel,
both Supabase projects, Row #3 scorer to completion, pack scorecard on both, `fn_os_portals_gates()`
on both, `project_parity.mjs` → BOTH PROJECTS IN SYNC.

## STATE AS OF 2026-08-11 ~17:20 UTC — do not re-derive

main `5e8ae59` · production READY on quotesdone.com · Row #3 **126/152** · gates **23/23 both** ·
parity **IN SYNC** (197 edge fns, 418 tables, 846 functions, 155 triggers, 0 tables without RLS,
56 anon-executable SECURITY DEFINER, 95 empty prod / 255 staging) · pack scorecard INGESTED 100%,
IN USE 37/37, RETRIEVABLE 46.6% · advisors 0 ERROR · corpus integrity ok · `kb_chunks` 95,841 with
0 byte-identical duplicates, `trade`/`regulation`/`material`/`library` 100% embedded · demand side
still zero (customers 0, inquiries 0, quotes 0, transactions 0) · `content_drafts` holds 1 genuine
marketing draft awaiting my review · `demo_rehearsal_active` false, 0 notifications held.

**Do not stop and do not check in. Take the next item. Keep going until I say stop.** If you hit a
hard limit that makes further work unreliable, hand over honestly and name exactly what is
unfinished — a truthful hand-over is worth more to me than a green tick.
