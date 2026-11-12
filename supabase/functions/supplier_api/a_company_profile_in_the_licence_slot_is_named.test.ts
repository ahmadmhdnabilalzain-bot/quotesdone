// A COMPANY PROFILE IN THE LICENCE SLOT IS NAMED, AT ONCE OR LATE, AND NOTHING OF IT IS READ AS A LICENCE (12 Nov 2026, sales_engineer;
// founder ruling 1668: "on purpose, I attached the company profile instead of the trade license ... It kept saying ... your document
// is being read"). Drives supplier_api's OWN process_docs over a stubbed fetch with an in-memory leads row; license_extract answers as
// the model would (STAND-INS, no paid call), passed through the real normaliseLicence. Every value is SYNTHETIC (ZZ DEMO).
import { assert, assertEquals } from 'jsr:@std/assert@1';
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
const PROFILE_PDF = pdf(['ZZ DEMO MEP CONTRACTING LLC', 'Company Profile', 'Our services: HVAC installation, plumbing, electrical works', 'Projects: ZZ DEMO Tower, ZZ DEMO Mall']);
const answer = (raw: Record<string, unknown>) => ({ ok: true, doc: normaliseLicence(raw) });
const SURE_PROFILE = { legal_name: '', license_number: '', license_authority: '', expiry_date: '', issue_date: '', activities: [], confidence: 'low',
  document_kind: 'company_profile', document_kind_confidence: 'high', document_kind_why: 'a company profile: services and projects, no licence number, authority or expiry' };
type Mode = { kind: 'answer'; raw: Record<string, unknown> } | { kind: 'error' } | { kind: 'late'; raw: Record<string, unknown> };
let mode: Mode = { kind: 'error' }; let releaseLate!: () => void;
let row: Record<string, unknown> = {};
const reset = () => { row = { id: 990008, company_name: 'ZZ DEMO MEP CONTRACTING LLC', services: null, products: null, service_emirates: [], approval_status: null, license_doc_path: null,
  claimed_by: 'zz-demo-wrong-doc@example.invalid' }; };
const SECRETS: Record<string, string> = { cred_fn_supplier_api: 'zz-demo-cred', document_expiry_ai: 'on' };
const stored = new Set<string>(); const rpcs: { fn: string; body: Record<string, unknown> }[] = []; const actions: Record<string, unknown>[] = [];
globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init); const u = new URL(req.url);
  const body = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text();
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
  if (u.hostname !== 'stub.invalid') return json({ error: 'not found' }, 404);
  if (u.pathname === '/functions/v1/license_extract') {
    if (mode.kind === 'answer') return json(answer(mode.raw));
    if (mode.kind === 'error') return json({ error: 'ai_error', detail: 'every model route for this task class is open-circuit' }, 502);
    const raw = mode.raw; await new Promise<void>((ok) => { releaseLate = ok; }); return json(answer(raw));
  }
  if (u.pathname.startsWith('/functions/v1/')) return json({ ok: true });
  if (u.pathname.startsWith('/storage/v1/object/list/')) { const b = JSON.parse(body || '{}'); return json(stored.has(`${b.prefix}/${b.search}`) ? [{ name: b.search }] : []); }
  if (u.pathname.startsWith('/storage/v1/object/supplier-docs/')) {
    const p = u.pathname.slice('/storage/v1/object/supplier-docs/'.length);
    if (req.method === 'POST' || req.method === 'PUT') { stored.add(decodeURIComponent(p)); return json({ Key: `supplier-docs/${p}`, Id: 'zz' }); }
    return new Response(Uint8Array.from(atob(PROFILE_PDF), (c) => c.charCodeAt(0)), { status: 200, headers: { 'Content-Type': 'application/pdf' } });
  }
  if (u.pathname.startsWith('/rest/v1/rpc/')) { rpcs.push({ fn: u.pathname.slice('/rest/v1/rpc/'.length), body: JSON.parse(body || '{}') }); return json(null); }
  const one = (req.headers.get('Accept') || '').includes('vnd.pgrst.object');
  if (u.pathname === '/rest/v1/agent_actions' && req.method === 'POST') { const b = JSON.parse(body); actions.push(...(Array.isArray(b) ? b : [b]).map((a) => ({ ...a, created_at: new Date().toISOString() }))); return new Response(null, { status: 201 }); }
  if (u.pathname === '/rest/v1/agent_actions' && req.method === 'GET') {
    const kind = (u.searchParams.get('kind') || '').replace(/^eq\./, ''), target = (u.searchParams.get('target_id') || '').replace(/^eq\./, '');
    return json(actions.filter((a) => a.kind === kind && a.target_id === target).reverse().map((a) => ({ detail: a.detail })));
  }
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
const { supplierOf } = await import('./lib/me_row.ts');
const upload = async (m: Mode, settle = true) => {
  mode = m; rpcs.length = 0;
  const r = await documentActions({ email: 'zz-demo-wrong-doc@example.invalid', action: 'process_docs',
    body: { action: 'process_docs', license: { original_b64: PROFILE_PDF, file_b64: PROFILE_PDF, images: [], filename: 'ZZ_DEMO_company_profile.pdf', mime: 'application/pdf' } } } as never) as Response;
  const j = (await r.json()).extracted;
  if (settle) await Promise.all(later.splice(0));
  return j;
};
const MSG = 'This looks like a company profile, not a trade licence. Please attach your trade licence here. Your company profile goes in the Company profile box below.';
const tells = () => rpcs.filter((r) => r.fn === 'fn_sales_engineer_writes');
const { admin } = await import('./context.ts');
const me = () => supplierOf(admin, 'zz-demo-wrong-doc@example.invalid', async () => null);

Deno.test({ name: 'a company profile the model is sure about is named at once; nothing of it is a licence reading; he is not e-mailed', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(); actions.length = 0;
  const j = await upload({ kind: 'answer', raw: SURE_PROFILE });
  assertEquals(j.licence_wrong_document, { kind: 'company_profile', message: MSG });
  assertEquals([row.licence_read_state, row.trade_license_no, row.license_expiry, row.license_authority, row.licence_legal_name], ['file_unreadable', null, null, null, null]);
  assertEquals(j.license_read_state, 'file_unreadable');
  const kept = actions.filter((a) => a.kind === 'licence_wrong_document');
  assertEquals(kept.length, 1);
  assertEquals((kept[0].detail as Record<string, unknown>).path, row.license_doc_path);
  assertEquals(tells().length, 0, 'the form said it; no e-mail');
  // `me` carries it, for the late-read poll and the form's opening
  assertEquals((await me())?.licence_wrong_document, { kind: 'company_profile', message: MSG });
} });

Deno.test({ name: 'answered after the budget: the answer says being read, the row then holds the finding, and he is told by e-mail once', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(); actions.length = 0;
  const j = await upload({ kind: 'late', raw: SURE_PROFILE }, false);
  assertEquals([j.license_read_state, j.licence_read_after_answer, j.licence_wrong_document], ['ours_failed', true, undefined]);
  releaseLate(); await Promise.all(later.splice(0));
  for (let i = 0; i < 100 && row.licence_read_state !== 'file_unreadable'; i++) await new Promise((ok) => setTimeout(ok, 20));
  assertEquals(row.licence_read_state, 'file_unreadable');
  const t = tells();
  assertEquals(t.length, 1);
  assertEquals(t[0].body.p_msg_type, 'licence_wrong_document');
  assertEquals(t[0].body.p_subject_id, `licence_wrong_document:990008:${row.license_doc_path}`);
  assert(String(t[0].body.p_body_en).startsWith('The file you attached as your trade licence looks like a company profile, not a trade licence.'), String(t[0].body.p_body_en));
} });

Deno.test({ name: 'unsure, an older model with no kind, or a model error: the existing flow, unchanged', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(); actions.length = 0;
  const unsure = await upload({ kind: 'answer', raw: { ...SURE_PROFILE, document_kind_confidence: 'medium' } });
  assertEquals([unsure.licence_wrong_document, unsure.license_read_state, actions.length], [undefined, 'file_unreadable', 0], 'unsure: the existing "could not read this"');
  reset();
  const err = await upload({ kind: 'error' });
  assertEquals([err.licence_wrong_document, err.license_read_state, row.licence_read_state], [undefined, 'ours_failed', 'ours_failed']);
  assertEquals(tells().length, 0);
} });
