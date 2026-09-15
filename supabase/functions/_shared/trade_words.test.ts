// trade_words — the TS twin of fn_norm_trades reads Arabic as well as English, exact or none.
// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/trade_words.test.ts
//
// The fixture (trade_words.fixtures.json) is the SAME list the Node parity check feeds to production
// fn_norm_trades (scripts/checks/arabic_trade_words_resolve_the_same_in_sql_and_ts.test.mjs). Here it
// runs offline against the Arabic alias list the SQL file applies plus a verbatim slice of the English.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { arNorm, tradesFromText, type TradeTerm } from './trade_words.ts';
import AR from './trade_aliases_ar.json' with { type: 'json' };
import FIXTURES from './trade_words.fixtures.json' with { type: 'json' };

// English aliases, verbatim from production taxonomy_trade (read 15 Sep 2026), for the English cases.
const EN: Record<string, string[]> = {
  hvac: ['hvac', 'air conditioning', 'air-conditioning', 'chiller', 'ducting', 'ventilation'],
  plumbing: ['plumbing', 'plumber', 'sanitary', 'drainage', 'pipework'],
  building_materials: ['building material', 'building materials', 'cement', 'ready mix'],
  aluminium: ['aluminium', 'aluminum', 'cladding', 'facade', 'curtain wall'],
  electrical: ['electrical', 'electric', 'wiring', 'switchgear'],
  packaging: ['packaging company', 'packaging material', 'corrugated'],
};
const ALIASES = AR as Record<string, string[]>;
const VOCAB: TradeTerm[] = Object.keys(ALIASES).map((code) => ({ code, aliases: [...(EN[code] || []), ...ALIASES[code]] }));
const codes = (text: string) => tradesFromText(text, VOCAB).map((h) => h.code).sort();

Deno.test('every shared fixture resolves to exactly its codes', () => {
  for (const f of FIXTURES as { text: string; codes: string[] }[]) assertEquals(codes(f.text), [...f.codes].sort(), f.text);
});

Deno.test('arNorm folds exactly what public.fn_ar_norm folds', () => {
  assertEquals(arNorm('أإآٱ ى ة ؤ ئ'), 'اااا ي ه و ي');
  assertEquals(arNorm('نِجـــارَةٌ'), 'نجاره');
  assertEquals(arNorm('٠١٢٣٤٥٦٧٨٩'), '0123456789');
  assertEquals(arNorm('Fit-Out'), 'Fit-Out'); // English is untouched
});

Deno.test('the article and the attached letters are read; a letter inside a word is not a word start', () => {
  for (const t of ['النجارة', 'والنجارة', 'بالنجارة', 'للنجارة', 'وللنجارة', 'ونجارة', 'نجارين']) assertEquals(codes(t), ['joinery'], t);
  assertEquals(codes('لمكافحة الحريق'), ['fire_fighting']); // proclitic on the first word, article on the second
  assertEquals(codes('تحديد'), []); // حديد (steel) inside تحديد is not at a word start
});

Deno.test('the evidence is the supplier\'s own line, spelling and hyphens kept', () => {
  const [h] = tradesFromText('نبذة عن الشركة\nنقدم أعمال النجارة الفاخرة\nاتصل بنا', VOCAB);
  assertEquals(h.code, 'joinery');
  assertEquals(h.phrases, ['نجار']);
  assertEquals(h.snippet, 'نقدم أعمال النجارة الفاخرة');
  const [b] = tradesFromText('We supply building-materials.', VOCAB);
  assertEquals(b.snippet, 'We supply building-materials.');
});

Deno.test('the Arabic alias list is exact-or-none: one code per alias, no article, Arabic letters only', () => {
  const seen = new Map<string, string>();
  assertEquals(Object.keys(ALIASES).length, 40);
  for (const [code, list] of Object.entries(ALIASES)) {
    assert(list.length > 0, code);
    for (const a of list) {
      const n = arNorm(a);
      assert(n.length >= 3, `${code}: ${a} is shorter than a term`);
      assert(/^[ء-ي]+( [ء-ي]+)*$/.test(n), `${code}: ${a} is not plain Arabic words`);
      assert(!a.split(' ').some((w) => w.startsWith('ال')), `${code}: ${a} carries the article; the matcher adds it`);
      assert(!seen.has(n), `${a} is an alias of both ${seen.get(n)} and ${code}`);
      seen.set(n, code);
    }
  }
});
