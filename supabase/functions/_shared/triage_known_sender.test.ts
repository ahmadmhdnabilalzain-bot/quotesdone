// email_triage's exact-sender route. FAILS if a settled spam sender would go back to the model.
import { assertEquals } from 'jsr:@std/assert@1';
import { knownSenderCategory } from './triage_known_sender.ts';

Deno.test('an address triaged spam twice and never anything else is spam without the model', () => {
  assertEquals(knownSenderCategory(['spam', 'spam']), 'spam');
  assertEquals(knownSenderCategory(['spam', null, 'spam']), 'spam');
});
Deno.test('once, or ever anything else, still goes to the model', () => {
  assertEquals(knownSenderCategory(['spam']), null);
  assertEquals(knownSenderCategory(['spam', 'customer_question', 'spam']), null);
  assertEquals(knownSenderCategory([]), null);
});
