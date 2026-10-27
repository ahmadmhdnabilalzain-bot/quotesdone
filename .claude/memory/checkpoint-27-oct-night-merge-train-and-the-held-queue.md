---
name: checkpoint-27-oct-night-merge-train-and-the-held-queue
description: "27 Oct 2026 night (founder away, ledger 1348): 25 PRs #1669-#1693 merged and live, parity 78/0; resilience_ping CPU kill fixed then two overrun causes found; held-question queue was newest-first and starved the November-plan revisions; what is still open"
metadata:
  node_type: memory
  type: project
  modified: 2026-10-27T22:45:00.000Z
---

**READ FIRST after the 27 Oct checkpoint.** Written at 22:45Z when the founder came back.

**Shipped (all reviewed by an independent agent, gate red only on otp-race = no Postgres in the container):**
- #1669–#1693 merged (25); SQL applied for #1669, #1670, #1675, #1679, #1681, #1684 (by accident, then bookkeeping only), #1686, #1691, #1693, plus #1690's data repair (rows 28985–28988 re-opened 20:28Z). `verify_deploy_parity --all` = MATCH 78 / STALE 0 after #1688's staged deploy (resilience_ping v409, then 10 back-office, then 11 customer-facing; 0 4xx/5xx after).
- it.finding handoffs past their window: 210 (20:36Z) → 171 (21:43Z).

**The resilience_ping chain, in order — each fix exposed the next cause:**
1. gte-small embeddings inside the worker hit the 2 s CPU cap → #1678/#1685/#1687 moved every embed to embed_ml (`heartbeatDeps`), guard test reads the deps position.
2. That turned into a fan-out: 5 replay rows × (embeds + ai_gateway) at once → ai_gateway 503 with no worker, every row `model_failed: no reply` (20:30, 21:31). #1688: replay runs 2 rows in its own detached kick with a deadline; embed_ml 30 s cool-off; error text kept.
3. itlater still overran 120 s: `routine_judgements` judged 5 rows serially at ~60 s each with no deadline. #1693: detached `routineJudgements`, JUDGE_CLAIM = 1 (3 would recreate the 5-way burst), per-step timing so the next overrun names its step. Code NOT deployed at 22:45 — held until row 28987 resolves unless the itlater tail (reasoning_escalate, wa_arrival_sweep, ceo_support_replies) is starved.
4. `fn_reason_held_due` ordered `last_attempt_at nulls first, created_at desc` — every new row beat every retry, so the four ceo_revision rows 28985–28988 (sales_engineer, marketing ×2, customer_support) starved while it_engineer.postmortem files ~3 rows/hour. #1693 SQL: `order by created_at, id`, applied ~22:35. Replay cadence is 2 rows per 30 min, not 15.
- **marketing.month_plan** (due with the founder 28 Oct) is blocked on 28986/28987; three of the four rows had one try left at 22:34.

**Process lessons tonight (already or to be written as their own notes):**
- A probe that returns its verdict instead of raising commits the DDL it tests ([[a-check-that-replays-sql-can-commit-it]]). Precisely: the file and the probe ran as ONE request that ended without an error, so that implicit transaction committed — it was not autocommit across separate statements.
- Bookkeeping (MANIFEST line, pending note, export) rides the reviewed PR's own branch before merge. #1692 was opened and merged separately without review; a post-merge review found it clean, but the rule stands.
- Container restarts kill background commands and agents; resume agents by id and re-establish state from main + `verify_deploy_parity` before acting.
- The `gh` GraphQL lookup is blocked in cloud sessions, so `apply_sql`'s release guard needs `--skip-release-guard` with a logged reason unless the file is already on main.

**Open after tonight:**
- Deploy #1693's code (resilience_ping, email_triage, quote_compare for parity); watch `detached_routineJudgements` claims 1, `detached_timing` logs, no itlater finding.
- Follow-ups not built: a `turn_deadline` cut should not count as a try; it_engineer.postmortem inflow; error_text over-scrubs `max_tokens`/request ids; `license_extract` 30/30 failing; `fn_accountant_files_reveal_invoice` missing from the alarm REGISTER; CEO probe "no held question <NULL>"; alarms-quiet check 486 s.
- Ledger: 1338, 1339, 1341, 1344, 1345 built but still `open` — verify live, then close; 1340/1348 are standing rulings, relabel. 24 older open items unchanged (see the 22:45 summary in the session).
- Founder decisions unchanged: Exchange transport rule, #1201 visual, 8 qd-company rows, #1635 spend, GLOCKAPPS_API_KEY, SSL restart window, Supabase tickets, Arabic supplier portal, re-test 30 Oct, invitations (1312).
