// EVERY DEMO SERVICE SENTENCE NAMES EXACT TAXONOMY LABELS (2 Nov 2026, customer_support).
//
// MEASURED, nightly journey run 41417049225: journey b "routing invited the demo suppliers" 0/3,
// verdict no_capable_supplier. The aluminium fixture said "Aluminium windows and doors, curtain wall, ACP
// cladding, pergolas and louvres"; the Services rewrite is exact (ruling 890, decision point 93), so it
// confirmed curtain_wall, acp_cladding, louvres and the trade "Doors", and NOT aluminium.windows_doors —
// "Aluminium windows" and "pergolas" only became meaning proposals, which stay off until a supplier adds
// them (SP-F-06). The journey's request is 40 aluminium windows (aluminium.windows_doors), so
// fn_match_capability's services gate dropped all three suppliers (live lead 153893 shows the stored list).
//
// WHAT THIS FAILS ON. A phrase in fixtures.mjs SERVICE_WORDS that is not, case-insensitively, a label the
// repository seeds for that trade in taxonomy_trade_service (scripts/sql value tuples).
//   node --test scripts/checks/every_demo_service_sentence_names_exact_taxonomy_labels.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const fixtures = readFileSync(here('../e2e/fixtures.mjs'), 'utf8');
const sqlDir = here('../sql/');

// ('trade','code','Label EN','Label AR', n) — the shape the taxonomy seeds use.
const labels = new Map();
for (const f of readdirSync(sqlDir).filter((x) => x.endsWith('.sql'))) {
  for (const m of readFileSync(sqlDir + f, 'utf8').matchAll(/\(\s*'([a-z_]+)'\s*,\s*'([a-z_]+)'\s*,\s*'((?:[^']|'')+)'\s*,\s*'[^']*'\s*,\s*\d+\s*\)/g)) {
    if (!labels.has(m[1])) labels.set(m[1], new Set());
    labels.get(m[1]).add(m[3].replace(/''/g, "'").toLowerCase());
  }
}

test('the seeds were read (aluminium has its windows & doors label)', () => {
  assert.ok(labels.get('aluminium')?.has('aluminium windows & doors'), 'taxonomy seed tuples not found under scripts/sql');
});

test('every SERVICE_WORDS phrase is an exact label of its trade', () => {
  const block = fixtures.match(/const SERVICE_WORDS = \{([\s\S]*?)\n\};/)[1];
  const bad = [];
  for (const [, trade, text] of block.matchAll(/^\s*([a-z_]+):\s*'([^']*)'/gm)) {
    for (const phrase of text.split(',').map((s) => s.trim().toLowerCase()).filter(Boolean)) {
      if (!labels.get(trade)?.has(phrase)) bad.push(`${trade}: "${phrase}"`);
    }
  }
  assert.deepEqual(bad, [], `not an exact service label, so the demo supplier never confirms it: ${bad.join('; ')}`);
});
