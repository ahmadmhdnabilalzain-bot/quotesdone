// alias_pattern — the Arabic folding and the alias pattern the SERVICE alias index and the catalogue's cue words use.
// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/alias_pattern.test.ts
//
// Until 29 Sep 2026 this file was trade_words.test.ts and asserted that every sentence of trade_words.fixtures.json
// resolved to its trades BY ITS WORDS. That behaviour is gone on purpose (ruling 890, ledger 1054): the same
// fixture now proves the opposite in trade_resolve.test.ts. What is asserted here is what the file still does.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { arNorm, foldForMatch, termPattern } from './alias_pattern.ts';
import AR from './trade_aliases_ar.json' with { type: 'json' };

const ALIASES = AR as Record<string, string[]>;
const hit = (alias: string, text: string) => !!termPattern(alias)?.test(foldForMatch(text).norm);

Deno.test('arNorm folds exactly what public.fn_ar_norm folds', () => {
  assertEquals(arNorm('أإآٱ ى ة ؤ ئ'), 'اااا ي ه و ي');
  assertEquals(arNorm('نِجـــارَةٌ'), 'نجاره');
  assertEquals(arNorm('٠١٢٣٤٥٦٧٨٩'), '0123456789');
  assertEquals(arNorm('Fit-Out'), 'Fit-Out'); // English is untouched
});

Deno.test('the article and the attached letters are read; a letter inside a word is not a word start', () => {
  for (const t of ['النجارة', 'والنجارة', 'بالنجارة', 'للنجارة', 'وللنجارة', 'ونجارة', 'نجارين']) assert(hit('نجار', t), t);
  assert(hit('مكافحة حريق', 'لمكافحة الحريق')); // proclitic on the first word, article on the second
  assert(!hit('حديد', 'تحديد'));               // حديد inside تحديد is not at a word start
  assert(!hit('hvac', 'Prehvac'));
  assert(hit('building materials', 'We supply building-materials.')); // runs of - _ / . are one space
  assertEquals(termPattern('ab'), null);       // shorter than a term
});

Deno.test('foldForMatch keeps the index of every character in the ORIGINAL text', () => {
  const { norm, at } = foldForMatch('نِجـارة-باب');
  assertEquals(norm, 'نجاره باب');
  assertEquals(at.length, norm.length);
  assertEquals('نِجـارة-باب'[at[at.length - 1]], 'ب');
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
      assert(!a.split(' ').some((w) => w.startsWith('ال')), `${code}: ${a} carries the article; the pattern adds it`);
      assert(!seen.has(n), `${a} is an alias of both ${seen.get(n)} and ${code}`);
      seen.set(n, code);
    }
  }
});
