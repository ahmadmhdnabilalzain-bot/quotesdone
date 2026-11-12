// The e-mailed quotation (customer_support, 10 Nov 2026; #1909 item 1; sales_engineer, 12 Nov 2026, LLM-first audit A2).
// email_quote_read asks the MODEL (quote_extract, a labelled stand-in here) what a candidate is; email_quote places the
// reading in the supplier's own quotation thread for him to confirm, and never calls submit_quote. On origin/main
// 4b7091f08 email_quote ran extract_quote then submit_quote with the code reader's figures, so a quotation whose review
// rules passed reached the customer unconfirmed. Doors are stubbed so nothing reaches a database. ZZ DEMO data only.
//   deno test --no-lock --node-modules-dir=none supabase/functions/supplier_api/email_quote.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { emailQuote, emailQuoteRead, type EmailQuoteDeps } from './email_quote.ts';
import type { ActionCtx } from './context.ts';
import { memoryReviewRepo } from './quote_review_memory_repo.ts';
import { choose, message, submit, upload, type ReviewDeps } from './quote_review_flow.ts';
import { checkReading, proposalFromModel } from '../quote_extract/model_reading.ts';
import { readFixture } from './review_reading.fixture.ts';
import { jobNo, type SafeInquiry } from './quote_review.ts';

const INQ = 'aaaaaaaa-0000-4000-8000-000000000001';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s });
const PROPOSAL = { amount: 9000, currency: 'AED', line_items: [{ description: 'MDF wardrobe 18mm', qty: '4 no', amount: 8000 }, { description: 'Installation', qty: '1 lot', amount: 1000 }],
  lead_time: '', validity: '', payment_terms: '', warranty: '', scope: '', conditions: '', exclusions: '', notes: 'ZZ DEMO stand-in model answer', description_anonymized: '', masked_terms: [],
  confidence: 'low', method: 'document', subtotal: 9000, vat_amount: 450, total_incl_vat: 9450, vat_treatment: 'exclusive', price_ex_vat: 9000, trn: null,
  gross_amount: null, discount_amount: null, discount_label: null, options: [], option_totals: {}, is_quotation: true, warnings: ['Your lines add up to AED 9,000. Is that right?'] };
const ROW = { id: INQ, rfq_no: 164810, category: 'Joinery', emirate: 'Dubai', summary: 'ZZ DEMO wardrobes', boq: null, spec: null };

function stub(over: Partial<{ extract: Record<string, unknown>; claimed: string | null; sanctioned: boolean; review: { ok: true; state: string } | { ok: false; code: string; message: string } }> = {}) {
  const seen: { action: string; email: string; body: Record<string, unknown> }[] = [];
  const extracts: Record<string, unknown>[] = []; const reviews: Parameters<EmailQuoteDeps['review']>[0][] = [];
  const deps: EmailQuoteDeps = {
    lead: (id) => Promise.resolve({ id, claimed_by: over.claimed === undefined ? 'Quotes@ZZ-Demo-Quoting.example.invalid' : over.claimed, company_name: 'ZZ DEMO Quoting LLC' }),
    sanctioned: () => Promise.resolve(!!over.sanctioned),
    inboxActions: (c: ActionCtx) => { seen.push({ action: c.action, email: c.email, body: c.body }); return Promise.resolve(J({ inquiries: [ROW] })); },
    safeInquiry: (row) => ({ ...row, id: String(row.id), job_no: String(row.rfq_no), boq_rows: [] }) as never,
    // THE STAND-IN MODEL: quote_extract's answer, labelled; no model is called.
    extract: (b) => { extracts.push(b); return Promise.resolve(over.extract ?? { ok: true, proposal: PROPOSAL, extracted_by_model: 'zz-demo/stand-in', is_quotation: true }); },
    review: (a) => { reviews.push(a); return Promise.resolve(over.review ?? { ok: true, state: 'reviewing' }); },
  };
  return { deps, seen, extracts, reviews };
}
const file = { file_b64: btoa('Description,Amount\nWardrobe,8000\n'), filename: 'q.csv', mime: 'text/csv' };
const input = { lead_id: 7, inquiry_id: INQ, ...file };

Deno.test('email_quote_read: what the model read decides; no answer is "unread", never a code price', async () => {
  const s = stub();
  const r = await emailQuoteRead({ lead_id: 7, ...file, requests: [{ job_no: '164810', category: 'Joinery' }] }, s.deps);
  assertEquals([r.verdict, (r as { extracted_by_model: string }).extracted_by_model], ['quotation', 'zz-demo/stand-in']);
  assertEquals(s.extracts[0].supplier_terms, ['ZZ DEMO Quoting LLC'], 'the supplier\'s name is masked by the reader');
  assertEquals(s.extracts[0].requests, [{ job_no: '164810', category: 'Joinery' }]);
  assertEquals(s.extracts[0].subject, { supplier_id: 7, email: 'quotes@zz-demo-quoting.example.invalid' }, 'the call names its subject');
  const no = await emailQuoteRead({ lead_id: 7, ...file }, stub({ extract: { ok: false, error: 'not_a_quotation', reason: 'a site-visit note', proposal: { amount: 150 } } }).deps);
  assertEquals([no.verdict, (no as { proposal: unknown }).proposal], ['not_quotation', null], 'a figure in a non-quotation is dropped');
  for (const e of [{ ok: false, error: 'model_unavailable', retryable: true }, { ok: false, error: 'unreadable_quotation' }, {}])
    assertEquals((await emailQuoteRead({ lead_id: 7, ...file }, stub({ extract: e }).deps)).verdict, 'unread');
  // the model said it is a quotation but it is priced in USD: still a quotation, the AED total is his to type
  const usd = await emailQuoteRead({ lead_id: 7, ...file }, stub({ extract: { ok: false, error: 'total_ambiguous', review_reason: 'foreign_currency', is_quotation: true, proposal: { ...PROPOSAL, amount: null } } }).deps);
  assertEquals([usd.verdict, (usd as { review_reason: string }).review_reason], ['quotation', 'foreign_currency']);
});

Deno.test('email_quote places the model\'s reading in his quotation thread and never submits it', async () => {
  const s = stub();
  const out = await emailQuote({ ...input, reading: { proposal: PROPOSAL as never, extracted_by_model: 'zz-demo/stand-in' } }, s.deps);
  assertEquals(s.extracts.length, 0, 'the reading resend_inbound has is used: no second model call');
  assertEquals(s.seen.map((x) => x.action), ['inbox'], 'nothing but the inbox: no extract_quote, no submit_quote');
  assertEquals(s.reviews.length, 1);
  assertEquals([s.reviews[0].inquiryId, s.reviews[0].lead.claimed_by, s.reviews[0].file], [INQ, 'quotes@zz-demo-quoting.example.invalid', { b64: file.file_b64, filename: 'q.csv', mime: 'text/csv' }]);
  assertEquals((s.reviews[0].proposal as { extracted_by_model?: string }).extracted_by_model, 'zz-demo/stand-in', 'the thread records which model read it');
  assertEquals(await s.reviews[0].inquiry(INQ).then((x) => x?.id), INQ, 'the thread reads the job through his inbox');
  assertEquals(out, { ok: true, stage: 'review', inquiry_id: INQ, state: 'reviewing', amount: 9000, lines: 2, options: 1, warnings: ['Your lines add up to AED 9,000. Is that right?'] });
});

Deno.test('without a reading it is read once by the model; what the model calls no quotation is never placed', async () => {
  const s = stub();
  assertEquals((await emailQuote(input, s.deps)).ok, true);
  assertEquals([s.extracts.length, s.reviews.length], [1, 1]);
  const n = stub({ extract: { ok: false, error: 'not_a_quotation' } });
  assertEquals(await emailQuote(input, n.deps), { ok: false, stage: 'extract', code: 'not_a_quotation', message: null, review_reason: null });
  assertEquals(n.reviews.length, 0);
  const u = stub({ extract: { ok: false, error: 'model_unavailable' } });
  assertEquals((await emailQuote(input, u.deps) as { code: string }).code, 'quote_read_delayed');
});

Deno.test('a thread that refuses (already submitted, job closed) comes back as it said', async () => {
  const s = stub({ review: { ok: false, code: 'review_closed', message: 'This conversation is closed.' } });
  assertEquals(await emailQuote({ ...input, reading: { proposal: PROPOSAL as never, extracted_by_model: null } }, s.deps), { ok: false, stage: 'review', code: 'review_closed', message: 'This conversation is closed.' });
});

Deno.test('no claimed account, a sanctioned one, or a job outside his inbox: nothing runs', async () => {
  for (const [o, code] of [[{ claimed: null }, 'no_company'], [{ sanctioned: true }, 'sanctioned']] as const) {
    const s = stub(o); const out = await emailQuote(input, s.deps);
    assertEquals([out.ok, (out as { code: string }).code, s.seen.length, s.extracts.length], [false, code, 0, 0]);
    assertEquals((await emailQuoteRead({ lead_id: 7, ...file }, s.deps)).verdict, 'refused');
    assertEquals(s.extracts.length, 0, 'no model call for a refused account');
  }
  const s = stub(); s.deps.inboxActions = () => Promise.resolve(J({ inquiries: [] }));
  const out = await emailQuote(input, s.deps);
  assertEquals([out.ok, out.stage, s.reviews.length], [false, 'job', 0]);
  assert(!s.extracts.length);
});

// THE THREAD ITSELF (quote_review_flow upload with the model's reading supplied, as actions/quote_review_chat.ts
// emailedQuotationThread wires it): the quotation waits for HIS Submit, and the model that read it is the reader recorded
// when he submits (quote_compare is then routed to another family, instruction ~891). On main the e-mailed quotation never
// entered the thread: it went straight to submit_quote, and a chat submit always recorded 'deterministic'.

// review of #1981 D5: on cd7a00857 the checker's questions reached only the e-mail; the thread said "approved for
// submission" while they were open. The reading below is a REAL proposalFromModel + checkReading of a stand-in answer.
Deno.test('in his thread the e-mailed quotation is not approved while the model\'s question is open; his confirmation, then his Submit, send it', async () => {
  const id = '3f2a9c1e-0000-4000-8000-00000000abcd';
  const inq: SafeInquiry = { id, job_no: jobNo({ id, rfq_no: 151767 }), category: 'painting', emirate: 'Dubai',
    spec: { customer_requirements: { version: 1, installation: { required: 'no' }, warranty: { required: 'yes' } } },
    boq_rows: [{ description: 'Internal wall painting emulsion', qty: 450, unit: 'm2' }], boq_withheld: false, concluded: false, revealed: false } as SafeInquiry;
  const reading = { ...checkReading(proposalFromModel({ is_quotation: true, currency: 'AED', confidence: 'low', notes: 'ZZ DEMO stand-in model answer', total: 9000, vat_treatment: 'exclusive',
    line_items: [{ description: 'Jotun Fenomastic emulsion, 2 coats, internal walls', qty: '450 m2', quantity: 450, unit: 'm2', unit_price: 20, amount: 9000 }],
    lead_time: '3 weeks', validity: '30 days', payment_terms: '50% advance', warranty: '2 years, materials and workmanship', scope: 'Supply and apply two coats to all internal walls' }, (v) => (v == null ? '' : String(v))), '', null),
    extracted_by_model: 'zz-demo/stand-in' };
  assertEquals(reading.warnings, ['We were not sure of your total. We read it as AED 9,000 excluding VAT. Is that right?']);
  const mem = memoryReviewRepo(() => new Date('2026-11-12T10:00:00Z'));
  const recorded: string[] = []; const submitted: Record<string, unknown>[] = [];
  const repo = { ...mem.repo, recordReader: (_i: string, _s: number, m: string) => { recorded.push(m); return Promise.resolve(); } };
  const deps: ReviewDeps = {
    inquiry: (x) => Promise.resolve(x === id ? inq : null),
    scan: (b64, filename, mime) => Promise.resolve({ ok: true as const, bytes: Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)), mime, name: filename }),
    read: () => Promise.resolve({ proposal: reading as never, text: '', kind: 'email' }),
    submit: (p) => { submitted.push(p); return Promise.resolve({ status: 200, json: { ok: true, accepted: true, quote: { id: 'q-1', option_no: 1, status: 'submitted' } } }); },
    quotePdf: () => Promise.resolve({ url: null, ref: null }),
    now: () => new Date('2026-11-12T10:00:00Z'),
    readWorking: (i, w) => Promise.resolve(readFixture(i, w)),
    // a STAND-IN for the model's reading of his words (ZZ DEMO): "they are right" is his confirmation, cited from his message
    voice: (v) => Promise.resolve({ text: '[ZZ DEMO stand-in engineer] ' + v.situation,
      ...((v.actions || []).some((a) => a.id === 'confirm_reading') && /right/i.test(v.supplierMessage || '') ? { action: 'confirm_reading', action_words: 'those figures are right' } : { action: null }) }),
    hold: () => Promise.resolve(),
  };
  const ctx = { supplierId: 7, email: 'quotes@zz-demo-quoting.example.invalid', lang: 'en' as const };
  const t = await upload(repo, deps, ctx, id, { b64: file.file_b64, filename: 'q.csv', mime: 'text/csv' }, null);
  assert(t.ok, JSON.stringify(t));
  assertEquals([t.state, t.open_requests.map((q) => q.code), submitted.length], ['changes_requested', ['reading_to_confirm'], 0], 'not approved while his answer is open');
  assert(t.messages.some((m) => /We were not sure of your total\. We read it as AED 9,000 excluding VAT\. Is that right\?/.test(m.body_en || '')), 'the thread asks the same question');
  assert(!t.messages.some((m) => /approved for submission/i.test(m.body_en || '')));
  assertEquals((mem.reviews[0].extracted as { extracted_by_model?: string }).extracted_by_model, 'zz-demo/stand-in');
  assert(t.messages.some((m) => m.kind === 'file' && m.attachments[0]?.name === 'q.csv'), 'his e-mailed file is in the thread');
  const c = await message(repo, deps, ctx, id, 'Yes, those figures are right.');
  assertEquals((c as { state: string }).state, 'awaiting_choice', 'his confirmation clears the point');
  assert(((await choose(repo, deps, ctx, id, 'generate')) as { state: string }).state === 'ready_to_submit');
  assertEquals(submitted.length, 0, 'still nothing sent until he presses Submit');
  await submit(repo, deps, ctx, id);
  assertEquals([submitted.length, submitted[0].amount, recorded], [1, 9000, ['zz-demo/stand-in']]);
});

// review of #1981 D1: on cd7a00857 a USD reading was placed, reviewed as AED and sent as AED 9,000 on one Submit.
Deno.test('a quotation the model read as USD is never placed: he is asked for his AED total', async () => {
  const usd = checkReading(proposalFromModel({ is_quotation: true, currency: 'USD', confidence: 'high', notes: 'ZZ DEMO stand-in model answer', total: 9000, vat_treatment: 'not_registered',
    line_items: [{ description: 'Wardrobe', qty: '1 lot', amount: 9000 }] }, (v) => (v == null ? '' : String(v))), '', null);
  for (const withReading of [true, false]) {
    const s = stub({ extract: { ok: false, error: 'total_ambiguous', review_reason: 'foreign_currency', is_quotation: true, proposal: usd } });
    const out = await emailQuote({ ...input, ...(withReading ? { reading: { proposal: usd as never, extracted_by_model: 'zz-demo/stand-in' } } : {}) }, s.deps);
    assertEquals(out, { ok: false, stage: 'extract', code: 'quote_total_ambiguous', message: null, review_reason: 'foreign_currency' });
    assertEquals(s.reviews.length, 0, 'nothing is placed in his thread');
  }
});

// review of #1981 N4: on 62ba18032 "no, it is 9,540" left 9,000 and the point open, and any cited-or-not "confirmation" cleared it.
Deno.test('in the thread he can correct the figure in words; a message about something else never counts as his confirmation', async () => {
  const id = '3f2a9c1e-0000-4000-8000-00000000abcd';
  const inq: SafeInquiry = { id, job_no: jobNo({ id, rfq_no: 151767 }), category: 'painting', emirate: 'Dubai', spec: null,
    boq_rows: [], boq_withheld: false, concluded: false, revealed: false } as SafeInquiry;
  const reading = { ...checkReading(proposalFromModel({ is_quotation: true, currency: 'AED', confidence: 'low', notes: 'ZZ DEMO stand-in model answer', total: 9000, vat_treatment: 'exclusive',
    lead_time: '3 weeks', validity: '30 days', warranty: '2 years, materials and workmanship' }, (v) => (v == null ? '' : String(v))), '', null), extracted_by_model: 'zz-demo/stand-in' };
  // the STAND-IN model slips on the unrelated message (cites words that are not his) and reads the correction right
  let next: { action: string | null; action_words?: string | null; action_value?: string | null } = { action: null };
  const mem = memoryReviewRepo(() => new Date('2026-11-12T10:00:00Z'));
  const deps: ReviewDeps = {
    inquiry: (x) => Promise.resolve(x === id ? inq : null),
    scan: (b64, filename, mime) => Promise.resolve({ ok: true as const, bytes: Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)), mime, name: filename }),
    read: () => Promise.resolve({ proposal: reading as never, text: '', kind: 'email' }),
    submit: () => Promise.reject(new Error('not in this test')), quotePdf: () => Promise.resolve({ url: null, ref: null }),
    now: () => new Date('2026-11-12T10:00:00Z'), readWorking: (i, w) => Promise.resolve(readFixture(i, w)),
    voice: (v) => Promise.resolve({ text: '[ZZ DEMO stand-in engineer] ' + v.situation, ...next }), hold: () => Promise.resolve(),
  };
  const ctx = { supplierId: 7, email: 'quotes@zz-demo-quoting.example.invalid', lang: 'en' as const };
  await upload(mem.repo, deps, ctx, id, { b64: file.file_b64, filename: 'q.csv', mime: 'text/csv' }, null);
  const openCodes = () => mem.requests.filter((q) => q.state === 'open').map((q) => q.code);
  assert(openCodes().includes('reading_to_confirm'));
  next = { action: 'confirm_reading', action_words: 'those figures are right' };
  await message(mem.repo, deps, ctx, id, 'What time is the site visit?');
  assert(openCodes().includes('reading_to_confirm'), 'an unrelated message is not his confirmation');
  next = { action: 'correct_price', action_words: 'it is 9,540', action_value: '9540' };
  const t = await message(mem.repo, deps, ctx, id, 'No, it is 9,540 before VAT.') as { messages: { body_en: string | null }[] };
  assertEquals(mem.reviews[0].working?.price_ex_vat, 9540);
  assert(!openCodes().includes('reading_to_confirm'), 'his correction answers the question');
  assert(t.messages.some((m) => /price excluding VAT AED 9,?540/.test(m.body_en || '')), 'the corrected figure is shown back');
  // a figure he did not write is never applied
  const before = mem.reviews[0].working?.price_ex_vat;
  next = { action: 'correct_price', action_words: 'it is', action_value: '95400' };
  await message(mem.repo, deps, ctx, id, 'Sorry, it is 9,540 as I said.');
  assertEquals(mem.reviews[0].working?.price_ex_vat, before);
});

