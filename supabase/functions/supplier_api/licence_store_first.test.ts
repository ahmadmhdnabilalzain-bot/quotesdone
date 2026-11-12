// A STORED LICENCE IS RECORDED AND ANSWERED BEFORE ANYTHING READS IT (11 Nov 2026, customer_support; free supplier registration
// certification, run 2, J5 desktop: L5, an image-only RAKEZ scan, stored 1.7 s in, named on the row only 56 s in, after two
// model attempts; the browser was cut off at ~30 s and told "We could not store your licence file"). lib/licence_store_first.ts.
//
// Drives supplier_api's OWN process_docs over a stubbed fetch (PostgREST, storage, license_extract), with the document model
// switched on and license_extract NEVER answering until the test releases it. Before the fix the action waited on it (two
// attempts, 120 s each) and wrote the row only afterwards, so this test failed on both counts below. No value is real:
// ZZ DEMO, example.invalid, a 1x1 PNG.
import { assert, assertEquals } from 'jsr:@std/assert@1';

Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');

const SUPPLIER = { id: 990001, company_name: 'ZZ DEMO Store First Trading LLC', services: null, products: null, service_emirates: [], license_doc_path: null };
const SECRETS: Record<string, string> = { cred_fn_supplier_api: 'zz-demo-cred', document_expiry_ai: 'on' };
// a 1x1 PNG: an image licence, which code cannot read, so the model is wanted
const PNG_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

type Call = { at: number; method: string; path: string; body: string };
const calls: Call[] = [];
const stored = new Set<string>();
let release!: () => void;
const released = new Promise<void>((ok) => { release = ok; });

globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init);
  const u = new URL(req.url);
  const body = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text();
  calls.push({ at: Date.now(), method: req.method, path: u.pathname, body });
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
  if (u.hostname !== 'stub.invalid') return json({ error: 'not found' }, 404);
  // THE MODEL: answers nothing until released, then the 502 production gave on 11 Nov (every model route open-circuit)
  if (u.pathname === '/functions/v1/license_extract') { await released; return json({ error: 'ai_error', detail: 'every model route for this task class is open-circuit' }, 502); }
  if (u.pathname.startsWith('/functions/v1/')) return json({ ok: true });
  if (u.pathname.startsWith('/storage/v1/object/list/')) {
    const b = JSON.parse(body || '{}'); const full = `${b.prefix}/${b.search}`;
    return json(stored.has(full) ? [{ name: b.search }] : []);
  }
  if (u.pathname.startsWith('/storage/v1/object/supplier-docs/')) {
    const p = u.pathname.slice('/storage/v1/object/supplier-docs/'.length);
    if (req.method === 'POST' || req.method === 'PUT') { stored.add(decodeURIComponent(p)); return json({ Key: `supplier-docs/${p}`, Id: 'zz' }); }
    return new Response(Uint8Array.from(atob(PNG_B64), (c) => c.charCodeAt(0)), { status: 200, headers: { 'Content-Type': 'image/png' } });
  }
  if (u.pathname.startsWith('/rest/v1/rpc/')) return json(null);
  const one = (req.headers.get('Accept') || '').includes('vnd.pgrst.object');
  if (u.pathname === '/rest/v1/app_secrets') {
    const v = SECRETS[(u.searchParams.get('key') || '').replace(/^eq\./, '')];
    if (v === undefined) return one ? json({ message: 'none' }, 406) : json([]);
    return one ? json({ value: v }) : json([{ value: v }]);
  }
  if (u.pathname === '/rest/v1/leads' && req.method === 'GET') return one ? json(SUPPLIER) : json([SUPPLIER]);
  if (req.method === 'PATCH' || req.method === 'DELETE') return new Response(null, { status: 204 });
  if (req.method === 'POST') return new Response(null, { status: 201 });
  return one ? json({ message: 'none' }, 406) : json([]);
}) as typeof fetch;

// After the answer, work goes to the edge runtime's waitUntil, as in production.
const later: Promise<unknown>[] = [];
// deno-lint-ignore no-explicit-any
(globalThis as any).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { later.push(p); } };

const { documentActions } = await import('./actions/documents.ts');
const { MODEL_ANSWER_BUDGET_MS, licenceRecordedFirst, modelReadingToRow, withinBudget } = await import('./lib/licence_store_first.ts');

const leadPatches = () => calls.filter((c) => c.method === 'PATCH' && c.path === '/rest/v1/leads').map((c) => ({ ...c, row: JSON.parse(c.body) }));

Deno.test({
  name: 'process_docs names the stored licence on the row before the model is asked, and answers without waiting for a model that does not answer',
  sanitizeOps: false, sanitizeResources: false,
  fn: async () => {
    const t0 = Date.now();
    const action = 'process_docs';
    const body = { action, license: { original_b64: PNG_B64, file_b64: PNG_B64, images: [], filename: 'ZZ_DEMO_licence_scan.png', mime: 'image/png' } };
    const run = documentActions({ email: 'zz-demo-supplier@example.invalid', body, action } as never);
    // Production's cut came at ~30 s; the old action waited 2 x 120 s here.
    const guard = new Promise<'cut'>((ok) => setTimeout(() => ok('cut'), 30_000));
    const r = await Promise.race([run, guard]);
    const ms = Date.now() - t0;
    try {
      assert(r !== 'cut', 'process_docs did not answer within 30 s while the model was silent: the licence step waits on reading');
      assert(ms < MODEL_ANSWER_BUDGET_MS + 5_000, `answered in ${ms} ms; it may wait for the model at most ${MODEL_ANSWER_BUDGET_MS} ms`);
      const j = await (r as Response).json();
      assertEquals(r && (r as Response).status, 200);
      assertEquals(j.ok, true, 'a stored licence is answered as stored');
      assertEquals(j.extracted.license_read_state, 'ours_failed', 'the supplier is told our reader has not finished, never that the file failed');
      assertEquals(j.extracted.licence_read_after_answer, true);

      const firstModel = calls.findIndex((c) => c.path === '/functions/v1/license_extract');
      const named = calls.findIndex((c) => c.method === 'PATCH' && c.path === '/rest/v1/leads' && /"license_doc_path":"licenses\/990001\//.test(c.body));
      assert(named >= 0, 'the row was never written with the stored licence path');
      assert(firstModel < 0 || named < firstModel, 'the row must name the stored licence BEFORE the model is asked to read it');
      const first = leadPatches()[0].row;
      assertEquals(first.licence_read_state, 'ours_failed', 'until it is read, the row says our reader has not finished (the sweep reads it again)');
      assertEquals(first.trade_license_no, null, "the old licence's number never judges a new file");
      assert(stored.has(first.license_doc_path), 'the path written is the object storage holds');
    } finally { release(); }
    // Released: the model answers its 502 after the answer, and its own write records whose failure the unread licence is.
    // the model's own write carries nothing but the state it ended in (it read no field)
    const modelWrite = () => leadPatches().find((p) => !('license_doc_path' in p.row) && 'licence_read_state' in p.row);
    for (let i = 0; i < 200 && !modelWrite(); i++) await new Promise((ok) => setTimeout(ok, 50));
    assert(modelWrite(), 'the model read, finishing after the answer, never wrote its outcome to the row');
    assertEquals(modelWrite()!.row.licence_read_state, 'ours_failed', "a model that failed after the answer leaves the licence ours to read again, never the supplier's");
    assert(calls.findIndex((c) => c.path === '/functions/v1/license_extract') > calls.findIndex((c) => c.method === 'PATCH' && /license_doc_path/.test(c.body)));
  },
});

Deno.test('a licence already named on the row is not recorded again (the sweep re-reads the same file); a new one clears the old readings', () => {
  assertEquals(licenceRecordedFirst('licenses/1/a.pdf', 'licenses/1/a.pdf'), null);
  const w = licenceRecordedFirst('licenses/1/b.pdf', 'licenses/1/a.pdf', '2026-11-11T14:45:31.000Z')!;
  assertEquals(w.license_doc_path, 'licenses/1/b.pdf');
  assertEquals([w.trade_license_no, w.license_authority, w.license_expiry, w.licence_legal_name], [null, null, null, null]);
  assertEquals(w.licence_read_state, 'ours_failed');
  assertEquals(licenceRecordedFirst('', null), null);
});

Deno.test('withinBudget answers when the work is late, and gives the value when it is not', async () => {
  const never = new Promise<number>(() => {});
  assertEquals(await withinBudget(never, 20), { done: false });
  assertEquals(await withinBudget(Promise.resolve(7), 1_000), { done: true, value: 7 });
});

// Corrected 12 Nov 2026 (sales_engineer), founder rulings 1663 and 1664 ("Trade license reading ... there's no code first, 100%").
// Until then this asserted that the model only filled what code left blank and never moved code's expiry: the founder's own DET
// licence was refused as expired on that rule (code had read the register's Reg. Date as the expiry). A sure read now replaces code's.
Deno.test("the model's reading is written in every field it read, code's never; each difference is listed", () => {
  const d = { license_number: 'ZZ-M-1', license_authority: 'ZZ Model Authority', expiry_date: '2027-01-01', legal_name: 'ZZ DEMO LLC', emirate: 'Dubai', trn: '100000000000003', issue_date: '2025-01-02T00:00:00Z', confidence: 'high' };
  const code = { fields: { licence_no: 'ZZ-C-9', authority: 'ZZ Code Authority', emirate: 'Sharjah' }, expiry: '2026-12-31', name: 'ZZ DEMO Code Name', issue: null };
  const sure = modelReadingToRow(d, code);
  assertEquals([sure.upd.trade_license_no, sure.upd.license_authority, sure.upd.license_expiry, sure.upd.emirate, sure.upd.licence_legal_name],
    ['ZZ-M-1', 'ZZ Model Authority', '2027-01-01', 'Dubai', 'ZZ DEMO LLC']);
  assertEquals(sure.expiryDiffers, { code: '2026-12-31', model: '2027-01-01' });
  assertEquals(sure.disagreements.map((x) => x.field).sort(), ['authority', 'emirate', 'expiry_date', 'legal_name_en', 'licence_no']);
  assertEquals(sure.issue, '2025-01-02');
  // review of #1978 (F1/F3): code's values never reach the row, beside a 'low' read either; a low read's name is not a name
  const low = modelReadingToRow({ ...d, confidence: 'low' }, code);
  assertEquals([low.upd.trade_license_no, low.upd.license_authority, low.upd.license_expiry, low.upd.emirate, low.upd.licence_legal_name], ['ZZ-M-1', 'ZZ Model Authority', '2027-01-01', 'Dubai', undefined]);
  const blank = modelReadingToRow(d, { fields: {}, expiry: null, name: null, issue: undefined });
  assertEquals([blank.upd.trade_license_no, blank.upd.license_authority, blank.upd.license_expiry, blank.upd.trn], ['ZZ-M-1', 'ZZ Model Authority', '2027-01-01', '100000000000003']);
});
