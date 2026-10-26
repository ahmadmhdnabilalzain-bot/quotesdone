// trade_glossary_ar.test.ts — the Arabic of our own keys (trade codes, units, attribute keys).
// deno test --no-lock supabase/functions/_shared/trade_glossary_ar.test.ts
//
// What it proves: every trade on the site has an Arabic (and English) name; our keys are looked up by
// exact key; and the phrase translator is gone — a person's words are no longer turned into Arabic by
// substitution (decision point trade_glossary_ar, 23 Sep 2026: they are reasoned, reasoned_governance.ts).
// `latinLeaks` is the guard other tests run on OUR OWN outgoing Arabic text.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import cats from '../../../src/content/categories.json' with { type: 'json' };
import * as G from './trade_glossary_ar.ts';
import { isProperToken, CATEGORY_AR, CATEGORY_EN, arAttr, arUnit, arCount } from './trade_glossary_ar.ts';

/** Latin words in an Arabic string that are not a brand, standard or code. */
export function latinLeaks(s: string): string[] {
  const t = s.replace(/المورّد [A-Z]{1,2}\b/g, '').replace(/\bQD-[A-Z0-9-]+\b/g, '').replace(/https?:\S+/g, '').replace(/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/g, '');
  return (t.match(/[A-Za-z][A-Za-z0-9'’\-/.+]*/g) || []).filter((w) => !w.split(/[-/]/).filter(Boolean).every(isProperToken));
}

Deno.test('every trade on the site has an Arabic and an English name', () => {
  // deno-lint-ignore no-explicit-any
  const items = (cats as any).items as Array<{ code: string; en: string; ar: string }>;
  assert(items.length >= 50, 'categories.json shrank: ' + items.length);
  for (const c of items) {
    assert(CATEGORY_AR[c.code], 'no Arabic trade name for ' + c.code);
    assertEquals(CATEGORY_EN[c.code], c.en, 'English trade name for ' + c.code);
  }
});

Deno.test('our keys are exact: an attribute key or unit key maps, a free-text label does not', () => {
  assert(arAttr('warranty'), 'a registered attribute key has its Arabic');
  assertEquals(arAttr('Solid oak veneer finish'), null, 'free text is not translated by substitution; the document reasons it');
  assertEquals(arUnit('sqm'), 'م²');
  assertEquals(arUnit('furlong'), null);
  assertEquals(arCount(2, 'week'), 'أسبوعان');
});

Deno.test('the phrase translator is gone: nothing here turns a person\'s words into Arabic', () => {
  assertEquals((G as Record<string, unknown>).arTrade, undefined);
  assertEquals((G as Record<string, unknown>).GLOSSARY_SIZE, undefined);
});

Deno.test('the outgoing-text guard: brands, standards and codes may stand in Arabic; other English leaks', () => {
  assert(isProperToken('R410A') && isProperToken('BS') && isProperToken('Blum') && !isProperToken('widget'));
  assertEquals(latinLeaks('وحدة Gree بقدرة 5 TR'), []);
  assertEquals(latinLeaks('خزانة ملابس with doors'), ['with', 'doors']);
});
