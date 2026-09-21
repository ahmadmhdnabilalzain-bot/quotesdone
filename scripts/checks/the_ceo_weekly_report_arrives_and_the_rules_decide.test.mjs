// THE CEO'S WEEKLY REPORT ARRIVES, AND THE CEO'S RULES DECIDE (21 Sep 2026, ceo).
//
// Measured that day: the weekly report failed delivery on 14 and 21 Sep with one fault (fn_notify_founder's
// jsonb answer stored in a bigint), the heartbeat recorded the step as healthy, and none of the ten active
// public.ceo_decision rules had ever written a ceo_decision_log row because nothing evaluated them.
// scripts/sql/the_weekly_report_arrives_and_the_rules_decide.sql fixes both. This fails if either returns:
//
//   1. every active ceo_decision rule has an evaluator (fn_ceo_decisions_evaluate dry run is ok and names
//      no rule 'no_evaluator') -- a rule added without one is the ten-silent-rules defect again;
//   2. the last closed week's report, once its configured slot is more than three hours past, reached the
//      founder (founder_submitted_at set) with a PDF attached, and the error is quoted if it did not;
//   3. fn_ceo_weekly_report_deliver does not route the report through fn_notify_founder (an alert, with a
//      WhatsApp copy and no attachment, is the wrong vehicle and was the failing call).
//
// READ-ONLY: the evaluator is called with p_dry_run => true, which writes nothing.
//   node --test scripts/checks/the_ceo_weekly_report_arrives_and_the_rules_decide.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token in this environment';
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

async function rows(q) {
  const r = await sql(`set local statement_timeout = '15s'; ${q}`);
  return Array.isArray(r) ? r : [];
}

test('every active CEO decision rule is evaluated', { skip: SKIP }, async () => {
  const [r] = await rows(`select public.fn_ceo_decisions_evaluate(true) as e`);
  const e = r?.e;
  assert.ok(e, 'fn_ceo_decisions_evaluate did not answer');
  const silent = (e.rules || []).filter(x => x.state === 'no_evaluator').map(x => x.rule);
  assert.equal(silent.length, 0, 'active ceo_decision rule(s) nothing evaluates: ' + silent.join(', '));
  assert.equal(e.ok, true, 'evaluator not ok: ' + e.error);
});

test('the last closed week\'s CEO report reached the founder with its PDF', { skip: SKIP }, async () => {
  const [r] = await rows(`
    with cfg as (
      select coalesce((select nullif(btrim(value),'')::int  from public.app_secrets where key='ceo_weekly_report_local_dow'), 1) as dow,
             coalesce((select nullif(btrim(value),'')::time from public.app_secrets where key='ceo_weekly_report_local_time'), time '08:00') as at),
    wk as (
      select (date_trunc('week', (now() at time zone 'Asia/Dubai')::date) - interval '7 days')::date as ws,
             date_trunc('week', (now() at time zone 'Asia/Dubai')::date)::date + (cfg.dow - 1) + cfg.at as slot
        from cfg)
    select wk.ws, wk.slot, (now() at time zone 'Asia/Dubai') > wk.slot + interval '3 hours' as due,
           w.id, w.status, w.founder_submitted_at, w.pdf_path, w.last_delivery_error
      from wk left join public.ceo_weekly_report w
        on w.report_key = 'quotesdone:' || to_char(wk.ws, 'IYYY-"W"IW')`);
  if (!r?.due) return;   // the slot plus its grace has not passed yet this week
  assert.ok(r.id, `no CEO weekly report was generated for the week of ${r.ws} (slot ${r.slot} Dubai)`);
  assert.ok(r.founder_submitted_at,
    `the CEO weekly report for the week of ${r.ws} did not reach the founder: status ${r.status}, error: ${r.last_delivery_error}`);
  assert.ok(r.pdf_path, `the CEO weekly report for the week of ${r.ws} was delivered without its PDF`);
});

test('the weekly report is delivered as a report, not through the alert routine', { skip: SKIP }, async () => {
  const [r] = await rows(`select prosrc ~ 'fn_notify_founder\\s*\\(' as uses_alert
                            from pg_proc where oid = 'public.fn_ceo_weekly_report_deliver(bigint)'::regprocedure`);
  assert.equal(r?.uses_alert, false, 'fn_ceo_weekly_report_deliver calls fn_notify_founder again');
});
