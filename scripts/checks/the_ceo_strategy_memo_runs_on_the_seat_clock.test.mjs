// THE CEO'S MONTHLY STRATEGY MEMO RUNS ON THE SEAT CLOCK, NOT ON PG_CRON (30 Sep 2026, it_engineer; the duty is the
// ceo's, instruction 1013).
//
// MEASURED: the memo was the only seat work scheduled on pg_cron (job 'ceo-strategy-memo-monthly'), outside the seat
// clock (public.seat_duty / fn_seat_duties_tick) whose health check files a finding for a duty that is overdue or failing.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: the routine loses its revoke or its pinned search_path; the file carries both (or neither of) a pending
//     note and a MANIFEST line;
//   * production, in ONE aborted transaction (the file replayed first while pending; nothing commits, so the memo the
//     probe writes and the founder notice it queues are rolled back): the pg_cron job is back; the duty is missing,
//     disabled or not callable; the ended month's memo is neither on file nor written when its
//     day comes (asked as of the 2nd of the current month, so the answer does not depend on today or on whether the
//     duty already ran — 5 Oct 2026: 'due to the tick' was false on every run after the day's tick); the memo is due before the 2nd; an August memo would be written
//     late; on the 2nd the ended month's memo is not written; on a later day it is written twice.
//
//   node --test scripts/checks/the_ceo_strategy_memo_runs_on_the_seat_clock.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/the_ceo_strategy_memo_runs_on_the_seat_clock.sql';
const pending = () => existsSync(join(REPO, 'scripts/sql/pending', FILE.split('/').pop().replace(/\.sql$/, '.txt')));

test('static: revoke, pinned search_path, pending XOR applied', () => {
  const s = read(FILE);
  assert.match(s, /fn_ceo_strategy_memo_now\(p_today date default null, p_first_month date default date '2026-09-01'\)[\s\S]{0,120}security definer\s+set search_path to 'public', 'pg_temp'/);
  assert.match(s, /revoke execute on function public\.fn_ceo_strategy_memo_now\(date, date\) from public, anon, authenticated;/);
  assert.match(s, /select cron\.unschedule\(jobid\) from cron\.job where jobname = 'ceo-strategy-memo-monthly';/);
  const manifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim());
  assert.ok(pending() !== manifest.includes(FILE), 'exactly one of a pending note and a MANIFEST line');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: registered, enabled, callable, the ended month on file or written, monthly, and off pg_cron', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const replay = pending() ? read(FILE) + '\n' : '';
  let o;
  try {
    await sql(replay + `
do $$
declare a jsonb; b jsonb; c jsonb; d jsonb; e jsonb;
  m date := date_trunc('month', (now() at time zone 'Asia/Dubai')::date - interval '1 month')::date;
begin
  -- the ended month, whatever today is: run as of the 2nd of this month, its memo is on file or written now
  e := public.fn_ceo_strategy_memo_now((date_trunc('month', (now() at time zone 'Asia/Dubai')::date) + interval '1 day')::date);
  a :=public.fn_ceo_strategy_memo_now(date '2026-10-01');
  b := public.fn_ceo_strategy_memo_now(date '2026-09-30');
  -- the write path, one month back (September has not ended yet): 2 Sep writes August's memo, 9 Sep finds it
  delete from public.ceo_strategy_memo where month = date '2026-08-01';   -- inside the aborted transaction only
  c := public.fn_ceo_strategy_memo_now(date '2026-09-02', date '2026-08-01');
  d := public.fn_ceo_strategy_memo_now(date '2026-09-09', date '2026-08-01');
  raise exception 'CHK<<%>>', jsonb_build_object(
    'cron', exists (select 1 from cron.job where jobname = 'ceo-strategy-memo-monthly' or command ilike '%fn_ceo_strategy_memo%'),
    'duty', (select jsonb_build_object('owner', owner_seat, 'enabled', enabled, 'every', every::text,
                    'callable', public.fn_seat_duty_routine_exists(routine))
               from public.seat_duty where duty = 'ceo.strategy_memo'),
    'ended', jsonb_build_object('due', e->'due', 'is_the_ended_month', e->>'month' = to_char(m, 'YYYY-MM'),
                                'on_file', (select count(*) from public.ceo_strategy_memo where month = m)),
    'oct1', a->'due', 'sep30', b->'due',
    'sep2', jsonb_build_object('due', c->'due', 'month', c->'month', 'already', coalesce(c->'already', 'false'::jsonb)),
    'sep9', jsonb_build_object('due', d->'due', 'already', d->'already'),
    'memos', (select count(*) from public.ceo_strategy_memo where month = date '2026-08-01'))::text;
end $$;`, { retry: false });
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 800));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(o, 'the probe committed instead of rolling back');
  assert.deepEqual(o, {
    cron: false,
    duty: { owner: 'ceo', enabled: true, every: '1 day', callable: true },
    ended: { due: true, is_the_ended_month: true, on_file: 1 },
    oct1: false, sep30: false,
    sep2: { due: true, month: '2026-08', already: false },
    sep9: { due: true, already: true },
    memos: 1,
  });
});
