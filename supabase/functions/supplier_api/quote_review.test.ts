// supplier_api/quote_review.test.ts — the sales engineer's quotation review, proved in memory.
//
// Table-driven: the approved case, then each failure reason on its own, each with its English AND its
// Arabic words; the supplier's replies read by rule; and the whole conversation — incomplete file,
// points raised, answered in text, approved, "generate", submitted through submit_quote — run on the
// in-memory repository with the REAL doc_read and quote_from_document readers. No database, no network.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { sanitizeUpload, SAFE_DOCS } from '../_shared/attachment.ts';
import {
  applyCorrections, jobNo, matchBoq, normUnit, readReply, reviewQuotation, reviewSaid, sanitizeSpec, sanitizeTermsSpec,
  type IssueCode, type SafeInquiry, type Working,
} from './quote_review.ts';
import { choose, message, readQuotationFile, start, submit, submitPayload, thread, upload, type ReviewDeps, type ThreadView } from './quote_review_flow.ts';
import { memoryReviewRepo } from './quote_review_memory_repo.ts';

const INQ_ID = '3f2a9c1e-0000-4000-8000-00000000abcd';
const inquiry = (over: Partial<SafeInquiry> = {}): SafeInquiry => ({
  id: INQ_ID, job_no: jobNo(INQ_ID), category: 'painting', emirate: 'Dubai',
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
  assertMatch(s.ar, /^تمت الموافقة على عرض السعر للتقديم\./);
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
function harness(inq = inquiry()) {
  const mem = memoryReviewRepo(() => new Date('2026-09-15T10:00:00Z'));
  const submitted: Record<string, unknown>[] = [];
  const deps: ReviewDeps = {
    inquiry: (id) => Promise.resolve(id === inq.id ? inq : null),
    scan(data, filename, mime) {
      const s = sanitizeUpload({ input: data, declaredMime: mime, filename, allow: SAFE_DOCS });
      return Promise.resolve(s.ok ? { ok: true as const, bytes: s.bytes, mime: s.mime, name: filename } : { ok: false as const, status: 415, code: String(s.error), message: 'refused' });
    },
    read: (bytes, name, mime) => readQuotationFile(bytes, name, mime, ['ZZ DEMO Paint Co']),
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

  const t3 = ok(await choose(mem.repo, deps, ctx, INQ_ID, 'generate'));
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

Deno.test('the hold gate disagreeing reopens the conversation with its own list', async () => {
  const { mem, deps, ctx } = harness();
  deps.submit = () => Promise.resolve({ status: 200, json: { ok: true, held: true, accepted: false, missing: [{ scope: 'quote', line_no: null, description: null, attr: 'delivery', label_en: 'Delivery date or lead time', label_ar: 'تاريخ التسليم', type: 'text' }] } });
  await start(mem.repo, deps, ctx, INQ_ID);
  await upload(mem.repo, deps, ctx, INQ_ID, { b64: b64(COMPLETE_CSV), filename: 'q.csv', mime: 'text/csv' });
  const t = ok(await choose(mem.repo, deps, ctx, INQ_ID, 'generate'));
  assertEquals(t.state, 'changes_requested'); assert(t.open_requests.some((q) => q.code === 'delivery'));
});

Deno.test('a photo is answered, not guessed; a closed job refuses; another supplier cannot open it', async () => {
  const { mem, deps, ctx } = harness();
  await start(mem.repo, deps, ctx, INQ_ID);
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 0x90, 0x77, 0x53, 0xde]);
  const t = ok(await upload(mem.repo, deps, ctx, INQ_ID, { b64: btoa(String.fromCharCode(...png)), filename: 'photo.png', mime: 'image/png' }));
  assertEquals(t.state, 'open'); assertMatch(t.messages.at(-1)!.body_en || '', /photo or a scan/);

  const shut = harness(inquiry({ concluded: true }));
  assertEquals(((await start(shut.mem.repo, shut.deps, shut.ctx, INQ_ID)) as { code: string }).code, 'inquiry_closed');
  assertEquals(((await thread(mem.repo, deps, ctx, '11111111-1111-4111-8111-111111111111')) as { code: string }).code, 'not_found');
});

Deno.test('submitPayload carries the chat-confirmed details the hold gate reads', () => {
  const w = applyCorrections(good(), readReply('installation included, 5 working days on site', []).corrections);
  const p = submitPayload(inquiry(), { original_file_path: 'review/7/x/q.csv', original_file_name: 'q.csv' }, w, reviewQuotation(inquiry(), w));
  assertEquals((p.terms_spec as { installation?: { included: string } }).installation?.included, 'yes');
  assertEquals((p.items as { qty: number }[])[0].qty, 450);
});
