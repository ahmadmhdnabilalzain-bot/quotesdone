// KNOWLEDGE LOOKUP GOES STRAIGHT TO THE RIGHT AREA FIRST (28 Sep 2026, sales_engineer / it_engineer).
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * static: scripts/sql/knowledge_lookup_goes_to_the_trade_first.sql loses the exact trade resolver (fn_norm_trades),
//     a routine loses its revoke or its pinned search_path, or the file has both / neither of a pending note and a
//     MANIFEST line;
//   * production, ONE aborted transaction (the file replayed while pending; ZZ DEMO rows on their own vector axis):
//     in BOTH routines, a row of another trade or another area is returned when a trade / an area resolves; a row of
//     the resolved trade or area, or a general row with neither tag, is NOT returned; or anything changes when
//     nothing resolves (free text as the trade, an area no row carries).
//
//   node --test scripts/checks/knowledge_lookup_goes_to_the_trade_first.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { replaySql } from '../lib/safe_replay.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/knowledge_lookup_goes_to_the_trade_first.sql';
const NOTE = 'scripts/sql/pending/knowledge_lookup_goes_to_the_trade_first.txt';
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const code = (t) => t.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');
const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));

test('the file resolves exactly, revokes both routines, pins search_path, and is either pending or in the MANIFEST', () => {
  const s = code(read(FILE));
  assert.equal((s.match(/public\.fn_norm_trades\(p_trade\)/g) || []).length, 2, 'both routines resolve the trade with fn_norm_trades');
  for (const sig of ['fn_reason_retrieve(text, vector, integer, text, text, text)', 'fn_reason_retrieve_ml(text, vector, vector, integer, integer, text, text, text)'])
    assert.match(s, new RegExp(`revoke execute on function public\\.${sig.replace(/[()]/g, '\\$&')} from public, anon, authenticated`), sig);
  assert.equal((s.match(/SET search_path TO 'public'/g) || []).length, 2);
  assert.doesNotMatch(s, /^\s*(begin|commit)\s*;/im);
  const inManifest = read('scripts/sql/MANIFEST.txt').split('\n').includes(FILE);
  assert.ok(existsSync(join(REPO, NOTE)) !== inManifest, 'exactly one of a pending note and a MANIFEST line');
});

test('production, one aborted transaction: another trade or area never, its own and the general rows always, nothing when unresolved', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const [t] = await sql(`select code from public.taxonomy_trade where active order by code limit 2`, { readOnly: true }).then((r) => [r.map((x) => x.code)]);
  const [A, B] = t;
  // Every probe row sits on ONE axis, so all are equally near the one-hot query and each filter alone decides.
  const v = `'[${Array.from({ length: 384 }, (_, j) => (j === 383 ? 1 : 0)).join(',')}]'::vector(384)`;
  const row = (id, tags) => `('zz-demo-area-probe:${id}', 'verified_pack_entry', 'concept', 'ZZ DEMO probe', 'ZZ DEMO probe', '{}'::jsonb, '{}'::text[],
    'verified_pack_sourced', 'AE', 'verified:zz:probe', 'zz', 'zz', true, 'none', array[${tags.map((x) => `'${x}'`).join(',')}]::text[], now(), 'zz', 'zz', ${v})`;
  const ins = (table, rows) => `insert into public.${table} (record_id, record_type, domain, title, content, structured_data, source_ids, epistemic_status,
    jurisdiction, pack_id, pack_version, body_sha256, runtime_index_eligible, authority_effect, tags, updated_at${table === 'sales_knowledge' ? ', record_version, content_sha256' : ''}, embedding_gte)
    values ${rows.map((r) => (table === 'sales_knowledge' ? r : r.replace(", 'zz', 'zz', " + v, ', ' + v))).join(',\n')};\n`;
  const setup = ins('sales_knowledge', [row('tradeA', [`trade:${A}`, 'kind:checklist']), row('tradeB', [`trade:${B}`, 'kind:checklist']), row('general', ['kind:method'])])
    + ins('accountant_knowledge', [row('areaX', ['area:zz_x']), row('areaY', ['area:zz_y']), row('noarea', [])]);
  const ids = (seat, args, ml) => `(select coalesce(string_agg(split_part(x->>'id', ':', 2), ',' order by x->>'id'), '') from jsonb_array_elements(${ml
    ? `public.fn_reason_retrieve_ml('${seat}', ${v}, ${v}, 12, 12, ${args})` : `public.fn_reason_retrieve('${seat}', ${v}, 12, ${args})`}) x where x->>'id' like 'zz-demo-area-probe:%')`;
  const cases = [
    ['sales_engineer', `'${A}', null, null`, 'general,tradeA'],
    ['sales_engineer', `'${A}', 'checklist', null`, 'general,tradeA'],
    ['sales_engineer', `null, null, null`, 'general,tradeA,tradeB'],
    ['sales_engineer', `'free text is not a trade', null, null`, 'general,tradeA,tradeB'],
    ['accountant', `null, null, 'zz_x'`, 'areaX,noarea'],
    ['accountant', `null, null, 'no such area'`, 'areaX,areaY,noarea'],
    ['accountant', `null, null, null`, 'areaX,areaY,noarea'],
  ];
  const pending = existsSync(join(REPO, NOTE)) ? read(FILE) + '\n' : '';
  const block = `do $qdchk$ declare o jsonb := '[]'::jsonb; begin
${cases.flatMap(([s, a]) => [false, true].map((ml) => `o := o || jsonb_build_array(${ids(s, a, ml)});`)).join('\n')}
raise exception 'CHK<<%>>', o::text; end $qdchk$;`;
  let out;
  try { await replaySql(pending + setup + block, { retry: false }); }
  catch (e) {
    const m = String(e.message).match(/CHK<<(.*?)>>/s);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.message).slice(0, 600));
    out = JSON.parse(m[1].replace(/\\"/g, '"'));
  }
  assert.ok(out, 'the probe committed instead of rolling back');
  const want = cases.flatMap(([s, a, w]) => [`gte ${s}(${a}) = ${w}`, `ml ${s}(${a}) = ${w}`]);
  const got = cases.flatMap(([s, a], i) => [`gte ${s}(${a}) = ${out[2 * i]}`, `ml ${s}(${a}) = ${out[2 * i + 1]}`]);
  assert.deepEqual(got, want);
});
