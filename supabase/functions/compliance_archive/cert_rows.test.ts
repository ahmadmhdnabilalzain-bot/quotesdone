// Run: deno test supabase/functions/compliance_archive/cert_rows.test.ts
import { assertEquals } from 'jsr:@std/assert';
import { certFields, identityRows } from './cert_rows.ts';

Deno.test('a supplier certificate names the signatory the supplier entered, not the contact', () => {
  const f = { ...certFields({ contact_name: 'ZZ DEMO Contact', signatory_name: 'ZZ DEMO Signatory' }, 'supplier'), company: 'ZZ DEMO Co' };
  assertEquals(identityRows(f, 'supplier'), [['Full name', 'ZZ DEMO Contact'], ['Company', 'ZZ DEMO Co'], ['Authorised signatory', 'ZZ DEMO Signatory']]);
});

Deno.test('no signatory entered: the contact is named; a customer has no signatory row', () => {
  const f = { ...certFields({ contact_name: 'ZZ DEMO Contact' }, 'supplier'), company: 'C' };
  assertEquals(identityRows(f, 'supplier')[2], ['Authorised signatory', 'ZZ DEMO Contact']);
  assertEquals(identityRows({ ...certFields({ full_name: 'ZZ DEMO Buyer' }, 'customer'), company: '' }, 'customer'), [['Full name', 'ZZ DEMO Buyer']]);
});
