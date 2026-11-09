// QUOTE QUALITY, TRADE KEYS AND REPEAT REQUESTS NEVER REACH THE MODEL (24 Sep 2026, it_engineer; founder: routine work
// is code, the LLM only for real judgement; ledger 890: no word matching; exact trade match or none).
//
// WHAT FAILS IF THE CAUSE RETURNS (static, over the committed SQL and TypeScript):
//   * trg_quote_quality holds a quote on 'needs_reasoning', or supplier_api asks the model for its aspects again;
//   * fn_category_key_ask files category.key_for_slug to the model again;
//   * trg_inquiry_enrich files inquiry.same_request to the model instead of pg_trgm similarity, or matches text.
//
//   node --test scripts/checks/quote_quality_trade_keys_and_repeats_never_reach_the_model.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { functionSource } from '../lib/function_sources.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const FILE = 'scripts/sql/quote_quality_trade_keys_and_repeat_requests_are_code_not_the_model.sql';
const code = (p) => readFileSync(join(REPO, p), 'utf8').split('\n').map((l) => l.replace(/--.*$/, '').replace(/\/\/.*$/, '')).join('\n');
const SQL = code(FILE);
function body(name) {
  const i = SQL.indexOf(`create or replace function public.${name}(`);
  assert.ok(i >= 0, `${name} is not defined in ${FILE}`);
  const rest = SQL.slice(i);
  const tag = rest.match(/\bas\s+(\$\w*\$)/i)[1];
  const a = rest.indexOf(tag) + tag.length;
  return rest.slice(a, rest.indexOf(tag, a));
}
const MODEL = /fn_reason_route_ask|fn_reason_hold|think\(/;

test('quote quality is structural: no held verdict, and supplier_api asks no model for the aspects', () => {
  const b = body('trg_quote_quality');
  assert.ok(!MODEL.test(b), 'trg_quote_quality files a model question');
  assert.ok(!b.includes("'needs_reasoning'"), 'a quote is held on a model reading again');
  assert.match(b, /v_cat_status := 'not_read';/, 'an unread category does not fall to the structural score');
  assert.doesNotMatch(b, /match_regex|~\*|ilike/, 'the quote text is pattern-matched');
  assert.match(SQL, /set status = 'expired'\s+where status = 'held' and surface = 'sql\.trg_quote_quality'/);
  const api = functionSource('supplier_api').split('\n').map((l) => l.replace(/--.*$/, '').replace(/\/\/.*$/, '')).join('\n');
  assert.ok(!api.includes('reasonQuoteAspects'), 'supplier_api reasons the quote aspects again');
  assert.ok(!code('supabase/functions/_shared/reasoned_suppliers.ts').includes("surface: 'sql.trg_quote_quality'"));
});

test('a trade word key is an exact lookup or none: fn_category_key_ask files nothing', () => {
  const b = body('fn_category_key_ask');
  assert.ok(!MODEL.test(b), 'fn_category_key_ask files category.key_for_slug to the model again');
  assert.match(b, /select null::bigint/);
  assert.match(SQL, /set status = 'expired'\s+where status = 'held' and surface = 'category\.key_for_slug'/);
});

test('a repeat request is flagged by pg_trgm similarity, never by the model or a substring', () => {
  const b = body('trg_inquiry_enrich');
  assert.ok(!MODEL.test(b), 'trg_inquiry_enrich files inquiry.same_request to the model again');
  assert.match(b, /c_repeat_similarity constant real := 0\.5;/, 'the documented threshold is gone');
  assert.match(b, /public\.similarity\(i\.summary, NEW\.summary\)/);
  assert.match(b, /v_sim >= c_repeat_similarity/);
  assert.doesNotMatch(b, /ilike|\blike\b|~\*|position\(|strpos\(/i, 'the summary is substring-matched again');
});

// The 40 words held on category.key_for_slug on 24 Sep 2026 (production, reasoning_held_question).
const HELD_40 = ['water-tank-cleaning', 'safety', 'general-building-contracting', 'blinds-curtains', 'security', 'waterproofing',
  'carpentry-joinery', 'insulation', 'flooring', 'facade-cleaning', 'movers', 'engineering-and-architectural-consultancies', 'roofing',
  'garage-doors', 'landscaping', 'smart-home', 'cleaning', 'general', 'marble-granite', 'tiling', 'general-services-other', 'hvac', 'mep',
  'acrylic', 'generators', 'job-shop-manufacturing', 'scaffolding', 'epoxy-flooring', 'masonry', 'carpentry', 'commercial-retail-fitout',
  'demolition', 'interior-design', 'electrical', 'structural-steel-fabrication', 'upholstery', 'tents-and-shade-structures',
  'custom-furniture', 'combined-mep', 'pest'];
test('each of the 40 held trade words is mapped to one catalogue trade or listed as ambiguous with a reason', () => {
  const raw = readFileSync(join(REPO, FILE), 'utf8');
  const seed = SQL.slice(SQL.indexOf('insert into public.category_route_map'), SQL.indexOf('on conflict (category) do nothing'));
  const mapped = new Map([...seed.matchAll(/\('([a-z-]+)', (\d+),/g)].map((m) => [m[1], Number(m[2])]));
  const ambiguous = new Set([...raw.slice(raw.indexOf('-- UNMAPPED')).matchAll(/^--   ([a-z-]+)\s+\S/gm)].map((m) => m[1]));
  assert.equal(mapped.size, 19); assert.equal(ambiguous.size, 21);
  for (const w of HELD_40) assert.ok(mapped.has(w) !== ambiguous.has(w), `${w}: exactly one of mapped or ambiguous`);
  for (const w of [...mapped.keys(), ...ambiguous]) assert.ok(HELD_40.includes(w), `${w} is not one of the 40`);
  for (const n of mapped.values()) assert.ok(n >= 1 && n <= 86, 'a catalogue number');
});
