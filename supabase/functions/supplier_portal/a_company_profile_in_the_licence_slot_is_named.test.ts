// THE DOCUMENTS TAB NAMES A FILE THAT IS NOT A LICENCE (12 Nov 2026, sales_engineer; founder ruling 1668). supplier_portal save_documents
// over a stubbed fetch; license_extract answers as the model would (STAND-INS through the real normaliseLicence, no paid call). SYNTHETIC.
import { assertEquals } from 'jsr:@std/assert@1';
import { normaliseLicence } from '../_shared/licence_extract.ts';
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
const FILE = pdf(['ZZ DEMO FILE']);
let raw: Record<string, unknown> = {};
const SECRETS: Record<string, string> = { cred_fn_supplier_portal: 'zz-demo-cred', document_expiry_ai: 'on' };
let patches: Record<string, unknown>[] = []; let actions: Record<string, unknown>[] = [];
globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init); const u = new URL(req.url);
  const body = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text();
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
  if (u.hostname !== 'stub.invalid') return json({ error: 'not found' }, 404);
  if (u.pathname === '/functions/v1/license_extract') return json({ ok: true, doc: normaliseLicence(raw) });
  if (u.pathname.startsWith('/functions/v1/')) return json({ ok: true });
  if (u.pathname.startsWith('/storage/v1/object/list/')) return json([]);
  if (u.pathname.startsWith('/storage/v1/object/sign/')) return json({ signedURL: '/object/sign/zz?token=zz' });
  if (u.pathname.startsWith('/storage/v1/object/')) return json({ Key: u.pathname, Id: 'zz' });
  if (u.pathname.startsWith('/rest/v1/rpc/')) return json(null);
  const one = (req.headers.get('Accept') || '').includes('vnd.pgrst.object');
  if (u.pathname === '/rest/v1/app_secrets') { const v = SECRETS[(u.searchParams.get('key') || '').replace(/^eq\./, '')]; if (v === undefined) return one ? json({ message: 'none' }, 406) : json([]); return one ? json({ value: v }) : json([{ value: v }]); }
  if (u.pathname === '/rest/v1/leads' && req.method === 'GET') return one ? json({ id: 990009 }) : json([{ id: 990009 }]);
  if (u.pathname === '/rest/v1/leads' && req.method === 'PATCH') { patches.push(JSON.parse(body)); return new Response(null, { status: 204 }); }
  if (u.pathname === '/rest/v1/agent_actions' && req.method === 'POST') { const b = JSON.parse(body); actions.push(...(Array.isArray(b) ? b : [b])); return new Response(null, { status: 201 }); }
  if (req.method === 'PATCH' || req.method === 'DELETE') return new Response(null, { status: 204 });
  if (req.method === 'POST') return new Response(null, { status: 201 });
  return one ? json({ message: 'none' }, 406) : json([]);
}) as typeof fetch;
// deno-lint-ignore no-explicit-any
(globalThis as any).EdgeRuntime = { waitUntil: (_p: Promise<unknown>) => {} };
const { documentActions } = await import('./actions/documents.ts');
const save = async (answer: Record<string, unknown>) => {
  raw = answer; patches = []; actions = [];
  const SUP = { id: 990009, company_name: 'ZZ DEMO TAB TRADING LLC', claimed_by: 'zz-demo-tab2@example.invalid', approval_status: null };
  const b = { action: 'save_documents', items: [{ kind: 'license', original_b64: FILE, mime: 'application/pdf', filename: 'ZZ_DEMO_file.pdf' }] };
  const r = await documentActions({ email: SUP.claimed_by, sup: SUP, supId: SUP.id, b, action: 'save_documents' } as never) as Response;
  return { j: await r.json(), w: Object.assign({}, ...patches) as Record<string, unknown> };
};
const SURE = (kind: string) => ({ legal_name: '', license_number: '', license_authority: '', expiry_date: '', confidence: 'low', document_kind: kind, document_kind_confidence: 'high', document_kind_why: 'not a licence' });

Deno.test({ name: 'save_documents: a profile, a catalogue or an invoice in the licence slot is named; a licence is read as one', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  for (const [kind, words] of [['company_profile', 'a company profile'], ['catalogue', 'a product catalogue or price list'], ['quotation_or_invoice', 'a quotation or an invoice']]) {
    const { j, w } = await save(SURE(kind));
    assertEquals(j.read?.license?.wrong_document, kind);
    assertEquals(String(j.read?.license?.message).startsWith(`This looks like ${words}, not a trade licence.`), true, String(j.read?.license?.message));
    assertEquals([w.licence_read_state, w.trade_license_no, w.license_expiry], ['file_unreadable', null, null]);
    assertEquals(actions.filter((a) => a.kind === 'licence_wrong_document').length, 1);
  }
  const lic = await save({ legal_name: 'ZZ DEMO TAB TRADING LLC', license_number: 'ZZ-777001', license_authority: 'Dubai Department of Economy and Tourism',
    issue_date: '2026-01-01', expiry_date: '2027-12-31', confidence: 'high', document_kind: 'trade_licence', document_kind_confidence: 'high', document_kind_why: 'a DET licence' });
  assertEquals([lic.j.read?.license?.wrong_document, lic.w.license_expiry, lic.w.licence_read_state], [undefined, '2027-12-31', 'read']);
} });
