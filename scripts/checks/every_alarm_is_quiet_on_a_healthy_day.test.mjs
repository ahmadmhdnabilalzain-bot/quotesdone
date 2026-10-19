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
  // 22 Sep 2026 (it_engineer, SEATS-01). Replayed with p_dry_run FALSE on purpose: the dry run does
  // not call the finding upsert at all, so registering it would be a replay that cannot fire —
  // quiet proving nothing. With false it takes its real branch and the transaction's raise rolls
  // every write back, exactly as it does for the other replays.
  // CEILING, stated rather than hidden: a report's status and next_review_at are PRESENT state, so
  // a report still accepted today reads as accepted at the instant (the same ceiling as
  // fn_support_reply_watch_tick below). asOf limits which reports and notifications EXISTED then,
  // which is what decides whether this alarm had anything to be loud about.
  fn_it_accepted_report_review: {
    replay: 'pg_temp.qd_replay_fn_it_accepted_report_review(false)',
    asOf: { support_ceo_report: 'created_at', notifications: 'created_at' },
  },
  // A reply is present state (replied_at, sent): one answered after the instant reads as answered then.
  fn_support_reply_watch_tick: {
    replay: 'pg_temp.qd_replay_fn_support_reply_watch_tick()',
    asOf: { inbound_messages: 'created_at', wa_messages: 'created_at', assistant_logs: 'created_at' },
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
    asOf: { seat_duty: 'created_at' },   // a duty registered after the instant did not exist then
    stub: { 'public.fn_seat_duty_run': `'{}'::jsonb`, 'public.fn_seat_duty_isolate': 'null' },
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
  fn_ceo_report_answer_sweep: { replay: 'pg_temp.qd_replay_fn_ceo_report_answer_sweep()', asOf: {} },
  fn_ceo_constraint_lever: { replay: 'pg_temp.qd_replay_fn_ceo_constraint_lever()', asOf: {} },
  fn_ceo_marketing_plan_watch: { replay: 'pg_temp.qd_replay_fn_ceo_marketing_plan_watch()', asOf: {} },
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
  // 29 Sep 2026 (accountant, founder ledger 1018: fraud and risk screening). Raises money_hold_unreviewed:<id> when a
  // reveal or refund the accountant's money screen held has waited 48 hours for review. Holds that existed at the
  // instant; a healthy day has none waiting that long. The party flags it writes and the holds it re-screens are
  // rolled back with the replay.
  fn_accountant_risk_screen_tick: {
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
  fn_wa_signature_watch: { relay: 'records a WhatsApp webhook wa_inbound itself refused for a bad X-Twilio-Signature; the refusal is the decision of the signature check, and nothing fires on a healthy day with no refused inbound' },
  fn_seat_clock_deliver: { relay: 'records a message the send door refused; the refusal is the door\'s decision' },
  fn_it_engineer_ingest_watch_findings: { relay: 'copies fn_it_detect\'s open it_watch_finding rows into the finding ledger' },
  fn_invite_placement_finding: { relay: 'records the verdict fn_invite_placement_settle reached on a seed message the inbox reader (resilience_ping inboxPlacement) looked at; the folder is the reader\'s reading, and no seed is sent on a healthy day before the morning batch' },
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
  const sql = replaySqlFor('fn_seat_duties_tick', def, REGISTER.fn_seat_duties_tick, '2026-09-14T01:00:00Z');
  assert.doesNotMatch(sql, /public\.fn_seat_duty_run\s*\(/, 'the replay would lock and run live seat_duty rows');
  assert.doesNotMatch(sql, /public\.fn_seat_duty_isolate\s*\(/, 'the replay would isolate a live duty');
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
  for (const [name, entry] of Object.entries(REGISTER).filter(([, e]) => e.replay)) {
    const pending = pendingSource(name);
    for (const { at } of INSTANTS) {
      const out = await replay(sql, name, entry, at, '', pending);
      for (const f of out.fired) {
        const id = `${name}@${at}@${f.split(' -- ')[0]}`;
        if (owed.delete(id)) continue;
        loud.push(`${name} at ${at} fired: ${f}`);
      }
    }
  }
  // The debt list only shrinks: an entry that no longer fires must leave it, or a later regression
  // of the same alarm would pass as "already known".
  if (!process.env.QUIET_DAY_AT) for (const id of owed) loud.push(`KNOWN_LOUD ${id} no longer fires -- delete it from KNOWN_LOUD`);
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
