// THE IT ENGINEER READS GMAIL POSTMASTER DAILY, AND A SPAM SPIKE STOPS THE INVITATIONS (it_engineer, 24 Sep 2026).
//
// WHAT FAILS IF THE CAUSE RETURNS:
//   static (always):
//     * the reading table loses RLS, its service-role-only policy, its revoke, or the constraint that a no-data
//       reading carries no numbers (a zero where Postmaster published nothing reads as a clean day);
//     * a routine in the file loses its pinned search_path or its exact-signature revoke;
//     * the invitation pause is written a second time instead of called: exactly one routine in the file sets
//       invite_enabled off, and both the #943 brake and the Postmaster record call it;
//     * the pause loses its once-per-Postmaster-day guard, or no-data stops carrying an open finding;
//     * the IT daily line drops a key the canonical body carries, or stops carrying the Postmaster sentence;
//     * resilience_ping stops running the step, or the duty moves to pg_cron;
//     * the integration registry, the pending note or the module's thresholds drift.
//   production, in ONE aborted transaction (skips without a Supabase management token; ZZ DEMO domain only,
//   nothing commits, nothing is sent): 0.15% files a finding and does not pause; 0.4% pauses once; the same
//   Postmaster day never pauses twice; no data holds the finding; a clean day closes it; unreadable is one
//   configuration finding.
//
//   node --test scripts/checks/the_it_engineer_reads_gmail_postmaster_daily.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const NAME = 'the_it_engineer_reads_gmail_postmaster_daily_and_a_spam_spike_stops_the_invitations';
const FILE = `scripts/sql/${NAME}.sql`;
const SQL = read(FILE);
const CANONICAL_DAILY = 'scripts/sql/the_it_engineer_watches_every_integration_and_fixes_what_it_can.sql';

// The body of one `create or replace function public.<name>(` ... `$fn$;` in a file.
function body(src, name) {
  const i = src.indexOf(`create or replace function public.${name}(`);
  assert.ok(i >= 0, `${name} is not defined`);
  const j = src.indexOf('$fn$;', i);
  assert.ok(j > i, `${name} has no end`);
  return src.slice(i, j);
}
const code = (s) => s.replace(/--.*$/gm, '');   // comments may describe a shape; only code is judged

test('static: the file states its subject, and ends in a verdict row', () => {
  assert.match(SQL, /^-- THE IT ENGINEER READS GMAIL POSTMASTER/);
  for (const h of ['WHAT WAS MEASURED', 'WHAT THIS CHANGES', 'WHAT THIS DOES NOT CHANGE', 'Prevented by:']) assert.ok(SQL.includes(h), 'header lacks ' + h);
  assert.match(SQL, /'PROBE OK' else 'PROBE FAILED[^']*' end as verdict;\s*$/);
  assert.ok(!/raise notice/i.test(SQL), 'reports through NOTICE, which nobody reads');
});

test('static: the reading table is service-role only and a no-data row carries no numbers', () => {
  const s = code(SQL);
  assert.match(s, /alter table public\.it_postmaster_reading enable row level security;/);
  assert.match(s, /create policy it_postmaster_reading_service_role_only on public\.it_postmaster_reading\s+as permissive for all to public using \(false\) with check \(false\);/);
  assert.match(s, /revoke all on public\.it_postmaster_reading from anon, authenticated;/);
  assert.match(s, /basis = 'measured' or \(spam_ratio is null and reputation is null and spf_ratio is null and dkim_ratio is null and dmarc_ratio is null\)/);
  assert.match(s, /primary key \(domain, read_on\)/);
});

test('static: every routine pins search_path and is revoked by its exact signature', () => {
  const sigs = { fn_invite_campaign_pause: 'text, text, jsonb, jsonb', fn_invite_same_day_brake: '', fn_it_postmaster_record: 'jsonb' };
  const defined = [...SQL.matchAll(/create or replace function public\.(fn_[a-z0-9_]+)\(/g)].map((m) => m[1]);
  for (const fn of defined) {
    assert.match(body(SQL, fn), /security definer\s+set search_path to 'public', 'pg_temp'/, fn + ' has no pinned search_path');
    if (fn === 'fn_it_daily_line') continue;   // CREATE OR REPLACE of an existing routine keeps its ACL
    assert.ok(fn in sigs, fn + ' is new here and has no expected signature in this check');
    assert.ok(SQL.includes(`revoke execute on function public.${fn}(${sigs[fn]}) from public, anon, authenticated;`), fn + ' is not revoked by its signature');
  }
});

test('static: ONE pause, called by the #943 brake and by the Postmaster record', () => {
  const s = code(SQL);
  const writers = [...s.matchAll(/create or replace function public\.(fn_[a-z0-9_]+)\(/g)].map((m) => m[1])
    .filter((fn) => /update app_secrets set value = 'false' where key = 'invite_enabled'/.test(code(body(SQL, fn))));
  assert.deepEqual(writers, ['fn_invite_campaign_pause'], 'the invitation pause is written in more than one routine');
  const pause = code(body(SQL, 'fn_invite_campaign_pause'));
  assert.match(pause, /update notifications set status = 'cancelled'\s+where type = 'supplier_invite' and status = 'queued';/);
  assert.match(pause, /'deliverability:supplier_invite'/, 'the pause no longer opens the #943 finding');
  assert.match(pause, /insert into agent_runs/);
  const brake = code(body(SQL, 'fn_invite_same_day_brake'));
  assert.match(brake, /perform public\.fn_invite_campaign_pause\('invite_same_day_brake', v_why,/);
  // the brake's thresholds are the #943 ones, unchanged
  const orig = read('scripts/sql/an_invitation_bounce_or_complaint_spike_stops_the_campaign_the_same_hour.sql');
  for (const line of ['v_br_max numeric := coalesce((c->>\'same_day_pause_bounce_rate\')::numeric, 0.05);',
                      'v_cr_max numeric := coalesce((c->>\'pause_complaint_rate\')::numeric, 0.003);',
                      'v_b_min  int     := coalesce((c->>\'same_day_pause_min_bounces\')::int, 3);',
                      'v_c_min  int     := coalesce((c->>\'same_day_pause_min_complaints\')::int, 1);']) {
    assert.ok(orig.includes(line) && brake.includes(line), 'the brake threshold changed: ' + line);
  }
  const rec = code(body(SQL, 'fn_it_postmaster_record'));
  assert.match(rec, /public\.fn_invite_campaign_pause\('it_engineer_postmaster',/);
});

test('static: the record pauses once per Postmaster day, carries on silence, and settles through the duty', () => {
  const rec = code(body(SQL, 'fn_it_postmaster_record'));
  assert.match(rec, /not exists \(select 1 from public\.it_postmaster_reading\s+where domain = v_dom and stats_day = v_stats and paused_at is not null\)/);
  assert.match(rec, /v_basis = 'measured' and coalesce\(\(p_r->'verdict'->>'pause'\)::boolean, false\)/, 'a no-data reading could pause');
  // Review of PR #961: invite_enabled is 'false' today; pausing a stopped campaign wrote an error run (test.failed),
  // rewrote the #943 finding and spent the day's once-only pause. The pause is gated on a RUNNING campaign.
  const gate = rec.slice(rec.indexOf('if v_basis = \'measured\' and coalesce((p_r->\'verdict\'->>\'pause\')'), rec.indexOf('fn_invite_campaign_pause('));
  assert.match(gate, /coalesce\(\(select value from public\.app_secrets where key = 'invite_enabled'\), 'false'\) = 'true'/,
    'the Postmaster pause is not gated on invite_enabled = true');
  assert.equal((rec.match(/set paused_at = now\(\)/g) || []).length, 1, 'paused_at is set outside the pause branch');
  assert.ok(rec.indexOf('set paused_at = now()') > rec.indexOf('fn_invite_campaign_pause('), 'paused_at is set before a pause happened');
  assert.match(rec, /paused_at = case when t\.stats_day is not distinct from excluded\.stats_day then t\.paused_at end/,
    'a rerun returning a newer stats day inherits the old day\'s paused_at');
  assert.match(rec, /'carried', true/, 'no data would close an open spam finding');
  assert.match(rec, /'config', true/, 'an unreadable Postmaster is re-raised every day');
  assert.match(rec, /public\.fn_it_duty_settle\('postmaster', v_items\)/);
  assert.match(rec, /public\.fn_it_duty_ran\('postmaster'/);
  assert.match(code(SQL), /\('postmaster', interval '1 day',/);
});

test('static: the IT daily line keeps every canonical key and carries the Postmaster sentence', () => {
  const keys = (b) => new Set([...code(b).matchAll(/^\s*'([a-z_]+)', \(?/gm)].map((m) => m[1]));
  const was = keys(body(read(CANONICAL_DAILY), 'fn_it_daily_line'));
  const now = keys(body(SQL, 'fn_it_daily_line'));
  assert.ok(was.size >= 15, 'the canonical key scan found only ' + was.size + ' keys');
  for (const k of was) assert.ok(now.has(k), 'the daily line dropped ' + k);
  assert.ok(now.has('gmail_postmaster'));
  const b = code(body(SQL, 'fn_it_daily_line'));
  assert.match(b, /coalesce\(v_ev->'gmail_postmaster'->>'line', 'Gmail Postmaster: not read yet/);
  assert.match(b, /if v_local::time < time '19:00'/);
});

test('static: resilience_ping runs it on the heartbeat, the registry and the pending note are in place', () => {
  const ping = functionSource('resilience_ping');
  assert.match(ping, /import \{ runPostmasterStep, takePostmasterReading \} from '(?:\.\.\/)+_shared\/it_postmaster_readings\.ts';/);
  // Deploy order: the function ships on merge, the SQL may be pending; the step goes through runPostmasterStep,
  // which records a missing routine/table as skipped (tested in it_postmaster_readings.test.ts).
  assert.match(ping, /step\('postmaster', \(\) => runPostmasterStep\(/);
  const mod = read('supabase/functions/_shared/it_postmaster_readings.ts');
  assert.match(mod, /SCHEMA_MISSING = new Set\(\['42883', '42P01', 'PGRST202', 'PGRST205'\]\)/);
  assert.match(mod, /rpc\('fn_it_postmaster_record', \{ p_r: reading \}\)/);
  assert.ok(!/cron\.schedule/.test(SQL), 'the duty is scheduled by resilience_ping, never pg_cron');
  const reg = JSON.parse(read('supabase/functions/_shared/integration_registry.json'));
  const e = reg.integrations.google_postmaster;
  assert.ok(e && e.hosts.includes('gmailpostmastertools.googleapis.com') && e.secrets.includes('google_postmaster_refresh_token'));
  assert.equal(e.owner_seat, 'it_engineer');
  const note = join(REPO, 'scripts/sql/pending', NAME + '.txt');
  const manifest = read('scripts/sql/MANIFEST.txt').split('\n').map((l) => l.trim());
  assert.ok(existsSync(note) ? !manifest.includes(FILE) : manifest.includes(FILE), 'the file must be pending XOR in MANIFEST');
  const ts = read('supabase/functions/_shared/it_postmaster_readings.ts');
  assert.match(ts, /export const SPAM_FINDING_RATIO = 0\.001;/);
  assert.match(ts, /export const SPAM_PAUSE_RATIO = 0\.003;/);
  assert.match(ts, /gmailpostmastertools\.googleapis\.com\/v1\/domains\//);
  assert.match(ts, /'no data \(volume below Postmaster threshold or not yet published\)'/);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('production, aborted: a spike files, pauses once, holds on silence and closes on a clean day',
  { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const pending = existsSync(join(REPO, 'scripts/sql/pending', NAME + '.txt'));
  const r = (spam, pause, finding, sd = '2026-09-20') => `{"domain":"zz-demo.example.invalid","basis":"measured","stats_day":"${sd}",
    "spam_ratio":${spam},"reputation":"HIGH","spf":1,"dkim":1,"dmarc":1,"reason":null,"line":"ZZ DEMO ${spam}",
    "verdict":{"finding":${finding},"pause":${pause},"reasons":["ZZ DEMO spam ${spam}"]}}`;
  const block = String.raw`
do $$ declare o jsonb := '{}'; k text := 'duty:postmaster:deliverability:zz-demo.example.invalid'; wf0 jsonb; begin
  -- a STOPPED campaign is not paused again: finding yes, run row no, #943 finding untouched, paused_at unset
  update public.app_secrets set value = 'false' where key = 'invite_enabled';
  select evidence into wf0 from public.it_watch_finding where detector_key = 'deliverability:supplier_invite';
  perform public.fn_it_postmaster_record('${r(0.004, true, true, '2026-09-19')}');
  o := o || jsonb_build_object('s_f', (select count(*) from public.it_engineer_finding where issue_key = k and closed_at is null),
    's_run', (select count(*) from public.agent_runs where agent = 'it_engineer_postmaster' and finished_at > now() - interval '1 minute'),
    's_wf', (select evidence is not distinct from wf0 from public.it_watch_finding where detector_key = 'deliverability:supplier_invite')
            or (wf0 is null and not exists (select 1 from public.it_watch_finding where detector_key = 'deliverability:supplier_invite')),
    's_paused', (select paused_at is not null from public.it_postmaster_reading where domain = 'zz-demo.example.invalid'));
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  perform public.fn_it_postmaster_record('${r(0.0015, false, true)}');
  o := o || jsonb_build_object('f1', (select count(*) from public.it_engineer_finding where issue_key = k and closed_at is null),
                               'on1', (select value from public.app_secrets where key = 'invite_enabled'));
  perform public.fn_it_postmaster_record('${r(0.004, true, true)}');
  o := o || jsonb_build_object('on2', (select value from public.app_secrets where key = 'invite_enabled'),
    'paused', (select paused_at is not null from public.it_postmaster_reading where domain = 'zz-demo.example.invalid'),
    'run', (select count(*) from public.agent_runs where agent = 'it_engineer_postmaster' and finished_at > now() - interval '1 minute'),
    'wf', (select evidence->>'paused_by' from public.it_watch_finding where detector_key = 'deliverability:supplier_invite'));
  update public.app_secrets set value = 'true' where key = 'invite_enabled';
  perform public.fn_it_postmaster_record('${r(0.004, true, true)}');
  o := o || jsonb_build_object('on3', (select value from public.app_secrets where key = 'invite_enabled'));
  -- a rerun the same read day that returns a NEWER stats day does not inherit the old day's paused_at
  perform public.fn_it_postmaster_record('${r(0.0002, false, false, '2026-09-21')}');
  o := o || jsonb_build_object('cleared', (select paused_at is null from public.it_postmaster_reading where domain = 'zz-demo.example.invalid'));
  perform public.fn_it_postmaster_record('${r(0.0015, false, true)}');   -- reopen the finding for the silence cases
  perform public.fn_it_postmaster_record('{"domain":"zz-demo.example.invalid","basis":"no_data","stats_day":null,"reason":"ZZ DEMO below threshold","line":"ZZ DEMO no data","verdict":{"finding":false,"pause":false,"reasons":[]}}');
  o := o || jsonb_build_object('f_held', (select count(*) from public.it_engineer_finding where issue_key = k and closed_at is null));
  perform public.fn_it_postmaster_record('{"domain":"zz-demo.example.invalid","basis":"unavailable","stats_day":null,"reason":"ZZ DEMO no token","line":"ZZ DEMO unread","verdict":{"finding":false,"pause":false,"reasons":[]}}');
  o := o || jsonb_build_object('unread', (select count(*) from public.it_engineer_finding
                                           where issue_key = 'duty:postmaster:unreadable:zz-demo.example.invalid' and closed_at is null));
  perform public.fn_it_postmaster_record('${r(0.0002, false, false)}');
  o := o || jsonb_build_object('f_closed', (select count(*) from public.it_engineer_finding where issue_key = k and closed_at is null));
  begin
    insert into public.it_postmaster_reading (domain, read_on, basis, spam_ratio, line) values ('zz-demo.example.invalid', date '2000-01-01', 'no_data', 0, 'x');
    o := o || jsonb_build_object('zero_refused', false);
  exception when check_violation then o := o || jsonb_build_object('zero_refused', true); end;
  raise exception 'CHK<<%>>', o::text;
end $$;`;
  let o, committed = false;
  try { await replaySql((pending ? SQL : '') + '\n' + block, { retry: false }); committed = true; }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 1200));
    o = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(!committed, 'the probe committed instead of rolling back');
  assert.equal(o.s_f, 1, 'a stopped campaign got no finding for an over-limit reading');
  assert.equal(o.s_run, 0, 'a stopped campaign was paused again: an error run (test.failed) was written');
  assert.equal(o.s_wf, true, 'a stopped campaign had its #943 finding rewritten');
  assert.equal(o.s_paused, false, 'paused_at was set although nothing was paused');
  assert.equal(o.cleared, true, 'a newer stats day inherited the old day\'s paused_at');
  assert.equal(o.f1, 1, '0.15% did not file a finding');
  assert.equal(o.on1, 'true', '0.15% paused the invitations');
  assert.equal(o.on2, 'false', '0.4% did not pause the invitations');
  assert.equal(o.paused, true);
  assert.equal(o.run, 1, 'the pause left no agent_runs row');
  assert.equal(o.wf, 'it_engineer_postmaster', 'the #943 finding does not say who paused');
  assert.equal(o.on3, 'true', 'the same Postmaster day paused a second time, overriding a hand resume');
  assert.equal(o.f_held, 1, 'no data closed an open spam finding');
  assert.equal(o.unread, 1, 'an unreadable Postmaster is not a configuration finding');
  assert.equal(o.f_closed, 0, 'a clean day did not close the finding');
  assert.equal(o.zero_refused, true, 'a no-data row accepted a zero spam rate');
});
