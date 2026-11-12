// THE SAME WORK UNDER TWO KEYS MEETS AT THE SERVICE GATE (12 Nov 2026, sales_engineer; founder rulings 1647, 1628).
//
// scripts/sql/the_same_work_under_two_keys_meets_at_the_service_gate.sql marks 18 pairs of keys as the same work
// (service_implication.same, one row each way), adds the 6 twins of curated implications that end in a pair key and 4
// plain implications, and makes the trades curated neighbours. Measured before it, through the live
// fn_match_capability: 24 of the analysis's 26 directions missed; the review measured 4 more pairs and an implied key's
// twin n -> n. What fails if that breaks:
//   * a pair loses a direction, thermal insulation becomes identity again, or the probe stops asking the file's rows -> static
//   * an implication ends in a pair key and does not reach its twin                                                -> static
//   * a row sits in two trades that are neither the same nor curated neighbours, so the reach never finds it        -> static
//   * on production, rolled back, ZZ DEMO only: each row matches, and another service of the same trade does NOT    -> probe
//
//   node --test scripts/checks/the_same_work_under_two_keys_meets_at_the_service_gate.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { pendingNotes } from '../lib/pending_sql.mjs';
import { replaySql } from '../lib/safe_replay.mjs';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const R = (p) => readFileSync(join(ROOT, p), 'utf8');
const NAME = 'the_same_work_under_two_keys_meets_at_the_service_gate';
const FILE = `scripts/sql/${NAME}.sql`;
const PROBE = `scripts/sql/${NAME}_probe.sql`;
const rowsIn = (src) => [...src.matchAll(/^ {2}\('([a-z_.]+)','([a-z_]+)','([a-z][a-z0-9_]*)','(?:[^']|'')*','(?:[^']|'')*',(true|false)\)/gm)]
  .map(([, a, t, c, same]) => [a, `${t}.${c}`, same === 'true']);
const probeRowsIn = (src) => [...src.matchAll(/^ {6}\('([a-z_.]+)', '([a-z_.]+)', (true|false)\)/gm)].map(([, a, b, same]) => [a, b, same === 'true']);

test('every identity row has its reverse, thermal insulation is an implication, and the probe asks every row', () => {
  const s = R(FILE);
  const rows = rowsIn(s);
  const same = rows.filter((r) => r[2]);
  assert.equal(same.length, 36, '18 pairs, both ways');
  for (const [a, b] of same) assert.ok(same.some(([x, y]) => x === b && y === a), `${a} = ${b} is written one way only`);
  assert.ok(rows.some(([a, b, sm]) => a === 'waterproofing.thermal' && b === 'thermal_insulation.wall_insulation' && !sm), 'thermal insulation does not imply wall insulation');
  assert.ok(!same.some(([a, b]) => [a, b].includes('waterproofing.thermal')), 'thermal insulation is still identity with roof insulation');
  assert.match(s, /alter table public\.service_implication add column if not exists same boolean not null default false/);
  assert.match(s, /on conflict \(from_code, implies_trade, implies_code\) do update set same = excluded\.same, active = true/);
  assert.deepEqual(probeRowsIn(R(PROBE)), rows, 'the probe asks other rows than the file writes');
});

test('an implication that ends in a key of a pair also reaches its twin (identity is one level deep)', () => {
  const rows = rowsIn(R(FILE));
  const twin = new Map(rows.filter((r) => r[2]).map(([a, b]) => [a, b]));
  const seed = R('scripts/sql/a_supplier_describes_its_services_in_its_own_words_and_the_sales_engineer_rewrites_them.sql');
  const seedRows = [...seed.matchAll(/\('([a-z_.]+)','([a-z_]+)','([a-z][a-z0-9_]*)','(?:[^']|'')*','(?:[^']|'')*'\)/g)].map(([, f, t, c]) => [f, `${t}.${c}`]);
  const all = [...seedRows, ...rows.filter((r) => !r[2]).map(([a, b]) => [a, b])];
  const missing = all.filter(([f, to]) => twin.has(to) && twin.get(to) !== f && !all.some(([g, x]) => g === f && x === twin.get(to)) && !rows.some(([g, x]) => g === f && x === twin.get(to)))
    .map(([f, to]) => `${f} -> ${to} (twin ${twin.get(to)})`);
  assert.deepEqual(missing, []);
});

test('every row\'s two trades are the same or curated neighbours (here or in an earlier file), so the reach can find it', () => {
  const adj = new Set();
  for (const f of readdirSync(join(ROOT, 'scripts/sql')).filter((n) => n.endsWith('.sql') && !n.endsWith('_probe.sql'))) {
    const src = R(`scripts/sql/${f}`);
    if (!src.includes('taxonomy_trade_adjacent')) continue;
    for (const [, a, b] of src.matchAll(/\('([a-z_]+)',\s*'([a-z_]+)',\s*\n?\s*'[A-Z]/g)) adj.add([a, b].sort().join('|'));
  }
  const far = rowsIn(R(FILE)).map(([a, b]) => [a.split('.')[0], b.split('.')[0]].sort())
    .filter(([x, y]) => x !== y && !adj.has(`${x}|${y}`)).map((p) => p.join(' / '));
  assert.deepEqual([...new Set(far)], [], 'these rows live in trades the reach never joins');
});

test('the change is pending until the release applies it, and the probe is never applied', () => {
  const notes = pendingNotes();
  const inManifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).includes(FILE);
  assert.ok(inManifest || notes.has(FILE), 'the change is neither applied (MANIFEST) nor pending');
  assert.match(notes.get(PROBE) || '', /^A PROBE\b/, 'the probe must carry a probe note so it is never applied');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production, rolled back, ZZ DEMO only: each of the 46 rows meets, and no other service of the trade does', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  // the catalogue file first while it is pending: four rows name services it adds
  const CAT = 'scripts/sql/the_catalogue_can_name_what_suppliers_do.sql';
  const pre = (pendingNotes().has(CAT) ? R(CAT) + '\n' : '') + (pendingNotes().has(FILE) ? R(FILE) + '\n' : '');
  let verdict = null;
  try { await replaySql(pre + R(PROBE), { label: PROBE }); } catch (e) {
    const m = String(e.body ?? e.message ?? e).match(/CHK<<([\s\S]*?)>>/);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.body ?? e.message ?? e).slice(0, 800));
    verdict = m[1].replace(/\\"/g, '"');
  }
  assert.ok(verdict, 'the probe committed instead of rolling back');
  assert.match(verdict, /"verdict": "PROBE OK"/, verdict);
  assert.match(verdict, /"rows_met": 46, "controls_kept_out": 46/, verdict);
});
