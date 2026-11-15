// supplier_api/the_comparison_points_are_answered_only_by_the_supplier.test.ts — the points the comparison asks a supplier to
// confirm are closed only by his answer. Seat: sales_engineer. 15 Nov 2026 (CEO, under founder ruling 1696; final review of
// the comparison branch, REVIEW_compare_vat_final FIX 1).
//
// THE FINDING. quote_compare wrote a code-made engineer message into the supplier's quotation conversation (rulings 1195-1197
// and 1339: an engineer message there is a model's turn), into conversations that were all `submitted` and refused every
// supplier write, and the review's auto-close then marked the points answered with no answer. Now the comparison hands the
// points to the sales engineer (request_fit.ts pointsHandoff -> fn_seat_handoff), whose handler records each as an open
// clarification with code comparison_point (scripts/sql/the_comparison_hands_its_open_points_to_the_sales_engineer.sql).
// Here, on the in-memory repository with a faked model: the points are raised by the model's turns, a submitted conversation
// takes the supplier's text answer and nothing else, the review and the submission never close them, and only an answer the
// model reads and code checks closes them, with his message, which is what quote_compare shows the customer.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/supplier_api/the_comparison_points_are_answered_only_by_the_supplier.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { sanitizeUpload, SAFE_DOCS } from '../_shared/attachment.ts';
import { jobNo, type SafeInquiry } from './quote_review.ts';
import { choose, message, readQuotationFile, start, submit, thread, upload, type ReviewDeps, type ThreadView } from './quote_review_flow.ts';
import { memoryReviewRepo } from './quote_review_memory_repo.ts';
import { readFixture } from './review_reading.fixture.ts';
import { POINT_CODE } from '../_shared/comparison_points.ts';

const INQ_ID = '3f2a9c1e-0000-4000-8000-00000000c0c0';
const inquiry = (over: Partial<SafeInquiry> = {}): SafeInquiry => ({
  id: INQ_ID, job_no: jobNo({ id: INQ_ID, rfq_no: 151768 }), category: 'painting', emirate: 'Dubai',
  spec: { customer_requirements: { version: 1, installation: { required: 'no' }, warranty: { required: 'yes' } } },
  boq_rows: [{ description: 'Internal wall painting emulsion', qty: 450, unit: 'm2' }], boq_withheld: false, concluded: false, revealed: false, ...over,
});
const b64 = (s: string) => btoa(String.fromCharCode(...new TextEncoder().encode(s)));
const CSV = 'Description,Qty,Unit,Rate,Amount\nJotun Fenomastic emulsion 2 coats internal walls,450,m2,20,9000\nTotal,,,,9000\n';
const TERMS = { validity: '30 days', lead_time: '3 weeks', warranty: '2 years materials and workmanship' };
const POINT = 'The request names a site visit before a final price. Please confirm whether your price is final or subject to that visit.';
const ok = (v: unknown): ThreadView => { assert((v as ThreadView).ok, JSON.stringify(v)); return v as ThreadView; };

function harness(inq: { v: SafeInquiry }) {
  const mem = memoryReviewRepo(() => new Date('2026-11-15T10:00:00Z'));
  const written: string[] = []; const voices: Parameters<ReviewDeps['voice']>[0][] = []; const answered: string[] = [];
  // the model's reading of "does this message answer the points?", and the words it cites; null: it does not
  const model: { cite: (m: string) => string | null } = { cite: (m) => (/\bfinal\b/i.test(m) ? (m.match(/[^.]*\bfinal\b[^.]*/i)?.[0] ?? null) : null) };
  const deps: ReviewDeps = {
    inquiry: (id) => Promise.resolve(id === inq.v.id ? inq.v : null),
    scan(data, filename, mime) {
      const s = sanitizeUpload({ input: data, declaredMime: mime, filename, allow: SAFE_DOCS });
      return Promise.resolve(s.ok ? { ok: true as const, bytes: s.bytes, mime: s.mime, name: filename } : { ok: false as const, status: 415, code: String(s.error), message: 'refused' });
    },
    read: (bytes, name, mime) => readQuotationFile(bytes, name, mime, ['ZZ DEMO Paint Co'], () => Promise.resolve(TERMS)),
    submit: () => Promise.resolve({ status: 200, json: { ok: true, accepted: true, quote: { id: 'q-1', option_no: 1, status: 'submitted' } } }),
    quotePdf: () => Promise.resolve({ url: null, ref: 'QD-3F2A9C1E-S' }),
    now: () => new Date('2026-11-15T10:00:00Z'),
    readWorking: (i, w) => Promise.resolve(readFixture(i, w)),
    hold: () => Promise.resolve(),
    // THE MODEL, faked: it writes the engineer's message from the situation, and picks the supplier's next step from his words
    voice: (v) => {
      voices.push(v); const t = '[sales engineer] ' + v.situation; written.push(t);
      const m = String(v.supplierMessage || ''); const ids = (v.actions || []).map((x) => x.id);
      if (ids.includes('answer_points')) { const w = model.cite(m); if (w) return Promise.resolve({ text: t, action: 'answer_points', action_words: w }); }
      const action = ids.includes('submit') && /submit/i.test(m) ? 'submit' : ids.includes('generate') && /generat/i.test(m) ? 'generate' : null;
      return Promise.resolve({ text: t, action });
    },
  };
  mem.repo.pointsAnswered = (rid) => { answered.push(rid); return Promise.resolve(); };
  return { mem, deps, written, voices, answered, model, ctx: { supplierId: 7, email: 'qd-test-sup1@example.invalid', lang: 'en' as const } };
}
/** What the hand-over's handler writes (the SQL routine): one open clarification per point, no message. */
async function raise(h: ReturnType<typeof harness>, label = POINT) {
  const r = h.mem.reviews[0];
  await h.mem.repo.addRequests([{ review_id: r.id, key: 'comparison:' + label.toLowerCase().replace(/[^a-z0-9]+/g, '_').slice(0, 80), code: POINT_CODE, kind: 'clarification', line_no: null, boq_line: null, attr: null, label_en: label, label_ar: label, asked_message_id: null }]);
}
async function toSubmitted(h: ReturnType<typeof harness>) {
  ok(await start(h.mem.repo, h.deps, h.ctx, INQ_ID));
  ok(await upload(h.mem.repo, h.deps, h.ctx, INQ_ID, { b64: b64(CSV), filename: 'quote.csv', mime: 'text/csv' }));
  ok(await message(h.mem.repo, h.deps, h.ctx, INQ_ID, 'validity 30 days. lead time 3 weeks. prices exclude VAT. warranty 2 years covering materials and workmanship'));
  ok(await choose(h.mem.repo, h.deps, h.ctx, INQ_ID, 'generate'));
  const t = ok(await submit(h.mem.repo, h.deps, h.ctx, INQ_ID));
  assertEquals(t.state, 'submitted');
  return t;
}

Deno.test('a submitted conversation takes his text answer to an open comparison point, and nothing else', async () => {
  const inq = { v: inquiry() }; const h = harness(inq);
  await toSubmitted(h);
  const before = h.mem.messages.length;
  await raise(h);
  // the handler wrote no message: nothing is said before the rows exist, and code never writes the engineer's words
  assertEquals(h.mem.messages.length, before);
  const t0 = ok(await thread(h.mem.repo, h.deps, h.ctx, INQ_ID));
  assertEquals([t0.state, t0.can_write, t0.can_upload, t0.can_submit], ['submitted', true, false, false]);
  assertEquals(t0.open_requests.map((q) => q.code), [POINT_CODE]);
  // a file, or a new submission, is still refused: only his text answer is taken
  assertEquals((await upload(h.mem.repo, h.deps, h.ctx, INQ_ID, { b64: b64(CSV), filename: 'quote2.csv', mime: 'text/csv' }) as { code?: string }).code, 'review_closed');
  assertEquals((await submit(h.mem.repo, h.deps, h.ctx, INQ_ID) as { code?: string }).code, 'review_closed');

  // a message that does not answer: the point stays open, the review is not re-run, the reply is the model's
  const t1 = ok(await message(h.mem.repo, h.deps, h.ctx, INQ_ID, 'Which site visit do you mean?'));
  assertEquals([t1.state, t1.open_requests.length], ['submitted', 1]);
  const said = h.voices[h.voices.length - 1];
  assert(said.situation.includes(POINT) && said.situation.includes('submitted to the customer'), 'the model is told the point, to raise it');
  assert((said.actions || []).some((a) => a.id === 'answer_points'));
  const eng = t1.messages.filter((m) => m.role === 'sales_engineer');
  assert(eng.every((m) => h.written.includes(m.body_en!) || m.kind === 'submitted'), 'every engineer message is the model\'s (1195-1197)');

  // the model cites words that are not his: nothing is closed
  h.model.cite = () => 'the price is final';
  const t2 = ok(await message(h.mem.repo, h.deps, h.ctx, INQ_ID, 'We will see.'));
  assertEquals(t2.open_requests.length, 1);
  h.model.cite = (m) => (/\bfinal\b/i.test(m) ? (m.match(/[^.]*\bfinal\b[^.]*/i)?.[0] ?? null) : null);

  // his answer: the point is closed by his message, the hand-over is told, and he can no longer write
  const t3 = ok(await message(h.mem.repo, h.deps, h.ctx, INQ_ID, 'Our price is final. No site visit is needed for this scope.'));
  const pt = h.mem.requests.find((q) => q.code === POINT_CODE)!;
  const his = h.mem.messages.find((m) => m.role === 'supplier' && m.body === 'Our price is final. No site visit is needed for this scope.')!;
  assertEquals([pt.state, pt.answered_message_id], ['answered', his.id]);
  assertEquals(h.answered, [h.mem.reviews[0].id]);
  assertEquals([t3.state, t3.can_write, t3.open_requests.length], ['submitted', false, 0]);
  assertEquals((await message(h.mem.repo, h.deps, h.ctx, INQ_ID, 'one more thing') as { code?: string }).code, 'review_closed');
});

Deno.test('the review and the submission never close a comparison point; only his answer does', async () => {
  const inq = { v: inquiry() }; const h = harness(inq);
  ok(await start(h.mem.repo, h.deps, h.ctx, INQ_ID));
  ok(await upload(h.mem.repo, h.deps, h.ctx, INQ_ID, { b64: b64(CSV), filename: 'quote.csv', mime: 'text/csv' }));
  await raise(h);
  // in a writable conversation the model's turn is told the point, to raise it with him
  ok(await message(h.mem.repo, h.deps, h.ctx, INQ_ID, 'Hello, is anything else needed from us?'));
  assert(h.voices[h.voices.length - 1].situation.includes(POINT), 'the model\'s turns are told the point');
  assertEquals(h.mem.requests.find((q) => q.code === POINT_CODE)!.state, 'open');
  // the supplier answers the review's own points: the review re-runs and closes them, never the comparison point (upload.ts)
  const t1 = ok(await message(h.mem.repo, h.deps, h.ctx, INQ_ID, 'validity 30 days. lead time 3 weeks. prices exclude VAT. warranty 2 years covering materials and workmanship'));
  assertEquals(t1.state, 'awaiting_choice');
  assert(h.mem.requests.filter((q) => q.code !== POINT_CODE && q.kind !== 'choice').every((q) => q.state === 'answered'), 'the review closed its own points');
  assertEquals(h.mem.requests.find((q) => q.code === POINT_CODE)!.state, 'open');
  ok(await choose(h.mem.repo, h.deps, h.ctx, INQ_ID, 'generate'));
  // the submission closes every other open request, never this one (submit.ts)
  ok(await submit(h.mem.repo, h.deps, h.ctx, INQ_ID));
  assertEquals(h.mem.requests.find((q) => q.code === POINT_CODE)!.state, 'open');
  ok(await message(h.mem.repo, h.deps, h.ctx, INQ_ID, 'Yes, the price is final.'));
  assertEquals(h.mem.requests.find((q) => q.code === POINT_CODE)!.state, 'answered');
});

Deno.test('after the reveal nothing is taken, and nothing is raised (the job is closed)', async () => {
  const inq = { v: inquiry() }; const h = harness(inq);
  await toSubmitted(h);
  await raise(h);
  inq.v = inquiry({ revealed: true });
  const t = ok(await thread(h.mem.repo, h.deps, h.ctx, INQ_ID));
  assertEquals(t.can_write, false);
  assertEquals((await message(h.mem.repo, h.deps, h.ctx, INQ_ID, 'Our price is final.') as { code?: string }).code, 'inquiry_closed');
  assertEquals(h.mem.requests.find((q) => q.code === POINT_CODE)!.state, 'open');
});

Deno.test('a point superseded at the decision is asked no more: the submitted conversation closes again and the model is not told it', async () => {
  // COMPARE4 gap 2: the database supersedes every open point the moment the customer reveals a supplier or the request ends
  // (fn_sales_engineer_comparison_points_supersede). Even before this conversation reads the request as closed, a superseded
  // point is not open: nothing reopens the submitted conversation for it, and no model turn raises it.
  const inq = { v: inquiry() }; const h = harness(inq);
  await toSubmitted(h);
  await raise(h);
  assertEquals(ok(await thread(h.mem.repo, h.deps, h.ctx, INQ_ID)).can_write, true);
  const pt = h.mem.requests.find((q) => q.code === POINT_CODE)!;
  await h.mem.repo.closeRequests([pt.id], 'superseded', null);
  const t = ok(await thread(h.mem.repo, h.deps, h.ctx, INQ_ID));
  assertEquals([t.state, t.can_write, t.open_requests.length], ['submitted', false, 0]);
  const voicesBefore = h.voices.length;
  assertEquals((await message(h.mem.repo, h.deps, h.ctx, INQ_ID, 'Our price is final.') as { code?: string }).code, 'review_closed');
  assert(h.voices.slice(voicesBefore).every((v) => !v.situation.includes(POINT)), 'no model turn raises a superseded point');
  assertEquals([h.mem.requests.find((q) => q.code === POINT_CODE)!.state, h.answered.length], ['superseded', 0]);
});

Deno.test('quote_compare writes no engineer message and no request row: it files the hand-over, and its handler writes the rows', async () => {
  const src = await Deno.readTextFile(new URL('../quote_compare/index.ts', import.meta.url));
  assert(!/from\('quote_review_messages'\)\s*\.insert/.test(src), 'quote_compare inserts an engineer message');
  assert(!/from\('quote_review_request'\)\s*\.insert/.test(src), 'quote_compare inserts request rows outside the hand-over');
  assert(/rpc\('fn_seat_handoff', args\)/.test(src) && /mayRaisePoints\(inq, revealedAny\)/.test(src), 'the hand-over is filed, guarded by the reveal');
  const sql = await Deno.readTextFile(new URL('../../../scripts/sql/the_comparison_hands_its_open_points_to_the_sales_engineer.sql', import.meta.url));
  assert(/insert into public\.quote_review_request/.test(sql) && !/insert into public\.quote_review_messages/.test(sql), 'the handler writes rows, never a message');
  assert(/'revealed', 'completed', 'closed', 'cancelled', 'expired', 'lost'/.test(sql) && /revealed_at is not null/.test(sql), 'the handler checks the reveal and the end of the request again');
  assert(/revoke execute on function public\.fn_sales_engineer_comparison_points_raise\(bigint\)/.test(sql) && /revoke execute on function public\.fn_sales_engineer_comparison_points_answered\(uuid\)/.test(sql));
  assert(/set search_path to 'public', 'pg_temp'/.test(sql));
});
