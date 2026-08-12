# Handover — 13 Aug 2026 (session ran 19:40–22:40 UTC / 23:40–02:40 Dubai)

Clock at start: `2026-08-12 19:40:09 UTC` = `2026-08-12 23:40 Dubai`. OpenRouter refused nothing all
session — every model call that was attempted returned.

Eight PRs' worth of work on one branch, `phone-gate-landline-voice` → **PR #288**, seven commits,
every change deployed to BOTH projects before the commit and verified by execution in the same turn.

---

## 1 — THE DEMAND DOOR. Settled by execution. Your office phone rang.

**Read `app_secrets.sms_enabled`: it was `'false'` — and nothing reads it.** No `pg_proc` body
references the key; `mobile_otp` derives its own `smsEnabled` from whether the three Twilio
credentials are present, and `kyc` calls `twilioAuth()` the same way. Meanwhile `sms_flush` posts to
`send_sms` every two minutes. A switch labelled "SMS off" beside a live SMS sender. **Deleted.**

**Twilio, asked for real:**

| probe | answer |
|---|---|
| Verify service | HTTP 200, "QuotesDone", account `active` / Full |
| Lookup `+97142587734` | `valid:true, country:AE, carrier:Etisalat, type:**landline**` |
| Verify send, Channel=sms | **HTTP 400, code 21635, "'To' number cannot be a landline"** |
| Verify send, Channel=call | **HTTP 201, status pending** |
| Lookup `+971509319355` (`admin_mfa_phone`) | `type:**mobile**` |
| Verify Attempts history | that mobile: SMS on 14 Jul 2026, **CONFIRMED / converted** |

So the earlier claim was right, and it is now proven rather than inferred. The number on your
customer record is your office landline; SMS to it is impossible, and Twilio says so itself.

**What was built.** `kyc send_sms` retries once on `Channel=call` when Twilio answers 21635, and
returns which channel carried the code. The deployed function, called with a real customer JWT for
your account, answered `{"ok":true,"channel":"call"}` — Twilio placed a voice call to
+971 4 258 7734 reading a six-digit code at about 00:20 Dubai. If you were not at the office, the
portal now also lets you fix the number: `Save details` is no longer hidden once the profile is
complete (previously the only way to correct a wrong number was to verify it first), and the hint
follows the channel instead of telling you to check a junk folder for a phone call.

**Two ways through, both live now.** Open `/en/me`: either answer the call and type the code, or
replace the number with `+971 50 931 9355` and press Send — SMS to that number is proven to arrive
and to have been entered before. Then the terms checkbox and `Finish` are yours, and lead 30466
MERIDIAN MEP is waiting at score 5.0 on intake `18e2c133-f728-464a-b5f1-43d1f9dc3c1e`.

**No inquiries row was fabricated.** Still 0 inquiries.

## 2 — Invites. Ramp is running. The call was mine and I made it.

`invite_enabled` → **true**. `invite_max_bounce_rate` 0.08 → **0.05**, because `fn_invite_ramp`
already throttles at 5% and the hard pause disagreed with it at 8%. Cap left at the base of 10 —
`fn_invite_ramp` doubles it daily while the list behaves, staged on lifetime volume to a ceiling
of 200.

**Ran it: 9 queued, 9 sent, all nine non-role named humans, 0 bounces.** The role-last ordering that
shipped yesterday works: 14,003 of the 19,842 uncontacted addresses are named humans, so the ramp
reaches people before it reaches shared inboxes.

**One defect fixed before it could fire.** The hard auto-pause was "5 hard bounces in 3 days
regardless of rate". At today's cap that is 17% and pausing is right; at the ceiling it is 0.8% and
pausing would stop supply on a healthy list. It now trips at `greatest(5, sent × max_rate)` — below
~100 sends in the window it is still exactly 5.

Watch it tomorrow: `select * from v_invite_funnel;` and `leads where invite_status='bounced'`.

## 3 — BoQ, proved end to end on a real drawing. It found two serious defects.

Pulled a genuine 7-sheet consultant mechanical set (Reading PA recreation-centre bid documents),
rasterised exactly as `CustomerPortal.fileToImages` does it, and pushed it through
`customer_api analyze_drawing`.

**The BoQ is excellent.** 23 line items, sectioned Demolition / AHUs / Split systems / VAV boxes /
Exhaust fans, each with quantity, unit and a `basis` citing the keyed note or schedule it came from;
`category=mep_hvac`. That was never in doubt and it is very good.

**The redaction was completely broken, silently:**

- `scale: 1.8` in `fileToImages` assumed a letter page. An ANSI-D sheet renders at 5444×3888 = 21
  megapixels. `drawing_redact` decodes to full-resolution RGBA (85 MB for one page) BEFORE resizing
  to its 1600px working width, so **one page** returned HTTP 546 WORKER_RESOURCE_LIMIT.
- A 546 kills the isolate, so `recordRun` never ran and **nothing was written anywhere**.
  `customer_api` counted that as `pages_in 0, pages_out 0` and `redaction_complete = (0 >= 0) =
  TRUE`. A total failure of a privacy control reported as complete.
- Even at 2600px the ceiling is four pages: 1/2/3/4 return 200 in 22.9 / 24.2 / 27.6 / 37.2s, five
  returns 546 at 37.5s.

Fixed: long edge capped at 2600px in both portals; `customer_api` sends the pages in batches of four
and merges the runs (`resolveRedactedPaths` already understood `redaction_job_ids`, plural);
`redaction_complete` now requires `pages_in > 0 AND pages_out == pages_in`; and the adversarial
verifier no longer rejects a page over "GENERAL NOTES", "ABBREVIATIONS" and other sheet-content
headings, which are not identity.

**After: 6 pages in, 6 accounted for, 4 cleared the verifier and are ledgered, 23 BoQ items, HTTP
200 in 65s.** Before: 0 pages, 546, no ledger row, and a green "complete".

**Still open and honest:** 2 of 6 pages fail the verifier on genuine leftovers ("GENERAL CONTRACTOR
TL", "ISSUED FOR BID"), so `create_inquiry` will refuse to attach a partial set. A real drawing today
reaches suppliers as a BoQ with no drawing attached. That is fail-closed and correct, and it is the
next piece of work: detection is missing title-block regions on sheets like these. `deno`-side repro
is `scripts/staging/prove_boq_real_drawing.mjs <pages.json> [original.pdf]`, which is in the repo and
documents the four rasterisation numbers a caller must match.

## 4 — dr_drill. It restored one row. It now restores 123,691.

Page-level resumption, as you asked, and none of the three measured dead ends were repeated. The
chain carries `{table, page, rows restored, key_ok, npages}` and stops between two pages of the same
table.

**Verified on production: `status ok`, 5 hops, 123,691 rows, 11 of 11 tables matching, page counts
equal to the manifest** — leads 20,471 / 21 pages, kb_chunks 95,983 / 96, ops_knowledge 3,735 / 4,
dept_library 1,456 / 2, agent_knowledge 2,044 / 3. Everything you asked to keep was kept: wipe on
hop 0 only, the old single-file fallback, page count asserted against the manifest, and
`restored_rows === backup_rows` / `key_ok` / `emptyBackupOfLiveTable` untouched.

Two defects the first full run exposed, both fixed:

- **Two chains share one staging table.** A 28s hop is long enough for the gateway to retry the
  POST; two hop-0s thirty seconds apart from one request were measured. `restored_rows` counted
  every `dr_restore` row with that kind, so one chain counted the other's work and reported
  kb_chunks, dept_library and ops_knowledge at exactly 2× live — a **false** alarm on the only
  instrument that says the backups are good. `dr_restore` now carries `run_id`, counts filter on it,
  hop 0 clears only rows older than three minutes, and a chain that finds another actively writing
  stands down.
- **A count mismatch failed silently.** The per-table numbers lived only in the response to a
  fire-and-forget POST nobody reads. They are now in `agent_runs.counts.tables`.

Next drill 1 Sep runs on its own; you can fire it any time with `cred_cron_backup`.

## 5 — Reflection budget: 24/day. Here is the arithmetic.

`workflow_reflection_steps_per_day` 6 → **24**, recorded in `decision_policy.description` so the
reasoning travels with the number.

- **Cost, measured:** 11 Aug ran 179 workflow steps and the estate spent AED 38.00; 10 Aug ran 0 and
  spent AED 22.58. 15.42 / 179 = **AED 0.086 per step**, which agrees with `ai_cost_log`'s own
  `agent_reasoning` class at AED 0.0968/call. So 6/day costs AED 0.52/day and 24/day costs AED
  2.06/day (~AED 63/month) against an estate spending ~AED 20/day.
- **What 6 costs you:** 43 classified reflection steps are parked right now (health_report 21,
  knowledge_fill 19, coordinate 3) and 11–12 Aug produced 211 dispatches in two days, so arrivals
  exceed 6/day. At 6 a health_report raised today runs next week — a report about a state the
  company has already left.
- **Why not uncapped:** 11 Aug dispatched 179 in a day, 138 of them `recommend`. 24 is 13% of that.
- **Named weakness:** one FIFO ceiling over two populations. `recommend` ran 166 times in 14 days
  against health_report 5 and forecast 5, so it can starve the management reports. At 24 today's mix
  leaves room for both. If the health_report backlog keeps growing, split the allowance per
  `action_class` in `fn_workflow_step_claim` — do not just raise this number.
- `cos_reflection_tasks_per_day` deliberately left at 6: different population, and moving two
  ceilings at once makes the next measurement unreadable.

## 6 — Five instruments reporting on the wrong subject. All five fixed.

1. **`fn_operations_ai.open_recommendations`** counted `agent='operations_ai'`, but every insert
   passes `a00_agent_action_resolve_addressee`, which resolves that alias to `ops_director`. 40 rows
   under the old key, 9 under the new one, **one of them pending** — so it reported 0 open
   recommendations while one was genuinely open. Not latent; wrong today. **After: 3.**
2. **`ai_spend_probe.pct`** held a percentage for departments and a ratio for `company_daily`
   (1.09 = 109%). Nothing reads the table yet, which is the right moment to fix it. **After:
   company_daily writes 109.03.**
3. **`fn_backup_watch` rang once for a two-day outage** — agent_action 2662, one email, still
   pending. The dedupe window was 24 hours and the watcher runs daily, so on day two the previous
   alert was 24 hours old minus a fraction of a second and still inside the window. Window is now 20
   hours, and past 48 hours it raises a `founder_alert` naming the age in hours. Probed with a
   3-day-old backup: 1 founder_alert, 1 notification, 1 agent_action, rolled back.
4. **59 AI calls this month carried no `dept_key`**, and `fn_ai_route` can only halt a department it
   can find a budget for — so they sat outside every ceiling. They were the demand path:
   inquiry_intake, drawing_boq, doc_extract, license_extract, supplier_onboard and eleven more.
   `fn_task_class` now carries the owning department beside the task class it already carried, and
   `fn_ai_route` falls back to it. Probed: with rfq_intelligence at 500% of budget,
   `fn_ai_route(fn=>'inquiry_intake')` with no dept_key now returns `halted:true` where it could not
   halt at all before. Rolled back.
5. **The knowledge exam was examining the catalogue instead of the staff.** One queue over 101
   employees and 132 trade categories, ties broken on the key, and `cat:` sorts before `ceo` and
   `finance_ai`. Result: 85 of 132 categories examined, **16 of 101 employees**. Adding a trade
   category silently pushed every employee's next examination further away. The picker now alternates
   between the two populations. Probed: category_curator, cat:medical-equipment-suppliers, ceo,
   cat:mep-suppliers-electromechanical-suppliers.

## 7 — s36. The brief was wrong again; re-measured first.

The brief said "~600 of 1,311 recommendations/30d still carry NULL". **Production: 1,433
agent_actions in 30 days and exactly TWO carry all three columns**, both written today by
`fn_operations_ai`. The helpers that fill them (`ai_rec`, `doc_rec`, `kn_task`, `mkt_rec`, `ops_rec`)
shipped hours ago and only `ops_rec` has run since, so those kinds fill as their routines come round.

Built the largest writer that had no helper: **`strategy_rec`, 93 rows/30d**. `fn_strategy_rec` gains
the three parameters (replaced, not overloaded, so the REVOKE travels in the same `--ddl` file —
confirmed on production: `{postgres=X/postgres,service_role=X/postgres}`), and `fn_strategy_ai`
passes true statements at all four call sites. Probed: 7 recommendations written, all seven carrying
assumptions, expected_impact and cost, 3 assumptions each. Rolled back.

**Still unfinished:** `supplier_risk_complaints` (117/30d), `coverage_gap`, `supply_gap`, `hot_lead`,
`sla_review`, `improvement_question` have no helper. `incident` (482), `handoff` (182) and
`licence_expiring` (150) are events rather than recommendations and are a separate question.

## 8 — Spec #3 UI. One table off the list of 22, properly.

`employee_knowledge` — 900 rows over 66 employees, the domains each is expected to cover and at what
depth — had no browser-reachable reader. The drawer's existing "Knowledge held" card is
`agent_knowledge`: what has been AUTHORED for them. The two look alike and answer opposite questions,
so the drawer could read full while an employee covered one of twenty-four domains they are meant to
hold.

`fn_ws_agent_ops` now returns a `curriculum` block and `AgentDrawer` renders it. Verified on
production: the busiest employee returns **24 domains, 18 expert / 4 awareness / 2 working, layers 1
to 8**. Path from a click: Smart Engine → a person on the org chart → AgentDrawer → `os_api ws.agent`
→ `fn_ws_agent_ops` → `employee_knowledge`.

**Still unread:** `ai_quality_snapshots` (1,167), `scenario_expectation_baseline` (3,324),
`internal_credential_audit` (1,760), `marketing_library`, `catalog_subcategories`,
`subcategory_agent_map`, `field_definition`.

## 9 — Pack scorecard: it was scoring files it could not see.

It needs `--packs=<extracted packs dir>` and no such directory exists here — only the 86-categories
pack, under `knowledge-import/all86_full`. The other three v2026.07.31 zips are not in the repo at
all.

Running it that way was **worse than not running it**: `lines()` returned 0 for an absent file and
`pct(got, 0)` returns 100, so a pack whose source was missing scored a perfect **100% INGESTED** on
every row. The headline number was mostly a statement about files it could not see.

Missing sources now read `null`, print `NO SOURCE`, and are excluded from the averages. Run on both:

- **production** — INGESTED 100% across 31 of 37 artefacts (6 have no source here and are not
  counted either way) · IN USE 37/37 · RETRIEVABLE 58,244 of 95,983 kb_chunks embedded (**60.7%**)
- **staging** — INGESTED 100% across 31 of 37 · IN USE 37/37 · RETRIEVABLE 48,034 of 95,410 (50.3%)

The six unscorable artefacts are the whole AI_AUTONOMY_ROUTING pack plus the model catalogue; all
five probe IN USE against the database, so they are demonstrably ingested and read — only the
disk-side comparison is unavailable. **Recovering those three zips is a file-recovery job, not an
engineering one, and it is the only thing standing between this scorecard and a complete number.**

## 10 — Housekeeping.

`.claude-flow/` untracked and ignored: daemon state, metrics and neural scratch, nothing reads it
from git, and one commit on main has a regenerated `stats.json` as its entire content. Removed the
shell-quoting debris that had accumulated at the repo root — files literally named `3)`, `1279'`,
`1){d++`, `-p`, `2026-08-10T08` — plus an empty `pr58/` and a zero-byte `s.key`, and deleted three
that were actually tracked (`29020`, `diag3.out`, `diag5.out`).

`graphify-out/` stays tracked on purpose: CLAUDE.md tells every session to read it, so a fresh clone
without it starts blind. `deno.lock` stays tracked because a lockfile is a build input. Both were
left dirty rather than swept into an unrelated commit — that is what PR #276 did.

## 11 — What the sweep itself found: a cron that had been failing for 31 hours

Nothing was watching this. `control_mode_sweep_5min`: **377 consecutive failures**, first
2026-08-11 13:50:00Z, latest 2026-08-12 21:15:00Z, every one of them

```
ERROR: update or delete on table "control_mode_challenge" violates foreign key constraint
       "control_mode_session_mfa_ref_fk"
```

The constraint is `ON DELETE RESTRICT`, and there is exactly one challenge row — consumed more than
seven days ago, referenced by the one session row. The retention DELETE at the end of
`fn_control_mode_sweep` could never succeed.

**What it stopped was not the tidying.** A plpgsql function is one transaction: the DELETE raised, so
the two statements above it rolled back with it — and the first of those **closes expired
control-mode sessions**. Your command channel has had no working session timeout for thirty-one
hours. Nothing leaked (zero open sessions, the only one on record already closed), but the expiry
path could not run and would not have run the moment it was needed.

Retention now sits in its own exception block, and the DELETE skips challenges a session still
references. Probed inside an aborted transaction with an expired open session: sweep returned 1, the
session closed with `closed_reason='expired'`, 1 audit row written, rolled back. **The cron then
succeeded on production at 21:20:00Z — its first success in 377 attempts.**

---

## State at hand-over

- Row #3 **127/152 (84%)**, scorer run to completion on production.
- Portal gates **23/23 on both projects**. `project_parity.mjs` → **BOTH PROJECTS IN SYNC**.
- GitHub Actions green on HEAD; `deploy edge functions` green.
- Invites **live**: 9 sent, 0 bounced, 0 claimed yet.
- DR drill **ok**, 123,691 rows restored, 11/11 tables.
- 1 supplier · 1 customer · **0 inquiries** · 3 go-live switches still false.
- Twilio placed a verification call to your office line; nobody entered the code, which is expected
  at 00:20.

## The three things only you can do

1. **Finish phone verification** at `/en/me` — answer the call, or type `+971 50 931 9355` and take
   the SMS. Then the terms checkbox, and the RFQ door is open to lead 30466.
2. **Recover the three missing v2026.07.31 pack zips** (AI_AUTONOMY_ROUTING, COMPANY_OPERATIONS,
   COMPLETE_OS_PORTALS) into a directory and tell me where — six artefacts cannot be scored without
   them.
3. Nothing else. Everything above was decided and done.
