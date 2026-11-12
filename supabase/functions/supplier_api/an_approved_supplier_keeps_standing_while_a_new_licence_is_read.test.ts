// AN APPROVED SUPPLIER KEEPS HIS STANDING WHILE A NEW LICENCE IS READ (12 Nov 2026, sales_engineer; second review of #1978, defect A).
//
// After #1978 a new licence file cleared the old readings at once with the state 'ours_failed'. For an APPROVED supplier the
// re-verification trigger (z20, source 'licence_changed') then found his name, number, expiry and authority blank and made him
// pending / licence_being_read, out of matching, until the model read the new file: with the provider down, 10 minutes to about
// 42 hours. And the nightly fn_reconcile_doc_blocks lifts a 'licence_expired' block when the expiry is NULL, so a supplier blocked
// for an expired licence who attached any file while the provider was down would have been unblocked and mailed "active again".
// fn_sales_engineer_verifies_supplier keeps an approved supplier approved while his name, number, expiry and authority are all on
// the row (its first branch), and the restore needs a null or later expiry: so what decides his standing is what this write leaves.
// Drives supplier_api's OWN process_docs over a stubbed fetch with an in-memory leads row. Every value is SYNTHETIC (ZZ DEMO).
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
const LICENCE_PDF = pdf(['Trade Licence', 'Licence No: ZZ-5500123', 'Legal Name: ZZ DEMO STANDING TRADING LLC', 'Expiry Date: 01/06/2028']);
const READ = (expiry: string, issue: string, extra: Record<string, unknown> = {}) => ({ ok: true, doc: { legal_name: 'ZZ DEMO STANDING TRADING LLC', license_number: 'ZZ-5500123',
  license_authority: 'Dubai Department of Economy and Tourism', emirate: 'Dubai', issue_date: issue, expiry_date: expiry, activities: [], confidence: 'high', ...extra } });
type Model = { kind: 'answer'; body: unknown } | { kind: 'error' } | { kind: 'unreadable' } | { kind: 'late'; body: unknown };
let model: Model = { kind: 'error' }; let releaseLate!: () => void;
// what the row held before: the reading we accepted for his previous licence
const ACCEPTED = { trade_license_no: 'ZZ-OLD-0001', licence_legal_name: 'ZZ DEMO STANDING TRADING LLC', license_authority: 'Dubai Department of Economy and Tourism',
  license_expiry: '2027-01-31', license_issue_date: '2026-02-01', licence_read_state: 'read' };
let row: Record<string, unknown> = {};
const reset = (approval: string | null, over: Record<string, unknown> = {}) => {
  row = { id: 990006, company_name: 'ZZ DEMO STANDING TRADING LLC', services: null, products: null, service_emirates: [], approval_status: approval,
    license_doc_path: 'licenses/990006/1700000000000_old.pdf', ...ACCEPTED, ...over };
};
const SECRETS: Record<string, string> = { cred_fn_supplier_api: 'zz-demo-cred', document_expiry_ai: 'on' };
const stored = new Set<string>(); const rpcs: { fn: string; body: Record<string, unknown> }[] = []; const actions: Record<string, unknown>[] = [];
globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init); const u = new URL(req.url);
  const body = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text();
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
  if (u.hostname !== 'stub.invalid') return json({ error: 'not found' }, 404);
  if (u.pathname === '/functions/v1/license_extract') {
    if (model.kind === 'answer') return json(model.body);
    if (model.kind === 'unreadable') return json({ ok: true, doc: { legal_name: '', license_number: '', expiry_date: null, issue_date: null, confidence: 'low', unreadable: true } });
    if (model.kind === 'error') return json({ error: 'ai_error', detail: 'every model route for this task class is open-circuit' }, 502);
    const b = model.body; await new Promise<void>((ok) => { releaseLate = ok; }); return json(b);
  }
  if (u.pathname.startsWith('/functions/v1/')) return json({ ok: true });
  if (u.pathname.startsWith('/storage/v1/object/list/')) { const b = JSON.parse(body || '{}'); return json(stored.has(`${b.prefix}/${b.search}`) ? [{ name: b.search }] : []); }
  if (u.pathname.startsWith('/storage/v1/object/supplier-docs/')) {
    const p = u.pathname.slice('/storage/v1/object/supplier-docs/'.length);
    if (req.method === 'POST' || req.method === 'PUT') { stored.add(decodeURIComponent(p)); return json({ Key: `supplier-docs/${p}`, Id: 'zz' }); }
    return new Response(Uint8Array.from(atob(LICENCE_PDF), (c) => c.charCodeAt(0)), { status: 200, headers: { 'Content-Type': 'application/pdf' } });
  }
  if (u.pathname.startsWith('/rest/v1/rpc/')) { rpcs.push({ fn: u.pathname.slice('/rest/v1/rpc/'.length), body: JSON.parse(body || '{}') }); return json(null); }
  if (u.pathname === '/rest/v1/agent_actions' && req.method === 'POST') { const b = JSON.parse(body); actions.push(...(Array.isArray(b) ? b : [b])); return new Response(null, { status: 201 }); }
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
const upload = async (m: Model, settle = true) => {
  model = m;
  const r = await documentActions({ email: 'zz-demo-supplier@example.invalid', action: 'process_docs',
    body: { action: 'process_docs', license: { original_b64: LICENCE_PDF, file_b64: LICENCE_PDF, images: [], filename: 'ZZ_DEMO_new_licence.pdf', mime: 'application/pdf' } } } as never) as Response;
  const j = (await r.json()).extracted;
  if (settle) await Promise.all(later.splice(0));
  return j;
};
const fields = () => [row.trade_license_no, row.license_authority, row.license_expiry, row.licence_legal_name, row.license_issue_date, row.licence_read_state];
// What fn_sales_engineer_verifies_supplier's first branch needs to keep an approved supplier approved (read from its live
// definition, 12 Nov 2026): a name, number, expiry and authority on the row. Its other conditions (a mismatch, a foreign authority)
// are not this change's subject. And fn_reconcile_doc_blocks restores a licence_expired block only on a null or later expiry.
const keepsApproval = () => [row.licence_legal_name, row.trade_license_no, row.license_expiry, row.license_authority].every((v) => v != null && String(v).trim() !== '');
const restoredOvernight = (today: string) => row.matching_block_reason === 'licence_expired' && (row.license_expiry == null || String(row.license_expiry) > today);
const shownExpiry = (j: Record<string, unknown>) => (j.license as Record<string, unknown> | undefined)?.expiry ?? null;

Deno.test({ name: 'an approved supplier: the provider down, or late, keeps the accepted reading and his standing; the panel shows the new licence being read', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset('approved');
  const j = await upload({ kind: 'error' });
  assert(String(row.license_doc_path).includes('ZZ_DEMO_new_licence'), 'the new file is on the row');
  assertEquals(fields(), ['ZZ-OLD-0001', 'Dubai Department of Economy and Tourism', '2027-01-31', 'ZZ DEMO STANDING TRADING LLC', '2026-02-01', 'ours_failed']);
  assert(keepsApproval(), 'the gate keeps him approved');
  assertEquals([j.license_read_state, shownExpiry(j)], ['ours_failed', null], 'he is told the new licence is being read, never the old date as its reading');
  // late: the same until the model's reading lands, then the new reading replaces the old one whole
  reset('approved');
  const late = await upload({ kind: 'late', body: READ('2028-06-01', '2025-06-02', { license_authority: '' }) }, false);
  assertEquals([late.license_read_state, late.licence_read_after_answer, shownExpiry(late), row.license_expiry, row.trade_license_no], ['ours_failed', true, null, '2027-01-31', 'ZZ-OLD-0001']);
  releaseLate(); await Promise.all(later.splice(0));
  for (let i = 0; i < 100 && row.licence_read_state !== 'read'; i++) await new Promise((ok) => setTimeout(ok, 20));
  assertEquals(fields(), ['ZZ-5500123', null, '2028-06-01', 'ZZ DEMO STANDING TRADING LLC', '2025-06-02', 'read'], 'an authority the model did not read is unread, never the old one');
} });

Deno.test({ name: "an approved supplier: the model's reading of the new file replaces the accepted one (same, renewed, really expired, unreadable)", sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset('approved');
  await upload({ kind: 'answer', body: READ('2027-01-31', '2026-02-01') });   // the same licence again
  assertEquals(fields(), ['ZZ-5500123', 'Dubai Department of Economy and Tourism', '2027-01-31', 'ZZ DEMO STANDING TRADING LLC', '2026-02-01', 'read']);
  reset('approved');
  const renewed = await upload({ kind: 'answer', body: READ('2028-01-30', '2027-01-31') });
  assertEquals([row.license_expiry, row.license_issue_date, shownExpiry(renewed)], ['2028-01-30', '2027-01-31', '2028-01-30']);
  reset('approved');
  const expired = await upload({ kind: 'answer', body: READ('2025-03-14', '2022-03-15') });   // a really expired licence: the date the nightly block acts on
  assertEquals([row.license_expiry, shownExpiry(expired)], ['2025-03-14', '2025-03-14']);
  reset('approved');
  await upload({ kind: 'unreadable' });   // "this file cannot be read" is its reading: the old one does not outlive it
  assertEquals(fields(), [null, null, null, null, null, 'file_unreadable']);
  assert(!keepsApproval());
} });

Deno.test({ name: 'a supplier blocked for an expired licence is not unblocked by a file nobody has read', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset('approved', { license_expiry: '2026-09-30', matching_blocked: true, matching_block_reason: 'licence_expired' });
  await upload({ kind: 'error' });
  assertEquals([row.license_expiry, row.licence_read_state], ['2026-09-30', 'ours_failed']);
  assertEquals(restoredOvernight('2026-11-12'), false, 'the nightly restore must not lift the block');
  // once the model reads a renewed licence, the restore lifts it on that date
  await upload({ kind: 'answer', body: READ('2027-09-30', '2026-10-01') });
  assertEquals(restoredOvernight('2026-11-12'), true);
} });

Deno.test({ name: 'a supplier who is not approved is cleared at once, as before', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  for (const approval of [null, 'pending', 'action_required']) {
    reset(approval);
    await upload({ kind: 'error' });
    assertEquals(fields(), [null, null, null, null, null, 'ours_failed'], String(approval));
  }
} });

// Review of #1982 (12 Nov 2026): L3-2, staff are told the fields on file are the previously accepted reading while the new file is
// read; L3-3, once the new reading lands he is re-verified whatever it changed (z20 runs on a path or name change only).
Deno.test({ name: 'the kept reading is marked for staff, and the landed reading is re-verified even when the name is the same', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset('approved'); rpcs.length = 0; actions.length = 0;
  await upload({ kind: 'error' });
  const marks = actions.filter((a) => a.kind === 'licence_new_file_being_read');
  assertEquals(marks.length, 1, 'one marker for the new file');
  assert(/previously accepted reading/.test(String(marks[0].recommendation)));
  assertEquals(rpcs.filter((r) => r.fn === 'fn_sales_engineer_verifies_supplier').length, 0, 'nothing landed, nothing re-verified by us');
  // a renewal that prints the same name, read with no authority
  reset('approved'); rpcs.length = 0; actions.length = 0;
  await upload({ kind: 'answer', body: READ('2028-01-30', '2027-01-31', { license_authority: '' }) });
  assertEquals(row.license_authority, null);
  const v = rpcs.filter((r) => r.fn === 'fn_sales_engineer_verifies_supplier');
  assertEquals(v.map((r) => r.body), [{ p_lead_id: 990006, p_source: 'licence_changed' }]);
  // not approved: no marker, and the gate is left to z20 as before
  reset('pending'); rpcs.length = 0; actions.length = 0;
  await upload({ kind: 'answer', body: READ('2028-01-30', '2027-01-31') });
  assertEquals([actions.filter((a) => a.kind === 'licence_new_file_being_read').length, rpcs.filter((r) => r.fn === 'fn_sales_engineer_verifies_supplier').length], [0, 0]);
} });
