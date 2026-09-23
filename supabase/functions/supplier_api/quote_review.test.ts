// supplier_api/quote_review.test.ts — the sales engineer's quotation review, proved in memory.
//
// Table-driven: the approved case, then each failure reason on its own, each with its English AND its
// Arabic words; the supplier's replies read by rule; and the whole conversation — incomplete file,
// points raised, answered in text, approved, "generate", submitted through submit_quote — run on the
// in-memory repository with the REAL doc_read and quote_from_document readers. No database, no network.
import { assert, assertEquals, assertMatch, assertStringIncludes } from 'jsr:@std/assert@1';
import { sanitizeUpload, SAFE_DOCS } from '../_shared/attachment.ts';
import {
  applyCorrections, fromMissing, generatedSaid, issueKey, jobNo, matchBoq, normUnit, readReply, reviewQuotation, reviewSaid, sanitizeSpec, sanitizeTermsSpec, tookSaid, workingFromProposal,
  type IssueCode, type SafeInquiry, type Working,
} from './quote_review.ts';
import { choose, message, readQuotationFile, start, submit, submitPayload, thread, typed, upload, type ReviewDeps, type ThreadView } from './quote_review_flow.ts';
import { boqCsv } from './quote_review_actions.ts';
import { memoryReviewRepo } from './quote_review_memory_repo.ts';
import { completenessOf, itemsOfRows, quoteDocument } from '../_shared/quote_documents.ts';

const INQ_ID = '3f2a9c1e-0000-4000-8000-00000000abcd';
const inquiry = (over: Partial<SafeInquiry> = {}): SafeInquiry => ({
  id: INQ_ID, job_no: jobNo({ id: INQ_ID, rfq_no: 151767 }), category: 'painting', emirate: 'Dubai',
  spec: { customer_requirements: { version: 1, installation: { required: 'no' }, warranty: { required: 'yes' } } },
  boq_rows: [{ description: 'Internal wall painting emulsion', qty: 450, unit: 'm2' }], boq_withheld: false, concluded: false, revealed: false, ...over,
});
/** A quotation that satisfies every rule for the inquiry above. */
const good = (over: Partial<Working> = {}): Working => ({
  lines: [{ description: 'Jotun Fenomastic emulsion, 2 coats, internal walls', qty: '450', unit: 'm2', unit_price: 20, amount: 9000 }],
  amount: 9000, subtotal: null, vat_amount: null, vat_treatment: 'exclusive', price_ex_vat: 9000, trn: null,
  lead_time: '3 weeks', validity: '30 days', payment_terms: '50% advance', warranty: '2 years, materials and workmanship',
  scope: 'Supply and apply two coats to all internal walls', conditions: '', exclusions: '', notes: 'Prices exclude VAT',
  terms_spec: {}, masked_terms: [], option_totals: {}, foreign_currency: null, boq_excluded: {}, qty_explained: {}, corrections: [], ...over,
});
const ARABIC = /[؀-ۿ]/;

Deno.test('a quotation that meets every rule is approved, in both languages', () => {
  const r = reviewQuotation(inquiry(), good());
  assertEquals(r.issues, [], JSON.stringify(r.issues));
  assert(r.approved);
  const s = reviewSaid(jobNo(INQ_ID), r);
  assertMatch(s.en, /^Quotation approved for submission\./);
  assertMatch(s.ar, /^اعتُمد عرض السعر للتقديم\./);
});

// Each row breaks exactly one rule and names the one code the review must raise for it.
const CASES: { name: string; inq?: Partial<SafeInquiry>; w: Partial<Working>; code: IssueCode; kind: 'adjustment' | 'clarification'; line?: number | null; boq?: number | null }[] = [
  { name: 'a BOQ line with no price', inq: { boq_rows: [{ description: 'Internal wall painting emulsion', qty: 450, unit: 'm2' }, { description: 'Ceiling gypsum board painting', qty: 120, unit: 'm2' }] }, w: {}, code: 'boq_line_not_priced', kind: 'adjustment', boq: 2 },
  { name: 'a quantity that differs from the BOQ', w: { lines: [{ description: 'Jotun Fenomastic emulsion, 2 coats, internal walls', qty: '400', unit: 'm2', unit_price: 22.5, amount: 9000 }] }, code: 'qty_mismatch', kind: 'clarification', line: 1, boq: 1 },
  { name: 'a unit that differs from the BOQ', w: { lines: [{ description: 'Jotun Fenomastic emulsion, 2 coats, internal walls', qty: '450', unit: 'litre', unit_price: 20, amount: 9000 }] }, code: 'unit_mismatch', kind: 'clarification', line: 1, boq: 1 },
  { name: 'a line with a quantity and no price', w: { lines: [...good().lines, { description: 'Masking tape and protection', qty: '10', unit: 'nr', unit_price: null, amount: null }] }, code: 'line_unpriced', kind: 'adjustment', line: 2 },
  { name: 'lines that do not add up to the total', w: { amount: 12000, price_ex_vat: 12000 }, code: 'total_mismatch', kind: 'clarification' },
  { name: 'a price in another currency', w: { foreign_currency: 'USD' }, code: 'currency_not_aed', kind: 'adjustment' },
  { name: 'no VAT basis', w: { vat_treatment: 'not_stated', price_ex_vat: null, notes: '' }, code: 'vat_basis', kind: 'adjustment' },
  { name: 'VAT included with no VAT amount', w: { vat_treatment: 'inclusive', price_ex_vat: null, notes: 'Prices include VAT' }, code: 'vat_ex_price', kind: 'adjustment' },
  { name: 'no validity', w: { validity: '' }, code: 'validity', kind: 'adjustment' },
  { name: 'a vague validity', w: { validity: 'as per standard terms' }, code: 'validity', kind: 'adjustment' },
  { name: 'a line without its exact specification', w: { lines: [{ description: 'Jotun Fenomastic emulsion, internal walls', qty: '450', unit: 'm2', unit_price: 20, amount: 9000 }] }, code: 'spec', kind: 'adjustment', line: 1 },
  { name: 'no delivery date or lead time', w: { lead_time: '' }, code: 'delivery', kind: 'adjustment' },
  { name: 'no warranty period', w: { warranty: '' }, code: 'warranty_period', kind: 'adjustment' },
];
for (const c of CASES) {
  Deno.test(`held for ${c.name} — ${c.code}, EN and AR`, () => {
    const r = reviewQuotation(inquiry(c.inq), good(c.w));
    assert(!r.approved, 'expected a hold');
    const hit = r.issues.find((i) => i.code === c.code);
    assert(hit, `expected ${c.code}, got ${r.issues.map((i) => i.code).join(', ')}`);
    assertEquals(hit.kind, c.kind);
    if (c.line !== undefined) assertEquals(hit.line_no, c.line);
    if (c.boq !== undefined) assertEquals(hit.boq_line, c.boq);
    assert(hit.en.length > 20 && !ARABIC.test(hit.en), 'English words');
    assert(ARABIC.test(hit.ar), 'Arabic words');
    const s = reviewSaid(jobNo(INQ_ID), r);
    assertMatch(s.en, new RegExp(`Job ${jobNo(INQ_ID)}`)); assert(ARABIC.test(s.ar));
  });
}

Deno.test('a TRN is never asked for, and "not VAT registered" is a complete VAT basis', () => {
  const r = reviewQuotation(inquiry(), good({ vat_treatment: 'not_stated', price_ex_vat: null, notes: 'We are not VAT registered' }));
  assert(r.approved, JSON.stringify(r.issues));
  const all = reviewQuotation(inquiry(), good({ vat_treatment: 'not_stated', price_ex_vat: null, notes: '', validity: '', lead_time: '' }));
  assert(!all.issues.some((i) => /\bTRN\b/.test(i.en) && !/needs no TRN/.test(i.en)), 'a TRN must never be requested');
});

Deno.test('a withheld BOQ is not held against the supplier', () => {
  const r = reviewQuotation(inquiry({ boq_withheld: true, boq_rows: [{ description: 'Ceiling painting', qty: 1, unit: 'ls' }] }), good());
  assert(r.approved, JSON.stringify(r.issues));
});

Deno.test('units agree across spellings, and BOQ lines match by their words', () => {
  assertEquals(normUnit('sqm'), 'm2'); assertEquals(normUnit('m²'), 'm2'); assertEquals(normUnit('Nos'), 'nr'); assertEquals(normUnit('L.S'), 'ls');
  const m = matchBoq([{ description: 'Internal wall painting emulsion' }, { description: 'Ceiling painting' }], [{ description: 'Ceiling emulsion painting', qty: '1', unit: 'ls', unit_price: null, amount: 10 }, ...good().lines]);
  assertEquals(m.get(0), 1); assertEquals(m.get(1), 0);
});

// The supplier's replies, read by rule.
const REPLIES: { text: string; field?: string; value?: unknown; choice?: 'generate' | 'reupload'; topic?: string }[] = [
  { text: 'validity 30 days', field: 'validity', value: '30 days' },
  { text: 'Lead time: 3 weeks from approval', field: 'lead_time', value: '3 weeks' },
  { text: 'prices exclude VAT', field: 'vat_treatment', value: 'exclusive' },
  { text: 'We are not VAT registered', field: 'vat_treatment', value: 'not_registered' },
  { text: 'price excluding VAT 10,500', field: 'price_ex_vat', value: 10500 },
  { text: 'الصلاحية 30 يومًا', field: 'validity' },
  { text: 'مدة التسليم 3 أسابيع', field: 'lead_time' },
  { text: 'please generate it for me', choice: 'generate' },
  { text: 'I will upload a new version', choice: 'reupload' },
  { text: 'أعدّه لي من فضلك', choice: 'generate' },
  { text: 'what is still missing?', topic: 'missing' },
  { text: 'Do I need a TRN?', topic: 'vat' },
  { text: 'who is the customer?', topic: 'customer' },
];
for (const c of REPLIES) {
  Deno.test(`the reply "${c.text}" is read`, () => {
    const r = readReply(c.text, []);
    if (c.field) {
      const hit = r.corrections.find((x) => x.field === c.field) as { value?: unknown } | undefined;
      assert(hit, `expected ${c.field} from ${JSON.stringify(r)}`);
      if (c.value !== undefined) assertEquals(hit.value, c.value);
    }
    if (c.choice) assertEquals(r.choice, c.choice);
    if (c.topic) assertEquals(r.topic, c.topic);
  });
}

Deno.test('an excluded BOQ line and a stated specification close their points', () => {
  const inq = inquiry({ boq_rows: [...inquiry().boq_rows, { description: 'Ceiling gypsum board painting', qty: 120, unit: 'm2' }] });
  const w0 = good({ lines: [{ description: 'Jotun Fenomastic emulsion, internal walls', qty: '450', unit: 'm2', unit_price: 20, amount: 9000 }] });
  const r0 = reviewQuotation(inq, w0);
  assertEquals(r0.issues.map((i) => i.code).sort(), ['boq_line_not_priced', 'spec']);
  const rr = readReply('BOQ line 2 excluded — by others. Line 1 number of coats: 2', r0.issues);
  const w1 = applyCorrections(w0, rr.corrections);
  const r1 = reviewQuotation(inq, w1);
  assert(r1.approved, JSON.stringify({ corrections: rr.corrections, issues: r1.issues }));
  assertMatch(w1.exclusions, /BOQ line 2 excluded/);
});

Deno.test('what submit_quote receives from the chat is cleaned of contact details and identity numbers', () => {
  const s = sanitizeSpec({ material: 'MDF, call 050 123 4567', thickness_mm: '18', 'Bad Key': 'x', coats: 'n/a' });
  assertEquals(Object.keys(s.spec).sort(), ['material', 'thickness_mm']);
  assert(!/050/.test(s.spec.material));
  const t = sanitizeTermsSpec({ delivery: { value: 'in 3 weeks, info@acme.ae' }, installation: { included: 'maybe' }, warranty: { period: '2 years', coverage: 'parts' } });
  assert(t && t.delivery && !/@/.test(t.delivery.value) && !t.installation && t.warranty?.period === '2 years');
});

// ---------------------------------------------------------------------------------------------
// The whole conversation, in memory, with the real file readers.
// ---------------------------------------------------------------------------------------------
const b64 = (s: string) => btoa(String.fromCharCode(...new TextEncoder().encode(s)));
const INCOMPLETE_CSV = 'Description,Qty,Unit,Rate,Amount\nJotun Fenomastic emulsion 2 coats internal walls,450,m2,20,9000\nTotal,,,,9000\n';
const COMPLETE_CSV = INCOMPLETE_CSV + 'Validity: 30 days\nLead time: 3 weeks\nWarranty: 2 years materials and workmanship\nPrices exclude VAT\n';
// THE TERMS ARE REASONED in production (reasoned_suppliers.ts quoteTerms, founder_instruction 886-903); here the
// model is mocked: each fixture gets the answer a model gives it, selected by which fixture it is.
const COMPLETE_TERMS = { validity: '30 days', lead_time: '3 weeks', warranty: '2 years materials and workmanship' };
const PDF_TERMS = { validity: '30 days', lead_time: '4 weeks from LPO', payment_terms: '50% advance, 50% on completion' };
const mockedModel = (text: string) => Promise.resolve(text.includes('Validity: 30 days') ? COMPLETE_TERMS : {});
const pdfModel = () => Promise.resolve(PDF_TERMS);
function harness(inq = inquiry()) {
  const mem = memoryReviewRepo(() => new Date('2026-09-15T10:00:00Z'));
  const submitted: Record<string, unknown>[] = [];
  const deps: ReviewDeps = {
    inquiry: (id) => Promise.resolve(id === inq.id ? inq : null),
    scan(data, filename, mime) {
      const s = sanitizeUpload({ input: data, declaredMime: mime, filename, allow: SAFE_DOCS });
      return Promise.resolve(s.ok ? { ok: true as const, bytes: s.bytes, mime: s.mime, name: filename } : { ok: false as const, status: 415, code: String(s.error), message: 'refused' });
    },
    read: (bytes, name, mime) => readQuotationFile(bytes, name, mime, ['ZZ DEMO Paint Co'], mockedModel),
    submit(p) { submitted.push(p); return Promise.resolve({ status: 200, json: { ok: true, accepted: true, quote: { id: 'q-1', option_no: 1, status: 'submitted' } } }); },
    quotePdf: () => Promise.resolve({ url: 'https://example.invalid/q.pdf', ref: 'QD-3F2A9C1E-S' }),
    now: () => new Date('2026-09-15T10:00:00Z'),
  };
  return { mem, deps, submitted, ctx: { supplierId: 7, email: 'qd-test-sup1@example.invalid', lang: 'en' as const } };
}
const ok = (v: unknown): ThreadView => { assert((v as ThreadView).ok, JSON.stringify(v)); return v as ThreadView; };

Deno.test('the conversation: incomplete file → points raised → answered in text → approved → generate → submitted', async () => {
  const { mem, deps, submitted, ctx } = harness();
  const t0 = ok(await start(mem.repo, deps, ctx, INQ_ID));
  assertEquals(t0.state, 'open'); assertEquals(t0.messages.length, 1); assert(ARABIC.test(t0.messages[0].body_ar || ''));

  const t1 = ok(await upload(mem.repo, deps, ctx, INQ_ID, { b64: b64(INCOMPLETE_CSV), filename: 'quote_incomplete.csv', mime: 'text/csv' }));
  assertEquals(t1.state, 'changes_requested');
  const codes = t1.open_requests.map((q) => q.code).sort();
  assertEquals(codes, ['delivery', 'validity', 'vat_basis', 'warranty_coverage', 'warranty_period'].sort(), JSON.stringify(t1.open_requests));
  assert(t1.messages.some((m) => m.kind === 'file' && m.attachments[0]?.url));

  const t2 = ok(await message(mem.repo, deps, ctx, INQ_ID, 'validity 30 days. lead time 3 weeks. prices exclude VAT. warranty 2 years covering materials and workmanship'));
  assertEquals(t2.state, 'awaiting_choice', JSON.stringify(t2.open_requests));
  assert(t2.messages.some((m) => /^Quotation approved for submission/.test(m.body_en || '')));
  assertEquals(t2.open_requests.map((q) => q.kind), ['choice']);
  assert(mem.requests.filter((q) => q.kind !== 'choice').every((q) => q.state === 'answered' && q.answered_message_id));

  // UPDATED 22 Sep 2026 (finding SP-F-07). This step used to assert that "generate" SUBMITTED — the
  // supplier's first sight of the quotation sent in its name was after the customer had it. The
  // generated quotation is now printed in the thread and waits in ready_to_submit for the
  // supplier's own Submit, exactly as the reupload road does and as the spec-hold's approve step
  // does. The check pins the corrected behaviour: printed, nothing sent, then sent on approval.
  const t2b = ok(await choose(mem.repo, deps, ctx, INQ_ID, 'generate'));
  assertEquals(t2b.state, 'ready_to_submit'); assert(t2b.can_submit);
  assertEquals(submitted.length, 0, 'the generated quotation was sent before the supplier saw it');
  assert(t2b.messages.some((m) => /standardised QuotesDone quotation I have prepared/.test(m.body_en || '') && ARABIC.test(m.body_ar || '')),
    'the generated quotation was not printed for the supplier');

  const t3 = ok(await submit(mem.repo, deps, ctx, INQ_ID));
  assertEquals(t3.state, 'submitted'); assertEquals(t3.submitted_quote_ids, ['q-1']);
  assertEquals(t3.open_requests, []); assert(!t3.can_write);
  assertEquals(submitted.length, 1);
  const p = submitted[0] as Record<string, unknown>;
  assertEquals(p.action, 'submit_quote'); assertEquals(p.source, 'upload'); assertEquals(p.amount, 9000); assertEquals(p.validity, '30 days');
  assertMatch(String(p.original_file_path), /^review\/7\//);

  const late = await message(mem.repo, deps, ctx, INQ_ID, 'one more thing');
  assertEquals((late as { code?: string }).code, 'review_closed');
  assertEquals((await thread(mem.repo, deps, ctx, INQ_ID) as ThreadView).messages.length, t3.messages.length, 'a closed thread is never written to');
});

Deno.test('the conversation: approved → "upload" → the new version is reviewed → submit', async () => {
  const { mem, deps, submitted, ctx } = harness();
  await start(mem.repo, deps, ctx, INQ_ID);
  const t1 = ok(await upload(mem.repo, deps, ctx, INQ_ID, { b64: b64(COMPLETE_CSV), filename: 'quote_v1.csv', mime: 'text/csv' }));
  assertEquals(t1.state, 'awaiting_choice', JSON.stringify(t1.open_requests));
  const t2 = ok(await message(mem.repo, deps, ctx, INQ_ID, "I'll upload a new version"));
  assertEquals(t2.state, 'awaiting_upload');
  const t3 = ok(await upload(mem.repo, deps, ctx, INQ_ID, { b64: b64(COMPLETE_CSV), filename: 'quote_v2.csv', mime: 'text/csv' }));
  assertEquals(t3.state, 'ready_to_submit'); assert(t3.can_submit);
  assertEquals(submitted.length, 0, 'nothing is submitted without the supplier');
  const t4 = ok(await submit(mem.repo, deps, ctx, INQ_ID));
  assertEquals(t4.state, 'submitted'); assertEquals(String((submitted[0] as Record<string, unknown>).original_file_name), 'quote_v2.csv');
});

// SP-F-03 (22 Sep 2026): the scan's way in. The typed lines go through the SAME parser and the
// SAME review as an attached file — nothing about the quotation is trusted more for being typed.
Deno.test('a quotation typed into the chat is read and reviewed exactly like an attached file', async () => {
  const { mem, deps, submitted, ctx } = harness();
  await start(mem.repo, deps, ctx, INQ_ID);
  const t1 = ok(await typed(mem.repo, deps, ctx, INQ_ID, COMPLETE_CSV.replace(/,/g, '  ')));
  assertEquals(t1.state, 'awaiting_choice', JSON.stringify(t1.open_requests));
  assert(t1.messages.some((m) => m.role === 'supplier' && /Jotun/.test(m.text || '')), 'the supplier\'s own words are kept in the thread');
  assertEquals(submitted.length, 0, 'typing a quotation must not submit it');

  // AND THROUGH THE ORDINARY CHAT BOX. A supplier told "type it here" types it into the message
  // field, which is review_message; it used to answer "attach the new version" a third time.
  const box = harness();
  await start(box.mem.repo, box.deps, box.ctx, INQ_ID);
  const t1b = ok(await message(box.mem.repo, box.deps, box.ctx, INQ_ID, COMPLETE_CSV.replace(/,/g, '  ')));
  assertEquals(t1b.state, 'awaiting_choice', JSON.stringify(t1b.open_requests));

  // Nothing priced in it: answered in the conversation, never sent to the customer, and the thread
  // goes back to where it was rather than sitting in 'reviewing'.
  const empty = harness();
  await start(empty.mem.repo, empty.deps, empty.ctx, INQ_ID);
  const t2 = ok(await typed(empty.mem.repo, empty.deps, empty.ctx, INQ_ID, 'we can do this job, call me'));
  assertEquals(t2.state, 'open');
  assertMatch(t2.messages.at(-1)!.body_en || '', /could not read a priced item/);
  assertEquals(((await typed(empty.mem.repo, empty.deps, empty.ctx, INQ_ID, '   ')) as { code?: string }).code, 'text_required');

  // A ONE-LINE QUOTATION IS NOT A DEAD END (23 Sep 2026, re-review of SP-F-03). review_typed has no
  // caller in src/ — quoteReviewApi.ts exposes choose/submit/message/upload — so the chat box IS the
  // typed path, and its two-priced-line test sent a single-line quotation straight back to "attach
  // the new version": the exact dead end SP-F-03 exists to close. Pre-fix this asserts that reply.
  const one = harness();
  await start(one.mem.repo, one.deps, one.ctx, INQ_ID);
  const t3 = ok(await message(one.mem.repo, one.deps, one.ctx, INQ_ID,
    'Jotun Fenomastic emulsion 2 coats internal walls 450 m2 20 = 9000'));
  const last = t3.messages.at(-1)!;
  assert(!/attach the new version/.test(last.body_en || ''), 'a single priced line was answered with "attach the new version" instead of being read');
  // It was READ, so the review ran and raised its own points (this one line states no VAT basis, no
  // validity, no lead time and no warranty). changes_requested is the conversation carrying on; the
  // pre-fix answer left the thread in 'open' with nothing raised.
  assertEquals(t3.state, 'changes_requested', JSON.stringify(t3.open_requests));
  assert(t3.open_requests.some((q) => q.code === 'validity'), 'the typed line was not reviewed');
});

// SP-F-06 / finding 6 of the re-review (23 Sep 2026): the preview prints at most PREVIEW_LINES lines
// and then says how many are left. At exactly one left it read "the remaining 1 are in the quotation".
// The Arabic was already number-safe — it carries the count in brackets — so only the English moved.
Deno.test('the generated preview counts the lines it did not print, in both languages', () => {
  const line = (i: number) => ({ line_no: i + 1, description: `Line ${i + 1}`, qty: 1, unit: 'no', unit_price: 100, amount: 100, boq_line_no: null });
  const said = (n: number) => generatedSaid('J-1', { lines: Array.from({ length: n }, (_, i) => line(i)), amount: n * 100, validity: '30 days', lead_time: null, warranty: null, payment_terms: null, exclusions: null, currency: 'AED' } as unknown as Working, n * 100);
  assertMatch(said(41).en, /the remaining 1 line is in the quotation/);
  assertMatch(said(42).en, /the remaining 2 lines are in the quotation/);
  assert(!/remaining/.test(said(40).en), 'at exactly 40 lines nothing is left over, so nothing is counted');
  assertMatch(said(41).ar, /وبقية البنود \(1\)/);
});

Deno.test('the hold gate disagreeing reopens the conversation with its own list', async () => {
  const { mem, deps, ctx } = harness();
  deps.submit = () => Promise.resolve({ status: 200, json: { ok: true, held: true, accepted: false, missing: [{ scope: 'quote', line_no: null, description: null, attr: 'delivery', label_en: 'Delivery date or lead time', label_ar: 'تاريخ التسليم', type: 'text' }] } });
  await start(mem.repo, deps, ctx, INQ_ID);
  await upload(mem.repo, deps, ctx, INQ_ID, { b64: b64(COMPLETE_CSV), filename: 'q.csv', mime: 'text/csv' });
  // 22 Sep 2026 (SP-F-07): "generate" now prints the quotation and waits; the hold gate is reached
  // by the supplier's Submit, and its words still win over the review's.
  ok(await choose(mem.repo, deps, ctx, INQ_ID, 'generate'));
  const t = ok(await submit(mem.repo, deps, ctx, INQ_ID));
  assertEquals(t.state, 'changes_requested'); assert(t.open_requests.some((q) => q.code === 'delivery'));
});

Deno.test('a photo is answered, not guessed; a closed job refuses; another supplier cannot open it', async () => {
  const { mem, deps, ctx } = harness();
  await start(mem.repo, deps, ctx, INQ_ID);
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 0x90, 0x77, 0x53, 0xde]);
  const t = ok(await upload(mem.repo, deps, ctx, INQ_ID, { b64: btoa(String.fromCharCode(...png)), filename: 'photo.png', mime: 'image/png' }));
  assertEquals(t.state, 'open'); assertMatch(t.messages.at(-1)!.body_en || '', /photo or a scan/);
  // AND IT NAMES THE WAY FORWARD (finding SP-F-03, 22 Sep 2026). Under the model hold there is no
  // OCR, so a supplier whose quotation is a scan used to have nowhere to go but the quote form
  // outside this conversation — the door that skips the review entirely.
  assertMatch(t.messages.at(-1)!.body_en || '', /type it here instead/i);
  assert(ARABIC.test(t.messages.at(-1)!.body_ar || ''));

  const shut = harness(inquiry({ concluded: true }));
  assertEquals(((await start(shut.mem.repo, shut.deps, shut.ctx, INQ_ID)) as { code: string }).code, 'inquiry_closed');
  assertEquals(((await thread(mem.repo, deps, ctx, '11111111-1111-4111-8111-111111111111')) as { code: string }).code, 'not_found');
});

Deno.test('an explained quantity does not silence a unit that differs on the same line', () => {
  const w = good({ lines: [{ description: 'Jotun Fenomastic emulsion, 2 coats, internal walls', qty: '400', unit: 'litre', unit_price: 22.5, amount: 9000 }], qty_explained: { '1': 'measured on site' } });
  const r = reviewQuotation(inquiry(), w);
  assert(r.issues.some((i) => i.code === 'unit_mismatch') && !r.issues.some((i) => i.code === 'qty_mismatch'), JSON.stringify(r.issues.map((i) => i.code)));
  const open = r.issues.filter((i) => i.code === 'unit_mismatch');
  const rr = readReply('BOQ line 1 unit: we measure paint by the litre, 1 litre covers 1 m2', open);
  assertEquals(rr.corrections.map((c) => (c as { what?: string }).what), ['unit']);
  assert(reviewQuotation(inquiry(), applyCorrections(w, rr.corrections)).approved);
});

Deno.test('the BOQ CSV never hands Excel a formula', () => {
  const csv = boqCsv([{ description: '=HYPERLINK("http://x","go")', qty: 1, unit: 'nr' }, { description: '+SUM(A1)', qty: 2, unit: '@x' }]);
  assert(csv.includes(`"'=HYPERLINK(""http://x"",""go"")"`), csv);
  assert(csv.includes("'+SUM(A1)") && csv.includes("'@x"), csv);
});

Deno.test('one option accepted and one held: the accepted one is submitted, the held one is named', async () => {
  const { mem, deps, ctx } = harness();
  deps.submit = () => Promise.resolve({ status: 200, json: { ok: true, accepted: true, held: true, options: [
    { quote_id: 'q-1', option_no: 1, accepted: true },
    { quote_id: 'q-2', option_no: 2, held: true, missing: [{ scope: 'quote', line_no: null, description: null, attr: 'delivery', label_en: 'Delivery date or lead time', label_ar: 'تاريخ التسليم', type: 'text' }] },
  ] } });
  await start(mem.repo, deps, ctx, INQ_ID);
  await upload(mem.repo, deps, ctx, INQ_ID, { b64: b64(COMPLETE_CSV), filename: 'q.csv', mime: 'text/csv' });
  ok(await choose(mem.repo, deps, ctx, INQ_ID, 'generate'));   // prints it; the Submit below sends it (SP-F-07)
  const t = ok(await submit(mem.repo, deps, ctx, INQ_ID));
  assertEquals(t.state, 'submitted'); assertEquals(t.submitted_quote_ids, ['q-1']);
  const last = t.messages.at(-1)!;
  assertMatch(last.body_en || '', /Option 2 is still held/); assert(ARABIC.test(last.body_ar || ''));
});

Deno.test('a double submission submits once', async () => {
  const { mem, deps, submitted, ctx } = harness();
  await start(mem.repo, deps, ctx, INQ_ID);
  await upload(mem.repo, deps, ctx, INQ_ID, { b64: b64(COMPLETE_CSV), filename: 'q1.csv', mime: 'text/csv' });
  await message(mem.repo, deps, ctx, INQ_ID, "I'll upload a new version");
  await upload(mem.repo, deps, ctx, INQ_ID, { b64: b64(COMPLETE_CSV), filename: 'q2.csv', mime: 'text/csv' });
  const both = await Promise.all([submit(mem.repo, deps, ctx, INQ_ID), submit(mem.repo, deps, ctx, INQ_ID)]);
  assertEquals(submitted.length, 1, 'submit_quote must be called once');
  assert(both.some((x) => (x as ThreadView).notice?.code === 'already_submitting' || (x as { code?: string }).code), JSON.stringify(both.map((x) => (x as ThreadView).notice)));
  assertEquals(ok((await thread(mem.repo, deps, ctx, INQ_ID))).state, 'submitted');
});

Deno.test('submitPayload carries the chat-confirmed details the hold gate reads', () => {
  const w = applyCorrections(good(), readReply('installation included, 5 working days on site', []).corrections);
  const p = submitPayload(inquiry(), { original_file_path: 'review/7/x/q.csv', original_file_name: 'q.csv' }, w, reviewQuotation(inquiry(), w));
  assertEquals((p.terms_spec as { installation?: { included: string } }).installation?.included, 'yes');
  assertEquals((p.items as { qty: number }[])[0].qty, 450);
});

// The three fixes from the 18 Sep independent reviews: an attribute this file does not know must not
// reach the database as an invalid issue code, and every VAT treatment readVat can return must be
// acknowledged back to the supplier rather than applied in silence.
Deno.test('a term assess.ts adds but this file does not know is asked as a spec, not stored as a bad code', () => {
  const known = fromMissing({ scope: 'quote', line_no: null, description: null, attr: 'delivery',
    label_en: 'Delivery', label_ar: 'التسليم', type: 'text' });
  assertEquals(known.code, 'delivery');
  const unknown = fromMissing({ scope: 'quote', line_no: null, description: null, attr: 'payment_terms',
    label_en: 'Payment terms', label_ar: 'شروط الدفع', type: 'text' });
  assertEquals(unknown.code, 'spec', 'an unknown quote-level attribute must fall back to spec');
  assertEquals(unknown.attr, 'payment_terms', 'and must still carry the attribute it came from');
});

Deno.test('every VAT treatment the reader returns is said back to the supplier', () => {
  for (const v of ['exclusive', 'inclusive', 'not_registered', 'confirmed_on_portal'] as const) {
    const said = tookSaid([{ field: 'vat_treatment', value: v }]);
    assert(said, `no acknowledgement for ${v}`);
    assert(said.en.length > 0 && said.ar.length > 0, `${v} was applied without being said in both languages`);
  }
});

// ---------------------------------------------------------------------------------------------
// THE AUDITOR'S SESSION OF 21 SEP 2026, replayed on the fixtures it used (supplier_api/fixtures/):
// the job's BOQ (22_Job_D958E1EA_BOQ.csv), the text PDF that was read as "9 things needed"
// (ZZDEMO_quotation_D958E1EA.pdf) and the CSV with a Specification column. Nothing here is real:
// ZZ DEMO Interiors gypsum founderdemo, invented figures.
// ---------------------------------------------------------------------------------------------
const FIX = new URL('./fixtures/', import.meta.url);
const fixture = (name: string) => Deno.readFile(new URL(name, FIX));
const b64bytes = (b: Uint8Array) => { let s = ''; for (const c of b) s += String.fromCharCode(c); return btoa(s); };
const GYPSUM_INQ_ID = 'd958e1ea-0000-4000-8000-00000000d958';
const gypsumInquiry = (): SafeInquiry => ({
  id: GYPSUM_INQ_ID, job_no: jobNo(GYPSUM_INQ_ID), category: 'gypsum', emirate: 'Dubai',
  spec: { customer_requirements: { version: 1, installation: { required: 'yes' }, warranty: { required: 'yes' } } },
  boq_rows: [
    { section: 'Partitions', description: 'Gypsum board partition, 100mm metal stud, both faces', qty: 320, unit: 'm2' },
    { section: 'Ceilings', description: 'Suspended false ceiling, 600x600 mineral fibre tiles', qty: 410, unit: 'm2' },
    { section: 'Ceilings', description: 'Gypsum bulkhead, 300mm drop, painted finish', qty: 64, unit: 'm' },
  ], boq_withheld: false, concluded: false, revealed: false,
});
const gypsumHarness = () => { const h = harness(gypsumInquiry()); h.deps.read = (b, n, m) => readQuotationFile(b, n, m, ['ZZ DEMO Interiors gypsum founderdemo'], pdfModel); return h; };

Deno.test('held: with no reasoned terms the prices are still read, and the terms are asked, never read off a label', async () => {
  const read = await readQuotationFile(await fixture('ZZDEMO_quotation_D958E1EA.pdf'), 'ZZDEMO_quotation_D958E1EA.pdf', 'application/pdf', ['ZZ DEMO Interiors gypsum founderdemo'], () => Promise.resolve(null));
  assertEquals(read.proposal!.price_ex_vat, 65960);
  assertEquals([read.proposal!.validity, read.proposal!.lead_time, read.proposal!.payment_terms], ['', '', '']);
  const codes = reviewQuotation(gypsumInquiry(), workingFromProposal(read.proposal!, read.text)).issues.map((i) => i.code);
  assert(codes.includes('validity') && codes.includes('delivery'), JSON.stringify(codes));
});

Deno.test('finding 1: the auditor\'s text PDF is read — every line priced, VAT, validity and lead time seen; only what it does not say is asked', async () => {
  const pdf = await fixture('ZZDEMO_quotation_D958E1EA.pdf');
  const read = await readQuotationFile(pdf, 'ZZDEMO_quotation_D958E1EA.pdf', 'application/pdf', ['ZZ DEMO Interiors gypsum founderdemo'], pdfModel);
  assert(read.proposal, 'the PDF must yield a proposal');
  assertEquals(read.proposal.line_items.map((l) => l.amount), [30400, 27880, 7680]);
  assertEquals(read.proposal.price_ex_vat, 65960); assertEquals(read.proposal.vat_treatment, 'exclusive'); assertEquals(read.proposal.vat_amount, 3298);
  assertEquals(read.proposal.validity, '30 days'); assertEquals(read.proposal.lead_time, '4 weeks from LPO');
  assert(read.proposal.masked_terms.includes('ZZ DEMO Interiors gypsum founderdemo'), 'the letterhead name is withheld from the customer');
  const rv = reviewQuotation(gypsumInquiry(), workingFromProposal(read.proposal, read.text));
  const keys = rv.issues.map(issueKey).sort();
  // Genuinely absent from the PDF: no installation statement, no warranty, the partition board's
  // thickness (100mm is the stud, not the board) and the bulkhead's board type. Nothing else.
  assertEquals(keys, ['installation_included|||installation_included', 'spec|1||thickness_mm', 'spec|3||board_type', 'warranty_coverage|||warranty_coverage', 'warranty_period|||warranty_period'].sort(), JSON.stringify(rv.issues.map((i) => i.en)));
  assert(!rv.issues.some((i) => i.code === 'boq_line_not_priced' || i.code === 'vat_basis' || i.code === 'validity' || i.code === 'delivery'));
  // finding 13: no stud gauge and no thickness asked of the ceiling tile, none of the bulkhead
  assert(!rv.issues.some((i) => i.line_no === 2), JSON.stringify(rv.issues.filter((i) => i.line_no === 2)));
  assert(!rv.issues.some((i) => i.line_no === 3 && i.attr === 'frame'));
});

Deno.test('finding 2: prices typed in the chat — the auditor\'s grammar, the review\'s own grammar, and Arabic — price the BOQ line', () => {
  const inq = gypsumInquiry();
  const w0: Working = { ...good(), lines: [], amount: null, subtotal: null, vat_amount: null, price_ex_vat: null, vat_treatment: 'exclusive', validity: '30 days', lead_time: '4 weeks' };
  const open = reviewQuotation(inq, w0).issues;
  assertEquals(open.filter((i) => i.code === 'boq_line_not_priced').length, 3);
  const cases: [string, number, number | null, number][] = [
    ['BOQ line 1: AED 95.00 per m2 × 320 m2 = AED 30,400', 1, 95, 30400],
    ['BOQ line 2 AED 27,880 (600x600 mineral fibre)', 2, 68, 27880],
    ['البند 3: 120 درهم لكل متر = 7680 درهم', 3, 120, 7680],
    ['line 3 @ AED 120 per m', 3, 120, 7680],
  ];
  for (const [text, n, rate, amount] of cases) {
    const rr = readReply(text, open);
    const c = rr.corrections.find((x) => x.field === 'boq_price') as { boq_line: number; unit_price: number | null; amount: number | null } | undefined;
    assert(c, `no price read from "${text}": ${JSON.stringify(rr.corrections)}`);
    assertEquals(c.boq_line, n);
    const w1 = applyCorrections(w0, rr.corrections, inq.boq_rows);
    const l = w1.lines.find((x) => x.description === String(inq.boq_rows[n - 1].description))!;
    assert(l, `line ${n} not created`); assertEquals(l.amount, amount); assertEquals(l.unit_price, rate); assertEquals(l.unit, String(inq.boq_rows[n - 1].unit));
    assert(!reviewQuotation(inq, w1).issues.some((i) => i.code === 'boq_line_not_priced' && i.boq_line === n), `BOQ line ${n} still unpriced after "${text}"`);
    const said = tookSaid(rr.corrections)!; assertMatch(said.en, new RegExp(`BOQ line ${n} priced`)); assert(ARABIC.test(said.ar));
  }
  // all three in one message, and the total follows the lines
  const rr = readReply('BOQ line 1 AED 30,400; BOQ line 2 AED 27,880; BOQ line 3 AED 7,680', open);
  assertEquals(rr.corrections.filter((x) => x.field === 'boq_price').length, 3);
  const w3 = applyCorrections(w0, rr.corrections, inq.boq_rows);
  assertEquals(w3.amount, 65960);
  assert(!reviewQuotation(inq, w3).issues.some((i) => i.code === 'boq_line_not_priced' || i.code === 'total_mismatch'));
  // a priced line is no longer an excluded one
  const wx = applyCorrections(w0, readReply('BOQ line 3 excluded — by others', open).corrections, inq.boq_rows);
  assertEquals(Object.keys(wx.boq_excluded), ['3']);
  const wp = applyCorrections(wx, readReply('BOQ line 3 AED 7,680', open).corrections, inq.boq_rows);
  assertEquals(wp.boq_excluded, {}); assert(!/BOQ line 3 excluded/.test(wp.exclusions));
});

Deno.test('finding 14: several answers in one message all match, and the acknowledgement echoes each one cleanly', () => {
  const inq = gypsumInquiry();
  const w0 = good({ lines: [
    { description: 'Gypsum board partition 100mm metal stud, both faces', qty: '320', unit: 'm2', unit_price: 95, amount: 30400 },
    { description: 'Suspended false ceiling 600x600 mineral fibre', qty: '410', unit: 'm2', unit_price: 68, amount: 27880 },
    { description: 'Gypsum bulkhead 300mm drop, painted finish', qty: '64', unit: 'm', unit_price: 120, amount: 7680 },
  ], amount: 65960, price_ex_vat: 65960, warranty: '', scope: '', notes: 'Prices exclude VAT', lead_time: '4 weeks' });
  const open = reviewQuotation(inq, w0).issues;
  assertEquals(open.map(issueKey).sort(), ['installation_included|||installation_included', 'spec|1||thickness_mm', 'spec|3||board_type', 'warranty_coverage|||warranty_coverage', 'warranty_period|||warranty_period'].sort());
  const rr = readReply('line 1 thickness: 12.5mm. line 3 board type: standard gypsum board. Installation included, 4 weeks on site. Warranty 2 years parts and labour.', open);
  const fields = rr.corrections.map((c) => c.field).sort();
  assertEquals(fields, ['installation', 'line_spec', 'line_spec', 'warranty_terms']);
  const specs = rr.corrections.filter((c) => c.field === 'line_spec') as { line_no: number; attr: string; value: string }[];
  assertEquals(specs.map((s) => [s.line_no, s.attr, s.value]), [[1, 'thickness_mm', '12.5mm'], [3, 'board_type', 'standard gypsum board']]);
  const wt = rr.corrections.find((c) => c.field === 'warranty_terms') as { period: string | null; coverage: string | null };
  assertEquals(wt.period, '2 years'); assertEquals(wt.coverage, 'parts, labour');   // finding 4: not "installation, on site, parts, labour"
  const said = tookSaid(rr.corrections)!;
  assertMatch(said.en, /line 1: 12\.5mm; line 3: standard gypsum board/); assert(!/Installation included, 4 weeks on site\. Warranty/.test(said.en), 'no echoed run-on');
  const r1 = reviewQuotation(inq, applyCorrections(w0, rr.corrections, inq.boq_rows));
  assert(r1.approved, JSON.stringify(r1.issues.map((i) => i.en)));
});

Deno.test('finding 12: a revised file keeps what the chat settled; only what the new file changes is reviewed again', async () => {
  const { mem, deps, ctx } = gypsumHarness();
  const ID = GYPSUM_INQ_ID;
  await start(mem.repo, deps, ctx, ID);
  const t1 = ok(await upload(mem.repo, deps, ctx, ID, { b64: b64bytes(await fixture('ZZDEMO_quotation_D958E1EA.pdf')), filename: 'ZZDEMO_quotation_D958E1EA.pdf', mime: 'application/pdf' }));
  assertEquals(t1.state, 'changes_requested');
  assertEquals(t1.open_requests.length, 5, JSON.stringify(t1.open_requests.map((q) => q.key)));
  const t2 = ok(await message(mem.repo, deps, ctx, ID, 'Installation included, 4 weeks on site. Warranty 2 years parts and labour. line 1 thickness: 12.5mm'));
  assertEquals(t2.open_requests.map((q) => q.key), ['spec|3||board_type'], JSON.stringify(t2.open_requests));
  // the revised CSV: a Specification column, "Installation included 4 weeks", warranty — and no lead time of its own
  const t3 = ok(await upload(mem.repo, deps, ctx, ID, { b64: b64bytes(await fixture('ZZDEMO_quotation_D958E1EA.csv')), filename: 'ZZDEMO_quotation_D958E1EA.csv', mime: 'text/csv' }));
  const keys = t3.open_requests.map((q) => q.key);
  assert(!keys.some((k) => /^(validity|delivery|installation_included|warranty_period|warranty_coverage|vat_basis)\|/.test(k)), 'answered points must stay closed: ' + JSON.stringify(keys));
  assert(!keys.some((k) => k.startsWith('spec|1|') || k.startsWith('spec|2|')), 'the Specification column states lines 1 and 2: ' + JSON.stringify(keys));
  // the bulkhead's board type is the one thing neither the chat nor the file has said
  assertEquals(keys, ['spec|3||board_type']);
  const t4 = ok(await message(mem.repo, deps, ctx, ID, 'line 3 board type: standard gypsum board'));
  assertEquals(t4.state, 'awaiting_choice', JSON.stringify(t4.open_requests));
  // finding 28: "generate" produces the quotation in BOTH languages — printed for the supplier
  // first (SP-F-07, 22 Sep 2026), and the PDFs attached once the supplier submits it.
  ok(await choose(mem.repo, deps, ctx, ID, 'generate'));
  const t5 = ok(await submit(mem.repo, deps, ctx, ID));
  assertEquals(t5.state, 'submitted');
  const atts = t5.messages.find((m) => m.kind === 'submitted')!.attachments;
  assertEquals(atts.map((a) => a.lang), ['en', 'ar']);
  assert(atts.every((a) => a.kind === 'standard_quote' && a.quote_id === 'q-1'));
});

Deno.test('finding 2: every open point closes from the chat — the supplier\'s own unpriced line, the total, a named material', () => {
  const inq = gypsumInquiry();
  const panel = { description: 'Access panel 600x600 with lock', qty: '4', unit: 'nos', unit_price: null, amount: null };
  const w0 = good({ lines: [
    { description: 'Gypsum board partition 12.5mm board, 100mm metal stud, both faces', qty: '320', unit: 'm2', unit_price: 95, amount: 30400 },
    { description: 'Suspended false ceiling 600x600 mineral fibre tiles', qty: '410', unit: 'm2', unit_price: 68, amount: 27880 },
    { description: 'Gypsum bulkhead, standard gypsum board, 300mm drop, painted finish', qty: '64', unit: 'm', unit_price: 120, amount: 7680 }, panel,
  ], amount: 70000, price_ex_vat: 70000, warranty: '2 years parts and labour', scope: 'Supply and install, installation included, 4 weeks on site', notes: 'Prices exclude VAT', lead_time: '4 weeks' });
  const open = reviewQuotation(inq, w0).issues;
  assert(open.some((i) => i.code === 'line_unpriced' && i.line_no === 4), JSON.stringify(open.map(issueKey)));
  const rr = readReply('line 4 AED 150 each', open);
  assertEquals(rr.corrections, [{ field: 'line_price', line_no: 4, unit_price: 150, amount: null }]);
  const w1 = applyCorrections(w0, rr.corrections, inq.boq_rows);
  assertEquals(w1.lines[3].amount, 600); assertEquals(w1.amount, 66560);
  assert(!reviewQuotation(inq, w1).issues.some((i) => i.code === 'line_unpriced' || i.code === 'total_mismatch'));
  // a total that does not add up: re-stated, or explained by a discount
  const w2 = good({ ...w1, amount: 70000, price_ex_vat: 70000 });
  const open2 = reviewQuotation(inq, w2).issues; assert(open2.some((i) => i.code === 'total_mismatch'));
  assert(!reviewQuotation(inq, applyCorrections(w2, readReply('Total AED 66,560', open2).corrections)).issues.some((i) => i.code === 'total_mismatch'));
  const wd = applyCorrections(w2, readReply('We give a discount of AED 3,440.', open2).corrections);
  assert(!reviewQuotation(inq, wd).issues.some((i) => i.code === 'total_mismatch')); assertMatch(wd.conditions, /discount of AED 3,440/);
  // a material the customer named
  const withGlass: SafeInquiry = { ...inq, category: 'glass', boq_rows: [], spec: { customer_requirements: { version: 1, materials: [{ component: 'glass', label_en: 'Glass', label_ar: 'الزجاج' }] } } };
  const wg = good({ lines: [{ description: 'Shower screen, 8mm clear tempered, chrome hinges', qty: '1', unit: 'nos', unit_price: 9000, amount: 9000 }] });
  const og = reviewQuotation(withGlass, wg).issues.filter((i) => i.code === 'component');
  assertEquals(og.map(issueKey), ['component|||component:glass']); {
    const rg = readReply('glass: 8mm clear tempered, polished edges', og);
    const c = rg.corrections.find((x) => x.field === 'component') as { key: string; value: string } | undefined;
    assert(c, JSON.stringify({ og, rg })); assertEquals(c.key, 'glass');
    const after = reviewQuotation(withGlass, applyCorrections(wg, rg.corrections)).issues;
    assert(!after.some((i) => i.code === 'component'), JSON.stringify(after.map(issueKey)));
    assert(ARABIC.test(tookSaid(rg.corrections)!.ar));
  }
});

Deno.test('finding 4 + 28: the generated quotation says what the approval said — every check met, every line\'s spec printed, in English and Arabic', async () => {
  const { mem, deps, ctx, submitted } = gypsumHarness();
  const inq = gypsumInquiry();
  await start(mem.repo, deps, ctx, GYPSUM_INQ_ID);
  ok(await upload(mem.repo, deps, ctx, GYPSUM_INQ_ID, { b64: b64bytes(await fixture('ZZDEMO_quotation_D958E1EA.pdf')), filename: 'ZZDEMO_quotation_D958E1EA.pdf', mime: 'application/pdf' }));
  const t2 = ok(await message(mem.repo, deps, ctx, GYPSUM_INQ_ID, 'Installation included, 4 weeks on site. Warranty 2 years parts and labour. line 1 thickness: 12.5mm. line 3 board type: standard gypsum board'));
  assertEquals(t2.state, 'awaiting_choice', JSON.stringify(t2.open_requests));
  ok(await choose(mem.repo, deps, ctx, GYPSUM_INQ_ID, 'generate'));   // prints it (SP-F-07)
  ok(await submit(mem.repo, deps, ctx, GYPSUM_INQ_ID));               // the supplier approves, and only then is it sent
  const p = submitted.at(-1)! as Record<string, any>;
  // what submit_quote stores (quotes + quote_items.spec), read back the way both quote_pdf printers read it
  const q = { id: 'q-1', inquiry_id: GYPSUM_INQ_ID, supplier_id: 7, quote_amount: p.amount, price_ex_vat: p.amount, lead_time: p.lead_time, validity: p.validity, payment_terms: p.payment_terms,
    warranty: p.warranty, scope: p.scope, conditions: p.conditions, exclusions: p.exclusions, notes: p.notes, terms_spec: p.terms_spec } as any;
  const done = completenessOf(q, itemsOfRows(p.items), inq.category, inq.spec);
  assertEquals(done.items.length, 3);
  assert(done.items.every((it) => it.specs && Object.keys(it.specs).length), JSON.stringify(done.items.map((it) => it.specs)));
  assert(!/excluded/i.test(String(q.exclusions || '')), 'no line is excluded, so none is printed as excluded');
  for (const lang of ['en', 'ar'] as const) {
    const body = quoteDocument({ quote: done.quote, inquiry: { id: GYPSUM_INQ_ID, category: 'gypsum', emirate: 'Dubai', summary: null }, items: done.items, letter: 'A', lang }).body as { blocks: { t: string; items?: [string, { text: string; flag: string }][] }[] };
    const checks = body.blocks.find((b) => b.t === 'checks')!.items!;
    assertEquals(checks.map(([, c]) => c.flag), ['match', 'match', 'match', 'match'], JSON.stringify(checks));
    if (lang === 'ar') assert(checks.every(([k]) => ARABIC.test(k)), 'Arabic check labels');
  }
});

Deno.test('finding 4: a BOQ line excluded in the chat leaves the quotation and the total — never "excluded" and priced at once', async () => {
  const inq = gypsumInquiry();
  const read = await readQuotationFile(await fixture('ZZDEMO_quotation_D958E1EA.pdf'), 'ZZDEMO_quotation_D958E1EA.pdf', 'application/pdf', ['ZZ DEMO Interiors gypsum founderdemo'], pdfModel);
  const w0 = workingFromProposal(read.proposal!, read.text);
  const open = reviewQuotation(inq, w0).issues;
  const w1 = applyCorrections(w0, readReply('BOQ line 3 excluded — by others. line 1 thickness: 12.5mm', open).corrections, inq.boq_rows);
  assertEquals(w1.lines.map((l) => l.amount), [30400, 27880]);
  assertEquals(w1.amount, 58280); assertEquals(w1.price_ex_vat, 58280); assertEquals(Object.keys(w1.boq_excluded), ['3']);
  assertEquals(w1.lines[0].spec?.thickness_mm, '12.5mm');   // the spec in the same message still names line 1
  const rv = reviewQuotation(inq, w1);
  assert(!rv.issues.some((i) => ['boq_line_not_priced', 'total_mismatch', 'vat_basis', 'vat_ex_price', 'price_ex_vat'].includes(i.code)), JSON.stringify(rv.issues.map((i) => i.en)));
});

// ── Supplier audit 21 Sep 2026, findings 7 and 26 ──────────────────────────────────────────────────
Deno.test('job number: the review speaks the rfq number both portals print, not the uuid prefix', () => {
  assertEquals(jobNo({ id: 'd958e1ea-0000-4000-8000-000000000000', rfq_no: 151767 }), '151767');
  assertEquals(inquiry().job_no, '151767');
});
Deno.test('Arabic acknowledgement: a stated period is read back in Arabic ("الصلاحية 30 days" never again)', () => {
  const said = tookSaid([{ field: 'validity', value: '30 days' }, { field: 'lead_time', value: '3 weeks' }])!;
  assertStringIncludes(said.ar, 'الصلاحية 30 يومًا');
  assertStringIncludes(said.ar, 'مدة التسليم 3 أسابيع');
  assert(!/\bdays?\b|\bweeks?\b/.test(said.ar), said.ar);
  assertStringIncludes(said.en, 'validity 30 days');
});

