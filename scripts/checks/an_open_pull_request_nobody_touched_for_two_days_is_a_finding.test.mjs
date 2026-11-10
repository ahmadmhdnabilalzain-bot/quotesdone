// AN OPEN PULL REQUEST NOBODY HAS TOUCHED FOR TWO DAYS IS A FINDING (it_engineer, 10 Nov 2026).
//
// Measured 10 Nov 2026: 15 pull requests opened by Claude sessions between about 20 Oct and 9 Nov sat open and unmerged
// for days; some carried SQL never applied. Nothing watched them. Fix: IT duty 25, open_pull_requests
//   scripts/sql/an_open_pull_request_nobody_touched_for_two_days_is_a_finding.sql   (schedule, threshold, record, founder line)
//   supabase/functions/_shared/stale_pull_requests.ts (+ .test.ts)                   (the pure stale decision)
//   supabase/functions/_shared/it_duty_readings.ts takeOpenPullRequests              (the GitHub read, same token as duty 24)
//   supabase/functions/resilience_ping/ticks/it_engineer/later_duties.ts             (the daily step)
//
// This fails if the duty stops being daily or loses its owner, the 48 hour or 7 day thresholds move, dependabot stops being
// excluded, a partial or failed GitHub reading is settled (which would close real findings), the finding stops being one
// per pull request or stops going through fn_it_duty_settle, the founder's list names a pull request younger than 7 days or
// leaks a title, a routine is left open or unpinned, or the file is rehearsed on production and its probe does not say OK.
//   node --test scripts/checks/an_open_pull_request_nobody_touched_for_two_days_is_a_finding.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { read, ROOT, canonicalBody, productionSkip, rehearseChain } from '../lib/canonical_body.mjs';
import { join } from 'node:path';

const FILE = 'scripts/sql/an_open_pull_request_nobody_touched_for_two_days_is_a_finding.sql';
const PROBE = FILE.replace(/\.sql$/, '_probe.sql');
const noComments = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const sql = noComments(read(FILE));

test('the duty runs once a day and belongs to the it_engineer', () => {
  assert.match(sql, /\('open_pull_requests',\s*interval '1 day',[^]*?'it_engineer'\)\s*on conflict \(duty\) do update set every = excluded\.every/);
  const step = noComments(read('supabase/functions/resilience_ping/ticks/it_engineer/later_duties.ts'));
  assert.match(step, /step\('open_pull_requests'/, 'the heartbeat step is gone');
  assert.match(step, /fn_it_scheduled_due[^;]*includes\('open_pull_requests'\)/, 'the step must be gated by the daily schedule');
  assert.match(step, /takeOpenPullRequests\(sec\)/);
  assert.match(step, /fn_it_open_pull_requests_record/);
});

test('thresholds: 48 hours idle (pure helper), 7 days for the founder (it_threshold)', () => {
  const pure = noComments(read('supabase/functions/_shared/stale_pull_requests.ts'));
  assert.match(pure, /export const STALE_PR_HOURS = 48;/);
  assert.match(pure, /hoursBetween\(p\.updated_at, now\) > staleAfterHours/, 'exactly 48 hours must not be stale');
  assert.match(pure, /login === 'dependabot\[bot\]'/);
  assert.match(pure, /startsWith\('dependabot\/'\)/);
  assert.match(pure, /SQL_PREFIX = 'scripts\/sql\/'/);
  assert.match(sql, /\('pr_founder_days',\s*7,\s*'days'/);
});

test('the GitHub reading is the duty-24 token, and a partial list is never settled', () => {
  const reader = noComments(read('supabase/functions/_shared/it_duty_readings.ts'));
  const fn = reader.slice(reader.indexOf('export async function takeOpenPullRequests'));
  assert.match(fn, /sec\('github_token'\)/);
  assert.match(fn, /pulls\?state=open&per_page=100/);
  assert.match(fn, /return unavailable\(`GitHub pulls/, 'a page GitHub would not give must make the whole reading unavailable');
  assert.match(fn, /more than 1000 open pull requests/);
  assert.match(fn, /stalePullRequests\(prs, now, filesByNumber\)/, 'the decision must be the pure helper');
  assert.match(fn, /filesByNumber\[p\.number\] = null/, 'unreadable files must be null, not "no SQL"');
});

test('one finding per stale pull request through fn_it_duty_settle; an unavailable reading settles nothing', () => {
  const { body } = canonicalBody('fn_it_open_pull_requests_record');
  const code = noComments(body);
  assert.match(code, /'item', 'pr:' \|\| \(x->>'number'\)/, 'one item, so one finding, per pull request number');
  assert.match(code, /fn_it_duty_settle\('open_pull_requests', v_items\)/);
  assert.match(code, /if p->>'basis' is distinct from 'measured'[^]*?return jsonb_build_object\('recorded', false/, 'an unavailable reading must return before settling');
  assert.match(code, /'owner_seat', 'it_engineer'/);
  assert.match(code, /'touches_sql'/);
  assert.match(code, /SQL is waiting to be applied/);
  assert.ok(code.indexOf("'recorded', false") < code.indexOf('fn_it_duty_settle'), 'the guard must come before the settle');
  assert.ok(code.indexOf("fn_it_duty_ran('open_pull_requests'") > code.indexOf('fn_it_duty_settle'), 'a run is recorded only after a settle');
});

test('the founder hears only of pull requests open more than 7 days, once, by number', () => {
  const { body } = canonicalBody('fn_it_session_fix_list');
  const code = noComments(body);
  assert.match(code, /issue_key like 'duty:open\\_pull\\_requests:pr:%'/);
  assert.match(code, /f\.closed_at is null/);
  assert.match(code, /\(f\.evidence->>'created_at'\)::timestamptz < now\(\) - make_interval\(days => public\.fn_it_threshold\('pr_founder_days'\)::int\)/);
  assert.match(code, /string_agg\('#' \|\| \(f\.evidence->>'number'\)/, 'numbers only: a title can carry an internal word');
  assert.doesNotMatch(code.slice(code.indexOf("'duty:open")), /evidence->>'title'/, 'a title must not reach the founder');
  assert.match(code, /where rn <= 12/, 'the list stays at twelve lines');
});

test('every routine the file defines is closed to clients and pinned', () => {
  for (const fn of ['fn_it_open_pull_requests_record', 'fn_it_session_fix_list']) {
    const re = new RegExp(`create or replace function public\\.${fn}\\([^]*?set search_path to 'public', 'pg_temp'`, 'i');
    assert.match(sql, re, `${fn} must be security definer with a pinned search_path`);
  }
  assert.match(sql, /revoke execute on function public\.fn_it_open_pull_requests_record\(jsonb\) from public, anon, authenticated/);
  assert.match(sql, /revoke execute on function public\.fn_it_session_fix_list\(\) from public, anon, authenticated/);
});

test('the file is pending (a note, no MANIFEST line) until it is applied, and its probe has its own note', () => {
  const manifest = read('scripts/sql/MANIFEST.txt');
  const note = `scripts/sql/pending/${FILE.split('/').pop().replace(/\.sql$/, '.txt')}`;
  const applied = manifest.split('\n').includes(FILE);
  assert.ok(applied !== existsSync(join(ROOT, note)), 'a file is either listed in MANIFEST or has a pending note, never both and never neither');
  assert.ok(existsSync(join(ROOT, PROBE)));
  assert.ok(existsSync(join(ROOT, note.replace(/\.txt$/, '_probe.txt'))), 'the probe needs its own pending note');
});

test('production, rolled back: the file runs and its probe answers PROBE OK', { skip: productionSkip() }, async () => {
  const v = await rehearseChain([FILE], PROBE);
  assert.match(v, /^PROBE OK/, v);
});
