// rehearse_drawing_to_suppliers — ONE ZZ DEMO drawing, end to end, to the suppliers it is routed to
// (28 Sep 2026, sales_engineer; founder ledger 30, 31, 32, 580, 703). The SANDBOX rehearsal: fixture rows on the
// one project, a declared rehearsal window, torn down in `finally` (demo_factory.withRun). Nothing real.
//
//   QD_FIXTURES=1 deno run --no-lock --node-modules-dir=auto -A scripts/staging/rehearse_drawing_to_suppliers.ts
//
// WHAT RUNS, AND WHAT IS PRODUCTION CODE:
//   1. three ZZ DEMO suppliers at @example.invalid (plumbing, HVAC, MEP), approved through the factory's
//      mandatory-six path, capability confirmed (demo_factory.makeSupplier);
//   2. a ZZ DEMO customer; the drawing (doc_read's ZZ DEMO vector PDF) is read and counted by drawing_set,
//      anonymised and PROVED by _shared/drawing_file_redact.ts, and published the way the CAD worker publishes
//      (storage + a drawing_redaction_runs row). This step runs HERE, not through drawing_redact mode 'file',
//      because that mode ships in this PR and nothing is deployed before merge;
//   3. the DEPLOYED customer_api create_inquiry posts it: resolveRedactedPaths, the BOQ anonymity gate, and the
//      real routing (matchAndNotify -> fn_match_capability -> inquiry_matches). The intake conversation is a
//      model surface and is held, so the 'ready' intake row is inserted as the intake would leave it;
//   4. each routed demo supplier reads the DEPLOYED supplier_api inbox: the BOQ lines and quantities must be the
//      hand count, the drawing URL must download the exact anonymised bytes, and the bytes must carry no
//      identifier.
// Exit 0 only when every step holds.
// deno-lint-ignore-file no-explicit-any
import { withRun, makeSupplier, makeCustomer, call, uploadObject, REF } from '../lib/demo_factory.mjs';
import { mgmtFixture, mgmtRead } from '../lib/qd_guard.mjs';
import { anonymisedDrawingFile } from '../../supabase/functions/_shared/drawing_file_redact.ts';
import { fileStrings } from '../../supabase/functions/_shared/pdf_vector_redact.ts';
import { pdfPages, linesFromRuns } from '../../supabase/functions/_shared/pdf_text_positions.ts';
import { boqFromDrawingSet } from '../../supabase/functions/drawing_boq/drawing_set.ts';
import { drawingIdentityTerms, gateDrawingBoq } from '../../supabase/functions/_shared/drawing_identity_gate.ts';
import { seedTerms } from '../../supabase/functions/_shared/anonymise.ts';
import { applyEdits, requirementQuestions } from '../../supabase/functions/_shared/intake_requirements.ts';
import { IDENTITY, PDF_COUNTS, zzPdfSheetWithLogo } from '../../supabase/functions/_shared/doc_read/zz_demo_drawings.fixtures.ts';

const q = (v: unknown) => v === null || v === undefined ? 'null' : `'${String(v).replace(/'/g, "''")}'`;
const checks: { name: string; ok: boolean; detail: string }[] = [];
const step = (name: string, ok: boolean, detail: string) => { checks.push({ name, ok, detail }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name} :: ${detail}`); };
const sha = async (b: Uint8Array) => [...new Uint8Array(await crypto.subtle.digest('SHA-256', b))].map((x) => x.toString(16).padStart(2, '0')).join('').slice(0, 16);
const CATEGORY = 'mep_general';
const TRADES = ['plumbing', 'hvac', 'mep_general'];

await withRun(async (run: any) => {
  // 1. the suppliers
  const sups: any[] = [];
  for (const [i, trade] of TRADES.entries()) {
    sups.push(await makeSupplier(run, { trade, email: `qd-${run.tag}-sup${i}@example.invalid`, company_name: `ZZ DEMO ${trade.toUpperCase()} Supplier ${run.tag}`, emirate: 'Dubai', services: 'all' }));
  }
  const approved = await mgmtRead(REF, `select id, approval_status from public.leads where id in (${sups.map((s) => s.leadId).join(',')})`);
  step('three ZZ DEMO suppliers at @example.invalid, approved', approved.length === 3 && approved.every((r: any) => r.approval_status === 'approved'), JSON.stringify(approved));

  // 2. the customer and the drawing
  const cust = await makeCustomer(run, { email: `qd-${run.tag}-cust0@example.invalid`, full_name: 'ZZ DEMO Rashid Kareem' });
  await mgmtFixture(REF, `update public.customers set date_of_birth = '1985-01-01', phone = '+971500000017' where id = ${q(cust.customerId)}`, 'demo customer account complete');
  const seeds = seedTerms({ name: 'ZZ DEMO Rashid Kareem', email: cust.email, phone: '+971500000017', extra: ['ZZ DEMO Harbour Tower E-101 ZZ-2026-0142'] });
  const original = zzPdfSheetWithLogo();
  const pages = await pdfPages(original);
  const set = boqFromDrawingSet(pages, '');
  const gated = gateDrawingBoq(set, drawingIdentityTerms(linesFromRuns(pages)), false).boq as any;
  const handCount = (re: RegExp) => gated?.boq?.find((l: any) => re.test(l.description))?.qty;
  step('the drawing is counted to the hand count', handCount(/FD-1/) === PDF_COUNTS['FD-1'] && handCount(/WC-1/) === PDF_COUNTS['WC-1'], `FD-1 ${handCount(/FD-1/)}, WC-1 ${handCount(/WC-1/)}, FCU-1..3 ${[1, 2, 3].map((n) => handCount(new RegExp(`FCU-${n}`))).join('/')}`);
  const f = await anonymisedDrawingFile(original, seeds);
  step('the drawing file is anonymised and proved', f.ok, f.ok ? JSON.stringify({ kind: f.kind, ...f.proof }).slice(0, 400) : JSON.stringify(f));
  if (!f.ok) return;
  const path = `redacted/${crypto.randomUUID()}/page_drawing.pdf`;
  await uploadObject('drawing-files', path, f.bytes, f.mime);
  const runId = crypto.randomUUID();
  await mgmtFixture(REF, `insert into public.drawing_redaction_runs (id, customer_id, owner_email, caller_ref, source_path, output_paths, pages_in, pages_out, skipped, status, pages_verified, verify_failed, verify_detail)
    values (${q(runId)}::uuid, ${q(cust.customerId)}::uuid, ${q(cust.email)}, 'redacted', null, array[${q(path)}]::text[], 1, 1, 0, 'complete', 1, 0, ${q(JSON.stringify({ method: 'file', rehearsal: run.tag, ...f.proof }))}::jsonb)`, 'demo redaction run');

  // 3. the request, through the deployed create_inquiry
  const edits: Record<string, string> = {};
  for (const qn of requirementQuestions(CATEGORY)) edits[qn.key] = qn.kind === 'material' ? 'no preference' : qn.kind === 'installation' ? 'yes' : qn.kind === 'warranty' ? '1 year' : 'within 8 weeks';
  const req = applyEdits(CATEGORY, null, edits);
  if (req.invalid.length) throw new Error('requirement fixture invalid: ' + req.invalid.join(','));
  const intake = await mgmtFixture(REF, `insert into public.inquiry_intake (customer_id, email, category, status, raw_input, brief, readiness)
    values (${q(cust.customerId)}::uuid, ${q(cust.email)}, ${q(CATEGORY)}, 'ready', 'MEP works for a ground floor: plumbing fixtures and fan coil units per the attached drawing.',
            ${q(JSON.stringify({ summary: 'MEP works for a ground floor per the attached drawing', emirate: 'Dubai', requirements: req.stored, details: {} }))}::jsonb, 100) returning id`, 'demo ready intake');
  const ci = await call('customer_api', cust.jwt, { action: 'create_inquiry', intake_id: intake[0].id, category: CATEGORY, emirate: 'Dubai', scope_type: 'single', trades: TRADES,
    drawing: { brief_source: 'drawing', drawing_file_name: 'drawing.pdf', redaction_job_ids: [runId], boq: gated } });
  const inquiryId = ci.json?.id ?? ci.json?.inquiry_id ?? null;
  step('create_inquiry posts the request with the drawing and the BOQ', ci.status === 200 && !!inquiryId, `HTTP ${ci.status} ${ci.text.slice(0, 300)}`);
  if (!inquiryId) return;
  await mgmtFixture(REF, `update public.inquiries set provenance = coalesce(provenance,'{}'::jsonb) || ${q(JSON.stringify({ qd_run: run.tag }))}::jsonb where id = ${q(inquiryId)}`, 'tag demo inquiry');
  const matched = await mgmtRead(REF, `select supplier_id from public.inquiry_matches where inquiry_id = ${q(inquiryId)}`);
  const ours = sups.filter((s) => matched.some((m: any) => Number(m.supplier_id) === Number(s.leadId)));
  step('routing reached every ZZ DEMO supplier (plumbing, HVAC, MEP)', ours.length === 3, `${matched.length} match(es); demo suppliers routed: ${ours.map((s) => s.trade).join(', ') || 'none'}`);

  // 4. what each routed supplier receives
  for (const s of ours) {
    const ib = await call('supplier_api', s.jwt, { action: 'inbox', inquiry_id: inquiryId });
    const row = (ib.json?.inquiries || []).find((r: any) => String(r.id) === String(inquiryId));
    const lines = row?.boq?.boq || [];
    const got = (re: RegExp) => lines.find((l: any) => re.test(`${l.description} ${l.item ?? ''}`))?.qty;
    const urls: string[] = row?.drawing_pages || [];
    const fileUrl = urls.find((u) => /\.pdf(\?|$)/i.test(u));
    let bytes = new Uint8Array();
    if (fileUrl) bytes = new Uint8Array(await (await fetch(fileUrl)).arrayBuffer());
    const text = bytes.length ? await fileStrings(bytes) : '';
    const leaks = IDENTITY.filter((id) => text.toLowerCase().includes(id.toLowerCase()) || JSON.stringify(row ?? {}).toLowerCase().includes(id.toLowerCase()));
    step(`${s.trade} supplier receives the BOQ at the hand count`, got(/FD-1/) === PDF_COUNTS['FD-1'] && got(/WC-1/) === PDF_COUNTS['WC-1'], `FD-1 ${got(/FD-1/)}, WC-1 ${got(/WC-1/)}, ${lines.length} line(s)`);
    step(`${s.trade} supplier receives the anonymised drawing file`, !!fileUrl && (await sha(bytes)) === (await sha(f.bytes)), `${urls.length} url(s); downloaded ${bytes.length} bytes, sha ${bytes.length ? await sha(bytes) : '-'} vs ${await sha(f.bytes)}`);
    step(`${s.trade} supplier sees no identifier`, leaks.length === 0, leaks.length ? leaks.join(', ') : '0 of ' + IDENTITY.length + ' identity strings in the file or the inbox row');
  }
}, { quiet: false, keep: Deno.env.get('QD_KEEP') === '1' });

const pass = checks.filter((c) => c.ok).length;
console.log(`\nDRAWING TO SUPPLIERS ${pass}/${checks.length} on ${REF}`);
Deno.exit(pass === checks.length && checks.length > 0 ? 0 : 1);
