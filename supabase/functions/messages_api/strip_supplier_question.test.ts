// strip_supplier_question.test.ts — what a customer reads of a supplier's clarifying question before the reveal (13 Nov
// 2026). The coordinator's ruling: a manufacturer's brand PASSES in a question (the customer must be able to answer "Do you
// accept Grohe or Hansgrohe?"); the asking supplier's own name, contacts and places below the emirate do not. The source
// check catches the door going back to stripContact (mutant M4 of the review survived 93 tests).
// deno test --no-lock supabase/functions/messages_api/strip_supplier_question.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { stripSupplierQuestion } from './strip_contact.ts';

const NAME = 'ZZ DEMO Falcon Trading LLC';
Deno.test('brands pass; the supplier\'s own name, contacts and the place below the emirate do not', () => {
  for (const q of ['Do you accept Grohe or Hansgrohe?', 'Is Jotun Fenomastic acceptable, or do you need Dulux?', 'Daikin FTKF50 or Mitsubishi MSZ-LN?']) assertEquals(stripSupplierQuestion(q, [NAME]), q);
  const out = stripSupplierQuestion('Can we use Falcon premium paint? Call 050 123 4567 or mail rashid@falcon.example.invalid. Is the villa in Al Barsha 2?', [NAME]);
  for (const gone of ['Falcon', '4567', 'rashid', 'Barsha']) assert(!out.includes(gone), out);
  assert(out.includes('premium paint') && out.includes('Dubai'), out);
});
Deno.test('clarify_ask runs stripSupplierQuestion, not the answer scrub', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  const ask = src.slice(src.indexOf("action === 'clarify_ask'"), src.indexOf("action === 'clarify_ask'") + 600);
  assert(/stripSupplierQuestion\(b\.text, \[supLead\.company_name\]\)/.test(ask), 'clarify_ask must use stripSupplierQuestion');
});
