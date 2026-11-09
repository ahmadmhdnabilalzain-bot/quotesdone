// THE WEBSITE IS CHECKED FROM OUTSIDE EVERY FIVE MINUTES (it_engineer, 9 Nov 2026).
//
// The founder approved uptime monitoring on 9 Nov 2026 and has no monitoring account, so the check runs in our own
// stack: pg_cron job site_uptime_5min calls https://quotesdone.com/api/health over pg_net from the database (Supabase),
// outside Vercel, and after 3 completed failed checks in a row opens the IT engineer's finding (fn_it_duty_settle) and
// pages him (fn_notify_founder, kind uptime_alert). Before it, nothing called the website on a short clock from outside
// Vercel: resilience_ping runs on Vercel's own cron, and the GitHub cross-check is off with Actions since 26 Oct.
// scripts/sql/the_website_is_checked_from_outside_every_five_minutes.sql built it.
//
// This fails if the job is unscheduled, if the URL drifts to www (308: pg_net does not follow redirects, measured
// 9 Nov) or off /api/health, if the 3-in-a-row rule or its decision function goes, or if the page stops using the
// allowed uptime_alert kind. It reads the schema mirror (what production runs) together with the MANIFEST-listed SQL
// (what merges apply), because the mirror only catches up after the apply-at-merge and its regeneration.
//
//   node --test scripts/checks/the_website_is_checked_from_outside_every_five_minutes.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const ROOT = join(import.meta.dirname, '..', '..');
const manifest = readFileSync(join(ROOT, 'scripts/sql/MANIFEST.txt'), 'utf8').split('\n').map((l) => l.trim())
  .filter((l) => l && !l.startsWith('#')).map((l) => (l.startsWith('scripts/') ? l : `scripts/sql/${l}`));
const applied = manifest.filter((f) => existsSync(join(ROOT, f))).map((f) => readFileSync(join(ROOT, f), 'utf8')).join('\n');
const both = readSchemaMirror() + '\n' + applied;
// Code only: a comment that quotes the rule must not satisfy the check (apply-discipline, section 7).
const code = both.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

// The LAST definition wins, as at apply: the MANIFEST text follows the mirror in `code`.
const lastDefinition = (name) => {
  const re = new RegExp(`create or replace function public\\.${name}\\([^]*?\\n\\$(fn|function)\\$;?`, 'gi');
  const all = [...code.matchAll(re)];
  return all.length ? all[all.length - 1][0] : null;
};

test('site_uptime_5min is scheduled every five minutes, off the seat-duty minute, and names its seat', () => {
  assert.match(code, /cron\.schedule\('site_uptime_5min',\s*'2-59\/5 \* \* \* \*',\s*\$CRON\$[^$]*select public\.fn_site_uptime_tick\(\);\$CRON\$\)/,
    'site_uptime_5min is not scheduled at 2-59/5 calling fn_site_uptime_tick()');
  assert.doesNotMatch(code, /cron\.unschedule\('site_uptime_5min'\)/, 'site_uptime_5min is unscheduled by a later file');
  assert.match(code, /\('cron_job', 'site_uptime_5min', 'it_engineer'/, 'the job must name its seat in writer_seat');
  assert.match(code, /\('site_uptime_5min', 'Website uptime check'/, 'the job must have its cron_registry row');
});

test('the tick calls the APEX /api/health with a timeout, and treats only 200 as up', () => {
  const tick = lastDefinition('fn_site_uptime_tick');
  assert.ok(tick, 'fn_site_uptime_tick is not defined');
  assert.match(tick, /c_url\s+constant text := 'https:\/\/quotesdone\.com\/api\/health';/,
    'the URL must be the apex https://quotesdone.com/api/health (www answers 308 and pg_net does not follow redirects)');
  assert.doesNotMatch(tick, /www\.quotesdone\.com/, 'the tick must not call www (308)');
  assert.match(tick, /net\.http_get\(url := c_url,[^;]*timeout_milliseconds := \d+\)/, 'the request must carry a timeout');
  assert.match(tick, /from net\._http_response h/, 'the tick must read pg_net answers to earlier requests');
  assert.match(tick, /ok = \(h\.status_code = 200 and not coalesce\(h\.timed_out, false\) and h\.error_msg is null\)/,
    'only a 200 with no timeout and no error is up: a 404 from a missing route is a failure');
  assert.match(tick, /checked_at < now\(\) - interval '14 days' order by id limit \d+/, 'the 14-day purge must be batched');
});

test('three completed failures in a row open ONE finding through the IT engineer path and page with uptime_alert', () => {
  const verdict = lastDefinition('fn_site_uptime_verdict');
  assert.ok(verdict, 'fn_site_uptime_verdict (the pure 3-in-a-row decision) is not defined');
  assert.match(verdict, /not \(true = any \(z\.r\[1:z\.need\]\)\)/, 'the decision must require the last `need` completed checks all failed');
  assert.match(verdict, /greatest\(coalesce\(p_need, 3\), 1\)/, 'the default run of failures is 3');

  const tick = lastDefinition('fn_site_uptime_tick');
  assert.match(tick, /c_need\s+constant int\s+:= 3;/, 'the tick must use 3 failures in a row');
  assert.match(tick, /public\.fn_site_uptime_verdict\(v_recent, v_open, c_need\)/, 'the tick must decide through fn_site_uptime_verdict');
  assert.match(tick, /where url = c_url and answered_at is not null order by checked_at desc limit c_need/,
    'the decision reads the last completed checks only (a lost check is not a failure)');
  assert.match(tick, /public\.fn_it_duty_settle\('site_uptime', v_items\)/, 'the finding must go through fn_it_duty_settle (open, keep, close)');
  assert.match(tick, /public\.fn_notify_founder\(\s*p_event => 'THE WEBSITE IS DOWN[^;]*p_level => 'critical', p_kind => 'uptime_alert', p_dedupe_key => 'site_uptime_down:' \|\| v_epoch/,
    'the outage page must use fn_notify_founder with the allowed kind uptime_alert, deduped per outage');
});

test('the checks table and the routines are closed to browser roles', () => {
  assert.match(code, /alter table public\.site_uptime_check enable row level security/);
  assert.match(code, /create policy site_uptime_check_service_role_only on public\.site_uptime_check/);
  assert.match(code, /revoke all on public\.site_uptime_check from anon, authenticated/);
  assert.match(code, /revoke execute on function public\.fn_site_uptime_tick\(\) from public, anon, authenticated/);
  assert.match(code, /revoke execute on function public\.fn_site_uptime_verdict\(boolean\[\], boolean, integer\) from public, anon, authenticated/);
});

test('the monitor arms itself only after the first 200, so a deploy in progress never pages anyone', () => {
  assert.match(both, /if v_action = 'open' and not exists \(select 1 from public\.site_uptime_check where url = c_url and ok\) then\s+v_action := 'none';/,
    'fn_site_uptime_tick must not open a finding before the url has ever answered 200');
});
