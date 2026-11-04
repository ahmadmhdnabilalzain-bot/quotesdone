// DRILL D7, first half (docs/release/qualification_matrix.md §5.1): VirusTotal down. Seat
// accountable: it_engineer (the drill); the files it guards are read by the sales_engineer.
// Offline, against the REAL gate every inbound supplier/customer file passes (_shared/malware.ts
// sanitizeAndScan, reached through its real caller supplier_catalog_ingest), with fetch and env
// stubbed by _shared/twilio_free_harness.ts and www.virustotal.com answered by the dispatcher below.
//
// Injected: VirusTotal 503, 401 (key invalid), a timeout (the AbortError malware.ts's own 8 s timer
// raises), and the host unreachable. Expected, in the matrix's terms:
//   safe      the verdict is 'unavailable' and cleared=false; nothing reads as 'clean' unscanned
//   visible   a public.file_scan row says 'unavailable' with the HTTP status; fn_security_detect turns
//             one older than 24 h into a 'file_unscanned' security event
//             (scripts/sql/the_security_watch_judges_every_file_and_names_what_it_cannot_stop.sql)
//   held      the matrix asks that an unjudged file is HELD, not read. That is NOT what the code does
//             (malware.ts header, option (c): an unjudged file is accepted and read; no caller reads
//             scan.cleared). The assertion is kept below, ignored, and reported OPEN.
//
// The known-bad control: VirusTotal answering 3 engines malicious refuses the upload with 415 and
// stores nothing; the positive control: answering 70 harmless engines clears it. So 'unavailable'
// here is the provider's outage reaching the gate, not a stub that never answers.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from './twilio_free_harness.ts';

type Row = Record<string, unknown>;
type VtMode = { status: number; body?: unknown } | 'timeout' | 'unreachable';
let vt: VtMode = { status: 503 };
let vtCalls = 0;

async function gate() {
  const h = await loadFunction('supplier_catalog_ingest', () => import('../supplier_catalog_ingest/index.ts'));
  const g = globalThis as unknown as { __d7vt?: boolean };
  if (!g.__d7vt) {
    g.__d7vt = true;
    const inner = globalThis.fetch;
    globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
      const u = new URL(input instanceof Request ? input.url : String(input));
      if (u.hostname === 'www.virustotal.com') {
        vtCalls++;
        if (vt === 'timeout') throw new DOMException('The signal has been aborted', 'AbortError');
        if (vt === 'unreachable') throw new TypeError('error sending request: dns error: failed to lookup address');
        return new Response(JSON.stringify(vt.body ?? { error: { code: 'TransientError' } }), { status: vt.status, headers: { 'content-type': 'application/json' } });
      }
      return inner(input, init);
    }) as typeof fetch;
  }
  return h;
}

/** The database the upload writes to: records file_scan, storage, catalogue and product writes. */
function world() {
  const w = { scans: [] as Row[], stored: [] as string[], products: [] as Row[], catalogStatus: [] as string[] };
  const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
  const stub: Stub = {
    rows: { leads: [{ id: 4242 }] },
    user: { id: 'u-zz-demo-d7', email: 'zz-demo-d7-supplier@example.invalid' },
    handle: async (req, u) => {
      if (u.pathname.startsWith('/storage/v1/object/')) { w.stored.push(u.pathname); return J({ Key: u.pathname }); }
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      if (t === 'file_scan' && req.method === 'POST') { w.scans.push(await req.clone().json()); return J([], 201); }
      if (t === 'supplier_catalog' && req.method === 'POST') return J([{ id: 55 }], 201);
      if (t === 'supplier_catalog' && req.method === 'PATCH') { w.catalogStatus.push(String((await req.clone().json()).status)); return J([]); }
      if (t === 'supplier_product') { w.products.push(await req.clone().json()); return J([], 201); }
      return undefined;
    },
  };
  return { w, stub };
}
// A small, harmless price list: CSV is read by code, so no model is on the path of this drill.
const CSV = 'name,model,price,unit\nZZ DEMO cable tray,CT-100,45,m\nZZ DEMO junction box,JB-2,12,ea\n';
const upload = { file_name: 'zz_demo_d7_prices.csv', content_type: 'text/csv', data: btoa(CSV) };

async function run(mode: VtMode) {
  vt = mode; vtCalls = 0;
  const h = await gate();
  const { w, stub } = world();
  const r = await invoke(h, stub, upload);
  return { r, w };
}

Deno.test('D7 positive control: VirusTotal answering clean clears the file and it is read', async () => {
  const { r, w } = await run({ status: 200, body: { data: { attributes: { last_analysis_stats: { malicious: 0, suspicious: 0, harmless: 70, undetected: 0 } } } } });
  assertEquals(vtCalls, 1, 'the gate asked VirusTotal');
  assertEquals(r.status, 200, JSON.stringify(r.json));
  assertEquals(w.scans.map((s) => s.verdict), ['clean']);
  assertEquals(r.json.products_created, 2);
});

Deno.test('D7 known-bad control: VirusTotal naming the file malicious refuses it and stores nothing', async () => {
  const { r, w } = await run({ status: 200, body: { data: { attributes: { last_analysis_stats: { malicious: 3, suspicious: 0, harmless: 60, undetected: 7 } } } } });
  assertEquals(r.status, 415);
  assertEquals(r.json.error, 'malware_detected');
  assertEquals(w.scans.map((s) => [s.verdict, s.blocked]), [['malicious', true]]);
  assertEquals(w.stored, [], 'nothing reached storage');
  assertEquals(w.products, []);
});

for (const [label, mode, status] of [
  ['503', { status: 503 }, 503],
  ['401 (key invalid)', { status: 401, body: { error: { code: 'WrongCredentialsError' } } }, 401],
  ['timeout', 'timeout', 0],
  ['unreachable', 'unreachable', 0],
] as [string, VtMode, number][]) {
  Deno.test(`D7 VirusTotal ${label}: the file is recorded UNAVAILABLE, never clean`, async () => {
    const { w } = await run(mode);
    assertEquals(vtCalls, 1);
    assertEquals(w.scans.length, 1, 'visible: one file_scan row for the arrival');
    const s = w.scans[0];
    assertEquals(s.verdict, 'unavailable', 'an outage is unjudged, never a pass');
    assertEquals(s.blocked, false);
    assertEquals(s.vt_status, status, 'the row carries what VirusTotal answered');
    assertEquals(s.source, 'supplier_catalog_ingest');
    assert(String(s.sha256 || '').length === 64, 'the hash is recorded so a later lookup can judge the same bytes');
    assert(/NOT scanned|returned \d+/.test(String((s.detail as Row)?.reason)), 'the reason names the outage: ' + JSON.stringify(s.detail));
  });
}

// OPEN (3 Nov 2026, it_engineer, drill D7). The matrix expects an unjudged file to be HELD. The code
// accepts it and reads it like a clean one: sanitizeAndScan returns ok:true with scan.cleared=false,
// and neither supplier_catalog_ingest nor supplier_api reads scan.cleared. malware.ts's header records
// this as deliberate (option (c): a VirusTotal 404 'unknown' is the normal case for a genuine trade
// licence, and holding those would refuse every new supplier), so turning it into a hold is a ruling,
// not a bug fix. The narrower gap the drill does prove: NOTHING re-asks VirusTotal about an
// 'unavailable' row after it recovers (no caller of vtLookup outside scanBytes; fn_security_detect only
// raises 'file_unscanned' after 24 h), so a recycled sample that arrived during an outage is never
// judged. Kept as the correct assertion, ignored, until one of those is decided.
Deno.test({
  name: 'D7 matrix expectation: a file VirusTotal could not judge is held, not read into products',
  ignore: true,
  fn: async () => {
    const { r, w } = await run({ status: 503 });
    assertEquals(w.products, [], 'an unjudged price list is not turned into product records');
    assert(r.json.status !== 'extracted', 'the catalogue is held, not extracted');
  },
});
