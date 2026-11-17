// A DRAWING SHEET IS REDACTED WITHIN THE EDGE BUDGET (17 Nov 2026, sales_engineer; founder ledger 580: the drawing reaches
// the suppliers, redacted). The live proof that afternoon (scripts/e2e/drawing_reaches_suppliers.mjs, tag 14173f94) sent
// the 8-sheet ZZ DEMO mechanical set, one 2600 px sheet per call, and drawing_redact died "CPU Time exceeded" seven times
// (HTTP 546 at 2,205-2,551 ms CPU): every sheet was held, so no supplier received a page.
//
// MEASURED LOCALLY on the same sheets (deno 2.9, process CPU, a cold process per sheet; the hand-back has all eight):
//   the main worker of one sheet, before   readerAgrees parsed ALL 8 pages (every path, ~4,000 a sheet) to compare ONE:
//                                           ~580 ms cold; decode 460 + paint 8 + encode 300 of the 2600 px raster; the
//                                           page's text layer, the vet and the unread-text rule ~250; the gate's 21 views.
//   after                                   readerAgrees reads the asked pages only; the paint runs in a worker of its
//                                           own (mode 'paint': one decode, one encode), like the tiles and the repaint.
// This file runs the REAL handler (drawing_redact/index.ts) in process on sheet 1, every network edge stubbed, the model a
// stub that copies each view's reading mark and answers clean, and holds each worker's CPU to a budget well inside the
// edge's 2 s. Every view is still asked and every box still painted: the test also proves the page comes back published.
//
//   deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-read=. \
//     --allow-net=deno.land,esm.sh supabase/functions/drawing_redact/a_sheet_is_redacted_within_the_edge_budget.check.ts
//
// A .check.ts, not a .test.ts: imagescript fetches its codec .wasm from deno.land when imported (see
// _shared/drawing_redact_page.check.ts), so it runs as its own local gate step with that one host.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import process from 'node:process';
import { planBoxes, planStrips, readPdfPlan } from '../_shared/drawing_plan.ts';
import { seedTerms } from '../_shared/anonymise.ts';
import { supplierBoxes } from '../_shared/supplier_copy.ts';
import { bytesToB64, serverBoxedPage } from '../_shared/drawing_redact_page.ts';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import { Image } from 'https://deno.land/x/imagescript@1.2.17/mod.ts';
import { VIEWS_PER_CROP, pageSizeFromMediaBox, planTiles } from '../_shared/drawing_pixel_gate.ts';

/** The edge kills a worker past about 2 s of CPU (measured: 2,205 ms). A worker here gets at most this, LOCALLY: the edge
 *  ran the same steps about 1.3x slower than this machine (the 546s at 2,205-2,551 ms against ~1.8 s here). */
// MEASURED by the reviewer (3 idle runs): the cold paint worker 820-955 ms, so 1,000 ms left 5% and flaked under load; 1,400 ms
// is still inside the edge's 2,205 ms at the 1.3x the edge runs slower.
export const WORKER_CPU_BUDGET_MS = 1_400;

const SET = Deno.readFileSync(new URL('../_shared/testdata/zz_demo_mechanical_set_8_sheets.pdf', import.meta.url));
// Sheet 1 of that set, rasterised as the portal does it (pdf.js, long edge 2600 px, JPEG 0.8): scripts/e2e/portal_raster.mjs.
const SHEET1 = Deno.readFileSync(new URL('../_shared/testdata/zz_demo_mechanical_set_sheet1_portal_2600.jpg', import.meta.url));
const SECRET = 'zz-demo-internal';
const cpu = () => { const u = process.cpuUsage(); return (u.user + u.system) / 1000; };

// ── the stubbed edges ────────────────────────────────────────────────────────────────────────────────────────────────
Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:9');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-service');
type Handler = (req: Request) => Promise<Response>;
let handler: Handler | null = null;
(Deno as any).serve = (h: Handler) => { handler = h; return { finished: Promise.resolve(), shutdown: async () => {}, ref() {}, unref() {}, addr: { hostname: '127.0.0.1', port: 9 } }; };
const marks = new Map<string, string>();           // a view the stub "cut" -> the reading mark drawn under it
const wholeViews = new Set<string>();              // the views that show the whole page
const workers: { mode: string; ms: number }[] = []; // each fresh worker this sheet used, and its CPU
let published: Uint8Array | null = null;            // the page as storage received it
let stubMs = 0, viewNo = 0, stampOnFirstWholeLook = false, stampsReported = 0;
/** Where the stub model reports a stamp on its first look at the whole page (page fractions; the whole view is the page). */
const STAMP = { x: 0.45, y: 0.45, w: 0.06, h: 0.04 };
const realFetch = globalThis.fetch;
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'Content-Type': 'application/json' } });
globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
  if (!url.startsWith('http://127.0.0.1:9')) return realFetch(input as any, init);
  let t0 = cpu();
  const body = typeof init?.body === 'string' ? init.body : init?.body instanceof Blob && !url.includes('/storage/') ? await init.body.text() : '';
  try {
    if (url.includes('/functions/v1/drawing_redact')) {
      const mode = /"mode":"([a-z_]+)"/.exec(body)?.[1] ?? '';
      // A view of the page (mode 'tile'): the stub hands back a token for it and remembers its mark; the real crop worker
      // is measured on its own (one decode, one crop and scale, one encode).
      if (mode === 'tile') { const q = JSON.parse(body), id = 'V' + (++viewNo); marks.set(id, q.mark); if (q.tile?.whole) wholeViews.add(id); return json({ ok: true, jpg_b64: id }); }
      // Several views of the page (mode 'tiles', 17 Nov 2026): a token and a mark for each, the real worker measured below.
      if (mode === 'tiles') { const q = JSON.parse(body); return json({ ok: true, jpgs: q.views.map((v: any) => { const id = 'V' + (++viewNo); marks.set(id, v.mark); if (v.tile?.whole) wholeViews.add(id); return id; }) }); }
      // Any other worker (the paint, a repaint) runs the REAL handler, its CPU measured as its own worker's.
      stubMs += cpu() - t0;
      const w0 = cpu();
      const r = await handler!(new Request('http://127.0.0.1:9/functions/v1/drawing_redact', { method: 'POST', body }));
      const out = await r.text();
      workers.push({ mode, ms: cpu() - w0 });
      t0 = cpu();   // the worker's own CPU is counted as the worker's, not the stub's
      return new Response(out, { status: r.status, headers: { 'Content-Type': 'application/json' } });
    }
    if (url.includes('/functions/v1/ai_gateway')) {
      // The model copies the mark of the view it was shown. It answers clean, except (when asked to) on its first look at
      // the whole page, where it reports a stamp: the gate must have it painted and ask that view again.
      const id = /base64,(V\d+)/.exec(body)?.[1] ?? '';
      const stamp = stampOnFirstWholeLook && wholeViews.has(id) && stampsReported === 0;
      if (stamp) stampsReported++;
      return json({ content: JSON.stringify({ mark: marks.get(id) ?? '', clean: !stamp, addressed: false, regions: stamp ? [{ ...STAMP, what: 'company stamp' }] : [] }), model: 'zz/stub' });
    }
    if (url.includes('/rpc/fn_internal_auth')) return json({ ok: true, context: 'drawing_redact' });
    if (url.includes('/rpc/')) return json({ message: 'no such rpc here' }, 404);
    if (url.includes('/rest/v1/app_secrets')) return json({ value: 'zz-demo-key' });
    if (url.includes('/storage/v1/object/')) {
      const b = init?.body;
      published = b instanceof Uint8Array ? b : b instanceof Blob ? new Uint8Array(await b.arrayBuffer()) : b instanceof ArrayBuffer ? new Uint8Array(b) : null;
      return json({ Key: url.split('/object/')[1] });
    }
    if (url.includes('/rest/v1/')) return (init?.method ?? 'GET') === 'GET' ? json([]) : new Response(null, { status: 201 });
    return json({}, 404);
  } finally { stubMs += cpu() - t0; }
}) as typeof fetch;

await import('./index.ts');

/** The manual boxes customer_api sends for this set (its readPdfPlan through drawing_redact mode 'plan'), read in process. */
async function serverBoxes(): Promise<{ x: number; y: number; w: number; h: number }[][]> {
  const seeds = seedTerms({ name: 'ZZ DEMO Drawing', email: 'qd-cust@example.invalid', phone: '', extra: ['ZZ DEMO mechanical set.pdf'] });
  const plan = await readPdfPlan(async (b: any) => b.step === 'boxes' ? { ok: true, ...(await planBoxes(SET, b.from, b.to, b.seed_terms, b.set_seeds)) } : { ok: true, ...(await planStrips(SET, b.from, b.to)) }, seeds);
  assert(plan, 'the set is read');
  const boxes = supplierBoxes(plan.tb, null, 8);
  assert(boxes && boxes[0].length > 0, 'the server boxes the title block itself: customer_api sends them, drawing_redact takes the manual path');
  return boxes;
}

/** Sheet 1 through the handler as customer_api sends it; each worker's CPU, the crop worker's measured on the result. */
async function oneSheet(stamp: boolean) {
  const boxes = await serverBoxes();
  const body = JSON.stringify({ __secret: SECRET, images: [{ mime: 'image/jpeg', data: bytesToB64(SHEET1) }], prefix: 'redacted', owner_customer_id: crypto.randomUUID(), owner_email: 'qd-cust@example.invalid', source_path: 'drawings/zz/ZZ DEMO mechanical set.pdf', page_offset: 0, seed_terms: [], original_b64: bytesToB64(SET), manual_boxes: [boxes[0]] });
  stubMs = 0; viewNo = 0; stampsReported = 0; stampOnFirstWholeLook = stamp; workers.length = 0; marks.clear(); wholeViews.clear(); published = null;
  const t0 = cpu();
  const r = await handler!(new Request('http://127.0.0.1:9/functions/v1/drawing_redact', { method: 'POST', body }));
  const total = cpu() - t0;
  const j = await r.json();
  // The main worker's own CPU: the whole call less the stubs and less the workers it handed pixels to.
  const main = total - stubMs - workers.reduce((s, w) => s + w.ms, 0);
  const views = viewNo;
  assert(published, `the page was uploaded: ${JSON.stringify(j.verify_detail)}`);
  // One crop worker on the published page (every view the gate asks is one of these).
  const t1 = cpu();
  const tile = await handler!(new Request('http://127.0.0.1:9/functions/v1/drawing_redact', { method: 'POST', body: JSON.stringify({ __secret: SECRET, mode: 'tile', jpg_b64: bytesToB64(published!), tile: { x: 0, y: 0, w: 0.27, h: 0.39, outW: 1256, outH: 742 }, mark: '123456' }) }));
  const crop = cpu() - t1;
  assertEquals((await tile.json()).ok, true);
  // One batched crop worker (mode 'tiles') with the most views a call carries: the first VIEWS_PER_CROP views of the plan.
  const plan = planTiles(pageSizeFromMediaBox(36 * 72, 24 * 72));
  const t2 = cpu();
  const many = await handler!(new Request('http://127.0.0.1:9/functions/v1/drawing_redact', { method: 'POST', body: JSON.stringify({ __secret: SECRET, mode: 'tiles', jpg_b64: bytesToB64(published!), views: plan.tiles.slice(0, VIEWS_PER_CROP).map((tile, k) => ({ tile, mark: String(100000 + k) })) }) }));
  const crops = cpu() - t2;
  assertEquals((await many.json()).jpgs?.length, VIEWS_PER_CROP);
  console.log(`main worker ${Math.round(main)} ms; ${workers.map((w) => `${w.mode} ${Math.round(w.ms)} ms`).join('; ') || 'no pixel worker'}; one crop worker ${Math.round(crop)} ms; one ${VIEWS_PER_CROP}-view crop worker ${Math.round(crops)} ms; views asked ${views}`);
  return { j, main, crop, crops, views, boxes, workers: [...workers], page: published! };
}

function withinBudget(o: { main: number; crop: number; crops: number; workers: { mode: string; ms: number }[] }) {
  assert(o.crops <= WORKER_CPU_BUDGET_MS, `a ${VIEWS_PER_CROP}-view crop worker spent ${Math.round(o.crops)} ms (budget ${WORKER_CPU_BUDGET_MS})`);
  assert(o.main <= WORKER_CPU_BUDGET_MS, `the main worker spent ${Math.round(o.main)} ms of CPU on one sheet (budget ${WORKER_CPU_BUDGET_MS})`);
  for (const w of o.workers) assert(w.ms <= WORKER_CPU_BUDGET_MS, `the ${w.mode} worker spent ${Math.round(w.ms)} ms (budget ${WORKER_CPU_BUDGET_MS})`);
  assert(o.crop <= WORKER_CPU_BUDGET_MS, `a crop worker spent ${Math.round(o.crop)} ms (budget ${WORKER_CPU_BUDGET_MS})`);
}

// A 36 x 24 in sheet: 24 tiles and the whole page. Every one is still asked.
const VIEWS = planTiles(pageSizeFromMediaBox(36 * 72, 24 * 72)).calls;

Deno.test('one 2600 px sheet of the 8-sheet set: every worker it uses stays inside the edge CPU budget, every view is asked, and the published page is the one the single worker painted', async () => {
  const o = await oneSheet(false);
  assertEquals(o.j.method, 'manual');
  assertEquals(o.j.pages_out, 1, `the sheet is published: ${JSON.stringify(o.j.verify_detail)}`);
  withinBudget(o);
  assertEquals(o.views, VIEWS, 'every view of the sheet is asked');
  assertEquals(o.workers.map((w) => w.mode), ['paint'], 'the pixels are painted in a worker of their own');
  // EQUIVALENCE: the page a supplier receives is byte for byte the page serverBoxedPage paints in one worker, which is
  // what drawing_redact published before the split (same boxes, same margin, same order, same quality).
  const pp = await pdfPages(SET, [0, 1], { layers: false });
  const here = await serverBoxedPage(SHEET1, pp, 0, o.boxes[0]);
  assert(here.ok);
  assertEquals(o.page, here.jpg, 'the published page differs from the one-worker paint');
});

Deno.test('a stamp the checker finds on its first look is painted by the repaint worker inside the budget, and the page is published covered', async () => {
  const o = await oneSheet(true);
  assertEquals(o.j.pages_out, 1, `the sheet is published after the re-check: ${JSON.stringify(o.j.verify_detail)}`);
  withinBudget(o);
  assertEquals(o.views, VIEWS + 1, 'the whole page is asked again after the stamp was painted');
  assertEquals(o.workers.map((w) => w.mode), ['paint', 'repaint']);
  const img = await Image.decode(o.page);
  const cx = Math.floor((STAMP.x + STAMP.w / 2) * img.width), cy = Math.floor((STAMP.y + STAMP.h / 2) * img.height);
  const [r, g, b] = img.getRGBAAt(cx + 1, cy + 1);
  assert(r + g + b < 60, `the stamp is not black on the published page: ${r},${g},${b}`);
});
