# The IT failures of 18–21 September 2026, by cause

Seat: it_engineer. Measured 21 Sep 2026 09:18–09:50 UTC against `htdblwldjkcgjvmqkbeh`, read-only
(`scripts/qsql.mjs`; every probe rolled back). Window: 18 Sep 00:00 UTC to 21 Sep 09:18 UTC.

The founder said: *"check all IT failures during the last few days. i got plenty of emails"*.

## What he received, per day (so it can be matched to the inbox)

Rows in `public.notifications` with `to_role='founder'`, `requested_by='it_engineer'`, `channel='email'`,
`status='sent'`. Each email had a WhatsApp twin (same count, 1 still queued on 21 Sep).

| Day (UTC) | Emails | Of which "N new problems" digests | "CEO has not answered" | SCHEDULER DOWN |
|---|---:|---:|---:|---:|
| 18 Sep | 10 | 7 | 2 | 1 |
| 19 Sep | 6 | 3 | 2 | 1 |
| 20 Sep | 5 | 2 | 2 | 1 |
| 21 Sep (to 09:18) | 4 | 2 | 1 | 1 |
| **Total** | **25** | 14 | 7 | 4 |

The CEO's own `founder_brief` (one a day, `to_role='admin'`) is not an IT email and is not counted.

## The 25 emails were 11 causes

"Emails" below counts the emails the cause produced or appeared in (a digest line counts the digest once).

| # | Cause | First seen | Count in window | Emails | Root cause (measured) | Fix (this PR) | Prevented by |
|---|---|---|---:|---:|---|---|---|
| 1 | **The IT detector was blind for 50 hours.** `fn_it_detect` cancelled every tick at PostgREST's 8 s statement timeout; no `it_watch_tick` row since 19 Sep 07:30Z. | 19 Sep 07:30Z | `duty:heartbeat:itdetect` seen 112×; `it_engineer` error rows 204 | 1 (detect_tick_blind) + causes 2 and 3 below | `agent_runs` 7-day baseline grew 62,203 → 88,181 rows, 40,368 of them `fn:ai_gateway` written in three ~6,000-row/hour bursts (19 Sep 07:26Z, 20 Sep 07:47Z, 21 Sep 08:01Z — the scheduled "kb embedding backfill" runs). The routine scanned the 7 days three times and ran two per-row predicates ~100,000× each; timed read-only at **10,999 ms**. | `the_it_detector_reads_agent_runs_once_and_no_subject_can_flood_it.sql`: one bounded slice (newest 5,000 rows per agent), predicates evaluated once, four arms read it. Rolled-back execution: **4,141 ms**, 52,743 rows, 2 subjects capped, published in `notes.slice`. | Check §2: 20,000-row synthetic flood, must finish < 6,000 ms. |
| 2 | **"SCHEDULER DOWN — automation stalled"**, one a day. | 18 Sep 03:47Z | 4 | 4 | `fn_cron_liveness` read `it_watch_tick offset 1` — the detector's own record — as the scheduler's heartbeat. The scheduler ran every 15 min (201 `fn:resilience_ping` rows, all ok, since the detector went blind); the "1,276" and "2,730 minutes" were the detector's silence. Same wrong subject fixed for D3 on 18 Sep, missed here. | `the_liveness_check_reads_the_scheduler_not_the_detector.sql`: reads `agent_runs` `fn:resilience_ping`. Rolled-back run: healthy=true at 1.5 min. | Check §1: source must read `fn:resilience_ping`, must not read `it_watch_tick`. |
| 3 | **"The CEO has not answered an IT report: a founder_alert did not arrive (sent_unconfirmed / not_sent)"** | 18 Sep 02:45Z | 10 reports | 4 + 9 digest lines | Two defects. (a) `send_whatsapp` never stored Twilio's SID: 24 of 24 WhatsApp rows 'sent' since 18 Sep have `provider_message_id` NULL, so the delivery watch returns `sent_unconfirmed` and escalates (the email twin was sent and confirmed in every case: 0 of 25 without a provider id). (b) The `delivery_undelivered:*` report family had no CEO decider, so every report sat 'sent' past its window and the silence watch paged him once per report. The 8 `not_sent` ones on 17–18 Sep were WhatsApp rows queued for hours while `send_whatsapp` was starved (fixed by #745's plan). | `send_whatsapp/index.ts` stores `res.sid` as `provider_message_id`. `the_ceo_answers_the_report_families_it_had_no_answer_for.sql`: `fn_ceo_delivery_undelivered_decide` accepts when the provider confirmed it or the email twin was sent; `fn_it_ceo_silence_watch` asks the CEO first and dedupes the page per family per day. | Check §3, §4, §5. |
| 4 | **"The CEO has not answered an IT report: Dropbox backup coverage has been failing for over 48 hours (refile_not_verified_in_48h)"** | 18 Sep 05:00Z | 3 reports | 3 | Two `backup.refile` handoffs (28974 since 15 Sep, 38862 since 18 Sep) pending > 48 h, each for a Stripe invoice PDF of a **TEST transaction the nightly journey tore down** (transaction 36267ce7… does not exist; finance-docs holds 0 invoice objects). `fn_it_backup_recheck` read an abandoned row as 'failing' and never closed the handoff; the daily `dropbox_backup_escalation:*` report had no CEO decider. | `a_backup_of_a_source_that_no_longer_exists_is_abandoned_not_refiled_for_ever.sql`: orphan transaction backups are abandoned with a dated reason; a documented abandonment settles the refile (both handoffs close next tick). `fn_ceo_backup_coverage_decide` runs the re-check and accepts with the measurement. | Check §3; the file's probe counts orphans (1 now) and open refiles (2 now). |
| 5 | **db_health "slow statement" findings** | 18 Sep 11:00Z | 1 + 8 + 4 findings | 3 | 18 Sep: the lifetime-average rule (replaced by #732 that day). 19–20 Sep: 6 of 12 are operator-session statements stamped `-- source: POST /v1/projects/:ref/database/query` (counts over the 2.6 M-row `kb_chunks`, a schema export, a `leads` update); 2 are this repo's own apply/probe blocks; **4 are real** PostgREST product statements on `doc_backups` (`fn_enqueue_doc_backups` 4.6 s × 21, the doc-backup register 4.2 s × 11, `fn_doc_backups_next` 4.1 s × 99) and `fn_it_detect`'s own RPC (7.2 s × 14, cause 1). | `the_slow_statement_duty_does_not_page_about_an_operators_session.sql`: operator-stamped statements are excluded and their count published every run (1,658 such queryids now). The 4 real ones stay raised. | Check §6. |
| 6 | **send_whatsapp "has not run for 60/99/150 minutes"** | 18 Sep 18:30Z | `watch:run_silent:send_whatsapp` seen 290× | 1 | `whatsappTick` returned early when nothing was queued, so `send_whatsapp` ran only under load (26 runs in 3.4 days against a 15-min tick); the run_silent arm measured it against its own 7-day rhythm (p50 13 min) and called a function with nothing to do "silent". | `resilience_ping/index.ts`: the call is made every tick (~0.8 s), so the subject has a real pulse. | Check §5. |
| 7 | **Nightly journey / post-merge smoke: customer overview data under 2.5 s** (4 locales) | 18 Sep 05:00Z | 8 findings, seen 3–41× | 4 emails + 6 digest lines | Real. Measured by the journey: data settles in 3,031 ms; six portal reads issued from a React effect queue behind the client bundle (evidence: `customer_portal:overview` +2,695 ms). Owner `sales_engineer`. | **Not fixed here** — a portal front-end change owned by the sales engineer and in flight in the Services rework (memory checkpoint 18 Sep). Named so it is not re-diagnosed. | Re-asserted by the nightly run; closes when it passes. |
| 8 | **Nightly journey: `f crawl` console errors** (customer ar-desktop/ar-mobile, supplier en-mobile/ar-mobile) | 18 Sep 03:41Z | 4 findings | 3 | Transient: each closed on the next nightly run ("the journey duty no longer finds it"). Not re-measured here beyond the ledger. | None needed; the ledger closed them. | — |
| 9 | **Nightly journey: `d payment` Stripe test checkout** (2 steps) | 19 Sep 00:08Z | 2 findings, seen 5× | 1 | Open. Evidence: "landed on checkout.stripe.com/c/pay/cs_test_…" — the harness reached Stripe's hosted page and did not return. Owner `accountant`. **Not diagnosed here** (would need the journey's screenshots). | Not fixed here. | Re-asserted nightly. |
| 10 | **Four product defects from the 18 Sep browser audit** (Arabic dates forced LTR in the supplier portal; a revealed request's rail one stage behind; no customer can rate a supplier — `reviews_reason_required` 500; the first request flashes the empty state) | 18 Sep 07:45Z | 4 findings | 2 | Real product defects raised by the human-style audit, owner `sales_engineer`, all still open in `it_engineer_finding`. | **Not fixed here** — portal work owned by the sales engineer; the rating 500 is the one the founder named in the Sunday brief. | Closed by that seat's fix. |
| 11 | Singles: the daily table export failed on `kb_chunks` (18 Sep, DB timeout mid-upload; closed 06:19Z — `fn_table_export_due` v2 resumes a failed day, commit b4ef350); 6 `knowledge_gap` org tasks queued on the sales engineer (18 Sep; #745 gave the queue a consumer; the finding row is open, never re-seen); the accountant's "1 renewal fell due > 7 days ago with no receipt" (21 Sep; Google AED 26.99 renewed 13 Sep — the remedy is the founder forwarding that receipt to the expenses mailbox, which is his and not an IT failure). | — | 3 | 3 | As stated. | Already fixed / not IT. | — |

## Also measured, no founder email

- **GitHub Actions on main since 18 Sep:** 88 success, 9 failed "repo and database agree" (00:52–07:52Z on 18 Sep: the schema-mirror gate waiting on locks and two applied PRs deadlocking each other's check — fixed that morning, commits "a timeout is not drift" and the serialised-apply rule) and 2 failed "deploy edge functions" (05:28 and 05:31Z, #745 and the sanctions producer — the next deploys succeeded). **None after 18 Sep 08:00Z.**
- **pg_cron:** 0 failed `job_run_details` rows in the window (pg_cron was retired on 7 Sep).
- **`fn:ai_gateway` 401 error rows** in the window: HTTP 503 `circuit_open` under the founder's OpenRouter hold — the hold working, logged at 'error'. Not emailed.
- **The backfill's 6,000 `agent_runs` rows an hour** (cause 1's trigger) are a producer's habit and are **not changed here**; the detector is now bounded whatever a producer does. The isolate count behind the burst was not measured.

## What the coordinator applies, in order

1. `scripts/sql/the_it_detector_reads_agent_runs_once_and_no_subject_can_flood_it.sql`
2. `scripts/sql/the_liveness_check_reads_the_scheduler_not_the_detector.sql`
3. `scripts/sql/the_ceo_answers_the_report_families_it_had_no_answer_for.sql`
4. `scripts/sql/a_backup_of_a_source_that_no_longer_exists_is_abandoned_not_refiled_for_ever.sql`
5. `scripts/sql/the_slow_statement_duty_does_not_page_about_an_operators_session.sql`

As each is applied, delete its note `scripts/sql/pending/<file>.txt` and append the file to the end
of `MANIFEST.txt` (the shared `PENDING.txt` list was retired 22 Sep 2026). Then deploy
`send_whatsapp` and `resilience_ping`, then run
`node --test scripts/checks/it_failures_of_18_to_21_september_do_not_recur.test.mjs` and
`node --test scripts/checks/it_engineer_loop_is_closed.test.mjs` (its 6,000 ms assertion is red on
main today for cause 1 and goes green with file 1).
