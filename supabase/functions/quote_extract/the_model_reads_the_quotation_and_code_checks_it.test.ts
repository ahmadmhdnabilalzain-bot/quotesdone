// THE MODEL READS THE QUOTATION; CODE CHECKS IT (sales_engineer, 12 Nov 2026; founder rulings 1663, 1664, 1666; LLM-first
// audit A2). Drives ./model_reading.ts with LABELLED STAND-IN model answers (ZZ DEMO: no model is called) and the REAL code
// money reader (quote_from_document.ts) as the checker, on the audit's examples. What each case proves:
//   * what the model read is what the supplier is shown: code never replaces a figure, it only asks;
//   * a disagreement (options, lines vs total, VAT, a second total in the file) becomes a plain-English question;
//   * a figure missing from the text layer is a note for our record, never a question and never a block.
// On origin/main 4b7091f08 this module does not exist; the same documents run through main's code-first reader
// (quoteFromExtracted, which quote_extract returned without asking the model) are recorded beside each case.
//   deno test --no-lock --node-modules-dir=none supabase/functions/quote_extract/the_model_reads_the_quotation_and_code_checks_it.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { readDocument } from '../_shared/doc_read/index.ts';
import { checkReading, documentText, figuresIn, proposalFromModel, type ModelAnswer } from './model_reading.ts';
import { quoteFromExtracted } from './quote_from_document.ts';

const gen = (v: unknown) => (v == null ? '' : String(v));
const enc = (s: string) => new TextEncoder().encode(s);
/** The file as quote_extract sees it: doc_read's transcription and the code money reader's reading of it. */
async function file(text: string, name = 'ZZ-DEMO-quotation.txt', mime = 'text/plain') {
  const rd = await readDocument(enc(text), name, mime);
  assert(rd.ok, 'doc_read opens the fixture');
  // what quote_extract gives the model and the checks: a plain-text body as written, any other file as doc_read's transcription
  return { text: documentText(btoa(String.fromCharCode(...enc(text))), name, mime, rd), code: quoteFromExtracted(rd, ['ZZ DEMO Quoting LLC']) };
}
// A stand-in model answer, labelled as one, with the fields quote_extract's SYS asks for.
const MODEL = (o: ModelAnswer): ModelAnswer => ({ is_quotation: true, currency: 'AED', confidence: 'high', notes: 'ZZ DEMO stand-in model answer', ...o });

Deno.test('a clean quotation: the model\'s figures stand, the arithmetic agrees, nothing is asked', async () => {
  const f = await file('ZZ DEMO Quoting LLC\nQuotation for RFQ-164810\nMDF wardrobe 18mm  4 no  2,000  8,000\nInstallation  1 lot  1,000  1,000\nSubtotal AED 9,000\nVAT 5% AED 450\nGrand Total AED 9,450\nValidity 30 days');
  const p = checkReading(proposalFromModel(MODEL({ total: 9450, subtotal: 9000, vat_amount: 450, vat_treatment: 'exclusive', request_reference: 'RFQ-164810',
    line_items: [{ description: 'MDF wardrobe 18mm', qty: '4 no', amount: 8000 }, { description: 'Installation', qty: '1 lot', amount: 1000 }], validity: '30 days' }), gen), f.text, f.code);
  assertEquals([p.is_quotation, p.amount, p.price_ex_vat, p.vat_amount, p.total_incl_vat, p.vat_treatment, p.request_reference], [true, 9000, 9000, 450, 9450, 'exclusive', 'RFQ-164810']);
  assertEquals(p.warnings, undefined, 'nothing to confirm');
  assertEquals(p.check_notes, []);
});

Deno.test('Option A 12,000 / Option B 9,500: both totals are put to the supplier, neither is chosen by code', async () => {
  const f = await file('Quotation\nOption A - imported marble\nMarble supply and fix  1 lot  12,000\nOption A total AED 12,000\nOption B - local granite\nGranite supply and fix  1 lot  9,500\nOption B total AED 9,500');
  const p = checkReading(proposalFromModel(MODEL({ total: 12000, options: [{ label: 'Option A', total: 12000 }, { label: 'Option B', total: 9500 }],
    line_items: [{ description: 'Marble supply and fix', qty: '1 lot', amount: 12000, option: 1 }, { description: 'Granite supply and fix', qty: '1 lot', amount: 9500, option: 2 }] }), gen), f.text, f.code);
  assertEquals([p.amount, p.price_ex_vat, p.option_totals], [12000, null, { '1': 12000, '2': 9500 }]);
  assertEquals(p.options.map((o) => o.amount), [12000, 9500]);
  assert(p.warnings?.length, 'the options are put to the supplier');
  assertMatch(p.warnings![0], /2 options: option 1 AED 12,000 and option 2 AED 9,500\. Each is sent to the customer as its own quotation\. Is that right\?/);
});

Deno.test('"Advance 50%: 5,250" under the total: a deposit read as the total is caught by the lines and put to the supplier', async () => {
  const doc = 'Quotation\nGypsum ceiling 100 m2  60  6,000\nPartition walls 50 m2  90  4,500\nTotal AED 10,500\nPayment terms: Advance 50%: 5,250, balance on completion';
  const f = await file(doc);
  // the model reads the price: nothing to ask
  const right = checkReading(proposalFromModel(MODEL({ total: 10500, vat_treatment: 'not_registered', payment_terms: 'Advance 50%: 5,250, balance on completion',
    line_items: [{ description: 'Gypsum ceiling', qty: '100 m2', amount: 6000 }, { description: 'Partition walls', qty: '50 m2', amount: 4500 }] }), gen), f.text, f.code);
  assertEquals([right.amount, right.warnings], [10500, undefined]);
  // had it taken the advance for the total, the supplier would be asked; the figure is not silently "corrected" by code
  const wrong = checkReading(proposalFromModel(MODEL({ total: 5250, vat_treatment: 'not_registered',
    line_items: [{ description: 'Gypsum ceiling', qty: '100 m2', amount: 6000 }, { description: 'Partition walls', qty: '50 m2', amount: 4500 }] }), gen), f.text, f.code);
  assertEquals(wrong.amount, 5250, 'code never replaces the model\'s figure');
  assertMatch(wrong.warnings!.join(' '), /Your lines add up to AED 10,500, but we read your total before VAT as AED 5,250\. Which is right\?/);
});

Deno.test('the code money reader is the checker: a total the file prints that the model did not read is put to the supplier', async () => {
  const f = await file('Description,Qty,Unit,Rate,Amount\nMDF wardrobe 18mm,4,no,2000,8000\nInstallation,1,lot,1000,1000\nSubtotal,,,,9000\nVAT 5%,,,,450\nGrand Total AED,,,,9450\n', 'ZZ-DEMO-Q.csv', 'text/csv');
  assertEquals([f.code.amount, f.code.total_incl_vat], [9000, 9450], 'the corpus-held reader reads this file exactly');
  // a stand-in model that missed the installation line
  const p = checkReading(proposalFromModel(MODEL({ total: 8000, vat_treatment: 'not_registered', line_items: [{ description: 'MDF wardrobe 18mm', qty: '4 no', amount: 8000 }] }), gen), f.text, f.code);
  assertEquals(p.amount, 8000, 'the model\'s figure is not replaced');
  assertMatch(p.warnings![0], /We read your total as AED 8,000 excluding VAT, but your file also shows AED 9,000\. Is AED 8,000 right\?/);
  // a plain-text body the code reader misreads (main read "AED 9,450" as AED 9) raises no question about a figure never written
  const body = await file('Grand Total AED 9,450 for the wardrobes, installation included.');
  const q = checkReading(proposalFromModel(MODEL({ total: 9450, vat_treatment: 'inclusive', vat_amount: 450 }), gen), body.text, body.code);
  assertEquals(q.warnings, undefined);
});

Deno.test('VAT that is not 5% of the price, and a subtotal + VAT that is not the total, are put to the supplier', () => {
  const vat = checkReading(proposalFromModel(MODEL({ total: 10600, subtotal: 10000, vat_amount: 600, vat_treatment: 'exclusive' }), gen), '', null);
  assertMatch(vat.warnings![0], /We read VAT as AED 600, which is not 5% of AED 10,000\. Please check the VAT\./);
  const sum = checkReading(proposalFromModel(MODEL({ total: 10600, subtotal: 10000, vat_amount: 500, vat_treatment: 'exclusive' }), gen), '', null);
  assertMatch(sum.warnings![0], /AED 10,000 plus VAT of AED 500 is not the total of AED 10,600 we read\. Please check the total\./);
});

Deno.test('a figure the text layer does not show is a NOTE for our record, never a question and never a block', () => {
  // a PDF text layer that dropped characters (the founder's licence lost its Arabic letters, 12 Nov 2026)
  const p = checkReading(proposalFromModel(MODEL({ total: 8400, vat_treatment: 'not_registered', line_items: [{ description: 'Painting', qty: '1 lot', amount: 8400 }] }), gen), 'Quotation\nPainting works  1 lot\nTotal AED', null);
  assertEquals([p.amount, p.warnings], [8400, undefined], 'no question, nothing blocked');
  assertEquals(p.check_notes.length, 1);
  assertMatch(p.check_notes[0], /not in the file's text layer.*note, not a block/);
  assertEquals(figuresIn('Total AED 12,450.00 and ١٢٣'), [12450, 123]);
});

Deno.test('what the model reads as no quotation is not one, whatever figure it holds; another currency is not read as AED', () => {
  const callout = checkReading(proposalFromModel({ is_quotation: false, not_a_quotation_reason: 'a site-visit arrangement with a call-out charge', notes: 'ZZ DEMO stand-in model answer' }, gen),
    'Our minimum call-out charge is AED 150, we will visit on Sunday.', null);
  assertEquals([callout.is_quotation, callout.amount, callout.warnings], [false, null, undefined]);
  const usd = proposalFromModel(MODEL({ currency: 'USD', total: 3000, vat_treatment: 'not_registered' }), gen);
  assertEquals(usd.review_reason, 'foreign_currency');
  assertEquals(proposalFromModel(MODEL({ currency: 'Dhs', total: 3000, vat_treatment: 'not_registered' }), gen).review_reason, undefined);
});

Deno.test('a stated discount: the price compared is after the discount, before VAT (rulings 1207/1208), as the shared helper computes it', () => {
  const p = checkReading(proposalFromModel(MODEL({ total: 1785, gross_amount: 2000, discount_amount: 300, subtotal: 1700, vat_amount: 85, vat_treatment: 'exclusive',
    line_items: [{ description: 'Cabinet', qty: '1 no', amount: 2000 }] }), gen), '', null);
  assertEquals([p.amount, p.price_ex_vat, p.gross_amount, p.discount_amount, p.vat_amount], [1700, 1700, 2000, 300, 85]);
  assertEquals(p.warnings, undefined, 'lines at the price before the discount agree');
});

// main (measured 12 Nov 2026): quote_extract priced this body by code, without the model, at AED 9 (doc_read split "9,450"
// at its comma as a CSV cell), and the e-mail route submitted it to the supplier's open request.
Deno.test('an e-mail body reaches the model as written: "Grand Total AED 9,450" is not cut at its thousands comma', async () => {
  const body = 'Dear Sir, our price for the wardrobes is as follows.\nGrand Total AED 9,450 including VAT. Validity 30 days.';
  const rd = await readDocument(enc(body), 'quotation-email.txt', 'text/plain');
  const t = documentText(btoa(String.fromCharCode(...enc(body))), 'quotation-email.txt', 'text/plain', rd);
  assertEquals(t, body);
  assert(figuresIn(t).includes(9450));
  assert(!documentText(null, 'q.csv', 'text/csv', rd).includes('AED 9,450'), 'the CSV transcription is what main gave its reader');
});
