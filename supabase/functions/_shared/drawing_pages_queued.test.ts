// The sheets of a set not verified in the request (held for time, lost to a 546, held for a transient reason) are checked off
// the request, a sheet refused for identity is not, and the set is published only whole (17 Nov 2026, sales_engineer;
// ./drawing_pages_queued.ts). Offline: drawing_redact is a stub that records what it was sent.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/_shared/drawing_pages_queued.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { PAGES_NEED_TIME, REFUSED_FOR_IDENTITY, SHEET_TRIES, queuedPagesOf, redactQueuedPages, sheetVerdict, sheetsToCheckOff, type QueuedPages, type SheetBody } from './drawing_pages_queued.ts';

const box = (x: number) => [{ x, y: 0, w: 0.1, h: 1 }];
const BOXES = Array.from({ length: 8 }, (_x, i) => box(0.8 + i / 100));
const DONE = [0, 1, 2, 3, 4, 5].map((page) => ({ page, paths: [`redacted/u${page}/page_p0.jpg`], job: `run-${page}` }));

Deno.test('queuedPagesOf: the sheets left for time, each with its stored raster and the SERVER\'s boxes; null whenever the set could not be finished', () => {
  const q = queuedPagesOf({ pagesIn: 8, seeds: ['ZZ DEMO'], done: DONE, left: [7, 6], boxes: BOXES, storedAt: (p) => `drawings/zz/sheet_${p + 1}.jpg` });
  assert(q);
  assertEquals(q.left.map((s) => s.page), [6, 7]);
  assertEquals(q.left[0].boxes, BOXES[6]);
  assertEquals(q.left[1].path, 'drawings/zz/sheet_8.jpg');
  assertEquals(q.done.length, 6);
  assertEquals(queuedPagesOf({ pagesIn: 8, seeds: [], done: DONE.slice(1), left: [6, 7], boxes: BOXES, storedAt: () => 'x' }), null, 'the count does not add up (a refused sheet is in neither list): the drawing stays held');
  assertEquals(queuedPagesOf({ pagesIn: 8, seeds: [], done: DONE.slice(0, 5), left: [5, 6, 6], boxes: BOXES, storedAt: () => 'x' }), null, 'a sheet twice is never queued');
  assertEquals(queuedPagesOf({ pagesIn: 8, seeds: [], done: DONE, left: [6, 7], boxes: null, storedAt: () => 'x' }), null, 'no server boxes: nothing may be checked off the request');
  assertEquals(queuedPagesOf({ pagesIn: 8, seeds: [], done: DONE, left: [6, 7], boxes: BOXES, storedAt: (p) => p === 7 ? null : 'x' }), null, 'a sheet not stored');
  assertEquals(queuedPagesOf({ pagesIn: 6, seeds: [], done: DONE, left: [], boxes: BOXES, storedAt: () => 'x' }), null, 'nothing left');
});

function stubRedact(o: { fails?: number; unrecorded?: number } = {}) {
  const sent: SheetBody[] = [];
  const redact = async (b: SheetBody) => {
    sent.push(b);
    if (b.page_offset === o.fails) return { ok: true, recorded: true, pages_out: 0, paths: [], job_id: 'held', verify_detail: [{ page: 0, skipped: 'pixels_not_clean' }] };
    return { ok: true, recorded: b.page_offset !== o.unrecorded, pages_out: 1, paths: [`redacted/n${b.page_offset}/page_p0.jpg`], job_id: `run-${b.page_offset}` };
  };
  return { sent, redact };
}
const Q = queuedPagesOf({ pagesIn: 8, seeds: ['ZZ DEMO'], done: DONE, left: [6, 7], boxes: BOXES, storedAt: (p) => `drawings/zz/sheet_${p + 1}.jpg` })!;

Deno.test('redactQueuedPages: every sheet left verified -> the WHOLE set, every sheet in page order, every run named', async () => {
  const s = stubRedact();
  const out = await redactQueuedPages(Q, { originalB64: 'JVBERi0x', raster: async (p) => 'b64:' + p, redact: s.redact });
  assertEquals(out.redaction_complete, true);
  assertEquals(out.drawing_redacted_paths, [...DONE.map((d) => d.paths[0]), 'redacted/n6/page_p0.jpg', 'redacted/n7/page_p0.jpg']);
  assertEquals(out.redaction_job_ids, ['run-0', 'run-1', 'run-2', 'run-3', 'run-4', 'run-5', 'run-6', 'run-7']);
  // Each sheet is ONE manual-path call with the server's boxes for it, its own page number and the original for its text layer.
  assertEquals(s.sent.map((b) => [b.page_offset, b.images.length, b.manual_boxes[0]]), [[6, 1, BOXES[6]], [7, 1, BOXES[7]]]);
  assertEquals(s.sent[0].images[0].data, 'b64:drawings/zz/sheet_7.jpg');
  assertEquals(s.sent[0].original_b64, 'JVBERi0x');
  assertEquals(s.sent[0].seed_terms, ['ZZ DEMO']);
});

// ── THE PAID PROOF OF 17 NOV 19:11 UTC (6244a525) ────────────────────────────────────────────────────────────────────
// What drawing_redact answered for the 8 sheets: 7 x HTTP 546 (the gateway's JSON, no pages_in), 1 x 200 with the sheet not
// verified. Before this change only a sheet held for TIME was queued, so this set queued nothing.
const DIED_546 = { code: 'WORKER_RESOURCE_LIMIT', message: 'Worker failed to boot or ran out of resources' };
const VERIFIED = (p: number) => ({ ok: true, recorded: true, pages_in: 1, pages_out: 1, paths: [`redacted/v${p}/page_p0.jpg`], job_id: `run-${p}`, verify_detail: [{ page: 0 }] });
const HELD = (skipped: string, extra: Record<string, unknown> = {}) => ({ ok: true, recorded: true, pages_in: 1, pages_out: 0, paths: [], job_id: 'held', skipped: 1, verify_detail: [{ page: 0, skipped }], ...extra });

Deno.test('sheetVerdict: a sheet LOST to a 546, a timeout or no answer is retried, never released and never refused', () => {
  assertEquals(sheetVerdict(DIED_546), { state: 'retry', why: 'lost' });
  assertEquals(sheetVerdict(null), { state: 'retry', why: 'lost' });
  assertEquals(sheetVerdict({ ok: false, error: 'boom' }), { state: 'retry', why: 'lost' });
  assertEquals(sheetVerdict(VERIFIED(3)), { state: 'verified', paths: ['redacted/v3/page_p0.jpg'], job: 'run-3' });
  assertEquals(sheetVerdict({ ...VERIFIED(3), recorded: false }), { state: 'retry', why: 'unrecorded' }, 'a page not recorded cannot be resolved at Send');
  assertEquals(sheetVerdict(HELD('time', { time_held: 1, time_held_pages: [0] })), { state: 'retry', why: 'time' });
  for (const why of ['pixels_unverified', 'paint_failed', 'decode_failed', 'upload_failed']) assertEquals(sheetVerdict(HELD(why)).state, 'retry', why);
});

Deno.test('sheetVerdict: a sheet the checker REFUSED for identity is a finding (held, not retried); a budget or reader refusal is held too; an unknown reason fails closed', () => {
  for (const why of REFUSED_FOR_IDENTITY) assertEquals(sheetVerdict(HELD(why)), { state: 'refused', why, identity: true });
  assertEquals(sheetVerdict({ ...HELD('x'), verify_detail: [{ page: 0, attempts: 2, found: ['ZZ DEMO CONSULTING'] }] }), { state: 'refused', why: 'pixels_not_clean', identity: true }, 'the model path names what it found');
  assertEquals(sheetVerdict(HELD('pixels_budget', { customer_message: { en: 'x' } })), { state: 'refused', why: 'pixels_budget', identity: false });
  assertEquals(sheetVerdict(HELD('reader_disagrees_with_pdf')), { state: 'refused', why: 'reader_disagrees_with_pdf', identity: false });
  assertEquals(sheetVerdict(HELD('something_new')).state, 'refused', 'a reason nobody sorted is held, not retried blindly');
});

Deno.test('sheetsToCheckOff: the proof\'s set (7 lost, 1 unverified) is queued WHOLE; one identity refusal queues nothing and names the sheet', () => {
  const proof = [DIED_546, DIED_546, DIED_546, HELD('pixels_unverified'), DIED_546, DIED_546, DIED_546, DIED_546].map(sheetVerdict);
  const p = sheetsToCheckOff(proof, 8);
  assertEquals(p.left.map((l) => l.page), [0, 1, 2, 3, 4, 5, 6, 7]);
  assertEquals(p.left[3].why, 'pixels_unverified');
  assertEquals(p.refused, []);
  const mixed = sheetsToCheckOff([VERIFIED(0), VERIFIED(1), HELD('time', { time_held: 1 }), DIED_546].map(sheetVerdict).concat([undefined as never]), 5);
  assertEquals(mixed.verified, [0, 1]);
  assertEquals(mixed.left, [{ page: 2, why: 'time' }, { page: 3, why: 'lost' }, { page: 4, why: 'lost' }], 'a sheet never answered is lost');
  const leak = sheetsToCheckOff([VERIFIED(0), DIED_546, HELD('pixels_not_clean')].map(sheetVerdict), 3);
  assertEquals(leak.left, [], 'nothing is queued when a sheet is refused');
  assertEquals(leak.refused, [{ page: 2, why: 'pixels_not_clean', identity: true }]);
});

function scripted(answers: Record<number, unknown[]>) {
  const sent: SheetBody[] = [];
  const redact = async (b: SheetBody) => { sent.push(b); const a = answers[b.page_offset] ?? []; const next = a.length > 1 ? a.shift() : a[0]; if (next instanceof Error) throw next; return next ?? VERIFIED(b.page_offset); };
  return { sent, redact };
}
const noWait = async () => {};

Deno.test('redactQueuedPages: a sheet lost to a 546 is asked again and the set is published when it passes; each verified sheet is kept as it goes', async () => {
  const s = scripted({ 6: [DIED_546, DIED_546, VERIFIED(6)] });
  const kept: QueuedPages[] = [];
  const out = await redactQueuedPages(Q, { originalB64: 'x', raster: async () => 'b', redact: s.redact, wait: noWait, progress: async (q) => { kept.push(q); } });
  assertEquals(out.redaction_complete, true);
  assertEquals(s.sent.map((b) => b.page_offset), [6, 6, 6, 7]);
  assertEquals(out.redaction_job_ids, ['run-0', 'run-1', 'run-2', 'run-3', 'run-4', 'run-5', 'run-6', 'run-7']);
  assertEquals(kept.map((q) => [q.done.length, q.left.map((l) => l.page)]), [[7, [7]], [8, []]], 'sheet 7 and then 8 are kept on the job');
});

Deno.test('redactQueuedPages: a sheet REFUSED for identity is asked once and holds the set; a sheet still lost after SHEET_TRIES goes back to the queue', async () => {
  const leak = scripted({ 6: [HELD('pixels_not_clean')] });
  const refused = await redactQueuedPages(Q, { originalB64: 'x', raster: async () => 'b', redact: leak.redact, wait: noWait });
  assertEquals(refused.redaction_complete, false);
  assertEquals(refused.drawing_redacted_paths, undefined, 'no page of a held set is handed out');
  assertEquals(refused.held_identity, true);
  assertMatch(String(refused.held_reason), /pixels_not_clean/);
  assertEquals(leak.sent.length, 1, 'not retried blindly');
  const dead = scripted({ 7: [DIED_546] });
  const later = await redactQueuedPages(Q, { originalB64: 'x', raster: async () => 'b', redact: dead.redact, wait: noWait });
  assertEquals(later.redaction_complete, false);
  assertEquals(later.retry_later, true);
  assertEquals(dead.sent.filter((b) => b.page_offset === 7).length, SHEET_TRIES);
  const unread = await redactQueuedPages(Q, { originalB64: 'x', raster: async () => { throw new Error('HTTP 404'); }, redact: scripted({}).redact, wait: noWait });
  assertEquals(unread.retry_later, true);
  assertMatch(String(unread.held_reason), /sheet_not_sent/);
  const unrecorded = await redactQueuedPages(Q, { originalB64: 'x', raster: async () => 'b', redact: scripted({ 7: [{ ...VERIFIED(7), recorded: false }] }).redact, wait: noWait });
  assertEquals(unrecorded.redaction_complete, false, 'never published unrecorded');
});

Deno.test('redactQueuedPages: a job whose every sheet was kept before its run was cut completes at once, asking nothing', async () => {
  const s = scripted({});
  const all = { ...Q, done: [...Q.done, { page: 6, paths: ['redacted/n6/page_p0.jpg'], job: 'run-6' }, { page: 7, paths: ['redacted/n7/page_p0.jpg'], job: 'run-7' }], left: [] };
  const out = await redactQueuedPages(all, { originalB64: 'x', raster: async () => 'b', redact: s.redact, wait: noWait });
  assertEquals(out.redaction_complete, true);
  assertEquals(s.sent.length, 0);
});

Deno.test('the queue is wired: customer_api queues every sheet it did not verify unless one was refused, once per drawing; the worker retries, keeps and attaches', () => {
  const api = Deno.readTextFileSync(new URL('../customer_api/actions/documents.ts', import.meta.url));
  assertMatch(api, /verdictOf\[b\] = sheetVerdict\(rj\);/);
  assertMatch(api, /verdictOf\[b\] = \{ state: 'retry', why: clock \? 'time' : 'lost' \};/, 'a call that threw is lost (or time), never dropped');
  assertMatch(api, /const sorted = sheetsToCheckOff\(verdictOf, batches\);/);
  assertMatch(api, /if \(!pricedByCode && !isCad && path && hand\.drawing_held && serverBoxes && !scanJob && !refusedPages\.length && leftToCheck\.length && /);
  assert(!/!redDied && redOut \+ timeHeld === redIn/.test(api), 'a sheet lost to the edge is no longer a reason not to queue');
  assertMatch(api, /pagesJob = await queuePagesOnce\(/);
  assertMatch(api, /\.\.\.pagesNote \}\);/);
  const lib = Deno.readTextFileSync(new URL('../customer_api/lib/drawings.ts', import.meta.url));
  assertMatch(lib, /export async function queuePagesOnce[\s\S]{0,900}\.eq\('why', PAGES_NEED_TIME\)\.in\('status', \['queued', 'running'\]\)/);
  const worker = Deno.readTextFileSync(new URL('../../../scripts/cad_read_worker.ts', import.meta.url));
  assertMatch(worker, /if \(job\.why === PAGES_NEED_TIME\) \{/);
  assertMatch(worker, /redactQueuedPages\(q, \{ originalB64: b64u\(bytes\), raster, redact, progress \}\)/);
  assertMatch(worker, /if \(drawing\.retry_later === true\) throw new Error/);
  assertMatch(worker, /const stmt = pagesReachTheirRequestsSql\(job, /);
  const sql = Deno.readTextFileSync(new URL('../../../scripts/sql/a_drawing_sheet_not_checked_in_time_is_queued_for_the_cad_reader.sql', import.meta.url));
  assert(sql.includes(`'site_photo_check', '${PAGES_NEED_TIME}'`), 'the constraint keeps every value and takes the new one');
  const once = Deno.readTextFileSync(new URL('../../../scripts/sql/a_drawing_sheet_is_queued_once.sql', import.meta.url));
  assertMatch(once, /create unique index if not exists cad_read_jobs_one_open_pages_job\s+on public\.cad_read_jobs \(source_path\)\s+where why = 'pages_need_time' and status in \('queued', 'running'\);/);
  const portal = Deno.readTextFileSync(new URL('../../../src/components/me/NewRequest.tsx', import.meta.url));
  assertMatch(portal, /if \(res && res\.pages_job_id\) \{/);
});
