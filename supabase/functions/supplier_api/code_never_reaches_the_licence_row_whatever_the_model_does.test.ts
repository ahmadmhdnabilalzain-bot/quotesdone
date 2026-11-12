// CODE'S READING NEVER REACHES THE ROW, WHATEVER THE MODEL DOES (12 Nov 2026, sales_engineer; founder rulings 1663 and 1664; independent
// review of #1978, F1). The reviewer drove process_docs with a text licence that code reads in full (number, name, authority and an
// expiry of 2028-01-01) and a model that reads 2027-05-05. With the model high the row was right; with the model low or unreadable,
// failing, or answering after the 10 s budget, code's 2028-01-01 was stored and shown with the read state 'read', which the re-read
// sweep never picks up and the form never polls. This drives supplier_api's OWN process_docs through those four cases over a stubbed
// fetch. Every value is SYNTHETIC (ZZ DEMO, invented numbers and dates). Takes ~11 s (the late case waits the real budget).
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
// a plain text licence code reads completely: its expiry, by code, is 2028-01-01
const LICENCE_PDF = pdf(['Trade Licence', 'Licence No: ZZ-4400123', 'Legal Name: ZZ DEMO FOUR CASES TRADING LLC',
  'Issuing Authority: Dubai Department of Economy and Tourism', 'Issue Date: 02/01/2025', 'Expiry Date: 01/01/2028']);
const HIGH = { ok: true, doc: { legal_name: 'ZZ DEMO FOUR CASES TRADING LLC', license_number: 'ZZ-4400123', license_authority: 'Dubai Department of Economy and Tourism',
  emirate: 'Dubai', issue_date: '2025-01-02', expiry_date: '2027-05-05', activities: [], confidence: 'high' } };
type Mode = 'high' | 'unreadable' | 'error' | 'late';
let mode: Mode = 'high'; let releaseLate!: () => void;
const row: Record<string, unknown> = { id: 990005, company_name: 'ZZ DEMO FOUR CASES TRADING LLC', services: null, products: null, service_emirates: [], license_doc_path: null };
const SECRETS: Record<string, string> = { cred_fn_supplier_api: 'zz-demo-cred', document_expiry_ai: 'on' };
const stored = new Set<string>();

globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init); const u = new URL(req.url);
  const body = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text();
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
  if (u.hostname !== 'stub.invalid') return json({ error: 'not found' }, 404);
  if (u.pathname === '/functions/v1/license_extract') {
    if (mode === 'high') return json(HIGH);
    if (mode === 'unreadable') return json({ ok: true, doc: { ...HIGH.doc, legal_name: '', license_number: '', expiry_date: null, issue_date: null, confidence: 'low', unreadable: true } });
    if (mode === 'error') return json({ error: 'ai_error', detail: 'every model route for this task class is open-circuit' }, 502);
    await new Promise<void>((ok) => { releaseLate = ok; }); return json(HIGH);
  }
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
  if (req.method === 'PATCH' || req.method === 'DELETE') return new Response(null, { status: 204 });
  if (req.method === 'POST') return new Response(null, { status: 201 });
  return one ? json({ message: 'none' }, 406) : json([]);
}) as typeof fetch;
const later: Promise<unknown>[] = [];
// deno-lint-ignore no-explicit-any
(globalThis as any).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { later.push(p); } };
const { documentActions } = await import('./actions/documents.ts');
const upload = async (m: Mode, settle = true) => {
  mode = m;
  const r = await documentActions({ email: 'zz-demo-supplier@example.invalid', action: 'process_docs',
    body: { action: 'process_docs', license: { original_b64: LICENCE_PDF, file_b64: LICENCE_PDF, images: [], filename: `ZZ_DEMO_${m}.pdf`, mime: 'application/pdf' } } } as never) as Response;
  const j = await r.json();
  if (settle) await Promise.all(later.splice(0));
  return j.extracted;
};
const shown = (x: Record<string, unknown>) => (x.license as Record<string, unknown> | undefined)?.expiry ?? null;

Deno.test({ name: "code's 2028-01-01 is never stored or shown: model high, unreadable, failing, or late", sanitizeOps: false, sanitizeResources: false, fn: async () => {
  const high = await upload('high');
  assertEquals([row.license_expiry, row.licence_read_state, shown(high)], ['2027-05-05', 'read', '2027-05-05']);
  const unreadable = await upload('unreadable');
  assertEquals([row.license_expiry, row.trade_license_no, row.licence_read_state, shown(unreadable)], [null, null, 'file_unreadable', null]);
  const failed = await upload('error');
  assertEquals([row.license_expiry, row.trade_license_no, row.licence_read_state, failed.license_read_state, shown(failed)], [null, null, 'ours_failed', 'ours_failed', null]);
  // late: the answer leaves at the budget saying ours_failed, so the form polls; the row then becomes the model's reading
  const late = await upload('late', false);
  assertEquals([late.license_read_state, late.licence_read_after_answer, shown(late), row.license_expiry, row.licence_read_state], ['ours_failed', true, null, null, 'ours_failed']);
  releaseLate();
  await Promise.all(later.splice(0));
  for (let i = 0; i < 100 && row.licence_read_state !== 'read'; i++) await new Promise((ok) => setTimeout(ok, 20));
  assertEquals([row.license_expiry, row.licence_read_state], ['2027-05-05', 'read']);
  assert(!JSON.stringify(row).includes('2028-01-01'), "code's expiry reached the row");
} });
