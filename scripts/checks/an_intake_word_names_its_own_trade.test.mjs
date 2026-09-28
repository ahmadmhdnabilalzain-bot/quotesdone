// AN INTAKE TRADE WORD NAMES ITS OWN TRADE, NEVER A NEIGHBOUR (24 Sep 2026, sales_engineer).
//
// Founder rule: exact trade match or none, no nearest mapping. Measured on 24 Sep 2026: ten intake slugs
// resolved to a neighbour trade (demolition -> civil_works, swimming-pools -> landscaping, movers ->
// logistics_moving, ...) and two aliases named two trades at once. The fix is
// scripts/sql/an_intake_trade_word_names_its_own_trade_never_a_neighbour.sql.
//
// FILES (always): every slug that file repoints names a trade the seed defines, and no alias in the seed
// names two trades. PRODUCTION (read-only, when a management token exists and the fix is applied): no
// active alias names two trades, every intake slug resolves only to active trades, and the words resolve
// to their own trade. Before the fix is applied the production part prints NOT_VERIFIED_FIX_NOT_APPLIED.
//
//   node --test scripts/checks/an_intake_word_names_its_own_trade.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => fs.readFileSync(path.join(ROOT, p), 'utf8');
const seed = read('scripts/sql/the_missing_trades_join_the_taxonomy_under_twelve_groups.sql');
const fix = read('scripts/sql/an_intake_trade_word_names_its_own_trade_never_a_neighbour.sql');

const OWN = {
  'demolition': ['demolition_works'], 'general-building-contracting': ['general_contracting'], 'masonry': ['masonry_blockwork'],
  'interior-design': ['design_consultancy'], 'swimming-pools': ['swimming_pools'], 'insulation': ['thermal_insulation'],
  'marble-granite': ['marble_stone'], 'blinds-curtains': ['curtains_blinds'], 'movers': ['removals_relocation'],
  'engineering-and-architectural-consultancies': ['design_consultancy', 'engineering_consultancy'], 'it-networking': ['it_services'],
};

test('the fix repoints each ambiguous word to its own trade, and each of those trades is defined', () => {
  const pairs = Object.fromEntries([...fix.matchAll(/^ {4}\('([a-z-]+)', array\[([^\]]+)\]\)/gm)]
    .map(([, slug, codes]) => [slug, [...codes.matchAll(/'([a-z_]+)'/g)].map((m) => m[1])]));
  assert.deepEqual(pairs, OWN);
  const defined = new Set([...seed.matchAll(/^ {2}\('([a-z_0-9]+)','[^']+','[^']+',array\[/gm)].map((m) => m[1]).concat(['engineering_consultancy', 'it_services']));
  for (const codes of Object.values(OWN)) for (const c of codes) assert.ok(defined.has(c), `${c} is not a trade the seed defines`);
});

test('no alias in the seed names two trades', () => {
  const seen = new Map();
  const block = seed.slice(seed.indexOf('insert into public.taxonomy_trade (code, label'), seed.indexOf(') as v(code, label, label_ar'));
  for (const [, code, list] of block.matchAll(/^ {2}\('([a-z_0-9]+)','[^']+','[^']+',array\[([^\]]*)\]::text\[\]/gm))
    for (const [, a] of list.matchAll(/'((?:[^']|'')+)'/g)) {
      const k = a.toLowerCase();
      assert.ok(!seen.has(k) || seen.get(k) === code, `'${a}' names ${seen.get(k)} and ${code}`);
      seen.set(k, code);
    }
});

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN || fs.existsSync(path.join(homedir(), '.supabase', 'access-token'));
test('production: one alias one trade, every slug active, each word its own trade', { skip: hasToken ? false : 'no Supabase management token' }, async (t) => {
  const { sql } = await import('../lib/db.mjs');
  const [applied] = await sql(`select count(*)::int as n from public.taxonomy_trade where code = 'demolition_works' and active`);
  if (!applied.n) { console.log('NOT_VERIFIED_FIX_NOT_APPLIED'); return t.skip('the 24 Sep trades are not applied yet'); }
  const dup = await sql(`select lower(a) as w from public.taxonomy_trade, unnest(aliases) a where active group by 1 having count(distinct code) > 1`);
  assert.deepEqual(dup.map((r) => r.w), []);
  const dead = await sql(`select m.intake_slug from public.intake_trade_taxonomy m, unnest(m.trade_codes) c
    where not exists (select 1 from public.taxonomy_trade t where t.code = c and t.active)`);
  assert.deepEqual(dead, []);
  for (const [slug, codes] of Object.entries(OWN)) {
    const [r] = await sql(`select public.fn_norm_trades('${slug}') as c`);
    assert.deepEqual(r.c, codes, slug);
  }
});
