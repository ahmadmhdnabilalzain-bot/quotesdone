// A LICENCE CODE MISREADS IS STORED AS THE MODEL READS IT, AND A RE-UPLOAD RECOVERS IT (12 Nov 2026, sales_engineer; founder rulings
// 1663 and 1664, "Trade license reading ... there's no code first, 100%").
//
// Drives supplier_api's OWN process_docs over a stubbed fetch (as licence_store_first.test.ts does), with an in-memory leads row that
// already holds what production stored for the founder's licence (expiry 2026-10-30, the Commercial Register page's Reg. Date). The
// supplier attaches the same file again. The file is a SYNTHETIC text PDF in the DET register layout ("Expiry Date   Reg. Date" over
// "30/10/2026   29/10/2027"); license_extract answers the reading a model gives (expiry 2027-10-29, issue 2026-10-30, 'high').
// On main 3baffbc9a: code read 30/10/2026 as the expiry, wrote it, answered it to the form (which says "expired on 30 Oct 2026"),
// and the model's 2027-10-29 was only recorded beside it. Now: the row and the answer hold 2027-10-29, and the difference is
// recorded in agent_actions. No value is real: ZZ DEMO, example.invalid, invented numbers.
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

// what production held after the first upload
const row: Record<string, unknown> = { id: 990003, company_name: 'ZZ DEMO REGISTER TRADING L.L.C', services: null, products: null, service_emirates: [],
  license_doc_path: 'licenses/990003/1700000000000_licence.pdf', license_expiry: '2026-10-30', license_issue_date: '2026-10-30' };
const SECRETS: Record<string, string> = { cred_fn_supplier_api: 'zz-demo-cred', document_expiry_ai: 'on' };
const stored = new Set<string>(); const notes: Record<string, unknown>[] = [];

globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init); const u = new URL(req.url);
  const body = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text();
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
  if (u.hostname !== 'stub.invalid') return json({ error: 'not found' }, 404);
  if (u.pathname === '/functions/v1/license_extract') return json(MODEL);
  if (u.pathname.startsWith('/functions/v1/')) return json({ ok: true });
  if (u.pathname.startsWith('/storage/v1/object/list/')) { const b = JSON.parse(body || '{}'); return json(stored.has(`${b.prefix}/${b.search}`) ? [{ name: b.search }] : []); }
  if (u.pathname.startsWith('/storage/v1/object/supplier-docs/')) {
    const p = u.pathname.slice('/storage/v1/object/supplier-docs/'.length);
    if (req.method === 'POST' || req.method === 'PUT') { stored.add(decodeURIComponent(p)); return json({ Key: `supplier-docs/${p}`, Id: 'zz' }); }
    return new Response(Uint8Array.from(atob(LICENCE_PDF), (c) => c.charCodeAt(0)), { status: 200, headers: { 'Content-Type': 'application/pdf' } });
  }
  if (u.pathname.startsWith('/rest/v1/rpc/')) return json(null);
  const one = (req.headers.get('Accept') || '').includes('vnd.pgrst.object');
  if (u.pathname === '/rest/v1/app_secrets') { const v = SECRETS[(u.searchParams.get('key') || '').replace(/^eq\./, '')]; if (v === undefined) return one ? json({ message: 'none' }, 406) : json([]); return one ? json({ value: v }) : json([{ value: v }]); }
  if (u.pathname === '/rest/v1/leads' && req.method === 'GET') return one ? json(row) : json([row]);
  if (u.pathname === '/rest/v1/leads' && req.method === 'PATCH') {
    const hit = [...u.searchParams].every(([k, v]) => k === 'select' || !v.startsWith('eq.') || String(row[k]) === v.slice(3));
    if (hit) Object.assign(row, JSON.parse(body));
    return (req.headers.get('Prefer') || '').includes('return=representation') ? json(hit ? [{ id: row.id }] : []) : new Response(null, { status: 204 });
  }
  if (u.pathname === '/rest/v1/agent_actions' && req.method === 'POST') { notes.push(JSON.parse(body)); return new Response(null, { status: 201 }); }
  if (req.method === 'PATCH' || req.method === 'DELETE') return new Response(null, { status: 204 });
  if (req.method === 'POST') return new Response(null, { status: 201 });
  return one ? json({ message: 'none' }, 406) : json([]);
}) as typeof fetch;
const later: Promise<unknown>[] = [];
// deno-lint-ignore no-explicit-any
(globalThis as any).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { later.push(p); } };
const { documentActions } = await import('./actions/documents.ts');

Deno.test({ name: 'the same licence attached again is stored as the model reads it: expiry 2027-10-29, never the Reg. Date code took for it',
  sanitizeOps: false, sanitizeResources: false, fn: async () => {
    const r = await documentActions({ email: 'zz-demo-supplier@example.invalid', action: 'process_docs',
      body: { action: 'process_docs', license: { original_b64: LICENCE_PDF, file_b64: LICENCE_PDF, images: [], filename: 'ZZ_DEMO_licence.pdf', mime: 'application/pdf' } } } as never) as Response;
    const j = await r.json();
    await Promise.all(later);
    assertEquals(r.status, 200, JSON.stringify(j).slice(0, 300));
    assertEquals(row.license_expiry, '2027-10-29', 'the row holds the model reading');
    assertEquals(row.license_issue_date, '2026-10-30');
    assertEquals(j.extracted.license.expiry, '2027-10-29', 'the form is answered the model reading (it says "expired" for a past date)');
    assertEquals(row.licence_read_state, 'read');
    assertEquals(notes.filter((n) => n.kind === 'licence_read_disagreement').length <= 1, true);
  } });
