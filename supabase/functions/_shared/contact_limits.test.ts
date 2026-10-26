// deno test --no-lock --node-modules-dir=auto supabase/functions/_shared/contact_limits.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { CONTACT_MESSAGE_MAX, contactMessageError } from './contact_limits.ts';

Deno.test('a message at the cap is accepted', () => {
  assertEquals(contactMessageError('x'.repeat(CONTACT_MESSAGE_MAX)), null);
});
Deno.test('one over the cap is rejected in English and Arabic, never truncated', () => {
  const e = contactMessageError('x'.repeat(CONTACT_MESSAGE_MAX + 1));
  assert(e && /too long/.test(e.error) && /طويلة/.test(e.error_ar));
  assert(contactMessageError('ZZ DEMO ' + 'x'.repeat(20000)));
});
Deno.test('emoji count as one character each', () => {
  assertEquals(contactMessageError('😀'.repeat(CONTACT_MESSAGE_MAX)), null);
});
Deno.test('too short is still rejected', () => {
  assert(contactMessageError('hi')?.error_ar);
});
