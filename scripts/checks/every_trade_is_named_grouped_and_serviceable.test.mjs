// EVERY TRADE IS NAMED, GROUPED AND SERVICEABLE (23 Sep 2026, sales_engineer; founder instructions
// 895/899/900: "trades are missing" — add them first, then build knowledge for the complete list).
//
// What a trade must carry to be on the platform at all, held in two places:
//
//   FILES (always, CI included). The seed scripts/sql/the_missing_trades_join_the_taxonomy_under_twelve_groups.sql
//   names twelve groups, puts each of the 42 trades that existed in one, and adds the new trades each with
//   EN + AR names, a group and at least one service (EN + AR). Every copy of that list must agree with it:
//     - serverCopy.ts TRADE_EN / TRADE_AR (the sign-up picker, which cannot read the table) and TRADE_GROUPS
//       (its groups: every code in exactly one, the same one the seed gives it);
//     - line_specs/taxonomy_trades.ts (how the quote hold reads each new code): every new code in exactly
//       one of BRANDED_GOODS / NO_LINE_SPECS_YET, and nothing else there.
//
//   PRODUCTION (when a management token exists; read-only). Every ACTIVE taxonomy_trade row has an English
//   label, an Arabic label, a group, and at least one active service. Until the seed is applied the group
//   column does not exist and this part says NOT_VERIFIED_SEED_NOT_APPLIED instead of failing.
//
//   KNOWLEDGE (reported, NOT a failure yet). A trade has a knowledge pack when public.sales_knowledge holds
//   a row tagged 'trade:<code>'. The knowledge for the complete list is being built after this (instruction
//   900); until it lands, the trades without a pack are printed as KNOWLEDGE_GAP lines. When the packs are
//   in, turn the report into an assertion — do not delete it.
//
//   node --test scripts/checks/every_trade_is_named_grouped_and_serviceable.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const AR = /[ء-ي]/;
const between = (s, a, b) => { const i = s.indexOf(a); assert.ok(i >= 0, `not found: ${a}`); const j = s.indexOf(b, i); assert.ok(j > i, `not found: ${b}`); return s.slice(i, j); };

const seed = read('scripts/sql/the_missing_trades_join_the_taxonomy_under_twelve_groups.sql');
const GROUPS = [...between(seed, 'insert into public.taxonomy_trade_group', 'on conflict (code)')
  .matchAll(/^ {2}\('([a-z_]+)','([^']+)','([^']+)',\d+\)/gm)].map(([, code, en, ar]) => ({ code, en, ar }));
const EXISTING = Object.fromEntries([...between(seed, 'with v(code, group_code) as (values', 'update public.taxonomy_trade t set group_code')
  .matchAll(/^ {2}\('([a-z_]+)','([a-z_]+)'\)/gm)].map(([, c, g]) => [c, g]));
const NEW = [...between(seed, 'insert into public.taxonomy_trade (code, label', ') as v(code, label, label_ar')
  .matchAll(/^ {2}\('([a-z_0-9]+)','([^']+)','([^']+)',array\[[^\]]*\]::text\[\],\d+,'([a-z_]+)'\)/gm)]
  .map(([, code, en, ar, group]) => ({ code, en, ar, group }));
const SERVICES = [...seed.matchAll(/^ {2}\('([a-z_0-9]+)','([a-z][a-z0-9_]*)','([^']+)','([^']+)',\d+\)/gm)]
  .map(([, trade, code, en, ar]) => ({ trade, code, en, ar }));

test('the seed: twelve groups, the 42 existing trades each in one, every new trade named, grouped and serviced', () => {
  assert.equal(GROUPS.length, 12);
  for (const g of GROUPS) assert.ok(g.en && AR.test(g.ar), g.code);
  const groupCodes = new Set(GROUPS.map((g) => g.code));
  assert.equal(Object.keys(EXISTING).length, 42);
  for (const [c, g] of Object.entries(EXISTING)) assert.ok(groupCodes.has(g), `${c} -> unknown group ${g}`);
  assert.ok(NEW.length >= 150, `only ${NEW.length} new trades parsed from the seed`);
  const bad = [];
  for (const t of NEW) {
    if (EXISTING[t.code]) bad.push(`${t.code} already existed`);
    if (!t.en.trim() || AR.test(t.en)) bad.push(`${t.code}: English name`);
    if (!AR.test(t.ar)) bad.push(`${t.code}: Arabic name`);
    if (!groupCodes.has(t.group)) bad.push(`${t.code}: group ${t.group}`);
    const svc = SERVICES.filter((s) => s.trade === t.code);
    if (!svc.length) bad.push(`${t.code}: no service`);
    for (const s of svc) if (AR.test(s.en) || !AR.test(s.ar)) bad.push(`${t.code}.${s.code}: EN/AR`);
  }
  assert.deepEqual(bad, []);
  for (const g of GROUPS) assert.ok(Object.values(EXISTING).includes(g.code) || NEW.some((t) => t.group === g.code), `${g.code} is empty`);
});

test('the sign-up mirror (serverCopy.ts) names every trade, in both languages, in the group the seed gives it', () => {
  const copy = read('src/components/portal/supplier/serverCopy.ts');
  const keysOf = (name) => {
    const body = new RegExp(`const ${name}: Record<string, string> = \\{([\\s\\S]*?)\\n\\};`).exec(copy);
    assert.ok(body, `${name} not found`);
    return [...body[1].matchAll(/(?:^|[\s,{])([a-z_]+):\s*'/g)].map((m) => m[1]);
  };
  const all = [...Object.keys(EXISTING), ...NEW.map((t) => t.code)].sort();
  assert.deepEqual([...keysOf('TRADE_EN')].sort(), all);
  assert.deepEqual([...keysOf('TRADE_AR')].sort(), all);
  const groups = [...between(copy, 'export const TRADE_GROUPS', '\n];').matchAll(/\{ code: '([a-z_]+)',[\s\S]*?codes: \[([^\]]*)\] \}/g)]
    .map(([, code, list]) => ({ code, codes: [...list.matchAll(/'([a-z_0-9]+)'/g)].map((m) => m[1]) }));
  assert.deepEqual(groups.map((g) => g.code), GROUPS.map((g) => g.code));
  const seen = new Map();
  for (const g of groups) for (const c of g.codes) { assert.ok(!seen.has(c), `${c} is in two groups`); seen.set(c, g.code); }
  assert.deepEqual([...seen.keys()].sort(), all);
  const want = { ...EXISTING, ...Object.fromEntries(NEW.map((t) => [t.code, t.group])) };
  for (const [c, g] of seen) assert.equal(g, want[c], `${c} is grouped differently from the seed`);
});

test('the quote hold decides every new code exactly once (line_specs/taxonomy_trades.ts)', () => {
  const src = read('supabase/functions/_shared/line_specs/taxonomy_trades.ts');
  const setOf = (name) => [...between(src, `export const ${name}`, ']);').matchAll(/'([a-z_0-9]+)'/g)].map((m) => m[1]);
  const b = setOf('BRANDED_GOODS'); const o = setOf('NO_LINE_SPECS_YET');
  assert.deepEqual(b.filter((c) => o.includes(c)), [], 'a code in both lists');
  assert.deepEqual([...b, ...o].sort(), NEW.map((t) => t.code).sort());
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || fs.existsSync(path.join(homedir(), '.supabase', 'access-token'));
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');

test('production: every active trade has EN + AR, a group and a service; the knowledge gap is reported', { skip: hasToken ? false : 'no Supabase management token' }, async (t) => {
  const { sql } = await import('../lib/db.mjs');
  const [col] = await sql(`select count(*)::int as n from information_schema.columns
    where table_schema = 'public' and table_name = 'taxonomy_trade' and column_name = 'group_code'`);
  if (!col.n) { console.log('NOT_VERIFIED_SEED_NOT_APPLIED'); return t.skip('taxonomy_trade.group_code does not exist yet: the seed is pending'); }
  const rows = await sql(`
    select t.code, coalesce(btrim(t.label), '') <> '' as en, coalesce(t.label_ar, '') ~ '[ء-ي]' as ar, t.group_code is not null as grouped,
           exists (select 1 from public.taxonomy_trade_service s where s.trade_code = t.code and s.active) as serviced,
           exists (select 1 from public.sales_knowledge k where k.tags @> array['trade:' || t.code]) as pack
      from public.taxonomy_trade t where t.active order by t.code`);
  const bad = rows.filter((r) => !(r.en && r.ar && r.grouped && r.serviced))
    .map((r) => `${r.code}:${r.en ? '' : ' no EN'}${r.ar ? '' : ' no AR'}${r.grouped ? '' : ' no group'}${r.serviced ? '' : ' no service'}`);
  const gap = rows.filter((r) => !r.pack).map((r) => r.code);
  console.log(`  ${rows.length} active trades; knowledge packs ${rows.length - gap.length}/${rows.length}`);
  for (const c of gap) console.log(`KNOWLEDGE_GAP ${c}`);
  assert.deepEqual(bad, []);
});
