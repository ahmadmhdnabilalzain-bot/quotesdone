// THE IMPLICATION MAP AND THE SERVICE ALIASES HAVE ONE SEED (18 Sep 2026, sales_engineer).
//
// Two consumers read this data and they must never disagree:
//   * SQL — public.service_implication and taxonomy_trade_service.aliases, seeded by
//     scripts/sql/a_supplier_describes_its_services_in_its_own_words_and_the_sales_engineer_rewrites_them.sql,
//     read by fn_services_effective inside fn_match_capability;
//   * the edge runtime — supabase/functions/_shared/service_aliases.json and
//     service_implications.json, read by _shared/service_rewrite.ts for the supplier's preview.
//
// If the two drift, a supplier confirms one list and matching uses another. That is the defect this
// check exists to catch, and it is a FILE check (no database) so it runs in CI without a token.
//
//   node --test scripts/checks/the_implication_map_has_one_seed.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const json = (p) => JSON.parse(read(p));
const AR = /[ء-ي]/;

const SQL_FILE = 'scripts/sql/a_supplier_describes_its_services_in_its_own_words_and_the_sales_engineer_rewrites_them.sql';
const sql = read(SQL_FILE);
const aliases = json('supabase/functions/_shared/service_aliases.json');
const implications = json('supabase/functions/_shared/service_implications.json');

// The alias seed block: ('trade','code', array['a','b'])
const aliasBlock = sql.slice(sql.indexOf('with seed(trade_code, code, aliases) as (values'), sql.indexOf('update public.taxonomy_trade_service t'));
const sqlAliases = new Map(
  [...aliasBlock.matchAll(/\('([a-z_]+)','([a-z][a-z0-9_]*)', array\[([^\]]*)\]::text\[\]\)/g)]
    .map(([, trade, code, list]) => [`${trade}.${code}`, [...list.matchAll(/'((?:[^']|'')*)'/g)].map((m) => m[1].replace(/''/g, "'"))]),
);

// The implication seed block: ('from','trade','code','en','ar')
const implBlock = sql.slice(sql.indexOf('insert into public.service_implication (from_code, implies_trade, implies_code, reason_en, reason_ar) values'));
const sqlImpl = new Map(
  [...implBlock.matchAll(/\('([a-z_.]+)','([a-z_]+)','([a-z][a-z0-9_]*)','((?:[^']|'')*)','((?:[^']|'')*)'\)/g)]
    .map(([, from, trade, code, en, ar]) => [`${from} -> ${trade}.${code}`, { en: en.replace(/''/g, "'"), ar: ar.replace(/''/g, "'") }]),
);

const jsonImpl = new Map(
  implications.flatMap((g) => g.to.map((to) => [`${g.from} -> ${to}`, { en: g.en, ar: g.ar }])),
);

test('the SQL alias seed is exactly the JSON alias seed', () => {
  assert.ok(sqlAliases.size > 0, 'no alias rows parsed out of the SQL — the seed block moved');
  assert.deepEqual([...sqlAliases.keys()].sort(), Object.keys(aliases).sort(), 'the two alias seeds name different services');
  for (const [key, list] of sqlAliases) {
    const want = [...new Set([...aliases[key].en, ...aliases[key].ar].map((s) => s.trim()).filter(Boolean))];
    assert.deepEqual(list, want, `aliases differ for ${key}`);
  }
});

test('the SQL implication seed is exactly the JSON implication seed, reasons included', () => {
  assert.ok(sqlImpl.size > 0, 'no implication rows parsed out of the SQL — the seed block moved');
  assert.deepEqual([...sqlImpl.keys()].sort(), [...jsonImpl.keys()].sort(), 'the two implication seeds hold different relations');
  for (const [k, v] of sqlImpl) assert.deepEqual(v, jsonImpl.get(k), `the reason differs for ${k}`);
});

test('every implication names an alias-known service and carries both languages', () => {
  const known = new Set(Object.keys(aliases));
  for (const k of jsonImpl.keys()) {
    const [from, to] = k.split(' -> ');
    assert.ok(known.has(to), `${k}: the implied service is not in the taxonomy seed`);
    if (from.includes('.')) assert.ok(known.has(from), `${k}: the stated service is not in the taxonomy seed`);
    assert.notEqual(from, to, `${k} implies itself`);
    const r = jsonImpl.get(k);
    assert.ok(r.en.trim().length >= 10, `${k} has no English reason`);
    assert.ok(AR.test(r.ar), `${k} has no Arabic reason`);
  }
});

// ONE LEVEL ONLY (founder instruction 439). The data is allowed to contain A->B and B->C — that is two
// separate curated statements. What must never appear is a READER that follows both. This asserts the
// rule is written where it is enforced, in the SQL and in the TypeScript, and that neither uses a
// recursive CTE over the map.
test('the readers apply the map one level, and say so', () => {
  assert.ok(/ONE LEVEL/.test(sql), 'the SQL no longer states the one-level rule');
  assert.ok(!/with\s+recursive/i.test(sql), 'a recursive CTE appeared over the implication map');
  const ts = read('supabase/functions/_shared/service_rewrite.ts');
  assert.ok(/ONE level|one level/.test(ts), 'service_rewrite.ts no longer states the one-level rule');
});

test('the implication map is not trivially small, and no trade implies nothing', () => {
  assert.ok(jsonImpl.size >= 80, `only ${jsonImpl.size} implication rows — the map was gutted`);
  const froms = new Set([...jsonImpl.keys()].map((k) => k.split(' -> ')[0]));
  assert.ok(froms.size >= 30, `only ${froms.size} distinct stated capabilities imply anything`);
});

// The founder's own example, instruction 439, kept as a named row so it cannot be quietly dropped.
test('decoration implies flooring', () => {
  assert.ok(jsonImpl.has('interior_fitout.decoration -> flooring.tiling'),
    'the founder’s example (decoration -> flooring) is not in the map');
});
