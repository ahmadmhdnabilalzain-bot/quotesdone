// A TYPED PRICE AND THE TOTAL IT MAKES ARE ONE STATE (11 Nov 2026, sales_engineer).
//
// MEASURED, nightly run 077cbbfc (10 Nov 2026, job 164810): the supplier typed "BOQ line 2 AED 27,880; BOQ line 3 AED
// 7,680" into the quotation chat and the thread read "price points open 0, total_ex_vat 30,400" (want 65,960). The parse
// and the re-total were right (this file's first test: 65,960 by code). The fault was ORDER: runReview closed the answered
// requests, then voiced the review message (a model call, seconds), and only then wrote working / last_review. The chat
// reads the thread every 4 s while it waits for the engineer (src/components/portal/supplier/awaitingReply.ts), and the
// acknowledgement bubble lands before the review, so a supplier (and the journey) read a thread whose price points were
// closed and whose total was still the old file's. The review is now persisted first; the thread can be old or new, never
// half of each.
// Run: deno test --no-check --allow-read --allow-env supabase/functions/supplier_api/a_typed_price_and_its_total_are_one_state.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { sanitizeUpload, SAFE_DOCS } from '../_shared/attachment.ts';
import { message, readQuotationFile, thread, upload, type ReviewDeps, type ThreadView } from './quote_review_flow.ts';
import { memoryReviewRepo } from './quote_review_memory_repo.ts';
import { jobNo, type SafeInquiry } from './quote_review.ts';
import { readFixture } from './review_reading.fixture.ts';

const INQ = 'd958e1ea-0000-4000-8000-00000000d958';
const inquiry = (): SafeInquiry => ({
  id: INQ, job_no: jobNo(INQ), category: 'gypsum', emirate: 'Dubai',
  spec: { customer_requirements: { version: 1, installation: { required: 'yes' }, warranty: { required: 'yes' } } },
  boq_rows: [
    { section: 'Partitions', description: 'Gypsum board partition, 100mm metal stud, both faces', qty: 320, unit: 'm2' },
    { section: 'Ceilings', description: 'Suspended false ceiling, 600x600 mineral fibre tiles', qty: 410, unit: 'm2' },
    { section: 'Ceilings', description: 'Gypsum bulkhead, 300mm drop, painted finish', qty: 64, unit: 'm' },
  ], boq_withheld: false, concluded: false, revealed: false,
} as SafeInquiry);
// scripts/e2e/journey_audit_buttons.mjs UNPRICED_CSV, byte for byte: line 1 priced, lines 2 and 3 not.
const UNPRICED_CSV = 'Description,Qty,Unit,Rate,Amount\n'
  + 'Gypsum board partition 12.5mm board 100mm metal stud both faces,320,m2,95,30400\n'
  + 'Suspended false ceiling 600x600 mineral fibre tiles,410,m2,,\n'
  + 'Gypsum bulkhead standard gypsum board 300mm drop painted finish,64,m,,\n'
  + 'Validity: 30 days\nLead time: 4 weeks from LPO\nPrices exclude VAT\nInstallation included, 4 weeks on site\nWarranty: 2 years parts and labour\n';
// What the terms model answered on production for this file (seat_judgement 13383, 10 Nov 2026 22:27Z).
const liveTerms = () => Promise.resolve({ lead_time: '4 weeks from LPO', validity: '30 days', warranty: '2 years parts and labour', exclusions: 'VAT' });
const b64 = (s: string) => btoa(s);
const isPrice = (k: string) => /^boq_line_not_priced|^line_unpriced|^total/.test(k);

function rig() {
  const mem = memoryReviewRepo(() => new Date('2026-11-10T22:27:00Z'));
  const ctx = { supplierId: 7, email: 'qd-test-sup1@example.invalid', lang: 'en' as const };
  // Every moment the engineer speaks (a model call that takes seconds on production), what a 4 s poll of the thread would
  // read at that instant: how many price points are open and the total it shows.
  const seen: { open: number; total: number | null }[] = [];
  let watching = false;
  const deps: ReviewDeps = {
    inquiry: (id) => Promise.resolve(id === INQ ? inquiry() : null),
    scan(data, filename, mime) {
      const s = sanitizeUpload({ input: data, declaredMime: mime, filename, allow: SAFE_DOCS });
      return Promise.resolve(s.ok ? { ok: true as const, bytes: s.bytes, mime: s.mime, name: filename } : { ok: false as const, status: 415, code: String(s.error), message: 'refused' });
    },
    read: (bytes, name, mime) => readQuotationFile(bytes, name, mime, [], liveTerms),
    submit: () => Promise.resolve({ status: 200, json: { ok: true } }),
    quotePdf: () => Promise.resolve({ url: 'https://example.invalid/q.pdf', ref: 'QD-X' }),
    now: () => new Date('2026-11-10T22:27:00Z'),
    readWorking: (i, w) => Promise.resolve(readFixture(i, w)),
    hold: () => Promise.resolve(),
    voice: async (v) => {
      if (watching) {
        const t = await thread(mem.repo, deps, ctx, INQ) as ThreadView;
        seen.push({ open: (t.open_requests || []).filter((q) => isPrice(q.key)).length, total: t.total_ex_vat });
      }
      return { text: '[sales engineer] ' + v.situation, action: null };
    },
  };
  return { mem, deps, ctx, seen, watch: () => { watching = true; } };
}

Deno.test('the typed prices price the BOQ lines and the total is 65,960', async () => {
  const { mem, deps, ctx } = rig();
  const t1 = await upload(mem.repo, deps, ctx, INQ, { b64: b64(UNPRICED_CSV), filename: 'h_unpriced.csv', mime: 'text/csv' }) as ThreadView;
  assertEquals(t1.total_ex_vat, 30400);
  assertEquals(t1.open_requests.filter((q) => isPrice(q.key)).length, 2, JSON.stringify(t1.open_requests.map((q) => q.key)));
  const t2 = await message(mem.repo, deps, ctx, INQ, 'BOQ line 2 AED 27,880; BOQ line 3 AED 7,680') as ThreadView;
  assertEquals(t2.open_requests.filter((q) => isPrice(q.key)).length, 0);
  assertEquals(t2.total_ex_vat, 65960);
});

Deno.test('while the engineer is still writing, the thread never shows the price points closed with the old total', async () => {
  const { mem, deps, ctx, seen, watch } = rig();
  await upload(mem.repo, deps, ctx, INQ, { b64: b64(UNPRICED_CSV), filename: 'h_unpriced.csv', mime: 'text/csv' });
  watch();
  await message(mem.repo, deps, ctx, INQ, 'BOQ line 2 AED 27,880; BOQ line 3 AED 7,680');
  assert(seen.length > 0, 'the engineer was never voiced during the review');
  const torn = seen.filter((s) => s.open === 0 && s.total !== 65960);
  assertEquals(torn, [], `a poll read the price points closed with total ${torn[0]?.total} (077cbbfc read 30,400): ${JSON.stringify(seen)}`);
});
