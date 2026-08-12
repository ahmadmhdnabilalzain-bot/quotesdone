# Next session prompt — finish what is pending

Copy everything below the line into a new session.

---

Start with the clock: `select now() at time zone 'utc';` — Dubai is UTC+4. Don't report the OpenRouter
balance, but DO tell me if it's refusing calls.

THE STANDARD. The company can operate, learn, manage itself, identify problems, make professional
decisions, improve its performance, and actively work toward **AED 1,000,000 by end of July 2027**
with minimal founder involvement. Not "the agent exists". Every item below is yours to build, fix or
decide. **I decide three things only: Stripe refunds, spending money, and the three go-live
switches.** Everything else — architecture, agents, org structure, workflows, KPIs, learning,
observability, orchestration, thresholds, policy numbers — is yours. Do not ask me to choose a
number you can measure your way to. You are the technical master here. Keep going until I say stop.

Read `docs/sessions/HANDOVER_2026_08_12_*` parts 1–6 first. 13 PRs merged 12 Aug (#275–#286), both
projects. State at handover: Row #3 **127/152** · gates 23/23 both · parity IN SYNC · 0 undocumented
crons · **0 literal project refs** (was 19) · 0 false T&C certificates · backups running again
(461 MB, 21 tables) · 1 confirmed supplier · 1 customer · **0 inquiries** · 3 go-live switches false.

## 1 — THE DEMAND DOOR. Settle the phone gate by EXECUTION, not inference.

`create_inquiry` refuses until `customers.phone_verified`. I claimed the number on file
(`+971 4 258 7734`) is a Dubai landline Twilio cannot SMS. **That claim is unverified and may be
wrong — do not repeat it.** What is measured: Twilio is fully configured (`twilio_account_sid`,
`twilio_api_key_sid`, `twilio_api_key_secret`, `twilio_verify_service_sid`, `twilio_from`,
`twilio_wa_from` all set), and `toE164()` turns that number into a valid `+97142587734`.

Settle it properly: read `app_secrets.sms_enabled`'s actual VALUE (I never did); call the Twilio
Verify API with that number and read the real error code; check the Twilio console — you have browser
tools and the connection. Then either make SMS verification work for my number, or establish from
Twilio's own response that it cannot be delivered and build the alternative (WhatsApp Verify is
already configured — `twilio_wa_from` is set). **The goal is that I can complete verification**, not
a diagnosis.

Then close the loop: intake `18e2c133-f728-464a-b5f1-43d1f9dc3c1e` is `ready`, and
`fn_match_capability` already returns lead 30466 MERIDIAN MEP at score 5.0 for that HVAC brief.
`tos_accepted_at` is null and `kyc accept_terms` sets it before signing — that is mine to click, but
if the phone gate is the only thing standing between me and it, get me to the box. **Do not fabricate
an inquiries row.**

## 2 — Invites. Decide and run the ramp yourself.

`invite_enabled` is false. All 5 bounces were role addresses on live MX; role 8.6% of 58 sent,
personal n=4; next run would queue 9 named humans. **You own the reputation call and the ramp.** Set
the cap, start it, watch the bounce rate, and stop it yourself if it degrades. Supply is the
constraint on AED 1M: 20,470 leads, 1 confirmed supplier.

## 3 — BoQ fixtures. Download a real drawing and test.

Do not wait for me. Pull a genuine construction/MEP drawing PDF from the internet, run it through
`customer_api analyze_drawing` → `drawing_boq` → `drawing_redact`, and prove the BoQ extraction and
redaction path end to end on staging. Fixtures follow the existing convention (`ZZ DEMO —` names,
`@example.invalid` emails) — never on production.

## 4 — dr_drill. Backups run; nothing verifies they restore. Next drill 1 Sep.

PR #286 fixed `backup`: pages at `${stamp}/${table}/page_NNNN.json`, chained across invocations
(30s slices, self-POST, 40-hop cap), resumable mid-table, manifest carries `layout:'paged'` and a
per-table `pages` count. Verified on production: 21 tables, 0 failed, 460,906,951 bytes, kb_chunks
95,983 rows / 96 pages with 96 objects confirmed present.

`dr_drill` still downloads `${day}/${tbl}.json` (~line 70). **Dead ends already measured — do not
repeat:** concatenating pages into one array → 546 at 62s; streaming each page into `dr_restore` →
546 at 93s; **table-level chaining → 546 at 110s, because one table alone exceeds the budget**
(kb_chunks = 96 pages ≈ 192 inserts of 500). It needs **page-level resumption**: carry
`{table index, page index, rows restored}` and stop between two pages of the same table.

Keep: wipe `dr_restore` **only on hop 0**; old single-file fallback; assert page count against the
manifest; and do not weaken `restored_rows === backup_rows`, `key_ok`, or `emptyBackupOfLiveTable`.
Credential for manual calls is `app_secrets.cred_cron_backup`, not `cred_db_internal`.

## 5 — Reflection budget. Decide the number yourself.

`fn_workflow_step_sweep` now counts DISPATCHES not completions (PR #282), so
`decision_policy.workflow_reflection_steps_per_day` = 6 binds for the first time and reflection work
drops from ~32/day to 6. I do not know what that number should be — **you decide it from evidence**:
what those steps produce (`health_report`, `forecast`, `coordinate`), what they cost, and what the
company loses at 6. Set it, record why, and move on.

## 6 — Instruments still reporting on the wrong subject

- `ai_spend_probe.pct` is a **percentage** for department scopes and a **ratio** for `company_daily`
  (1.09 = 109%). Same column, two units. No decision is wrong today; any cross-scope reader would be.
- `fn_operations_ai.open_recommendations` counts `agent='operations_ai'`, but a trigger renames rows
  to `ops_director` — 6 of 32 `ops_recommendation` rows sit under the renamed key. Latent today
  because all are closed.
- `fn_backup_watch` dedupe suppresses every repeat while an alert stays pending. That is why a
  two-day backup outage produced exactly one email (agent_action 2662, 11 Aug, still pending).
- 95 `ai_cost_log` rows still carry no `dept_key` (was 884) — functions that are neither an executor
  nor tied to an employee, so they sit outside the automatic spend ceiling.
- The knowledge exam rotation couples two populations: employees and trade categories share one
  round-robin over 233 keys at 6 sittings/day, so adding categories silently slows how often every
  employee is examined.

## 7 — s36, and the rest of Row #3

s36 has its three columns (`assumptions`, `expected_impact`, `cost`) and 13 edge call sites + 6 SQL
routines fill them; ~600 of 1,311 recommendations/30d still carry NULL. It stays MISSING until every
writer states them AND 30 days roll over — correct, not a shortfall. Finish the remaining writers.

Time-blocked, no work needed: `explain-knowledge-used` (13 Aug) · `s24` (5 Sep) ·
`explain-alternatives-considered` (as escalations arrive) · `employee-learning-progress` (~mid-Oct;
133 of 233 keys still unexamined at 6/day before any second sitting) · `s33` (outcomes are opened
weekly by `fn_kpi_review`/`fn_os_improve`, the replay is daily).

Correctly MISSING, do not chase: `s32` (`learning_speed` is deliberately NULL — the routine says
so) · `what-if-*` (rewriting a stored simulation changes an answer the company may have acted on) ·
`s26-discover-suppliers` (Apify paused to ~Feb 2027).

## 8 — Spec #3 UI. Untouched, and my judgement of the screen stands.

I opened the OS dashboard on 10 Aug and it was basic. Nothing was done to it. A useful lens found
this session: **22 tables over 200 rows have no UI-reachable reader** — computed with the blueprint's
own `uiClosure`, so it matches the scorer's definition. Following two of them found real defects
(`supplier_score`, `action_execution`). The rest are still unread: `employee_knowledge` (900),
`ai_quality_snapshots` (1,167), `scenario_expectation_baseline` (3,324), `internal_credential_audit`
(1,760), `marketing_library`, `catalog_subcategories`, `subcategory_agent_map`, `field_definition`.

## 9 — Pack scorecard has not run

`scripts/kb/pack_scorecard.mjs` needs `--packs=<extracted packs dir>` and **no such directory exists
in the working tree**. Six knowledge packs are unscored. Find or reconstruct the packs source, then
run it on both projects.

## 10 — Housekeeping I caused

PR #276 swept in generated files that were already dirty (`graphify-out`, `deno.lock`,
`.claude-flow`), and there is a commit on `main` whose entire content is a regenerated
`.claude-flow/neural/stats.json`. Decide whether those belong in git at all and act.

## Traps that cost time — do not rediscover

- `apply_sql --promote` carries only the routine definition. A REVOKE or DML in the same file lands
  on staging alone. There is now a guard that **refuses** to promote a routine containing a literal
  `https://<ref>.supabase.co`; all 19 offenders were converted, so do not reintroduce one.
- Every `cron.schedule` needs a `cron_registry` row **in the same change**, or s38 drops Row #3.
- `_` is a word character in Postgres regex. `least()`/`greatest()` ignore NULLs.
- BEFORE triggers fire in **name** order — that is what `a00_` prefixes are for.
- A cron reporting `succeeded` for a `net.http_post` only means the request was **queued**.
- `WORKER_RESOURCE_LIMIT` (HTTP 546) kills the isolate, so the function's own catch block never runs
  and nothing is logged. Absence of an `agent_runs` row is the signal.
- Read the dates. A 24h failure window keeps showing failures fixed hours earlier.
- Guards that refused me and were right: `leads_approved_implies_verified`, `fn_org_authority_guard`,
  and qd_guard refusing any SQL file that names the production ref — even in a comment.

## The lens that keeps working

Four related questions found almost every defect this session, none of which had *failed*:
**is this number measuring what its name says?** · **has this recovery path ever actually run?** ·
**what does the user CLICK to reach this?** · **what does this table know that no screen shows?**

Verify by execution in the same turn. Aborted-transaction probes for writes. Never fabricate,
back-date or mass-close data to turn a gate green. Deploy to BOTH Supabase projects, merge via PR,
and run the end-of-session sweep before the one line.
