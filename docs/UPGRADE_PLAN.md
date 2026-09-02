# QuotesDone — Hardening & Upgrade Plan

**Written 2 September 2026. Step 3 of the founder's directive** (steps 1–2 — lifting
development freezes and wiring every agent/department connection — are being done by the
main session). This document owns *what to harden and upgrade* so the company can run
itself for a year with only the founder's email as an inbound human signal. It does not
re-freeze anything and it proposes **nothing that requires paid inference** — OpenRouter
stays off; embeddings are free/in-region.

All numbers below were measured directly against production (`htdblwldjkcgjvmqkbeh`) on
2 Sep 2026 via read-only SELECTs. Where a number is load-bearing it is cited inline.

---

## Executive framing — what the evidence says

The plumbing is sound. The instrumentation exists. **What is missing is the layer that
turns instrumentation into action without a human**: nothing escalates a red view to the
founder, most departments' agents are defined but never scheduled to *run*, the
self-evolution loop proposes but almost never lands, and the knowledge the agents act on
is 46% correct on its own exams. The freezes coming off make this urgent, not less so — a
company that acts more needs the feedback loops that catch it acting wrong.

Six load-bearing measurements:

| Signal | Measured | Reading |
|---|---|---|
| Cron health (24h) | 3234 succeeded, **0 failed** | Day-to-day execution is healthy |
| Failing view | `policy_consistency_weekly` timed out 31 Aug, **still red, no alert fired** | Views detect, nothing responds |
| Dept health | 6 of 15 depts **"no data"**, 6 **"at risk / no runs recorded for staff"**, 1 healthy | Most departments don't execute yet |
| Evolution loop | 48 proposed, 53 rejected, **1 implemented** | Loop runs but effectively never lands a change |
| Canary | **3 records, last 2026-07-03** | Canary mechanism exists but is dormant |
| Knowledge exams | 311 correct / 191 not_covered / 112 wrong / 45 partial | ~46% correct; 303 gaps or errors agents act on |

---

## 1. Resilience & Self-Healing — P0

**Current state (measured).** The mechanisms are already built and working:
- `dead_letter`: 122 total, **0 open** — the DLQ drains.
- `phase_c_event_outbox`: 34 delivered, 17 superseded, **0 stuck** — the real send path with
  `attempts`/`max_attempts`/`next_attempt_at`/`last_error` backoff columns is live.
- `refund_event_quarantine`: 0 — the money guard is armed and idle.
- `v_workflow_side_effects_without_executor`: **0** — every side effect has an executor.
- Monitoring views exist: `v_cron_failing`, `v_dead_letter_open`, `v_email_deadletter`,
  `v_ai_agent_health`, `v_department_health`.

**The gap.** Detection is not connected to response. `v_cron_failing` has surfaced
`policy_consistency_weekly` (statement timeout) since 31 Aug and it is **still red** — no
alert, no retry, no self-heal. `v_ai_agent_health` shows `ops_director` at **5 errors of 7
runs** and several agents whose `last_run` is 2–3 weeks stale, with nothing reacting. There
is no heartbeat check that distinguishes "agent healthy and idle" from "agent silently
dead" (the classic zero-cannot-tell-a-dead-guard-from-an-idle-system trap).

**Upgrades.**
1. **Founder-alert bridge (P0, S).** One deterministic cron (`fn_health_escalate`, ~5 min)
   that reads the existing red views (`v_cron_failing`, `v_dead_letter_open`,
   `v_email_deadletter`, agents with `errors_30d > threshold` or `last_run` older than their
   own schedule interval) and, on a *new* red condition only (dedupe on a
   `health_alert_seen` watermark so it never spams), enqueues one email to the founder via
   the existing outbox. This is the single most important upgrade in the document: it is the
   founder's only promised inbound signal, and it does not exist yet.
2. **Cron heartbeat / liveness (P0, S).** A view `v_cron_stale` = active jobs in
   `cron_registry` whose last `cron.job_run_details.succeeded` is older than 2× their
   schedule. Feeds the same alert bridge. Turns "0 failures" into "0 failures *and* everyone
   ran," closing the dead-guard blind spot.
3. **Statement-timeout fix for `policy_consistency_weekly` (P1, S).** Root cause is a
   full-table regex scan over `kb_chunks` (2.69M rows). Bound it to changed/reviewed chunks
   since last run, or move the regex to an indexed expression. Fix the one red job so the
   alert bridge starts from green.
4. **Auto-retry-then-quarantine for edge executors (P1, M).** The outbox already models
   backoff; extend the same `attempts/max_attempts/next_attempt_at` discipline to
   `org_action_executor` edge calls that currently fail terminally, then route exhausted
   retries to `dead_letter` with the executor's `compensation_action_class` (column already
   exists) invoked where reversible.

**Why it matters.** The founder will be absent for a year. "The company emails me if
something major breaks" is a literal requirement, and today nothing sends that email.

---

## 2. Observability — the founder must SEE it working — P0

**Current state (measured).** The data exists but is scattered across ~15 `v_*` views and
raw tables. `v_department_health` already computes a 0–100 score and a plain-English
`basis` string per department — genuinely good design. The OS/portal surfaces exist
(`os_pages`, `os_ops`, OsxShell.tsx).

**The gap.** There is **no single rollup** the founder can open and no periodic digest
pushed to him. Reading the true state today requires running 15 SELECTs. And the rollup
would currently show mostly red: 12 of 15 departments at "no data" or "at risk," which is a
*throughput* problem (§3/§4), not a display problem — but the founder can't even see that
framed.

**Upgrades.**
1. **`v_company_pulse` single-screen rollup (P0, M).** One view/RPC composing: department
   scores, agent health, cron liveness, open dead-letters, event throughput
   (1483 events/30d, 20 types, last 13:45 today — healthy), revenue-to-target, and the
   refund queue. Render it on the existing OS dashboard (memory notes the dashboard is still
   basic — this is the content it needs).
2. **Weekly founder digest email (P1, S).** Deterministic cron renders `v_company_pulse`
   to an email every Monday: "company ran itself this week — here's the one screen." This is
   the *positive* counterpart to §1's exception alert; together they are the founder's whole
   interface.
3. **KPI backbone wiring (P1, M).** `knowledge_kpis`/`knowledge_kpi_snapshots` and
   `department_objective` exist but the pulse must actually read revenue vs the AED-1M
   trajectory and each department's objective, not just task-throughput proxies. Today
   "score 50, no runs recorded" is measuring the wrong subject for a department whose real
   job is an outcome, not a task count.

**Why it matters.** "I will literally just check my email notifications." The company is
only *seen* to work if one screen and one weekly email say so truthfully.

---

## 3. Loop Throughput & Autonomy — safe self-evolution — P1

**Current state (measured).** `evolution_proposal`: 48 proposed, 53 rejected, **1
implemented**. A decider exists and is not a rubber stamp (rejects the majority — good).
`canary_records` (3, last Jul 3) and `phase1_rollback_log` exist. `phase_c_change_request`
/ `phase_c_freeze_amendment` govern frozen-scope changes.

**The gap.** The evolution loop is *proposing into a wall*. One implemented change in the
loop's lifetime means either the bar is miscalibrated or there is no safe path to *land* a
change unattended. Now that freezes lift, this loop is meant to be the engine of
self-improvement — but with a dormant canary and no rate limit, it is either inert (today)
or unsafe (if simply opened up). The guardrails must arrive *before* throughput does.

**Upgrades (guardrails that raise autonomy without re-freezing).**
1. **Reactivate canary as the mandatory gate for implemented proposals (P1, M).** Any
   `evolution_proposal` moving to `implemented` must first write a `canary_records` row,
   run against a sandbox/shadow population, and auto-promote only on a green canary;
   red canary auto-rolls-back via `phase1_rollback_log`. This is the safe path that lets
   the implement count rise above 1 without a human.
2. **Rate-limit self-change (P1, S).** A hard cap (e.g. ≤ N implemented proposals per
   department per week) enforced in the decider. Prevents a runaway self-modification storm
   while leaving steady evolution open. `ponytail:` a single count-per-window guard, not a
   scheduler — tighten only if throughput demands.
3. **Reversibility precondition (P1, S).** Refuse to auto-implement any proposal whose
   subject lacks a `compensation_action_class` / down-script. The executor registry already
   tracks reversibility; reuse it as the admission test.
4. **Decider calibration review (P2, S).** 53:1 reject:implement is worth one audit — is
   the bar right, or is it rejecting safe wins? Sample the 53 rejected with their evidence.

**Why it matters.** Self-evolution is how the company hits a moving target for a year
without feature changes. It must be *able* to change itself and *unable* to hurt itself.

---

## 4. Workflow / Agent Upgrades — recommend → act — P1

**Current state (measured).** `org_action_executor`: 89 total, **88 active**, with the
recommend-vs-act distinction fully modeled per action: `advisory_safe`, `notifies_human`,
`unattended_ok`, `required_authority`, `second_authority`, `risk_tier`, `reversible`,
`compensation_action_class`. 46 RPCs allow-listed. `v_executor_registry_gaps` lists ~a
dozen executors with registry-completeness gaps — notably all **low-risk and reversible**
(artifact.review, agent.train, video.produce, eval_run, security_scan…), so these are
metadata gaps, not safety holes.

**The gap.** The binding constraint is **not** missing executors — it is that most
departments' agents **never run**. `v_department_health`: growth, marketing, evolution,
sales, bizdev, customer_success all "no data / no runs recorded for staff"; finance, legal,
customer_experience, marketplace, people_ops, product_eng, data_intel all "at risk / no
runs recorded." Only assurance (93) and exec (75) actually execute. The capability exists;
the *cadence* does not (finished-capability-with-no-entry-point, at department scale).

**Upgrades.**
1. **Schedule the silent departments (P1, M).** For each department with a defined agent
   roster and zero runs, register the pg_cron cadence that invokes its agents (this is
   step 1–2's connectivity made *periodic*). Sequence: start read-only/advisory agents
   first, confirm they produce sane recommendations in `agent_actions`, then flip
   `unattended_ok` per action as evidence accrues. Do not mass-enable acting on day one.
2. **Close the executor registry gaps (P2, S).** Fill the ~12 rows in
   `v_executor_registry_gaps` (idempotency/owner metadata) so `fn_company_connectivity_register`
   stays at zero gaps as agents start acting.
3. **Promote proven advisory actions to unattended (P1, ongoing).** Use `agent_actions`
   history (auto_done 802, done 392, dismissed 1024) to identify action classes that
   consistently produce accepted recommendations, and graduate them from `advisory_safe` to
   `unattended_ok`. This is the safe human-in-loop-removal path: promote on evidence, per
   action class, reversibly.

**Why it matters.** A department that only recommends is a department the founder must
staff. The target requires them to act — safely, and only after they've proven they
recommend correctly.

---

## 5. Data & Knowledge — freshness, retrieval, exams — P1

**Current state (measured).** `kb_chunks`: **2,686,026 chunks across 407 categories** —
enormous coverage. `v_kb_review_due`: 16 due. Embeddings are free/in-region
(`Supabase.ai gte-small`). Knowledge exams graded to date: **311 correct, 191 not_covered,
112 wrong, 45 partial, 13 unverifiable** (672 total, ~46% correct).

**The gap.**
- **Retrieval is keyword, not vector** (confirmed: `kb_usage_log` records `query`/`category`
  with no vector path; matches the standing memory). Vector retrieval is *free* here, so the
  company is leaving quality on the table for zero cost.
- **191 not_covered + 112 wrong = 303 exam items** where agents either have no knowledge or
  hold *incorrect* knowledge — and they act on it. The exam harness already finds these;
  nothing feeds them back into ingestion.

**Upgrades.**
1. **Turn on vector retrieval where it's free (P1, M).** Route the retrieval RPCs through
   the existing embedding index instead of keyword match. Zero inference cost, directly
   lifts every downstream agent's answer quality. Highest quality-per-effort item here.
2. **Close the exam feedback loop (P1, M).** A cron that takes `knowledge_exam_results`
   verdict `not_covered`/`wrong` and enqueues a targeted (free-embedding) ingestion or
   correction task, then re-exams. Convert the 303 gaps/errors into a shrinking backlog
   instead of a static score.
3. **Freshness SLA on review-due (P2, S).** Wire `v_kb_review_due` (16) into the §1 alert
   bridge so stale knowledge is surfaced, not just queryable.

**Why it matters.** "Internal communication 100% accurate so targets are reached." An
agent acting on wrong knowledge is confidently wrong at scale, unwatched, for a year.

---

## 6. Launch Readiness — before real customers/payments — P0 gate

**Current state (measured).** The real-traffic paths exist but are cold: outbox has moved
only 34+17 messages; `refund_event_quarantine` and `agent_pending_actions` are empty; the
marketplace funnel history is fixtures (per standing memory: "the funnel was all
fixtures"). Money safety is correct at rest: `auto_action_max_aed=0`, refunds route to
founder, MFA gates money moves, ledgers immutable.

**The latent risk.** The paths that *only fire with real traffic* have never carried it:
first real customer inquiry → quote → reveal → payment → refund; first real supplier
registration; the Stripe webhook → `stripe_events` → ledger path. These are exactly the
paths memory has repeatedly caught misbehaving only under real conditions
(harness-seeds-an-order-reality-cannot-produce; supplier-funnel 81 invited / 0 registered).

**Upgrades / launch-gate checklist.**
1. **Sandbox full-funnel rehearsal (P0, M).** Using the established `ZZ DEMO` /
   `example.invalid` fixture convention, drive one end-to-end journey through the *real*
   code paths (not seeded rows): inquiry intake → parse → match → quote → reveal (2 emails +
   2 notifications per the reveal rule) → Stripe test-mode payment → founder-gated refund.
   Assert each hop's event, executor, and ledger row actually appears.
2. **Real-send soak, founder-approved (P0, S — gated).** A time-boxed soak where the outbox
   actually sends to internal addresses, watching for rate/429 behavior
   (production-429-during-sweep is a known failure mode). Crosses the effects line → needs
   the founder's explicit go per the launch plan's boundary.
3. **Pre-launch invariant sweep (P0, S).** Re-run `fn_company_connectivity_register` (0
   gaps today) plus the §1 heartbeat and §2 pulse, and require all-green as the literal
   launch gate. Launch only when perfect, in a sandbox first — the founder's stated bar.

**Why it matters.** Launch is one-way. Every fixture-only path is an untested path, and the
founder won't be watching when the first real one fires.

---

## 7. Security & Compliance — P1

**Current state (measured).** Authority model is real: 46-entry RPC allow-list
(`org_action_executor_rpc_allowed`), `required_authority`/`second_authority` per action,
MFA on money moves, refund→founder, immutable `gl_journal`/`decision_trace`. `security`
agent runs 718×/30d with 0 errors. PDPL surfaces exist (`compliance_archive`,
`collections_legal`, retention crons).

**The gap.** As §4 flips agents from advisory to `unattended_ok`, the authority model faces
its first real load — an executor gaining `unattended_ok` without correct
`required_authority` is the drift to fear (a-rule-at-intake-is-not-a-rule-at-the-decision).
Credential handling for the coming real Stripe/email traffic must be audited once, not
assumed.

**Upgrades.**
1. **Authority-on-promotion gate (P1, S).** Make it structurally impossible to set
   `unattended_ok=true` on an executor whose `required_authority` is null or whose
   `risk_tier` is high without `second_authority`. A CHECK/trigger, reusing the existing
   columns — the promotion path from §4 must pass through it.
2. **Credential & allow-list audit before soak (P1, S).** Confirm every secret the
   real-send/Stripe paths read is present and scoped, and that the 46-entry RPC allow-list
   contains no entry that shouldn't act unattended. One deterministic pass, gated before §6.2.
3. **PDPL retention proof (P2, S).** Verify the retention/erasure crons actually execute on
   real customer data shapes (not fixtures) as part of the §6 rehearsal — a compliance path
   is also a latent path.

**Why it matters.** UAE PDPL and the money model are the two places where "confidently
wrong, unwatched" becomes a legal or financial event, not just a bad metric.

---

## Phased roadmap

### Immediate (this week — zero-cost, under the hold, no founder decision needed)
- **§1.1 Founder-alert bridge** + **§1.2 cron heartbeat** — the missing inbound signal. *(P0)*
- **§1.3** fix `policy_consistency_weekly` timeout so alerting starts from green. *(P1)*
- **§2.1 `v_company_pulse`** rollup on the OS dashboard. *(P0)*
- **§5.1 vector retrieval** on (free) + **§7.1 authority-on-promotion gate**. *(P1)*

### Near-term (next 2–4 weeks — zero-cost, safe autonomy)
- **§4.1** schedule the silent departments, advisory-first. *(P1)*
- **§3.1 canary reactivation** + **§3.2 rate-limit** + **§3.3 reversibility precondition**. *(P1)*
- **§5.2 exam feedback loop**; **§2.2 weekly digest**; **§2.3 KPI wiring**. *(P1)*
- **§4.2/§4.3** close registry gaps; graduate proven advisory actions. *(P1–P2)*

### Launch gate (founder boundary decision required — crosses money/effects line)
- **§6.1 sandbox full-funnel rehearsal** (fixtures, no real effects — can start now). *(P0)*
- **§7.2 credential/allow-list audit**, then **§6.2 real-send soak** (founder go). *(P0)*
- **§6.3 pre-launch invariant sweep** all-green as the literal launch gate. *(P0)*
- **§7.3 PDPL retention proof** inside the rehearsal. *(P2)*

**One-line definition of done for this plan:** the founder can open one screen that tells
the truth, gets one email only when something breaks, and every department both runs and
acts — safely, reversibly, on correct knowledge — without him.
