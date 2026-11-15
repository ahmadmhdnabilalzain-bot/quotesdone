// A REFUSED SUBMISSION READS AS A SENTENCE IN THE CHAT, NEVER A CODE (15 Nov 2026, third review of the certificate branch, items 2
// and 6). submit_quote answers a write that did not land with 503 { error: 'quote_not_sent' | 'quote_not_saved', message }; the
// chat's refusal branch printed "I could not submit the quotation yet: quote_not_sent" in the thread and as the banner. The thread
// is driven to its Submit the way email_quote.test.ts drives it (memory repo, a stand-in model reading, ZZ DEMO only).
//   deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-read=. supabase/functions/supplier_api/a_refused_submission_reads_as_a_sentence_in_the_chat.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { memoryReviewRepo } from './quote_review_memory_repo.ts';
import { choose, message, submit, upload, type ReviewDeps } from './quote_review_flow.ts';
import { checkReading, proposalFromModel } from '../quote_extract/model_reading.ts';
import { readFixture } from './review_reading.fixture.ts';
import { jobNo, type SafeInquiry } from './quote_review.ts';

const file = { file_b64: btoa('Description,Amount\nWardrobe,8000\n'), filename: 'q.csv', mime: 'text/csv' };
const CODE = /\bquote_not_(sent|saved)\b|\bsubmit_refused\b/;

async function refusedWith(answer: { status: number; json: Record<string, unknown> }) {
  const id = '3f2a9c1e-0000-4000-8000-00000000abce';
  const inq: SafeInquiry = { id, job_no: jobNo({ id, rfq_no: 151768 }), category: 'painting', emirate: 'Dubai',
    spec: { customer_requirements: { version: 1, installation: { required: 'no' }, warranty: { required: 'yes' } } },
    boq_rows: [{ description: 'Internal wall painting emulsion', qty: 450, unit: 'm2' }], boq_withheld: false, concluded: false, revealed: false } as SafeInquiry;
  const reading = { ...checkReading(proposalFromModel({ is_quotation: true, currency: 'AED', confidence: 'high', notes: 'ZZ DEMO stand-in model answer', total: 9000, vat_treatment: 'exclusive',
    line_items: [{ description: 'Jotun Fenomastic emulsion, 2 coats, internal walls', qty: '450 m2', quantity: 450, unit: 'm2', unit_price: 20, amount: 9000 }],
    lead_time: '3 weeks', validity: '30 days', payment_terms: '50% advance', warranty: '2 years, materials and workmanship', scope: 'Supply and apply two coats to all internal walls' }, (v) => (v == null ? '' : String(v))), '', null),
    extracted_by_model: 'zz-demo/stand-in' };
  const mem = memoryReviewRepo(() => new Date('2026-11-12T10:00:00Z'));
  const deps: ReviewDeps = {
    inquiry: (x) => Promise.resolve(x === id ? inq : null),
    scan: (b64, filename, mime) => Promise.resolve({ ok: true as const, bytes: Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)), mime, name: filename }),
    read: () => Promise.resolve({ proposal: reading as never, text: '', kind: 'email' }),
    submit: () => Promise.resolve(answer),
    quotePdf: () => Promise.resolve({ url: null, ref: null }),
    now: () => new Date('2026-11-12T10:00:00Z'),
    readWorking: (i, w) => Promise.resolve(readFixture(i, w)),
    voice: (v) => Promise.resolve({ text: '[ZZ DEMO stand-in engineer] ' + v.situation, action: null }),
    hold: () => Promise.resolve(),
  };
  const ctx = { supplierId: 7, email: 'quotes@zz-demo-quoting.example.invalid', lang: 'en' as const };
  await upload(mem.repo, deps, ctx, id, { b64: file.file_b64, filename: 'q.csv', mime: 'text/csv' }, null);
  await message(mem.repo, deps, ctx, id, 'Those figures are right.');
  await choose(mem.repo, deps, ctx, id, 'generate');
  const t = await submit(mem.repo, deps, ctx, id) as { notice?: { code?: string; message?: string } | null; messages: { body_en?: string | null }[] };
  return { t, inq };
}

Deno.test('a write that did not land: the thread and the banner say it was not sent and name the chat\'s own button, never a code', async () => {
  for (const code of ['quote_not_sent', 'quote_not_saved']) {
    const { t, inq } = await refusedWith({ status: 503, json: { ok: false, error: code, code, retryable: true, message: 'Your quotation was NOT sent: ... Please press "Submit quote" again in a moment.' } });
    assert(t.notice, 'a notice is shown');
    assert(!CODE.test(String(t.notice!.message)), `banner: ${t.notice!.message}`);
    assert(String(t.notice!.message).includes(`"Submit to Job ${inq.job_no}"`), String(t.notice!.message));
    const last = t.messages[t.messages.length - 1];
    assert(!CODE.test(String(last.body_en)), `thread: ${last.body_en}`);
    assert(/NOT sent to the customer/.test(String(last.body_en)), String(last.body_en));
  }
});

Deno.test('an older refusal whose error is a sentence still reads as that sentence; a bare code with no message reads as the general one', async () => {
  const a = await refusedWith({ status: 400, json: { ok: false, error: 'accept the supplier terms first', code: 'terms_not_accepted' } });
  assertEquals(a.t.notice?.message, 'accept the supplier terms first');
  const b = await refusedWith({ status: 500, json: { ok: false, error: 'unexpected_error', code: 'unexpected_error' } });
  assertEquals(b.t.notice?.message, 'The quotation could not be submitted.');
});

Deno.test('the page shows a notice through noticeText, which never prints a bare code (serverCopy.ts imports the site\'s @/ modules, so it is read)', () => {
  const chat = Deno.readTextFileSync(new URL('../../../src/components/portal/supplier/QuoteReviewChat.tsx', import.meta.url));
  assert(chat.includes("setErr(v.notice ? noticeText(lang, v.notice, t.err) : '')"));
  const copy = Deno.readTextFileSync(new URL('../../../src/components/portal/supplier/serverCopy.ts', import.meta.url));
  assert(/export function noticeText\(lang: string, notice: any, fallback: string\): string \{\n  const m = srvMsg\(lang, notice, fallback\);\n  return \/\\s\/\.test\(m\) \? m : fallback;/.test(copy));
  for (const k of ['quote_not_sent', 'quote_not_sent_approve', 'quote_not_saved']) assert(copy.includes(`  ${k}: s('`), k);
  assert(copy.includes('Please press "Submit quote" again') && copy.includes('Please press "Approve and send to the customer" again'));
  const agreement = Deno.readTextFileSync(new URL('../../../src/components/portal/supplier/core/Agreement.tsx', import.meta.url));
  assert(agreement.includes("setMsg(srvMsg(lang, j, t(lang, 'err_generic')))"), 'the terms page shows the server\'s sentence (item 6)');
});
