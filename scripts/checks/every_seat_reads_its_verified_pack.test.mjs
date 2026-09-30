// EVERY SEAT READS ITS VERIFIED PACK AT DECISION TIME (23 Sep 2026, it_engineer).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: a pack in knowledge/ that the gate does not pass (unsourced / low-confidence technical > 10%,
//     no verified block), an id in two packs, an eval question expecting an entry the pack does not hold,
//     or a seat with no pack;
//   * static: the SQL file gains a begin/commit, a routine without a revoke or pinned search_path, a table
//     without RLS + policy, or both / neither of a pending note and a MANIFEST line;
//   * static: fn_reason_retrieve stops reading one seat's table (the #884 gap: support_knowledge and
//     ceo_knowledge had no vector and were read by nobody; customer_support could not reach a trade pack);
//   * production, ONE aborted transaction (the pending file replayed first, nothing commits, ZZ DEMO rows
//     only): a row the loader builds (rowsOf -- the loader's own mapping) is refused by its table, or is not
//     returned to its seat by fn_reason_retrieve, or is returned to a seat that does not own it;
//   * production, once loaded: any (pack, seat) below the eval FLOOR (scripts/eval/knowledge_pack_eval.mjs).
//
//   node --test scripts/checks/every_seat_reads_its_verified_pack.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { readPacks, rowsOf, upsertSql, vecLit, SEATS, SEAT_TABLE, TABLES } from '../kb/verified_packs.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FILE = 'scripts/sql/every_verified_pack_has_a_home_and_every_seat_reads_its_own.sql';
const NOTE = 'scripts/sql/pending/every_verified_pack_has_a_home_and_every_seat_reads_its_own.txt';
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('every pack in knowledge/ is verified, well-formed and unique, and every seat has one', () => {
  const packs = readPacks(join(REPO, 'knowledge'));
  assert.ok(packs.length >= SEATS.length + 1, `only ${packs.length} packs`);
  assert.deepEqual(packs.filter((p) => p.errors.length).map((p) => `${p.rel}: ${p.errors[0]}`), []);
  for (const s of SEATS) assert.ok(packs.some((p) => p.kind === 'seat' && p.code === s), `no pack for ${s}`);
  assert.ok(packs.every((p) => (p.pack.eval ?? []).length > 0), 'a pack without eval questions cannot be measured');
});

test('the loader and the eval run the shared module, not a copy', () => {
  for (const f of ['scripts/kb/load_verified_packs.mjs', 'scripts/eval/knowledge_pack_eval.mjs']) {
    assert.match(read(f), /from '\.\.\/kb\/verified_packs\.mjs'|from '\.\/verified_packs\.mjs'/, f);
    assert.doesNotMatch(read(f), /function gate\(|function rowsOf\(/, `${f} carries its own copy`);
  }
});

test('the SQL file replays safely and fn_reason_retrieve reads every seat\'s own table', () => {
  const sql = code(read(FILE));
  assert.doesNotMatch(sql, /^\s*(begin|commit)\s*;/im);
  for (const m of sql.matchAll(/create (?:or replace )?function public\.([a-z0-9_]+)\(/g)) {
    assert.match(sql, new RegExp(`revoke execute on function public\\.${m[1]}\\(`), `${m[1]}: revoke`);
    assert.match(sql.slice(m.index, m.index + 400), /search_path to 'public', 'pg_temp'/, `${m[1]}: search_path`);
  }
  for (const m of sql.matchAll(/create table if not exists public\.([a-z0-9_]+)/g)) {
    assert.match(sql, new RegExp(`alter table public\\.${m[1]} enable row level security`));
    assert.match(sql, new RegExp(`create policy \\w+ on public\\.${m[1]}`));
  }
  const inManifest = read('scripts/sql/MANIFEST.txt').split(/\r?\n/).includes(FILE);
  assert.ok(existsSync(join(REPO, NOTE)) !== inManifest, 'exactly one of a pending note and a MANIFEST line');
  const fn = sql.slice(sql.indexOf('function public.fn_reason_retrieve('));
  for (const [seat, table] of Object.entries(SEAT_TABLE)) {
    const at = fn.indexOf(`from public.${table} s`);
    assert.ok(at > 0, `fn_reason_retrieve does not read ${table}`);
    assert.match(fn.slice(at, at + 400), new RegExp(`p_seat = '${seat}'`), `${table} is not read for ${seat}`);
  }
  assert.match(fn, /p_seat = 'customer_support' and s\.pack_id like 'verified:trade:%'/, 'customer_support reads the trade packs');
});

test('production, one aborted transaction: each seat gets its own pack row back and no other seat\'s', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  // One ZZ DEMO entry per seat pack and one trade-pack entry, mapped by the loader's own rowsOf.
  const entry = (id) => ({ id, topic: 'ZZ DEMO probe', kind: 'concept', body_en: 'ZZ DEMO probe entry', body_ar: 'ZZ DEMO مدخل تجريبي',
    sources: ['https://example.invalid/zz'], confidence: 'high', as_of: '2026-09-23' });
  const fake = (kind, c) => ({ kind, code: c, key: c, rel: `zz/${c}.json`, version: 'sha256:zzdemo', pack_id: `verified:${kind}:${c}`, pack: { entries: [entry(`${c}:zz-demo-probe`)] } });
  const rows = [...SEATS.map((s) => fake('seat', s)), fake('trade', 'zz_demo_trade')].flatMap((p) => rowsOf(p).filter((r) => r.lang === 'en'));
  // Each probe row sits on its own axis, so it is the nearest row to its own one-hot query (similarity 1).
  rows.forEach((r, i) => { r.vec = Array.from({ length: 384 }, (_, j) => (j === i ? 1 : 0)); });
  const byTable = {};
  for (const r of rows) (byTable[r.table] ??= []).push(r);
  const pending = existsSync(join(REPO, NOTE)) ? read(FILE) + '\n' : '';
  // One character per (row, seat) comes back: the error text that carries the verdict is cut at ~2,000 characters.
  const ask = (seat, r) => `case when exists (select 1 from jsonb_array_elements(public.fn_reason_retrieve('${seat}', ${vecLit(r.vec)}, 6)) x where x->>'source' = '${r.table}' and x->>'id' = '${r.record_id}') then '1' else '0' end`;
  const calls = [];
  for (const r of rows) for (const seat of SEATS) calls.push({ seat, r, sql: ask(seat, r) });
  const block = `do $qdchk$ declare o jsonb; b text := ''; begin
${calls.map((c) => `b := b || ${c.sql};`).join('\n')}
o := jsonb_build_object('bits', b, 'anon', (select bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')) from pg_proc p where p.oid = coalesce(to_regprocedure('public.fn_reason_retrieve(text,vector,integer,text,text,text)'), to_regprocedure('public.fn_reason_retrieve(text,vector,integer)'))),
  'rls', (select relrowsecurity from pg_class where oid = 'public.marketing_knowledge'::regclass));
raise exception 'CHK<<%>>', o::text; end $qdchk$;`;
  let out;
  try { await replaySql(pending + Object.entries(byTable).map(([t, rs]) => upsertSql(t, rs)).join('\n') + block, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 600));
    out = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  assert.equal(out.anon, false, 'anon or authenticated can execute fn_reason_retrieve');
  assert.equal(out.rls, true, 'marketing_knowledge has no RLS');
  const owner = (r) => (r.cols.pack_id ?? r.cols.extra?.pack_id).split(':');   // ['verified', kind, code]
  const wrong = [];
  assert.equal(out.bits.length, calls.length);
  calls.forEach((c, i) => {
    const [, kind, who] = owner(c.r);
    const should = kind === 'trade' ? ['sales_engineer', 'customer_support'].includes(c.seat) : who === c.seat;
    const got = out.bits[i] === '1';
    if (got !== should) wrong.push(`${c.seat} ${got ? 'reads' : 'misses'} ${c.r.table}|${c.r.record_id}`);
  });
  assert.deepEqual(wrong, []);
  assert.deepEqual(TABLES.filter((t) => !rows.some((r) => r.table === t)), [], 'every table was probed');
});

test('production, once loaded: every pack meets the recall floor', { skip: hasToken ? false : 'no Supabase management token' }, async (t) => {
  const { sql } = await import('../lib/db.mjs');
  const [r] = await sql(`select count(*)::int n from public.sales_knowledge where tags @> array['verified_pack']`, { readOnly: true });
  if (existsSync(join(REPO, NOTE)) || !r.n) return t.skip('not applied and loaded yet (see the pending note); the staged eval measured the baseline');
  const run = spawnSync(process.execPath, [join(REPO, 'scripts/eval/knowledge_pack_eval.mjs'), '--mode', 'live'], { encoding: 'utf8', timeout: 1_500_000 });
  assert.equal(run.status, 0, (run.stdout + run.stderr).slice(-3000));
  assert.match(run.stdout, /EVAL OK/);
});
