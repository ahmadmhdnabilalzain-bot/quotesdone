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
import { replay } from '../lib/alarm_replay.mjs';
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
  { at: '2026-09-14T18:00:00Z', why: 'Dubai 22:00; 4 ticks at 0 findings' },
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
  fn_seat_duties_tick: {
    replay: 'pg_temp.qd_replay_fn_seat_duties_tick(1)',
    asOf: { seat_duty: 'created_at' },   // a duty registered after the instant did not exist then
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
  fn_customer_support_disputes_tick: {
    replay: 'pg_temp.qd_replay_fn_customer_support_disputes_tick()',
    asOf: { post_reveal_dispute: 'opened_at' },
  },
  // 24 Sep 2026 (marketing, #905). recruitment:pool_empty when a trade marked for recruitment has no leads left to
  // invite. Gaps opened and leads that existed at the instant; a healthy day has no marked gap with an empty pool.
  fn_marketing_recruitment_funnel: {
    replay: 'pg_temp.qd_replay_fn_marketing_recruitment_funnel()',
    asOf: { supply_gap: 'opened_at', leads: 'created_at' },
  },
  // 24 Sep 2026 (marketing, #905). reputation:no_public_review_link when a satisfied customer waits for an ask and no
  // review link is configured. Reviews that existed at the instant; the asks it writes are rolled back.
  fn_marketing_reputation: {
    replay: 'pg_temp.qd_replay_fn_marketing_reputation()',
    asOf: { reviews: 'created_at' },
  },
  // ── RELAYS: they pass on what another routine decided ─────────────────────────────────────────
  fn_spec_offer_failed: { relay: 'records a spec comparison the sales_engineer sweep reported failed; raises only after its fifth backed-off failure, never on a healthy day' },
  fn_wa_signature_watch: { relay: 'records a WhatsApp webhook wa_inbound itself refused for a bad X-Twilio-Signature; the refusal is the decision of the signature check, and nothing fires on a healthy day with no refused inbound' },
  fn_seat_clock_deliver: { relay: 'records a message the send door refused; the refusal is the door\'s decision' },
  fn_it_engineer_ingest_watch_findings: { relay: 'copies fn_it_detect\'s open it_watch_finding rows into the finding ledger' },
  fn_it_duty_settle: { relay: 'writes the failing items a duty reading hands it; the rule is the duty\'s' },
  fn_accountant_duty_settle: { relay: 'the accountant\'s twin of fn_it_duty_settle' },
  fn_accountant_duty_stage: { relay: 'records that an accountant duty stage raised; the error is the finding' },
  fn_it_loop_stage: { relay: 'records that an IT loop stage raised; the error is the finding' },
  fn_seat_duty_cross_review: { relay: 'records that a cross-family review could not be opened; the error from fn_seat_deliberation_open is the finding' },
  fn_seat_handoff: { relay: 'records a handoff that could not be opened; the error is the finding' },
  fn_ceo_accountant_notice_report_decide: { relay: 'the CEO\'s decision on an accountant report' },
  fn_ceo_sales_engineer_report_decide: { relay: 'the CEO\'s decision on a sales engineer report' },
  fn_it_journey_ingest: { relay: 'writes the failed steps a nightly journey or smoke run reports' },
  fn_it_restore_table_pick: { relay: 'records that the restore drill could not pick a table; the error is the finding' },
  // ── BASELINE: existed on 22 Sep 2026 and cannot be replayed yet ─────────────────────────────────
  fn_it_engineer_alert_tick: { baseline: 'monitor rules over it_watch_tick and it_engineer_scanner; replaying it runs the whole IT loop (handoffs, digest) and needs a side-effect-free split first' },
  fn_it_dropbox_health_record: { baseline: 'rules over a Dropbox API reading passed in as jsonb; the readings are not stored with a time' },
  fn_delivery_feedback_canary_tick: { baseline: 'posts a canary and judges the reply; nothing to replay without sending' },
  trg_it_judge_routine_change: { baseline: 'fires on a routine being changed; a healthy day has no DDL to replay' },
};
// Frozen. Adding a name here is how a gate gets softened; add a replay instead.
const BASELINE = new Set(['fn_it_engineer_alert_tick', 'fn_it_dropbox_health_record', 'fn_delivery_feedback_canary_tick', 'trg_it_judge_routine_change']);

// ── STATIC ────────────────────────────────────────────────────────────────────────────────────────
// name -> canonical body (the LAST file in MANIFEST order that defines it).
export function canonicalBodies(repo = REPO) {
  const manifest = readFileSync(join(repo, 'scripts', 'sql', 'MANIFEST.txt'), 'utf8')
    .split(/\r?\n/).map((l) => l.trim()).filter((l) => l.endsWith('.sql') && !l.startsWith('#'));
  const out = new Map();
  for (const f of manifest) {
    const p = join(repo, f);
    if (!existsSync(p)) continue;
    const src = readFileSync(p, 'utf8');
    const heads = [...src.matchAll(/create\s+or\s+replace\s+function\s+public\.(\w+)\s*\(/gi)];
    heads.forEach((m, i) => out.set(m[1].toLowerCase(), src.slice(m.index, heads[i + 1]?.index ?? src.length)));
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
    for (const { at } of INSTANTS) {
      const out = await replay(sql, name, entry, at);
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
