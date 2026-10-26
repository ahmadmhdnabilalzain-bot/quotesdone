// "Not sure" must open the handoff to the sales engineer; nothing else may.
//   deno test supabase/functions/customer_api/spec_handoff.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { notSureKeys, specHandoffArgs } from './spec_handoff.ts';

Deno.test('a not-sure spec opens a spec.not_sure handoff to the sales engineer', () => {
  const a = specHandoffArgs('inq-1', 'cust-1', notSureKeys(['finish', ' finish ', '', 7]));
  assertEquals(a?.p_to, 'sales_engineer');
  assertEquals(a?.p_type, 'spec.not_sure');
  assertEquals(a?.p_subject_id, 'inq-1');
  assertEquals(a?.p_payload.not_sure, ['finish', '7']);
});

Deno.test('no not-sure spec opens nothing', () => {
  assertEquals(specHandoffArgs('inq-1', 'cust-1', notSureKeys(undefined)), null);
  assertEquals(specHandoffArgs('inq-1', 'cust-1', []), null);
});
