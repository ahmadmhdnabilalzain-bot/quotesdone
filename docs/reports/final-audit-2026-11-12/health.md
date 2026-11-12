# Production health — final audit, 11 Nov 2026 (seat: it_engineer)

Measured 22:32–23:00 UTC on project htdblwldjkcgjvmqkbeh, main 2cc9d1017. Reads only. No model call, no SQL apply,
no deploy, no switch touched. Windows are "last 24 h" unless stated. Evidence files are in this folder.

## VERDICT: GO WITH FIXES

Nothing in production's own records shows a broken supplier registration or sign-in path. One real supplier
(lead 19398, a real supplier) registered and was verified today, 06:43–06:53 UTC, end to end. Four things are broken
or unguarded right now and should be fixed before real traffic: the IT seat's hourly duties have not completed for 22 h,
the Claude cloud routines that replaced GitHub Actions do no work, one heartbeat step has a broken import, and real
customers would be sent to Stripe LIVE keys (no switch holds it). None stops a supplier registering tomorrow.

## What was checked

| # | Check | Pass bar | Measured | Result |
|---|---|---|---|---|
| 1 | Edge 5xx, real visitors | 0 | 0 of 150 AE-browser requests; all 1,241 5xx came from our harness, tagged test runs or internal callers | PASS |
| 1 | Worker kills (546) | 0 on a person's request | 129: conversation_archive 51 (internal, 8% of its 652 calls, last 17:01), embed_ml 38, site_assistant 36 (load test only), drawing_redact 4 | PASS for people, F7 |
| 1 | Slowest functions p95 | — | resilience_ping 73 s, marketing 52 s, drawing_boq 40 s, inquiry_intake 26 s, sales_engineer 22 s, site_assistant 12.7 s, license_extract 12 s, ai_gateway 10 s; public_site 0.8 s but 12 real-browser calls took 20–39 s | F6 |
| 2 | Functions = main | 78/78 | 77 MATCH, 1 STALE (voice_otp), 0 unverified; 78 in repo = 78 live; all ACTIVE | F10 |
| 2 | verify_jwt = config.toml | 0 mismatches | 0 | PASS |
| 2 | Vercel production | built from 2cc9d1017, READY | dpl_4SjQnoezXJyi2y9zjPhZwuh6tYRG, READY, 0 runtime errors 24 h; uptime probe 287/288 ok, 0 failed; 0 website error events in 8 days | PASS |
| 3 | Routine drift | 0 | repo→prod 0, prod→repo 0, uncommitted DDL 0; manifest gaps 1 (exit 1 on main) | F11 |
| 3 | MANIFEST / pending | consistent | 1,929 manifest entries, 0 missing files; 188 unlisted files = 188 pending notes (181 probes that are never applied, 7 others, each with a reason); 4 repo checks 24/24 tests pass | PASS |
| 4 | pg_cron | 0 failed | 106 jobs, all active; 31,563 runs, 0 failed, 0 failed in 8 days; seat duties 18 per minute on each of the 5 offsets (design: ≤18); busiest minute 27 jobs; longest run 24.1 s | PASS |
| 4 | Work behind cron | completing | fn_it_duties last ok 00:45 UTC; 62 timeouts since | FAIL F1 |
| 5 | Outbox stuck | 0 unexplained | 12 queued: 10 invitations held to 12 Nov 06:00 UTC (daily cap, by design), 2 WhatsApp to a real supplier queued 16 h with no reason | F8 |
| 5 | Duplicates since #1938 | 0 | 0 (1 real send since 11:00 UTC). Before it: 2 seed addresses got the seed twice (ids 137260/137389, 137286/137415) | PASS |
| 5 | supplier@ auto replies since #1939 | each appropriate | 0 sent; 0 inbound mail since 07:30 UTC; mailbox_reply_decision 0 rows | NOT EXERCISED |
| 6 | Rehearsal windows | none stale | 3 open, all opened 22:30–22:43 by sibling audit runs, unexpired; 60 opened in 24 h | PASS |
| 6 | load_stub | off | 0 open load_test windows (last closed 06:07 UTC) | PASS |
| 6 | Fixture residue | 0 from today | 0 from today older than 2 h; standing leftovers from earlier dates | F12 |
| 7 | Switches | as expected | see "Switches"; no unexpected state | PASS |
| 8 | Database | under limits | 3.74 GB of 19.3 GB disk (19%); 22–30 of 120 connections at the time of reading; 0 long queries; storage 19.75 GB of 100 GB | PASS (peak not measured) |
| 8 | Advisors | 0 ERROR, 0 new | security: 0 ERROR, 493 findings, 0 new against the 568-key baseline; performance: 0 ERROR | PASS |
| 9 | Seat duties | 0 failing | seat_duty: 162 enabled, 0 failing, 0 stale; heartbeat steps itduties and supportVoice failing all day | FAIL F1, F3 |
| 9 | Daily export | ran, includes new tables | last run finished 10 Nov 23:35 UTC (402 tables). support_case is in it. support_case_summary_version, support_case_promise and mailbox_reply_decision were created after it; all three are registered exported=true. Tonight's run had not started at 22:58 UTC | PASS / NOT YET RUN for the 3 new tables |
| 9 | Dropbox | draining | 34,092 done, last 22:34 UTC, 8 pending (minutes old), 1 error from 12 Oct; 102 of 452 runs warned on the Dropbox token endpoint and retried | PASS |
| 10 | No real card can be charged | confirmed | NOT confirmed: live Stripe keys are configured and used for every non-demo account | F4 |
| 11 | Scheduled cloud routines | doing their jobs | daily routine ran 28 s and did nothing (no repo access) | FAIL F2 |

## Findings

### HIGH

**F1. The IT seat's hourly duties have not completed since 11 Nov 00:45 UTC.**
Evidence: agent_runs `it_engineer` job=duties: 2 runs in 24 h against 151 in the 7 days before; last ok 00:45:27.
Finding `duty:heartbeat:itduties` "canceling statement due to statement timeout", 62 times, last 22:46. pg_stat_statements:
the `fn_it_duties` RPC averages 3.3 s, max 7.9 s; the authenticator role's limit is 8 s. Effect measured: findings it owns are
stale: six `duty:pack_ml_vectors:*` findings are still open although the routine now returns 0 rows missing a vector, and
646 `duty:delivery:request:*` findings are open although every one of their handoffs now reads done. 798 IT findings are
open in all. Cause not proven: `fn_pack_rows_without_fresh_ml_vector` alone takes 1.98 s, and section 4 settles one item per
unconfirmed delivery request. Smallest fix: run `fn_it_duties` from its own pg_cron job with `set statement_timeout='60s'`
(as the seat duties already do), or split section 4c out. The stale findings then close on the first good run.

**F2. The Claude cloud routines that replaced GitHub Actions run but do no work.**
Evidence: routine "QuotesDone daily jobs" fired 11 Nov 22:14:06, finished 22:14:34, status SUCCEEDED. Its own transcript
(session cse_01MHFn2q8pno6kTee9dWY4US) says none of the 5 jobs ran: empty container, `git clone` refused, GitHub API 403
"GitHub access to this repository is not enabled for this session". The weekly routine ran 21 s on 9 Nov; findings
`duty:workflow_heartbeat:platform` and `:dependency` say its readings have not arrived for 8 days. The CAD read worker
routine ran 31 s at 22:15 (not read; same environment). Not running: daily deploy parity, the advisor baseline, the embed
backfills, the CAD (DWG) read worker, weekly readings and the weekly journey. cad_read_jobs has 0 queued today.
Smallest fix: attach ahmadmhdnabilalzain-bot/quotesdone to the routines' environment (the routine asks for exactly this),
re-run each once and read the result; make a routine that cannot reach the repo end as failed.

**F3. A heartbeat step has a broken import: complaint and incident updates to people are never written.**
Evidence: `supabase/functions/resilience_ping/ticks/customer_support.ts:33` imports `'../_shared/duty_voice.ts'`, which
resolves to `resilience_ping/_shared/` (does not exist). Finding `duty:detached_supportVoice:supportVoice` "Module not found",
115 times since 10 Nov 00:46 UTC (the #1874 split), last 22:45. A scan of all 46 dynamic relative imports found only this
one. It carries `complaint.update`, `incident.holding`, `incident.resolved`. customer_support_voice_owed has 0 rows, so nobody
is waiting today. Smallest fix: change the path to `'../../_shared/duty_voice.ts'`, deploy resilience_ping, and add a check
that every literal `import('./…')` resolves.

**F4. Stripe live keys are in production and nothing holds them back.**
Evidence: app_secrets `stripe_secret_key` is an `sk_live` key and `stripe_publishable_key` a `pk_live` key (prefix class only
was read), both set 30 Jun 2026. `stripe_checkout/index.ts:62-74`: a demo e-mail gets the test pair, every other account
gets the live pair; there is no switch. The accountant's hourly reconcile read the live side as "measured" (0 invoices,
0 payment intents in 30 days), so the live key works. All 328 Stripe events, 7 payouts and the 1 transaction on record are
test mode or demo. What a real customer sees at reveal today: the normal card form on live Stripe for the 3% fee plus
processing. NOT measured: whether the live Stripe account has charges enabled (needs a Stripe call; `stripe_setup` reports
`charges_enabled` to an admin session). No real customer, inquiry or quote exists, so nothing was charged. Smallest fix if
the founder's decision is "no real card yet": one app_secrets switch read by stripe_checkout before the key is chosen, off
by default, answering a clear "payment opens soon" message; otherwise record that live charging is intended.

### MEDIUM

**F5. A loop is sending the founder's IT digest about 15 reports an hour.** Evidence: 117 pending `delivery.request`
handoffs from `ceo` marked digest=pending, created 15:16–22:45 UTC; 267 `support_ceo_report` rows from it_engineer today
(19 yesterday). Each says "New problem the IT engineer could not fix: Delivery request N from sales_engineer has had no
confirmed outcome". The findings behind them are the 646 stale ones of F1 (258 are last night's seed batch: 131 sent,
127 cancelled; 367 have no notification row left; all handoffs read done). Smallest fix: F1; then confirm the digest queue
empties, and close by hand what does not.

**F6. A service page waits about 19 s for its price box, and every crawler render costs a model call.** Evidence:
`src/components/PriceGuide.tsx:51-55` asks `public_site` `price_guidance` on mount for each /services/[slug]; that call goes to
the model. ai_gateway rows for `public_site`: p50 19.2 s, p95 30.2 s, max 35.0 s today (13 calls), same range for 8 days.
All 12 slow real-browser calls were this: 6 Baiduspider, 5 Singapore, 1 US. Cost today USD 0.027. Smallest fix: answer a
fixed slug topic from a stored trade (no model), or cache the answer per slug.

**F7. The licence text kept beside each supplier document has never been saved.** Evidence: 235 errors
`supplier_doc_trades.saveText … mime type text/plain is not supported` since 10:23 UTC, last 22:53; bucket `supplier-docs`
does not list `text/plain`; 0 `.read.txt` objects exist. Code re-reads a PDF when the copy is missing, but not a photo's
transcription (`_shared/supplier_doc_trades.ts:481-485`), so a supplier who uploads a photographed licence and later a
profile loses the licence text for the second reading. Smallest fix: add `text/plain` to the bucket's allowed types.

**F8. Transactional mail leaves on a 15-minute clock; two WhatsApp notices to the real supplier are stuck.** Evidence:
notifications 139627/139630 ("Thanks for registering") were created 06:47:48 and sent 07:00:59–07:01:06, 13 minutes later.
139628 and 139631 (WhatsApp, same supplier) are still queued after 16 h with no reason recorded: their template
`supplier_account_notice` is "missing" in wa_template_registry. Smallest fix: stamp the reason and expire a WhatsApp twin
after 72 h once its e-mail was delivered; drain person-facing mail every minute.

**F9. OpenRouter credit is USD 25.93 above zero, 5.93 above the alert floor.** Evidence: openrouter_meter 22:15 UTC:
credits 580, used 554.07; `openrouter_min_usd` = 20. Twilio prepaid balance USD 18.46, no floor recorded. Fix: top up
before the invitations (founder).

### LOW

**F10.** `voice_otp` is one shared file behind main (`_shared/site_origins.ts`, changed in #1874). Deploy it.
**F11.** `canonical_routine_manifest.mjs` exits 1 on main: `the_inquiry_interview_moves_to_the_model_eval_b_passes.sql` has
been pending over 24 h. Apply it with its MANIFEST line, or delete it.
**F12.** Standing fixture residue, none from today: 14 "ZZ DEMO Signup" customers and auth users from 2 Nov
(`delivered+qd-*-cust1@resend.dev`), 486 quote-files objects (44 MB) whose lead no longer exists (54 from 10 Nov),
2 table_export_registry rows for dropped tables (kb_chunks_old, kb_chunks_new), 18,788 doc_backups in prune_pending since
7 Oct, charge_audit row for the founderdemo transaction unresolved.
**F13.** Noise an outside developer will notice: 798 open IT findings; `support_reply_sla:*` counts fixture senders (all 8
real WhatsApp messages in 30 days were answered); kyc logged "signed PDF not produced" 9 times today (6% of supplier
acceptances, test runs; cause not established, compliance_archive answered 200 in the one traced); the routine status says SUCCEEDED when nothing ran (F2).

## Switches (names and non-secret values; 288 app_secrets keys, 203 withheld by name)

site_assistant_worker_turns = 7 (expected 7). invite_enabled = true, invite_m365_enabled = true, invite_lane_enabled = true,
invite_daily_cap = 15, invite_reachable_only = true, invite_open_tracking = 20, invite_ceo_ceiling = 0,
supplier_outreach_golive = true, wa_supplier_invite_golive = false, marketing_golive = false, meta_autospend_golive = false,
ceo_daily_number_golive = false, ceo_growth_act_golive = false, social_send_enabled = off, qa_mint_enabled = false,
wa_autoreply_enabled = true, wa_templates_ready = true, email_triage_enabled = true, ml_embed_golive = true,
supplier_terms_version = v17, customer_terms_version = v11. Not set, so on their code defaults: wa_typing_indicator (on),
voice_transcription_provider (off; hf_inference_token absent), wa_burst_quiet_ms, outbox_duplicate_window_min.
Prompt diet: no `decision_policy` row `prompt_diet`, so structural cuts on, content cuts off, as the memory note says.
No model circuit breaker is open. Note: with invite_enabled = true, 10 real invitations leave at 06:00 UTC on 12 Nov and the
next daily batch is built at 05:00 UTC.

## Not measured

Peak connection count (only the current reading and the 80% alarm, which has not fired). Stripe live `charges_enabled`.
The supplier@ reply gate on a real mail (none arrived). Whether tonight's export includes the three new tables (it had not
started). The weekly and CAD routines' transcripts (inferred from run length and the missing readings). Data-only SQL files
cannot be proved applied by the routine check. Performance advisors have no baseline, so "new" is unknown.

## Spend and teardown

Spend: USD 0 (no model call; `ai_cost_log` has no row from this workstream). I created no row, object, window or fixture in
production. The advisor check ran without `--refresh`. Rehearsal windows open now belong to other workstreams (run tags
f5b09c50, 71366940, evaldietaf13d1af).
