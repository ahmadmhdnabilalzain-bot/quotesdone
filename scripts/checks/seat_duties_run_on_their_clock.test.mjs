// EVERY SEAT DUTY HAS AN OWNER, A CLOCK AND A CHECK (23 Sep 2026, it_engineer; founder_instruction 898).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: a SQL file that registers a seat duty loses its routine, its revoke or its pinned search_path; the
//     resilience_ping step that runs the clock is unwired; a duty file matches words instead of filing a reasoning
//     question (a `~*` / `ilike` over a message body in a duty routine);
//   * production, in ONE aborted transaction (the pending files replayed first, nothing commits, ZZ DEMO only):
//       - a due duty does not run, a failing one stops the others, three failures or a missing routine is not a
//         finding, a recovered duty's finding is not closed;
//       - a judgement is not filed as a high-stakes think() decision in the owning seat's queue;
//   * production, once public.seat_duty is applied: ANY registered duty that is overdue, failing, orphaned or
//     missing its routine (fn_seat_duty_health() is not empty). This is the standing check on every duty.
//
//   node --test scripts/checks/seat_duties_run_on_their_clock.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FRAME = 'scripts/sql/every_seat_duty_has_an_owner_a_clock_and_a_check.sql';
const PING = read('supabase/functions/resilience_ping/index.ts');
const MANIFEST = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

/** Every SQL file that registers a seat duty, in MANIFEST order then pending files by name. */
export function dutyFiles() {
  const all = readdirSync(join(REPO, 'scripts/sql')).filter((f) => f.endsWith('.sql'))
    .filter((f) => /insert into public\.seat_duty\b/.test(code(read('scripts/sql/' + f))));
  const rank = (f) => { const i = MANIFEST.indexOf('scripts/sql/' + f); return i < 0 ? 1e9 : i; };
  return all.sort((a, b) => rank(a) - rank(b) || a.localeCompare(b)).map((f) => 'scripts/sql/' + f);
}
const pending = (f) => existsSync(join(REPO, 'scripts/sql/pending', f.split('/').pop().replace(/\.sql$/, '.txt')));

test('the clock is wired into resilience_ping and scheduled', () => {
  assert.match(PING, /seatDuties:\s*\{\s*run:\s*seatDutiesTick\s*\}/, 'STEP_RUN has no seatDuties step');
  assert.match(PING, /rpc\('fn_seat_duties_tick'/, 'seatDutiesTick does not call fn_seat_duties_tick');
  assert.match(read(FRAME), /insert into public\.resilience_step[\s\S]{0,80}'seatDuties'/, 'no resilience_step row schedules seatDuties');
});

test('every duty file: routines revoked with a pinned search_path, each duty routine defined, pending XOR MANIFEST', () => {
  for (const f of [FRAME, ...dutyFiles()]) {
    const src = code(read(f));
    assert.ok(!/^\s*(begin|commit)\s*;/im.test(src), `${f}: a migration file carries its own transaction control`);
    const made = [...src.matchAll(/create or replace function public\.(\w+)\(([^)]*)\)/g)];
    for (const [, name] of made) {
      const body = src.slice(src.indexOf(`function public.${name}(`));
      const head = body.slice(0, body.indexOf('$'));
      assert.match(head, /set search_path to 'public', 'pg_temp'/, `${f}: ${name} does not pin its search_path`);
      assert.match(src, new RegExp(`revoke execute on function public\\.${name}\\([^)]*\\) from public, anon, authenticated`), `${f}: ${name} is not revoked`);
    }
    for (const m of src.matchAll(/insert into public\.seat_duty[^;]*?values([\s\S]*?)on conflict/g)) {
      for (const r of m[1].matchAll(/'(fn_[a-z0-9_]+)'/g)) {
        assert.ok(made.some(([, n]) => n === r[1]), `${f}: the duty routine ${r[1]} is not defined in the file that registers it`);
      }
    }
    for (const t of src.matchAll(/create table if not exists public\.(\w+)/g)) {
      assert.match(src, new RegExp(`alter table public\\.${t[1]} enable row level security`), `${f}: ${t[1]} has no RLS`);
      assert.match(src, new RegExp(`create policy \\w+ on public\\.${t[1]}`), `${f}: ${t[1]} has no policy`);
    }
    assert.ok(pending(f) !== MANIFEST.includes(f), `${f}: exactly one of a pending note and a MANIFEST line`);
  }
});

test('no duty decides meaning with a word list (founder_instruction 890)', () => {
  // A duty reads numbers and dates deterministically; what TEXT means is filed with fn_seat_duty_reason.
  for (const f of dutyFiles()) {
    const src = code(read(f));
    assert.ok(!/\b(body|message|comment|question|raw_input|summary|notes|content)\b\s*(~\*|ilike|~)\s*'/i.test(src),
      `${f}: a duty matches words in a text field; file the judgement with fn_seat_duty_reason instead`);
  }
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';

async function probe(block) {
  const { sql } = await import('../lib/db.mjs');
  const replay = [FRAME, ...dutyFiles()].filter(pending).map(read).join('\n');
  try { await replaySql(replay + '\n' + block, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    return JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.fail('the probe committed instead of rolling back');
}

test('production, aborted: a due duty runs, a failing one is isolated and becomes a finding, a judgement is reasoned', { skip: SKIP }, async () => {
  const o = await probe(String.raw`
do $$ declare o jsonb; v jsonb; h bigint; begin
  create or replace function public.fn_zz_demo_duty_ok() returns jsonb language sql as $f$ select '{"did":1}'::jsonb $f$;
  create or replace function public.fn_zz_demo_duty_bad() returns jsonb language plpgsql as $f$ begin raise exception 'boom'; end $f$;
  update public.seat_duty set last_started_at = now() where true;   -- only the ZZ DEMO duties are due in this probe
  insert into public.seat_duty(duty, owner_seat, every, routine, what, owner_file) values
   ('it_engineer.zz_demo_ok','it_engineer','15 minutes','fn_zz_demo_duty_ok','ZZ DEMO ok','scripts/sql/x.sql'),
   ('it_engineer.zz_demo_bad','it_engineer','15 minutes','fn_zz_demo_duty_bad','ZZ DEMO bad','scripts/sql/x.sql'),
   ('it_engineer.zz_demo_missing','it_engineer','15 minutes','fn_zz_demo_nope','ZZ DEMO missing','scripts/sql/x.sql');
  update public.seat_duty set failures = 2 where duty = 'it_engineer.zz_demo_bad';
  perform public.fn_it_engineer_finding_upsert('seat_duty:it_engineer.zz_demo_ok', 'ZZ DEMO stale', 'x', 'agent_facing');
  v := public.fn_seat_duties_tick(30);
  h := public.fn_seat_duty_reason('it_engineer','it_engineer.zz_demo','ZZ DEMO which?', '[{"id":"a","meaning":"A"},{"id":"b","meaning":"B"}]', '{"x":1}', '{"k":1}', 'zz_demo:probe');
  o := jsonb_build_object(
    'ok_ran', (select last_ok_at is not null and last_result = '{"did":1}' from seat_duty where duty = 'it_engineer.zz_demo_ok'),
    'bad_failures', (select failures from seat_duty where duty = 'it_engineer.zz_demo_bad'),
    'open', (select coalesce(jsonb_agg(issue_key order by issue_key), '[]') from it_engineer_finding where issue_key like 'seat_duty:it_engineer.zz_demo%' and closed_at is null),
    'held', (select jsonb_build_object('seat', seat, 'stakes', request->>'stakes', 'options', jsonb_array_length(request->'decision'->'options'), 'status', status) from reasoning_held_question where id = h));
  raise exception 'CHK<<%>>', o::text;
end $$;`);
  assert.equal(o.ok_ran, true, 'a due duty did not run or its result was not recorded');
  assert.equal(o.bad_failures, 3, 'a failing duty did not count its failure');
  assert.deepEqual(o.open, ['seat_duty:it_engineer.zz_demo_bad', 'seat_duty:it_engineer.zz_demo_missing'], 'findings are not exactly the broken duties (the recovered one must close)');
  assert.deepEqual(o.held, { seat: 'it_engineer', stakes: 'high', options: 2, status: 'held' }, 'the judgement is not a high-stakes reasoning decision in the seat queue');
});

test('production: every registered seat duty is on its clock (fn_seat_duty_health is empty)', { skip: SKIP }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const [{ present }] = await sql(`select to_regclass('public.seat_duty') is not null as present`, { readOnly: true });
  if (!present) {
    assert.ok(pending(FRAME), 'public.seat_duty is not on production and the framework file has no pending note');
    return;
  }
  // Not the API read-only role: fn_seat_duty_health is service-role only (42501). It is STABLE; nothing is written.
  const [{ h }] = await sql(`select public.fn_seat_duty_health() as h`);
  assert.deepEqual(h, [], 'seat duties not being done: ' + JSON.stringify(h).slice(0, 1500));
});
