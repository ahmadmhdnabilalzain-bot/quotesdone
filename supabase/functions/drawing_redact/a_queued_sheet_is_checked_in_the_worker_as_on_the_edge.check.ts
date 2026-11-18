// A QUEUED SHEET IS CHECKED IN THE CAD WORKER, AS THE EDGE CHECKS IT (18 Nov 2026, sales_engineer; founder ledger 580).
// Production, 18 Nov 10:10 UTC: the sheets of the 8-sheet set the request could not verify were queued ('pages_need_time')
// and scripts/cad_read_worker.ts sent each BACK to the edge's drawing_redact, where the same ~2 s CPU cap lost them again
// ("sheet 1 not checked yet (pages_need_time_pixels_unverified)", "(pages_need_time_lost)"). The worker now runs the manual
// path's per-sheet core in its own process (_shared/drawing_redact_sheet.ts). This file proves, offline, on sheet 1 of the set:
//   (a) the worker's pages job (runJob, why 'pages_need_time') checks the sheet IN PROCESS: no call reaches drawing_redact,
//       every view goes to ai_gateway, and the set is published and its run recorded;
//   (b) the edge handler and the worker give the SAME answer for the same sheet with the same stub model: the same result
//       (bar the run's id and its random path), the same published bytes, the same run row, the same gateway calls;
//   and it measures the CPU one 2600 px sheet costs through the core in process (model stubbed).
// The stub model READS each view's reading mark from its pixels (drawing_pixel_gate.markCells), so neither path is told it.
//   deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-read=. \
//     --allow-net=deno.land,esm.sh supabase/functions/drawing_redact/a_queued_sheet_is_checked_in_the_worker_as_on_the_edge.check.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import process from 'node:process';
import { Image } from 'https://deno.land/x/imagescript@1.2.17/mod.ts';
import { planBoxes, planStrips, readPdfPlan } from '../_shared/drawing_plan.ts';
import { seedTerms } from '../_shared/anonymise.ts';
import { supplierBoxes } from '../_shared/supplier_copy.ts';
import { b64ToBytes, bytesToB64 } from '../_shared/drawing_redact_page.ts';
import { MARK_DIGITS, MARK_FONT, MARK_SCALE, TILING, pageSizeFromMediaBox, planTiles } from '../_shared/drawing_pixel_gate.ts';
import { PAGES_NEED_TIME, redactQueuedPages, sheetVerdict, type QueuedPages } from '../_shared/drawing_pages_queued.ts';

const SET = Deno.readFileSync(new URL('../_shared/testdata/zz_demo_mechanical_set_8_sheets.pdf', import.meta.url));
const SHEET1 = Deno.readFileSync(new URL('../_shared/testdata/zz_demo_mechanical_set_sheet1_portal_2600.jpg', import.meta.url));
const cpu = () => { const u = process.cpuUsage(); return (u.user + u.system) / 1000; };
const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;
const WHOLE = planTiles(pageSizeFromMediaBox(36 * 72, 24 * 72)).whole!;
const VIEWS = planTiles(pageSizeFromMediaBox(36 * 72, 24 * 72)).calls;
/** Where the stub reports a stamp on its first look at the whole page (page fractions; the whole view is the page). */
const STAMP = { x: 0.45, y: 0.45, w: 0.06, h: 0.04 };

// ── the stub model: it reads the mark drawn under each view, as a model that read the view would ────────────────────────
async function readView(b64: string): Promise<{ mark: string; whole: boolean }> {
  const img = await Image.decode(b64ToBytes(b64));
  const drawingH = img.height - TILING.markPx;
  // markCells' layout: digit k's 5 x 7 grid starts at x = 6 + k * (6 * MARK_SCALE + 2), y = drawingH + (markPx - 7 * MARK_SCALE) / 2
  const top = drawingH + Math.floor((TILING.markPx - 7 * MARK_SCALE) / 2);
  const ink = (x: number, y: number) => { let d = 0; for (const [dx, dy] of [[0, 0], [1, 0], [0, 1], [1, 1]]) { const [r, g, b] = img.getRGBAAt(x + dx + 1, y + dy + 1); d += r + g + b; } return d / 4 < 384; };
  let mark = '';
  for (let k = 0; k < MARK_DIGITS; k++) {
    const left = 6 + k * (6 * MARK_SCALE + 2);
    let best = '', score = -1;
    for (const [ch, glyph] of Object.entries(MARK_FONT)) {
      let s = 0;
      for (let r = 0; r < 7; r++) for (let c = 0; c < 5; c++) if (ink(left + c * MARK_SCALE, top + r * MARK_SCALE) === (glyph[r][c] === '1')) s++;
      if (s > score) { score = s; best = ch; }
    }
    mark += best;
  }
  return { mark, whole: img.width === WHOLE.outW && drawingH === WHOLE.outH };
}

// ── the stubbed estate (the edge at 127.0.0.1:9, the worker's project, the management API) ─────────────────────────────
Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:9');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-service');
type Handler = (req: Request) => Promise<Response>;
let handler: Handler | null = null;
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (h: Handler) => { handler = h; return { finished: Promise.resolve(), shutdown: async () => {}, ref() {}, unref() {}, addr: { hostname: '127.0.0.1', port: 9 } }; };
type Seen = { redactCalls: number; shown: string[]; gateway: Record<string, unknown>[]; uploads: { path: string; bytes: Uint8Array }[]; rows: Record<string, unknown>[]; sql: string[]; stubMs: number;
  /** Every request to the project or a function: what it is, and the run tag and proof it carried. */
  calls: { kind: string; run: string | null; secret: string | null; bearer: boolean }[] };
const fresh = (): Seen => ({ redactCalls: 0, shown: [], gateway: [], uploads: [], rows: [], sql: [], stubMs: 0, calls: [] });
let seen = fresh(), stampOnFirstWholeLook = false, stamps = 0, wholeLooks = 0;
/** Faults the stub estate can show the worker (review of a3fe7161, item 4). `secondWholeLook`: what the model does when it is
 *  asked the whole page again (after the stamp it reported was painted): no answer (502), or the job's budget cut lands. */
type Faults = { failView?: number; abortAtView?: { n: number; abort: AbortController }; secondWholeLook?: 'no_answer' | { abort: AbortController }; budgetRead?: 'fails'; held?: boolean; windowClosed?: boolean };
/** auth.users app_metadata.e2e_run by address (only the service role writes it; the harness sets it on its own customers). */
const APP_RUN: Record<string, string> = { 'qd-zz12ab34-cust@example.invalid': 'zz12ab34' };
let faults: Faults = {}, gatewayN = 0;
const RUN_PROOF = 'zz-db-internal-proof';
const RASTER_PATH = 'drawings/zz/pages/zz-sheet-0.jpg', SOURCE = 'drawings/zz/ZZ DEMO mechanical set.pdf';
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'Content-Type': 'application/json' } });
const realFetch = globalThis.fetch;
globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
  const local = url.startsWith('http://127.0.0.1:9'), project = url.startsWith('https://htdblwldjkcgjvmqkbeh.supabase.co'), mgmt = url.startsWith('https://api.supabase.com/');
  if (!local && !project && !mgmt) return realFetch(input as RequestInfo, init);
  const method = init?.method ?? 'GET';
  const isBlob = init?.body instanceof Blob;
  const text = typeof init?.body === 'string' ? init.body : '';
  if (!mgmt) {
    const h = new Headers(init?.headers);
    const kind = url.includes('/functions/v1/') ? 'fn:' + url.split('/functions/v1/')[1].split(/[/?]/)[0] : url.includes('/rpc/') ? 'rpc:' + url.split('/rpc/')[1].split(/[/?]/)[0] : url.includes('/storage/') ? 'storage' : 'rest:' + (url.split('/rest/v1/')[1] ?? '').split(/[/?]/)[0];
    seen.calls.push({ kind, run: h.get('x-qd-e2e-run'), secret: h.get('x-qd-e2e-secret'), bearer: /^Bearer zz-demo-service$/.test(h.get('authorization') ?? '') });
  }
  if (url.includes('/functions/v1/drawing_redact')) {
    seen.redactCalls++;
    if (!local) return json({ code: 'WORKER_RESOURCE_LIMIT' }, 546);   // the worker must never come here
    // The edge's own workers (paint, tiles, repaint): the REAL handler, as on the edge.
    return await handler!(new Request('http://127.0.0.1:9/functions/v1/drawing_redact', { method: 'POST', body: text }));
  }
  const t0 = cpu();
  try {
    if (url.includes('/functions/v1/ai_gateway')) {
      const b = JSON.parse(text);
      const shown = String(b.input?.[0]?.content?.[1]?.image_url?.url ?? '').replace(/^data:image\/jpeg;base64,/, '');
      seen.shown.push(shown);
      if (init?.signal?.aborted) throw new DOMException('aborted', 'AbortError');
      seen.gateway.push({ __secret: b.__secret, fn: b.fn, counterpart_model: b.counterpart_model, temperature: b.temperature, response_format: b.response_format, sys: b.sys, text: b.input?.[0]?.content?.[0]?.text, has_timeout: Number(b.client_timeout_ms) > 0 });
      const v = await readView(shown);
      if (++gatewayN === faults.failView) return json({ ok: false, error: 'provider_error' }, 502);
      if (faults.abortAtView && gatewayN === faults.abortAtView.n) { faults.abortAtView.abort.abort(); throw new DOMException('aborted', 'AbortError'); }
      if (v.whole && ++wholeLooks === 2 && faults.secondWholeLook) {
        if (faults.secondWholeLook === 'no_answer') return json({ ok: false, error: 'provider_error' }, 502);
        faults.secondWholeLook.abort.abort();   // the job's 30-minute budget lands while this view is under way
        throw new DOMException('aborted', 'AbortError');
      }
      const stamp = stampOnFirstWholeLook && v.whole && stamps === 0;
      if (stamp) stamps++;
      return json({ content: JSON.stringify({ mark: v.mark, clean: !stamp, addressed: false, regions: stamp ? [{ ...STAMP, what: 'company stamp' }] : [] }), model: 'zz/stub' });
    }
    if (mgmt) {
      const q = JSON.parse(text).query as string;
      seen.sql.push(q);
      if (q.includes("key = 'cred_fn_ai'")) return json([{ value: 'zz-demo-key' }]);
      if (q.includes("key = 'cred_db_internal'")) return json([{ value: RUN_PROOF }]);
      if (q.includes('fn_e2e_run_tag_open(')) { const em = /lower\(u\.email\) = lower\(\$qd\$(.*?)\$qd\$\)/.exec(q)?.[1] ?? ''; return json([{ run: APP_RUN[em.toLowerCase()] ?? null, open: !faults.windowClosed }]); }
      if (q.startsWith('with att as')) return json([{ attached: [], delivered: [] }]);
      return json([]);
    }
    if (url.includes('/rpc/fn_internal_auth')) return json({ ok: true, context: 'drawing_redact' });
    // The founder's hold is off: the gate refuses only the probe model (llm_hold.heldFromGate).
    if (url.includes('/rpc/fn_kernel_paid_provider_gate')) return json(faults.held ? { allowed: false, rule: 'founder_hold' } : { allowed: false, rule: 'route_not_registered' });
    if (url.includes('/rpc/')) return json({ message: 'no such rpc here' }, 404);
    if (url.includes('/rest/v1/app_secrets')) return json({ value: 'zz-demo-key' });
    if (url.includes('/rest/v1/drawing_redaction_runs')) {
      if (method === 'GET') return project && faults.budgetRead === 'fails' ? json({ message: 'canceling statement due to statement timeout' }, 500) : json([]);
      const row = JSON.parse(text); seen.rows.push(Array.isArray(row) ? row[0] : row);
      return new Response(null, { status: 201 });
    }
    if (url.includes('/storage/v1/object/')) {
      if (method === 'GET') return new Response(url.includes('zz-sheet-0.jpg') ? SHEET1 : SET, { status: 200 });
      if (method === 'DELETE') return json([]);
      const b = init?.body;
      const bytes = b instanceof Uint8Array ? b : isBlob ? new Uint8Array(await (b as Blob).arrayBuffer()) : b instanceof ArrayBuffer ? new Uint8Array(b) : new Uint8Array();
      seen.uploads.push({ path: decodeURIComponent(url.split('/object/drawing-files/')[1] ?? ''), bytes });
      return json({ Key: url.split('/object/')[1] });
    }
    if (url.includes('/rest/v1/')) return method === 'GET' ? json([]) : new Response(null, { status: 201 });
    return json({}, 404);
  } finally { seen.stubMs += cpu() - t0; }
}) as typeof fetch;

await import('./index.ts');
const worker = await import('../../../scripts/cad_read_worker.ts');

// The server's boxes for sheet 1 (customer_api's plan read), and the set's seeds: what the queued job carries.
const seeds = seedTerms({ name: 'ZZ DEMO Drawing', email: 'qd-cust@example.invalid', phone: '', extra: ['ZZ DEMO mechanical set.pdf'] });
// deno-lint-ignore no-explicit-any
const plan = (await readPdfPlan(async (b: any) => b.step === 'boxes' ? { ok: true, ...(await planBoxes(SET, b.from, b.to, b.seed_terms, b.set_seeds)) } : { ok: true, ...(await planStrips(SET, b.from, b.to)) }, seeds))!;
const BOXES = supplierBoxes(plan.tb, null, 8)![0];
const SEEDS = [...new Set([...seeds, ...plan.tb.setSeeds])];
const CUSTOMER = 'c0ffee00-0000-4000-8000-00000000000a';
const JOB = { id: 'a0b00000-0000-4000-8000-000000000001', customer_id: CUSTOMER, owner_email: 'qd-cust@example.invalid', source_path: SOURCE, file_name: 'ZZ DEMO mechanical set.pdf', mime: 'application/pdf', attempts: 1, why: PAGES_NEED_TIME, boq_in: { queued_pages: { pages_in: 1, seed_terms: SEEDS, done: [], left: [{ page: 0, path: RASTER_PATH, boxes: BOXES, why: 'lost' }] } satisfies QueuedPages } };
// What redactQueuedPages sends for the sheet (drawing_pages_queued.SheetBody), with what the worker adds.
const SHEET_BODY = { images: [{ mime: 'image/jpeg', data: bytesToB64(SHEET1) }], page_offset: 0, manual_boxes: [BOXES], seed_terms: SEEDS, original_b64: bytesToB64(SET), prefix: 'redacted' };
const owner = { owner_customer_id: CUSTOMER, owner_email: JOB.owner_email, source_path: SOURCE };

/** The answer with the run's random id and path made equal, for comparison. */
const same = (o: unknown) => JSON.parse(JSON.stringify(o).replace(UUID, 'UUID'));

async function onTheEdge(stamp: boolean) {
  seen = fresh(); stampOnFirstWholeLook = stamp; stamps = 0; wholeLooks = 0; faults = {}; gatewayN = 0;
  const r = await handler!(new Request('http://127.0.0.1:9/functions/v1/drawing_redact', { method: 'POST', body: JSON.stringify({ __secret: 'zz-cred-customer-api', ...SHEET_BODY, ...owner }) }));
  return { answer: await r.json(), seen };
}
async function inTheWorker(stamp: boolean) {
  seen = fresh(); stampOnFirstWholeLook = stamp; stamps = 0; wholeLooks = 0; faults = {}; gatewayN = 0;
  const redact = await worker.sheetRedactorHere(JOB, 'zz-demo-service', new AbortController().signal, Date.now() + 30 * 60_000);
  const t0 = cpu();
  const answer = await redact(SHEET_BODY);
  const total = cpu() - t0;
  // The stub model's own CPU (reading each view's mark), measured again on the same views one by one and taken off.
  const t1 = cpu(); for (const v of seen.shown) await readView(v); const model = cpu() - t1;
  return { answer, seen, ms: total - model };
}

for (const stamp of [false, true]) {
  Deno.test(`(b) one sheet, the edge and the worker: the same answer, the same published bytes, the same run row, the same gateway calls${stamp ? ' (a stamp found on the first look is painted and asked again)' : ''}`, async () => {
    const e = await onTheEdge(stamp);
    const w = await inTheWorker(stamp);
    assertEquals(e.answer.pages_out, 1, `the edge publishes the sheet: ${JSON.stringify(e.answer.verify_detail)}`);
    assertEquals(same(w.answer), same(e.answer), 'the worker answers what the edge answers');
    assertEquals(w.seen.uploads.length, 1); assertEquals(e.seen.uploads.length, 1);
    assert(/^redacted\/[0-9a-f-]{36}\/page_p0\.jpg$/.test(w.seen.uploads[0].path), w.seen.uploads[0].path);
    assertEquals(w.seen.uploads[0].bytes, e.seen.uploads[0].bytes, 'the page a supplier receives is byte for byte the edge\'s');
    assertEquals(same(w.seen.rows), same(e.seen.rows), 'the same drawing_redaction_runs row');
    assertEquals(w.seen.rows[0].output_paths, w.answer.paths);
    assertEquals(w.seen.gateway.length, VIEWS + (stamp ? 1 : 0), 'every view asked');
    assertEquals(w.seen.gateway, e.seen.gateway, 'the same gateway call, view for view: fn, counterpart, credential, prompt');
    assertEquals(w.seen.gateway[0].fn, 'drawing_redact_verify');
    assertEquals(w.seen.gateway[0].__secret, 'zz-demo-key', 'the credential drawing_redact presents (app_secrets.cred_fn_ai)');
    assertEquals(w.seen.redactCalls, 0, 'the worker never calls drawing_redact');
    assert(w.seen.calls.length > VIEWS && w.seen.calls.every((c) => c.run === null && c.secret === null), 'a real customer\'s job carries no run tag and no run proof');
    if (stamp) {
      const img = await Image.decode(w.seen.uploads[0].bytes);
      const [r, g, b] = img.getRGBAAt(Math.floor((STAMP.x + STAMP.w / 2) * img.width) + 1, Math.floor((STAMP.y + STAMP.h / 2) * img.height) + 1);
      assert(r + g + b < 60, `the stamp is covered on the worker's page: ${r},${g},${b}`);
    }
    console.log(`one 2600 px sheet through the core in process (model stubbed): ${Math.round(w.ms)} ms of CPU, ${w.seen.gateway.length} views asked`);
  });
}

Deno.test('(a) the worker\'s pages job checks the queued sheet in process: nothing reaches drawing_redact, the set is published and the job closed', async () => {
  seen = fresh(); stampOnFirstWholeLook = false; stamps = 0;
  // deno-lint-ignore no-explicit-any
  await worker.runJob(JOB as any, 'zz-demo-service');
  assertEquals(seen.redactCalls, 0, 'no sheet is sent back to the edge');
  assertEquals(seen.gateway.length, VIEWS, 'every view went to ai_gateway');
  assertEquals(seen.uploads.length, 1);
  assertEquals(seen.rows.length, 1);
  assertEquals(seen.rows[0].status, 'complete');
  assertEquals(seen.rows[0].source_path, SOURCE);
  assertEquals(seen.rows[0].customer_id, CUSTOMER);
  const done = seen.sql.find((q) => q.includes("status = 'done'"));
  assert(done, `the job is closed: ${seen.sql.map((q) => q.slice(0, 60)).join(' | ')}`);
  assert(/"redaction_complete":true/.test(done!) && done!.includes(seen.uploads[0].path), 'the job\'s result names the published page');
  assert(seen.sql.some((q) => q.includes('{queued_pages}')), 'the verified sheet is kept on the job as it goes');
  assert(seen.sql.some((q) => q.startsWith('with att as')), 'the pages are attached to the requests already sent');
});

Deno.test('(a) the worker source: the pages branch builds its redactor in process, never through edge()', () => {
  const src = Deno.readTextFileSync(new URL('../../../scripts/cad_read_worker.ts', import.meta.url));
  const branch = src.slice(src.indexOf('if (job.why === PAGES_NEED_TIME) {'), src.indexOf("if (job.why === 'site_photo_check') {"));
  assert(branch.includes('const redact = await sheetRedactorHere(job, key, stop.signal, Date.now() + PAGES_JOB_MS);'));
  assert(!/\bedge\(/.test(branch), 'the pages branch calls edge()');
  const here = src.slice(src.indexOf('export async function sheetRedactorHere('), src.indexOf('async function supplierDrawing('));
  assert(!/\bedge\(|functions\/v1\/drawing_redact/.test(here), 'the in-process redactor reaches drawing_redact');
  assert(here.includes('sheet.manualSheetsCall(') && here.includes('...sheet.inProcessWorkers'));
});

// ── review of a3fe7161, item 4: the run tag, a budget that cannot be read, the job's budget cut, and the model's holds ──────
const TEST_EMAIL = 'qd-zz12ab34-cust@example.invalid';
/** The queued sheet through redactQueuedPages and the worker's in-process redactor, as runJob runs it. */
async function queued(email: string, f: Faults & { stamp?: boolean }, o: { tries?: number; ctl?: AbortController } = {}) {
  seen = fresh(); faults = f; stampOnFirstWholeLook = !!f.stamp; stamps = 0; wholeLooks = 0; gatewayN = 0;
  const ctl = o.ctl ?? new AbortController();
  const redact = await worker.sheetRedactorHere({ ...JOB, owner_email: email }, 'zz-demo-service', ctl.signal, Date.now() + 30 * 60_000);
  const answers: Record<string, unknown>[] = [];
  const out = await redactQueuedPages(JOB.boq_in.queued_pages, { originalB64: bytesToB64(SET), raster: () => Promise.resolve(bytesToB64(SHEET1)), redact: async (b) => { const a = await redact(b); answers.push(a); return a; }, wait: () => Promise.resolve(), tries: o.tries, signal: ctl.signal });
  return { out, answers, seen };
}

Deno.test('a test run\'s job sends its run tag with its proof on every call (the gateway, the hold probe, the run row); a real customer\'s sends none', async () => {
  const t = await queued(TEST_EMAIL, {});
  assertEquals(t.out.redaction_complete, true, JSON.stringify(t.out));
  const gw = t.seen.calls.filter((c) => c.kind === 'fn:ai_gateway');
  assertEquals(gw.length, VIEWS);
  assert(gw.every((c) => c.run === 'zz12ab34' && c.secret === RUN_PROOF), 'every model call names the run and proves it (cred_db_internal)');
  const probe = t.seen.calls.filter((c) => c.kind === 'rpc:fn_kernel_paid_provider_gate');
  assert(probe.length >= 1 && probe.every((c) => c.run === 'zz12ab34' && c.bearer), 'the hold probe is asked as the run, with the service bearer');
  assert(t.seen.calls.filter((c) => c.kind.startsWith('rest:') || c.kind === 'storage').every((c) => c.run === 'zz12ab34' && c.bearer), 'the budget read, the run row and the upload carry the tag');
  assertEquals(t.seen.redactCalls, 0);
  // the same sheet for a real customer: no tag anywhere
  const r = await queued('buyer@realfirm.ae', {});
  assertEquals(r.out.redaction_complete, true);
  assert(r.seen.calls.every((c) => c.run === null && c.secret === null), 'a real customer\'s job is never tagged');
});

Deno.test('an address anyone can type is not a run: a real customer whose e-mail looks like a run address, or a run whose window is closed, sends no tag', async () => {
  for (const [email, f] of [['qd-zz99cd56-buyer@example.invalid', {}], [TEST_EMAIL, { windowClosed: true }]] as const) {
    faults = f;
    assertEquals(await worker.provenRunTag(email, (e) => /^qd-([a-z0-9]{4,16})-/.exec(String(e))?.[1] ?? null), null, email);
    const t = await queued(email, f);
    assertEquals(t.out.redaction_complete, true, JSON.stringify(t.out));
    assert(t.seen.calls.every((c) => c.run === null && c.secret === null), `${email}: no tag, no proof`);
  }
  faults = {};
  assertEquals(await worker.provenRunTag(TEST_EMAIL, (e) => /^qd-([a-z0-9]{4,16})-/.exec(String(e))?.[1] ?? null), 'zz12ab34', 'the harness\'s own customer, its window open');
});

Deno.test('a budget that cannot be read is no answer: the sheet is asked again later, never refused, and no model is paid', async () => {
  const b = await queued(TEST_EMAIL, { budgetRead: 'fails' });
  assertEquals(b.out.retry_later, true, JSON.stringify(b.out));
  assertEquals(b.out.held_identity, undefined);
  assertEquals(b.answers.length, 3, 'asked SHEET_TRIES times in the run, then back to the queue');
  assert(b.answers.every((a) => a.ok === false && a.error === 'budget_unreadable' && sheetVerdict(a).state === 'retry'));
  assertEquals(b.seen.gateway.length, 0, 'nothing spent without a budget');
  assertEquals(b.seen.uploads.length + b.seen.rows.length, 0);
});

Deno.test('the job\'s budget cut lands before the checker found anything: the sheet goes back to the queue', async () => {
  const ctl = new AbortController();
  const c = await queued(TEST_EMAIL, { abortAtView: { n: 3, abort: ctl } }, { ctl });
  assertEquals(c.out.retry_later, true, JSON.stringify(c.out));
  assertEquals(c.out.held_identity, undefined);
  assertEquals(c.out.held_reason, 'pages_need_time_job_budget', 'no sheet is sent again once the budget is spent');
  assertEquals(c.answers.length, 1);
  assertEquals(c.answers[0].error, 'job_budget_cut');
  assertEquals(c.answers[0].cut_hold, 'pixels_unverified');
  assertEquals(c.seen.uploads.length, 0, 'nothing published on a cut');
});

Deno.test('the job\'s budget cut lands AFTER the checker painted a stamp: the finding stands, the set is held for identity, never retried', async () => {
  const ctl = new AbortController();
  const c = await queued(TEST_EMAIL, { stamp: true, secondWholeLook: { abort: ctl } }, { ctl });
  assertEquals(c.out.held_identity, true, JSON.stringify(c.out));
  assertEquals(c.out.retry_later, undefined, 'a retry would start from the unpainted raster: one miss would publish the stamp');
  assertEquals(c.out.held_reason, 'pages_need_time_checker_found_then_pixels_unverified');
  assertEquals(c.answers.length, 1);
  assertEquals(c.seen.uploads.length, 0);
});

Deno.test('the model\'s holds in the worker: an unanswered view is asked again; a view unanswered after the checker found a stamp is never retried; the founder\'s hold is asked again', async () => {
  const u = await queued(TEST_EMAIL, { failView: 3 }, { tries: 1 });
  assertEquals(u.out.retry_later, true, JSON.stringify(u.out));
  assertEquals(u.out.held_reason, 'pages_need_time_pixels_unverified');
  assertEquals(sheetVerdict(u.answers[0]), { state: 'retry', why: 'pixels_unverified' });
  const f = await queued(TEST_EMAIL, { stamp: true, secondWholeLook: 'no_answer' });
  assertEquals(f.out.held_identity, true, JSON.stringify(f.out));
  assertEquals(f.out.retry_later, undefined);
  assertEquals(f.out.held_reason, 'pages_need_time_checker_found_then_pixels_unverified');
  assertEquals(f.answers.length, 1, 'a checker finding is asked once, never retried blindly');
  assertEquals(f.seen.uploads.length, 0);
  const h = await queued(TEST_EMAIL, { held: true }, { tries: 1 });
  assertEquals(h.out.retry_later, true, JSON.stringify(h.out));
  assertEquals(h.seen.gateway.length, 0, 'under the founder\'s hold no model is asked');
  assertEquals((h.answers[0].verify_detail as { reason?: string }[])[0].reason, 'model_hold');
});
