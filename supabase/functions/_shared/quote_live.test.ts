// deno test --no-lock supabase/functions/_shared/quote_live.test.ts
// The customer's comparison (quote_compare `live`), portal list, letters and reveal door all read this:
// a withdrawn quotation is gone from what the customer sees, with no stale price left among the live ones.
import { assertEquals } from 'jsr:@std/assert@1';
import { isLiveQuote, NOT_LIVE_QUOTE_IN } from './quote_live.ts';

Deno.test('a withdrawn or draft quote is not live; submitted and accepted are', () => {
  const qs = [{ id: 'a', status: 'submitted', quote_amount: 9000 }, { id: 'b', status: 'withdrawn', quote_amount: 7000 },
    { id: 'c', status: 'draft', quote_amount: 6000 }, { id: 'd', status: 'accepted', quote_amount: 9500 }];
  const live = qs.filter((q) => isLiveQuote(q.status));
  assertEquals(live.map((q) => q.id), ['a', 'd']);
  assertEquals(Math.min(...live.map((q) => q.quote_amount)), 9000, 'the withdrawn 7000 is not the cheapest price any more');
});
Deno.test('the PostgREST filter names the same two states', () => {
  assertEquals(NOT_LIVE_QUOTE_IN, '("draft","withdrawn")');
});
