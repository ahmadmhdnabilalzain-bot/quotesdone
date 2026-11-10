// A DRAWING READ IS NOT CUT OFF BY THE PORTAL, AND A CUT-OFF READ IS NEVER RE-READ BY OCR (10 Nov 2026, sales_engineer;
// evidence run ea40c830, docs/reports/2026-11-10-journey-evidence.md, still-seen item 2).
//
// Measured on production (function_edge_logs, 10 Nov 2026 19:29:58-19:30:41Z): customer_api analyze_drawing on journey 2's
// one-sheet HVAC drawing ran 39,679 ms and answered 200 (drawing_redact 8,476 ms for the page, drawing_boq 35,071 ms with the
// model on). The customer portal's call() aborted every request at 30 s, and the composer then took its "scanned PDF" path
// for ANY PDF that came back without lines: it OCR'd the rendered sheet in the browser and sent that text to
// analyze_document (customer_api 2,735 ms at 19:30:41Z). The take-off of the OCR text carried the title block's client as
// "Mir. 22 Demo Owner", and the request was stored with drawing_redacted_paths null. In the models-off dry run the same
// file answered inside 30 s, was read from its text layer and redacted 1/1.
//
// This pins the portal side: the analyze_drawing call waits as long as the edge can run it, the dashboard's wrapper passes
// that timeout through, and the browser OCR runs only on a PDF the server read and found to have no text layer
// (pdf_words 0, returned by analyze_drawing). The server side is pinned by
// supabase/functions/_shared/drawing_identity_ocr_misread.test.ts and customer_api/drawing_send_gate.test.ts.
//   node --test scripts/checks/a_drawing_read_is_not_cut_off_by_the_portal.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const read = (p) => readFileSync(root + p, 'utf8');
const API = read('src/components/me/api.ts');
const NR = read('src/components/me/NewRequest.tsx');
const DASH = read('src/components/me/dashboard/Dashboard.tsx');
const DOCS = read('supabase/functions/customer_api/actions/documents.ts');
const MEASURED_MS = 39679;
const EDGE_WALL_MS = 150000;

// The real api.ts, with its imports replaced by stubs, loaded by Node's own type stripping.
async function loadApi() {
  const dir = mkdtempSync(join(tmpdir(), 'qd-me-api-'));
  const retryUrl = new URL('../../src/lib/fetchRetry.ts', import.meta.url).href;
  const src = API
    .replace(/^import \{ supaClient \} from '@\/lib\/supaClient';$/m, 'const supaClient = () => null;')
    .replace(/^import \{ SUPA_ANON as ANON, fnUrl \} from '@\/lib\/supaEnv';$/m, "const ANON = 'anon'; const fnUrl = (p) => 'https://fn.invalid/functions/v1/' + p;")
    .replace(/^import \{ retryRead, isReadAction \} from '@\/lib\/fetchRetry';$/m, `import { retryRead, isReadAction } from '${retryUrl}';`)
    .replace(/^import \{ warm \} from '\.\/prefetch';$/m, 'const warm = () => {};');
  assert.equal((src.match(/^import /gm) || []).length, 1, 'me/api.ts imports changed; update the stubs of this check');
  const f = join(dir, 'api.mts'); writeFileSync(f, src);
  return import(pathToFileURL(f).href);
}
const slowServer = (ms) => (_url, init) => new Promise((resolve, reject) => {
  const t = setTimeout(() => resolve(new Response(JSON.stringify({ ok: true, boq: { boq: [] }, pdf_words: 488 }), { status: 200 })), ms);
  init.signal.addEventListener('abort', () => { clearTimeout(t); reject(new DOMException('aborted', 'AbortError')); });
});

test('the drawing read waits longer than the measured read and no longer than the edge can run', async () => {
  const api = await loadApi();
  assert.ok(api.DRAWING_READ_TIMEOUT_MS >= 3 * MEASURED_MS, `DRAWING_READ_TIMEOUT_MS ${api.DRAWING_READ_TIMEOUT_MS} must stay well over the measured ${MEASURED_MS} ms`);
  assert.ok(api.DRAWING_READ_TIMEOUT_MS <= EDGE_WALL_MS, 'past the edge wall the answer can never come');
  const real = globalThis.fetch;
  try {
    globalThis.fetch = slowServer(120);
    assert.equal((await api.call('customer_api', { action: 'analyze_drawing' }, 't', 50)).error, 'qd_timeout', 'a per-call timeout is honoured');
    assert.equal((await api.call('customer_api', { action: 'analyze_drawing' }, 't', 1000)).ok, true);
  } finally { globalThis.fetch = real; }
});

test('the composer passes the drawing timeout, and the dashboard passes it through', () => {
  const at = NR.indexOf("action: 'analyze_drawing'");
  assert.ok(at > 0, 'analyze_drawing call not found in NewRequest.tsx');
  assert.match(NR.slice(at, NR.indexOf('\n', at)), /\}, token, DRAWING_READ_TIMEOUT_MS\);$/, 'analyze_drawing must pass DRAWING_READ_TIMEOUT_MS as call()\'s 4th argument');
  assert.match(DASH, /call=\{async \(p, b, tk, ms\) => \{ const r = await call\(p, b, tk, ms\);/, "Dashboard's call wrapper must forward the 4th argument, or the composer's timeout never reaches api.call");
});

test('the browser OCR of a PDF runs only when the server read it and found no text layer', () => {
  const at = NR.indexOf("action: 'analyze_document', file_b64: p.b64, mime: p.mime, file_name: p.name, ocr_text: text");
  assert.ok(at > 0, 'the scanned-PDF OCR path was not found in NewRequest.tsx');
  const cond = NR.slice(NR.lastIndexOf('if (!(res && res.boq', at), at);
  assert.match(cond, /res\.ok === true && res\.pdf_words === 0/, 'the OCR fallback must require ok:true and pdf_words 0 from analyze_drawing');
  // analyze_drawing returns pdf_words on the success path and on both failure paths that still carry the file.
  const ad = DOCS.slice(DOCS.indexOf("if (action === 'analyze_drawing')"));
  assert.equal((ad.match(/pdf_words: pdfWords/g) || []).length, 3, 'analyze_drawing must return pdf_words on its success, boq_fetch_failed and analysis_failed answers');
});
