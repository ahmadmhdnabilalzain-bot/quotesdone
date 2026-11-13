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
//   * a file's own SET/RESET/set_config can lift a limit; or the real apply loses its 2 s / 60 s limits or re-sends a 5xx blindly.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import {
  APPLY_HOLD_LIMIT, APPLY_LOCK_CAP, CATALOGUE_SQL, LOCK_TIMEOUT, REPLAY_LIMIT, catalogueFrom, planReplay, settleVerdict,
  stallsLiveUsers, tightenLimits,
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
    + "set lock_timeout to default;\nreset lock_timeout;\nset lock_timeout = 0;\nselect set_config('lock_timeout', '30s', true);\n"
    + "do $d$ begin perform set_config('lock_timeout', '0', true); end $d$;\n"
    + "create function public.fn_y() returns int language sql set lock_timeout to '2s' as $f$ select 1 $f$;\n"
    + "create function public.fn_z() returns void language plpgsql as $f$ begin perform set_config('lock_timeout', v_prev, true); end $f$;\n";
  const out = tightenLimits(t);
  assert.equal(out.split('\n').length, t.split('\n').length, 'line numbers kept');
  assert.deepEqual(out.split('\n').slice(0, 9), ["-- set lock_timeout = '9s' in a comment stays", "set local lock_timeout = '1s';", "set local lock_timeout = '1s';",
    "set local lock_timeout = '250ms';", "set local lock_timeout = '1s';", "set local lock_timeout = '1s';", "set local lock_timeout = '1s';",
    "select set_config('lock_timeout', '1s', true);", "do $d$ begin perform set_config('lock_timeout', '1s', true); end $d$;"]);
  assert.match(out, /set lock_timeout to '2s' as \$f\$/, "a routine's own SET attribute is not a statement of the replay");
  assert.match(out, /perform set_config\('lock_timeout', v_prev, true\)/, 'nor is a set_config inside a routine body');
  assert.match(tightenLimits("set lock_timeout = '15s';", 'apply', { cap: APPLY_LOCK_CAP }), /^set local lock_timeout = '2s';$/);
  assert.throws(() => tightenLimits("set local transaction_timeout = '10min';"), /transaction_timeout/);
  assert.throws(() => tightenLimits("select set_config('transaction_timeout', '0', true);"), /transaction_timeout/);
  assert.throws(() => tightenLimits('reset all;'), /RESET ALL/);
  assert.throws(() => tightenLimits("select set_config('lock_timeout', v, true) from t;"), /computes its lock_timeout/);
});

test('every committed SQL file can be tightened (none lifts a limit of its own)', () => {
  for (const f of readdirSync(join(REPO, 'scripts/sql')).filter((x) => x.endsWith('.sql'))) tightenLimits(read(`scripts/sql/${f}`), f);
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

test('the real apply: 2 s lock_timeout with the file\'s own capped, 60 s when it stops writers, a fixed pause, no blind re-send', () => {
  const apply = read('scripts/apply_sql.mjs');
  assert.equal(APPLY_LOCK_CAP, '2s'); assert.equal(APPLY_HOLD_LIMIT, '60s');
  assert.match(apply, /guard\.tightenLimits\(sql, file, \{ cap: guard\.APPLY_LOCK_CAP \}\)/, 'the file\'s own lock_timeout is capped');
  assert.match(apply, /strongLocks\.length \? `set local transaction_timeout = '\$\{guard\.APPLY_HOLD_LIMIT\}'; `/, '60 s when it stops writers');
  assert.match(apply, /setTimeout\(res, 10_000\)\);\n  \}\n\}/, 'the lock-timeout retry keeps its fixed 10 s pause');
  assert.match(apply, /if \(r\.status === 429 && attempt < 7\)/, 'only a 429 (refused before running) is re-sent by the transport');
  assert.doesNotMatch(apply, /r\.status >= 500\) && attempt/, 'a 5xx is never re-sent by the transport');
  // the settlement of a 5xx: all or nothing, so an unchanged state proves nothing committed only if the file would change it
  assert.equal(settleVerdict('a', 'b', false), 'committed');
  assert.equal(settleVerdict('a', 'a', true), 'not committed');
  assert.equal(settleVerdict('a', 'a', false), 'unknown');
  assert.match(apply, /process\.exit\(5\)/, 'unknown is never re-sent: it stops');
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
