// Replays the stored shape of stage-2 run f4294be8 (12 Oct 2026): trades null, the trade in `category`,
// the emirate in Arabic. Every one of those 9 requests matched nobody.
import { assertEquals } from 'jsr:@std/assert@1';
import { tradeSlugsOf, matchEmirate } from './match_criteria.ts';

Deno.test('a request whose trade is only in its category still names that trade', () => {
  assertEquals(tradeSlugsOf({ trades: null, category: 'painting' }), ['painting']);
  assertEquals(tradeSlugsOf({ trades: null, category: 'glass' }), ['glass']);
  assertEquals(tradeSlugsOf({ trades: ['hvac'], category: 'combined' }), ['hvac']);
  assertEquals(tradeSlugsOf({ trades: [], category: '' }), []);
});

Deno.test('an Arabic emirate is matched in the spelling suppliers state', () => {
  assertEquals(matchEmirate('دبي'), 'Dubai');
  assertEquals(matchEmirate('أبوظبي'), 'Abu Dhabi');
  assertEquals(matchEmirate('الشارقة'), 'Sharjah');
  assertEquals(matchEmirate('Ras Al Khaimah'), 'Ras Al Khaimah');
  assertEquals(matchEmirate(''), null);
  assertEquals(matchEmirate('Somewhere'), 'Somewhere');
});
