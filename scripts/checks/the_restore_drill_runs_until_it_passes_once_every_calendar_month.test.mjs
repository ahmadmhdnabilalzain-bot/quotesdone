// THE RESTORE DRILL RUNS UNTIL IT PASSES, ONCE EVERY CALENDAR MONTH.
//
// scripts/sql/the_restore_drill_runs_until_it_passes_once_every_calendar_month.sql, run with the due check inside ONE
// transaction that ends in raise exception 'CHK<<...>>', so nothing is kept. Fails when:
//   1. a month with no passing drill, and no drill in 20 hours, is not due (28 Sep 2026: 2 drills ever, none passing
//      on real rows, and the next due ~15 Oct because the cadence counted attempts);
//   2. a month that already has a passing drill is due again (the drill would run every day).
//
//   node --test scripts/checks/the_restore_drill_runs_until_it_passes_once_every_calendar_month.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { sql } from '../lib/db.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const ddl = readFileSync(join(REPO, 'scripts/sql/the_restore_drill_runs_until_it_passes_once_every_calendar_month.sql'), 'utf8')
  .split('\n-- ── VERDICT')[0];

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('no pass this month -> due; a pass this month -> not due', { skip: hasToken ? false : 'no management token' }, async () => {
  const body = `do $p$ declare o jsonb; begin
      -- the state the fix is for: no passing drill this month, no drill or pick in the last day
      delete from public.it_restore_drill_result where ran_at >= date_trunc('month', now());
      delete from public.agent_runs where agent = 'it_engineer' and counts->>'job' in ('duty:restore_table', 'restore_table_pick')
         and started_at > now() - interval '1 day';
      o := jsonb_build_object('open_finding', exists (select 1 from public.it_engineer_finding where closed_at is null and issue_key like 'duty:restore\\_table:%'),
                              'due_without_pass', public.fn_it_restore_table_due());
      -- a passing drill this month, recorded 21 hours ago (so the 30-day schedule is not what answers)
      insert into public.it_restore_drill_result (ok, detail, ran_at, subject)
      values (true, jsonb_build_object('restored', 5), greatest(date_trunc('month', now()), now() - interval '21 hours'), 'CHK probe');
      insert into public.agent_runs (agent, status, started_at, finished_at, counts)
      values ('it_engineer', 'ok', now() - interval '21 hours', now() - interval '21 hours', jsonb_build_object('job', 'duty:restore_table'));
      o := o || jsonb_build_object('due_with_pass', public.fn_it_restore_table_due());
      raise exception 'CHK<<%>>', o;
    end $p$;`;
  let r;
  try { await sql('begin;\n' + ddl + '\n' + body); } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    r = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(r, 'the probe must end in CHK');
  assert.equal(r.due_without_pass, true, 'a month with no passing drill must be due');
  if (!r.open_finding) assert.equal(r.due_with_pass, false, 'a month that already passed must not be due again');
});
