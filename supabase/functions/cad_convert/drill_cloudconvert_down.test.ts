// DRILL D7, second half (docs/release/qualification_matrix.md §5.1): CloudConvert down. Seat
// accountable: it_engineer (the drill); the drawings and catalogues it converts are read by the
// sales_engineer. Offline and end to end through the REAL code: supplier_catalog_ingest receives a
// supplier's DXF, calls the REAL cad_convert (answered in-process by the stub below, not by a canned
// reply), and cad_convert calls api.cloudconvert.com, which the dispatcher below makes fail.
//
// Injected: CloudConvert 503 on job create, 401 (key invalid), a timeout (the AbortError cad_convert's
// own 25 s timer raises) and the host unreachable. Expected, in the matrix's terms:
//   safe      the file is HELD: stored, a supplier_catalog row exists with status 'conversion_failed',
//             no product is invented and the model is never handed a sheet that does not exist
//   visible   the supplier's answer and the catalogue row name the provider error (cad_convert's code)
//   recovery  NOT automatic: nothing re-converts a 'conversion_failed' row once CloudConvert is back
//             (grep: the status is written in supplier_catalog_ingest and read by no routine). OPEN.
//
// The positive control: CloudConvert answering the job with a finished PDF makes the same upload get
// past conversion to the reader. So 'conversion_failed' here is the outage, not a stub that never answers.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

type Row = Record<string, unknown>;
type CcMode = { status: number } | 'timeout' | 'unreachable' | 'up';
let cc: CcMode = { status: 503 };
let ccCalls: string[] = [];

async function handlers() {
  const ingest = await loadFunction('supplier_catalog_ingest', () => import('../supplier_catalog_ingest/index.ts'));
  const convert = await loadFunction('cad_convert', () => import('./index.ts'));
  const g = globalThis as unknown as { __d7cc?: boolean };
  if (!g.__d7cc) {
    g.__d7cc = true;
    const inner = globalThis.fetch;
    globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
      const u = new URL(input instanceof Request ? input.url : String(input));
      const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
      if (u.hostname === 'api.cloudconvert.com') {
        ccCalls.push((init?.method || 'GET') + ' ' + u.pathname);
        if (cc === 'timeout') throw new DOMException('The signal has been aborted', 'AbortError');
        if (cc === 'unreachable') throw new TypeError('error sending request: connection refused');
        if (cc === 'up') {
          if (u.pathname === '/v2/jobs') return J({ data: { id: 'job-zz-d7' } }, 201);
          return J({ data: { status: 'finished', tasks: [{ name: 'conv', status: 'finished' },
            { name: 'exp', status: 'finished', result: { files: [{ url: 'https://storage.cloudconvert.com/zz-d7.pdf' }] } }] } });
        }
        return J({ message: 'CloudConvert drill: ' + cc.status }, cc.status);
      }
      if (u.hostname === 'storage.cloudconvert.com') return new Response(new TextEncoder().encode('%PDF-1.4\n%zz demo sheet\n'), { status: 200 });
      return inner(input, init);
    }) as typeof fetch;
  }
  return { ingest, convert };
}

function world(convert: (req: Request) => Promise<Response>) {
  const w = { stored: [] as string[], products: [] as Row[], catalogStatus: [] as string[], gateway: 0, convertAnswers: [] as Row[] };
  const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
  const stub: Stub = {
    rows: { leads: [{ id: 4243 }] },
    rpc: { fn_internal_auth: { ok: true, context: 'db.internal', credential_id: 111 } },
    user: { id: 'u-zz-demo-d7cc', email: 'zz-demo-d7cc-supplier@example.invalid' },
    // VirusTotal is not under test here: the harness's {} for it reads as 'unknown' (total 0).
    handle: async (req, u) => {
      if (u.pathname === '/functions/v1/cad_convert') {
        const res = await convert(req);                          // the real cad_convert
        const body = await res.json();
        w.convertAnswers.push(body);
        return J(body, res.status);
      }
      if (u.pathname === '/functions/v1/ai_gateway') { w.gateway++; return J({ ok: false, used_llm: false, outcome: 'drill_no_model' }); }
      if (u.pathname.startsWith('/storage/v1/object/')) { w.stored.push(u.pathname); return J({ Key: u.pathname }); }
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      if (t === 'supplier_catalog' && req.method === 'POST') return J([{ id: 56 }], 201);
      if (t === 'supplier_catalog' && req.method === 'PATCH') { w.catalogStatus.push(String((await req.clone().json()).status)); return J([]); }
      if (t === 'supplier_product') { w.products.push(await req.clone().json()); return J([], 201); }
      return undefined;
    },
  };
  return { w, stub };
}
const DXF = '  0\nSECTION\n  2\nENTITIES\n  0\nTEXT\n  8\n0\n 10\n0\n 20\n0\n 40\n2.5\n  1\nZZ DEMO D7 GENERAL ARRANGEMENT\n  0\nENDSEC\n  0\nEOF\n';
const upload = { file_name: 'zz_demo_d7_sheet.dxf', content_type: 'image/vnd.dxf', data: btoa(DXF) };

async function run(mode: CcMode) {
  cc = mode; ccCalls = [];
  const { ingest, convert } = await handlers();
  const { w, stub } = world(convert);
  const r = await invoke(ingest, stub, upload);
  return { r, w };
}

Deno.test({
  name: 'D7 positive control: CloudConvert up, the DXF is converted and goes on to the reader',
  // cad_convert waits 3.5 s before its first status poll; the timer is real and is left running.
  sanitizeOps: false,
  fn: async () => {
    const { r, w } = await run('up');
    assertEquals(ccCalls[0], 'POST /v2/jobs', 'cad_convert asked CloudConvert');
    assertEquals(w.convertAnswers[0]?.ok, true, JSON.stringify(w.convertAnswers[0]));
    assert(r.json.status !== 'conversion_failed', 'conversion succeeded: ' + JSON.stringify(r.json));
    assertEquals(w.gateway >= 1, true, 'the converted sheet reached the reader');
  },
});

for (const [label, mode, code] of [
  ['503', { status: 503 }, 'convert_create_failed'],
  ['401 (key invalid)', { status: 401 }, 'convert_create_failed'],
  ['timeout', 'timeout', 'create_exception'],
  ['unreachable', 'unreachable', 'create_exception'],
] as [string, CcMode, string][]) {
  Deno.test(`D7 CloudConvert ${label}: the drawing is held as conversion_failed, stored, and nothing is invented`, async () => {
    const { r, w } = await run(mode);
    assertEquals(ccCalls, ['POST /v2/jobs'], 'one attempt at the provider');
    assertEquals(w.convertAnswers.map((a) => [a.ok, a.error]), [[false, code]], 'cad_convert names the failure');
    assertEquals(r.status, 200);
    assertEquals(r.json.status, 'conversion_failed', 'held, under the status that says why');
    assertEquals(r.json.products_created, 0);
    assert(String(r.json.why).includes(code), 'the supplier\'s answer names the provider error: ' + r.json.why);
    assertEquals(w.catalogStatus, ['conversion_failed'], 'visible: the catalogue row carries the status');
    // the file itself, once; the text code read off it is kept beside it as <path>.read.txt (supplier_doc_trades.saveText, ruling 1627)
    assertEquals(w.stored.filter((p) => p.includes('/supplier-docs/catalog/4243/') && !p.endsWith('.read.txt')).length, 1, 'nothing lost: the file itself is stored');
    assertEquals(w.products, [], 'no product record from a sheet nobody read');
    assertEquals(w.gateway, 0, 'the model is never handed a conversion that did not happen');
  });
}
