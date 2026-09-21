// A RESTORE REBUILDS FROM BASE + INCREMENTS, AND THE RULE IS APPLIED BY SIZE (owner: it_engineer, 18 Sep 2026).
//
// Founder instruction 519: "exactly we back up the extra stuff only since the existing is already there
// unless they got updated". His fourth condition was that the restore must be PROVEN, not assumed, and
// that the proof is part of a check rather than a manual step.
//
// There are two proofs, and they are deliberately different:
//   * THE MONTHLY DRILL (IT duty 19) proves the real ARTIFACTS: it downloads the base page of the newest
//     full day out of the 'backups' bucket, every later day's pages for that table and every later day's
//     table_export_change pages, and rebuilds them through public.fn_table_export_replay.
//   * THIS CHECK proves the REPLAY ITSELF, every CI run, by execution against production, with no
//     storage round trip and nothing written: it takes a real page out of fn_table_export_page and
//     replays it three ways -- whole, split into base + increment, and with a delete in the change log.
//     If the replay logic breaks, this goes red the same day; the drill would not notice for a month.
//
// Without a management token (the CI checks job has none) the live half is skipped and the structural
// half still runs, reading the canonical SQL file rather than the schema mirror, which is regenerated
// only after the apply.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const ROOT = new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const FILE = join(ROOT, 'scripts', 'sql', 'we_back_up_the_extra_stuff_only_unless_they_got_updated.sql');
const SRC = readFileSync(FILE, 'utf8');
const hasToken = Boolean(process.env.SUPABASE_ACCESS_TOKEN) || existsSync(join(homedir(), '.supabase', 'access-token'));

test('the incremental rule is applied by SIZE, never by a hard-coded table name', () => {
  assert.match(SRC, /export_incremental_min_bytes/,
    'there is no size threshold; a hard-coded list of big tables goes stale the moment a table grows');
  assert.match(SRC, /pg_total_relation_size\(format\('public\.%I', r\.t\)::regclass\)/,
    'fn_table_export_change_tracking does not decide by measured size');
  // The name-bound predicate this file replaced. It must not come back in fn_table_export_list.
  const list = SRC.slice(SRC.indexOf('function public.fn_table_export_list'));
  assert.ok(!/case when v\.t = '/.test(list.slice(0, 2000)),
    'fn_table_export_list names a specific table as the change-tracked one again');
});

test('a DELETE is recorded, and the record is itself exported', () => {
  assert.match(SRC, /tg_op = 'DELETE'/, 'the change trigger does not log deletes, so a restore resurrects deleted rows');
  assert.match(SRC, /\('table_export_change','backup'\)/,
    'public.table_export_change is not in fn_table_export_list, so the day\'s deletions never reach the bucket or Dropbox');
});

test('xmin is not used as a change marker anywhere in this file', () => {
  assert.ok(!/\bxmin\b/.test(SRC.replace(/^--.*$/gm, '')),
    'xmin is not stable across VACUUM FREEZE and would silently miss frozen rows');
});

test('every routine this file defines is revoked and pins its search_path', () => {
  const defined = [...SRC.matchAll(/create or replace function (public\.[a-z0-9_]+)\(/g)].map((m) => m[1]);
  assert.ok(defined.length >= 8, `only ${defined.length} routines parsed from ${FILE}`);
  for (const fn of new Set(defined)) {
    const body = SRC.slice(SRC.indexOf(`create or replace function ${fn}(`));
    assert.match(body.slice(0, 900), /set search_path to 'public', 'pg_temp'/, `${fn} does not pin search_path`);
    assert.ok(new RegExp(`revoke execute on function ${fn.replace('.', '\\.')}\\(`).test(SRC),
      `${fn} has no revoke`);
  }
});

test('every table this file creates has RLS, a policy and a revoke', () => {
  for (const m of SRC.matchAll(/create table if not exists public\.([a-z0-9_]+) \(/g)) {
    const t = m[1];
    assert.match(SRC, new RegExp(`alter table public\\.${t} enable row level security`), `${t}: RLS not enabled`);
    assert.match(SRC, new RegExp(`create policy ${t}_service_role_only`), `${t}: no policy (RLS on with no policy is indistinguishable from a forgotten one)`);
    assert.match(SRC, new RegExp(`revoke all on public\\.${t} from anon, authenticated`), `${t}: no revoke`);
  }
});

// ── THE LIVE PROOF ────────────────────────────────────────────────────────────────────────────────
// Reads one real page and replays it three ways. It writes nothing: fn_table_export_replay works in
// ON COMMIT DROP temp tables only, and the check asserts the change log is the same size afterwards.
test('a base page, a base + increment and a base + delete all rebuild to what is live', { skip: hasToken ? false : 'no management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  // Named in its own statement: a query that MENTIONS the table fails to parse before the apply, so
  // the existence test cannot be a CASE in the same statement. This cannot hide a file that never gets
  // applied -- the file is in scripts/sql/MANIFEST.txt, and canonical_routine_manifest.mjs fails on a
  // manifest line whose routines are not in the database.
  const [{ live }] = await sql(`select to_regclass('public.table_export_change_tracked') is not null as live`);
  if (!live) { console.log('# skip: we_back_up_the_extra_stuff_only_unless_they_got_updated.sql is not applied yet'); return; }
  const [{ t }] = await sql(`select coalesce(
      (select x.table_name from public.table_export_change_tracked x order by x.table_name limit 1),
      'pricing_config') as t`);

  const [{ before }] = await sql('select count(*)::int as before from public.table_export_change');

  // 1. the whole page as the base: everything it carries must still be live and identical
  const [whole] = await sql(`
    with p as (select public.fn_table_export_page('${t}', null, 200, null) as page)
    select public.fn_table_export_replay('${t}', p.page->'rows') as r from p`);
  const a = whole.r;
  assert.ok(a.rebuilt > 0, `the base page of ${t} rebuilt ${a.rebuilt} rows`);
  assert.equal(a.lost_rows, 0, `${a.lost_rows} live row(s) in the rebuilt window are in no backup file: ${JSON.stringify(a.lost_keys_first_10)}`);
  assert.ok(a.identical_to_live > 0, 'no rebuilt row is identical to live');

  // 2. the same page split: a MIDDLE row is removed from the base and handed back as a later day's
  //    increment. The rebuild must be the same size, which is only true if increments are applied.
  //    It has to be a middle row: the window is the base page's own key range, so a row taken off
  //    either END would be legitimately clamped out of the comparison and prove nothing.
  const [split] = await sql(`
    with p as (select public.fn_table_export_page('${t}', null, 200, null) as page),
         e as (select v, i from p, jsonb_array_elements(p.page->'rows') with ordinality x(v, i)),
         m as (select max(i) / 2 as mid from e)
    select public.fn_table_export_replay('${t}',
             (select jsonb_agg(v order by i) from e, m where e.i <> m.mid),
             jsonb_build_array((select jsonb_agg(v) from e, m where e.i = m.mid))) as r`);
  assert.equal(split.r.rebuilt, a.rebuilt, 'the increment did not put the row back, so a later day is not being applied');
  assert.equal(split.r.lost_rows, 0, 'the base + increment rebuild lost a live row');

  // 3. the same page with the last key marked deleted in the change log. The rebuild must be one row
  //    SHORTER -- a restore that ignores the log would hand back a row the company deleted.
  const [del] = await sql(`
    with p as (select public.fn_table_export_page('${t}', null, 200, null) as page),
         k as (select p.page as page,
                      (p.page->'rows'->-1->>(select x.pk_column from public.table_export_change_tracked x where x.table_name = '${t}'
                                             union all select 'id' limit 1)) as key from p)
    select public.fn_table_export_replay('${t}', k.page->'rows', '[]'::jsonb,
             jsonb_build_array(jsonb_build_object('table_name', '${t}', 'row_key', k.key, 'deleted', true,
                                                  'changed_at', to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SSOF')))) as r
      from k`);
  assert.equal(del.r.rebuilt, a.rebuilt - 1, 'the deletion in the change log was not applied, so a restore would resurrect a deleted row');
  assert.equal(del.r.deletes_applied, 1, 'the replay did not report the delete it applied');
  // and the row is still LIVE, so a log whose latest entry says deleted must NOT excuse it: that is the
  // shape a trigger-bypassing write leaves, and it is the one thing lost_rows exists to catch.
  assert.equal(del.r.lost_rows, 1,
    'a live row whose latest change-log entry is a delete was excused; lost_rows can read 0 while data really is unbacked');

  const [{ after }] = await sql('select count(*)::int as after from public.table_export_change');
  assert.equal(after, before, 'the proof left rows behind in the change log');
});
