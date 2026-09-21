// 21 Sep 2026 customer audit, finding 2 (BLOCKER): "Send to suppliers" answered 500
// "Cannot read properties of undefined (reading 'filter')" on an electrical request. The category
// classifier and the keyword map disagree on which categories exist; the map must never throw on a
// category it has no words for.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { detect, KW } from './keywords.ts';
import { detectCat } from '../_shared/trade_classify.ts';

const AUDIT_TEXT = 'Supply and install a 12-way DB board, cables and sockets for a 4-bedroom villa in Abu Dhabi. Brands: Schneider, Ducab. 2 year warranty. Needed by 30 Nov.';

Deno.test('the auditor\'s electrical request classifies to a category the keyword map does not know, and detect() does not throw', () => {
  const cat = detectCat(AUDIT_TEXT);
  assertEquals(cat, 'electrical');
  assertEquals(KW[cat!], undefined, 'the reproduction depends on the map lacking this key; if it gains one, the test still holds');
  const d = detect(AUDIT_TEXT);
  assertEquals(d.category, 'electrical');
  assertEquals(d.emirate, 'Abu Dhabi');
  assertEquals(d.keywords, []);
});

Deno.test('a category the map knows still yields its keywords', () => {
  const d = detect('gypsum false ceiling for a villa in Dubai');
  assertEquals(d.category, 'gypsum');
  assertEquals(d.emirate, 'Dubai');
  assert(d.keywords.includes('gypsum') && d.keywords.includes('false ceiling'));
});

Deno.test('detect() never throws for any category the classifier can return', () => {
  // Every classifier category, fed its own first alias, must come back with an array of keywords.
  const mod = Deno.readTextFileSync(new URL('../_shared/trade_classify.ts', import.meta.url));
  const slugs = [...mod.matchAll(/^\s{2}([a-z_]+): \[/gm)].map((m) => m[1]);
  assert(slugs.length > 16, 'the classifier lists more categories than the keyword map (' + slugs.length + ')');
  for (const s of slugs) { const d = detect(s.replace(/_/g, ' ')); assert(Array.isArray(d.keywords), s); }
});
