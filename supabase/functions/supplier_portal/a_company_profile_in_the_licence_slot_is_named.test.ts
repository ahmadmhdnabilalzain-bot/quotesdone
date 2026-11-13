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
let patches: Record<string, unknown>[] = []; let actions: Record<string, unknown>[] = []; const rpcs: string[] = [];
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
  if (u.pathname.startsWith('/rest/v1/rpc/')) { rpcs.push(u.pathname.slice('/rest/v1/rpc/'.length)); return json(null); }
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
const save = async (answer: Record<string, unknown>, approval: string | null = null) => {
  raw = answer; patches = []; actions = []; rpcs.length = 0;
  const SUP = { id: 990009, company_name: 'ZZ DEMO TAB TRADING LLC', claimed_by: 'zz-demo-tab2@example.invalid', approval_status: approval };
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
    // review of #1985 (D3): nothing of this upload reaches the row, so the licence before it (or none) stands
    for (const k of ['license_doc_path', 'license_doc_name', 'licence_read_state', 'trade_license_no', 'license_expiry', 'licence_legal_name', 'license_authority', 'license_issue_date'])
      assertEquals(k in w, false, `${kind}: ${k} was written`);
    assertEquals(actions.filter((a) => a.kind === 'licence_wrong_document').length, 1);
  }
  const lic = await save({ legal_name: 'ZZ DEMO TAB TRADING LLC', license_number: 'ZZ-777001', license_authority: 'Dubai Department of Economy and Tourism',
    issue_date: '2026-01-01', expiry_date: '2027-12-31', confidence: 'high', document_kind: 'trade_licence', document_kind_confidence: 'high', document_kind_why: 'a DET licence' });
  assertEquals([lic.j.read?.license?.wrong_document, lic.w.license_expiry, lic.w.licence_read_state], [undefined, '2027-12-31', 'read']);
} });

Deno.test({ name: 'save_documents: an approved supplier attaching his profile as his licence keeps his licence; his real licence then replaces it', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  const wrong = await save(SURE('company_profile'), 'approved');
  assertEquals(wrong.j.read?.license?.wrong_document, 'company_profile');
  for (const k of ['license_doc_path', 'licence_read_state', 'trade_license_no', 'license_expiry', 'licence_legal_name', 'license_authority']) assertEquals(k in wrong.w, false, k);
  const real = await save({ legal_name: 'ZZ DEMO TAB TRADING LLC', license_number: 'ZZ-777002', license_authority: 'Dubai Department of Economy and Tourism',
    issue_date: '2026-01-01', expiry_date: '2027-12-31', confidence: 'high', document_kind: 'trade_licence', document_kind_confidence: 'high', document_kind_why: 'a DET licence' }, 'approved');
  assertEquals([real.w.trade_license_no, real.w.license_expiry, real.w.licence_read_state, typeof real.w.license_doc_path], ['ZZ-777002', '2027-12-31', 'read', 'string']);
} });

Deno.test({ name: 'save_documents: a chamber certificate with licence-like fields is held on its file for a person, nothing stored as a licence', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  const CHAMBER = { legal_name: 'ZZ DEMO TAB TRADING LLC', license_number: 'ZZ-777001', license_authority: 'Dubai Chamber of Commerce and Industry', expiry_date: '2027-12-31',
    confidence: 'high', document_kind: 'certificate', document_kind_confidence: 'high', document_kind_why: 'a chamber of commerce membership certificate' };
  const { j, w } = await save(CHAMBER);
  assertEquals([j.read?.license?.held, j.read?.license?.wrong_document], [true, 'certificate']);
  assertEquals([w.licence_read_state, w.trade_license_no, w.license_authority, w.license_expiry, typeof w.license_doc_path], ['ours_failed', null, null, null, 'string']);
  assertEquals(patches.some((p) => p.licence_read_tries === 8), true, 'the re-read sweep is kept off it');
  assertEquals(actions.filter((a) => a.kind === 'licence_held_for_person' && a.status === 'needs_review').length, 1);
} });

// 13 Nov 2026, the first paid J11 on the live site (founder ruling 1668): a sure company profile that quotes its licence number and
// authority (no expiry, the measured shape) is named, not held (licence_extract.ts NEVER_A_LICENCE_KINDS); with an authority AND an
// expiry read it may hold a licence page and is held for a person (review of #1992); a certificate quoting either stays held (W1).
Deno.test({ name: 'save_documents: a sure company profile quoting its licence details is named and nothing of it is written', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  const QUOTING = { ...SURE('company_profile'), legal_name: 'ZZ DEMO TAB TRADING LLC', license_number: 'ZZ-555001', license_authority: 'Dubai Department of Economy and Tourism', expiry_date: '' };
  for (const approval of [null, 'approved']) {
    const { j, w } = await save(QUOTING, approval);
    assertEquals([j.read?.license?.wrong_document, j.read?.license?.held ?? false], ['company_profile', false], String(approval));
    for (const k of ['license_doc_path', 'licence_read_state', 'trade_license_no', 'license_expiry', 'licence_legal_name', 'license_authority']) assertEquals(k in w, false, `${approval}: ${k}`);
    assertEquals([actions.filter((a) => a.kind === 'licence_wrong_document').length, actions.filter((a) => a.kind === 'licence_held_for_person').length], [1, 0]);
  }
} });
Deno.test({ name: 'save_documents: a sure company profile with an authority AND an expiry read is held for a person, nothing stored as a licence', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  const PAGE = { ...SURE('company_profile'), legal_name: 'ZZ DEMO TAB TRADING LLC', license_number: 'ZZ-555001', license_authority: 'Dubai Department of Economy and Tourism', expiry_date: '2027-06-30' };
  const { j, w } = await save(PAGE);
  assertEquals([j.read?.license?.held, j.read?.license?.wrong_document], [true, 'company_profile']);
  assertEquals([w.licence_read_state, w.trade_license_no, w.license_authority, w.license_expiry, typeof w.license_doc_path], ['ours_failed', null, null, null, 'string']);
  assertEquals([actions.filter((a) => a.kind === 'licence_held_for_person' && a.status === 'needs_review').length, actions.filter((a) => a.kind === 'licence_wrong_document').length], [1, 0]);
  assertEquals(rpcs.filter((f) => f === 'fn_ceo_task_open').length, 1, 'a person is asked once');
} });
