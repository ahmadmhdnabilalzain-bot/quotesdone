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
import { pendingNotes } from '../lib/pending_sql.mjs';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FRAME = 'scripts/sql/every_seat_duty_has_an_owner_a_clock_and_a_check.sql';
const PING = functionSource('resilience_ping');
const MANIFEST = read('scripts/sql/MANIFEST.txt').split(/\r?\n/);
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

/** Every SQL file that registers a seat duty, in MANIFEST order then pending files by name. */
export function dutyFiles() {
  // A probe that is never applied (its pending note says 'A PROBE') may insert a ZZ DEMO seat_duty row inside its
  // rolled-back transaction (16 Nov, each_seat_works_..._probe.sql): that registers no duty, so it is not a duty file.
  const notes = pendingNotes(REPO);
  const neverApplied = (f) => /^\s*A PROBE\b/.test(notes.get('scripts/sql/' + f) || '');
  const all = readdirSync(join(REPO, 'scripts/sql')).filter((f) => f.endsWith('.sql') && !neverApplied(f))
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
    // One revoke may list many routines (an_order_is_a_conversation_until_its_outcome.sql closes eighteen in one
    // statement, 16 Nov); every name inside a revoke that ends 'from public, anon, authenticated' is closed.
    // A body copied from production keeps pg_get_functiondef's upper case (SET search_path TO, 16 Nov): either spelling
    // pins it. (Upper-case CREATE definitions are outside this check's scope as before; their live ACLs and search_path
    // were read 17 Nov: all eleven closed to postgres and service_role and pinned.)
    const revoked = new Set([...src.matchAll(/revoke execute on function ([^;]*?) from public, anon, authenticated/gi)]
      .flatMap((r) => [...r[1].matchAll(/public\.(\w+)\(/g)].map((n) => n[1])));
    for (const m of made) {
      const name = m[1];
      // the head of THIS definition (a revoke or a probe naming the routine may come earlier in the file)
      const body = src.slice(m.index);
      const head = body.slice(0, body.indexOf('$'));
      assert.match(head, /set search_path to 'public', 'pg_temp'/i, `${f}: ${name} does not pin its search_path`);
      assert.ok(revoked.has(name), `${f}: ${name} is not revoked`);
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

// SPREAD OVER THE FIVE MINUTES (it_engineer, 11 Nov 2026). All 89 seat_duty:<duty> jobs were made on one schedule by
// fn_seat_duty_isolate, so they all started at :x0 and :x5; edge calls in the 10 s after a mark had p90 3.4 s against
// 1.4 s the rest of the time. The generator now gives each job a minute of the five ('N-59/5 * * * *').
// Fails if the LAST definition of fn_seat_duty_isolate (MANIFEST order, then pending files) schedules a fixed minute.
const SPREAD = 'scripts/sql/the_seat_duty_jobs_are_spread_over_the_five_minutes.sql';
test('the seat-duty job generator gives each job a minute of the five, never one shared minute', () => {
  const rank = (f) => { const i = MANIFEST.indexOf('scripts/sql/' + f); return i < 0 ? 1e9 : i; };
  const defs = readdirSync(join(REPO, 'scripts/sql')).filter((f) => f.endsWith('.sql'))
    .filter((f) => rank(f) < 1e9 || pending('scripts/sql/' + f))
    .sort((a, b) => rank(a) - rank(b) || a.localeCompare(b))
    .map((f) => code(read('scripts/sql/' + f)))
    .flatMap((s) => [...s.matchAll(/create or replace function public\.fn_seat_duty_isolate\([\s\S]*?\$function\$;/g)].map((m) => m[0]));
  assert.ok(defs.length, 'no file defines fn_seat_duty_isolate');
  const last = defs[defs.length - 1];
  assert.doesNotMatch(last, /cron\.schedule\([^,]+,\s*'[^']*\*\/5 \* \* \* \*'/, 'fn_seat_duty_isolate schedules every duty on one fixed minute again');
  assert.match(last, /cron\.schedule\([^,]+,\s*v_min \|\| '-59\/5 \* \* \* \*'/, 'fn_seat_duty_isolate does not give the job its own minute of the five');
  assert.match(last, /order by c\.seat, c\.every_five, m\.n/, 'fn_seat_duty_isolate no longer picks the minute holding the fewest seat_duty jobs');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
const SKIP = hasToken ? false : 'no Supabase management token';

test('production: every seat_duty job runs every five minutes and no minute of the five holds more than ceil(n/5)', { skip: SKIP }, async () => {
  // Measured inside a rolled-back request, with the spreading file replayed first while it is pending.
  const measure = String.raw`
do $m$ declare o jsonb; begin
  with j as (select jobname, schedule, substring(schedule from '^([0-4])-59/5 \* \* \* \*$')::integer as minute
               from cron.job where left(jobname, 10) = 'seat_duty:' and active)
  select jsonb_build_object('n', (select count(*) from j),
           'off', (select coalesce(jsonb_agg(jobname || ' ' || schedule), '[]') from j where minute is null),
           'max', (select coalesce(max(c), 0) from (select count(*) c from j where minute is not null group by minute) x),
           'own_without_job', (select count(*) from public.seat_duty s where s.own_job
                                 and not exists (select 1 from cron.job c where c.jobname = 'seat_duty:' || s.duty)))
    into o;
  raise exception 'CHK<<%>>', o::text;
end $m$;`;
  let o;
  try { await replaySql((pending(SPREAD) ? read(SPREAD) + '\n' : '') + measure, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the measurement failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the measurement committed instead of rolling back');
  assert.deepEqual(o.off, [], 'seat_duty jobs not on one minute of the five (every five minutes)');
  assert.equal(o.own_without_job, 0, 'an own_job duty has no job');
  assert.ok(o.max <= Math.ceil(o.n / 5), `a minute of the five holds ${o.max} of ${o.n} seat_duty jobs, over ceil(n/5) = ${Math.ceil(o.n / 5)}`);
});

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
  -- avg_ms is given: since one_slow_duty_never_wedges_the_seat_duty_tick.sql (634a8952, 18 Oct 2026) the tick moves an
  -- UNMEASURED duty to its own cron job instead of running it inline, so a probe duty must be a measured, fast one
  insert into public.seat_duty(duty, owner_seat, every, routine, what, owner_file, avg_ms) values
   ('it_engineer.zz_demo_ok','it_engineer','15 minutes','fn_zz_demo_duty_ok','ZZ DEMO ok','scripts/sql/x.sql', 10),
   ('it_engineer.zz_demo_bad','it_engineer','15 minutes','fn_zz_demo_duty_bad','ZZ DEMO bad','scripts/sql/x.sql', 10),
   ('it_engineer.zz_demo_missing','it_engineer','15 minutes','fn_zz_demo_nope','ZZ DEMO missing','scripts/sql/x.sql', 10);
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
