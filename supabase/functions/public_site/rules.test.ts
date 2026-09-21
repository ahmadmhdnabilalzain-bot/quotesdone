// deno test supabase/functions/public_site/rules.test.ts
// Replays the two findings of the 22 Sep 2026 production walk: English authority names on the Arabic
// service pages, and 429s on the service pages' own price question.
import { assertEquals } from 'jsr:@std/assert@1';
import { documentLine, isPageTopic, PAGE_TOPICS } from './rules.ts';

Deno.test('an Arabic page gets the Arabic authority; English keeps English; no Arabic falls back', () => {
  const x = { item: 'Trade licence', item_ar: 'رخصة تجارية', authority: 'the relevant emirate authority', authority_ar: 'السلطة المختصة في الإمارة' };
  assertEquals(documentLine(x, 'ar'), { item: 'رخصة تجارية', authority: 'السلطة المختصة في الإمارة' });
  assertEquals(documentLine(x, 'en'), { item: 'Trade licence', authority: 'the relevant emirate authority' });
  assertEquals(documentLine({ item: 'X', authority: 'SIRA' }, 'ar'), { item: 'X', authority: 'SIRA' });
  assertEquals(documentLine({ item: 'X', authority: null, authority_ar: null }, 'ar'), { item: 'X', authority: null });
});

Deno.test('index.ts builds every document line through documentLine', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  // Any other place that reads the authority field directly is how the English came back.
  assertEquals((src.match(/x\?\.authority\b/g) || []).length, 0, 'index.ts reads the authority field directly');
  assertEquals((src.match(/documentLine\(x, lang\)/g) || []).length, 2);
});

Deno.test('the service page topics are exactly the ones PriceGuide asks on mount', async () => {
  const pg = await Deno.readTextFile(new URL('../../../src/components/PriceGuide.tsx', import.meta.url));
  const block = pg.slice(pg.indexOf('SERVICE_TOPIC'), pg.indexOf('};', pg.indexOf('SERVICE_TOPIC')));
  const asked = [...block.matchAll(/:\s*'([^']+)'/g)].map((m) => m[1]).sort();
  assertEquals(asked, [...PAGE_TOPICS].sort());
});

Deno.test('a page topic skips the visitor limiter; free text and unknown topics do not', () => {
  assertEquals(isPageTopic({ topic: 'solar' }), true);
  assertEquals(isPageTopic({ topic: 'solar', question: 'how much for my roof in JVC?' }), false);
  assertEquals(isPageTopic({ topic: 'anything a script invents' }), false);
  assertEquals(isPageTopic({}), false);
});
