// supplier_trade_choice — the reader's shared pieces: quotes found in the text they came from, JSON answers read, documents cut into parts.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/supplier_trade_choice.test.ts
//
// 12 Nov 2026 (sales_engineer, ruling 1647): the one-call chooser these tests were written for (checkChoice, settleReadings, majority,
// the second look) is DELETED with its tests; the profile is read in two steps (supplier_profile_reading.ts and its tests, and the
// hard-profile set scripts/e2e/services_hard_profiles/). What stays here is what the two steps still use, with its regressions.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { answerJson, quoteFinder, quoteKey, textChunks } from './supplier_trade_choice.ts';
import { readDocForTrades } from './supplier_doc_trades.ts';
import { fakeReader } from './supplier_profile_reading.test_reader.ts';

const DOC = 'ZZ DEMO Joinery LLC\nScope of Work: Supply & Installation of Doors, Kitchen,\nWardrobes and Vanity Cabinets\nWe take up Service, Installation & Maintenance of:\nSprinkler Systems, Foam System';

Deno.test('a quote that runs across a PDF line break is still found, line by line (Royal Joinery, run 4)', () => {
  assert(quoteFinder(DOC)('Supply & Installation of Doors, Kitchen,\nWardrobes and Vanity Cabinets'));
  assertEquals(quoteKey('Doors,  Kitchen,'), 'doors kitchen');
  assert(!quoteFinder(DOC)('We install data networks'), 'a line the document does not hold is not found');
});
Deno.test('a word hyphenated across a line break is read whole (N07 OCR: "Compa-\\nny")', () => {
  const text = 'ZZ DEMO REGC is a leading UAE-based General Contracting Compa-\nny. We install Sprinkler Systems.';
  assert(quoteFinder(text)('is a leading UAE-based General Contracting Company. We install Sprinkler Systems.'));
});
Deno.test('an answer in a code fence or after a sentence is still read; prose is not an answer (Summertown, run 9)', () => {
  const fenced = 'Here is the result:\n```json\n{"evidence":[{"words":"Wardrobes","quote":"Wardrobes and Vanity Cabinets"}]}\n```\nDone.';
  assertEquals((answerJson(fenced, 'evidence') as { evidence: unknown[] }).evidence.length, 1);
  assertEquals(answerJson('The company does joinery.', 'evidence'), null);
  assertEquals(answerJson('I cannot answer that {not json}', 'evidence'), null);
});
Deno.test('a long document is cut in parts on line breaks, and nothing is lost between them (N05 546, H02 deadline)', () => {
  const text = Array.from({ length: 50 }, (_, i) => 'line ' + i + ' ' + 'x'.repeat(500)).join('\n');
  const parts = textChunks(text, 6000);
  assert(parts.length > 1 && parts.every((p) => p.length <= 6000));
  assertEquals(parts.join('\n'), text);
});
// H01, held-out set (review of #1412, 18 Oct 2026): an image-only profile's trades were taken from the vision model's own SUMMARY of
// services, so every quote matched text the model itself had written. A picture is read only from the lines it PRINTS; a quote from a
// summary is not in those lines and is refused (now by supplier_profile_reading.checkReading).
Deno.test('an image-only profile proposes what its PRINTED lines quote; a summary phrase is refused (H01, ledger 1442)', async () => {
  const { modelReadText } = await import('./supplier_doc_trades.ts');
  const lines = ['ZZ DEMO Aluminium works, Glass works, UPVC windows & doors', 'Glass Partitions', 'Doors & windows'];
  const deps = { readProfile: fakeReader(() => ({ trades: [
    { code: 'doors', quote: 'Doors & windows' },
    { code: 'fire_fighting', quote: 'Plumbing and sanitary installation' },   // not a printed line
  ] })) };
  const ev = await readDocForTrades({ path: 'p', name: 'p.pdf', kind: 'profile', photo_text: modelReadText('profile', lines) }, deps);
  assertEquals([ev.trades.map((t) => t.code), ev.vision_held], [['doors'], undefined]);
});
Deno.test('the profile reading asks for printed lines verbatim, never from a certificate or letter', async () => {
  const LX = await import('./licence_extract.ts');
  assert(/copied EXACTLY as printed/.test(LX.SYS_PROFILE) && /never from a certificate, a letter of recommendation/.test(LX.SYS_PROFILE));
  assertEquals(LX.profileExtractRequest({ images: [] }, null).sys, LX.SYS_PROFILE);
});
