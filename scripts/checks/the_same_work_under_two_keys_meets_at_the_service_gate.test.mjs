// THE SAME WORK UNDER TWO KEYS MEETS AT THE SERVICE GATE (12 Nov 2026, sales_engineer; founder rulings 1647, 1628).
//
// scripts/sql/the_same_work_under_two_keys_meets_at_the_service_gate.sql marks 13 pairs of keys as the same work
// (service_implication.same, one row each way) and makes their trades curated neighbours. Measured before it, through the
// live fn_match_capability: 24 of the 26 directions missed (a supplier holding one key was skipped by a request naming
// the other). What fails if that breaks:
//   * a pair loses a direction, or the probe stops asking the file's pairs                                   -> static
//   * a pair sits in two trades that are neither the same nor curated neighbours, so the reach never finds it -> static
//   * on production, rolled back, ZZ DEMO only: each direction matches, and another service of the same trade
//     does NOT (identity, not a wider trade)                                                                   -> probe
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
const pairsIn = (src) => [...src.matchAll(/^\s+\('([a-z_]+\.[a-z_]+)', '([a-z_]+\.[a-z_]+)'\),?$/gm)].map(([, a, b]) => [a, b]);

test('13 pairs, one identity row each way, and the probe asks exactly these pairs', () => {
  const s = R(FILE);
  const pairs = pairsIn(s);
  assert.equal(pairs.length, 13);
  assert.match(s, /alter table public\.service_implication add column if not exists same boolean not null default false/);
  assert.match(s, /lateral \(values \(p\.k1, p\.k2\), \(p\.k2, p\.k1\)\) x\(a, b\)/, 'a pair is written one way only');
  assert.match(s, /on conflict \(from_code, implies_trade, implies_code\) do update set same = true, active = true/);
  assert.deepEqual(pairsIn(R(PROBE)), pairs, 'the probe asks other pairs than the file writes');
});

test('every pair\'s two trades are curated neighbours (here or in an earlier file), so the reach can find it', () => {
  const adj = new Set();
  for (const f of readdirSync(join(ROOT, 'scripts/sql')).filter((n) => n.endsWith('.sql') && !n.endsWith('_probe.sql'))) {
    const src = R(`scripts/sql/${f}`);
    if (!src.includes('taxonomy_trade_adjacent')) continue;
    for (const [, a, b] of src.matchAll(/\('([a-z_]+)',\s*'([a-z_]+)',\s*\n?\s*'[A-Z]/g)) adj.add([a, b].sort().join('|'));
  }
  const far = pairsIn(R(FILE)).map(([a, b]) => [a.split('.')[0], b.split('.')[0]].sort())
    .filter(([x, y]) => x !== y && !adj.has(`${x}|${y}`)).map((p) => p.join(' / '));
  assert.deepEqual(far, [], 'these pairs live in trades the reach never joins');
});

test('the change is pending until the release applies it, and the probe is never applied', () => {
  const notes = pendingNotes();
  const inManifest = R('scripts/sql/MANIFEST.txt').split(/\r?\n/).map((l) => l.trim()).includes(FILE);
  assert.ok(inManifest || notes.has(FILE), 'the change is neither applied (MANIFEST) nor pending');
  assert.match(notes.get(PROBE) || '', /^A PROBE\b/, 'the probe must carry a probe note so it is never applied');
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || existsSync(join(homedir(), '.supabase', 'access-token'));
test('production, rolled back, ZZ DEMO only: each of the 26 directions meets, and no other service of the trade does', { skip: hasToken ? false : 'no Supabase management token' }, async () => {
  const pre = pendingNotes().has(FILE) ? R(FILE) + '\n' : '';
  let verdict = null;
  try { await replaySql(pre + R(PROBE), { label: PROBE }); } catch (e) {
    const m = String(e.body ?? e.message ?? e).match(/CHK<<([\s\S]*?)>>/);
    assert.ok(m, 'the probe failed before it could report: ' + String(e.body ?? e.message ?? e).slice(0, 800));
    verdict = m[1].replace(/\\"/g, '"');
  }
  assert.ok(verdict, 'the probe committed instead of rolling back');
  assert.match(verdict, /"verdict": "PROBE OK"/, verdict);
  assert.match(verdict, /"directions_met": 26/, verdict);
});
