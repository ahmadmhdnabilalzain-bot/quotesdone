// tradeCode must agree with public.fn_trade_code: a supplier's typed trade and a request's category
// meet on string equality in fn_match_capability, so two spellings of one trade must be one code.
import { assertEquals } from 'jsr:@std/assert@1';
import { tradeCode, relevanceFloorApplies } from './supplier_capability.ts';

Deno.test('relevanceFloorApplies: the floor gates only a request that named products', () => {
  assertEquals(relevanceFloorApplies([]), false);          // create_inquiry's match: exact trade decides
  assertEquals(relevanceFloorApplies(['', '  ']), false);
  assertEquals(relevanceFloorApplies(undefined), false);
  assertEquals(relevanceFloorApplies(['aluminium windows']), true);
});

Deno.test('tradeCode: spellings of one trade are one code', () => {
  for (const s of ['Packaging Services', 'packaging-services', '  packaging_services ', 'PACKAGING / services']) {
    assertEquals(tradeCode(s), 'packaging_services');
  }
});

Deno.test('tradeCode: a taxonomy code passes through unchanged', () => {
  for (const c of ['glazing', 'interior_fitout', 'av_it']) assertEquals(tradeCode(c), c);
});

Deno.test('tradeCode: Arabic letters are kept, punctuation is not', () => {
  assertEquals(tradeCode('خدمات التغليف'), 'خدمات_التغليف');
  assertEquals(tradeCode(' - '), '');
});
