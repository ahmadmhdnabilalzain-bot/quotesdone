// A SCANNED DRAWING IS REDACTED BY OCR, OR HELD (24 Sep 2026, sales_engineer; founder instruction 579: "OCR for
// scanned drawings", and 580 / 703: nothing identifying reaches a supplier, the drawing is not damaged).
//
// MEASURED: a page with no text layer (a scanned PDF, a photo) was held by the edge every time, and no path ever
// released it. The proof that the OCR path works is supabase/functions/_shared/scan_redact.check.ts (the real
// engine) and scan_redact.test.ts (the decisions). This check pins the WIRING and the fail-closed rules, so the
// path cannot be disconnected or loosened quietly.
//
//   node --test scripts/checks/a_scanned_drawing_is_redacted_by_ocr_or_held.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { functionSource } from '../lib/function_sources.mjs';
import { readSource } from '../lib/portal_sources.mjs';

const read = (p) => readFileSync(new URL('../../' + p, import.meta.url), 'utf8');
const api = functionSource('customer_api');
const worker = read('scripts/cad_read_worker.ts');
const scan = read('supabase/functions/_shared/scan_redact.ts');
const engine = read('scripts/lib/scan_ocr.ts');
const portal = readSource('src/components/me/NewRequest.tsx');
const checks = read('.github/workflows/checks.yml');
const SQL = 'scripts/sql/a_scanned_drawing_is_queued_for_ocr_redaction.sql';

test('customer_api queues a held scan or photo, page rasters stored like any original, and says so', () => {
  const block = api.slice(api.indexOf("action === 'analyze_drawing'"), api.indexOf("action === 'create_inquiry'"));
  assert.ok(block.includes('hand.drawing_held && path && !isCad && images.length && (/^image\\//i.test(mime) || pdfWords === 0)'), 'the scan queue no longer fires on exactly a held page with no text layer');
  assert.ok(block.includes("storeOriginal(cust.id, email, `scan_page_${i + 1}.jpg`, 'image/jpeg', b64, SAFE_UPLOAD)"), 'the page rasters are not stored like an original');
  assert.ok(block.includes("why: 'scan_needs_ocr', boqIn: { scan_pages: pagePaths }"));
  assert.ok(block.includes("note: 'scan_queued', cad_job_id: scanJob"));
  assert.ok(portal.includes("res.note === 'scan_queued' && res.cad_job_id) pollScan("), 'the portal never picks up the redacted scan');
});

test('the worker OCRs with the pinned free engine and publishes only a proved-clean page, as a recorded run', () => {
  assert.ok(worker.includes("if (job.why === 'scan_needs_ocr')"));
  assert.ok(worker.includes("tesseractOcr('eng+ara')"));
  assert.ok(worker.includes("if (!out.ok) return { redaction_complete: false"), 'one held page must publish none');
  assert.ok(worker.includes("return publishPages(job, key, jpgs, { method: 'scan_ocr'"));
  // The scanned take-off is extra: if it throws, the BOQ is omitted and the pages still publish (review of #1056).
  assert.match(worker, /try \{ boq = \(await scanTakeoff\(imgs, engine\.ocr\)\)\.boq; \}\s*catch \(e\) \{ boq = null;/, 'a failing scanned take-off can take the redacted pages down with it');
  const pub = worker.slice(worker.indexOf('async function publishPages'), worker.indexOf('async function supplierDrawing'));
  assert.match(pub, /insert into public\.drawing_redaction_runs[\s\S]{0,500}'complete'/);
  assert.match(pub, /catch \(e\) \{\s*await removeObjects\(key, paths\)/, 'an unrecorded upload is not removed');
  assert.ok(engine.includes('npm:tesseract.js@7.0.0'), 'the OCR engine is no longer the pinned free one');
  assert.ok(engine.includes('public/ocr/lang'), "the language data is no longer the repository's own");
});

test('the fail-closed rules stand: no title block, a low-confidence title block, and a dirty re-read all hold', () => {
  assert.ok(scan.includes('export const MIN_TITLE_CONF = 70;'));
  assert.ok(scan.includes("if (!strip || tb.confidence !== 'medium') return { ok: false, held: 'no_title_block_found'"));
  assert.ok(scan.includes("if (titleConf < MIN_TITLE_CONF) return { ok: false, held: 'title_block_low_confidence'"));
  // 13 Nov 2026: the re-read is at the page's own magnification, and a vocabulary-only span is removed and read again.
  assert.ok(scan.includes('let second = standing(await readAllWays(painted, ocr, pk));'), 'the painted page is no longer re-read every way up');
  assert.ok(scan.includes("if (ident.length) return { ok: false, held: 'identity_survived_reocr'"));
  // Second review of #967: fail closed. Every quarter turn is read, a word outside the vocabulary is boxed, and
  // text-like ink no read word covers holds the page.
  assert.ok(scan.includes('for (const q of [0, 1, 2, 3])'), 'the page is no longer OCRed at all four orientations');
  // 13 Nov 2026 (anonymity audit B): every standing reading AND every upright reading is judged, and a place below the
  // emirate is boxed with the parties.
  assert.ok(scan.includes('const pageWide = [...new Set([...stood, ...first])].filter((l) => party(l.text) || drawingLocation(l.text) || notContent(l))'), 'a line that is not drawing content is no longer boxed');
  assert.ok(scan.includes("if (unread.length) return { ok: false, held: 'unread_ink'"), 'unread text-like ink no longer holds the page');
  assert.match(checks, /--allow-env\s+--allow-net=deno\.land\s+supabase\/functions\/_shared\/scan_redact\.check\.ts/, 'the real-engine check is not run in CI');
});

test('the queue reason is added by a file that is either pending or applied with a MANIFEST line, never both', () => {
  const sql = read(SQL);
  assert.ok(sql.includes("check (why in ('over_edge_ceiling', 'edge_worker_died', 'edge_reader_failed', 'pdf_lengths_worker_died', 'scan_needs_ocr'))"));
  const pending = existsSync(new URL('../../scripts/sql/pending/a_scanned_drawing_is_queued_for_ocr_redaction.txt', import.meta.url));
  const inManifest = read('scripts/sql/MANIFEST.txt').split('\n').includes(SQL);
  assert.ok(pending !== inManifest, 'exactly one of: a pending note, or a MANIFEST line (applied 28 Sep 2026)');
});
