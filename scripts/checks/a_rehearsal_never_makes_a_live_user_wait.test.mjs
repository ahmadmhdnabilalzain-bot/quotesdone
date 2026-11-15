// A REHEARSAL NEVER MAKES A LIVE USER WAIT (it_engineer, 13 Nov 2026). Offline: no database; production is stubbed.
//
// On 13 Nov 2026 rolled-back rehearsals of whole SQL files on production held ACCESS EXCLUSIVE on quotes, inquiries and
// transactions for 12-15 s at a time; 103 live requests waited behind 28 of them, and the functions' 8 s statement timeout
// killed a supplier's agreement certificate write (07:46:10), a supplier's spec_fill at the hold desk (08:11:08), a customer's
// acceptance of the terms (08:47) and 29 dashboard reads (scripts/lib/replay_guard.mjs header). Independent review then showed
// the first guard (a regex on a list of hot tables) let 40 lock-taking shapes through with a 120 s hold. This fails if:
//   * any of those 40 shapes is neither refused before sending nor cut at 5 s;
//   * a production replay is sent without the 5 s transaction_timeout and the 1 s lock_timeout, or is re-sent after a 5xx;
//   * production becomes the default again (no QD_LOCAL_DB_URL and no QD_REPLAY_ON_PRODUCTION=1 must send NOTHING);
//   * a file's own SET/RESET/set_config can lift a limit; or the real apply loses its 1500 ms / 60 s limits or re-sends after a 5xx.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import {
  APPLY_HOLD_LIMIT, APPLY_LOCK_CAP, CATALOGUE_SQL, applyLockTimeout, applyPrelude, LOCK_TIMEOUT, REPLAY_LIMIT, catalogueFrom, planReplay, settleOutcome,
  settleVerdict, stallsLiveUsers, tightenLimits,
} from '../lib/replay_guard.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');

// What pg_class answers on production, cut down to the relations the fixtures name (an index carries its table).
const RELATIONS = ['public.quotes', 'public.inquiries', 'public.quote_items', 'public.leads', 'public.customers', 'public.a',
  'public.it_engineer_finding', 'public.sales_knowledge', 'public.wa_messages', 'public.seat_duty', 'public.v_quotes',
  'public.quotes_id_seq', 'public.quotes_pkey>public.quotes', 'storage.objects', 'auth.users'];
const CATALOGUE = catalogueFrom({ relations: RELATIONS.join(',') });

// THE 40 EVASIONS: each passed the first guard (review of 13 Nov, [L] on a local Postgres built from the mirror, or the same
// shape spelled another way). Every one is now refused before anything is sent.
export const EVASIONS = [
  'alter table "public"."quotes" add column x int',
  'alter table "quotes" add column x int',
  'ALTER TABLE ONLY public.quotes ADD COLUMN x int',
  '/* c */ ALTER/* d */TABLE public.quotes add column y int',
  'alter table if exists "public"."customers" drop column z',
  'drop policy "a b" on quotes',
  'create policy "p q" on "public"."inquiries" for select using (true)',
  'alter policy p on public.leads using (true)',
  'do $$ begin alter table public.quotes add column x int; end $$',
  "do $$ begin execute 'alter table public.quotes add column x int'; end $$",
  "do $$ begin execute format('alter table %I add column x int', 'quotes'); end $$",
  'do $$ begin if true then create index on public.quotes (id); end if; end $$',
  'do language plpgsql $$ begin drop table public.leads; end $$',
  "do $d$ declare n int; begin select 1 into n; lock table public.quotes; end $d$",
  'drop index public.quotes_pkey',
  'drop index if exists quotes_pkey',
  'alter index public.quotes_pkey rename to quotes_pkey2',
  'create table public.zz_new (q bigint references public.quotes(id))',
  'alter table public.zz_new add constraint zz_fk foreign key (q) references quotes (id)',
  'create table public.zz_part partition of public.quotes for values in (1)',
  'create or replace view public.v_quotes as select 1 as one',
  'truncate public.a, public.quotes',
  'truncate table only a, "quotes"',
  'lock public.a, public.quotes',
  'lock table quotes in share mode',
  'lock table quotes in exclusive mode',
  'alter table storage.objects add column z int',
  'create trigger t after insert on storage.objects for each row execute function f()',
  'create policy p on auth.users using (true)',
  'create table if not exists public.it_engineer_finding (id int); create index on public.it_engineer_finding (id)',
  'create table if not exists public.it_engineer_finding (id int); alter table public.it_engineer_finding enable row level security',
  'create unique index qx on public.quote_items (id)',
  'alter table public.sales_knowledge alter column x set not null',
  'drop trigger if exists t on public.wa_messages',
  'create constraint trigger t after update on "public"."seat_duty" for each row execute function f()',
  'reindex table public.quotes',
  'cluster public.quotes',
  'alter sequence public.quotes_id_seq restart',
  'drop table public.a, public.quotes cascade',
  'create rule r as on insert to public.quotes do instead nothing',
];
// What no static reading can see: DDL inside a routine the text calls, and the row locks of a write. Not refused; cut at 5 s.
export const CUT_NOT_REFUSED = ['select public.fn_that_alters_quotes()', 'update public.quotes set status = status where id = 1',
  'delete from public.leads where id = -1', 'select * from public.quotes for update'];

test('there are 40 evasions, and every one is refused before anything is sent, naming the relation production has', () => {
  assert.equal(EVASIONS.length, 40);
  for (const t of EVASIONS) {
    const s = stallsLiveUsers(t, CATALOGUE);
    assert.ok(s.length, `not refused: ${t}`);
    assert.throws(() => planReplay(t, { label: 'evasion', catalogue: CATALOGUE }), /SAFE REPLAY REFUSED: evasion takes a lock that stops live requests[\s\S]*local_pg16\.mjs start/, t);
  }
  const named = (t) => stallsLiveUsers(t, CATALOGUE).map((l) => l.table);
  assert.deepEqual(named('truncate public.a, public.quotes'), ['a', 'quotes'], 'the second table of a TRUNCATE');
  assert.deepEqual(named('drop index public.quotes_pkey'), ['quotes'], 'an index lock is felt by its table');
  assert.deepEqual(named("do $$ begin execute format('alter table %I add column x int', 'quotes'); end $$"), ['?'], 'a name built at run time');
});

test('what no reading can see is still sent behind a 5 s transaction_timeout and a 1 s lock_timeout, one at a time', () => {
  for (const t of CUT_NOT_REFUSED) {
    const { prelude, stalls } = planReplay(t, { catalogue: CATALOGUE });
    assert.deepEqual(stalls, [], t);
    assert.ok(prelude.startsWith(`set local lock_timeout = '${LOCK_TIMEOUT}'; set local transaction_timeout = '${REPLAY_LIMIT}'; `), prelude);
    assert.match(prelude, /pg_try_advisory_xact_lock\(hashtext\('qd_safe_replay_one_at_a_time'\)\)/);
    assert.ok(!prelude.includes('\n'), 'one line, so the text keeps its line numbers');
  }
  assert.equal(REPLAY_LIMIT, '5s', 'under the live role\'s 8 s statement_timeout, with room for the 1 s lock wait');
  assert.equal(LOCK_TIMEOUT, '1s');
});

test('accepted by the operator, a refused text runs under the same 5 s cut (there is no longer hold)', () => {
  const { prelude } = planReplay(EVASIONS[0], { acceptStall: true, catalogue: CATALOGUE });
  assert.ok(prelude.includes(`transaction_timeout = '${REPLAY_LIMIT}'`), prelude);
  assert.doesNotMatch(read('scripts/lib/replay_guard.mjs'), /120s|HOT_TABLES/, 'no 120 s hold and no list of hot tables');
});

test('not refused: routine bodies, new tables, comments, reads, writes, and lock modes that do not stop writers', () => {
  for (const t of [
    "create or replace function public.fn_x() returns int language sql as $f$ alter table public.leads add column z int; select 1 $f$",
    'create table public.zz_new2 (id int); create index on public.zz_new2 (id); alter table public.zz_new2 enable row level security',
    "comment on table public.quotes is 'alter table public.quotes'", 'select count(*) from public.quotes',
    "insert into public.quotes (id) values (-1)", 'lock table public.quotes in row exclusive mode', 'create table public.zz_t (like public.quotes)',
    'create view public.zz_v as select * from public.quotes', 'drop table if exists public.zz_never_existed',
  ]) assert.deepEqual(stallsLiveUsers(t, CATALOGUE), [], t);
});

test("a file's own limits are lowered on the same line, every way it can say them; what would lift one is refused", () => {
  const t = "-- set lock_timeout = '9s' in a comment stays\nset local lock_timeout = '5s';\nset lock_timeout to '15s';\nset local lock_timeout = '250ms';\n"
    + "set lock_timeout to default;\nreset lock_timeout;\nset lock_timeout = 0;\nset session lock_timeout = '30s';\n"
    + "select set_config('qd.probe', 'x', true);\n"
    + "create function public.fn_y() returns int language sql set lock_timeout to '2s' as $f$ select 1 $f$;\n"
    + "create function public.fn_z() returns void language plpgsql as $f$ begin perform set_config('lock_timeout', v_prev, true); end $f$;\n";
  const out = tightenLimits(t);
  assert.equal(out.split('\n').length, t.split('\n').length, 'line numbers kept');
  assert.deepEqual(out.split('\n').slice(0, 9), ["-- set lock_timeout = '9s' in a comment stays", "set local lock_timeout = '1s';", "set local lock_timeout = '1s';",
    "set local lock_timeout = '250ms';", "set local lock_timeout = '1s';", "set local lock_timeout = '1s';", "set local lock_timeout = '1s';",
    "set local lock_timeout = '1s';", "select set_config('qd.probe', 'x', true);"]);
  assert.match(out, /set lock_timeout to '2s' as \$f\$/, "a routine's own SET attribute is not a statement of the replay");
  assert.match(out, /perform set_config\('lock_timeout', v_prev, true\)/, 'nor is a set_config inside a routine body');
  assert.match(tightenLimits("set lock_timeout = '15s';", 'apply', { cap: APPLY_LOCK_CAP }), /^set local lock_timeout = '1500ms';$/);
  assert.throws(() => tightenLimits("set local transaction_timeout = '10min';"), /transaction_timeout/);
  assert.throws(() => tightenLimits("select set_config('transaction_timeout', '0', true);"), /transaction_timeout/);
  assert.throws(() => tightenLimits('reset all;'), /RESET ALL/);
  assert.throws(() => tightenLimits("select set_config('lock_timeout', v, true) from t;"), /changes lock_timeout through set_config/);
  assert.throws(() => tightenLimits("select set_config(v_name, '0', true) from t;"), /computes the setting it changes in set_config/);
  // the spellings the review listed (item 9): case, spacing, SESSION/LOCAL, quoted and unquoted values, a statement over lines
  for (const v of ["SET LOCK_TIMEOUT = '15s';", 'set   lock_timeout   to   15000;', "set local lock_timeout='3s';", 'SET SESSION lock_timeout TO "15s";',
    'set lock_timeout=15s;', "set\nlock_timeout\n=\n'15s';", "set lock_timeout = '1 min';", 'RESET   LOCK_TIMEOUT;', 'Set Lock_Timeout To Default;']) {
    assert.equal(tightenLimits(v), `set local lock_timeout = '1s'${'\n'.repeat(v.split('\n').length - 1)};`, v);
  }
  // set_config of a limit is refused, however it is spelled (review 2, item 2): only the top-level SET form is lowered
  for (const v of ["select SET_CONFIG('LOCK_TIMEOUT','15s',true);", "SELECT pg_catalog.set_config( 'lock_timeout' , '9s' , true );",
    "select set_config('statement_timeout', '0', true);", "do $d$ begin perform set_config('lock_timeout', '0', true); end $d$;"]) assert.throws(() => tightenLimits(v), /through set_config/, v);
  assert.equal(tightenLimits("set lock_timeout = '500ms';"), "set lock_timeout = '500ms';", 'a tighter value is kept');
  assert.throws(() => tightenLimits('RESET  ALL;'), /RESET ALL/);
  assert.throws(() => tightenLimits("SET Transaction_Timeout = '1h';"), /transaction_timeout/);
});

// HISTORICAL FILES THE GUARD NOW REFUSES ON PRODUCTION (counted 15 Nov 2026). 15 set statement_timeout inside a DO block (review 2,
// item 2); 13 more define a routine that sets lock_timeout or statement_timeout (set_config, or its SET clause) and call it, which is
// read as part of the file since the third review (item 3). All are applied already or are probes; they run on the local database,
// where no plan is applied (safe_replay.mjs replaySql), and none is ever applied again. A new file is not added to this list: it
// says its limit at the top level, or not at all.
export const REFUSED_ON_PRODUCTION = new Set(['a_queue_filled_this_hour_is_not_a_stopped_queue.sql', 'a_silence_is_judged_against_the_rhythm_a_subject_still_keeps.sql',
  'a_supplier_describes_its_services_in_its_own_words_probe.sql', 'a_supplier_who_limits_its_emirates_is_matched_only_there_probe.sql',
  'a_surface_refusing_at_its_own_baseline_is_not_a_refusal_rate_finding.sql', 'every_seat_reviews_itself_every_month_probe.sql',
  'one_job_number_on_every_portal_document_and_notice_probe.sql', 'one_slow_duty_never_wedges_the_seat_duty_tick.sql',
  'probe_the_invitation_batch_runs_on_its_own_clock_and_the_guard_takes_the_link_less_copy.sql', 'replay_verify.sql',
  'the_ceo_improvement_sweep_closes_before_it_proposes_and_settles_in_one_run_probe.sql', 'the_ceo_plans_every_day_and_directs_the_seats_probe.sql',
  'the_ceo_tracks_the_supplier_target_by_trade_and_emirate_probe.sql', 'the_ceo_weekly_review_acts_on_every_missed_target_probe.sql',
  'the_embedding_picker_orders_on_the_index.sql', 'the_it_detector_evaluates_its_row_rules_as_sets_not_as_function_calls.sql',
  'the_it_detector_fails_fast_on_a_lock_instead_of_dying_behind_one.sql', 'the_it_detector_reads_agent_runs_once_and_no_subject_can_flood_it.sql',
  'the_nonresponse_charge_is_the_refund_plus_the_admin_fee_plus_lawful_interest_probe.sql', 'the_purge_cannot_take_the_database_down.sql',
  'the_restore_drill_runs_until_it_passes_once_every_calendar_month.sql', 'the_sanctions_screen_stops_opening_tasks_on_seats_that_do_not_exist.sql',
  'the_scheduler_was_never_down_and_the_queue_nobody_counted_was_fine.sql', 'the_schema_export_sorts_triggers_and_overloads_on_a_unique_key.sql',
  'the_seat_duty_jobs_are_spread_over_the_five_minutes.sql', 'the_seat_duty_jobs_are_spread_over_the_five_minutes_probe.sql',
  'the_unverified_bulk_and_the_duplicates_leave_kb_chunks_in_pages.sql', 'the_weekly_report_arrives_and_the_rules_decide_probe.sql']);
test('every committed SQL file can be tightened (none lifts a limit of its own), but the 28 named historical files', () => {
  assert.equal(REFUSED_ON_PRODUCTION.size, 28);
  for (const f of readdirSync(join(REPO, 'scripts/sql')).filter((x) => x.endsWith('.sql'))) {
    if (REFUSED_ON_PRODUCTION.has(f)) assert.throws(() => tightenLimits(read(`scripts/sql/${f}`), f), /statement_timeout|lock_timeout/, f);
    else tightenLimits(read(`scripts/sql/${f}`), f);
  }
});

// ---- replaySql against a stubbed production ------------------------------------------------------------------------------
async function withStub(env, answer, fn) {
  const saved = { ...process.env }; const realFetch = globalThis.fetch; const sent = [];
  Object.assign(process.env, { SUPABASE_ACCESS_TOKEN: 'sbp_' + '0'.repeat(40), QD_OFFLINE: '' }, env);
  for (const [k, v] of Object.entries(env)) if (v === undefined) delete process.env[k];
  globalThis.fetch = async (url, init) => {
    const q = JSON.parse(init.body).query; sent.push(q);
    if (q.includes('qd_relation_catalogue')) return new Response(JSON.stringify([{ relations: RELATIONS.join(',') }]), { status: 200 });
    if (q.includes('pg_get_functiondef')) return new Response(JSON.stringify([{ fp: 'same' }]), { status: 200 });
    return answer(q);
  };
  try { return await fn(sent); } finally { globalThis.fetch = realFetch; for (const k of Object.keys(process.env)) if (!(k in saved)) delete process.env[k]; Object.assign(process.env, saved); }
}
const { replaySql, NO_TARGET } = await import('../lib/safe_replay.mjs');
const PROBE = "create or replace function public.fn_zz() returns int language sql as $f$ select 1 $f$;\ndo $p$ begin raise exception 'CHK<<PROBE OK>>'; end $p$;";

test('production is never the default: with no local database and no flag, nothing is sent and the message says how', async () => {
  await withStub({ QD_LOCAL_DB_URL: undefined, QD_REPLAY_ON_PRODUCTION: undefined }, () => new Response('[]'), async (sent) => {
    await assert.rejects(replaySql(PROBE, { label: 'p' }), (e) => e.message.startsWith(NO_TARGET) && /local_pg16\.mjs start/.test(e.message) && /QD_REPLAY_ON_PRODUCTION=1/.test(e.message));
    assert.equal(sent.length, 0, 'not even the catalogue read');
  });
});

test('with the flag, the replay carries the guard and is sent ONCE: a 5xx or a cut is reported as such, never re-sent', async () => {
  const err = (status, message) => () => new Response(JSON.stringify({ message }), { status });
  await withStub({ QD_LOCAL_DB_URL: undefined, QD_REPLAY_ON_PRODUCTION: '1' }, err(400, 'ERROR: P0001: CHK<<PROBE OK>>'), async (sent) => {
    await assert.rejects(replaySql(PROBE), /CHK<<PROBE OK>>/);
    const replays = sent.filter((q) => q.includes('SAFE_REPLAY_ROLLBACK'));
    assert.equal(replays.length, 1);
    assert.ok(replays[0].startsWith(`set local lock_timeout = '1s'; set local transaction_timeout = '5s'; do $qd_one$`), replays[0].slice(0, 200));
  });
  await withStub({ QD_LOCAL_DB_URL: undefined, QD_REPLAY_ON_PRODUCTION: '1' }, err(503, 'upstream connect error'), async (sent) => {
    await assert.rejects(replaySql(PROBE), /SAFE REPLAY CUT[\s\S]*NOT re-sent[\s\S]*local_pg16\.mjs start/);
    assert.equal(sent.filter((q) => q.includes('SAFE_REPLAY_ROLLBACK')).length, 1, 'a 5xx is not re-sent (db.mjs would have sent it 8 times)');
  });
  await withStub({ QD_LOCAL_DB_URL: undefined, QD_REPLAY_ON_PRODUCTION: '1' }, err(400, 'FATAL: 25P04: terminating connection due to transaction timeout'), async () => {
    await assert.rejects(replaySql(PROBE), /SAFE REPLAY CUT/);
  });
  await withStub({ QD_LOCAL_DB_URL: undefined, QD_REPLAY_ON_PRODUCTION: '1' }, err(400, 'x'), async (sent) => {
    await assert.rejects(replaySql('alter table "public"."quotes" add column x int;\n' + PROBE), /SAFE REPLAY REFUSED/);
    assert.equal(sent.filter((q) => q.includes('SAFE_REPLAY_ROLLBACK')).length, 0, 'refused before anything is sent');
  });
  assert.match(CATALOGUE_SQL, /^select \/\* qd_relation_catalogue \*\//, 'the catalogue is one light read');
});

test('the real apply: lock_timeout 1500 ms (or --lock-timeout), printed; the file\'s own lowered; 60 s when it stops writers; never re-sent after a 5xx', () => {
  const apply = read('scripts/apply_sql.mjs');
  assert.equal(APPLY_LOCK_CAP, '1500ms'); assert.equal(APPLY_HOLD_LIMIT, '60s');
  // the flag, executed
  assert.equal(applyLockTimeout(['--apply']), '1500ms');
  assert.equal(applyLockTimeout(['--apply', '--lock-timeout=3000']), '3000ms');
  assert.equal(applyLockTimeout(['--lock-timeout', '800']), '800ms');
  assert.equal(applyLockTimeout(['--lock-timeout=2s']), '2000ms');
  for (const bad of ['--lock-timeout=0', '--lock-timeout=0.4', '--lock-timeout=0.99', '--lock-timeout=0.5ms', '--lock-timeout=60000', '--lock-timeout=soon', '--lock-timeout=']) assert.throws(() => applyLockTimeout([bad]), /refused/, bad);
  assert.equal(applyLockTimeout(['--lock-timeout=1.2']), '2ms', 'rounded up, never down to no limit (review 2, item 4)');
  assert.equal(applyLockTimeout(['--lock-timeout=1']), '1ms');
  // what is put in front of the file, and what is printed
  const plain = applyPrelude({ lockTimeout: '1500ms', holdsStrongLock: false, tag: 'qd-apply x' });
  assert.equal(plain.prelude, "set local lock_timeout = '1500ms'; set application_name = 'qd-apply x'; ");
  assert.match(plain.said, /lock_timeout = 1500ms/); assert.match(plain.said, /no transaction_timeout/);
  const strong = applyPrelude({ lockTimeout: '3000ms', holdsStrongLock: true, tag: "x'; drop" });
  assert.equal(strong.prelude, "set local lock_timeout = '3000ms'; set local transaction_timeout = '60s'; set application_name = 'x__ drop'; ");
  assert.match(strong.said, /lock_timeout = 3000ms.*transaction_timeout = 60s/);
  assert.match(tightenLimits("set lock_timeout = '15s';", 'apply', { cap: applyLockTimeout(['--lock-timeout=3000']) }), /^set local lock_timeout = '3000ms';$/);
  // apply_sql.mjs uses them, prints the sentence, and sends the prelude in front of the tightened text
  assert.match(apply, /lockTimeout = guard\.applyLockTimeout\(process\.argv\.slice\(3\)\);/);
  assert.match(apply, /guard\.tightenLimits\(sql, file, \{ cap: lockTimeout \}\)/, 'the file\'s own lock_timeout is lowered to the same value');
  assert.match(apply, /guard\.applyPrelude\(\{ lockTimeout, holdsStrongLock: strongLocks\.length > 0, tag: applyTag \}\)/);
  assert.match(apply, /console\.log\(`  \$\{said\}`\)/, 'the limits it set are printed');
  assert.match(apply, /dbPost\(mustRunAlone \? sql : prelude \+ text\)/);
  assert.match(apply, /if \(r\.status === 429 && attempt < 7\)/, 'only a 429 (refused before running) is re-sent by the transport');
  assert.doesNotMatch(apply, /r\.status >= 500\) && attempt/, 'a 5xx is never re-sent by the transport');
  // after a 5xx: committed -> read back; anything else -> it stops (exit 4 proven not committed, exit 5 unknown), never re-sent
  const unsettled = apply.slice(apply.indexOf('if (!mustRunAlone && e?.unsettled) {'), apply.indexOf('if (mustRunAlone || !LOCK_NOT_GRANTED'));
  assert.match(unsettled, /const verdict = await settleUnknown\(e\);/);
  assert.doesNotMatch(unsettled, /continue;/, 'a 5xx is never followed by another send');
  // review 2, item 5: a first copy still running is never judged, and the MANIFEST is read before anyone is told to re-run
  const settle = apply.slice(apply.indexOf('async function settleUnknown(e) {'), apply.indexOf('let applied;'));
  assert.match(settle, /stillRunning = false; break;/);
  assert.match(settle, /guard\.settleOutcome\(\{ stillRunning, verdict, inManifest, file, tag: applyTag \}\)/);
  assert.match(settle, /MANIFEST\.txt/);
  assert.match(settle, /process\.exit\(out\.exit\)/);
  assert.equal(settleVerdict('a', 'b', false), 'committed');
  assert.equal(settleVerdict('a', 'a', true), 'not committed');
  assert.equal(settleVerdict('a', 'a', false), 'unknown');
  const o = (a) => settleOutcome({ file: 'f.sql', tag: 'qd-apply t', ...a });
  assert.equal(o({ stillRunning: true, verdict: 'not committed', inManifest: false }).exit, 5, 'still running: never judged');
  assert.match(o({ stillRunning: true }).lines.join(' '), /STILL RUNNING[\s\S]*Do NOT re-run/);
  assert.equal(o({ stillRunning: false, verdict: 'committed', inManifest: false }).exit, 0);
  assert.equal(o({ stillRunning: false, verdict: 'not committed', inManifest: false }).exit, 4);
  assert.match(o({ stillRunning: false, verdict: 'not committed', inManifest: false }).lines.join(' '), /run the same command again/);
  assert.equal(o({ stillRunning: false, verdict: 'not committed', inManifest: true }).exit, 5, 'the MANIFEST lists it: nobody is told to re-run');
  assert.doesNotMatch(o({ stillRunning: false, verdict: 'not committed', inManifest: true }).lines.join(' '), /run the same command again/);
  assert.equal(o({ stillRunning: false, verdict: 'unknown', inManifest: false }).exit, 5, 'unknown is never re-sent: it stops');
  assert.match(apply, /const dynamic = guard\.dynamicSql\(sql\);/, 'the apply refuses dynamic SQL');
});

test('every path that rehearses goes through the guard and none loosens it', () => {
  for (const f of ['scripts/ci/rehearse_this_prs_manifest_lines.mjs', 'scripts/lib/canonical_body.mjs', 'scripts/lib/alarm_replay.mjs']) {
    const s = read(f);
    for (const m of s.matchAll(/lock_timeout = '(\d+)(ms|s)'/g)) assert.ok((m[2] === 's' ? Number(m[1]) * 1000 : Number(m[1])) <= 1000, `${f}: lock_timeout ${m[1]}${m[2]}`);
    assert.doesNotMatch(s, /transaction_timeout/, `${f} must not set its own transaction_timeout`);
  }
  assert.match(read('scripts/lib/alarm_replay.mjs'), /await guarded\(replaySql\(/, 'the alarm replay goes through safe_replay');
  const door = read('scripts/lib/safe_replay.mjs');
  assert.match(door, /send\(q, \{ \.\.\.opts, retry: false \}\)/, 'a production replay is sent once');
  assert.match(door, /if \(!where\) throw/, 'no target, no send');
});
