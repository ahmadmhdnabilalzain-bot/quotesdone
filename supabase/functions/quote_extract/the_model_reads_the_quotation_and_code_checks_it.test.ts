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
import { checkerReading, readFigure } from './model_reading.ts';
import { statedPrice } from '../_shared/stated_price.ts';
import { workingFromProposal } from '../supplier_api/quote_review/working.ts';
import { submitPayload } from '../supplier_api/quote_review_flow/submit.ts';
import { reviewQuotation, type SafeInquiry } from '../supplier_api/quote_review.ts';

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
  // 12 Nov 2026 (review of #1981, D4): the question names both figures that may be wrong
  assertMatch(vat.warnings![0], /We read VAT as AED 600, which is not 5% of your price before VAT of AED 10,000\. Which is right: the VAT or the price\?/);
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

// ── Review of #1981 (12 Nov 2026), items D1, D2, D4, D7 and the checker gaps. Inputs are REAL proposalFromModel readings
// of labelled stand-in model answers; what is STORED is computed by the same statedPrice call submit_quote makes, from the
// payload each door sends: the portal form (QuoteForm.tsx onFile + buildPayload: amount = total ?? amount, the stated VAT
// basis, subtotal and VAT amount, the ex-VAT box blank) and the quotation thread (submitPayload).
const INQ = { id: 'zz', job_no: '1', category: 'joinery', emirate: 'Dubai', spec: null, boq_rows: [], boq_withheld: false, concluded: false, revealed: false } as unknown as SafeInquiry;
function stored(p: ReturnType<typeof proposalFromModel> & { total?: number }) {
  const amt = p.total != null ? p.total : p.amount;
  const vt = ['exclusive', 'inclusive', 'not_registered'].includes(String(p.vat_treatment)) ? String(p.vat_treatment) : null;
  const form = amt == null ? null : statedPrice({ amount: amt, subtotal: p.subtotal, vat_amount: p.vat_amount, text: '', stated: vt, price_ex_vat: null }).price_ex_vat;
  const w = workingFromProposal(p); const body = submitPayload(INQ, { original_file_path: null, original_file_name: null }, w, reviewQuotation(INQ, w));
  const thread = body.amount == null ? null : statedPrice({ amount: Number(body.amount), subtotal: (body.subtotal as number) ?? null, vat_amount: (body.vat_amount as number) ?? null, text: '',
    stated: (body.vat_treatment as string) ?? null, price_ex_vat: (body.price_ex_vat as number) ?? null }).price_ex_vat;
  return { form, thread };
}
const LINE = [{ description: 'Wardrobes', qty: '1 lot', amount: 9000 }];

// main of this branch (cd7a00857): the form stored 8,550 (D2) and 9,450 (D4); the USD reading kept amount 9,000 (D1).
Deno.test('the three VAT cases and a USD quotation: what each door stores is the price before VAT, never 5% off, never USD as AED', () => {
  const incl = proposalFromModel(MODEL({ total: 9450, vat_amount: 450, vat_treatment: 'inclusive', line_items: LINE }), gen);
  assertEquals([incl.amount, incl.total, incl.price_ex_vat, stored(incl)], [9000, 9450, 9000, { form: 9000, thread: 9000 }]);
  const excl = proposalFromModel(MODEL({ total: 9450, vat_amount: 450, vat_treatment: 'exclusive', line_items: LINE }), gen);   // VAT on top, no subtotal
  assertEquals([excl.amount, excl.subtotal, excl.price_ex_vat, stored(excl)], [9000, 9000, 9000, { form: 9000, thread: 9000 }]);
  assertEquals(checkReading(excl, '', null).warnings, undefined, 'consistent: nothing to ask');
  const none = proposalFromModel(MODEL({ total: 9000, vat_treatment: '', line_items: LINE }), gen);   // VAT not stated
  assertEquals([none.amount, none.price_ex_vat, none.vat_treatment, stored(none).form], [9000, null, 'not_stated', null], 'no basis: no price is fixed; the review asks the VAT basis');
  const usd = checkReading(proposalFromModel(MODEL({ currency: 'USD', total: 9000, vat_treatment: 'not_registered', line_items: LINE }), gen), '', null);
  assertEquals([usd.review_reason, usd.amount, usd.price_ex_vat, usd.line_items[0].amount, stored(usd).form], ['foreign_currency', null, null, null, null]);
  assertMatch(usd.warnings!.join(' '), /priced in USD\. Customers compare quotations in AED: please type your AED total\./);
});

Deno.test('VAT on top with a wrong figure: the question names the total and the VAT, not the VAT alone (D4)', () => {
  const p = checkReading(proposalFromModel(MODEL({ total: 9000, vat_amount: 450, vat_treatment: 'exclusive', line_items: [{ description: 'Works', qty: '1 lot', amount: 8550 }] }), gen), '', null);
  assertMatch(p.warnings!.join(' '), /total including VAT as AED 9,000 and the VAT as AED 450\. That makes your price before VAT AED 8,550, but 5% of AED 8,550 is AED 427\.5\. Which is right: the total or the VAT\?/);
});

// main of this branch: "12.000" -> 12 silently; "١٢٬٠٠٠", "12,000/-", 0 and negatives -> null silently; 1e9 accepted; 0.99 unasked.
Deno.test('a figure is read exactly or put to the supplier: never guessed, dropped or accepted when absurd', () => {
  assertEquals(['12,000', '12 000', '١٢٬٠٠٠', '12,000/-', 'AED 12,000.50', 12000].map((v) => readFigure(v)),
    [{ value: 12000, doubt: null }, { value: 12000, doubt: null }, { value: 12000, doubt: null }, { value: 12000, doubt: null }, { value: 12000.5, doubt: null }, { value: 12000, doubt: null }]);
  for (const v of ['12.000', '1,2', 'abc', '-500', 0, -5]) assertEquals(readFigure(v).value, null, String(v));
  for (const [v, re] of [['12.000', /We could not read your total \("12\.000"\) as an amount\. Please type it\./], [0, /your total \("0"\)/], ['-500', /your total \("-500"\)/],
    [1e9, /We read your total as AED 1,000,000,000, which is unusually large for a quotation\. Is that right\?/]] as const) {
    const p = checkReading(proposalFromModel(MODEL({ total: v, vat_treatment: 'not_registered' }), gen), '', null);
    assertMatch(p.warnings!.join(' '), re, String(v));
  }
  const off = checkReading(proposalFromModel(MODEL({ total: 9450.99, subtotal: 9000, vat_amount: 450, vat_treatment: 'exclusive', line_items: LINE }), gen), '', null);
  assertMatch(off.warnings!.join(' '), /AED 9,000 plus VAT of AED 450 is not the total of AED 9,450\.99/, 'a 0.99 AED gap is asked (sums agree to 5 fils)');
});

Deno.test('options whose totals include VAT raise no false VAT question (D7)', () => {
  const p = checkReading(proposalFromModel(MODEL({ total: 12600, vat_amount: 600, vat_treatment: 'inclusive', options: [{ label: 'A', total: 12600 }, { label: 'B', total: 9975 }] }), gen), '', null);
  assert(!p.warnings!.some((w) => /VAT/.test(w)), JSON.stringify(p.warnings));
});


// review D7: on cd7a00857 the checker read an e-mail body through doc_read's CSV cells, so its figures were filtered out and
// an advance taken for the total of a body with no lines was asked nothing.
Deno.test('an e-mail body is checked too: an advance taken for the total is put to the supplier', async () => {
  const body = 'Dear Sir, for the gypsum works our total is AED 10,500. Payment terms: Advance 50%: 5,250, balance on completion.';
  const b64 = btoa(String.fromCharCode(...enc(body)));
  const rd = await readDocument(enc(body), 'quotation-email.txt', 'text/plain');
  const text = documentText(b64, 'quotation-email.txt', 'text/plain', rd);
  const p = checkReading(proposalFromModel(MODEL({ total: 5250, vat_treatment: 'not_registered' }), gen), text, checkerReading(b64, 'quotation-email.txt', 'text/plain', text, rd));
  assertMatch(p.warnings!.join(' '), /We read your total as AED 5,250 excluding VAT, but your file also shows AED 10,500\. Is AED 5,250 right\?/);
});
