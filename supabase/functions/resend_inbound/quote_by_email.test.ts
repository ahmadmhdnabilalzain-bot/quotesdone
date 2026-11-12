// A supplier's quotation sent by e-mail reaches his request (customer_support, 10 Nov 2026; supplier follow-up #1909
// item 1). Since 12 Nov 2026 (sales_engineer; founder rulings 1663/1664, LLM-first audit A2) WHAT a mail is, and its figures,
// are what the MODEL reads: `read` here is a LABELLED STAND-IN for supplier_api email_quote_read (no model is called), and
// each case records what origin/main 4b7091f08 did with the same mail, measured by running main's own quoteByEmail with
// main's code reader (readQuotationFile). Stubbed database/portal doors; ZZ DEMO names, example.invalid addresses.
//   deno test --node-modules-dir=none supabase/functions/resend_inbound/quote_by_email.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { chooseRequest, isQuotation, messageIdsIn, notificationIdsIn, quoteByEmail, replyFor, requestNumbersIn, verifiedSender,
  MAX_READS, type Lead, type MailFile, type OpenRequest, type QuoteMailDeps, type Reading } from './quote_by_email.ts';
import type { EmailQuoteInput, EmailQuoteResult } from '../supplier_api/email_quote.ts';

const A: OpenRequest = { id: 'aaaaaaaa-0000-4000-8000-000000000001', rfq_no: 164810, category: 'Joinery', emirate: 'Dubai' };
const B: OpenRequest = { id: 'bbbbbbbb-0000-4000-8000-000000000002', rfq_no: 164811, category: 'Painting', emirate: 'Sharjah' };
const LEAD: Lead = { id: 7, company_name: 'ZZ DEMO Quoting LLC', claimed_by: 'quotes@zz-demo-quoting.example.invalid', email: 'info@zz-demo-quoting.example.invalid' };
const enc = (s: string) => new TextEncoder().encode(s);
const QUOTE_CSV = 'Description,Qty,Unit,Rate,Amount\nMDF wardrobe 18mm,4,no,2000,8000\nInstallation,1,lot,1000,1000\nSubtotal,,,,9000\nVAT 5%,,,,450\nGrand Total AED,,,,9450\n';
const PROFILE_TXT = 'ZZ DEMO Quoting LLC company profile.\nEstablished in Dubai. We deliver joinery, fit-out and painting for villas, offices and retail.\nOur team of forty craftsmen serves all seven emirates.\n';
const CALLOUT = 'Dear QuotesDone, our minimum call-out charge is AED 150, we will visit the site on Sunday to measure. Regards, ZZ DEMO Quoting LLC.';
const INVOICE_CSV = 'TAX INVOICE INV-2026-0091 (job 77120)\nDescription,Qty,Unit,Rate,Amount\nKitchen cabinets,1,lot,6000,6000\nVAT 5%,,,,300\nTotal AED,,,,6300\n';

Deno.test('a request number is read only where the supplier wrote one, never from a price', () => {
  assertEquals(requestNumbersIn('Re: Quotation for RFQ-164810', 'Total AED 9,450 for 4 wardrobes'), ['164810']);
  assertEquals(requestNumbersIn('Our quote', 'Job No: 164811 and request #164810'), ['164811', '164810']);
  assertEquals(requestNumbersIn('Quotation', 'Total 164810 AED, 25 days'), []);
  assertEquals(notificationIdsIn('<qd-notif-5512.1731230000000@quotesdone.com>', null), [5512]);
  assertEquals(messageIdsIn('<0100abcd-ef@email.amazonses.com> <qd-notif-9.1@quotesdone.com>'), ['0100abcd-ef', 'qd-notif-9.1']);
});

Deno.test('the request is the threaded one, the named one or the only open one; two candidates is a question', () => {
  assertEquals(chooseRequest([A, B], [B.id], []), { kind: 'one', request: B, by: 'thread' });
  assertEquals(chooseRequest([A, B], [], ['164810']), { kind: 'one', request: A, by: 'reference' });
  assertEquals(chooseRequest([A], [], []), { kind: 'one', request: A, by: 'only_open' });
  assertEquals(chooseRequest([A, B], [], []), { kind: 'ask', candidates: [A, B], why: 'several_open' });
  assertEquals(chooseRequest([A, B], [], ['164810', '164811']), { kind: 'ask', candidates: [A, B], why: 'several_named' });
  assertEquals(chooseRequest([A], [], ['999999']), { kind: 'ask', candidates: [A], why: 'named_not_open' });
  assertEquals(chooseRequest([], [], []), { kind: 'none' });
});

Deno.test('only the sign-in address (or the listed one, proven) on an authenticated domain is a verified sender', () => {
  assert(verifiedSender(LEAD, LEAD.claimed_by!, true, false));
  assert(!verifiedSender(LEAD, LEAD.claimed_by!, false, false), 'the domain did not authenticate');
  assert(!verifiedSender(LEAD, LEAD.email!, true, false), 'the listed address was never proven');
  assert(verifiedSender(LEAD, LEAD.email!, true, true));
  assert(!verifiedSender({ ...LEAD, claimed_by: null }, LEAD.email!, true, true), 'an unclaimed listing cannot quote');
});


// THE STAND-IN MODEL (labelled; quote_extract's model is not called): what it read in each candidate, by file name.
const PRICED = { amount: 9000, currency: 'AED', line_items: [{ description: 'MDF wardrobe 18mm', qty: '4 no', amount: 8000 }, { description: 'Installation', qty: '1 lot', amount: 1000 }],
  lead_time: '', validity: '', payment_terms: '', warranty: '', scope: '', conditions: '', exclusions: '', notes: 'ZZ DEMO stand-in model answer', description_anonymized: '', masked_terms: [],
  confidence: 'low', method: 'document', subtotal: 9000, vat_amount: 450, total_incl_vat: 9450, vat_treatment: 'exclusive', price_ex_vat: 9000, trn: null,
  gross_amount: null, discount_amount: null, discount_label: null, options: [], option_totals: {} } as unknown as NonNullable<Reading['proposal']>;
const MODEL: Record<string, Reading> = {
  'Q-2026-114.csv': { verdict: 'quotation', proposal: PRICED, extracted_by_model: 'zz-demo/stand-in' },
  'quote.csv': { verdict: 'quotation', proposal: PRICED, extracted_by_model: 'zz-demo/stand-in' },
  'Q-cites-164811.pdf': { verdict: 'quotation', proposal: { ...PRICED, request_reference: 'RFQ-164811' }, extracted_by_model: 'zz-demo/stand-in' },
  'company profile.txt': { verdict: 'not_quotation', proposal: null },
  'INV-2026-0091.csv': { verdict: 'not_quotation', proposal: null },
};
const BODY: Record<string, Reading> = {
  [QUOTE_CSV]: { verdict: 'quotation', proposal: PRICED, extracted_by_model: 'zz-demo/stand-in' },
  [CALLOUT]: { verdict: 'not_quotation', proposal: null },
};
const standIn = (f: MailFile): Reading => (f.index === -1 ? BODY[new TextDecoder().decode(f.bytes)] : MODEL[f.filename]) ?? { verdict: 'not_quotation', proposal: null };

Deno.test('a mail is a quotation only when the model read it as one: a price does not make it one', () => {
  // The audit's call-out body and an invoice for another job carry a price; the code reader priced both on main.
  assert(!isQuotation({ verdict: 'not_quotation', proposal: PRICED }), 'a priced reading the model called no quotation is not one');
  assert(!isQuotation({ verdict: 'unread', proposal: null }));
  assert(isQuotation({ verdict: 'quotation', proposal: PRICED }));
});

// The route, end to end over stubbed doors.
function harness(over: Partial<{ open: OpenRequest[]; threaded: string[]; result: EmailQuoteResult; read: (f: MailFile) => Reading }> = {}) {
  const submits: EmailQuoteInput[] = []; const replies: { to: string; inquiry: string | null; subject: string; body: string }[] = []; const reads: string[] = [];
  const deps: QuoteMailDeps = {
    openRequests: () => Promise.resolve(over.open ?? [A]),
    threaded: () => Promise.resolve(over.threaded ?? []),
    listedProven: () => Promise.resolve(false),
    read: (f) => { reads.push(f.filename); return Promise.resolve((over.read ?? standIn)(f)); },
    submit: (i) => { submits.push(i); return Promise.resolve(over.result ?? { ok: true, stage: 'review', inquiry_id: i.inquiry_id, state: 'reviewing', amount: 9000, lines: 2, options: 1,
      warnings: ['We read your total as AED 9,000 excluding VAT, but your file also shows AED 9,450. Is AED 9,000 right?'] }); },
    reply: (_l, to, inquiry, m) => { replies.push({ to, inquiry, ...m }); return Promise.resolve(); },
  };
  return { deps, submits, replies, reads };
}
const file = (name: string, text: string, mime = 'text/csv', index = 0): MailFile => ({ index, filename: name, mime, bytes: enc(text) });
const mail = (o: Partial<{ from: string; subject: string; text: string; inReplyTo: string | null; senderAuth: boolean }> = {}) =>
  ({ from: LEAD.claimed_by!, subject: 'Re: New job request on QuotesDone', text: 'Please find our quotation attached.', inReplyTo: null, references: null, senderAuth: true, ...o });

// main: outcome 'submitted' and, when submit_quote accepted it, "It has been sent to the customer" (the reading unconfirmed).
Deno.test('an e-mailed quotation is placed for the supplier to confirm, with the model\'s reading; it is never sent to the customer from here', async () => {
  const h = harness();
  const out = await quoteByEmail(mail(), LEAD, [file('Q-2026-114.csv', QUOTE_CSV)], h.deps);
  assertEquals([out.outcome, out.taken, out.inquiry_id], ['to_confirm', [0], A.id]);
  assertEquals(h.submits.length, 1);
  assertEquals([h.submits[0].lead_id, h.submits[0].inquiry_id, h.submits[0].filename], [7, A.id, 'Q-2026-114.csv']);
  assertEquals(new TextDecoder().decode(Uint8Array.from(atob(h.submits[0].file_b64), (c) => c.charCodeAt(0))), QUOTE_CSV);
  assertEquals(h.submits[0].reading, { proposal: PRICED, extracted_by_model: 'zz-demo/stand-in' }, 'the reading goes with it: no second model call');
  const r = h.replies[0];
  assertEquals([r.to, r.inquiry], [LEAD.claimed_by, A.id]);
  assertMatch(r.subject, /Please confirm your quotation for RFQ-164810/);
  assertMatch(r.body, /read it: a total of AED 9,000 excluding VAT, 2 priced lines/);
  assertMatch(r.body, /Please check:\n1\. We read your total as AED 9,000 excluding VAT, but your file also shows AED 9,450\. Is AED 9,000 right\?/);
  assertMatch(r.body, /It has NOT been sent to the customer yet\. Please open the request in the supplier portal and check the figures we read; the same questions are waiting for your answer in the quotation thread there/);
  assertMatch(r.body, /Your Submit sends it/);
  assert(!/It has been sent to the customer/.test(r.body), 'never "sent to the customer" (main\'s words when submit_quote accepted it)');
  assertMatch(r.body, /quotesdone\.com\/portal/);
});

// main: NOT a quotation either: main's code reader did not price the audit's wording (nor four others, measured 12 Nov). The
// audit's example was wrong; this case is kept because what decides it now is the model, not the absence of a priced line.
Deno.test('the audit\'s call-out e-mail ("minimum call-out charge AED 150, we will visit Sunday") is not a quotation', async () => {
  const h = harness();
  const out = await quoteByEmail(mail({ text: CALLOUT }), LEAD, [], h.deps);
  assertEquals([out.outcome, out.taken, h.submits.length, h.replies.length], [null, [], 0, 0]);
  assertEquals(h.reads, ['quotation-email.txt'], 'the model read the body');
});

// main (measured): the code reader priced the invoice and submitted it to his one open request as his quotation.
Deno.test('an invoice for another job attached to a reply is not a quotation; the quotation beside it is the one used', async () => {
  const alone = harness();
  assertEquals((await quoteByEmail(mail(), LEAD, [file('INV-2026-0091.csv', INVOICE_CSV)], alone.deps)).outcome, null);
  assertEquals(alone.submits.length, 0);
  const both = harness();
  const out = await quoteByEmail(mail(), LEAD, [file('INV-2026-0091.csv', INVOICE_CSV, 'text/csv', 0), file('Q-2026-114.csv', QUOTE_CSV, 'text/csv', 1)], both.deps);
  assertEquals([out.outcome, out.taken, both.submits[0].filename], ['to_confirm', [1], 'Q-2026-114.csv']);
  assert(!/more than one quotation file/.test(both.replies[0].body), 'the invoice is not called a second quotation');
});

// main: the code reader decided; a model that did not answer could not leave a mail "unread" (a text file was priced by code).
Deno.test('no model answer: nothing is taken or priced by code, the files stay on the profile path, and he is told plainly once', async () => {
  const h = harness({ read: () => ({ verdict: 'unread', proposal: null }) });
  const out = await quoteByEmail(mail(), LEAD, [file('Q-2026-114.csv', QUOTE_CSV)], h.deps);
  assertEquals([out.outcome, out.taken, h.submits.length, out.inquiry_id], ['unread', [], 0, A.id]);
  // review D6: nothing retries yet, so nothing is promised
  assertMatch(h.replies[0].subject, /^We could not read your e-mail for RFQ-164810 yet$/);
  assertMatch(h.replies[0].body, /we could not read it yet\. Nothing has been sent to the customer\. If it is your quotation, please upload it on the request in the supplier portal, or e-mail it to us again/);
  assertMatch(h.replies[0].body, /"Q-2026-114\.csv"/);
  // a plain message whose body could not be read is left to email_triage: no reply from here
  const q = harness({ read: () => ({ verdict: 'unread', proposal: null }) });
  assertEquals([(await quoteByEmail(mail({ text: 'Thank you, we will visit on Sunday.' }), LEAD, [], q.deps)).outcome, q.replies.length], [null, 0]);
});

// main: read every attachment of every claimed supplier (free code). The model is not asked when nothing can be quoted.
Deno.test('no open request and no reply to our notice: nothing is read by the model', async () => {
  const h = harness({ open: [] });
  const out = await quoteByEmail(mail(), LEAD, [file('Q-2026-114.csv', QUOTE_CSV)], h.deps);
  assertEquals([out.outcome, h.reads.length, h.replies.length], [null, 0, 0]);
});

// main: 'ask' (two open requests, no number in the subject or body): the number printed in the file was not seen.
Deno.test('a request number the quotation itself prints (read by the model) chooses between his open requests', async () => {
  const h = harness({ open: [A, B] });
  const out = await quoteByEmail(mail(), LEAD, [file('Q-cites-164811.pdf', '%PDF-ZZ', 'application/pdf')], h.deps);
  assertEquals([out.outcome, out.inquiry_id], ['to_confirm', B.id]);
});

Deno.test('two open requests and no thread or number: the supplier is asked which, nothing is placed', async () => {
  const h = harness({ open: [A, B] });
  const out = await quoteByEmail(mail(), LEAD, [file('quote.csv', QUOTE_CSV)], h.deps);
  assertEquals([out.outcome, h.submits.length], ['ask', 0]);
  assertMatch(h.replies[0].body, /RFQ-164810 \(Joinery, Dubai\)/); assertMatch(h.replies[0].body, /RFQ-164811 \(Painting, Sharjah\)/);
  // a reply to the RFQ notice answers it
  const t = harness({ open: [A, B], threaded: [B.id] });
  assertEquals((await quoteByEmail(mail({ inReplyTo: '<qd-notif-77.1@quotesdone.com>' }), LEAD, [file('quote.csv', QUOTE_CSV)], t.deps)).inquiry_id, B.id);
});

Deno.test('a priced e-mail body the model reads as a quotation is placed for confirmation like a file', async () => {
  const h = harness();
  const out = await quoteByEmail(mail({ subject: 'Quotation RFQ-164810', text: QUOTE_CSV }), LEAD, [], h.deps);
  assertEquals([out.outcome, out.taken], ['to_confirm', []]);
  assertEquals(h.submits[0].mime, 'text/plain');
  assertMatch(h.replies[0].body, /NOT been sent to the customer/);
});

// review of #1981 D3 (cd7a00857: 7 model readings for an unauthenticated mail, and an 'unread' reply before any check) and
// N3 (62ba18032: no reply at all from this route, and the profile path then told him his files were added to his profile).
Deno.test('an unverified sender costs no model reading; with attachments he is told at his sign-in address to use the portal', async () => {
  for (const m of [mail({ senderAuth: false }), mail({ from: LEAD.email! })]) {
    for (const read of [standIn, () => ({ verdict: 'unread', proposal: null }) as Reading]) {
      const h = harness({ read });
      const six = Array.from({ length: 6 }, (_, i) => file('quote' + i + '.csv', QUOTE_CSV, 'text/csv', i));
      const out = await quoteByEmail(m, LEAD, six, h.deps);
      assertEquals([out.outcome, out.taken, h.reads.length, h.submits.length, h.replies.map((r) => r.to)], ['unverified', [], 0, 0, [LEAD.claimed_by]]);
      assertMatch(h.replies[0].body, /we have not read it and nothing has been sent to the customer/);
    }
    const plain = harness();
    assertEquals([(await quoteByEmail(m, LEAD, [], plain.deps)).outcome, plain.replies.length], [null, 0], 'a plain message: no reply from this route');
  }
});

// review N3: the quotation was the fifth of six files; 62ba18032 read three, found none and said nothing.
Deno.test('more files than are read and no quotation among them: he is told which were read and asked to upload it', async () => {
  const h = harness({ read: () => ({ verdict: 'not_quotation', proposal: null }) });
  const six = Array.from({ length: 6 }, (_, i) => file('doc' + i + '.pdf', '%PDF-ZZ', 'application/pdf', i));
  const out = await quoteByEmail(mail(), LEAD, six, h.deps);
  assertEquals([out.outcome, out.taken, h.submits.length], ['not_all_read', [], 0]);
  assertMatch(h.replies[0].subject, /^We read only the first 3 attachments of your e-mail$/);
  assertMatch(h.replies[0].body, /Your e-mail had 6 attachments\. We read only the first 3 \("doc0\.pdf", "doc1\.pdf", "doc2\.pdf"\), and none of them is a quotation\./);
});

Deno.test('a mail costs at most MAX_READS model readings (three files and the body, in one round)', async () => {
  const h = harness({ read: () => ({ verdict: 'not_quotation', proposal: null }) });
  const six = Array.from({ length: 6 }, (_, i) => file('doc' + i + '.pdf', '%PDF-ZZ', 'application/pdf', i));
  await quoteByEmail(mail(), LEAD, six, h.deps);
  assertEquals(MAX_READS, 4);
  assertEquals(h.reads, ['doc0.pdf', 'doc1.pdf', 'doc2.pdf', 'quotation-email.txt']);
});

// review D7 (cd7a00857: a bare number that is not one of his requests, e.g. his own quote number, made it 'ask').
Deno.test('a reference the quotation prints that is not one of his requests is ignored, not turned into a question', async () => {
  const h = harness({ read: (f) => (f.index === -1 ? { verdict: 'not_quotation', proposal: null } : { verdict: 'quotation', proposal: { ...PRICED, request_reference: 'Q-2026-0114' }, extracted_by_model: 'zz-demo/stand-in' }) });
  const out = await quoteByEmail(mail(), LEAD, [file('Q-2026-0114.pdf', '%PDF-ZZ', 'application/pdf')], h.deps);
  assertEquals([out.outcome, out.inquiry_id], ['to_confirm', A.id]);
});

// review D1 (cd7a00857: the reply read "a total of AED 9,000 excluding VAT" for a USD quotation).
Deno.test('a quotation priced in another currency: he is asked for his AED total, in main\'s own words', () => {
  const r = replyFor(LEAD, { kind: 'to_confirm', request: A, file: 'q.pdf', extra: [], result: { ok: false, stage: 'extract', code: 'quote_total_ambiguous', message: null, review_reason: 'foreign_currency' } });
  assertMatch(r.body, /It is priced in a currency other than AED, and customers compare quotations in AED\. Please open the request in the supplier portal and type your AED total\./);
  assert(!/AED \d/.test(r.body), 'no figure is quoted back as AED');
});

Deno.test('a profile document and plain correspondence stay on the profile path', async () => {
  const h = harness();
  const out = await quoteByEmail(mail({ text: 'Thank you, we will send the documents tomorrow.' }), LEAD, [file('company profile.txt', PROFILE_TXT, 'text/plain')], h.deps);
  assertEquals([out.outcome, out.taken, h.submits.length, h.replies.length], [null, [], 0, 0]);
});

Deno.test('every reply is English and names what happened', () => {
  for (const o of [{ kind: 'unverified' as const }, { kind: 'none' as const }, { kind: 'ask' as const, choice: { kind: 'ask' as const, candidates: [A, B], why: 'several_open' as const } },
    { kind: 'unread' as const, request: A, files: ['q.pdf'] },
    { kind: 'to_confirm' as const, request: A, file: 'q.pdf', extra: ['q2.pdf'], result: { ok: false as const, stage: 'review' as const, code: 'review_closed', message: null } },
    { kind: 'to_confirm' as const, request: A, file: 'q.pdf', extra: [], result: { ok: true as const, stage: 'review' as const, inquiry_id: A.id, state: 'reviewing', amount: 12000, lines: 2, options: 2, warnings: ['We read 2 options.'] } }]) {
    const r = replyFor(LEAD, o);
    assert(!/[؀-ۿ]/.test(r.subject + r.body), 'suppliers are written in English only');
    assertMatch(r.body, /quotesdone\.com\/portal/);
    assert(!/It has been sent to the customer/.test(r.subject + r.body), 'no reply says a quotation went to the customer');
  }
});

// review D7 (cd7a00857 said nothing about it)
Deno.test('a file beside the quotation that could not be read is named in the reply', async () => {
  const h = harness({ read: (f) => (f.filename === 'drawing.pdf' ? { verdict: 'unread', proposal: null } : standIn(f)) });
  await quoteByEmail(mail(), LEAD, [file('Q-2026-114.csv', QUOTE_CSV, 'text/csv', 0), file('drawing.pdf', '%PDF-ZZ', 'application/pdf', 1)], h.deps);
  assertMatch(h.replies[0].body, /We could not read "drawing\.pdf" yet/);
});
