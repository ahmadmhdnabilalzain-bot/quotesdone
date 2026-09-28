// readability.ts — the plain-language gate's own cases (founder instruction 1013 item 7). No network.
import { assert, assertEquals } from 'jsr:@std/assert';
import { checkReadability } from './readability.ts';

Deno.test('a short plain English reply passes', () => {
  const r = checkReadability('Posting a request is free. You pay 3% only when you reveal a supplier. Call 800 123 or write to help@quotesdone.ae.', 'en');
  assert(r.ok, r.issues.join());
  assertEquals(r.score, 100);
});
Deno.test('a 40-word sentence fails on length', () => {
  const r = checkReadability(Array(40).fill('word').join(' ') + '.', 'en');
  assert(!r.ok); assert(r.issues.some((i) => i.startsWith('long_sentence')));
});
Deno.test('jargon and internal identifiers fail', () => {
  const r = checkReadability('Your RFQ is in the workflow. See fn_quote_status.', 'en');
  assert(!r.ok); assertEquals(r.jargon.sort(), ['fn_quote_status', 'rfq', 'workflow'].sort());
});
Deno.test('a word that merely contains a jargon token is not jargon (rapid is not api)', () => {
  assert(checkReadability('We give a rapid reply.', 'en').ok);
});
Deno.test('language: Arabic expected, English given, fails; Arabic given with a link passes', () => {
  assert(!checkReadability('We will reply soon.', 'ar').ok);
  assert(checkReadability('سنرد عليك قريبًا. الرابط:\nhttps://www.quotesdone.ae/help', 'ar').ok);
});
Deno.test('decimal numbers do not split sentences', () => {
  assertEquals(checkReadability('The fee is 3.5 percent of the quote.', 'en').sentences, 1);
});
Deno.test('tone: shouting and blame cost points but do not fail alone', () => {
  const r = checkReadability('PLEASE read it. As I said, you forgot the drawing!!', 'en');
  assert(r.ok); assert(r.tone <= 60, String(r.tone));
  assertEquals(checkReadability('We need the drawing. UAE and AED are fine.', 'en').tone, 100);
});
