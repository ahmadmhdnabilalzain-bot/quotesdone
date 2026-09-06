# Audit of the mail sent from info@quotesdone.com — 30 days to 6 Sep 2026

**Your order (6 Sep 2026):** "send an agent to audit the emails sent from info@quotesdone.com. So many errors were sent to me from the engine."

**Your standing rule:** you receive exceptions, not routine; nothing routes to your approval except a Stripe refund.

**Verdict in one line:** of the 242 emails the platform sent you in 30 days, about 30 were yours to read (the daily brief, the weekly and monthly reports, money). The other ~210 were a department's work — failed cron jobs, silent jobs, watchdog findings, legal and security notices, a stalled handoff — that reached your inbox because twenty-plus routines each decided for themselves whether to email you and none of them had a policy to ask. As of 09:14 UTC today they do: `founder_mail_policy` decides, one gate on the queue enforces it, and a disallowed signal opens one task for the role that owns it instead. Details and proof are in §5.

**Measured on:** production `htdblwldjkcgjvmqkbeh`, 6 Sep 2026 08:53–09:40 UTC, `public.notifications` (the only send log — there is no `send_outbox` table or `email_log`), `founder_alerts`, `alert_signature`, `red_episode`, `agent_runs`, `agent_actions`, `cron.job` / `cron.job_run_details`, `email_suppressions`, `leads.invite_status`, `app_secrets` (keys only). Window: `created_at >= now() - 30 days` = 7 Aug 09:00 UTC onward. Everything below is a count from those tables; nothing is inferred from the Resend dashboard, which this audit did not read.

---

## 1. Everything the platform sent in 30 days, by recipient

`send_outbox` sends every `notifications` row with `channel = 'email'` from `QuotesDone <info@quotesdone.com>` (supplier-side rows from the supplier address). 445 notification rows were created in the window: 434 email, 11 WhatsApp. Two recipient classes only — you, and suppliers. No customer received an email (there are no real customers yet), and no row went to a reserved test address (`@example.invalid`) in the window.

| Recipient class | Rows | sent | expired (never sent) | digested / digest (folded into your brief) | skipped | failed | bounced / suppressed |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Founder** (to_role founder/admin or your address) — email | 434 | 242 | 33 | 154 + 2 | 3 | 0 | 0 |
| **Founder** — WhatsApp | 11 | 0 | 0 | — | 1 (+10 today, see §3) | 0 | — |
| **Supplier** (`supplier_invite`, 12–15 Aug) | 110 | 110 | 0 | — | 0 | 0 | 5 hard-bounced → suppressed |
| **Supplier** — other (4 rows to addresses matching a reserved test pattern: `doc_request`, `registration_received`, `supplier_enablement`, `supplier_invite`, 12–13 Aug) | 4 | 4 | 0 | — | 0 | 0 | 0 |
| **Customer** | 0 | | | | | | |

Founder rows by type (email channel):

| Type | sent | expired | digested | skipped | What it is |
|---|---:|---:|---:|---:|---|
| founder_alert | 155 | | | | fn_notify_founder ("[Attention] …") and alert_founder ("[Action needed] …") |
| agent_silence | 42 | | | | fn_agent_silence_watch / fn_runner_silence_watch |
| founder_brief | 16 | 16 | | | the daily brief |
| health_alert | | | 72 | | folded into the brief |
| resilience_alert | | | 40 | | folded into the brief (the email itself went as founder_alert) |
| cost_snapshot | 7 | | | | weekly burn + revenue (7 copies on 10–11 Aug) |
| smoke_alert | 6 | 14 | | | fn_smoke "data-integrity check failed" |
| ops_alert | 1 | | 22 | | fn_ops_watch |
| backup_alert | 4 | | | | fn_backup_watch |
| exception_alert | | | 13 | 2 | fn_exception_alerts |
| agent_escalation | 2 | 1 | | | trg_page_high_agent_action "[HIGH] …" |
| board_report | 2 | 2 | | | weekly board report |
| period_report | 2 | | | | monthly business report |
| finance_reminder | 2 | | | | upcoming payments |
| policy_inconsistency | | | 4 | | |
| expense_logged | | | 4 | | |
| cfo_report, llm_drift, invite_paused_bounce, supplier_registered | 1 each | | | | |
| supply_health | | | 1 | | |
| weekly_learnings | | | | 1 | |

---

## 2. What reached YOU that was an error or an alert

Every distinct alert subject, with the routine that sent it, the cause, whether that cause is fixed or live as measured now, and whether it was yours to act on.

| # | Subject (as you saw it) | Count | First → last (UTC) | Sent by | Underlying cause | Cause today | Yours to act on? |
|---|---|---:|---|---|---|---|---|
| 1 | `[Action needed] Scheduled runs failed (N agent(s))` | 79 | 8 Aug 05:15 → 16 Aug 03:15 | fn_watch_failed_runs → alert_founder | Hourly pass, and a dedupe key that carried the hour so it never deduplicated. Most failures were the paid-inference hold ("model returned nothing"). | **Fixed** 3–5 Sep: one alert per condition, the hold is counted not paged, a signature resolves when its subject succeeds. | No — engineering's |
| 1b | `[Action needed] Scheduled runs failed (N new condition(s))` | 9 | 2 Sep 00:08 → 5 Sep 08:15 | same | Real failures after the hold was lifted: agent_context_missing, dr_drill, dropbox_backup, enrich_capability, kb_embed, os_review, quote_compare, send_outbox, uptime, workflow_step_sweep; cron `monthly_report` read as stale (a monthly schedule read as daily). | `v_cron_stale` is empty now. No agent has errored since 2 Sep except kb_autofill_gaps (4 Sep, 5 LLM calls failed on the hold) and **kb_embed, live** — two error runs today 09:23/09:27 belonging to a kb_embed change in flight on another branch. | No |
| 2 | `Scheduled job stopped: <job>` / `Scheduled job failing: <job>` | 40 | 11 Aug 08:46 → 6 Sep 00:40 | fn_agent_silence_watch | Jobs paused by the 16 Aug stand-down and re-enabled 2–3 Sep looked silent against their pre-stand-down last success (15 jobs paged in one day). | **Fixed** 3 Sep (activation is the floor; once per silence episode). All 29 named jobs are active and their last run succeeded today, except `org_task_execute_sweep_hourly` and `cos_execute_hourly` (inactive since 16 Aug / 3 Sep) and `emit_metric_alerts` (weekly, last 10 Aug). | No |
| 2b | `Employee has stopped working: docs / followup / onboarding / intel_director`, `N employee(s) have stopped working` | 5 | 11 Aug 08:55 → 6 Sep 07:10 | fn_runner_silence_watch | Runners past their own cadence during and after the stand-down. | followup, onboarding, intel_director all ran ok today; `docs` is an inactive employee (people_ops). | No — COO's |
| 3 | `[Action needed] Resilience: the platform needs attention` | 20 | 8 Aug 04:30 → 3 Sep 02:00 | fn_resilience_watch → alert_founder | 14 of the 20 carried one byte-identical body — "3 caller(s) still using the LEGACY shared secret" — because the only dedupe was a 3-hour clock; up to 8 a day. The other 6: "N inquiry(ies) unmatched for >6h" (fixture inquiries). | **Fixed** 6 Sep 00:34 (signature ledger, once per condition, resolved on merit). The watch reports "all critical pipelines healthy" at 09:00 today. | No |
| 4 | `[Action needed] AI credit low: $N left` ($0.44 – $9.18) | 14 | 9 Aug 05:00 → 16 Aug 05:00 | cost_snapshot (edge) → alert_founder, level critical (+WhatsApp) | OpenRouter balance below the $20 floor (`openrouter_min_usd`) while the paid hold is your deliberate decision. | **Live condition, silent job**: `cost_snapshot_balance_daily` and `cost_snapshot_weekly` have been INACTIVE since the 16 Aug stand-down and were never resumed, which is why the emails stopped — not because the balance rose. | The top-up is your input, but the hold is your decision; the brief carries it now |
| 5 | `[Action needed] Business health N% – department(s) at risk` | 12 | 8 Aug 07:00 → 5 Sep 07:00 | fn_watch_health → alert_founder | Daily by design: any department "at risk" in `v_department_health`. | Live routine; today 96%, no department at risk. | No — CEO's |
| 6 | `[Attention] Stalled handoff run #80 / #82 (H-W20-01-02) Nh past SLA` | 6 | 4 Sep 00:00 → 6 Sep 06:00 | fn_handoff_watchdog → fn_notify_founder, every 6 h | **Real.** Handoff H-W20-01-02 from chief_revenue_officer to content_strategy_and_copy, due 17 Aug 01:08, never accepted: 488 hours late as of 09:00 today. | **Live.** Now one task for the receiving role's department lead (growth: sales_director), bumped daily; it emails you only if `founder_mail_policy.handoff_stalled_7d` is set to allow it (seeded: not). | No — the receiving lead's |
| 7 | `QuotesDone: data-integrity check failed` | 6 sent + 14 expired | 17 Aug 07:30 → 6 Sep 08:30 | fn_smoke, every 30 min | `email_backlog_stuck` counted every non-portal queued row older than 2 h — the 6–10 queued **WhatsApp** rows (see §3) — as a stuck email backlog. The same check every time; the body differs only in the count. | **Fixed** today: the check counts `channel = 'email'` only. Proved: with the 10 WhatsApp rows present it reports 0 failures; with a genuinely stuck email fixture it reports 1. | No |
| 8 | `QuotesDone: backup overdue or failed` (4) + `[HIGH] Backup may have failed or is overdue` (1) + `[Attention] Backup may have failed or is overdue` (1) | 6 | 11 Aug 08:00 → 4 Sep 08:35 | fn_backup_watch, trg_page_high_agent_action, fn_agent_action_work_sweep | Events 11, 14, 15 Aug and 4 Sep. On 4 Sep ONE missed backup produced THREE emails: the watcher's own row, the trigger paging its agent_action, and the sweep paging the same action again. | **Fixed** today: one task per event; only a backup still failing after 48 h (two daily retries) may email you, once per day. Backup ran ok today 03:30. | Only after retry |
| 9 | `[Attention] High-severity security events` (2), `Auth hardening review` (2), `Core legal documents missing` (2), `Customers have not accepted current terms` (2), `Regulatory change may affect your terms/policies` (2) | 10 | 31 Aug 22:26 → 6 Sep 05:35 | fn_agent_action_work_sweep, paging every `notify`-policy agent_action (fn_security_ai, fn_legal_ai daily) with "This is a notification — no approval is required of you" | security_incident: 7 `anon_exposure_drift` security events in 7 days plus the auth-hardening review; legal_flag: the three legal findings, raised daily. | **Live** findings (agent_actions 9350–9354 at `notified`, 6 Sep). Now routed to the cybersecurity engineer and the general counsel as tasks. | No |
| 10 | `[Action needed] Red view: N new red signal(s)` | 2 | 4 Sep 07:22, 5 Sep 18:52 | fn_red_view_alert → alert_founder | 3 then 24 kernel-board / connectivity / cron reds (policy_consistency_weekly timing out; trace-integrity boards). | **Live**: 11 red episodes open now. Routed to the IT operations engineer. A page DOWN (a failing health check) is the one red that still emails you. | No |
| 11 | `[Attention] 10 agent run(s) failed in last 24h` | 2 | 4 Sep 06:35, 5 Sep 03:35 | agents (edge) → agent_action `incident` → fn_agent_action_work_sweep | kb_autofill_gaps and kb_embed failures (the hold). | kb_embed live (above). Routed. | No |
| 12 | `QuotesDone: cron watchdog is down` | 1 | 2 Sep 00:25 | fn_ops_watch | `agent_silence_watch` had no successful run in 48 h — it was paused by the stand-down. | **Fixed** 3 Sep (resumed; ran ok 06:40 today). | No |
| 13 | `QuotesDone: AI model drift detected` | 1 | 13 Aug 07:25 | fn_llm_drift_watch | Model output drift measurement. | Routed to the CTO now. | No |
| 14 | `Supplier invites paused – deliverability risk` | 1 | 7 Aug 09:00 | enqueue_supplier_invites | Bounce rate on the invite wave. | Routed to business development now. | No |
| 15 | `New supplier auto-approved` | 1 | 12 Aug 11:41 | supplier registration | A registration. | Routed to business development now. | No |
| — | `QuotesDone daily brief` (16 sent, 16 never sent 16–30 Aug), `Weekly Board Report` (2 + 2 never sent), `Monthly Business Report` (2), `weekly finance report` (1), `weekly burn + revenue snapshot` (7, all on 10–11 Aug), `Upcoming payments` (2) | 30 | | fn_founder_brief, fn_board_report, period reports, cost_snapshot, finance reminders | Reading you asked for; money. | Allowed. Note the 16 unsent briefs (§3). | **Yes** |

**Actionable by you, in the 30 days: the 30 report/money emails. Not yours: everything in rows 1–15 (≈212 emails).** No email in the window asked you for a refund decision, reported a money anomaly, or reported the site down — which is what the policy now reserves your inbox for.

---

## 3. Delivery integrity

**What can and cannot be measured.** `send_outbox` marks a row `sent` on a 2xx from Resend and stores nothing else — there is no Resend message id column anywhere in the schema. So "sent with no Resend id" is unmeasurable by construction (every sent row has none), and this audit does not claim Resend delivered them. The measurable Resend-side signals are below.

| Signal | Measured |
|---|---|
| `send_outbox` runs, 30 days | 2,433 ok, **3 error**: 2× Resend `422 validation_error "Invalid to"`, 1× Resend `500 application_error` |
| Founder rows `sent` with an error recorded | 1 — a `founder_alert` on 8 Aug hit the Resend 500, was retried, and was sent |
| Founder rows `failed` (dead-lettered after 3 attempts) | 0 |
| Founder rows **expired, never sent** | **33**: 16 daily briefs (16–30 Aug), 14 smoke alerts, 2 board reports, 1 agent escalation — all `sent_at` null. Created during the 16 Aug stand-down that held the outbound senders; no live routine writes `'expired'` to notifications (a scan of every routine body), so the status was set by a one-off statement at the time. You did not receive a brief from 16 to 30 Aug. |
| Hard bounces (Resend webhook → `email_suppressions`) | 5 in the window, all 15 Aug, all supplier invites (5 of the 110 invited addresses; `leads.invite_status = 'bounced'` for those 5; 10 bounced all-time, 37 suppressions all-time: 36 permanent hard bounces + 1 blocked QA-mailbox pattern) |
| Founder address suppressed? | No |
| `email_enabled` / Resend key present | true / present |
| **WhatsApp to you** | **10 rows queued 3–6 Sep with 0 attempts** — the same subjects as rows 6, 8 and 9 above (stalled handoff ×6, legal documents ×2, backup ×1, security ×1). Two reasons they never went: `wa_flush` and `sms_flush` (the Twilio drains) have been INACTIVE since 2 Sep 00:26, and there is no approved WhatsApp template for a founder alert (`wa_template_sids` has six keys — control_mode_code, customer_new_quote, supplier_doc_expiry, supplier_new_inquiry, supplier_quote_accepted, customer_supplier_unlocked — none for `founder_alert`), so even a running drain would fall back to a free-form message that only delivers inside a 24 h session. **Your input:** a founder-alert template submitted to Twilio for approval, if you want WhatsApp pages at all. **Done today:** the 10 rows are marked `skipped` with the reason written on them, because under the policy none of those kinds is yours and re-enabling the drain would otherwise have paged you ten times about routed work. |

---

## 4. The mechanism that let this happen

More than twenty database routines and seven edge functions wrote to your inbox (49 routine bodies touch `founder_alerts` or write founder-bound `notifications`; four of the watchers reached you through an HTTP hop to `alert_founder`), and each carried its own idea of when to email you: a 3-hour clock (resilience), an hourly dedupe key that never matched anything (failed runs), a "notify" policy that pages you and then says no approval is required (the action sweep), a 24-hour window exactly as long as the check interval (backup), and no dedupe at all (silence, smoke, handoff). The digest that was supposed to fold routine alerts into your brief let anything through whose subject contained "failed" or "down", and never saw the rows written without a `to_role`. There was no single place that knew the rule you gave.

---

## 5. What changed today (6 Sep 2026, applied and proved on production)

**One policy table.** `public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)`, 58 rows seeded from this audit:

| Allowed to email you (17) | Owner |
|---|---|
| founder_brief, board_report, period_report | chief_of_staff |
| cfo_report, cost_snapshot, finance_reminder, refund_approval, refund_decision, spend_approval_needed (above your AED 10,000 boundary), finance_alert, ledger_imbalance, stripe_webhook_failed, unexpected_charge | cfo |
| platform_down, uptime_alert, backup_failed_after_retry | it_operations_engineer |
| security_critical (customer data exposed to anon, or a secret leaked) | cybersecurity_engineer |

| Never emailed — opens ONE task for the owner instead (41) | Owner |
|---|---|
| scheduled_runs_failed, agent_silence, resilience, resilience_alert, red_view, smoke_alert, backup_alert, ops_alert, incident, os_incident, os_incident_past_sla | it_operations_engineer (runtime agent `it`, product_eng) |
| health_alert, llm_drift, ai_quality_alert, agent_escalation | cto |
| security_incident | cybersecurity_engineer |
| business_health_at_risk | ceo |
| handoff_stalled, handoff_stalled_7d (flip this row to allow a week-old stall to email you), corrective_task_overdue, agent_action_unclassified, policy_inconsistency | chief_of_staff |
| runner_silence, remediation_escalated, knowledge_coverage, exception_alert, weekly_learnings, agent_created | chief_operating_officer |
| legal_flag, legal_docs_missing, terms_not_accepted, regulatory_change, pdpl_request | general_counsel |
| ai_credit_low, expense_logged | cfo |
| rfq_sla_breach | marketplace_director |
| customer_escalation | customer_success_director |
| supply_health, doc_expiry, supplier_registered, invite_paused_bounce | business_development |

A kind that is not in the table is treated as not allowed and routed to the CTO.

**One gate.** `a10_notifications_founder_mail_policy`, a BEFORE INSERT trigger on `notifications`: every founder-bound email or WhatsApp row is looked up by its kind; allowed rows queue as before; anything else is handed to `fn_founder_mail_route` and the row is refused without an error, so no producer needs to know. It fires before the digest trigger. `fn_notify_founder` (the front door 20 routines call) applies the same policy and now takes the kind, a 24-hour dedupe key, and the owner; `alert_founder` (the HTTP door six edge functions call) is a thin shim over it.

**One task per condition.** A routed signal opens one `org_tasks` row for the owner role's runtime agent (else its department lead, else the lane's own picker), tier advisory, `needs_founder = false`. The condition is the kind plus the subject with numbers normalised, so "run #80" and "run #82" of the same stalled handoff, or the trigger's "[HIGH] Backup may have failed" and the sweep's "Backup may have failed", are one condition. While that task is open, a repeat only bumps its `seen_count`; when the owner closes it and the condition returns, a new task opens. The ledger is `alert_signature` (watcher `founder_mail`). The task appears on the OS, and the daily brief's **WITH THE ORGANISATION** section now carries one line — how many signals were routed and which kinds. That line is the only way this traffic reaches you.

**The specific senders.** fn_smoke counts email only; fn_backup_watch pages once per event, and only `backup_failed_after_retry` (> 48 h) may email you, once a day; fn_handoff_watchdog opens the task for the RECEIVING role's department lead; fn_watch_failed_runs, fn_red_view_alert, fn_watch_health, fn_resilience_watch call fn_notify_founder with their kind instead of the HTTP hop; fn_agent_silence_watch and fn_runner_silence_watch route by kind; fn_agent_action_work_sweep passes the action's own kind; every other caller names its kind.

**Proof (one aborted transaction inside a declared rehearsal window; nothing committed, nobody paged — `scripts/checks/the_founder_is_emailed_exceptions_only.probe.mjs`, 17/17):**

| Condition simulated | Routine run | Founder emails queued | Tasks opened | Owner |
|---|---|---:|---:|---|
| A failed scheduled run | fn_watch_failed_runs | 0 | 1 | it / product_eng |
| The same failure again | fn_watch_failed_runs | 0 | 0 (first task bumped to seen 2) | |
| A cron job that never ran | fn_agent_silence_watch | 0 | 1 | it / product_eng |
| Resilience finding (the routine's call) | fn_notify_founder(resilience) | 0 | 1 | it / product_eng |
| AI credit low (what cost_snapshot sends) | fn_notify_founder(ai_credit_low) | 0 | 1 | cfo / finance |
| Business health at risk (the routine's call) | fn_notify_founder(business_health_at_risk) | 0 | 1 | ceo / exec |
| 10 WhatsApp rows waiting, no stuck email | fn_smoke | 0 | 0 — reports 0 failures | |
| A genuinely stuck email | fn_smoke | 0 | 1 | it / product_eng |
| One missed backup (30 h) | fn_backup_watch | 0 | 1 (backup_alert) | it / product_eng |
| Backup still failing after retry (60 h) | fn_backup_watch | **1** (backup_failed_after_retry) | 0 (task bumped) | |
| The real stalled handoff, runs #80 and #82 | fn_handoff_watchdog | 0 | 1 (seen 2) | sales_director / growth |
| A cron job's latest run failed | fn_red_view_alert | 0 | 1 | it / product_eng |
| A page down (failing health check) | fn_red_view_alert | **1** (platform_down) | 0 | |
| A refund approval | fn_notify_founder(refund_approval) | **1** | 0 | |
| A caller that names no kind | fn_notify_founder | 0 | 1 (unregistered) | cto |
| A legacy routine inserting straight into the queue | insert into notifications | 0 rows queued | 1 | it / product_eng |
| The real queue | — | 0 non-policy founder emails queued | | |

On the deployed `alert_founder` (v18), by HTTP: a routed kind returns `{mode: routed, task_id}` and opens the task for `it`; no kind named routes to the CTO; a bad secret is 403; an info level is only logged. Since the policy was seeded at 09:14 UTC, production has queued 0 founder-bound rows and logged 0 route failures (measured 09:40; the next watchdog passes that meet a real condition — the handoff watchdog at 12:00 — will be the first to route on their own).

**CI:** `scripts/checks/the_founder_is_emailed_exceptions_only.test.mjs` (5/5) — every founder-bound row since the policy was seeded carries an allowed kind; every fn_notify_founder call names its kind and every literal kind is registered; the gate is attached and ordered before the digest; no route failure logged.

---

## 6. Boundaries of this audit

- The send log is `public.notifications`; a row `sent` means Resend accepted the POST. Whether Resend delivered it, and whether you opened it, is not in any table this platform keeps.
- The 30-day window starts 7 Aug 09:00 UTC; the 16–30 Aug stand-down sits inside it and explains the 33 unsent rows and most of the silence alerts.
- "Cause today" was measured at 09:00 UTC on 6 Sep from `cron.job_run_details`, `agent_runs`, `red_episode`, `security_events`, `agent_actions` and `fn_phase_c_handoff_overdue()`. A condition marked live can clear within the hour; one marked fixed names the change that fixed it.
- Not changed: `cost_snapshot_balance_daily` / `cost_snapshot_weekly` (inactive since 16 Aug) and `wa_flush` / `sms_flush` (inactive since 2 Sep) are left as found — re-enabling a sender is outside an audit that was told nothing may page you. The kb_embed error runs today belong to a change in flight on another branch.
