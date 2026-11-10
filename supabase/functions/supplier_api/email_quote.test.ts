// The e-mailed quotation takes the portal's road (customer_support, 10 Nov 2026; #1909 item 1). email_quote runs the
// portal's own extract_quote and then submit_quote, as the supplier, with the quotation-review chat's payload; no
// second reader, review or hold. The action groups are stubbed so nothing reaches a database. ZZ DEMO data only.
//   deno test --node-modules-dir=none supabase/functions/supplier_api/email_quote.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { emailQuote, type EmailQuoteDeps } from './email_quote.ts';
import { submitPayload } from './quote_review_flow/submit.ts';
import { workingFromProposal } from './quote_review/working.ts';
import { reviewQuotation } from './quote_review.ts';
import type { ActionCtx } from './context.ts';

const INQ = 'aaaaaaaa-0000-4000-8000-000000000001';
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s });
const PROPOSAL = { amount: 9000, currency: 'AED', line_items: [{ description: 'MDF wardrobe 18mm', qty: '4 no', amount: 8000 }, { description: 'Installation', qty: '1 lot', amount: 1000 }],
  lead_time: '', validity: '', payment_terms: '', warranty: '', scope: '', conditions: '', exclusions: '', notes: '', description_anonymized: '', masked_terms: [],
  confidence: 'low', method: 'document', subtotal: 9000, vat_amount: 450, total_incl_vat: 9450, vat_treatment: 'exclusive', price_ex_vat: 9000, trn: null,
  gross_amount: null, discount_amount: null, discount_label: null, options: [], option_totals: {} };
const ROW = { id: INQ, rfq_no: 164810, category: 'Joinery', emirate: 'Dubai', summary: 'ZZ DEMO wardrobes', boq: null, spec: null };

function stub(over: Partial<{ extract: unknown; submit: unknown; claimed: string | null; sanctioned: boolean }> = {}) {
  const seen: { action: string; email: string; body: Record<string, unknown> }[] = [];
  const deps: EmailQuoteDeps = {
    lead: (id) => Promise.resolve({ id, claimed_by: over.claimed === undefined ? 'Quotes@ZZ-Demo-Quoting.example.invalid' : over.claimed }),
    sanctioned: () => Promise.resolve(!!over.sanctioned),
    inboxActions: (c: ActionCtx) => { seen.push({ action: c.action, email: c.email, body: c.body }); return Promise.resolve(J({ inquiries: [ROW] })); },
    quoteActions: (c: ActionCtx) => {
      seen.push({ action: c.action, email: c.email, body: c.body });
      if (c.action === 'extract_quote') return Promise.resolve(J(over.extract ?? { ok: true, proposal: PROPOSAL, original_file_path: 'quotes/7/' + INQ + '/1_q.csv', original_file_name: 'q.csv' }));
      return Promise.resolve(J(over.submit ?? { ok: true, quote: { id: 'q1' }, accepted: false, held: true, missing: [{ label_en: 'Line 1: board brand and grade' }], code: 'spec_hold' }));
    },
    safeInquiry: (row) => ({ ...row, job_no: String(row.rfq_no), boq_lines: [] }) as never,
  };
  return { deps, seen };
}
const input = { lead_id: 7, inquiry_id: INQ, file_b64: btoa('Description,Amount\nWardrobe,8000\n'), filename: 'q.csv', mime: 'text/csv' };

Deno.test('extract_quote then submit_quote, as the supplier, with the chat\'s own payload', async () => {
  const s = stub();
  const out = await emailQuote(input, s.deps);
  assertEquals(s.seen.map((x) => x.action), ['inbox', 'extract_quote', 'submit_quote']);
  assertEquals(new Set(s.seen.map((x) => x.email)), new Set(['quotes@zz-demo-quoting.example.invalid']));
  assertEquals(s.seen[1].body.original, { b64: input.file_b64, filename: 'q.csv', mime: 'text/csv' });
  const inq = s.deps.safeInquiry(ROW); const w = workingFromProposal(PROPOSAL as never);
  assertEquals(s.seen[2].body, submitPayload(inq, { original_file_path: 'quotes/7/' + INQ + '/1_q.csv', original_file_name: 'q.csv' }, w, reviewQuotation(inq, w)));
  assertEquals(s.seen[2].body.source, 'upload');
  assertEquals(out, { ok: true, stage: 'submit', inquiry_id: INQ, accepted: false, held: true, missing: [{ label_en: 'Line 1: board brand and grade' }], message: null, code: 'spec_hold', amount: 9000, lines: 2, options: 1 });
});

Deno.test('a file the portal could not read is never submitted; the portal\'s own words go back', async () => {
  const s = stub({ extract: { error: 'quote_unreadable', code: 'quote_read_failed', message: 'We could not read "q.csv" clearly.' } });
  const out = await emailQuote(input, s.deps);
  assertEquals(s.seen.map((x) => x.action), ['inbox', 'extract_quote']);
  assertEquals(out, { ok: false, stage: 'extract', code: 'quote_read_failed', message: 'We could not read "q.csv" clearly.', review_reason: null });
});

Deno.test('a refusal of the submission (not verified, request concluded) comes back as the portal said it', async () => {
  const s = stub({ submit: { error: 'This request has been concluded.', code: 'inquiry_concluded' } });
  assertEquals(await emailQuote(input, s.deps), { ok: false, stage: 'submit', code: 'inquiry_concluded', message: 'This request has been concluded.' });
});

Deno.test('no claimed account, a sanctioned one, or a job outside his inbox: nothing runs', async () => {
  for (const [o, code] of [[{ claimed: null }, 'no_company'], [{ sanctioned: true }, 'sanctioned']] as const) {
    const s = stub(o); const out = await emailQuote(input, s.deps);
    assertEquals([out.ok, (out as { code: string }).code, s.seen.length], [false, code, 0]);
  }
  const s = stub(); s.deps.inboxActions = () => Promise.resolve(J({ inquiries: [] }));
  const out = await emailQuote(input, s.deps);
  assertEquals([out.ok, out.stage, s.seen.length], [false, 'job', 0]);
});
