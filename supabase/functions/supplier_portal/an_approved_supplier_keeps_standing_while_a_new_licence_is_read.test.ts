// AN APPROVED SUPPLIER KEEPS HIS STANDING WHILE A NEW LICENCE IS READ, ON THE DOCUMENTS TAB TOO (12 Nov 2026, sales_engineer; second
// review of #1978, defect A). The other licence door, supplier_portal save_documents, over a stubbed fetch; supplier_api's own test
// (an_approved_supplier_keeps_standing_while_a_new_licence_is_read.test.ts) says why. Every value is SYNTHETIC (ZZ DEMO).
import { assert, assertEquals } from 'jsr:@std/assert@1';
Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');

const enc = new TextEncoder();
const esc = (s: string) => s.replace(/[\\()]/g, (c) => '\\' + c);
const pdf = (lines: string[]) => {
  const body = lines.map((l, i) => `BT /F1 10 Tf 1 0 0 1 60 ${760 - 20 * i} Tm (${esc(l)}) Tj ET`).join('\n');
  const s = enc.encode(body);
  const head = enc.encode(`%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 5 0 R >>\nendobj\n5 0 obj\n<< /Length ${s.length} >>\nstream\n`);
  const tail = enc.encode('\nendstream\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n');
  const out = new Uint8Array(head.length + s.length + tail.length); out.set(head); out.set(s, head.length); out.set(tail, head.length + s.length);
  let bin = ''; for (const b of out) bin += String.fromCharCode(b);
  return btoa(bin);
};
const LICENCE_PDF = pdf(['Trade Licence', 'Licence No: ZZ-5500124', 'Legal Name: ZZ DEMO TAB TRADING LLC', 'Expiry Date: 01/06/2028']);
const READ = { ok: true, doc: { legal_name: 'ZZ DEMO TAB TRADING LLC', license_number: 'ZZ-5500124', license_authority: 'Dubai Department of Economy and Tourism',
  emirate: 'Dubai', issue_date: '2027-01-31', expiry_date: '2028-01-30', activities: [], confidence: 'high' } };
let modelUp = false;
const SECRETS: Record<string, string> = { cred_fn_supplier_portal: 'zz-demo-cred', document_expiry_ai: 'on' };
let patches: Record<string, unknown>[] = []; let actions: Record<string, unknown>[] = [];
globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init); const u = new URL(req.url);
  const body = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text();
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
  if (u.hostname !== 'stub.invalid') return json({ error: 'not found' }, 404);
  if (u.pathname === '/functions/v1/license_extract') return modelUp ? json(READ) : json({ error: 'ai_error' }, 502);
  if (u.pathname.startsWith('/functions/v1/')) return json({ ok: true });
  if (u.pathname.startsWith('/storage/v1/object/list/')) return json([]);
  if (u.pathname.startsWith('/storage/v1/object/sign/')) return json({ signedURL: '/object/sign/zz?token=zz' });
  if (u.pathname.startsWith('/storage/v1/object/')) return json({ Key: u.pathname, Id: 'zz' });
  if (u.pathname.startsWith('/rest/v1/rpc/')) return json(null);
  const one = (req.headers.get('Accept') || '').includes('vnd.pgrst.object');
  if (u.pathname === '/rest/v1/app_secrets') { const v = SECRETS[(u.searchParams.get('key') || '').replace(/^eq\./, '')]; if (v === undefined) return one ? json({ message: 'none' }, 406) : json([]); return one ? json({ value: v }) : json([{ value: v }]); }
  if (u.pathname === '/rest/v1/leads' && req.method === 'GET') return one ? json({ id: 990007 }) : json([{ id: 990007 }]);
  if (u.pathname === '/rest/v1/leads' && req.method === 'PATCH') { patches.push(JSON.parse(body)); return new Response(null, { status: 204 }); }
  if (u.pathname === '/rest/v1/agent_actions' && req.method === 'POST') { const b = JSON.parse(body); actions.push(...(Array.isArray(b) ? b : [b])); return new Response(null, { status: 201 }); }
  if (req.method === 'PATCH' || req.method === 'DELETE') return new Response(null, { status: 204 });
  if (req.method === 'POST') return new Response(null, { status: 201 });
  return one ? json({ message: 'none' }, 406) : json([]);
}) as typeof fetch;
// deno-lint-ignore no-explicit-any
(globalThis as any).EdgeRuntime = { waitUntil: (_p: Promise<unknown>) => {} };
const { documentActions } = await import('./actions/documents.ts');
const save = async (approval: string | null, up: boolean) => {
  modelUp = up; patches = []; actions = [];
  const SUP = { id: 990007, company_name: 'ZZ DEMO TAB TRADING LLC', claimed_by: 'zz-demo-tab@example.invalid', approval_status: approval };
  const b = { action: 'save_documents', items: [{ kind: 'license', original_b64: LICENCE_PDF, mime: 'application/pdf', filename: 'ZZ_DEMO_new.pdf' }] };
  const r = await documentActions({ email: SUP.claimed_by, sup: SUP, supId: SUP.id, b, action: 'save_documents' } as never) as Response;
  const j = await r.json();
  return { j, w: Object.assign({}, ...patches) as Record<string, unknown> };
};
const KEYS = ['trade_license_no', 'license_authority', 'license_expiry', 'licence_legal_name', 'license_issue_date'];

Deno.test({ name: "save_documents: an approved supplier's accepted reading stays while the provider is down, and the new reading replaces it", sanitizeOps: false, sanitizeResources: false, fn: async () => {
  const down = await save('approved', false);
  assert(String(down.w.license_doc_path || '').length > 0, 'the new file is recorded');
  for (const k of KEYS) assert(!(k in down.w), `${k} was written while nothing was read`);
  assertEquals(down.w.licence_read_state, 'ours_failed');
  assertEquals(down.j.read?.license?.being_read, true, 'the tab says the new licence is being read');
  // review of #1982, L3-2: staff are told the fields on file are the previously accepted reading
  assertEquals(actions.filter((a) => a.kind === 'licence_new_file_being_read').length, 1);
  const read = await save('approved', true);
  assertEquals(KEYS.map((k) => read.w[k]), ['ZZ-5500124', 'Dubai Department of Economy and Tourism', '2028-01-30', 'ZZ DEMO TAB TRADING LLC', '2027-01-31']);
  assertEquals(read.w.licence_read_state, 'read');
} });

Deno.test({ name: 'save_documents: a supplier who is not approved is cleared at once, as before', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  const { w } = await save('pending', false);
  assertEquals(KEYS.map((k) => w[k]), [null, null, null, null, null]);
  assertEquals(w.licence_read_state, 'ours_failed');
} });
