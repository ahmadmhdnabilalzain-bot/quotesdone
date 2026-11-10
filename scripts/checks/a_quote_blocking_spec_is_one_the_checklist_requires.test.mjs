// A QUOTE-BLOCKING SPEC IS ONE THE CHECKLIST REQUIRES, AND IT REACHES THE CHECKLIST TABLE MARKED (sales_engineer, 10 Nov 2026).
//
// Founder, ledger 1587-1590: the customer interview happens once, with no back-and-forth, so the inquiry must carry every
// detail a supplier needs for a firm price. Each enriched spec_checklist entry in knowledge/packs therefore names its
// `blocking` specs (no firm price without them) beside required_specs, and a `spec_guide` row per spec saying why it prices,
// the usual UAE options and the follow-up questions an answer triggers. Pinned here, offline:
//   1. load_trade_spec_checklists.mjs carries blocking: true onto exactly the specs the pack lists as blocking;
//   2. every checklist that has a spec_guide has at least one blocking spec, a guide row for every required spec, and a
//      non-empty pricing reason on every blocking row (validate() in verified_packs.mjs refuses the malformed cases);
//   3. every brand profile carries an origin country and one of the tier words, so a supplier-identifying brand can be
//      replaced with a factually correct generic description.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { checklistsOf } from '../kb/load_trade_spec_checklists.mjs';

const dir = new URL('../../knowledge/packs/', import.meta.url);
const packs = readdirSync(dir).filter((f) => /^[a-z_]+(\.market)?\.json$/.test(f)).map((f) => ({ f, p: JSON.parse(readFileSync(new URL(f, dir), 'utf8')) }));

test('the loader marks exactly the pack\'s blocking specs', () => {
  const pack = { trade: 'zz_demo', entries: [{ id: 'zz_demo:chk', kind: 'spec_checklist', topic: 'ZZ DEMO', required_specs: ['Size (mm)', 'Colour', 'Quantity'], blocking: ['Size (mm)', 'Quantity'] }] };
  const [row] = checklistsOf(pack, 'zz_demo.json');
  assert.deepEqual(row.specs.map((s) => [s.label_en, s.blocking]), [['Size (mm)', true], ['Colour', false], ['Quantity', true]]);
  const old = checklistsOf({ trade: 'zz_demo', entries: [{ ...pack.entries[0], blocking: undefined }] }, 'zz_demo.json')[0];
  assert.ok(old.specs.every((s) => s.blocking === false), 'a checklist without a blocking list marks nothing');
});

test('every guided checklist names its blockers and guides every spec it requires', () => {
  let guided = 0;
  for (const { f, p } of packs) for (const e of p.entries ?? []) {
    if (e.kind !== 'spec_checklist' || !e.spec_guide) continue;
    guided++;
    const req = e.required_specs ?? [];
    assert.ok((e.blocking ?? []).length > 0, `${f} ${e.id}: a guided checklist with no blocking spec`);
    assert.deepEqual(new Set(e.spec_guide.map((g) => g.spec)), new Set(req), `${f} ${e.id}: guide rows and required_specs differ`);
    for (const g of e.spec_guide.filter((x) => x.blocking)) assert.ok(String(g.why_it_prices).trim(), `${f} ${e.id}: blocking ${g.spec} has no pricing reason`);
    assert.match(e.body_en, /Quote-blocking/, `${f} ${e.id}: the body does not say which specs block a firm price`);
  }
  assert.ok(guided >= 1, 'no guided checklist found');
});

test('every brand profile has an origin and a tier the description can be built from', () => {
  for (const { f, p } of packs) for (const e of p.entries ?? []) for (const b of e.brand_profiles ?? []) {
    assert.ok(b.origin_country && ['economy', 'mid', 'premium', 'luxury', 'dealer', 'operator', 'supplier'].includes(b.tier), `${f} ${b.brand}`);
    assert.ok(!b.generic_en.includes(b.brand), `${f} ${b.brand}: the generic description repeats the brand`);
  }
});
