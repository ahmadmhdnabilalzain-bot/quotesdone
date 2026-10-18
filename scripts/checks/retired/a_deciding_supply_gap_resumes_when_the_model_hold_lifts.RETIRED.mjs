// RETIRED 5 Oct 2026 (it_engineer) WITH ITS SUBJECT. A supply gap no longer waits in 'deciding' for the model: the LLM
// burn audit of 5 Oct 2026 (R8) measured 77 gaps holding one identical question with demand 0, and
// scripts/sql/a_held_question_is_paid_for_once_and_test_traffic_never_waits_for_a_model.sql defers a gap nobody waits
// on by rule (rule:nobody_waiting) and files nothing. What replaces this check:
// scripts/checks/a_held_question_is_paid_for_once.test.mjs ("a supply gap nobody waits on is decided by code").
//
// A SUPPLY GAP IN 'deciding' WAITS ONLY ON THE MODEL HOLD, AND RESUMES WHEN IT LIFTS (it_engineer, 29 Sep 2026).
//
// MEASURED 29 Sep 2026 20:00 UTC: supply_gap held 70 rows in 'deciding' (140 open, 7 recruit). All 70 point at a
// reasoning_held_question of surface sales_engineer.supply_gap in status 'held' with 0 attempts, and
// fn_kernel_paid_provider_gate answers rule 'founder_hold' (20 of 20 routes held). fn_reason_held_due returns nothing
// under that rule and claims 'held' rows otherwise; resilience_ping replays what it returns (replayHeld) and delivers
// the answer to fn_reason_apply_sales_engineer__supply_gap, which moves the gap to recruit or deferred. Nothing else
// holds them: no failed or expired question (those return the gap to 'open'), no missing apply routine.
//
// WHAT FAILS IF THAT STOPS BEING TRUE
//   * static: the replay, the gate, the apply or the reopen-on-failure is gone from the code;
//   * production (token present): a 'deciding' gap whose question is not 'held' on its surface, or - with the hold
//     lifted - a deciding gap whose question has not been attempted within a day of the gate opening.
//
//   node --test scripts/checks/a_deciding_supply_gap_resumes_when_the_model_hold_lifts.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const SCHEMA = readSchemaMirror();
const fn = (name) => {
  const i = SCHEMA.indexOf(`CREATE OR REPLACE FUNCTION public.${name}(`);
  assert.ok(i >= 0, `${name} is not in the schema mirror`);
  return SCHEMA.slice(i, SCHEMA.indexOf('$function$', SCHEMA.indexOf('$function$', i) + 10));
};

test('the gap files its decision, the replay resumes it when the gate opens, the answer moves it on', () => {
  assert.match(fn('fn_sales_engineer_supply_gap'), /status = 'deciding', held_id = public\.fn_seat_duty_reason\('sales_engineer', 'sales_engineer\.supply_gap'/);
  assert.match(fn('fn_sales_engineer_supply_gap'), /sgp\.status = 'deciding' and exists[\s\S]{0,160}h\.status in \('failed', 'expired'\)/,
    'a failed or expired decision no longer returns the gap to open');
  const due = fn('fn_reason_held_due');
  assert.match(due, /fn_kernel_paid_provider_gate\(/);
  assert.match(due, /in \('founder_hold', 'no_paid_ai_switch', 'empty_route_state'\) then\s+return '\[\]'::jsonb/);
  assert.match(due, /where status = 'held' and attempts < 3/, 'the replay no longer claims held questions');
  assert.match(fn('fn_reason_apply_sales_engineer__supply_gap'), /set status = case when v_choice = 'recruit' then 'recruit' else 'deferred' end/);
  assert.match(readFileSync(join(REPO, 'supabase/functions/resilience_ping/index.ts'), 'utf8'), /step\('reasoning_held', async \(\) => replayHeld\(admin,/);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production: every deciding gap waits on a held question, and only the hold keeps it waiting', { skip: hasToken ? false : 'no Supabase management token in this environment' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const [r] = await sql(`
    select public.fn_kernel_paid_provider_gate('hold-probe/not-a-model')->>'rule' as rule,
           count(*)::int as deciding,
           count(*) filter (where h.id is null or h.status <> 'held' or h.surface <> 'sales_engineer.supply_gap')::int as not_held,
           count(*) filter (where h.status = 'held' and coalesce(h.last_attempt_at, h.created_at) < now() - interval '1 day')::int as unattempted_a_day
      from public.supply_gap g left join public.reasoning_held_question h on h.id = g.held_id
     where g.status = 'deciding'`);
  assert.equal(r.not_held, 0, `${r.not_held} deciding gap(s) wait on no held question - nothing will ever decide them`);
  const held = ['founder_hold', 'no_paid_ai_switch', 'empty_route_state'].includes(r.rule);
  if (!held) assert.equal(r.unattempted_a_day, 0, `the hold is lifted (rule ${r.rule}) and ${r.unattempted_a_day} deciding gap(s) were not replayed in a day`);
  console.log(`# ${r.deciding} deciding, gate rule ${r.rule}`);
});
