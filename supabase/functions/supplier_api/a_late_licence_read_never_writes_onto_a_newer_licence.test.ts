// A SLOW READ OF A LICENCE THE SUPPLIER HAS SINCE REPLACED NEVER WRITES ONTO THE NEWER FILE (12 Nov 2026, customer_support; final
// audit R3 = code review F3 and regcert_diagnosis F3; founder "Proceed with fixes", ledger 1642). lib/licence_store_first.ts writerForFile.
//
// supplier_api/actions/documents.ts askLicenceModel (#1947) writes the model's reading AFTER the answer, up to 23 s later on
// production (11 Nov, run 2 J1), and filtered that write by the lead id only. Drives process_docs itself over a stubbed fetch, as
// licence_store_first.test.ts does, with an in-memory leads row whose PATCH honours the request's filters (id, license_doc_path)
// and answers the rows it changed:
//   1. licence A is uploaded; its model read does not answer inside MODEL_ANSWER_BUDGET_MS, so the answer leaves without it;
//   2. the supplier uploads licence B; its model read answers at once and the row holds B's number;
//   3. A's model read answers late.
// What must hold: the row that names file B holds B's readings. On main 2cc9d1017 it ends with A's number, authority and expiry
// (the audit's repro/late_licence_write.test.ts). No value is real: ZZ DEMO, example.invalid, a 1x1 PNG. Takes ~11 s (the real budget).
//   deno test -A --no-lock --node-modules-dir=none supabase/functions/supplier_api/a_late_licence_read_never_writes_onto_a_newer_licence.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');

const row: Record<string, unknown> = { id: 990002, company_name: 'ZZ DEMO Late Write Trading LLC', services: null, products: null, service_emirates: [], license_doc_path: null };
const SECRETS: Record<string, string> = { cred_fn_supplier_api: 'zz-demo-cred', document_expiry_ai: 'on' };
const PNG_B64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const READING = (n: string) => ({ ok: true, doc: { legal_name: 'ZZ DEMO Late Write Trading LLC', license_number: `ZZ-${n}-0001`, license_authority: `ZZ Authority ${n}`, expiry_date: n === 'A' ? '2027-01-01' : '2028-02-02', confidence: 'high', activities: [] } });
const stored = new Set<string>(); const writes: string[] = [];
let modelCalls = 0; let releaseA!: () => void; const aReleased = new Promise<void>((ok) => { releaseA = ok; });

globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init); const u = new URL(req.url);
  const body = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text();
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
  if (u.hostname !== 'stub.invalid') return json({ error: 'not found' }, 404);
  if (u.pathname === '/functions/v1/license_extract') { const n = ++modelCalls; if (n === 1) { await aReleased; return json(READING('A')); } return json(READING('B')); }
  if (u.pathname.startsWith('/functions/v1/')) return json({ ok: true });
  if (u.pathname.startsWith('/storage/v1/object/list/')) { const b = JSON.parse(body || '{}'); return json(stored.has(`${b.prefix}/${b.search}`) ? [{ name: b.search }] : []); }
  if (u.pathname.startsWith('/storage/v1/object/supplier-docs/')) {
    const p = u.pathname.slice('/storage/v1/object/supplier-docs/'.length);
    if (req.method === 'POST' || req.method === 'PUT') { stored.add(decodeURIComponent(p)); return json({ Key: `supplier-docs/${p}`, Id: 'zz' }); }
    return new Response(Uint8Array.from(atob(PNG_B64), (c) => c.charCodeAt(0)), { status: 200, headers: { 'Content-Type': 'image/png' } });
  }
  if (u.pathname.startsWith('/rest/v1/rpc/')) return json(null);
  const one = (req.headers.get('Accept') || '').includes('vnd.pgrst.object');
  if (u.pathname === '/rest/v1/app_secrets') { const v = SECRETS[(u.searchParams.get('key') || '').replace(/^eq\./, '')]; if (v === undefined) return one ? json({ message: 'none' }, 406) : json([]); return one ? json({ value: v }) : json([{ value: v }]); }
  if (u.pathname === '/rest/v1/leads' && req.method === 'GET') return one ? json(row) : json([row]);
  if (u.pathname === '/rest/v1/leads' && req.method === 'PATCH') {
    // PostgREST: only a row every eq. filter matches is changed; with return=representation the changed rows are the answer
    const b = JSON.parse(body);
    const hit = [...u.searchParams].every(([k, v]) => k === 'select' || !v.startsWith('eq.') || String(row[k]) === v.slice(3));
    if (hit) Object.assign(row, b);
    writes.push(`PATCH leads ${hit ? '' : '(no row) '}${decodeURIComponent(u.search)}  ${JSON.stringify(Object.fromEntries(Object.entries(b).filter(([k]) => ['license_doc_path', 'trade_license_no', 'license_authority', 'license_expiry', 'licence_read_state'].includes(k))))}`);
    return (req.headers.get('Prefer') || '').includes('return=representation') ? json(hit ? [{ id: row.id }] : []) : new Response(null, { status: 204 });
  }
  if (req.method === 'PATCH' || req.method === 'DELETE') return new Response(null, { status: 204 });
  if (req.method === 'POST') return new Response(null, { status: 201 });
  return one ? json({ message: 'none' }, 406) : json([]);
}) as typeof fetch;
// deno-lint-ignore no-explicit-any
(globalThis as any).EdgeRuntime = { waitUntil: (_p: Promise<unknown>) => {} };
const { documentActions } = await import('./actions/documents.ts');
const upload = (filename: string) => documentActions({ email: 'zz-demo-supplier@example.invalid', action: 'process_docs',
  body: { action: 'process_docs', license: { original_b64: PNG_B64, file_b64: PNG_B64, images: [], filename, mime: 'image/png' } } } as never);

Deno.test({ name: "a slow read of a licence the supplier has since replaced never writes its fields onto the row that names the new file",
  sanitizeOps: false, sanitizeResources: false, fn: async () => {
    const a = await (await upload('ZZ_DEMO_licence_A.png') as Response).json();
    assertEquals(a.extracted.licence_read_after_answer, true, 'licence A: the answer left before its model read finished');
    const pathA = String(row.license_doc_path);
    await new Promise((ok) => setTimeout(ok, 5));
    const b = await (await upload('ZZ_DEMO_licence_B.png') as Response).json();
    const pathB = String(row.license_doc_path);
    assert(pathB !== pathA && /licence_B/.test(pathB), 'the row names file B');
    assertEquals(b.extracted.license.license_number, 'ZZ-B-0001', 'licence B was read and shown back');
    assertEquals(row.trade_license_no, 'ZZ-B-0001');
    releaseA();                                             // licence A's model read answers now
    for (let i = 0; i < 100 && row.trade_license_no === 'ZZ-B-0001'; i++) await new Promise((ok) => setTimeout(ok, 20));
    await new Promise((ok) => setTimeout(ok, 100));
    console.log('writes to the row, in order:\n  ' + writes.join('\n  '));
    console.log('final row:', JSON.stringify({ license_doc_path: row.license_doc_path, trade_license_no: row.trade_license_no, license_authority: row.license_authority, license_expiry: row.license_expiry, licence_read_state: row.licence_read_state }));
    assertEquals(row.license_doc_path, pathB);
    assertEquals([row.trade_license_no, row.license_authority, row.license_expiry], ['ZZ-B-0001', 'ZZ Authority B', '2028-02-02'], "the row that names file B holds file B's readings, not file A's late ones");
  } });
