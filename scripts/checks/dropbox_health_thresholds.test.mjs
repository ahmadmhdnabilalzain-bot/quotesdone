// DROPBOX IS CHECKED EVERY DAY, AND HOW LOUD EACH READING IS FOLLOWS THE THRESHOLDS.
//
// scripts/sql/dropbox_is_checked_every_day_login_and_space.sql. This fails when:
//   1. a routine in the file is not revoked or does not pin its search_path, or the file stops routing
//      through fn_it_duty_settle (the IT loop) and emails or reports to anyone itself;
//   2. resilience_ping stops calling op 'health' as its own step, or drops it from either response;
//   (production; the file itself is run inside the probe and everything rolls back through
//    raise exception 'CHK<<...>>', so this works before the apply and never leaves a row)
//   3. with invented readings: 60% raises nothing, 70% is quiet (warn), 85% is loud (high) and
//      closes the quiet one, 69.9% closes both; auth is high at once, a provider outage is warn, the
//      next reading closes what it no longer finds, and a readable login with an unreadable space is
//      its own quiet finding.
//
//   node --test scripts/checks/dropbox_health_thresholds.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/dropbox_is_checked_every_day_login_and_space.sql';
const read = (f) => readFileSync(join(REPO, f), 'utf8');

test('every routine is revoked and pins its search_path; findings go only through the IT loop', () => {
  const src = read(FILE);
  const fns = [...src.matchAll(/create or replace function (public\.\w+)\(([^)]*)\)[\s\S]*?\$fn\$;/g)];
  assert.equal(fns.length, 2);
  for (const [body, name] of fns) {
    assert.match(body, /set search_path to 'public', 'pg_temp'/, name + ' has no pinned search_path');
    assert.match(src, new RegExp('revoke execute on function ' + name.replace('.', '\\.') + '\\([^)]*\\) from public, anon, authenticated'), name + ' is not revoked');
  }
  assert.match(src, /fn_it_duty_settle\('dropbox_login'/);
  assert.match(src, /fn_it_duty_settle\('dropbox_space'/);
  assert.doesNotMatch(src, /notifications|fn_notify_founder|fn_support_report_to_ceo|fn_seat_handoff\(|delivery\.request/i,
    'a finding reaches people only through it_engineer_finding and the loop');
});

test('resilience_ping calls op health as its own step, and both responses carry it', () => {
  const ts = read('supabase/functions/resilience_ping/index.ts');
  assert.match(ts, /async function dropboxHealthTick\(\)[\s\S]*?fn_it_dropbox_health_due[\s\S]*?op: 'health'/);
  assert.match(ts, /const dropboxHealth = await dropboxHealthTick\(\);/);
  assert.equal((ts.match(/healthy: true,[^\n]*\bdropboxHealth\b/g) || []).length, 1);
  assert.equal((ts.match(/healthy: false,[^\n]*\bdropboxHealth\b/g) || []).length, 1);
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('the thresholds and classes, with invented readings, rolled back', { skip: !hasToken && 'no Supabase token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const body = `
    do $p$
    declare o jsonb := '{}'::jsonb; r jsonb;
      ok constant jsonb := '{"auth_ok":true,"write_ok":true,"read_ok":true,"delete_ok":true,"plan":"zz_demo"}';
    begin
      -- open/closed and severity of every dropbox key, after each reading
      r := public.fn_it_dropbox_health_record(ok || '{"used":60,"allocated":100}');
      o := o || jsonb_build_object('r60', r->>'status');
      r := public.fn_it_dropbox_health_record(ok || '{"used":70,"allocated":100}');
      o := o || jsonb_build_object('r70', r->>'status', 'quiet70', (select public.fn_it_engineer_severity(blast, affected, started_at)
            from public.it_engineer_finding where issue_key = 'duty:dropbox_space:space_quiet' and closed_at is null));
      r := public.fn_it_dropbox_health_record(ok || '{"used":85,"allocated":100}');
      o := o || jsonb_build_object('loud85', (select public.fn_it_engineer_severity(blast, affected, started_at)
            from public.it_engineer_finding where issue_key = 'duty:dropbox_space:space_loud' and closed_at is null),
            'quiet_after85', (select closed_at is null from public.it_engineer_finding where issue_key = 'duty:dropbox_space:space_quiet'));
      r := public.fn_it_dropbox_health_record(ok || '{"used":69.9,"allocated":100}');
      o := o || jsonb_build_object('r699', r->>'status', 'open_space_after699', (select count(*) from public.it_engineer_finding
            where issue_key like 'duty:dropbox_space:%' and closed_at is null));
      r := public.fn_it_dropbox_health_record('{"write_ok":false,"error":"no_dropbox_auth","class":"auth","used":10,"allocated":100}');
      o := o || jsonb_build_object('auth', r->>'status', 'auth_sev', (select public.fn_it_engineer_severity(blast, affected, started_at)
            from public.it_engineer_finding where issue_key = 'duty:dropbox_login:auth' and closed_at is null));
      r := public.fn_it_dropbox_health_record('{"write_ok":false,"error":"get_space_usage 503","class":"provider_outage"}');
      o := o || jsonb_build_object('outage_sev', (select public.fn_it_engineer_severity(blast, affected, started_at)
            from public.it_engineer_finding where issue_key = 'duty:dropbox_login:provider_outage' and closed_at is null),
            'auth_after_outage', (select closed_at is null from public.it_engineer_finding where issue_key = 'duty:dropbox_login:auth'),
            'due_after_error', public.fn_it_dropbox_health_due());
      r := public.fn_it_dropbox_health_record('{"write_ok":false,"error":"boom","class":"made_up"}');
      o := o || jsonb_build_object('made_up_class', r->>'class');
      r := public.fn_it_dropbox_health_record(ok || '{"allocated":0,"space_error":"get_space_usage 429","space_class":"rate_limit"}');
      o := o || jsonb_build_object('unread', r->>'status', 'unread_open', (select closed_at is null from public.it_engineer_finding
            where issue_key = 'duty:dropbox_space:space_unread'),
            'login_open_after_ok', (select count(*) from public.it_engineer_finding where issue_key like 'duty:dropbox_login:%' and closed_at is null));
      raise exception 'CHK<<%>>', o;
    end $p$;`;
  let r;
  try { await sql('begin;\n' + read(FILE) + '\n' + body); } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    if (!m) throw e;
    r = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(r, 'the probe must end in CHK');
  assert.equal(r.r60, 'ok');
  assert.equal(r.r70, 'warn');
  assert.equal(r.quiet70, 'warn', '70% is a quiet finding');
  assert.equal(r.loud85, 'high', '85% is a loud finding');
  assert.equal(r.quiet_after85, false, 'the loud finding replaces the quiet one');
  assert.equal(r.r699, 'ok');
  assert.equal(Number(r.open_space_after699), 0);
  assert.equal(r.auth, 'error');
  assert.equal(r.auth_sev, 'high', 'a refused login is loud at once');
  assert.equal(r.outage_sev, 'warn', 'a provider outage is quiet until it is six hours old');
  assert.equal(r.auth_after_outage, false, 'the next reading closes what it no longer finds');
  assert.equal(r.due_after_error, false, 'a failed reading is retried after two hours, not every tick');
  assert.equal(r.made_up_class, 'internal');
  assert.equal(r.unread, 'warn');
  assert.equal(r.unread_open, true);
  assert.equal(Number(r.login_open_after_ok), 0);
});
