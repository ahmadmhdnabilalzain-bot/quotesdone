// fn_it_detect's refusal_rate detector must judge a public surface against its OWN baseline.
// 28 Sep 2026: claim_lookup (window 100%, baseline 100%) and supplier_portal (100% vs 82.65%) were
// raised 'stopped' because the absolute public arm ignored a measured baseline.
// Reads the newest fn_it_detect definition: a scripts/sql/pending note's file wins over MANIFEST
// (pending = committed, awaiting apply), else the last MANIFEST file defining the routine.
// Then replays the state CASE on the two live cases and on a no-baseline outage.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';

const defines = (f) => existsSync(f) && /function\s+public\.fn_it_detect\s*\(/i.test(readFileSync(f, 'utf8'));
const pending = readdirSync('scripts/sql/pending')
  .map((n) => `scripts/sql/${n.replace(/\.txt$/, '.sql')}`).filter(defines);
const manifest = readFileSync('scripts/sql/MANIFEST.txt', 'utf8').split(/\r?\n/)
  .map((l) => l.trim()).filter((l) => l.endsWith('.sql')).filter(defines);
const file = pending.at(-1) ?? manifest.at(-1);
const src = readFileSync(file, 'utf8');

// The CASE that decides v_state, as SQL text -> a JS predicate list.
const body = src.match(/v_bshare\s*:=[^\n]*\n\s*v_state\s*:=\s*case([\s\S]*?)else null end;/)[1];
const arms = [...body.matchAll(/when\s+(.+?)\s+then\s+'(\w+)'/g)].map(([, cond, state]) => ({
  state,
  test: new Function('r', 'v_share', 'v_bshare', 'return ' + cond
    .replace(/\bis not null\b/g, '!== null').replace(/\bis null\b/g, '=== null')
    .replace(/\band\b/g, '&&').replace(/\bor\b/g, '||')),
}));
const state = (pub, share, bshare) => arms.find((a) => a.test({ pub }, share, bshare))?.state ?? null;

test(`${file}: a public surface at its own baseline raises nothing`, () => {
  assert.equal(state(true, 1.0, 1.0), null, 'claim_lookup 100% vs 100% baseline');
  assert.equal(state(true, 1.0, 0.8265), null, 'supplier_portal 100% vs 82.65% baseline');
});

test(`${file}: a real departure or an unbaselined outage is still raised`, () => {
  assert.equal(state(true, 0.95, 0.10), 'stopped', '85 points above its own baseline, near-total');
  assert.equal(state(true, 0.60, 0.10), 'degraded', '50 points above its own baseline');
  assert.equal(state(true, 0.95, null), 'stopped', 'public surface with no measured baseline');
  assert.equal(state(false, 0.45, 0.05), 'degraded', 'non-public departure rule unchanged');
});
