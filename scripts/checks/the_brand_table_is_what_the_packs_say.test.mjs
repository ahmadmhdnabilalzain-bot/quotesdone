// THE BRAND TABLE IS WHAT THE PACKS SAY (10 Nov 2026, sales_engineer; founder ledger 1589).
//
// supabase/functions/_shared/brand_facts.generated.ts is the table the quotation generaliser reads to turn a brand into
// "<tier> <origin> brand" before the reveal. It is GENERATED from knowledge/packs/*.market.json (uae_market_brands) and
// knowledge/brands/origin_and_tier.json by scripts/kb/brand_facts.mjs. This fails when:
//   * the committed table is not what the packs and the explicit table give now (a pack gained a brand, or the k1/k2
//     knowledge branches added origins, and nobody regenerated) — the generaliser would miss the new make;
//   * an origin is not an ISO-2 code the generaliser has an adjective for, or a tier is not one of three words — the
//     founder's rule is a FACTUALLY CORRECT generic description, so a value the code cannot say is refused here;
//   * the founder's own example is lost: Grohe is German and premium ("premium German brand mixer", never Italian);
//   * a nationality or a country is listed as a brand ("Malaysian" was, and "Malaysian origin" lost its origin).
//   node --test scripts/checks/the_brand_table_is_what_the_packs_say.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const rows = [...read('supabase/functions/_shared/brand_facts.generated.ts').matchAll(/^ {2}("(?:[^"\\]|\\.)*"): \{ o: (null|"[A-Z]{2}"), t: (null|"[a-z-]+"), s: "([a-z+_]+)", w: ([01]), tr: (\[.*\]) \},$/gm)]
  .map((m) => ({ name: JSON.parse(m[1]), o: JSON.parse(m[2]), t: JSON.parse(m[3]), s: m[4], w: m[5] === '1' }));
// The adjectives the generaliser can write (quote_generalise.ts ORIGIN), read from its source.
const ORIGIN_KEYS = new Set([...read('supabase/functions/_shared/quote_generalise.ts').matchAll(/\b([A-Z]{2}): \{ en: '/g)].map((m) => m[1]));

test('the committed table is what the packs and the explicit table give now', () => {
  const r = spawnSync(process.execPath, [join(REPO, 'scripts/kb/brand_facts.mjs'), '--check'], { encoding: 'utf8' });
  assert.equal(r.status, 0, (r.stderr || '') + (r.stdout || ''));
});

test('every row parses, and the table covers the packs', () => {
  const lines = read('supabase/functions/_shared/brand_facts.generated.ts').split('\n').filter((l) => /^ {2}"/.test(l));
  assert.equal(rows.length, lines.length, 'a row the check cannot parse');
  assert.ok(rows.length >= 1000, `the packs list ${rows.length} brands; 219 packs listed 1,700+ on 10 Nov 2026`);
});

test('every origin is one the generaliser can say, every tier one of three words', () => {
  for (const r of rows) {
    if (r.o) assert.ok(ORIGIN_KEYS.has(r.o), `${r.name}: origin ${r.o} has no adjective in quote_generalise.ts ORIGIN`);
    if (r.t) assert.ok(['premium', 'mid-range', 'economy'].includes(r.t), `${r.name}: tier ${r.t}`);
  }
  const table = JSON.parse(read('knowledge/brands/origin_and_tier.json')).brands;
  for (const [name, v] of Object.entries(table)) {
    assert.ok(v.origin === null || ORIGIN_KEYS.has(v.origin), `${name}: ${v.origin}`);
    assert.ok(v.tier === null || ['premium', 'mid-range', 'economy'].includes(v.tier), `${name}: ${v.tier}`);
  }
});

test("the founder's example stays true, and no nationality is a brand", () => {
  const g = rows.find((r) => r.name === 'Grohe');
  assert.deepEqual([g?.o, g?.t], ['DE', 'premium'], 'Grohe is a premium German brand');
  const NAT = /^(?:german|italian|spanish|french|japanese|chinese|indian|american|british|turkish|korean|emirati|saudi|swiss|malaysian|thai|vietnamese|european|uae|china|india|italy|germany|japan|turkey)$/i;
  assert.deepEqual(rows.filter((r) => NAT.test(r.name)).map((r) => r.name), []);
});
