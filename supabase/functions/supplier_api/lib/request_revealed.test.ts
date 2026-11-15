// deno test --no-lock --node-modules-dir=none supabase/functions/supplier_api/lib/request_revealed.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { isRequestRevealed, REQUEST_REVEALED } from './request_revealed.ts';

Deno.test('a payment landing between the pre-check and the insert is answered with the 409 sentence, not a 500', () => {
  // the error PostgREST hands back when trigger a05 refuses the insert
  assert(isRequestRevealed({ code: 'P0001', message: 'REQUEST_REVEALED: the customer has already opened a quotation on this request, so it takes no new quotations' }));
  assert(!isRequestRevealed({ code: '23505', message: 'duplicate key value violates unique constraint' }));
  assert(!isRequestRevealed(null));
  assertEquals(REQUEST_REVEALED.code, 'inquiry_revealed');
  assert(!/[؀-ۿ]/.test(REQUEST_REVEALED.error), 'suppliers read English');
});
