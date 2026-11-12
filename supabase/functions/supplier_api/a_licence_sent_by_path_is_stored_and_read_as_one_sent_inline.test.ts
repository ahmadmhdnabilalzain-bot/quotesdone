// A TRADE LICENCE SENT BY PATH IS STORED, GATED AND READ EXACTLY AS ONE SENT INLINE (12 Nov 2026, customer_support; browser
// perfection walk B1, founder ruling 1645; "Proceed with fixes", ledger 1642).
//
// The walk measured a 4.32 MB phone photo of the licence becoming a 17.29 MB request (process_docs carried its base64 three
// times) that waited 102 s at 1.5 Mbit/s up, was cut off and stored nothing. The form now uploads the licence straight to
// storage (upload_url kind 'licence') and names the path to process_docs, as the profile already went. This drives
// actions/documents.ts itself over a stubbed fetch with a byte-true storage and leads row, and holds the two doors equal:
//   1. upload_url signs a path in the folder the licence is kept in, and refuses a type the licence gate refuses;
//   2. the same file sent inline and by path ends in the same stored bytes and content type, the same row (number, authority,
//      expiry, read state) and the same answer to the form, and asks the model the same way (models off here: USD 0);
//   3. a file the gate refuses (an HTML page named .pdf, an empty file) is refused by path with the inline branch's sentence,
//      leaves storage, and never reaches the row. On main 0b612866e the path branch recorded it as it lay.
// The licences are the certification's own fixtures (scripts/e2e/fixtures/registration: L2 a text PDF, L4 a phone photo).
//   deno test -A --no-lock --node-modules-dir=none supabase/functions/supplier_api/a_licence_sent_by_path_is_stored_and_read_as_one_sent_inline.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');

const FIX = new URL('../../../scripts/e2e/fixtures/registration/', import.meta.url);
const L2 = await Deno.readFile(new URL('L2_abu_dhabi_added.pdf', FIX));
const L4 = await Deno.readFile(new URL('L4_ajman_phone_photo.jpg', FIX));
const SECRETS: Record<string, string> = { cred_fn_supplier_api: 'zz-demo-cred', document_expiry_ai: 'on' };
const blank = () => ({ id: 990011, company_name: 'ZZ DEMO Ghaf Joinery and Carpentry LLC', services: null, products: null, service_emirates: [], license_doc_path: null } as Record<string, unknown>);
let row = blank();
const store = new Map<string, { bytes: Uint8Array; type: string }>();
const modelBodies: Record<string, unknown>[] = [];
const downloads: string[] = [];
let modelsAllowed = false;   // models off: USD 0, as the walk ran (the two reading tests below answer with the stub's model reading)

const b64 = (u: Uint8Array) => { let s = ''; for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000)); return btoa(s); };
globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init); const u = new URL(req.url);
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
  if (u.hostname !== 'stub.invalid') return json({ error: 'not found' }, 404);
  if (u.pathname === '/functions/v1/license_extract') {
    modelBodies.push(JSON.parse(await req.text()));
    return modelsAllowed ? json({ ok: true, doc: { legal_name: 'ZZ DEMO Ghaf Joinery and Carpentry LLC', license_number: 'CN-ZZ482137', license_authority: 'ZZ Abu Dhabi ADDED', expiry_date: '2027-05-03', confidence: 'high', activities: [] } })
      : json({ error: 'models_off', code: 'models_off' }, 503);
  }
  if (u.pathname.startsWith('/functions/v1/')) return json({ ok: true });
  const S = '/storage/v1/object/';
  if (u.pathname.startsWith(S + 'upload/sign/supplier-docs/')) { const p = decodeURIComponent(u.pathname.slice((S + 'upload/sign/supplier-docs/').length)); return json({ url: `/object/upload/sign/supplier-docs/${p}?token=zz-token` }); }
  if (u.pathname.startsWith(S + 'list/')) { const b = JSON.parse(await req.text() || '{}'); const o = store.get(`${b.prefix}/${b.search}`); return json(o ? [{ name: b.search, metadata: { size: o.bytes.length, mimetype: o.type } }] : []); }
  if (u.pathname === S + 'supplier-docs' && req.method === 'DELETE') { const b = JSON.parse(await req.text() || '{}'); for (const p of b.prefixes || []) store.delete(p); return json([]); }
  const objPath = u.pathname.startsWith(S + 'authenticated/supplier-docs/') ? u.pathname.slice((S + 'authenticated/supplier-docs/').length)
    : u.pathname.startsWith(S + 'supplier-docs/') ? u.pathname.slice((S + 'supplier-docs/').length) : null;
  if (objPath !== null) {
    const p = decodeURIComponent(objPath);
    if (req.method === 'POST' || req.method === 'PUT') {
      const raw = new Uint8Array(await req.arrayBuffer());
      // supabase-js sends a Uint8Array body as-is with its content type, or (older) wrapped in FormData
      const ct = req.headers.get('content-type') || '';
      store.set(p, { bytes: raw, type: ct.split(';')[0] || 'application/octet-stream' });
      return json({ Key: `supplier-docs/${p}`, Id: 'zz' });
    }
    if (req.method === 'GET') downloads.push(p);
    const o = store.get(p);
    return o ? new Response(o.bytes as BodyInit, { status: 200, headers: { 'Content-Type': o.type } }) : json({ statusCode: '404', error: 'not_found' }, 400);
  }
  if (u.pathname.startsWith('/rest/v1/rpc/')) return json(null);
  const one = (req.headers.get('Accept') || '').includes('vnd.pgrst.object');
  if (u.pathname === '/rest/v1/app_secrets') { const v = SECRETS[(u.searchParams.get('key') || '').replace(/^eq\./, '')]; if (v === undefined) return one ? json({ message: 'none' }, 406) : json([]); return one ? json({ value: v }) : json([{ value: v }]); }
  if (u.pathname === '/rest/v1/leads' && req.method === 'GET') return one ? json(row) : json([row]);
  if (u.pathname === '/rest/v1/leads' && req.method === 'PATCH') {
    const b = JSON.parse(await req.text());
    const hit = [...u.searchParams].every(([k, v]) => k === 'select' || !v.startsWith('eq.') || String(row[k]) === v.slice(3));
    if (hit) Object.assign(row, b);
    return (req.headers.get('Prefer') || '').includes('return=representation') ? json(hit ? [{ id: row.id }] : []) : new Response(null, { status: 204 });
  }
  if (req.method === 'PATCH' || req.method === 'DELETE') return new Response(null, { status: 204 });
  if (req.method === 'POST') return new Response(null, { status: 201 });
  return one ? json({ message: 'none' }, 406) : json([]);
}) as typeof fetch;
// deno-lint-ignore no-explicit-any
(globalThis as any).EdgeRuntime = { waitUntil: (_p: Promise<unknown>) => {} };
const { documentActions } = await import('./actions/documents.ts');
const act = async (action: string, body: Record<string, unknown>) => {
  const r = await documentActions({ email: 'zz-demo-supplier@example.invalid', action, body: { action, ...body } } as never) as Response;
  return { status: r.status, j: await r.json() };
};
// The browser's half of the path door: sign, then PUT the bytes (src/components/portal/supplier/core/upload.ts uploadDirect).
const byPath = async (bytes: Uint8Array, filename: string, mime: string) => {
  const u = await act('upload_url', { kind: 'licence', filename, mime });
  assertEquals(u.status, 200, JSON.stringify(u.j)); assert(u.j.ok && u.j.token);
  store.set(u.j.path, { bytes, type: mime });
  return { sent: u.j.path as string, ...(await act('process_docs', { license: { path: u.j.path, filename, mime, issued: u.j.issued } })) };
};
const inline = (bytes: Uint8Array, filename: string, mime: string) => {
  const s = b64(bytes);
  return act('process_docs', { license: { original_b64: s, file_b64: s, images: mime.startsWith('image/') ? [{ mime, data: s }] : [], filename, mime } });
};
const ROW = ['trade_license_no', 'license_authority', 'license_expiry', 'licence_legal_name', 'licence_read_state'];
const pick = (o: Record<string, unknown>, ks: string[]) => Object.fromEntries(ks.map((k) => [k, o[k] ?? null]));
// what the form is told, without the path and the moment it was stored
const told = (x: Record<string, unknown>) => JSON.parse(JSON.stringify(x, (k, v) => (k === 'license_doc_path' || k === 'documents_reading' ? undefined : v)));
const settle = () => new Promise((ok) => setTimeout(ok, 50));

async function bothDoors(bytes: Uint8Array, filename: string, mime: string) {
  row = blank(); store.clear(); modelBodies.length = 0;
  const a = await inline(bytes, filename, mime); await settle();
  const aRow = pick(row, ROW); const aObj = store.get(String(row.license_doc_path)); const aPath = String(row.license_doc_path);
  const aModel = modelBodies.map((m) => ({ file: String(m.file_b64 || '').length, images: (m.images as unknown[] || []).length, mime: m.mime }));
  row = blank(); store.clear(); modelBodies.length = 0;
  const b = await byPath(bytes, filename, mime); await settle();
  const bRow = pick(row, ROW); const bObj = store.get(String(row.license_doc_path)); const bPath = String(row.license_doc_path);
  const bModel = modelBodies.map((m) => ({ file: String(m.file_b64 || '').length, images: (m.images as unknown[] || []).length, mime: m.mime }));
  return { a, b, aRow, bRow, aObj, bObj, aPath, bPath, aModel, bModel, sent: b.sent };
}

Deno.test({ name: 'upload_url signs a licence path in the folder a licence is kept in, and refuses a type the licence gate refuses', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  row = blank();
  const ok = await act('upload_url', { kind: 'licence', filename: 'ZZ DEMO licence.jpg', mime: 'image/jpeg' });
  assertEquals(ok.status, 200); assert(/^licenses\/990011\/\d+_/.test(ok.j.path), ok.j.path); assertEquals(ok.j.max_bytes, 10 * 1024 * 1024);
  const no = await act('upload_url', { kind: 'licence', filename: 'licence.docx', mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' });
  assertEquals(no.status, 415); assertEquals(no.j.code, 'file_type_not_allowed');
  assert(/PDF or a clear photo/.test(no.j.message));
} });

for (const [name, bytes, filename, mime] of [['a text PDF (L2)', L2, 'L2_abu_dhabi_added.pdf', 'application/pdf'], ['a phone photo (L4)', L4, 'L4_ajman_phone_photo.jpg', 'image/jpeg']] as const) {
  Deno.test({ name: `${name} sent by path is stored, read and told exactly as the same file sent inline`, sanitizeOps: false, sanitizeResources: false, fn: async () => {
    const r = await bothDoors(bytes, filename, mime);
    assertEquals(r.a.status, 200, JSON.stringify(r.a.j)); assertEquals(r.b.status, 200, JSON.stringify(r.b.j));
    console.log(name, 'row:', JSON.stringify(r.bRow), 'paths:', r.aPath, '|', r.bPath);
    assertEquals(r.bRow, r.aRow, 'the same row');
    assert(/^licenses\/990011\/\d+_/.test(r.bPath), r.bPath);
    assertEquals(r.bPath.replace(/\/\d+_/, '/_'), r.aPath.replace(/\/\d+_/, '/_'), 'the same stored name');
    assertEquals(r.bObj?.type, r.aObj?.type, 'the same content type');
    assertEquals(b64(r.bObj!.bytes), b64(r.aObj!.bytes), 'the same stored bytes');
    assertEquals(told(r.b.j), told(r.a.j), 'the same answer to the form');
    assertEquals(r.b.j.extracted.license_doc_path, r.bPath, 'the answer names the stored file');
    assertEquals(r.bModel.length, r.aModel.length, 'the model is asked as often');
    assertEquals(r.bModel.map((m) => m.mime), r.aModel.map((m) => m.mime));
    const files = [...store.keys()].filter((k) => !k.endsWith('.read.txt'));   // the reader keeps its text beside the file
    assertEquals(files.length, 1, files.join(' , ') + ': one licence object in storage, nothing left over from the browser upload');
  } });
}

// Since 12 Nov 2026 (founder rulings 1663, 1664; review of #1978, F1) the row carries the MODEL's reading only: these read the
// licence through the stub's model answer (still no paid call). Until then they asserted the number and expiry code read.
Deno.test({ name: 'the text PDF reads its number, authority and expiry through the path door (the model reading)', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  modelsAllowed = true;
  const r = await bothDoors(L2, 'L2_abu_dhabi_added.pdf', 'application/pdf').finally(() => { modelsAllowed = false; });
  assertEquals(r.bRow.trade_license_no, 'CN-ZZ482137');
  assertEquals(r.bRow.license_expiry, '2027-05-03');
  assertEquals(r.b.j.extracted.license.expiry, '2027-05-03');
} });

for (const [name, bytes] of [['an HTML page named .pdf', new TextEncoder().encode('<!doctype html><html><body><script>alert(1)</script>ZZ DEMO</body></html>')], ['an empty file', new Uint8Array(0)]] as const) {
  Deno.test({ name: `${name} is refused by path with the inline sentence, leaves storage and never reaches the row`, sanitizeOps: false, sanitizeResources: false, fn: async () => {
    row = blank(); store.clear();
    const a = await inline(bytes as Uint8Array, 'licence.pdf', 'application/pdf');
    row = blank(); store.clear();
    const b = await byPath(bytes as Uint8Array, 'licence.pdf', 'application/pdf');
    assertEquals(b.status, 415, JSON.stringify(b.j));
    assert(/PDF or a clear photo/.test(b.j.message), b.j.message);
    if ((bytes as Uint8Array).length) { assertEquals(a.status, b.status); assertEquals(a.j.message, b.j.message); }
    assertEquals(store.has(b.sent), false, 'the refused file left storage');
    assertEquals(row.license_doc_path, null, 'the row never named it');
  } });
}

// Review of this change (12 Nov 2026, it_engineer finding 3): supplier_api index.ts docs_reread names the row's OWN licence with no
// filename. It must be recorded as it lies: the same path, the same object, nothing copied or deleted. Failed on 23e360ef8.
Deno.test({ name: "the reread sweep's call on the licence the row already names keeps its path, its object and its bytes", sanitizeOps: false, sanitizeResources: false, fn: async () => {
  row = blank(); store.clear();
  const own = 'licenses/990011/1794400000000_IMG_4471.jpg';
  store.set(own, { bytes: L4, type: 'image/jpeg' }); row.license_doc_path = own;
  const r = await act('process_docs', { license: { path: own } });
  assertEquals(r.status, 200, JSON.stringify(r.j));
  assertEquals(row.license_doc_path, own, 'the row keeps its path (fn_leads_licence_read_clock keeps its tries)');
  assertEquals(store.has(own), true, 'the object is not deleted');
  assertEquals([...store.keys()].filter((k) => !k.endsWith('.read.txt')), [own], 'nothing copied beside it');
  assertEquals(b64(store.get(own)!.bytes), b64(L4));
} });

// Review finding 8: over the read ceiling is refused from storage's own size, without downloading the file.
Deno.test({ name: 'a licence over the read ceiling is refused from its stored size without being downloaded', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  row = blank(); store.clear(); downloads.length = 0;
  const u = await act('upload_url', { kind: 'licence', filename: 'big.pdf', mime: 'application/pdf' });
  store.set(u.j.path, { bytes: new Uint8Array(11 * 1024 * 1024), type: 'application/pdf' });
  const r = await act('process_docs', { license: { path: u.j.path, filename: 'big.pdf', mime: 'application/pdf', issued: u.j.issued } });
  assertEquals(r.status, 413, JSON.stringify(r.j));
  assertEquals(downloads.filter((d) => d === u.j.path), [], 'never downloaded');
  assertEquals(store.has(u.j.path), false, 'and it leaves storage');
  assertEquals(row.license_doc_path, null);
} });

// Review round 2, item 4: only the row's own path or a path upload_url issued for this upload. Any other name in his own licence
// folder is refused and left where it is: never moved, never recorded. On 0c2e1e2d0 the old file below was re-stored and recorded.
Deno.test({ name: 'a path in his own licence folder that this server did not issue is refused and left untouched', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  row = blank(); store.clear();
  const other = 'licenses/990011/1700000000000_older_licence.pdf';
  store.set(other, { bytes: L2, type: 'application/pdf' });
  const none = await act('process_docs', { license: { path: other, filename: 'older_licence.pdf', mime: 'application/pdf' } });
  assertEquals(none.status, 400, JSON.stringify(none.j)); assertEquals(none.j.code, 'document_not_found');
  const u = await act('upload_url', { kind: 'licence', filename: 'new.pdf', mime: 'application/pdf' });
  const wrong = await act('process_docs', { license: { path: other, filename: 'older_licence.pdf', mime: 'application/pdf', issued: u.j.issued } });
  assertEquals(wrong.status, 400, 'a token issued for another path does not open this one');
  const forged = await act('process_docs', { license: { path: other, issued: `${Date.now() + 60_000}.${'0'.repeat(64)}` } });
  assertEquals(forged.status, 400, 'a made-up token is refused');
  assertEquals(row.license_doc_path, null, 'never recorded');
  assertEquals(store.has(other), true, 'never moved or deleted');
  assertEquals(b64(store.get(other)!.bytes), b64(L2));
} });
Deno.test({ name: 'the path upload_url issued for this upload is accepted on the real handler', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  row = blank(); store.clear(); modelsAllowed = true;
  const r = await byPath(L2, 'L2_abu_dhabi_added.pdf', 'application/pdf').finally(() => { modelsAllowed = false; });
  assertEquals(r.status, 200, JSON.stringify(r.j)); assertEquals(row.trade_license_no, 'CN-ZZ482137');
} });

// Review round 3, A: the signing key is derived from the credential (never the credential itself, never the service key), an
// unread credential issues nothing and verifies nothing, and only a string can be a token.
Deno.test({ name: 'the licence path key is derived, fails closed without the credential, and takes only a string token', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  const m = await import('./actions/documents.ts');
  const k = await m.licencePathKey('zz-demo-cred');
  assert(k.length === 64 && k !== 'zz-demo-cred', 'a derived 64-hex key');
  assertEquals(await m.licencePathKey(null), '');
  assertEquals(await m.licencePathKey(''), '');
  assertEquals(await m.issueLicencePath('', 990011, 'licenses/990011/1_a.pdf'), null, 'no key, nothing issued');
  const tok = await m.issueLicencePath(k, 990011, 'licenses/990011/1_a.pdf');
  assertEquals(await m.issuedLicencePath(k, 990011, 'licenses/990011/1_a.pdf', tok), true);
  assertEquals(await m.issuedLicencePath('', 990011, 'licenses/990011/1_a.pdf', tok), false, 'no key, nothing verifies');
  assertEquals(await m.issuedLicencePath(k, 990011, 'licenses/990011/1_a.pdf', [tok]), false, 'an array is not a token');
  assertEquals(await m.issuedLicencePath('zz-demo-cred', 990011, 'licenses/990011/1_a.pdf', tok), false, 'the bare credential does not verify it');
  const svc = await m.issueLicencePath(Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, 990011, 'licenses/990011/1_a.pdf');
  assertEquals(await m.issuedLicencePath(k, 990011, 'licenses/990011/1_a.pdf', svc), false, 'a token signed with the service key does not verify');
} });
Deno.test({ name: 'upload_url answers 502 "please try again" when the credential cannot be read, and issues nothing', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  row = blank(); const was = SECRETS.cred_fn_supplier_api; delete SECRETS.cred_fn_supplier_api;
  try {
    const r = await act('upload_url', { kind: 'licence', filename: 'a.pdf', mime: 'application/pdf' });
    assertEquals(r.status, 502); assertEquals(r.j.issued, undefined); assert(/Please try again/.test(r.j.message));
  } finally { SECRETS.cred_fn_supplier_api = was; }
} });
