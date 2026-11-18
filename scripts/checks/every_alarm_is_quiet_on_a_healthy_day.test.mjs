// EVERY ALARM IS QUIET ON A HEALTHY DAY — a new alarm cannot merge until it is.
//
// it_engineer, 22 Sep 2026, founder instruction 642 ("tired of 1-3+ IT issue emails daily").
//
// MEASURED (22 Sep 2026, production, public.notifications type founder_alert, 14 days): 88 IT emails
// and 35 WhatsApp copies; about 55 were alarms that fired while nothing was wrong. The causes were
// one pattern four times over -- "SCHEDULER DOWN" read the detector's own record, "send_whatsapp has
// not run" fired because nothing was queued, "1 undrained row, oldest 1 hour" is normal jitter, and
// a "slow statement" was our own session. Not one of those rules had ever been run against a day on
// which nothing was wrong before it went live, so none of them could know it would fire on one.
//
// WHAT THIS CHECKS
//   1. STATIC (CI, no token). Every routine that can raise an IT finding -- its canonical body (the
//      last file in scripts/sql/MANIFEST.txt that defines it) calls fn_it_engineer_finding_upsert or
//      writes public.it_watch_finding -- is named in REGISTER below. An entry is either REPLAYED
//      (section 2 runs it) or a RELAY (it passes on something another routine decided, and says
//      which). The only other state is the frozen BASELINE of alarms that existed when this gate was
//      born and cannot be replayed yet, each with its reason; a routine that is not in that frozen
//      list cannot be registered there, so a NEW alarm must be replayed to merge.
//   2. LIVE (token; runs in the credential job of .github/workflows/project-parity.yml on every PR).
//      Each REPLAYED alarm is rebuilt, inside ONE transaction that is always rolled back, as a pg_temp
//      copy whose clock reads the healthy instant and whose time-logged tables stop at it
//      (scripts/lib/alarm_replay.mjs). A finding is caught two ways -- the routine's own returned
//      findings, and every call it makes to fn_it_engineer_finding_upsert, which the copy sends to a
//      pg_temp capture instead. Any finding at any HEALTHY instant fails the check, naming the alarm and
//      what it said -- except the KNOWN_LOUD debts this check found on the day it was written, which
//      may only be removed.
//   3. THE CHECK CAN FAIL. The KNOWN-BAD fixture replays fn_it_detect at the first healthy instant
//      after staging, inside the same rolled-back transaction, three failed runs of a ZZ DEMO subject
//      ten minutes before it. The replay must fire run_failure on that subject. If it stays quiet the
//      machinery is blind and every "quiet" above means nothing, so that fails the check too.
//
// CEILING (said, not hidden): a replay is exact for rules over time-logged rows. A rule over present
// state -- a queue's pending rows, pg_stat_archiver -- reads today's state at the old instant: rows
// written after it are invisible, rows that were pending then and have drained since are missed. So
// it can under-fire on those arms, never over-fire on the logged ones. The duties whose rules live in
// TypeScript (supabase/functions/_shared/it_duty_readings.ts) reach the database through the RELAYS
// fn_it_duty_settle and fn_it_journey_ingest; their readings are not stored with a time, so they are
// not replayed here.
//
//   node --test scripts/checks/every_alarm_is_quiet_on_a_healthy_day.test.mjs
//   QUIET_DAY_AT=2026-09-21T20:30:00Z node --test ...   # replay one instant of your choosing
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replay, replaySql as replaySqlFor } from '../lib/alarm_replay.mjs';
import { manifestWithPending, pendingNotes } from '../lib/pending_sql.mjs';
import { lit } from '../lib/db.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));

// The healthy instants. fn_it_detect judges the hour ENDING at the instant against the seven days
// before it, so each is the end of an hour that, MEASURED on production 22 Sep 2026, had all four:
// every live detector tick in the hour recorded 0 findings (it_watch_tick), no it_incident started,
// no it_engineer_finding was raised, and no founder_alert notification was written. Those are the only
// hours in 13-21 Sep that had all four, so these are the estate's quiet hours, not a sample of them.
// Fidelity, measured the same day by replaying at the instants the live detector ticked on 21 Sep:
// the time-logged arms (run_failure, latency) reproduced its findings exactly; the present-state arms
// (queue_stalled on a queue that has drained since) did not -- the ceiling stated above.
export const HEALTHY = [
  { at: '2026-09-14T01:00:00Z', why: 'night, Dubai 05:00; 4 ticks at 0 findings' },
  { at: '2026-09-14T04:00:00Z', why: 'Dubai 08:00; 4 ticks at 0 findings' },
  { at: '2026-09-14T06:00:00Z', why: 'Dubai 10:00, working hours; 4 ticks at 0 findings' },
  // 2026-09-14T18:00Z left on 12 Oct: retention purged that hour's ok agent_runs rows and kept its errors (measured:
  // 88 error rows 16:00-19:00, 0 ok), so the replay saw "ai_gateway failed every one of its 6 attempts" - history
  // that no longer exists, not a rule that fires on a healthy day. The four instants below still replay quiet (12 Oct).
  { at: '2026-09-19T06:00:00Z', why: 'Dubai 10:00, five days later; 2 ticks at 0 findings' },
];

// What this check found the day it was written: an alarm that fires on a healthy instant TODAY.
// Each is a debt with an owner, not an exemption: the check fails on anything NOT listed here, and
// fails when a listed one stops firing, so this list can only get shorter.
export const KNOWN_LOUD = [
  // Measured 22 Sep 2026: the LIVE detector opened exactly this finding at 19 Sep 06:00:25Z, and 0
  // WhatsApp rows were waiting then (public.notifications) -- a false alarm, the audit's "send_whatsapp
  // has not run" class. The 21 Sep fix (docs/it/IT_FAILURES_18_21_SEP_2026.md, cause 6) made the
  // PRODUCER pulse every tick; the D2 rule still reads an idle subject as a silent one, so any
  // rhythmic subject whose producer is quiet for 4x its median gap is paged about. Owner: the
  // it_engineer IT sweep (detector rules), branch it_engineer/every-open-it-item-is-closed-at-its-cause.
  { alarm: 'fn_it_detect', at: '2026-09-19T06:00:00Z', key: 'run_silent:send_whatsapp' },
];

// A HEALTHY instant was chosen for a quiet HOUR (see HEALTHY). An alarm that judges a longer window can see, inside it, a
// failure that was real and measured; firing on it is the alarm working, not a false alarm. Each entry here MUST fire at
// its instant (so it is also a known-bad control: the alarm sees a real outage), and its evidence is written down. It is
// not KNOWN_LOUD: that list is false alarms owed a fix. If an entry stops firing, the alarm went blind to a measured
// failure, or retention removed the history; the check fails either way and says which entry.
export const REAL_FAILURE_IN_WINDOW = [
  // Measured 2 Nov 2026 on production (agent_runs, 12 Sep 06:00Z to 19 Sep 06:00Z, the 7 days fn_it_engineer_run_clusters
  // judges at the instant): inquiry_intake ran 704 times, all 704 status error with counts.llm_call_ok 0 - "Intake LLM call
  // failed for every model", every brief built by the keyword fallback (OpenRouter on hold). No ok row was purged: the
  // same days keep 8,000-16,000 ok rows each, and inquiry_intake's ok rows from the week of 21 Sep are still there.
  { alarm: 'fn_it_engineer_run_clusters', at: '2026-09-19T06:00:00Z', key: 'duty:run_cluster:inquiry_intake' },
  // Same window: send_whatsapp 107 runs, 62 error, every one "WhatsApp notification(s) cannot be sent yet because the
  // matching template is missing or still awaiting Meta approval" - customers' WhatsApp notices were not delivered.
  { alarm: 'fn_it_engineer_run_clusters', at: '2026-09-19T06:00:00Z', key: 'duty:run_cluster:send_whatsapp' },
];

export const REGISTER = {
  // ── REPLAYED ──────────────────────────────────────────────────────────────────────────────────
  fn_it_detect: {
    replay: 'pg_temp.qd_replay_fn_it_detect(null::jsonb, false)',   // p_web null: no live site probe; p_persist false
    findings: 'findings',                                           // the returned jsonb array
    asOf: { agent_runs: 'started_at', error_events: 'created_at', it_watch_tick: 'ran_at', rehearsal_window: 'started_at' },
  },
  fn_it_restore_table_overdue: {
    replay: 'pg_temp.qd_replay_fn_it_restore_table_overdue()',
    asOf: { agent_runs: 'started_at' },
  },
  // 17 Nov 2026 (it_engineer, offline-checks repair): three clocks of 16 Nov that were never registered. Their replay at the
  // healthy instants is asserted by the production half of this file (with a token); offline only the registration is.
  // fn_it_registration_watch: a person stalled in registration, a licence read failed, terms accepted and unsigned; present
  // state of the people's rows, cut by when each row came to be.
  fn_it_registration_watch: {
    replay: 'pg_temp.qd_replay_fn_it_registration_watch()',
    asOf: { leads: 'created_at', customers: 'created_at', support_fault_report: 'reported_at', email_verifications: 'created_at' },
  },
  // fn_ceo_sanctions_review_tick: a screening hit not decided within 24 h of its first sight.
  fn_ceo_sanctions_review_tick: {
    replay: 'pg_temp.qd_replay_fn_ceo_sanctions_review_tick()',
    asOf: { customer_screening_hit: 'created_at', agent_actions: 'created_at' },
  },
  // fn_table_export_unpageable_settle: a registered table the daily export cannot page (fn_table_export_unpageable); present
  // state of the registry, so a healthy day (every exported table has a primary key) is quiet.
  fn_table_export_unpageable_settle: {
    replay: 'pg_temp.qd_replay_fn_table_export_unpageable_settle()',
    asOf: { table_export_registry: 'added_at' },
  },
  // 22 Sep 2026 (it_engineer, SEATS-01). Replayed with p_dry_run FALSE on purpose: the dry run does
  // not call the finding upsert at all, so registering it would be a replay that cannot fire —
  // quiet proving nothing. With false it takes its real branch and the transaction's raise rolls
  // every write back, exactly as it does for the other replays.
  // CEILING, stated rather than hidden: a report's status and next_review_at are PRESENT state, so
  // a report still accepted today reads as accepted at the instant (the same ceiling as
  // fn_support_reply_watch_tick below). asOf limits which reports and notifications EXISTED then,
  // which is what decides whether this alarm had anything to be loud about.
  fn_it_accepted_report_review: {
    stub: { 'public.fn_it_loop_reverify': 'null' },   // the follow-on re-verify of handoffs; the alarm is this review's own finding
    replay: 'pg_temp.qd_replay_fn_it_accepted_report_review(false)',
    asOf: { support_ceo_report: 'created_at', notifications: 'created_at' },
  },
  // A reply is present state (replied_at, sent): one answered after the instant reads as answered then.
  fn_support_reply_watch_tick: {
    replay: 'pg_temp.qd_replay_fn_support_reply_watch_tick()',
    asOf: { inbound_messages: 'created_at', wa_messages: 'created_at', assistant_logs: 'created_at' },
  },
  // 19 Oct 2026 (customer_support, #1549, CS-C08). Raises delivery_outcome_unreturned: a delivery.request done or
  // failed more than 2 h before the instant with no delivery.result returned and no open watch window. It runs
  // fn_customer_support_delivery_watch first (its returns are written inside the rolled-back replay). A request's
  // status and result_handoff_id are PRESENT state (same ceiling as fn_support_reply_watch_tick): one returned
  // after the instant reads as returned then, so it can under-fire, never over-fire.
  // The watch is stubbed in the replay (review of #1549 after main's row-lock walk): it returns results through
  // fn_seat_handoff -> act -> complete, which can lock a LIVE refunds or refund_incident row when the asking seat is the
  // accountant. The alarm's decision does not need it here: result_handoff_id is present state, so a request the watch
  // returned after the instant already reads as returned, and stubbing can only under-fire.
  fn_customer_support_delivery_outcome_tick: {
    stub: { 'public.fn_customer_support_delivery_watch': `'{}'::jsonb` },
    replay: 'pg_temp.qd_replay_fn_customer_support_delivery_outcome_tick()',
    asOf: { agent_actions: 'created_at', notifications: 'created_at' },
  },
  // 19 Oct 2026 (customer_support, #1549, CS-C06). Raises support_reply_quality:<readability_avg|tone_avg|scored_share>
  // over the 7 days to the instant. scored_share judges only replies sent after support_reply_scoring_complete_since
  // (the day every road scores), so an instant before it cannot fire on the gap that file fixed.
  fn_customer_support_reply_quality_week: {
    replay: 'pg_temp.qd_replay_fn_customer_support_reply_quality_week()',
    asOf: { support_reply_readability: 'created_at', assistant_logs: 'created_at', wa_messages: 'created_at', inbound_messages: 'created_at' },
  },
  // 19 Oct 2026 (customer_support, #1549, CS-C09). Raises delivery_health:<send_failures|whatsapp_failures|
  // template_watch|unsubscribe_refusals> over the 24 h to the instant: failures over 5% of 20+ sends, a template
  // watcher run not ok (or none), a refused unsubscribe from a real address.
  // Sending the signed opt-out confirmation is the follow-on action, not the alarm: stubbed, so the replay neither
  // queues a message nor walks fn_customer_support_takes_delivery's handoff chain into a live row lock.
  fn_customer_support_delivery_health_tick: {
    stub: { 'public.fn_customer_support_duty_send': `'{}'::jsonb` },
    replay: 'pg_temp.qd_replay_fn_customer_support_delivery_health_tick()',
    // unsubscribe_refusal (2 Nov 2026, it_engineer): its arm counts refusals with at > now() - 24 h and no upper bound, so
    // without the view every refusal recorded AFTER the instant counted at it. Measured: the table's first real row is
    // 28 Oct 00:55Z (2 real, 9 example.invalid), and the replay fired delivery_health:unsubscribe_refusals at all four
    // healthy instants of September, a month before the table existed. Main's database check was red on it from then.
    asOf: { notifications: 'created_at', agent_runs: 'started_at', email_suppressions: 'created_at', inbound_messages: 'created_at',
            unsubscribe_refusal: 'at' },
  },
  // 23 Sep 2026 (sales_engineer, #869). Raises two findings: a reminder whose handler failed three times,
  // and a reminder whose delivery never became final in 3 days. Both read handoffs and leads that existed
  // at the instant; p_include_fixtures false, so a healthy day with no failing or stuck reminder is quiet.
  fn_supplier_portfolio_reminder_tick: {
    replay: 'pg_temp.qd_replay_fn_supplier_portfolio_reminder_tick(false)',
    asOf: { agent_actions: 'created_at', leads: 'created_at' },
  },
  // 23 Sep 2026 (marketing, #876). Raises one finding: a model step quarantined after failing 3 days running
  // on one subject. It reads marketing_model_run rows that existed at the instant; a healthy day has no step
  // failing three days in a row, so it is quiet. Its handoffs (the brief) are written inside the rolled-back replay.
  fn_marketing_plan_loop_tick: {
    stub: { 'public.fn_marketing_plan_to_ceo': 'null' },   // sending the plan to the CEO is the follow-on action
    replay: 'pg_temp.qd_replay_fn_marketing_plan_loop_tick()',
    asOf: { marketing_model_run: 'created_at', marketing_month_plan: 'created_at' },
  },
  // 24 Sep 2026 (it_engineer, #910). Raises learning_accuracy_fell:<seat> when a seat's 7-day judgement accuracy
  // falls against the week before. It reads the judgements, lessons and daily rows that existed at the instant;
  // a healthy day has no seat whose accuracy fell, so it is quiet. Its own daily row is written inside the
  // rolled-back replay.
  fn_seat_learning_measure: {
    replay: 'pg_temp.qd_replay_fn_seat_learning_measure(null::date)',
    asOf: { seat_judgement: 'made_at', seat_learning_daily: 'measured_at' },
  },
  // 24 Sep 2026 (it_engineer, #901). Raises seat_duty:<duty> when a registered duty is overdue, failing or has no
  // live owner (fn_seat_duty_health). Duties are present state; a healthy day has every duty on its clock. The
  // duties it runs are run inside the rolled-back replay.
  // 19 Oct 2026: the replay used to RUN the duties through public.fn_seat_duty_run. That took a FOR UPDATE row lock on
  // the live public.seat_duty row and held it for the replay's whole transaction, and the live tick
  // ("for update skip locked") then skipped the most overdue duties for as long as CI replays ran: five sales_engineer
  // duties went 80 minutes without a run. The alarm under test is fn_seat_duty_health, so the duty runs are stubbed.
  fn_seat_duties_tick: {
    replay: 'pg_temp.qd_replay_fn_seat_duties_tick(1)',
    // seat_duty_skip (a_seat_duty_skipped_because_its_row_is_locked_is_counted_and_raised.sql): a skip streak that began
    // after the instant did not exist then; a healthy day has none, so seat_duty_skipped:<duty> is quiet.
    asOf: { seat_duty: 'created_at', seat_duty_skip: 'first_skipped_at' },
    stub: { 'public.fn_seat_duty_run': `'{}'::jsonb`, 'public.fn_seat_duty_isolate': 'null' },
    // 27 Oct 2026: the duties it raises are DECIDED in fn_seat_duty_health, which used to run live: it read today's
    // seat_duty at today's clock, so marketing.month_plan (registered 29 Sep, failed 7 times running on 27 Oct) fired
    // at every September instant. Replayed as of the instant with the tick; the known-bad duty below proves it still
    // fires. CEILING, as above: failures and last_error are present state on a row that existed at the instant.
    callees: ['fn_seat_duty_health'],
    // its closing UPDATE of it_engineer_finding would hold live finding rows until the rollback
    shadow: ['it_engineer_finding'],
  },
  // 24 Sep 2026 (it_engineer, #903). Raises held_notice:undelivered when a WhatsApp holding notice owed to a customer
  // failed 8 times. It reads held questions that existed (were escalated) at the instant; a healthy day has none
  // undeliverable, so it is quiet. Its claims are made inside the rolled-back replay.
  fn_reason_held_notice_due: {
    replay: 'pg_temp.qd_replay_fn_reason_held_notice_due(20)',
    asOf: { reasoning_held_question: 'escalated_at' },
  },
  // 24 Sep 2026 (it_engineer, #903). Raises licence_expiry:matchable_after_expiry only when an approved supplier with
  // an expired licence or insurance is STILL matchable after its own pause ran. Leads that existed at the instant;
  // the renewal asks and pauses happen inside the rolled-back replay.
  fn_it_engineer_licence_expiry_watch: {
    replay: 'pg_temp.qd_replay_fn_it_engineer_licence_expiry_watch()',
    asOf: { leads: 'created_at' },
  },
  // 24 Sep 2026 (it_engineer, #903). A seat's knowledge pass rate below 70%, or 10 points down on the month before,
  // over graded exam answers that existed at the instant. A healthy day has no seat below the bar.
  fn_it_engineer_knowledge_pass_rate: {
    replay: 'pg_temp.qd_replay_fn_it_engineer_knowledge_pass_rate()',
    asOf: { seat_knowledge_exam: 'asked_at' },
  },
  // 24 Sep 2026 (it_engineer, #936). The daily no-model knowledge exam: a seat whose retrieval misses the expected
  // entries, or no questions loaded. Not filtered: the questions were loaded after the healthy instants, and hiding
  // them makes it raise no_questions, which is the apply window, not an unhealthy day.
  fn_it_engineer_knowledge_recall_exam: {
    replay: 'pg_temp.qd_replay_fn_it_engineer_knowledge_recall_exam()',
    asOf: {},
  },
  // 24 Sep 2026 (ceo, #933). The CEO's report sweep, the weekly constraint lever and the marketing month-plan chase.
  // Not filtered: each reads present state (open reports, the plan, the month plan), the ceiling fn_it_detect's
  // neighbours state above; a healthy day has no unanswered report, no stalled lever and no late plan.
  // 5 Oct 2026 (it_engineer, #1188). A duty paused in public.duty_pause for over 7 days. Pauses that existed at the
  // instant; a healthy day has no duty paused for a week.
  fn_it_engineer_duty_pause_expiry: {
    replay: 'pg_temp.qd_replay_fn_it_engineer_duty_pause_expiry()',
    asOf: { duty_pause: 'paused_at' },
  },
  // 27 Oct 2026 (it_engineer, 68046f265, ledger 1003 IT-C14). A run label with more than 5 runs in 7 days and more than
  // half of them not ok is one owned finding. Runs that existed at the instant.
  fn_it_engineer_run_clusters: {
    replay: 'pg_temp.qd_replay_fn_it_engineer_run_clusters()',
    asOf: { agent_runs: 'started_at' },
  },
  fn_ceo_report_answer_sweep: { stub: { 'public.fn_ceo_decide_report': 'null', 'public.fn_ceo_backup_heartbeat_decide': 'null' }, replay: 'pg_temp.qd_replay_fn_ceo_report_answer_sweep()', asOf: {} },
  fn_ceo_constraint_lever: { stub: { 'public.fn_ceo_improvement_close': 'null' }, replay: 'pg_temp.qd_replay_fn_ceo_constraint_lever()', asOf: {} },
  fn_ceo_marketing_plan_watch: { stub: { 'public.fn_ceo_improvement_open': 'null' }, replay: 'pg_temp.qd_replay_fn_ceo_marketing_plan_watch()', asOf: {} },
  // 24 Sep 2026 (it_engineer, #903). A quarter's knowledge refresh still unverified 45 days after it opened. Refreshes
  // that existed at the instant; the new quarter's refresh it files is written inside the rolled-back replay.
  fn_it_engineer_knowledge_refresh: {
    replay: 'pg_temp.qd_replay_fn_it_engineer_knowledge_refresh()',
    // Not filtered by opened_at: hiding this quarter's row makes the copy insert it again (23505). A row opened after
    // the instant is never 45 days old at it, so leaving it visible cannot make the replay louder.
    asOf: {},
  },
  // 24 Sep 2026 (accountant, #904). sanctions_list_stale: the newest good list of some source is over 8 days old at
  // the instant. Screening runs that existed then; a healthy day has fresh lists.
  fn_accountant_sanctions_rescreen: {
    replay: 'pg_temp.qd_replay_fn_accountant_sanctions_rescreen()',
    // Not filtered: the first ok list postdates the healthy instants, and with none visible the routine raises
    // (never fetched). A later list seen at the instant can only make it quieter (the ceiling in the header).
    asOf: {},
  },
  // 24 Sep 2026 (customer_support, #904). A post-reveal dispute past its decision date. Disputes that existed at
  // the instant; a healthy day has none overdue.
  fn_sales_engineer_disputes_tick: {
    replay: 'pg_temp.qd_replay_fn_sales_engineer_disputes_tick()',
    asOf: { post_reveal_dispute: 'opened_at' },
  },
  // 24 Sep 2026 (marketing, #905). recruitment:pool_empty when a trade marked for recruitment has no leads left to
  // invite. Gaps opened and leads that existed at the instant; a healthy day has no marked gap with an empty pool.
  fn_marketing_recruitment_funnel: {
    locksLive: { fn_marketing_funnel_diagnosis: 'the diagnosis IS the alarm decision; its row locks are on the handoff rows it opens through fn_ceo_improvement_open, which no live caller selects skip locked' },
    replay: 'pg_temp.qd_replay_fn_marketing_recruitment_funnel()',
    asOf: { supply_gap: 'opened_at', leads: 'created_at' },
  },
  // 29 Sep 2026 (marketing, #1070). recruitment:no_source:<trade> when a trade planned for recruitment has no checked
  // source. It plans from the gaps that existed at the instant (the copy's own delete drops plans for gaps not yet
  // opened, rolled back); a healthy day has no planned trade without a checked source. Sources are not filtered:
  // checked_at is when a source was last checked, not when it was recorded, and a source seen at the instant can only
  // make it quieter (the ceiling in the header).
  fn_marketing_gap_recruitment_plans: {
    replay: 'pg_temp.qd_replay_fn_marketing_gap_recruitment_plans()',
    asOf: { supply_gap: 'opened_at' },
  },
  // 24 Sep 2026 (marketing, #905). reputation:no_public_review_link when a satisfied customer waits for an ask and no
  // review link is configured. Reviews that existed at the instant; the asks it writes are rolled back.
  fn_marketing_reputation: {
    replay: 'pg_temp.qd_replay_fn_marketing_reputation()',
    asOf: { reviews: 'created_at' },
  },
  // 19 Oct 2026 (marketing, ledger 1003 C11, #1551). social_inbox:overdue / :signature_rejected / :send_failed: owed
  // social messages unanswered 2 working hours, signed webhooks rejected, failed replies. Messages and runs that existed
  // at the instant; a healthy day has none.
  fn_marketing_social_inbox: {
    replay: 'pg_temp.qd_replay_fn_marketing_social_inbox()',
    asOf: { social_message: 'created_at', agent_runs: 'started_at' },
  },
  // 19 Oct 2026 (marketing, ledger 1003 C12, #1551). trends:feed_silent when a trend feed is unread for 2 days. Trends
  // seen by the instant; the 48h decisions it writes are rolled back. Feed read times are present state (header ceiling).
  fn_marketing_trend_decision: {
    replay: 'pg_temp.qd_replay_fn_marketing_trend_decision()',
    asOf: { marketing_trend: 'seen_at' },
  },
  // 19 Oct 2026 (marketing, ledger 1003 C14, #1551). facts:surface_stale:<surface> when a fetched public page does not
  // state a public fact. It checks only responses to its own earlier requests; inside the replay its requests are
  // rolled back, so a healthy day raises nothing.
  fn_marketing_fact_register: {
    replay: 'pg_temp.qd_replay_fn_marketing_fact_register()',
    asOf: { marketing_duty_record: 'written_at' },
  },
  // 19 Oct 2026 (marketing, ledger 1003 C15, #1551). paid:spend_without_budget / paid:spend_not_reported. Spend days
  // pulled by the instant; a healthy day has no spend while paid is off and every spend day with the accountant.
  fn_marketing_paid_spend_report: {
    replay: 'pg_temp.qd_replay_fn_marketing_paid_spend_report()',
    asOf: { marketing_ad_spend_day: 'pulled_at' },
  },
  // 29 Sep 2026 (accountant, founder ledger 1018: fraud and risk screening). Raises money_hold_unreviewed:<id> when a
  // reveal or refund the accountant's money screen held has waited 48 hours for review. Holds that existed at the
  // instant; a healthy day has none waiting that long. The party flags it writes and the holds it re-screens are
  // rolled back with the replay.
  fn_accountant_risk_screen_tick: {
    locksLive: { fn_accountant_money_screen: 'the money screen IS the alarm decision; no live caller selects the rows it locks skip locked' },
    replay: 'pg_temp.qd_replay_fn_accountant_risk_screen_tick()',
    asOf: { money_move_hold: 'opened_at' },
  },
  // 29 Sep 2026 (it_engineer, #1064, founder_instruction 1009). high_stakes_open:<kind>:<subject> when the second-seat
  // review of a high-stakes decision cannot be opened. Replayed as a ZZ DEMO refund decision by the CEO. The gate
  // still resolves the author's model from the reasoning calls that existed at the instant (asOf ai_cost_log), but
  // p_demo=true with a 'ZZ DEMO' question SKIPS fn_seat_deliberation_open's author-model check (AUTHOR_MODEL_UNPROVEN),
  // so this replay does not exercise that arm; it exercises the kind, the pair, the seats and the open itself. A
  // healthy day opens its review. Still pending, so the replay runs its pending file first (alarm_replay.mjs, `pending`),
  // without retries. The negative control is the known-bad test below (an unknown kind fires high_stakes_open).
  fn_high_stakes_gate: {
    locksLive: { fn_high_stakes_challenge: 'the challenge IS the gate under test; it opens a deliberation through handoffs, which no live caller selects skip locked' },
    replay: `pg_temp.qd_replay_fn_high_stakes_gate('refund', 'ceo', 'zz_demo_quiet_day', 'zz_demo_quiet_day:refund',
      'ZZ DEMO should this refund be approved as the CEO decided?', '{"ledger":"ZZ DEMO paid by card"}'::jsonb,
      '{"decision":"ZZ DEMO approve in full"}'::jsonb, null, null, true)`,
    asOf: { ai_cost_log: 'occurred_at' },
  },
  // 29 Sep 2026 (sales_engineer, #1106, ledger 1018 item 1). Raises stalled_inquiry_rescue:no_uninvited_leads:<trades>:<emirate>
  // when a real request is in the stalled-inquiry rescue (no quote 48 h after matching, or nobody reachable - #1105's
  // intake) and no uninvited lead is left for its trade and area.
  // It reads the requests, matches and quotes that existed at the instant; a healthy day has no stalled real request with
  // an empty pool, so it is quiet. p_include_fixtures false: a ZZ DEMO request never raises it. The rescue rows, the
  // customer's update and the enqueue_supplier_invites call it makes are inside the rolled-back replay; while pending,
  // the replay runs its pending file first. Measured 29 Sep 2026: quiet at all five instants, and with a stalled request
  // in a trade with no uninvited lead staged at 2026-09-14T06:00Z it fires the no_uninvited_leads finding for Ajman.
  fn_sales_engineer_stalled_inquiry_rescue: {
    replay: 'pg_temp.qd_replay_fn_sales_engineer_stalled_inquiry_rescue(false)',
    asOf: { inquiries: 'created_at', inquiry_matches: 'sent_at', quotes: 'created_at' },
  },
  // ── RELAYS: they pass on what another routine decided ─────────────────────────────────────────
  trg_high_stakes_review: { relay: 'records the disagreement a second seat recorded with a high-stakes decision that already went ahead; the verdict is the reviewer\'s (seat_deliberation_turn), and a healthy day has none' },
  fn_spec_offer_failed: { relay: 'records a spec comparison the sales_engineer sweep reported failed; raises only after its fifth backed-off failure, never on a healthy day' },
  // 27 Oct 2026 (it_engineer for marketing): the WhatsApp supplier invitation brake (#1634) writes it_watch_finding
  // directly, and main went red on this check because nobody registered it. It decides nothing itself: its two callers
  // decide (fn_wa_sender_quality_record on Twilio's own quality reading, fn_wa_supplier_invite_gate on >= 2 STOP replies
  // and >= 5% of the invitations sent in 7 days), and fn_it_engineer_ingest_watch_findings carries the open row into
  // the finding ledger. With 0 invitations sent and no reading below HIGH, a healthy day raises nothing.
  fn_wa_supplier_invite_brake: { relay: 'records the WhatsApp invitation brake that fn_wa_sender_quality_record (a Twilio quality reading below HIGH / ONLINE) or fn_wa_supplier_invite_gate (>= 2 STOPs and >= 5% of 7-day invitations) decided; a healthy day sends no invitation below HIGH and has no STOPs, so it raises nothing' },
  fn_wa_signature_watch: { relay: 'records a WhatsApp webhook wa_inbound itself refused for a bad X-Twilio-Signature; the refusal is the decision of the signature check, and nothing fires on a healthy day with no refused inbound' },
  fn_seat_clock_deliver: { relay: 'records a message the send door refused; the refusal is the door\'s decision' },
  // 17 Nov 2026 (it_engineer, offline-checks repair): seven alarms of 16 Nov that were never registered, each read in its body.
  // Each raises only on an event a healthy day does not have; the decision is another routine's or another seat's.
  fn_support_profile_resolve: { relay: 'records that two NAMED people met on one e-mail or phone tail when a support profile was opened (the profile is opened apart, nothing joined); raised only on that clash, never by a clock' },
  fn_support_hands_it_a_fault: { relay: 'files the fault customer_support\'s reasoning found in a person\'s conversation (once per case per hour); the finding is support\'s decision, and a healthy day has none' },
  fn_inbound_mail_dead_letter: { relay: 'records a mail the inbound queue gave up reading after its attempts (the queue\'s decision, an_inbound_burst_is_accepted_at_once_and_read_in_turn.sql); a healthy day reads every mail' },
  fn_expense_document_waits_for_statement: { relay: 'records, for the one expense it is called on, a fee booked on the founder\'s word whose document is held (fn_expense_held_entry_for decides); called per entry, never by a clock' },
  fn_sanctions_ban_tells_affected_customers: { relay: 'the trigger on a sanctions ban the CEO decided: records only that the affected customers could NOT be told (its exception arm); a healthy day has no ban' },
  fn_fraud_flag_goes_to_the_accountants_reasoning: { relay: 'the trigger on a fraud flag: records only that the accountant\'s review could not be opened for it (its exception arm); a healthy day raises no flag' },
  fn_injection_attempt_record: { relay: 'records an attempt to instruct the assistant that the conversation guard detected, raising only on a REPEAT from one sender in 30 days; a healthy day has none' },
  // Missing on origin/main as well (review 4, item 5): a00 on notifications (a_notice_is_a_duplicate_only_of_the_same_event.sql).
  fn_notifications_the_same_message_is_sent_once: { relay: 'records a notification its own insert guard cancelled because the same message to the same person (same channel, type, subject, body, event and dedupe key) was already queued or sent inside the window (founder ruling 1631); the cancellation is the guard\'s decision on the row being written, there is no reading to replay, and a healthy day queues no repeat' },
  // 13 Nov 2026 (accountant; a_paid_reveal_is_reconciled_booked_and_timed_by_the_accountant_from_the_moment_it_is_paid.sql).
  fn_it_engineer_takes_unrecorded_payment: { relay: 'records a payment stripe_webhook could not record as a sale (the handoff payment.unrecorded the webhook raised); a healthy day records every payment and raises nothing' },
  fn_accountant_payment_checks_sweep: { relay: 'records a payment check that raised inside the sweep, or an exception that could not be escalated (the check and the escalation are the decisions; a healthy day has neither), and reads the holiday calendar: calendar:public_holidays_running_out fires while public.public_holidays reaches less than 365 days ahead (its last date is 2027-12-03, so from 4 Dec 2026 until next year\'s dates are added); that rule is the calendar\'s, and a quiet day needs the calendar filled' },
  // 13 Nov 2026, review 4 (item 5): the two the local gate named.
  fn_accountant_reconciles_reveal: { relay: 'records that the CEO could not be told of a sale after its books were written (reveal:sale_notice_failed: the error from fn_accountant_tells_ceo_of_sale, i.e. fn_seat_handoff refusing sale.made, is the finding; the sweep retries the notice); a healthy day files every sale notice and raises nothing' },
  fn_refund_settle: { relay: 'records a refund Stripe reported (made in its dashboard or API) that matches no sale we hold by PaymentIntent or charge (refund:unbooked:, owner the accountant); the refund and its event are Stripe\'s facts, and a healthy day has none' },
  // 15 Nov 2026 (release of the certificate branch): a detector over four states of the people's own rows, real rows only (demo
  // excluded). Measured on production 15 Nov 2026 by a read-only count of the same four conditions: 0, 0, 0, 0. A healthy day has
  // none, because kyc and supplier_api now refuse to let anyone on without a recorded acceptance and the minute sweep signs it.
  fn_it_engineer_finds_people_working_without_an_acceptance: { relay: 'counts real customers with a request and no recorded acceptance, real suppliers submitted or approved with none, and real acceptances with no signed certificate after 30 minutes (acceptance_gap:<state>, owner the IT engineer); the rows are the people\'s own state, read-only, and on a healthy day all four counts are 0 (measured 15 Nov 2026)' },
  // 15 Nov 2026 (final review of the paid-reveal release, item 2; a_paid_reveal_closes_the_request_and_everyone_on_it_is_told.sql 9b).
  fn_sales_engineer_request_step_failed: { relay: 'records that the sales engineer\'s request step after a reveal.paid or refund.paid hand-over raised (fn_sales_engineer_records_reveal or fn_sales_engineer_reopens_after_refund; reveal_request_step:<handoff>, owner the sales engineer) and adds request.step_failed to company_event; it is called only from the exception arm of fn_sales_engineer_acts_on_handoff and reads nothing itself, so the error is the finding, and a healthy day records every request step and raises nothing' },
  // 3 Nov 2026 (customer_support, #1844 review). Both record what another routine already decided; a healthy day has neither.
  fn_customer_support_closes_status_chases: { relay: 'records a status-chase follow-up that fn_customer_support_takes_delivery failed to deliver (or had no channel for) on three ticks; the failure is the delivery door\'s, and a healthy day delivers every follow-up' },
  fn_wa_customer_request_answer: { relay: 'records a status chase whose handler fn_sales_engineer_chases_for_status failed (fn_seat_handoff marked it failed); the failure is the handler\'s, and a healthy day starts every chase' },
  fn_it_engineer_ingest_watch_findings: { relay: 'copies fn_it_detect\'s open it_watch_finding rows into the finding ledger' },
  fn_invite_placement_finding: { relay: 'records the verdict fn_invite_placement_judge reached from the latest recorded GlockApps result (public.deliverability_test against public.invite_placement_bar, 28 Oct 2026; the morning seed is retired); it files only on an open sending day, so a held campaign files nothing, and a healthy open day has a passing verdict' },
  fn_wa_supplier_invite_brake: { relay: 'records the brake a caller pulled on the supplier WhatsApp invitations (the quality or opt-in gate, with its reason); it cancels the queued sends and files deliverability:supplier_invite_wa only when called, and a healthy day never calls it' },
  fn_lesson_reapproval_lapse_escalates: { relay: 'records that the CEO escalation of a lapsed lesson re-approval could not be opened (#1443); fires only when fn_seat_handoff itself errors on that lapse, and a healthy day has none' },
  fn_rehearsal_window_sweep: { relay: 'logs a window it closed as an already-resolved info row (status resolved, severity info); the decision is the window\'s own expires_at (#1401), and no alarm is raised' },
  fn_it_duty_settle: { relay: 'writes the failing items a duty reading hands it; the rule is the duty\'s' },
  fn_accountant_duty_settle: { relay: 'the accountant\'s twin of fn_it_duty_settle' },
  fn_accountant_record_supplier_payment: { relay: 'records the refusal of a bank payment above what is still owed on a supplier due; fires only when a caller attempts that overpayment, and a healthy day has none' },
  fn_supplier_due_record_settlement: { relay: 'records a Stripe settlement (stripe_webhook\'s write to supplier_dues.paid_at) with no stored checkout amount, or above what was owed; fires only on that settlement, and a healthy day has none' },
  fn_customer_support_sends_the_it_digest: { relay: 'raises nothing itself: the match is its file\'s rolled-back probe, which seeds one ZZ DEMO duty:access finding to prove a real founder decision still mails; on a healthy day the digest only reads findings' },
  fn_web_search_degraded: { relay: 'records that web_search.ts degraded (no key, an outage, a refused Serper key, or the daily cap fn_web_search_claim counted); the failure is what the caller read, and a healthy day searches without one' },
  fn_accountant_duty_stage: { relay: 'records that an accountant duty stage raised; the error is the finding' },
  fn_it_loop_stage: { relay: 'records that an IT loop stage raised; the error is the finding' },
  fn_seat_duty_cross_review: { relay: 'records that a cross-family review could not be opened; the error from fn_seat_deliberation_open is the finding' },
  fn_seat_handoff: { relay: 'records a handoff that could not be opened; the error is the finding' },
  // 27 Oct 2026 (#1607, accountant): the reveal-invoice trigger raises only in the exception arm of its handoff insert.
  fn_accountant_files_reveal_invoice: { relay: 'records that the invoice.issued handoff to the sales engineer could not be filed for a transaction whose invoice it just filed; fires only when that insert is refused (the error is the finding), and a healthy day has none' },
  fn_ceo_accountant_notice_report_decide: { relay: 'the CEO\'s decision on an accountant report' },
  fn_ceo_sales_engineer_report_decide: { relay: 'the CEO\'s decision on a sales engineer report' },
  fn_it_journey_ingest: { relay: 'writes the failed steps a nightly journey or smoke run reports' },
  // 29 Sep 2026 (it_engineer, #1048). A truncated smoke run now upserts its FAIL steps itself instead of settling,
  // so it closes nothing on silence. The FAIL is the journey's verdict (scripts/e2e/journeys.mjs), not a rule here.
  fn_it_smoke_ingest: { relay: 'writes the failed steps a post-deploy smoke run reports; each FAIL is the journey\'s verdict, and a run with no failed step raises nothing' },
  // 29 Sep 2026 (it_engineer, #1072). A trigger function (returns trigger), so it cannot be called as a replay. It
  // decides nothing: it raises monitor:seat_playbook_rebuild_failed only when fn_seat_playbook_build itself raised
  // on a recorded lesson or a decided knowledge finding. Quiet on a healthy day, measured 29 Sep 2026 in one
  // rolled-back transaction on production with both pending files applied: fn_seat_playbook_build_all rebuilt all
  // six seats without error, and a ZZ DEMO lesson inserted into seat_case_memory fired the trigger and raised 0
  // findings; with fn_seat_playbook_build replaced by one that raises, the same insert raised 1. It reads no clock,
  // so the HEALTHY instants change nothing for it.
  // 18 Nov 2026 (sales_engineer): two relays of an error, and one relay of what the nightly Dropbox listing measured
  trg_invite_reply_reaches_sales_engineer: { relay: 'records that fn_marketing_files_invite_reply raised while filing an invited supplier\'s reply; the error is the finding, and a healthy day files every reply without one' },
  trg_answered_prospect_gets_its_chase: { relay: 'records that fn_sales_engineer_books_prospect_chase raised while booking an answered prospect\'s follow-up; the error is the finding, and a healthy day books without one' },
  fn_it_backup_listing_record: { relay: 'records the empty or ownerless party folders the dropbox_backup listing measured in Dropbox (summary.shells); it reads no table, and a healthy day lists none, which closes the finding' },
  trg_seat_playbook_learns: { relay: 'records that fn_seat_playbook_build raised while learning from a lesson; the error is the finding, and a healthy day rebuilds every seat without one' },
  // 29 Sep 2026 (it_engineer, #1062, instruction 1009). The monthly game day. Each game_day:<scenario> finding is the
  // verdict of a scenario routine (fn_it_game_day_<scenario>) that injected a fault in a rolled-back savepoint and saw
  // the REAL detector miss it or fail to clear; the rule is those detectors', each replayed or relayed above. Not
  // replayed: the scenarios drive the live detectors on today's clock inside savepoints, so a pg_temp copy at a past
  // instant would not be a replay of anything. Measured quiet on a healthy day: run on production 29 Sep 2026 inside one
  // rolled-back transaction, 5/5 scenarios passed and 0 game_day findings were open afterwards.
  fn_it_engineer_game_day: { relay: 'records a game-day scenario that failed; the failure is the verdict of the injected fault against the real detector, and a healthy month passes all five and raises nothing (measured 29 Sep 2026: 5/5, 0 findings)' },
  // 12 Oct 2026 (it_engineer, #1287 release review): the held-question replay decides a stale answer is not sent
  // (think.ts replayHeld, older than 24 h or undated); this routine only records that decision for customer_support.
  fn_reason_held_delivered: { relay: 'records a reasoned answer the replay held for review instead of sending (think.ts replayHeld decided it was stale); a healthy day answers inside 24 h and holds none' },
  fn_it_restore_table_pick: { relay: 'records that the restore drill could not pick a table; the error is the finding' },
  // ── BASELINE: existed on 22 Sep 2026 and cannot be replayed yet ─────────────────────────────────
  fn_it_engineer_alert_tick: { baseline: 'monitor rules over it_watch_tick and it_engineer_scanner; replaying it runs the whole IT loop (handoffs, digest) and needs a side-effect-free split first' },
  fn_it_dropbox_health_record: { baseline: 'rules over a Dropbox API reading passed in as jsonb; the readings are not stored with a time' },
  fn_delivery_feedback_canary_tick: { baseline: 'posts a canary and judges the reply; nothing to replay without sending' },
  trg_it_judge_routine_change: { baseline: 'fires on a routine being changed; a healthy day has no DDL to replay' },
};
// Frozen. Adding a name here is how a gate gets softened; add a replay instead.
const BASELINE = new Set(['fn_it_engineer_alert_tick', 'fn_it_dropbox_health_record', 'fn_delivery_feedback_canary_tick', 'trg_it_judge_routine_change']);

// A routine whose defining file still waits in scripts/sql/pending/: { file: that file's SQL, def: its body there },
// the last such file winning, as MANIFEST order will. null when no pending file defines it (the live one is replayed).
export function pendingSource(name, repo = REPO) {
  let out = null;
  for (const [f, note] of pendingNotes(repo)) {
    if (/^\s*A PROBE\b/.test(note) || !existsSync(join(repo, f))) continue;
    const src = readFileSync(join(repo, f), 'utf8');
    const heads = [...src.matchAll(/create\s+or\s+replace\s+function\s+public\.(\w+)\s*\(/gi)];
    const i = heads.findIndex((m) => m[1].toLowerCase() === name.toLowerCase());
    if (i >= 0) out = { file: src, def: src.slice(heads[i].index, heads[i + 1]?.index ?? src.length) };
  }
  return out;
}

// ── STATIC ────────────────────────────────────────────────────────────────────────────────────────
// name -> canonical body (the LAST file in MANIFEST order that defines it).
export function canonicalBodies(repo = REPO) {
  // MANIFEST plus pending/ (29 Sep 2026): a new alarm waiting in pending/ must be registered by its own
  // PR, not discovered on main after the bookkeeping commit appends it (#1070's was).
  const manifest = manifestWithPending(repo);
  const out = new Map();
  for (const f of manifest) {
    const p = join(repo, f);
    if (!existsSync(p)) continue;
    const src = readFileSync(p, 'utf8');
    const heads = [...src.matchAll(/create\s+or\s+replace\s+function\s+public\.(\w+)\s*\(/gi)];
    heads.forEach((m, i) => out.set(m[1].toLowerCase(), src.slice(m.index, heads[i + 1]?.index ?? src.length)));
    // A later file that drops a routine takes it out of the canonical source (24 Sep 2026: #934 dropped
    // fn_customer_support_disputes_tick; its earlier body is history, not a live alarm).
    for (const d of src.matchAll(/drop\s+function\s+if\s+exists\s+public\.(\w+)\s*\(/gi)) {
      if (!heads.some((h) => h[1].toLowerCase() === d[1].toLowerCase() && h.index > d.index)) out.delete(d[1].toLowerCase());
    }
  }
  return out;
}

const RAISES = /public\.fn_it_engineer_finding_upsert\s*\(|insert\s+into\s+public\.it_watch_finding\b/i;

// Every alarm the canonical source holds that the register does not answer for, with why.
export function unanswered(bodies, register = REGISTER, baseline = BASELINE) {
  const bad = [];
  for (const [name, body] of bodies) {
    if (name === 'fn_it_engineer_finding_upsert' || !RAISES.test(body)) continue;
    const e = register[name];
    if (!e) bad.push(`${name}: raises IT findings and is not in REGISTER -- replay it on a healthy day`);
    else if (e.baseline && !baseline.has(name)) bad.push(`${name}: BASELINE is frozen; a new alarm must be replayed`);
    else if (!e.replay && !e.relay && !e.baseline) bad.push(`${name}: its entry says neither replay, relay nor baseline`);
  }
  return bad;
}

test('the seat-duty tick replay never runs a live duty (no live row lock)', () => {
  const def = `create or replace function public.fn_seat_duties_tick(p_limit integer default 8) returns jsonb language plpgsql as $f$
    begin perform public.fn_seat_duty_isolate(sd.duty) from public.seat_duty sd; v := v || public.fn_seat_duty_run(d.duty); end $f$;`;
  const health = `create or replace function public.fn_seat_duty_health() returns jsonb language sql as $f$ select '[]'::jsonb $f$`;
  const sql = replaySqlFor('fn_seat_duties_tick', def, REGISTER.fn_seat_duties_tick, '2026-09-14T01:00:00Z', '', '', { fn_seat_duty_health: health });
  assert.doesNotMatch(sql, /public\.fn_seat_duty_run\s*\(/, 'the replay would lock and run live seat_duty rows');
  assert.doesNotMatch(sql, /public\.fn_seat_duty_isolate\s*\(/, 'the replay would isolate a live duty');
});

// A callee the decision is made in is replayed as of the instant too (27 Oct 2026), and every call reaches the copy.
test('a registered callee is rebuilt as of the instant and the routine calls the copy', () => {
  const def = `create or replace function public.fn_zz_demo_tick() returns jsonb language plpgsql as $f$
    begin return public.fn_zz_demo_health(); end $f$;`;
  const health = `create or replace function public.fn_zz_demo_health() returns jsonb language sql as $f$
    select jsonb_agg(d.duty) from public.seat_duty d where d.created_at < now() $f$`;
  const entry = { replay: 'pg_temp.qd_replay_fn_zz_demo_tick()', asOf: { seat_duty: 'created_at' }, callees: ['fn_zz_demo_health'] };
  const sql = replaySqlFor('fn_zz_demo_tick', def, entry, '2026-09-14T01:00:00Z', '', '', { fn_zz_demo_health: health });
  assert.match(sql, /create function pg_temp\.qd_replay_fn_zz_demo_health\(\)[\s\S]*pg_temp\.qd_asof_seat_duty[\s\S]*pg_temp\.qd_asof\(\)/);
  assert.doesNotMatch(sql, /public\.fn_zz_demo_health\s*\(/, 'the routine still calls the live callee');
  assert.ok(sql.indexOf('qd_replay_fn_zz_demo_health(') < sql.indexOf('create function pg_temp.qd_replay_fn_zz_demo_tick'), 'the callee must exist before the routine');
  assert.throws(() => replaySqlFor('fn_zz_demo_tick', def, entry, '2026-09-14T01:00:00Z'), /callee fn_zz_demo_health has no definition/);
});

// NO REPLAY HOLDS A LIVE ROW (19 Oct 2026). A replay is one transaction rolled back at the end, so any row lock it
// takes on the way is held for the whole replay. Every replayed entry is walked here: its own body, after the replay's
// rewrite, and every public routine it still calls, transitively, through the schema mirror. A path that reaches a
// FOR UPDATE / FOR SHARE must be stubbed (entry.stub, or DEFAULT_STUBS for the pure follow-on actions), or named in
// entry.locksLive with the reason the alarm's own decision runs through it.
test('no healthy-day replay can take a row lock on a live table, transitive callees included', async () => {
  const { readSchemaMirror } = await import('../lib/schema_mirror.mjs');
  const { routineBodies, lockingCalls, ROW_LOCK } = await import('../lib/replay_locks.mjs');
  const bodies = routineBodies(readSchemaMirror());
  const bad = [];
  for (const [name, entry] of Object.entries(REGISTER).filter(([, e]) => e.replay)) {
    const pending = pendingSource(name);
    const defs = pending ? [pending.def] : (bodies.get(name) ?? []);
    for (const def of defs) {
      // A registered callee is part of the replayed text (it is rebuilt before the routine), so its calls are walked too.
      const calleeDefs = Object.fromEntries((entry.callees ?? []).map((c) => [c, (bodies.get(c) ?? [])[0]]));
      const sql = replaySqlFor(name, def, entry, '2026-09-14T01:00:00Z', '', '', calleeDefs);
      const body = sql.slice(sql.indexOf('create function pg_temp.qd_replay_'));
      if (ROW_LOCK.test(body.replace(/--[^\n]*/g, ''))) bad.push(`${name}: its replayed body still takes a row lock`);
      const allowed = new Set(Object.keys(entry.locksLive ?? {}));
      for (const p of lockingCalls(name, body, bodies)) {
        const via = p.split(' -> ')[1];
        if (!allowed.has(via)) bad.push(`${name}: ${p}`);
      }
    }
  }
  assert.deepEqual([...new Set(bad)], [], 'a replay would hold a live row lock until its rollback: stub the call, or name it in locksLive with why');
});

test('the stub matches a call whose arguments nest parentheses', async () => {
  const { stubCalls } = await import('../lib/alarm_replay.mjs');
  assert.equal(stubCalls(`x := public.fn_seat_duty_run(coalesce(a, (b)), 'it''s (x)') + 1;`, 'public.fn_seat_duty_run', 'null'), 'x := null + 1;');
  assert.equal(stubCalls(`t := 'see public.fn_seat_duty_run (locked)';`, 'public.fn_seat_duty_run', 'null'), `t := 'see public.fn_seat_duty_run (locked)';`);
});

test('every routine that can raise an IT finding is replayed on a healthy day, or says why not', () => {
  const bad = unanswered(canonicalBodies());
  assert.deepEqual(bad, [], bad.join('\n'));
});

test('the static gate fails a new, unregistered alarm and a new name smuggled into BASELINE', () => {
  const fake = new Map([
    ['fn_zz_demo_new_alarm', "perform public.fn_it_engineer_finding_upsert('zz', 'ZZ DEMO', 'x', 'internal')"],
    ['fn_zz_demo_smuggled', "insert into public.it_watch_finding (detector_key) values ('zz')"],
    ['fn_zz_demo_quiet', 'select 1'],
  ]);
  const bad = unanswered(fake, { fn_zz_demo_smuggled: { baseline: 'ZZ DEMO' } });
  assert.equal(bad.length, 2, bad.join('\n'));
  assert.match(bad.join('\n'), /fn_zz_demo_new_alarm: raises IT findings and is not in REGISTER/);
  assert.match(bad.join('\n'), /fn_zz_demo_smuggled: BASELINE is frozen/);
});

test('a real failure in an alarm\'s window names a replayed alarm at a healthy instant, and is not a known false alarm', () => {
  const at = new Set(HEALTHY.map((h) => h.at));
  const debt = new Set(KNOWN_LOUD.map((k) => `${k.alarm}@${k.at}@${k.key}`));
  const bad = REAL_FAILURE_IN_WINDOW.filter((r) => !REGISTER[r.alarm]?.replay || !at.has(r.at) || !r.key || debt.has(`${r.alarm}@${r.at}@${r.key}`));
  assert.deepEqual(bad, []);
});

test('every REGISTER entry names a routine that still exists in the canonical source', () => {
  const bodies = canonicalBodies();
  const gone = Object.keys(REGISTER).filter((n) => !bodies.has(n));
  assert.deepEqual(gone, [], `registered but defined by no file in MANIFEST.txt: ${gone.join(', ')}`);
});

// ── LIVE ──────────────────────────────────────────────────────────────────────────────────────────
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const INSTANTS = process.env.QUIET_DAY_AT ? [{ at: process.env.QUIET_DAY_AT, why: 'QUIET_DAY_AT' }] : HEALTHY;

test('production: every replayed alarm is quiet at every healthy instant', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  assert.ok(INSTANTS.length > 0, 'HEALTHY names no instant');
  const loud = [];
  const owed = new Set(KNOWN_LOUD.map((k) => `${k.alarm}@${k.at}@${k.key}`));
  const real = new Set(REAL_FAILURE_IN_WINDOW.map((k) => `${k.alarm}@${k.at}@${k.key}`));
  for (const [name, entry] of Object.entries(REGISTER).filter(([, e]) => e.replay)) {
    const pending = pendingSource(name);
    for (const { at } of INSTANTS) {
      const out = await replay(sql, name, entry, at, '', pending);
      for (const f of out.fired) {
        const id = `${name}@${at}@${f.split(' -- ')[0]}`;
        if (owed.delete(id) || real.delete(id)) continue;
        loud.push(`${name} at ${at} fired: ${f}`);
      }
    }
  }
  // The debt list only shrinks: an entry that no longer fires must leave it, or a later regression
  // of the same alarm would pass as "already known".
  if (!process.env.QUIET_DAY_AT) for (const id of owed) loud.push(`KNOWN_LOUD ${id} no longer fires -- delete it from KNOWN_LOUD`);
  if (!process.env.QUIET_DAY_AT) for (const id of real) loud.push(`REAL_FAILURE_IN_WINDOW ${id} no longer fires -- the alarm is blind to a measured failure, or retention removed that history (measure which)`);
  assert.deepEqual(loud, [], loud.join('\n'));
});

test('production: the known-bad fixture makes the replay fire, so quiet means something', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const at = INSTANTS[0].at;
  // Three failed runs of a ZZ DEMO subject, ten minutes before the instant. Rolled back with the rest.
  const stage = `insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
    select 'zz_demo_quiet_day_fixture', 'error', ${lit(at)}::timestamptz - interval '10 minutes' + g * interval '1 second',
           ${lit(at)}::timestamptz - interval '10 minutes' + g * interval '1 second', '{}'::jsonb, 'ZZ DEMO known-bad fixture'
      from generate_series(1, 3) g;`;
  const out = await replay(sql, 'fn_it_detect', REGISTER.fn_it_detect, at, stage);
  assert.ok(out.fired.some((f) => f.startsWith('run_failure:zz_demo_quiet_day_fixture')),
    `the replay did not fire on three staged failures, so it cannot see anything: ${JSON.stringify(out)}`);
});

// The same for the seat-duty tick now that its health callee is replayed as of the instant (27 Oct 2026): a ZZ DEMO
// duty registered a day BEFORE the instant and failing three times running must fire seat_duty:<duty>, or the as-of
// rebuild has blinded the alarm. A new row only (no live row is locked), rolled back with the rest.
test('production: a known-bad seat duty that existed at the instant makes the tick replay fire', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const at = INSTANTS[0].at;
  const stage = `insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file, enabled, failures, last_error, created_at)
    values ('it_engineer.zz_demo_quiet_day_fixture', 'it_engineer', interval '1 hour', 'fn_zz_demo_quiet_day_fixture',
            'ZZ DEMO known-bad fixture', 'scripts/sql/zz_demo_quiet_day_fixture.sql', true, 3, 'ZZ DEMO failure',
            ${lit(at)}::timestamptz - interval '1 day');`;
  const out = await replay(sql, 'fn_seat_duties_tick', REGISTER.fn_seat_duties_tick, at, stage);
  assert.ok(out.fired.some((f) => f.startsWith('seat_duty:it_engineer.zz_demo_quiet_day_fixture')),
    `the tick replay did not fire on a failing duty that existed at the instant, so it cannot see anything: ${JSON.stringify(out)}`);
});

// The same for a PENDING alarm (29 Sep 2026, #1064): fn_high_stakes_gate replayed from its pending file with a kind
// that is not high-stakes must fire high_stakes_open, or its quiet healthy days mean nothing (and neither does the
// pending-replay path).
test('production: the known-bad high-stakes kind makes the pending gate replay fire', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const pending = pendingSource('fn_high_stakes_gate');   // null once applied: the control then replays the live routine
  const entry = REGISTER.fn_high_stakes_gate;
  const bad = { ...entry, replay: entry.replay.replace("gate('refund',", "gate('zz_demo_not_a_kind',") };
  assert.notEqual(bad.replay, entry.replay, 'the known-bad kind was not substituted into the replay');
  const out = await replay(sql, 'fn_high_stakes_gate', bad, INSTANTS[0].at, '', pending);
  assert.ok(out.fired.some((f) => f.startsWith('high_stakes_open:zz_demo_not_a_kind:')),
    `the gate replay did not fire on an unknown kind, so it cannot see anything: ${JSON.stringify(out)}`);
});
