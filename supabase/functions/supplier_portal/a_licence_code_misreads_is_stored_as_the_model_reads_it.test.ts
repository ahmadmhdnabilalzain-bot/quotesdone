// THE DOCUMENTS TAB STORES A LICENCE CODE MISREADS AS THE MODEL READS IT (12 Nov 2026, sales_engineer; founder rulings 1663, 1664).
// The other licence door, supplier_portal save_documents, driven over a stubbed fetch as licence_read_is_bounded.test.ts does. The
// file is a SYNTHETIC text PDF in the DET Commercial Register layout ("Expiry Date   Reg. Date" over "30/10/2026   29/10/2027");
// license_extract answers a model's 'high' reading (expiry 2027-10-29, issue 2026-10-30). On main 3baffbc9a the model was not even
// asked (code had read every field) and the row was written expiry 2026-10-30, the Reg. Date. No value is real.
import { assertEquals } from 'jsr:@std/assert@1';
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
// the DET Commercial Register page's own layout (synthetic values)
const LICENCE_PDF = pdf(['Commercial Register', 'License No. 9990002', 'Company Name ZZ DEMO REGISTER TRADING L.L.C',
  'Issuing Authority Dubai Department of Economy and Tourism', 'Expiry Date   Reg. Date   30/10/2026   29/10/2027']);
const MODEL = { ok: true, doc: { legal_name: 'ZZ DEMO REGISTER TRADING L.L.C', license_number: '9990002', license_authority: 'Dubai Department of Economy and Tourism',
  emirate: 'Dubai', issue_date: '2026-10-30', expiry_date: '2027-10-29', activities: ['General Trading'], confidence: 'high' } };

const SUP = { id: 990004, company_name: 'ZZ DEMO REGISTER TRADING L.L.C', claimed_by: 'zz-demo-docs@example.invalid' };
const SECRETS: Record<string, string> = { cred_fn_supplier_portal: 'zz-demo-cred', document_expiry_ai: 'on' };
const patches: Record<string, unknown>[] = [];
globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init); const u = new URL(req.url);
  const body = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text();
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
  if (u.hostname !== 'stub.invalid') return json({ error: 'not found' }, 404);
  if (u.pathname === '/functions/v1/license_extract') return json(MODEL);
  if (u.pathname.startsWith('/functions/v1/')) return json({ ok: true });
  if (u.pathname.startsWith('/storage/v1/object/list/')) return json([]);
  if (u.pathname.startsWith('/storage/v1/object/sign/')) return json({ signedURL: '/object/sign/zz?token=zz' });
  if (u.pathname.startsWith('/storage/v1/object/')) return json({ Key: u.pathname, Id: 'zz' });
  if (u.pathname.startsWith('/rest/v1/rpc/')) return json(null);
  const one = (req.headers.get('Accept') || '').includes('vnd.pgrst.object');
  if (u.pathname === '/rest/v1/app_secrets') { const v = SECRETS[(u.searchParams.get('key') || '').replace(/^eq\./, '')]; if (v === undefined) return one ? json({ message: 'none' }, 406) : json([]); return one ? json({ value: v }) : json([{ value: v }]); }
  if (u.pathname === '/rest/v1/leads' && req.method === 'GET') return one ? json({ id: SUP.id }) : json([{ id: SUP.id }]);
  if (u.pathname === '/rest/v1/leads' && req.method === 'PATCH') { patches.push(JSON.parse(body)); return new Response(null, { status: 204 }); }
  if (req.method === 'PATCH' || req.method === 'DELETE') return new Response(null, { status: 204 });
  if (req.method === 'POST') return new Response(null, { status: 201 });
  return one ? json({ message: 'none' }, 406) : json([]);
}) as typeof fetch;
// deno-lint-ignore no-explicit-any
(globalThis as any).EdgeRuntime = { waitUntil: (_p: Promise<unknown>) => {} };
const { documentActions } = await import('./actions/documents.ts');

Deno.test({ name: "save_documents stores the model's reading of a licence code misreads: expiry 2027-10-29, never the Reg. Date",
  sanitizeOps: false, sanitizeResources: false, fn: async () => {
    const b = { action: 'save_documents', items: [{ kind: 'license', original_b64: LICENCE_PDF, mime: 'application/pdf', filename: 'ZZ_DEMO_licence.pdf' }] };
    const r = await documentActions({ email: SUP.claimed_by, sup: SUP, supId: SUP.id, b, action: 'save_documents' } as never) as Response;
    const j = await r.json();
    const row = Object.assign({}, ...patches.filter((p) => 'license_doc_path' in p || 'license_expiry' in p || 'license_issue_date' in p));
    assertEquals(row.license_expiry, '2027-10-29', JSON.stringify(j).slice(0, 300));
    assertEquals(row.license_issue_date, '2026-10-30');
    assertEquals(row.licence_read_state, 'read');
  } });
