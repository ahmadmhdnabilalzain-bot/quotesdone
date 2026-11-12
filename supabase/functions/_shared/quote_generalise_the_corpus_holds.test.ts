// THE BRAND HIDER CORPUS HOLDS (sales_engineer, 12 Nov 2026; review rounds 1-3 of the quoting fix). Every string the reviewer
// and the earlier tests used is a row of quote_generalise.corpus.json with its exact expected output:
//   hide - the identity is gone (and the reviewer's identity pattern, where given, is not found); identitiesLeft finds the
//          identity as written and nothing after the hider: the customer-door check and the hider agree;
//   keep - the string is unchanged, and identitiesLeft finds nothing in it;
//   gap  - shown or over-hidden today and not separable by rule; the row names why, and its output is pinned so any change
//          to it is a decision, not an accident.
// A change to the hider is done only when the whole corpus passes. To re-pin after a deliberate change, regenerate the
// file and read every changed row.
//   deno test --node-modules-dir=none --allow-read supabase/functions/_shared/quote_generalise_the_corpus_holds.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { generaliseText, identitiesLeft } from './quote_generalise.ts';

type Row = { s: string; list: 'hide' | 'keep' | 'gap'; expect: string; identity?: string; reason?: string; main: string; src: string };
const { rows } = JSON.parse(await Deno.readTextFile(new URL('./quote_generalise.corpus.json', import.meta.url))) as { rows: Row[] };

Deno.test(`the corpus is whole: ${rows.length} rows, every list present, every gap has a reason`, () => {
  assert(rows.length >= 480, String(rows.length));
  for (const l of ['hide', 'keep', 'gap'] as const) assert(rows.some((r) => r.list === l), l);
  for (const r of rows.filter((r) => r.list === 'gap')) assert(r.reason && r.reason.length > 10, r.s);
  assertEquals(new Set(rows.map((r) => r.s)).size, rows.length, 'a string is listed twice');
});

for (const list of ['hide', 'keep', 'gap'] as const) {
  Deno.test(`every ${list} row gives its pinned output`, () => {
    const bad: string[] = [];
    for (const r of rows.filter((x) => x.list === list)) {
      const out = generaliseText(r.s).text;
      if (out !== r.expect) { bad.push(`${JSON.stringify(r.s)} => ${JSON.stringify(out)}, pinned ${JSON.stringify(r.expect)}`); continue; }
      if (list === 'hide') {
        if (out === r.s) bad.push(`${JSON.stringify(r.s)} is shown as written`);
        if (r.identity) { const [src, flags] = r.identity.split('/'); if (new RegExp(src, flags).test(out)) bad.push(`${JSON.stringify(r.s)} still carries ${r.identity}`); }
        if (!identitiesLeft(r.s).length) bad.push(`identitiesLeft misses ${JSON.stringify(r.s)}`);
        if (identitiesLeft(out).length) bad.push(`identitiesLeft still finds ${JSON.stringify(identitiesLeft(out))} in ${JSON.stringify(out)}`);
      }
      if (list === 'keep' && identitiesLeft(r.s).length) bad.push(`identitiesLeft flags the specification ${JSON.stringify(r.s)}: ${JSON.stringify(identitiesLeft(r.s))}`);
    }
    assertEquals(bad, []);
  });
}
