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
let shaOnAnswer: string | null = null;   // license_extract's SHA-256 of the file, put on a refused file's finding (ruling 1681)
const answer = (raw: Record<string, unknown>) => { const doc = normaliseLicence(raw);
  return { ok: true, doc: shaOnAnswer && doc.wrong_document ? { ...doc, wrong_document: { ...doc.wrong_document, file_sha: shaOnAnswer } } : doc }; };
const SURE_PROFILE = { legal_name: '', license_number: '', license_authority: '', expiry_date: '', issue_date: '', activities: [], confidence: 'low',
  document_kind: 'company_profile', document_kind_confidence: 'high', document_kind_why: 'a company profile: services and projects, no licence number, authority or expiry' };
type Mode = { kind: 'answer'; raw: Record<string, unknown> } | { kind: 'error' } | { kind: 'late'; raw: Record<string, unknown> };
let mode: Mode = { kind: 'error' }; let releaseLate!: () => void;
let row: Record<string, unknown> = {};
const ACCEPTED = { license_doc_path: 'licenses/990008/1700000000000_licence.pdf', trade_license_no: 'ZZ-OLD-0001', licence_legal_name: 'ZZ DEMO MEP CONTRACTING LLC',
  license_authority: 'Dubai Department of Economy and Tourism', license_expiry: '2027-06-30', license_issue_date: '2026-07-01', licence_read_state: 'read' };
const reset = (approved = false) => { row = { id: 990008, company_name: 'ZZ DEMO MEP CONTRACTING LLC', services: null, products: null, service_emirates: [],
  approval_status: approved ? 'approved' : null, license_doc_path: null, claimed_by: 'zz-demo-wrong-doc@example.invalid', ...(approved ? ACCEPTED : {}) }; };
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
    const k = u.searchParams.get('kind') || '', target = (u.searchParams.get('target_id') || '').replace(/^eq\./, '');
    const kinds = k.startsWith('in.(') ? k.slice(4, -1).split(',') : [k.replace(/^eq\./, '')];
    const pathEq = u.searchParams.get('detail->>path'), shaEq = u.searchParams.get('detail->>file_sha');
    return json(actions.filter((a) => kinds.includes(String(a.kind)) && a.target_id === target && (!pathEq || (a.detail as Record<string, unknown>).path === pathEq.replace(/^eq\./, ''))
      && (!shaEq || (a.detail as Record<string, unknown>).file_sha === shaEq.replace(/^eq\./, '')))
      .reverse().map((a) => ({ kind: a.kind, detail: a.detail, id: 1 })));
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
const MSG = 'This looks like a company profile, not a trade licence. Please attach your trade licence here. Your company profile goes in the Company profile box below. If this is your trade licence, reply to our e-mail or write to management@quotesdone.com and we will check it.';
const tells = () => rpcs.filter((r) => r.fn === 'fn_sales_engineer_writes');
const { admin } = await import('./context.ts');
const me = () => supplierOf(admin, 'zz-demo-wrong-doc@example.invalid', async () => null);

Deno.test({ name: 'a company profile the model is sure about is named at once; nothing of it is a licence reading; he is not e-mailed', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(); actions.length = 0;
  const j = await upload({ kind: 'answer', raw: SURE_PROFILE });
  assertEquals(j.licence_wrong_document, { kind: 'company_profile', message: MSG, held: false, blocks_submit: true });
  // review of #1985 (D3): the file never becomes his licence file: a new supplier has no licence again, nothing is read off it
  assertEquals([row.license_doc_path, row.licence_read_state, row.trade_license_no, row.license_expiry, row.license_authority, row.licence_legal_name], [null, null, null, null, null, null]);
  const kept = actions.filter((a) => a.kind === 'licence_wrong_document');
  assertEquals(kept.length, 1);
  const detail = kept[0].detail as Record<string, unknown>;
  assert(/ZZ_DEMO_company_profile/.test(String(detail.path)), 'the wrong file is kept on its agent_actions row');
  assertEquals(detail.restored_to, null);
  assertEquals(tells().length, 0, 'the form said it; no e-mail');
  // `me` carries it, for the late-read poll and the form's opening
  assertEquals((await me())?.licence_wrong_document, { kind: 'company_profile', message: MSG, path: detail.path, held: false, blocks_submit: true });
} });

Deno.test({ name: 'answered after the budget: the answer says being read, the row then holds the finding, and he is told by e-mail once', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(); actions.length = 0;
  const j = await upload({ kind: 'late', raw: SURE_PROFILE }, false);
  assertEquals([j.license_read_state, j.licence_read_after_answer, j.licence_wrong_document], ['ours_failed', true, undefined]);
  releaseLate(); await Promise.all(later.splice(0));
  for (let i = 0; i < 100 && row.license_doc_path !== null; i++) await new Promise((ok) => setTimeout(ok, 20));
  assertEquals([row.license_doc_path, row.licence_read_state], [null, null]);
  const t = tells();
  assertEquals(t.length, 1);
  assertEquals(t[0].body.p_msg_type, 'licence_wrong_document');
  const wrongPath = (actions.find((a) => a.kind === 'licence_wrong_document')!.detail as Record<string, unknown>).path;
  assertEquals(t[0].body.p_subject_id, `licence_wrong_document:990008:${wrongPath}`);   // once per wrong file
  assert(String(t[0].body.p_body_en).startsWith('The file you attached as your trade licence looks like a company profile, not a trade licence.'), String(t[0].body.p_body_en));
} });

Deno.test({ name: 'unsure, an older model with no kind, or a model error: the existing flow, unchanged', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(); actions.length = 0;
  // second review of #1985 (W1): a non-licence kind at 'medium' is the model's doubt: held for a person, never named wrong, never stored
  const unsure = await upload({ kind: 'answer', raw: { ...SURE_PROFILE, document_kind_confidence: 'medium' } });
  assertEquals([unsure.licence_wrong_document?.held, unsure.license_read_state, actions.filter((a) => a.kind === 'licence_held_for_person').length], [true, 'ours_failed', 1]);
  reset(); actions.length = 0;
  const older = await upload({ kind: 'answer', raw: { legal_name: '', license_number: '', license_authority: '', expiry_date: '', confidence: 'low' } });
  assertEquals([older.licence_wrong_document, older.license_read_state, actions.length], [undefined, 'file_unreadable', 0], 'an older model with no kind: the existing "could not read this"');
  reset();
  const err = await upload({ kind: 'error' });
  assertEquals([err.licence_wrong_document, err.license_read_state, row.licence_read_state], [undefined, 'ours_failed', 'ours_failed']);
  assertEquals(tells().length, 0);
} });

Deno.test({ name: 'an approved supplier who attaches his profile as his licence keeps his licence and his standing; then his real licence is read', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(true); actions.length = 0;
  const j = await upload({ kind: 'answer', raw: SURE_PROFILE });
  assertEquals(j.licence_wrong_document?.kind, 'company_profile');
  // put back as it was: the previous licence file and the accepted reading (the gate keeps him approved on it)
  assertEquals([row.license_doc_path, row.trade_license_no, row.license_expiry, row.license_authority, row.licence_legal_name, row.licence_read_state, row.license_issue_date],
    [ACCEPTED.license_doc_path, 'ZZ-OLD-0001', '2027-06-30', 'Dubai Department of Economy and Tourism', 'ZZ DEMO MEP CONTRACTING LLC', 'read', '2026-07-01']);
  assertEquals((actions.find((a) => a.kind === 'licence_wrong_document')!.detail as Record<string, unknown>).restored_to, ACCEPTED.license_doc_path);
  // then the real licence: the model's reading replaces the accepted one, as for any new licence
  await upload({ kind: 'answer', raw: { legal_name: 'ZZ DEMO MEP CONTRACTING LLC', license_number: 'ZZ-NEW-0002', license_authority: 'Dubai Department of Economy and Tourism',
    issue_date: '2027-06-30', expiry_date: '2028-06-29', confidence: 'high', document_kind: 'trade_licence', document_kind_confidence: 'high', document_kind_why: 'a DET licence' } });
  assertEquals([row.trade_license_no, row.license_expiry, row.licence_read_state], ['ZZ-NEW-0002', '2028-06-29', 'read']);
  assert(String(row.license_doc_path).includes('ZZ_DEMO_company_profile') && row.license_doc_path !== ACCEPTED.license_doc_path, 'the new licence file is on the row');
  assertEquals((await me())?.licence_wrong_document, null, 'the old finding is not shown once another licence is on file');
} });

// Second review of #1985, W1: a Dubai Chamber certificate whose fields the model read but which it calls a certificate. Since ruling 1681
// a SURE one is named (below); the held path is the reader UNSURE ('medium') and the second reader unsure too (license_extract answers it
// held only then), so the held cases here use 'medium'.
const CHAMBER = { legal_name: 'ZZ DEMO MEP CONTRACTING LLC', license_number: 'ZZ-777001', license_authority: 'Dubai Chamber of Commerce and Industry', expiry_date: '2027-12-31',
  issue_date: '2026-01-01', confidence: 'high', document_kind: 'certificate', document_kind_confidence: 'medium', document_kind_why: 'a chamber of commerce membership certificate' };
const SURE_CHAMBER = { ...CHAMBER, document_kind_confidence: 'high' };
const HELD = 'We could not confirm that this is a trade licence. If it is another document (such as a chamber of commerce or VAT certificate), please attach your trade licence here. If it is your trade licence, you do not need to do anything: one of our team will check it and confirm.';
Deno.test({ name: 'a chamber certificate is never stored as a licence: held on its file for a person now, the sweep kept off it, he is told the truth', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(); actions.length = 0;
  const j = await upload({ kind: 'answer', raw: CHAMBER });
  assertEquals(j.licence_wrong_document, { kind: 'certificate', message: HELD, held: true, blocks_submit: false });
  assert(String(row.license_doc_path).includes('ZZ_DEMO_company_profile'), 'the file stays on the row, held');
  assertEquals([row.trade_license_no, row.license_authority, row.license_expiry, row.licence_legal_name, row.licence_read_state, row.licence_read_tries], [null, null, null, null, 'ours_failed', 8]);
  const review = actions.filter((a) => a.kind === 'licence_held_for_person');
  assertEquals([review.length, review[0]?.status], [1, 'needs_review']);
  assertEquals(((review[0].detail as Record<string, unknown>).read as Record<string, unknown>).license_authority, 'Dubai Chamber of Commerce and Industry');
  assertEquals(rpcs.filter((r) => r.fn === 'fn_ceo_task_open').length, 1, 'a person is asked now');
  assertEquals(actions.filter((a) => a.kind === 'held_registration_for_ceo' && (a.detail as Record<string, unknown>).clock === `licence_being_read:${row.license_doc_path}`).length, 1);
  assertEquals(((await me())?.licence_wrong_document as { message?: string } | null)?.message, HELD);
  // the same file answered again (a retry): no second task
  rpcs.length = 0;
} });
Deno.test({ name: 'an approved supplier who attaches a chamber certificate keeps his licence; a person is asked about the new file', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(true); actions.length = 0;
  const j = await upload({ kind: 'answer', raw: { ...CHAMBER, document_kind_confidence: 'medium' } });
  assertEquals(j.licence_wrong_document?.held, true);
  assertEquals([row.license_doc_path, row.trade_license_no, row.license_expiry, row.licence_read_state], [ACCEPTED.license_doc_path, 'ZZ-OLD-0001', '2027-06-30', 'read']);
  assertEquals(actions.filter((a) => a.kind === 'licence_held_for_person').length, 1);
} });

// THE RE-READ SWEEP (third review of #1985, F1): the first read failed, so the row already names the file in 'ours_failed', and
// docs_reread sends that same path back to process_docs. There is nothing earlier to put back, and the sweep must stop on it.
const sweep = async (m: Mode) => {
  mode = m; rpcs.length = 0;
  const r = await documentActions({ email: 'zz-demo-wrong-doc@example.invalid', action: 'process_docs', body: { action: 'process_docs', license: { path: String(row.license_doc_path) } } } as never) as Response;
  const j = (await r.json()).extracted; await Promise.all(later.splice(0)); return j;
};
const FILE = 'licenses/990008/1794500000000_ZZ_DEMO_file.pdf';
stored.add(FILE);   // the file the row names is in storage (the sweep reads it back)
Deno.test({ name: 'sweep: a new supplier whose stuck file is a sure profile has no licence again, Submit stops, the sweep stops', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(); actions.length = 0; Object.assign(row, { license_doc_path: FILE, licence_read_state: 'ours_failed', licence_read_tries: 1 });
  const j = await sweep({ kind: 'answer', raw: SURE_PROFILE });
  assertEquals([row.license_doc_path, row.licence_read_state, row.licence_read_tries], [null, null, 8]);
  assertEquals(j.licence_wrong_document?.blocks_submit, true);
  assertEquals((actions.find((a) => a.kind === 'licence_wrong_document')!.detail as Record<string, unknown>).restored_to, null);
} });
Deno.test({ name: 'sweep: an approved supplier whose stuck file is a sure profile keeps his accepted reading and approval; the sweep stops', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(true); actions.length = 0; Object.assign(row, { license_doc_path: FILE, licence_read_state: 'ours_failed', licence_read_tries: 1 });
  await sweep({ kind: 'answer', raw: SURE_PROFILE });
  assertEquals([row.license_doc_path, row.trade_license_no, row.license_expiry, row.license_authority, row.licence_legal_name, row.license_issue_date, row.approval_status],
    [FILE, 'ZZ-OLD-0001', '2027-06-30', 'Dubai Department of Economy and Tourism', 'ZZ DEMO MEP CONTRACTING LLC', '2026-07-01', 'approved']);
  assertEquals([row.licence_read_state, row.licence_read_tries], ['ours_failed', 8]);
} });
Deno.test({ name: 'sweep: an approved supplier\'s held (iii) file keeps his reading, opens one review and one task per file, and is not re-asked', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(true); actions.length = 0; Object.assign(row, { license_doc_path: FILE, licence_read_state: 'ours_failed', licence_read_tries: 1 });
  await sweep({ kind: 'answer', raw: CHAMBER });
  assertEquals([row.license_doc_path, row.trade_license_no, row.licence_read_state, row.licence_read_tries, row.approval_status], [FILE, 'ZZ-OLD-0001', 'ours_failed', 8, 'approved']);
  const tasks = rpcs.filter((r) => r.fn === 'fn_ceo_task_open').length;
  await sweep({ kind: 'answer', raw: CHAMBER });   // were it asked again: still one review row and one task for this file
  assertEquals([actions.filter((a) => a.kind === 'licence_held_for_person').length, tasks + rpcs.filter((r) => r.fn === 'fn_ceo_task_open').length], [1, 1]);
} });
Deno.test({ name: 'sweep: a new supplier\'s held (iii) file stays held, the sweep is capped, one review and one task per file', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(); actions.length = 0; Object.assign(row, { license_doc_path: FILE, licence_read_state: 'ours_failed', licence_read_tries: 1 });
  await sweep({ kind: 'answer', raw: CHAMBER });
  assertEquals([row.license_doc_path, row.trade_license_no, row.licence_read_state, row.licence_read_tries], [FILE, null, 'ours_failed', 8]);
  await sweep({ kind: 'answer', raw: CHAMBER });
  assertEquals(actions.filter((a) => a.kind === 'licence_held_for_person').length, 1);
} });

// 13 Nov 2026, the first paid J11 on the live site (founder ruling 1668): the ZZ DEMO MEP company profile came back company_profile,
// 'high', with the licence number, authority and name it quotes read and no expiry. A kind that is never a licence is named unless both
// an authority and an expiry are read (licence_extract.ts NEVER_A_LICENCE_KINDS; review of #1992); before, the authority read held it.
const QUOTING_PROFILE = { ...SURE_PROFILE, legal_name: 'ZZ DEMO MEP CONTRACTING LLC', license_number: 'ZZ-555001', license_authority: 'Dubai Department of Economy and Tourism',
  expiry_date: '', document_kind_why: 'a company profile describing MEP services and projects; it mentions a licence number but contains no licence page or expiry date' };
// both read: the model may have seen a licence page (a profile pack with the licence inside): held for a person, never refused
const PAGE_READ_PROFILE = { ...QUOTING_PROFILE, expiry_date: '2027-06-30', document_kind_why: 'a company profile pack' };
Deno.test({ name: 'a sure company profile that quotes its licence number and authority is named; nothing of it is stored; Submit stops', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(); actions.length = 0;
  const j = await upload({ kind: 'answer', raw: QUOTING_PROFILE });
  assertEquals(j.licence_wrong_document, { kind: 'company_profile', message: MSG, held: false, blocks_submit: true });
  assertEquals([row.license_doc_path, row.licence_read_state, row.trade_license_no, row.license_expiry, row.license_authority, row.licence_legal_name], [null, null, null, null, null, null]);
  assertEquals([actions.filter((a) => a.kind === 'licence_wrong_document').length, actions.filter((a) => a.kind === 'licence_held_for_person').length], [1, 0]);
  assertEquals(rpcs.filter((r) => r.fn === 'fn_ceo_task_open').length, 0, 'no person is asked: the model is sure');
  // an approved supplier keeps his accepted reading and his file
  reset(true); actions.length = 0;
  const a = await upload({ kind: 'answer', raw: QUOTING_PROFILE });
  assertEquals([a.licence_wrong_document?.kind, a.licence_wrong_document?.blocks_submit], ['company_profile', false]);
  assertEquals([row.license_doc_path, row.trade_license_no, row.license_expiry, row.license_authority, row.licence_read_state],
    [ACCEPTED.license_doc_path, 'ZZ-OLD-0001', '2027-06-30', 'Dubai Department of Economy and Tourism', 'read']);
  // the same profile at 'medium' is the model's doubt: held for a person, never named, never stored
  reset(); actions.length = 0;
  const m = await upload({ kind: 'answer', raw: { ...QUOTING_PROFILE, document_kind_confidence: 'medium' } });
  assertEquals([m.licence_wrong_document?.held, row.trade_license_no], [true, null]);
} });
Deno.test({ name: 'sweep: a stuck file that is a sure profile quoting its licence is named on the sweep door too, for a new and an approved supplier', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(); actions.length = 0; Object.assign(row, { license_doc_path: FILE, licence_read_state: 'ours_failed', licence_read_tries: 1 });
  const j = await sweep({ kind: 'answer', raw: QUOTING_PROFILE });
  assertEquals([row.license_doc_path, row.licence_read_state, row.licence_read_tries, row.trade_license_no, j.licence_wrong_document?.blocks_submit], [null, null, 8, null, true]);
  reset(true); actions.length = 0; Object.assign(row, { license_doc_path: FILE, licence_read_state: 'ours_failed', licence_read_tries: 1 });
  await sweep({ kind: 'answer', raw: QUOTING_PROFILE });
  assertEquals([row.trade_license_no, row.license_expiry, row.approval_status, row.licence_read_tries], ['ZZ-OLD-0001', '2027-06-30', 'approved', 8]);
  assertEquals(actions.filter((a) => a.kind === 'licence_held_for_person').length, 0);
} });
Deno.test({ name: 'a sure company profile with an authority AND an expiry read is held for a person on both doors: nothing stored, Submit not blocked, one review, one task', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(); actions.length = 0;
  const j = await upload({ kind: 'answer', raw: PAGE_READ_PROFILE });
  assertEquals([j.licence_wrong_document?.kind, j.licence_wrong_document?.held, j.licence_wrong_document?.blocks_submit], ['company_profile', true, false]);
  assertEquals([row.trade_license_no, row.license_authority, row.license_expiry, row.licence_legal_name, row.licence_read_state], [null, null, null, null, 'ours_failed']);
  assertEquals([actions.filter((a) => a.kind === 'licence_held_for_person').length, actions.filter((a) => a.kind === 'licence_wrong_document').length,
    rpcs.filter((r) => r.fn === 'fn_ceo_task_open').length], [1, 0, 1]);
  // the sweep door
  reset(); actions.length = 0; Object.assign(row, { license_doc_path: FILE, licence_read_state: 'ours_failed', licence_read_tries: 1 });
  const w = await sweep({ kind: 'answer', raw: PAGE_READ_PROFILE });
  assertEquals([w.licence_wrong_document?.held, w.licence_wrong_document?.blocks_submit ?? false], [true, false]);
  assertEquals([row.license_doc_path, row.trade_license_no, row.license_expiry, row.licence_read_state, row.licence_read_tries], [FILE, null, null, 'ours_failed', 8]);
  assertEquals([actions.filter((a) => a.kind === 'licence_held_for_person').length, rpcs.filter((r) => r.fn === 'fn_ceo_task_open').length], [1, 1]);
} });

// Ruling 1681 (13 Nov 2026): the reader decides. A chamber certificate it is SURE of is named on both doors, never stored, and a person is
// not asked; the SAME file refused twice for one supplier opens one ceo task (once per supplier, not per upload).
Deno.test({ name: 'a chamber certificate the reader is sure of is named on the upload and sweep doors; nothing stored; no person asked', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(); actions.length = 0;
  const j = await upload({ kind: 'answer', raw: SURE_CHAMBER });
  assertEquals([j.licence_wrong_document?.kind, j.licence_wrong_document?.held, j.licence_wrong_document?.blocks_submit], ['certificate', false, true]);
  assertEquals([row.license_doc_path, row.trade_license_no, row.license_authority, row.license_expiry, row.licence_read_state], [null, null, null, null, null]);
  assertEquals([actions.filter((a) => a.kind === 'licence_held_for_person').length, rpcs.filter((r) => r.fn === 'fn_ceo_task_open').length], [0, 0]);
  reset(true); actions.length = 0; Object.assign(row, { license_doc_path: FILE, licence_read_state: 'ours_failed', licence_read_tries: 1 });
  await sweep({ kind: 'answer', raw: SURE_CHAMBER });
  assertEquals([row.trade_license_no, row.license_authority, row.approval_status, row.licence_read_tries], ['ZZ-OLD-0001', 'Dubai Department of Economy and Tourism', 'approved', 8]);
} });
Deno.test({ name: 'the same file refused twice for one supplier opens ONE ceo task; a third refusal opens none', sanitizeOps: false, sanitizeResources: false, fn: async () => {
  reset(); actions.length = 0;
  const raw = { ...SURE_PROFILE };
  // license_extract puts the file's SHA-256 on the finding; the stub answers the model's doc as it would
  const withSha = async () => { mode = { kind: 'answer', raw }; rpcs.length = 0;
    const r = await documentActions({ email: 'zz-demo-wrong-doc@example.invalid', action: 'process_docs',
      body: { action: 'process_docs', license: { original_b64: PROFILE_PDF, file_b64: PROFILE_PDF, images: [], filename: 'ZZ_DEMO_company_profile.pdf', mime: 'application/pdf' } } } as never) as Response;
    await r.json(); await Promise.all(later.splice(0)); return rpcs.filter((x) => x.fn === 'fn_ceo_task_open').length; };
  shaOnAnswer = 'a'.repeat(64);
  const tasks = [await withSha(), await withSha(), await withSha()];
  shaOnAnswer = null;
  assertEquals(tasks, [0, 1, 0]);
  assertEquals(actions.filter((a) => a.kind === 'licence_refused_twice').length, 1);
  assert(MSG.includes('management@quotesdone.com'), 'the sentence names a way to a person');
} });
