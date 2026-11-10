// THE GENERAL-MATCHING MATRIX, TEXT -> CODES (10 Nov 2026, sales_engineer; founder ledger 1573, 1579, 1586).
//
// For 44 rows in all 12 taxonomy groups, a supplier describes a service in his own words and a customer asks for it in
// different words. This proves the half that runs in TypeScript: the supplier's words (service_rewrite.rewriteServices, the
// Services tab and the profile reader) and the customer's (service_vocabulary.serviceKeysOf, dispatch and the intake count)
// both reach the SAME service key, exactly, over the live vocabulary of 10 Nov 2026 plus the curated aliases and the
// film-wrap service of scripts/sql/a_suppliers_own_words_reach_every_customer_who_asks_for_the_same_work.sql, read from
// that file (one source). The other half, codes -> suppliers, is that file's probe on production (rolled back).
//
// Meaning is given an embedder that understands nothing (every clause orthogonal to every service), so a key here is
// an EXACT name, never a nearest one. Before the SQL file the same code reached the row's key on 3 supplier texts and 2
// customer texts of 44 (fixture keys_before).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { rewriteServices, type ServiceTerm } from './service_rewrite.ts';
import { serviceKeysOf } from './service_vocabulary.ts';
import type { MeaningService } from './service_meaning.ts';
import FX from './general_matching.fixtures.json' with { type: 'json' };
import VOCAB from './general_matching.vocab.fixtures.json' with { type: 'json' };

const SQL_FILE = new URL('../../../scripts/sql/a_suppliers_own_words_reach_every_customer_who_asks_for_the_same_work.sql', import.meta.url);
const sql = await Deno.readTextFile(SQL_FILE).catch(() => '');

/** The curated aliases, exactly as the SQL file appends them: its seed block ('trade','code', array[...]::text[]). */
function curated(src: string): Map<string, string[]> {
  const block = src.slice(src.indexOf('with seed(trade_code, code, aliases) as (values'), src.indexOf('pairs as ('));
  const out = new Map<string, string[]>();
  for (const [, t, c, list] of block.matchAll(/\('([a-z_]+)','([a-z][a-z0-9_]*)', array\[([^\]]*)\]::text\[\]\)/g)) {
    out.set(`${t}.${c}`, [...list.matchAll(/'((?:[^']|'')*)'/g)].map((m) => m[1].replace(/''/g, "'").trim().toLowerCase()));
  }
  return out;
}
const added = curated(sql);
const newService = sql.match(/values \('wallpaper', 'film_wrap', '([^']+)', '([^']+)'/);

function vocab(): MeaningService[] {
  const base = (VOCAB.services as [string, string, string, string, string[]][])
    .map(([trade_code, code, label_en, label_ar, aliases]) => ({ trade_code, code, label_en, label_ar, aliases: [...aliases] }));
  if (newService) base.push({ trade_code: 'wallpaper', code: 'film_wrap', label_en: newService[1], label_ar: newService[2], aliases: [] });
  for (const s of base) {
    const more = added.get(`${s.trade_code}.${s.code}`) ?? [];
    s.aliases = [...s.aliases, ...more.filter((a) => !s.aliases.includes(a))];
  }
  return base.map((s) => ({ ...s, vec: [1, 0], vec_ml: [1, 0] }));
}
const V = vocab();
const understandsNothing = async () => [0, 1];

type Row = (typeof FX.rows)[number];
const rows = FX.rows as Row[];

Deno.test('the SQL file is there, adds the film-wrap service, and curates aliases on every row\'s service', () => {
  assert(sql.length > 0, 'scripts/sql/a_suppliers_own_words_reach_every_customer_who_asks_for_the_same_work.sql is missing');
  assert(newService, 'the file does not add wallpaper.film_wrap');
  for (const r of rows) assert(added.has(r.key), `${r.family}: ${r.key} has no curated aliases in the SQL file`);
});

Deno.test('the matrix spans all 12 taxonomy groups, two trades or more in each, and names its inquiries by taxonomy code', () => {
  const byGroup = new Map<string, Set<string>>();
  for (const r of rows) (byGroup.get(r.group) ?? byGroup.set(r.group, new Set()).get(r.group)!).add(r.supplier.trade);
  assertEquals(byGroup.size, 12, [...byGroup.keys()].join(','));
  for (const [g, t] of byGroup) assert(t.size >= 2, `${g}: only ${[...t].join(',')}`);
  assert(rows.length >= 40);
  // ledger 1586: the 223 codes, not the 32 intake slugs (a slug carries a hyphen; a code never does)
  for (const r of rows) assert(/^[a-z][a-z0-9_]*$/.test(r.customer.trade), `${r.family}: ${r.customer.trade} is not a taxonomy code`);
  for (const r of rows) {
    const ctl = rows.find((x) => x.family === r.control);
    assert(ctl && ctl.group !== r.group, `${r.family}: its control is not from another group`);
  }
});

for (const r of rows) {
  Deno.test(`matrix ${r.group} / ${r.family}: "${r.supplier.text}" and "${r.customer.text}" reach ${r.key}`, async () => {
    const s = rewriteServices(r.supplier.text, V as ServiceTerm[]);
    assertEquals([...s.service_keys].sort(), [...r.supplier.keys].sort(), `supplier: ${r.supplier.text}`);
    const c = await serviceKeysOf(r.customer.text, null, { services: V, embed: understandsNothing });
    assert(c.complete, `the customer's text was not read whole (${c.state})`);
    assertEquals(c.keys, [...r.customer.keys].sort(), `customer: ${r.customer.text}`);
    assert(s.service_keys.includes(r.key) && c.keys.includes(r.key), `${r.key} is not on both sides`);
  });
}

Deno.test('the founder\'s own sentence: supply and installation of PVC decorative panels, WPC panels and vinyl wrap', () => {
  const s = rewriteServices('Supply and installation of PVC decorative panels, WPC panels and vinyl wrap', V as ServiceTerm[]);
  assertEquals(s.service_keys.sort(), ['wallpaper.film_wrap', 'wallpaper.wall_panels']);
  const part = s.items.find((i) => i.kind === 'service' && i.key === 'wallpaper.wall_panels');
  assertEquals(part && part.kind === 'service' ? part.part : null, 'PVC decorative panels', 'the delivery frame was not cut from his own name');
});

Deno.test('a curated alias names exactly one service over the whole fixture vocabulary (a shared name would name neither)', () => {
  const owners = new Map<string, Set<string>>();
  const norm = (x: string) => x.toLowerCase().replace(/[_\-–—]+/g, ' ').replace(/\s+/g, ' ').trim();
  for (const s of V) for (const n of [s.code, s.label_en, s.label_ar, ...(s.aliases || [])]) {
    if (!n) continue;
    (owners.get(norm(n)) ?? owners.set(norm(n), new Set()).get(norm(n))!).add(`${s.trade_code}.${s.code}`);
  }
  const shared: string[] = [];
  for (const [k, list] of added) for (const a of list) { const o = owners.get(norm(a)); if (o && o.size > 1) shared.push(`${k}: "${a}" also names ${[...o].filter((x) => x !== k).join(',')}`); }
  assertEquals(shared, []);
});

Deno.test('no word matching came back: a curated alias inside a sentence still names nothing', () => {
  const r = rewriteServices('We supply many pvc panels to villas every year', V as ServiceTerm[]);
  assertEquals(r.service_keys, [], 'an alias word inside a sentence named a service');
  assertEquals(rewriteServices('PVC panel boxes', V as ServiceTerm[]).service_keys, [], 'a longer phrase holding an alias was matched');
  // the frame is cut only for supply / installation: maintenance of X is not X
  assertEquals(rewriteServices('Maintenance of swimming pool', V as ServiceTerm[]).service_keys, []);
});
