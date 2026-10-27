// A ROLLED-BACK PROBE MAY FILE DEMO SEAT WORK UNDER ITS OWN SWITCH (it_engineer, 27 Oct 2026).
//
// scripts/sql/a_rolled_back_probe_may_file_demo_seat_work_under_its_own_switch.sql. Fails when:
//   1. (static) the switch line is gone, is reachable by any other setting name, or the 1199 guard below it changed;
//   2. (production, one rolled-back request) with the switch unset a ZZ DEMO handoff is filed or a ZZ DEMO org task
//      is kept (ruling 1199 broken), or with it on either one is NOT filed (the probes go blind again).
//
//   node --test scripts/checks/a_rolled_back_probe_may_file_demo_seat_work_under_its_own_switch.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';
import { seatWorkFixtures } from '../lib/seat_work_fixtures.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const R = (f) => readFileSync(join(REPO, f), 'utf8');
const FILE = 'scripts/sql/a_rolled_back_probe_may_file_demo_seat_work_under_its_own_switch.sql';
const BEFORE = 'scripts/sql/demo_activity_files_no_seat_task_or_handoff.sql';
const body = (s) => s.slice(s.indexOf('create or replace function public.fn_seat_work_is_demo'), s.indexOf('end $f$;'))
  .split('\n').map((l) => l.replace(/--.*$/, '').trimEnd()).filter(Boolean).join('\n');

test('the switch is one line in front of the unchanged 1199 guard', () => {
  const now = body(R(FILE)), was = body(R(BEFORE));
  const line = "  if coalesce(current_setting('qd.probe_files_demo_handoff', true), '') = 'on' then return false; end if;";
  assert.ok(now.includes(line), 'the switch line is missing or changed');
  assert.equal(now.replace(line + '\n', ''), was, 'the 1199 guard itself changed, not only the switch in front of it');
  assert.equal((R(FILE).match(/current_setting\(/g) || []).length, 1, 'a second setting reaches the guard');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production, rolled back: off, ZZ DEMO files nothing; on, it files the handoff and the task', { skip: hasToken ? false : 'no Supabase management token', timeout: 300000 }, async () => {
  // the prelude replays the file (while pending) and turns the switch ON; the first half turns it off again
  const rows = await replaySql(seatWorkFixtures() + `
;select set_config('qd.probe_files_demo_handoff', 'off', true)
;create temp table zz_sw (k text, v text) on commit drop
;insert into zz_sw select 'off_guard', public.fn_seat_work_is_demo('ZZ DEMO switch probe', '{}'::jsonb)::text
;insert into zz_sw select 'off_handoff', public.fn_seat_handoff('customer_support', 'sales_engineer', 'spec.not_sure',
    'inquiries', 'zz-switch-probe-off', '{"note":"ZZ DEMO switch probe"}'::jsonb)::text
;insert into public.org_tasks (title, detail, status, assigned_agent) values ('ZZ DEMO switch probe off', 'probe', 'assigned', 'sales_engineer')
;insert into zz_sw select 'off_task', count(*)::text from public.org_tasks where title = 'ZZ DEMO switch probe off'
;select set_config('qd.probe_files_demo_handoff', 'on', true)
;insert into zz_sw select 'on_guard', public.fn_seat_work_is_demo('ZZ DEMO switch probe', '{}'::jsonb)::text
;insert into zz_sw select 'on_handoff', (public.fn_seat_handoff('customer_support', 'sales_engineer', 'spec.not_sure',
    'inquiries', 'zz-switch-probe-on', '{"note":"ZZ DEMO switch probe"}'::jsonb) is not null)::text
;insert into public.org_tasks (title, detail, status, assigned_agent) values ('ZZ DEMO switch probe on', 'probe', 'assigned', 'sales_engineer')
;insert into zz_sw select 'on_task', count(*)::text from public.org_tasks where title = 'ZZ DEMO switch probe on'
;select jsonb_object_agg(k, v) as r from zz_sw`, { label: 'seat work fixtures switch', rows: true, retry: false });
  assert.deepEqual(rows[0].r, { off_guard: 'true', off_handoff: null, off_task: '0', on_guard: 'false', on_handoff: 'true', on_task: '1' });
});
