// deno test --no-lock supabase/functions/supplier_api/new_option.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { newOptionRefusal } from './new_option.ts';
Deno.test('a new option after a reveal is refused with 409', () => {
  assertEquals(newOptionRefusal(true, 1)?.status, 409);
  assertEquals(newOptionRefusal(true, 1)?.body.code, 'option_after_reveal');
});
Deno.test('a new option before any reveal, or an edit after one, is not refused here', () => {
  assertEquals(newOptionRefusal(true, 0), null);
  assertEquals(newOptionRefusal(undefined, 3), null);
  assertEquals(newOptionRefusal('true', 3), null);
});
// The double-click guard on the server is the unique index quotes_inquiry_supplier_option_key (inquiry_id,
// supplier_id, option_no), in supabase/schema/full_schema/01; a racing second insert answers 409 option_exists.
Deno.test('the unique index that stops two rows for one option exists in the schema', async () => {
  const schema = await Deno.readTextFile(new URL('../../schema/full_schema/01_extensions_sequences_tables_constraints_indexes.sql', import.meta.url));
  assertEquals(/CREATE UNIQUE INDEX quotes_inquiry_supplier_option_key ON public\.quotes USING btree \(inquiry_id, supplier_id, option_no\)/.test(schema), true);
});
