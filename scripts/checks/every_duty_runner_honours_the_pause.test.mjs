// EVERY DUTY RUNNER HONOURS THE ONE PAUSE SWITCH (it_engineer, 29 Sep 2026).
// public.duty_pause (scripts/sql/every_duty_runner_honours_one_pause_switch.sql) pauses one duty wherever it runs.
// It is only a switch if every runner reads it: this fails the moment one stops, or a new runner is added that
// settles duties (fn_it_duty_settle) without reading it. Offline: reads source only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { functionSource } from '../lib/function_sources.mjs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const between = (s, a, b) => { const i = s.indexOf(a); assert.ok(i >= 0, 'missing: ' + a); const j = s.indexOf(b, i + a.length); return s.slice(i, j < 0 ? undefined : j); };

test('resilience_ping skips a paused plan step and a paused later-duty step (rotate_by_api among them)', () => {
  const s = functionSource('resilience_ping');
  const main = between(s, 'const steps: Step[] = [];', 'await runSteps(');
  assert.match(main, /pausedDuties\(admin\)/, 'the plan loop does not read duty_pause');
  assert.match(main, /pause\.has\('resilience_ping\.' \+ name\)/, 'the plan loop does not skip a paused step');
  const later = between(s, 'async function itLaterDutiesTick', "await step('renewal'");
  assert.match(later, /const pause = await pausedDuties\(admin\)/, 'the later-duty runner does not read duty_pause');
  assert.match(later, /if \(pause\.has\('resilience_ping\.' \+ name\)\) \{ out\[name\] = PAUSED; return; \}/, 'the later-duty step wrapper runs a paused duty');
  assert.ok(s.indexOf("step('rotate_by_api'") > s.indexOf('async function itLaterDutiesTick'), 'rotate_by_api left the paused wrapper');
});

test('marketing skips a paused duty before running it', () => {
  const s = between(read('supabase/functions/marketing/index.ts'), 'export async function runDuties', "admin.rpc('fn_it_duty_settle'");
  assert.match(s, /pausedDuties\(admin\)/);
  assert.ok(s.indexOf("pause.has('marketing.' + d.name)") < s.indexOf('await d.run('), 'the pause is read after the duty runs');
});

test('fn_seat_duties_tick does not start a paused seat duty', () => {
  const sql = read('scripts/sql/every_duty_runner_honours_one_pause_switch.sql');
  const fn = between(sql, 'create or replace function public.fn_seat_duties_tick', '$function$;');
  assert.match(fn, /where enabled\s+-- [^\n]*\n\s+and not exists \(select 1 from public\.duty_pause dp where dp\.duty = sd\.duty\)/);
  // once applied, the live mirror must carry it too
  const mirror = new URL('../../supabase/schema/full_schema.sql', import.meta.url);
  const pending = new URL('../sql/pending/every_duty_runner_honours_one_pause_switch.txt', import.meta.url);
  if (existsSync(mirror) && !existsSync(pending)) {
    const live = between(readFileSync(mirror, 'utf8'), 'FUNCTION public.fn_seat_duties_tick', '$function$;');
    assert.match(live, /duty_pause/, 'the applied fn_seat_duties_tick does not read duty_pause');
  }
});

test('no other edge function settles duties without reading the pause', () => {
  const root = new URL('../../supabase/functions/', import.meta.url);
  const runners = [];
  for (const d of readdirSync(root, { withFileTypes: true })) {
    if (!d.isDirectory() || d.name.startsWith('_')) continue;
    const f = new URL(d.name + '/index.ts', root);
    if (!existsSync(f)) continue;
    const s = readFileSync(f, 'utf8');
    if (/for \(const \w+ of DUTIES\)/.test(s) && !/pausedDuties\(/.test(s)) runners.push(d.name);
  }
  assert.deepEqual(runners, [], 'a DUTIES loop that ignores public.duty_pause');
});
