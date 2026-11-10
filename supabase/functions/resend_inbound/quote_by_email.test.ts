// A supplier's quotation sent by e-mail reaches his request (customer_support, 10 Nov 2026; supplier follow-up #1909
// item 1). Drives quote_by_email.ts with the REAL quotation reader (readQuotationFile: doc_read + quote_from_document)
// and stubbed database/portal doors. Every party is invented: ZZ DEMO names, example.invalid addresses.
//   deno test --node-modules-dir=none supabase/functions/resend_inbound/quote_by_email.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { readQuotationFile } from '../supplier_api/quote_review_flow/reading.ts';
import { chooseRequest, isQuotation, messageIdsIn, notificationIdsIn, quoteByEmail, replyFor, requestNumbersIn, verifiedSender,
  type Lead, type MailFile, type OpenRequest, type QuoteMailDeps } from './quote_by_email.ts';
import type { EmailQuoteInput, EmailQuoteResult } from '../supplier_api/email_quote.ts';

const A: OpenRequest = { id: 'aaaaaaaa-0000-4000-8000-000000000001', rfq_no: 164810, category: 'Joinery', emirate: 'Dubai' };
const B: OpenRequest = { id: 'bbbbbbbb-0000-4000-8000-000000000002', rfq_no: 164811, category: 'Painting', emirate: 'Sharjah' };
const LEAD: Lead = { id: 7, company_name: 'ZZ DEMO Quoting LLC', claimed_by: 'quotes@zz-demo-quoting.example.invalid', email: 'info@zz-demo-quoting.example.invalid' };
const enc = (s: string) => new TextEncoder().encode(s);
const QUOTE_CSV = 'Description,Qty,Unit,Rate,Amount\nMDF wardrobe 18mm,4,no,2000,8000\nInstallation,1,lot,1000,1000\nSubtotal,,,,9000\nVAT 5%,,,,450\nGrand Total AED,,,,9450\n';
const PROFILE_TXT = 'ZZ DEMO Quoting LLC company profile.\nEstablished in Dubai. We deliver joinery, fit-out and painting for villas, offices and retail.\nOur team of forty craftsmen serves all seven emirates.\n';

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

Deno.test('what a document IS is decided by the quotation reader, not by a word', async () => {
  const quote = await readQuotationFile(enc(QUOTE_CSV), 'Q-2026-114.csv', 'text/csv', [LEAD.company_name!]);
  const profile = await readQuotationFile(enc(PROFILE_TXT), 'quotation.txt', 'text/plain', [LEAD.company_name!]);
  assert(isQuotation({ proposal: quote.proposal, kind: quote.kind }, false), 'a priced file with a total is a quotation');
  assert(!isQuotation({ proposal: profile.proposal, kind: profile.kind }, true), 'a profile named "quotation" is still not one');
});

// The route, end to end over stubbed doors.
function harness(over: Partial<{ open: OpenRequest[]; threaded: string[]; result: EmailQuoteResult }> = {}) {
  const submits: EmailQuoteInput[] = []; const replies: { to: string; inquiry: string | null; subject: string; body: string }[] = [];
  const deps: QuoteMailDeps = {
    openRequests: () => Promise.resolve(over.open ?? [A]),
    threaded: () => Promise.resolve(over.threaded ?? []),
    listedProven: () => Promise.resolve(false),
    read: async (f, terms) => { const r = await readQuotationFile(f.bytes, f.filename, f.mime, terms); return { proposal: r.proposal, kind: r.kind }; },
    submit: (i) => { submits.push(i); return Promise.resolve(over.result ?? { ok: true, stage: 'submit', inquiry_id: i.inquiry_id, accepted: false, held: true,
      missing: [{ label_en: 'Line 1 (MDF wardrobe 18mm): the board brand and grade' }], message: null, code: 'spec_hold', amount: 9000, lines: 2, options: 1 }); },
    reply: (_l, to, inquiry, m) => { replies.push({ to, inquiry, ...m }); return Promise.resolve(); },
  };
  return { deps, submits, replies };
}
const file = (name: string, text: string, mime = 'text/csv', index = 0): MailFile => ({ index, filename: name, mime, bytes: enc(text) });
const mail = (o: Partial<{ from: string; subject: string; text: string; inReplyTo: string | null; senderAuth: boolean }> = {}) =>
  ({ from: LEAD.claimed_by!, subject: 'Re: New job request on QuotesDone', text: 'Please find our quotation attached.', inReplyTo: null, references: null, senderAuth: true, ...o });

Deno.test('a verified supplier\'s e-mailed quotation goes to the portal\'s own submit for his one open request, and he is told what is missing', async () => {
  const h = harness();
  const out = await quoteByEmail(mail(), LEAD, [file('Q-2026-114.csv', QUOTE_CSV)], h.deps);
  assertEquals([out.outcome, out.taken, out.inquiry_id], ['submitted', [0], A.id]);
  assertEquals(h.submits.length, 1);
  assertEquals([h.submits[0].lead_id, h.submits[0].inquiry_id, h.submits[0].filename], [7, A.id, 'Q-2026-114.csv']);
  assertEquals(new TextDecoder().decode(Uint8Array.from(atob(h.submits[0].file_b64), (c) => c.charCodeAt(0))), QUOTE_CSV);
  const r = h.replies[0];
  assertEquals([r.to, r.inquiry], [LEAD.claimed_by, A.id]);
  assertMatch(r.body, /RFQ-164810/); assertMatch(r.body, /on hold/); assertMatch(r.body, /board brand and grade/); assertMatch(r.body, /quotesdone\.com\/portal/);
  assert(!/profile/i.test(r.body), 'never "added to your profile"');
});

Deno.test('a priced e-mail body is a quotation too', async () => {
  const h = harness({ result: { ok: true, stage: 'submit', inquiry_id: A.id, accepted: true, held: false, missing: [], message: null, code: null, amount: 9000, lines: 2, options: 1 } });
  const out = await quoteByEmail(mail({ subject: 'Quotation RFQ-164810', text: QUOTE_CSV }), LEAD, [], h.deps);
  assertEquals([out.outcome, out.taken], ['submitted', []]);
  assertEquals(h.submits[0].mime, 'text/plain');
  assertMatch(h.replies[0].body, /sent to the customer/);
  assertMatch(h.replies[0].body, /AED 9,000 excluding VAT/);
});

Deno.test('two open requests and no thread or number: the supplier is asked which, nothing is submitted', async () => {
  const h = harness({ open: [A, B] });
  const out = await quoteByEmail(mail(), LEAD, [file('quote.csv', QUOTE_CSV)], h.deps);
  assertEquals([out.outcome, h.submits.length], ['ask', 0]);
  assertMatch(h.replies[0].body, /RFQ-164810 \(Joinery, Dubai\)/); assertMatch(h.replies[0].body, /RFQ-164811 \(Painting, Sharjah\)/);
  // a reply to the RFQ notice answers it
  const t = harness({ open: [A, B], threaded: [B.id] });
  assertEquals((await quoteByEmail(mail({ inReplyTo: '<qd-notif-77.1@quotesdone.com>' }), LEAD, [file('quote.csv', QUOTE_CSV)], t.deps)).inquiry_id, B.id);
});

Deno.test('a quotation from an unverified sender is never accepted: he is told to use the portal at the sign-in address', async () => {
  for (const m of [mail({ senderAuth: false }), mail({ from: LEAD.email! })]) {
    const h = harness();
    const out = await quoteByEmail(m, LEAD, [file('quote.csv', QUOTE_CSV)], h.deps);
    assertEquals([out.outcome, h.submits.length, h.replies[0].to], ['unverified', 0, LEAD.claimed_by]);
    assertMatch(h.replies[0].body, /Nothing has been sent to the customer/);
  }
});

Deno.test('a profile document and plain correspondence stay on the profile path', async () => {
  const h = harness();
  const out = await quoteByEmail(mail({ text: 'Thank you, we will send the documents tomorrow.' }), LEAD, [file('company profile.txt', PROFILE_TXT, 'text/plain')], h.deps);
  assertEquals([out.outcome, out.taken, h.submits.length, h.replies.length], [null, [], 0, 0]);
});

Deno.test('every reply is English and names what happened', () => {
  for (const o of [{ kind: 'unverified' as const }, { kind: 'none' as const }, { kind: 'ask' as const, choice: { kind: 'ask' as const, candidates: [A, B], why: 'several_open' as const } },
    { kind: 'submitted' as const, request: A, file: 'q.pdf', extra: ['q2.pdf'], result: { ok: false as const, stage: 'extract' as const, code: 'quote_total_ambiguous', message: null, review_reason: 'conflicting_totals' } }]) {
    const r = replyFor(LEAD, o);
    assert(!/[؀-ۿ]/.test(r.subject + r.body), 'suppliers are written in English only');
    assertMatch(r.body, /quotesdone\.com\/portal/);
  }
});
