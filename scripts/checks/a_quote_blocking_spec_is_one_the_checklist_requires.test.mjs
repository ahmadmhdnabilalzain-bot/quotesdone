// A QUOTE-BLOCKING SPEC IS ONE THE CHECKLIST REQUIRES (sales_engineer, 10 Nov 2026, ledger 1587-1590).
//
// Founder: the customer interview happens once, with no back-and-forth, so the inquiry must carry every detail a
// supplier needs for a firm price; incoming quotes are reviewed as an expert; a supplier-identifying brand is replaced
// with a factually correct generic description. The trade packs therefore carry, on a spec_checklist entry:
//   blocking                  the specs without which no firm price can be given (each one of required_specs)
//   spec_guide                one row per required spec: why it prices, the usual UAE options, the follow-up it triggers
//   site_visit_required_when  the sample / drawing / site visit that is genuinely unavoidable, or null
// and, on a uae_market_brands entry, brand_origins: origin country and tier per brand the pack already names.
// The field names are shared by the three knowledge branches (coordinator, 10 Nov 2026); the loader that carries them
// into the tables is owned elsewhere. Pinned here, offline, on the pack files themselves:
//   1. a blocking spec is a required spec, and the guide's blocking rows are exactly the blocking list;
//   2. every guided checklist guides every required spec, names at least one blocker, gives each blocker a pricing
//      reason, and says in its body which specs block a firm price;
//   3. a brand origin has a country and one tier word, its generic description does not repeat the brand, and the brand
//      is one the pack's own text already names (a profile is not a way to add an unchecked market claim).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';

const dir = new URL('../../knowledge/packs/', import.meta.url);
const packs = readdirSync(dir).filter((f) => /^[a-z_]+(\.market)?\.json$/.test(f)).map((f) => ({ f, p: JSON.parse(readFileSync(new URL(f, dir), 'utf8')) }));
const TIERS = ['economy', 'mid', 'premium', 'luxury', 'dealer', 'operator', 'supplier'];
const AR = /[؀-ۿ]/;

test('a blocking spec is a required spec, and the guide agrees with the blocking list', () => {
  let n = 0;
  for (const { f, p } of packs) for (const e of p.entries ?? []) {
    if (e.blocking === undefined) continue;
    n++;
    const req = new Set(e.required_specs ?? []);
    assert.ok(Array.isArray(e.blocking), `${f} ${e.id}: blocking must be an array`);
    for (const b of e.blocking) assert.ok(req.has(b), `${f} ${e.id}: blocking spec ${JSON.stringify(b)} is not in required_specs`);
    const fromGuide = (e.spec_guide ?? []).filter((g) => g.blocking).map((g) => g.spec).sort();
    assert.deepEqual(fromGuide, [...e.blocking].sort(), `${f} ${e.id}: spec_guide blocking rows and the blocking list disagree`);
  }
  assert.ok(n >= 66, `only ${n} checklists carry a blocking list`);
});

test('every guided checklist names its blockers and guides every spec it requires', () => {
  for (const { f, p } of packs) for (const e of p.entries ?? []) {
    if (e.kind !== 'spec_checklist' || !e.spec_guide) continue;
    assert.ok((e.blocking ?? []).length > 0, `${f} ${e.id}: a guided checklist with no blocking spec`);
    assert.deepEqual(new Set(e.spec_guide.map((g) => g.spec)), new Set(e.required_specs ?? []), `${f} ${e.id}: guide rows and required_specs differ`);
    for (const g of e.spec_guide) assert.equal(typeof g.blocking, 'boolean', `${f} ${e.id}: ${g.spec} blocking is not a boolean`);
    for (const g of e.spec_guide.filter((x) => x.blocking)) assert.ok(String(g.why_needed_to_price).trim(), `${f} ${e.id}: blocking ${g.spec} has no pricing reason`);
    assert.ok(e.site_visit_required_when === null || String(e.site_visit_required_when).trim(), `${f} ${e.id}: site_visit_required_when must be a sentence or null`);
    assert.match(e.body_en, /Quote-blocking/, `${f} ${e.id}: the body does not say which specs block a firm price`);
    assert.ok(AR.test(e.body_ar), `${f} ${e.id}: body_ar is not Arabic`);
  }
});

test('every brand origin has a country, a tier, a generic description, and is named by its own pack', () => {
  for (const { f, p } of packs) for (const e of p.entries ?? []) for (const b of e.brand_origins ?? []) {
    assert.ok(b.origin && TIERS.includes(b.tier), `${f} ${b.brand}: needs origin and a tier (${TIERS.join('/')})`);
    assert.ok(String(b.generic_en ?? '').trim() && AR.test(String(b.generic_ar ?? '')), `${f} ${b.brand}: generic_en and an Arabic generic_ar`);
    assert.ok(!b.generic_en.includes(b.brand), `${f} ${b.brand}: the generic description repeats the brand`);
    const own = p.entries.map((x) => x.body_en.split('\n\nOrigin and tier')[0]).join(' ');
    assert.ok(own.includes(b.brand.split(' (')[0]), `${f} ${b.brand}: profiled but not named in the pack's own text`);
  }
});
