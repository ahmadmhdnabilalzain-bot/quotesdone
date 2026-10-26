// THE IT ENGINEER'S DUTIES 19-24 DO WHAT THEIR FILES SAY, ON TOP OF DUTIES 9-18.
//
// Founder, 14 Sep 2026: "add all for accountant and IT". Duties 19-24 reuse duties 9-18
// (the_it_engineer_takes_on_seven_more_duties.sql, every_new_bug_leaves_a_playbook_entry_...sql):
//   19 the file half is duty 9's sample made stricter (opens, and the storage copy hashed against Dropbox);
//      the table half is the_it_engineer_restores_a_table_sample_every_month.sql
//   20 renewals_warn_the_accountant_at_sixty_and_thirty_days.sql
//   21 duty 10's sender check, with its failure classes in it_playbook and a blocklist refusal never a listing
//   22 the_it_engineer_watches_every_bill_before_its_cap.sql, caps as it_threshold rows
//   23 duty 12's weekly audit, plus scripts/it/open_dependency_patch_pr.mjs (a PR, never a merge)
//   24 a_routine_change_nobody_signed_is_a_finding_within_minutes.sql
// This fails when:
//   1. a routine in the new files is not revoked from public, anon and authenticated, or runs as its
//      definer without a pinned search_path; or a new table has no RLS, no policy or no revoke;
//   2. a new file is missing from MANIFEST, or sits before the duty 9-18 files it builds on;
//   3. the signed-apply tag scripts/apply_sql.mjs writes no longer matches the pattern the guard reads;
//   4. duty 9's drill stops checking that both copies open and match, or a playbook class is missing;
//   5. the patch step can merge, or loses its --package-lock-only / no --force guarantee;
//   (production, once applied; every write rolls back through raise exception 'CHK<<...>>')
//   6. an unsigned routine change raises no security finding for the ceo, or acceptance does not close it;
//   7. a renewal inside 60 days opens no handoff to the accountant, the accountant can close it, a recorded
//      renewal does not close it, or the last stage past its window does not reach the ceo;
//   8. the table drill fails a page identical to live, or stays quiet about a stale export;
//   9. a bill over its recorded cap raises nothing for the accountant.
// Tests use ZZ DEMO names and roll back; none can reach a person.
//
//   node --test scripts/checks/it_engineer_duties_19_to_24.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { advisoryCount } from '../it/open_dependency_patch_pr.mjs';
import { replaySql } from '../lib/safe_replay.mjs';
import { seatWorkFixtures } from '../lib/seat_work_fixtures.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILES = [
  'scripts/sql/the_it_engineer_restores_a_table_sample_every_month.sql',
  'scripts/sql/renewals_warn_the_accountant_at_sixty_and_thirty_days.sql',
  'scripts/sql/the_it_engineer_watches_every_bill_before_its_cap.sql',
  'scripts/sql/a_routine_change_nobody_signed_is_a_finding_within_minutes.sql',
  'scripts/sql/the_it_engineer_playbook_knows_what_duties_19_to_24_find.sql',
];
const DUTIES_9_18 = 'scripts/sql/the_it_engineer_takes_on_seven_more_duties.sql';
const PLAYBOOK_TABLE = 'scripts/sql/every_new_bug_leaves_a_playbook_entry_a_check_and_an_incident_record.sql';
const read = (f) => readFileSync(join(REPO, f), 'utf8');

test('every routine is revoked and pins its search_path; every table has RLS, a policy and a revoke', () => {
  const bad = [];
  for (const f of FILES) {
    const src = read(f);
    for (const m of src.matchAll(/create\s+or\s+replace\s+function\s+public\.(\w+)\s*\(([\s\S]*?)\)\s*returns[\s\S]*?\$fn\$/gi)) {
      const [whole, name] = m;
      if (!new RegExp(`revoke\\s+execute\\s+on\\s+function\\s+public\\.${name}\\s*\\([^)]*\\)\\s+from\\s+public,\\s*anon,\\s*authenticated`, 'i').test(src)) bad.push(`${f}: ${name} not revoked`);
      if (/security\s+definer/i.test(whole) && !/set\s+search_path\s+to\s+'public',\s*'pg_temp'/i.test(whole)) bad.push(`${f}: ${name} has no pinned search_path`);
    }
    for (const [, t] of src.matchAll(/create\s+table\s+if\s+not\s+exists\s+public\.(\w+)/gi)) {
      if (!new RegExp(`alter\\s+table\\s+public\\.${t}\\s+enable\\s+row\\s+level\\s+security`, 'i').test(src)) bad.push(`${f}: ${t} has no RLS`);
      if (!new RegExp(`create\\s+policy\\s+\\w+\\s+on\\s+public\\.${t}\\b`, 'i').test(src)) bad.push(`${f}: ${t} has no policy`);
      if (!new RegExp(`revoke\\s+all\\s+on\\s+public\\.${t}\\s+from\\s+anon,\\s*authenticated`, 'i').test(src)) bad.push(`${f}: ${t} is not revoked`);
    }
  }
  assert.deepEqual(bad, []);
});

test('every new file is in MANIFEST, after the duty 9-18 files, in dependency order', () => {
  const order = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).filter((l) => l.endsWith('.sql'));
  const at = (f) => order.indexOf(f);
  for (const f of FILES) assert.ok(at(f) >= 0, `${f} is not in MANIFEST`);
  for (const b of [DUTIES_9_18, PLAYBOOK_TABLE, 'scripts/sql/every_routine_change_records_who_made_it.sql']) {
    assert.ok(at(b) >= 0 && at(b) < at(FILES[0]), `${b} must come before the duty 19-24 files`);
  }
  for (let i = 1; i < FILES.length; i++) assert.ok(at(FILES[i - 1]) < at(FILES[i]), `${FILES[i - 1]} must come before ${FILES[i]}`);
});

test('fn_it_duties warns only certificates; the renewal watch owns licences, domains and tokens', () => {
  assert.match(read('scripts/sql/the_it_engineer_runs_its_duties_every_hour.sql'),
    /from public\.it_expiry where kind = 'tls' and expires_on is not null and expires_on < current_date \+ 30/);
  assert.match(read(FILES[1]), /for e in select \* from public\.it_expiry where kind <> 'tls'/);
});

test('the table drill\'s due-check waits at most 250 ms for a lock and then says not due', () => {
  const src = read(FILES[0]);
  const fn = src.slice(src.indexOf('create or replace function public.fn_it_restore_table_due()'),
                       src.indexOf('revoke execute on function public.fn_it_restore_table_due()'));
  assert.match(fn, /set lock_timeout to '250ms'/, 'a lock held elsewhere made the check outlive the 8 s statement timeout (14 Sep 2026)');
  assert.match(fn, /exception when lock_not_available then[\s\S]*?raise warning[\s\S]*?return false;/);
  assert.doesNotMatch(fn, /count\(\*\)|storage\.objects/, 'the due path must not count rows or scan storage');
  assert.match(fn, /raise warning 'fn_it_restore_table_due: a lock held elsewhere/, 'a skipped tick must leave a trace in the postgres log');
  const od = src.slice(src.indexOf('create or replace function public.fn_it_restore_table_overdue()'),
                       src.indexOf('revoke execute on function public.fn_it_restore_table_overdue()'));
  assert.ok(od.length > 0, 'the overdue check is missing');
  assert.doesNotMatch(od, /fn_it_restore_table_due\s*\(/, 'the overdue check must not go through the due-check');
  assert.match(od, /set lock_timeout to '250ms'/);
  assert.match(read('supabase/functions/resilience_ping/index.ts'), /step\('restore_overdue', async \(\) => rpc\('fn_it_restore_table_overdue'\)\)/);
});

test('the tag apply_sql.mjs writes is the tag the guard reads as signed', () => {
  assert.match(read('scripts/apply_sql.mjs'), /const tag = `qd-apply \$\{rev\} \$\{seat\} \$\{base\(process\.cwd\(\)\)\} \$\{base\(file\)\}`/);
  const guard = /^qd-apply ([0-9a-f]{7,40}) /;   // the pattern in trg_it_judge_routine_change
  assert.equal('qd-apply 133aa12 it_engineer qd-it19 x.sql'.match(guard)?.[1], '133aa12', 'the seat after the revision must not break the guard');
  assert.equal('qd-apply 133aa12 qd-it19 x.sql'.match(guard)?.[1], '133aa12');
  assert.equal('qd-apply unknown qd-it19 x.sql'.match(guard), null, 'a copy that is not a git checkout must read as unsigned');
  assert.equal('mgmt-api'.match(guard), null);
  assert.match(read(FILES[3]), /\^qd-apply \(\[0-9a-f\]\{7,40\}\) /);
});

test('duty 9\'s drill checks that both copies open and that the storage copy is the Dropbox copy', () => {
  const sql = read(DUTIES_9_18);
  assert.match(sql, /\(e->'dropbox'->>'opens'\) = 'false'/);
  assert.match(sql, /\(e->'storage'->>'opens'\) = 'false'/);
  assert.match(sql, /e->'storage'->>'content_hash' <> e->'dropbox'->>'content_hash'/);
  const ts = read('supabase/functions/_shared/it_scheduled_readings.ts');
  assert.match(ts, /content_hash: await dropboxContentHash\(b\), opens: opensAs\(d\.path, b\)/);
  assert.match(ts, /const v = dnsblVerdict\(list, ips\)/, 'a blocklist answer must go through dnsblVerdict');
});

test('the playbook has a class for every key duties 10, 19, 20, 22, 23 and 24 raise', () => {
  const src = read(FILES[4]);
  const prefixes = [...src.matchAll(/\('[a-z0-9_]+', '(duty:[a-z_0-9:]+)'/g)].map((m) => m[1]);
  for (const p of ['duty:sender:spf:', 'duty:sender:dmarc:', 'duty:sender:dkim:', 'duty:sender:resend_domain', 'duty:sender:blocklist:',
                   'duty:sender:bounce_rate', 'duty:sender:complaint_rate', 'duty:sender:whatsapp_quality', 'duty:sender:template:',
                   'duty:dependency:', 'duty:restore_table:', 'duty:renewal:', 'duty:usage_', 'duty:unsigned_change:', 'duty:unsigned_revision:']) {
    assert.ok(prefixes.includes(p), `no playbook class covers ${p}`);
  }
  // every sender item duty 10 raises starts with one of those prefixes
  const sender = read(DUTIES_9_18).split('-- ── 10. SENDER HEALTH ──')[1].split('-- ── 11a.')[0];
  for (const [, item] of sender.matchAll(/'item', '([a-z_]+)(?::|')/g)) {
    assert.ok(prefixes.some((p) => p.startsWith('duty:sender:' + item)), `duty 10 raises ${item} and no playbook class covers it`);
  }
});

test('the patch step opens a lockfile-only PR and has no way to merge it', () => {
  const src = read('scripts/it/open_dependency_patch_pr.mjs');
  assert.match(src, /'audit', 'fix', '--package-lock-only', '--ignore-scripts', '--omit=dev'/);
  assert.doesNotMatch(src, /'--force'/);
  assert.doesNotMatch(src, /\bpr['", ]+merge\b|gh pr merge|--auto\b/);
  assert.match(read('.github/workflows/it-weekly-readings.yml'), /node scripts\/it\/open_dependency_patch_pr\.mjs/);
  assert.equal(advisoryCount({ metadata: { vulnerabilities: { total: 3 } } }), 3);
  assert.equal(advisoryCount({ vulnerabilities: { a: {}, b: {} } }), 2);
  assert.equal(advisoryCount({}), 0);
});

// ── production, once applied ──────────────────────────────────────────────────────────────────────
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
let SKIP = hasToken ? false : 'no Supabase management token in this environment';
let sql;
if (!SKIP) {
  ({ sql } = await import('../lib/db.mjs'));
  try {
    const [r] = await sql(`select to_regprocedure('public.fn_it_change_watch()') is not null
                              and to_regprocedure('public.fn_it_restore_table_record(jsonb)') is not null
                              and to_regprocedure('public.fn_it_renewal_watch()') is not null
                              and to_regprocedure('public.fn_it_usage_watch(jsonb)') is not null ok`);
    if (!r.ok) SKIP = 'NOT_APPLIED: the duty 19-24 files are not on production yet';
  } catch (e) { SKIP = 'production not reachable: ' + String(e.message).slice(0, 120); }
}
if (SKIP) console.log(SKIP);
// The overdue check is newer than the other duties: it has its own gate until it is applied.
let OVERDUE_SKIP = SKIP;
if (!OVERDUE_SKIP) {
  const [o] = await sql(`select to_regprocedure('public.fn_it_restore_table_overdue()') is not null ok`);
  if (!o.ok) OVERDUE_SKIP = 'NOT_APPLIED: fn_it_restore_table_overdue is not on production yet';
}

// fixtures: ruling 1199 (#1479, demo_activity_files_no_seat_task_or_handoff.sql) files no handoff for a ZZ DEMO subject;
// a probe that proves a renewal handoff on one switches that guard off for its own rolled-back transaction
// (scripts/lib/seat_work_fixtures.mjs).
async function probe(body, { fixtures = false } = {}) {
  try {
    if (fixtures) await replaySql(seatWorkFixtures() + `\n;\ndo $p$ ${body} $p$;`);
    else await sql(`do $p$ ${body} $p$;`);
  } catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    // The payload arrives JSON-escaped inside the error text: unescape it as one JSON string first, so a
    // nested value that itself carries quotes survives (the crude \" replace broke on fn_it_usage_watch's
    // 'unjudged' object, 22 Sep 2026).
    if (m) { try { return JSON.parse(JSON.parse('"' + m[1] + '"')); } catch { return JSON.parse(m[1].replace(/\\"/g, '"')); } }
    throw e;
  }
  throw new Error('probe committed instead of rolling back');
}

test('an unsigned routine change is a security finding for the ceo at once; acceptance closes it', { skip: SKIP }, async () => {
  const r = await probe(`
    declare v_tx bigint := txid_current(); v_open json;
    begin
      perform set_config('application_name', 'zz-demo-probe', true);
      execute 'create function public.zz_demo_probe_unsigned() returns int language sql as ''select 1''';
      perform set_config('application_name', 'qd-apply abcdef1 zz_demo_probe x.sql', true);
      execute 'create or replace function public.zz_demo_probe_unsigned() returns int language sql as ''select 2''';
      select json_build_object('open', closed_at is null, 'blast', blast, 'owner', evidence->>'owner_seat',
                               'severity', public.fn_it_engineer_severity(blast, affected, started_at))
        into v_open from public.it_engineer_finding where issue_key = 'duty:unsigned_change:tx' || v_tx;
      perform public.fn_it_change_accept(v_tx, 'ceo', 'ZZ DEMO probe');
      raise exception 'CHK<<%>>', json_build_object('before', v_open,
        'rev', (select verdict from public.it_change_revision where rev = 'abcdef1'),
        'after_accept', (select closed_at is not null from public.it_engineer_finding where issue_key = 'duty:unsigned_change:tx' || v_tx));
    end`);
  assert.deepEqual(r.before, { open: true, blast: 'security', owner: 'ceo', severity: 'critical' });
  assert.equal(r.rev, 'pending', 'a signed apply queues its revision for GitHub');
  assert.equal(r.after_accept, true);
});

test('a renewal 45 days out is warned to the accountant, who cannot close it; the renewal closes it', { skip: SKIP }, async () => {
  const r = await probe(`
    declare h record; v_refused boolean := false;
    begin
      insert into public.it_expiry (item, kind, expires_on, owner_seat, route, source, warn_days)
      values ('zz_demo_licence', 'licence', current_date + 45, 'accountant', 'ZZ DEMO route', 'ZZ DEMO probe', '{60,30}');
      perform public.fn_it_renewal_watch();
      select id, detail->>'stage' stage, detail ? 'replied_at' replied, agent into h from public.agent_actions
       where kind = 'handoff' and detail->>'type' = 'renewal.due' and detail->>'item' = 'zz_demo_licence';
      begin
        perform set_config('qd.handoff_closer', 'accountant', true);
        update public.agent_actions set status = 'done' where id = h.id;
      exception when others then v_refused := true; end;
      perform set_config('qd.handoff_closer', '', true);
      perform public.fn_it_renewal_recorded('zz_demo_licence', current_date + 400, 'accountant', 'ZZ DEMO receipt');
      raise exception 'CHK<<%>>', json_build_object('to', h.agent, 'stage', h.stage, 'replied', h.replied, 'refused', v_refused,
        'after', (select status from public.agent_actions where id = h.id),
        'finding_open', (select closed_at is null from public.it_engineer_finding where issue_key = 'duty:renewal:zz_demo_licence'));
    end`, { fixtures: true });
  assert.deepEqual(r, { to: 'accountant', stage: '60', replied: true, refused: true, after: 'done', finding_open: false });
});

test('the last renewal stage past its reply window reaches the ceo', { skip: SKIP }, async () => {
  const r = await probe(`
    declare v_id bigint;
    begin
      insert into public.it_expiry (item, kind, expires_on, owner_seat, route, source, warn_days)
      values ('zz_demo_domain', 'domain', current_date + 20, 'accountant', 'ZZ DEMO route', 'ZZ DEMO probe', '{60,30}');
      perform public.fn_it_renewal_watch();
      select id into v_id from public.agent_actions
       where kind = 'handoff' and detail->>'type' = 'renewal.due' and detail->>'item' = 'zz_demo_domain';
      update public.agent_actions set created_at = now() - interval '4 days' where id = v_id;
      perform public.fn_it_renewal_watch();
      raise exception 'CHK<<%>>', json_build_object(
        'escalated', (select detail ? 'escalated_report_id' from public.agent_actions where id = v_id),
        'report', (select json_build_object('source', source_agent, 'severity', severity) from public.support_ceo_report
                    where idempotency_key = 'renewal:zz_demo_domain@' || (current_date + 20)));
    end`, { fixtures: true });
  assert.equal(r.escalated, true);
  assert.deepEqual(r.report, { source: 'it_engineer', severity: 'serious' });
});

test('the table drill passes a page identical to live and names a stale export', { skip: SKIP }, async () => {
  const r = await probe(`
    declare v_rows jsonb; v1 jsonb; v2 jsonb;
    begin
      select jsonb_agg(to_jsonb(p)) into v_rows from (select * from public.pricing_config order by id limit 5) p;
      v1 := public.fn_it_restore_table_record(jsonb_build_object('newest_export_day', current_date,
        'table', jsonb_build_object('table', 'pricing_config', 'path', 'zz_demo/pricing_config/page_0000.json', 'rows', v_rows)));
      v2 := public.fn_it_restore_table_record(jsonb_build_object('newest_export_day', '2026-09-07', 'table', null));
      raise exception 'CHK<<%>>', json_build_object('rows', jsonb_array_length(coalesce(v_rows, '[]'::jsonb)), 'first', v1->'drill',
        'restore_open', (select closed_at is null from public.it_engineer_finding where issue_key = 'duty:restore_table:restore'),
        'stale_open', (select closed_at is null from public.it_engineer_finding where issue_key = 'duty:restore_table:export_stale'));
    end`);
  assert.ok(r.rows > 0, 'pricing_config has no rows to restore');
  assert.equal(r.first.restored, r.rows);
  assert.equal(r.first.identical_to_live, r.rows);
  assert.equal(r.stale_open, true, 'an export from 7 Sep must raise export_stale');
  assert.equal(r.restore_open, true, 'a drill with no table to restore must fail');
});

test('an empty page never passes: a lost export is named, and an empty one proves nothing', { skip: SKIP }, async () => {
  // ZZ DEMO: a scratch table in the drill list, empty live, so the only difference is what the export says.
  // 24 Sep 2026 (#912, the_restore_drill_passes_only_on_rows_it_actually_restored.sql): the drill's only historical
  // "pass" was a restore of 0 rows against an empty live table, so an empty restore is now a failure with its own
  // reason. This test used to assert that pass; it asserts the stricter rule now.
  const r = await probe(`
    declare v_lost jsonb; v_empty jsonb;
    begin
      create table public.zz_demo_drill (id int primary key, note text);
      insert into public.it_restore_drill_table (table_name, key_column, note) values ('zz_demo_drill', 'id', 'ZZ DEMO probe');
      v_lost := public.fn_it_restore_table_record(jsonb_build_object('newest_export_day', current_date,
        'table', jsonb_build_object('table', 'zz_demo_drill', 'path', 'zz_demo/page_0000.json', 'rows', '[]'::jsonb, 'rows_in_file', 3)));
      v_empty := public.fn_it_restore_table_record(jsonb_build_object('newest_export_day', current_date,
        'table', jsonb_build_object('table', 'zz_demo_drill', 'path', 'zz_demo/page_0000.json', 'rows', '[]'::jsonb, 'rows_in_file', 0)));
      raise exception 'CHK<<%>>', json_build_object('lost_error', v_lost->'drill'->>'error',
        'lost_settle', v_lost->'restore_table'->'failing', 'empty_error', v_empty->'drill'->>'error',
        'restore_open_after_empty', (select closed_at is null from public.it_engineer_finding where issue_key = 'duty:restore_table:restore'));
    end`);
  assert.match(r.lost_error, /export holds 3 row\(s\) and none reached the restore/, 'an export that lost its rows passed because the live table is empty');
  assert.match(r.empty_error ?? '', /holds 0 rows, so nothing was restored and nothing was proved/, 'an empty restore passed the drill');
  assert.equal(r.restore_open_after_empty, true, 'an empty restore closed the restore finding');
});

test('a drill that has not completed for 33 days is its own finding, and a completed drill closes it', { skip: OVERDUE_SKIP }, async () => {
  // ZZ DEMO: every change here rolls back. The real drill runs are hidden inside the transaction and a
  // scheduled-duty run older than the window stands in for a long-running estate.
  const r = await probe(`
    declare v1 jsonb; v2 jsonb; v_open boolean;
    begin
      delete from public.agent_runs where agent = 'it_engineer' and counts->>'job' = 'duty:restore_table';
      insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
      values ('it_engineer', 'ok', now() - interval '40 days', now() - interval '40 days', '{"job": "duty:zz_demo_probe"}', 'ZZ DEMO probe');
      v1 := public.fn_it_restore_table_overdue();
      select closed_at is null into v_open from public.it_engineer_finding where issue_key = 'duty:restore_table:overdue';
      insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
      values ('it_engineer', 'ok', now(), now(), '{"job": "duty:restore_table"}', 'ZZ DEMO probe');
      v2 := public.fn_it_restore_table_overdue();
      raise exception 'CHK<<%>>', json_build_object('first', v1->'overdue', 'open', v_open, 'second', v2->'overdue',
        'closed', (select closed_at is not null from public.it_engineer_finding where issue_key = 'duty:restore_table:overdue'),
        'blast', (select blast from public.it_engineer_finding where issue_key = 'duty:restore_table:overdue'));
    end`);
  assert.deepEqual(r, { first: true, open: true, second: false, closed: true, blast: 'monitor' });
});

test('a bill over its recorded cap is a finding for the accountant; an unread provider is named', { skip: SKIP }, async () => {
  const r = await probe(`
    declare v jsonb;
    begin
      perform public.fn_it_cap_set('cap_supabase_storage_bytes', 1, 'accountant', 'ZZ DEMO probe');
      v := public.fn_it_usage_watch(jsonb_build_object('twilio', jsonb_build_object('basis', 'unavailable', 'reason', 'probe'),
                                                       'vercel', jsonb_build_object('basis', 'unavailable', 'reason', 'probe')));
      raise exception 'CHK<<%>>', json_build_object('not_read', v->'not_read',
        'finding', (select json_build_object('open', closed_at is null, 'owner', evidence->>'owner_seat', 'blast', blast)
                      from public.it_engineer_finding where issue_key = 'duty:usage_supabase:supabase_storage_bytes'));
    end`);
  assert.deepEqual(r.finding, { open: true, owner: 'accountant', blast: 'agent_facing' });
  assert.deepEqual(Object.keys(r.not_read).sort(), ['twilio', 'vercel']);
});

// 22 Sep 2026, founder instruction 639: caps and subscriptions are his. duty:usage_twilio:cap_unknown:twilio_balance
// and duty:usage_vercel:cap_unknown:vercel_charges_month had sat open since 14 Sep saying only "no cap is recorded".
// A metric with no cap is now READ and recorded (unjudged), never raised; a cap that is set and breached still is.
let UNJUDGED_SKIP = SKIP;
if (!UNJUDGED_SKIP) {
  const [u] = await sql(`select prosrc like '%unjudged%' ok from pg_proc where oid = 'public.fn_it_usage_watch(jsonb)'::regprocedure`);
  if (!u.ok) UNJUDGED_SKIP = 'NOT_APPLIED: a_cap_the_founder_holds_is_read_not_raised.sql is not on production yet';
}
test('a cap nobody set is read and recorded, never raised; a set cap that is breached still is', { skip: UNJUDGED_SKIP }, async () => {
  const r = await probe(`
    declare v jsonb; v2 jsonb;
    begin
      update public.it_threshold set value = null where key = 'cap_supabase_storage_bytes';
      v := public.fn_it_usage_watch(jsonb_build_object('twilio', jsonb_build_object('basis', 'measured', 'balance', 11.25),
                                                       'vercel', jsonb_build_object('basis', 'measured', 'charges_month', 48.63)));
      -- control: the same reading against a cap set at 1 byte is a finding
      perform public.fn_it_cap_set('cap_supabase_storage_bytes', 1, 'accountant', 'ZZ DEMO probe');
      v2 := public.fn_it_usage_watch(jsonb_build_object('twilio', jsonb_build_object('basis', 'measured', 'balance', 11.25),
                                                        'vercel', jsonb_build_object('basis', 'measured', 'charges_month', 48.63)));
      raise exception 'CHK<<%>>', json_build_object(
        'open_cap_unknown', (select count(*) from public.it_engineer_finding where closed_at is null and issue_key like 'duty:usage\\_%:cap\\_unknown:%'),
        'unjudged', v->'unjudged',
        'breach_open', (select closed_at is null from public.it_engineer_finding where issue_key = 'duty:usage_supabase:supabase_storage_bytes'));
    end`);
  assert.equal(Number(r.open_cap_unknown), 0, 'a cap nobody recorded is still raised as a finding');
  for (const k of ['twilio_balance', 'vercel_charges_month', 'supabase_storage_bytes']) {
    assert.ok(r.unjudged && k in r.unjudged, `${k} was read with no cap and its reading was not recorded: ${JSON.stringify(r.unjudged)}`);
  }
  assert.equal(r.breach_open, true, 'a cap that is set and breached must still be a finding');
});

// 22 Sep 2026: 16 of 22 unsigned_revision findings were raised in the minutes between an apply and its PR's
// merge -- the estate's own order is apply, then merge. An open PR now has two hours; past that it is raised,
// and a revision in no PR (not_on_main) is raised at once.
let GRACE_SKIP = SKIP;
if (!GRACE_SKIP) {
  const [g] = await sql(`select prosrc like '%''applied_as''%' ok from pg_proc where oid = 'public.fn_it_change_watch()'::regprocedure`);
  if (!g.ok) GRACE_SKIP = 'NOT_APPLIED: an_apply_from_an_open_pull_request_waits_for_its_merge.sql is not on production yet';
}
test('an open PR revision waits two hours; after that, and not_on_main at once, it is raised', { skip: GRACE_SKIP }, async () => {
  const r = await probe(`
    begin
      insert into public.it_change_revision (rev, verdict, pr_number, first_seen_at, checked_at, detail) values
        ('abcdef2', 'open_pr', 9001, now() - interval '5 minutes', now(), '{}'),
        ('abcdef3', 'open_pr', 9002, now() - interval '3 hours', now(), '{}'),
        ('abcdef4', 'not_on_main', null, now() - interval '5 minutes', now(), '{}');
      perform public.fn_it_change_watch();
      raise exception 'CHK<<%>>', json_build_object(
        'fresh_open_pr', (select count(*) from public.it_engineer_finding where issue_key = 'duty:unsigned_revision:rev:abcdef2' and closed_at is null),
        'stale_open_pr', (select count(*) from public.it_engineer_finding where issue_key = 'duty:unsigned_revision:rev:abcdef3' and closed_at is null),
        'not_on_main',   (select blast from public.it_engineer_finding where issue_key = 'duty:unsigned_revision:rev:abcdef4' and closed_at is null));
    end`);
  assert.equal(Number(r.fresh_open_pr), 0, 'an apply minutes before its merge was raised');
  assert.equal(Number(r.stale_open_pr), 1, 'a PR left open for hours with its code live must be raised');
  assert.equal(r.not_on_main, 'security', 'a revision in no pull request must be raised at once');
});

// 22 Sep 2026: duty:unsigned_revision:rev:2d34c4a and rev:59a3de8 (PR #834) could be attributed only by
// opening the pull request -- the apply tag named a commit and a worktree, never the seat. The tag now
// carries the seat, and an apply no seat owns is refused before it can write (scripts/lib/apply_seat.mjs).
test('an apply is signed with the seat that owns it, and refused when nothing names one', async () => {
  const { seatFor } = await import('../lib/apply_seat.mjs');
  assert.equal(seatFor({ branch: 'it_engineer/the-alarms-say-only-what-is-true' }), 'it_engineer');
  assert.equal(seatFor({ branch: 'worktree-agent-a3466b29cc207b137', subject: 'marketing: the seat publishes' }), 'marketing');
  assert.equal(seatFor({ branch: 'HEAD', subject: 'sales_engineer + it_engineer: the Arabic check' }), 'sales_engineer');
  assert.equal(seatFor({ flag: 'ceo', branch: 'it_engineer/x' }), 'ceo', 'an explicit --seat wins');
  // controls: nothing names a seat, or a name that is not a seat
  assert.equal(seatFor({ branch: 'worktree-agent-a3466b29cc207b137', subject: 'Merge branch main' }), null);
  assert.equal(seatFor({ flag: 'session' }), null, 'a made-up seat is not a seat');
  assert.equal(seatFor({ branch: 'main', subject: 'fix: typo' }), null);
  const src = read('scripts/apply_sql.mjs');
  assert.ok(src.indexOf('if (!seat) {') > 0 && src.indexOf('if (!seat) {') < src.indexOf('if (!APPLY) {'),
    'the seat must be resolved, and refused, before the dry run exits -- so a dry run says so first');
});
