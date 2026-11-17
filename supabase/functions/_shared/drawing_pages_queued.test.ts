// The sheets of a set not checked in time are checked off the request, and the set is published only whole
// (17 Nov 2026, sales_engineer; ./drawing_pages_queued.ts). Offline: drawing_redact is a stub that records what it was sent.
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/_shared/drawing_pages_queued.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { PAGES_NEED_TIME, queuedPagesOf, redactQueuedPages, type SheetBody } from './drawing_pages_queued.ts';

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
  assertEquals(queuedPagesOf({ pagesIn: 8, seeds: [], done: DONE.slice(1), left: [6, 7], boxes: BOXES, storedAt: () => 'x' }), null, 'a sheet refused (neither verified nor held for time): the drawing stays held');
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

Deno.test('redactQueuedPages fails closed: one sheet refused, unrecorded or not read holds the whole set', async () => {
  const refused = await redactQueuedPages(Q, { originalB64: 'x', raster: async () => 'b', redact: stubRedact({ fails: 6 }).redact });
  assertEquals(refused.redaction_complete, false);
  assertEquals(refused.drawing_redacted_paths, undefined, 'no page of a held set is handed out');
  assertMatch(String(refused.held_reason), /pixels_not_clean/);
  const unrecorded = await redactQueuedPages(Q, { originalB64: 'x', raster: async () => 'b', redact: stubRedact({ unrecorded: 7 }).redact });
  assertEquals(unrecorded.redaction_complete, false);
  const unread = await redactQueuedPages(Q, { originalB64: 'x', raster: async () => { throw new Error('HTTP 404'); }, redact: stubRedact().redact });
  assertEquals(unread.redaction_complete, false);
  assertMatch(String(unread.held_reason), /sheet_not_sent/);
});

Deno.test('the queue is wired: customer_api queues only sheets held for time when every other sheet was verified; the worker and the database take the job', () => {
  const api = Deno.readTextFileSync(new URL('../customer_api/actions/documents.ts', import.meta.url));
  assertMatch(api, /if \(!pricedByCode && !isCad && path && hand\.drawing_held && serverBoxes && leftForTime\.length && leftForTime\.length === timeHeld && !redDied && redOut \+ timeHeld === redIn && /);
  assertMatch(api, /why: PAGES_NEED_TIME, boqIn: \{ queued_pages: q \}/);
  assertMatch(api, /\.\.\.pagesNote \}\);/);
  const worker = Deno.readTextFileSync(new URL('../../../scripts/cad_read_worker.ts', import.meta.url));
  assertMatch(worker, /if \(job\.why === PAGES_NEED_TIME\) \{/);
  assertMatch(worker, /redactQueuedPages\(q, \{ originalB64: b64u\(bytes\), raster, redact \}\)/);
  const sql = Deno.readTextFileSync(new URL('../../../scripts/sql/a_drawing_sheet_not_checked_in_time_is_queued_for_the_cad_reader.sql', import.meta.url));
  assert(sql.includes(`'site_photo_check', '${PAGES_NEED_TIME}'`), 'the constraint keeps every value and takes the new one');
  const portal = Deno.readTextFileSync(new URL('../../../src/components/me/NewRequest.tsx', import.meta.url));
  assertMatch(portal, /if \(res && res\.pages_job_id\) \{/);
});
