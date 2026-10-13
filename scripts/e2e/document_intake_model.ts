// scripts/e2e/document_intake_model.ts — the MODEL half of the document intake accuracy suite (Deno).
// Assigned: sales_engineer (reading), it_engineer (harness). Driven by scripts/e2e/document_intake_accuracy.mjs.
//
// For every licence the code could not read completely, the licence goes to the vision model exactly the way
// supplier_api.process_docs sends it (licenceModelPayload: a picture as an image, a PDF as a file), inside the
// harness's own TAGGED rehearsal window (x-qd-e2e-run + the service-role bearer, ledger 1119): the gateway lets a
// fixture subject through only while that window is open with models allowed, and fn_kernel_paid_provider_gate
// stops the run at the window's cap. Nothing else in production changes: the founder's hold stays on for every
// untagged call, and process_docs's own switch (app_secrets.document_expiry_ai) is not touched.
//
//   via=deployed  POST license_extract (the function as deployed today)
//   via=none      no model at all: production as configured today (process_docs's switch is off)
//   via=gateway   POST ai_gateway with the request THIS checkout builds (_shared/licence_extract.ts), so a prompt
//                 change is measured before it is deployed
//
//   SUPABASE_URL SUPABASE_SERVICE_ROLE_KEY QD_RUN_TAG QD_SUBJECT(json) QD_SECRET deno run -A … <corpus> <code.json> <out.json> <deployed|gateway>
import * as DX from '../../supabase/functions/_shared/document_expiry.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { readDocForTrades, modelReadText } from '../../supabase/functions/_shared/supplier_doc_trades.ts';
import { liveTradeDeps } from '../../supabase/functions/_shared/trade_resolve.ts';

const [dir, codePath, outPath, via] = Deno.args;
const URL_ = Deno.env.get('SUPABASE_URL')!, SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const TAG = Deno.env.get('QD_RUN_TAG')!, SUBJECT = JSON.parse(Deno.env.get('QD_SUBJECT') || 'null'), SECRET = Deno.env.get('QD_SECRET')!;
if (via !== 'none' && (!/^[a-z0-9]{4,16}$/.test(TAG || '') || !SUBJECT || !SECRET)) { console.error('QD_RUN_TAG, QD_SUBJECT and QD_SECRET are required'); Deno.exit(2); }
const truth = JSON.parse(await Deno.readTextFile(`${dir}/truth.json`));
const code = Object.fromEntries(JSON.parse(await Deno.readTextFile(codePath)).docs.map((d: { id: string }) => [d.id, d]));
const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${SERVICE}`, 'x-qd-e2e-run': TAG, 'x-qd-e2e-secret': Deno.env.get('QD_E2E_SECRET') || '' };
// deno-lint-ignore no-explicit-any
const anyDX = DX as any;
// deno-lint-ignore no-explicit-any
let LX: any = null;
if (via === 'gateway') LX = await import('../../supabase/functions/_shared/licence_extract.ts');

// THE MERGE process_docs makes, code first (DX.mergeLicenceReads once it exists; before it, the deployed rule spelled
// out: code's name and expiry stand, the model fills the name only when confident, and every other field is the model's).
// deno-lint-ignore no-explicit-any
function merge(c: any, m: any): { merged: Record<string, unknown>; source: Record<string, string> } {
  if (typeof anyDX.mergeLicenceReads === 'function') return anyDX.mergeLicenceReads(c, m);
  const name = c.legal_name_en ?? DX.licenceNameFromModel(m);
  const merged = { legal_name_en: name, expiry_date: c.expiry_date ?? m?.expiry_date ?? null, licence_no: m?.license_number || null,
    authority: m?.license_authority || null, emirate: m?.emirate || null, issue_date: m?.issue_date || null, activities: m?.activities || null,
    trade_name: null, legal_form: null, legal_name_ar: null };
  const source: Record<string, string> = {};
  for (const [k, v] of Object.entries(merged)) if (v != null) source[k] = (k === 'legal_name_en' && c.legal_name_en) || (k === 'expiry_date' && c.expiry_date) ? 'code' : 'model';
  return { merged, source };
}
// deno-lint-ignore no-explicit-any
let deps: any = null;
const out: Record<string, unknown>[] = [];
for (const d of truth.docs) {
  if (d.kind !== 'licence' || !d.file) continue;
  if (Deno.env.get('QD_ONLY') && !Deno.env.get('QD_ONLY')!.split(',').includes(d.id)) continue;
  const c = code[d.id]?.code || {};
  // The same question process_docs asks: is there anything code could not read that the model must be asked for?
  const ask = typeof anyDX.licenceNeedsModel === 'function' ? anyDX.licenceNeedsModel(c) : !c.legal_name_en;
  if (!ask || via === 'none') { out.push({ id: d.id, asked: false, ...merge(c, null) }); continue; }
  const bytes = await Deno.readFile(`${dir}/${d.file}`);
  const payload = DX.licenceModelPayload({}, { bytes, mime: d.mime }, null);
  const t0 = Date.now();
  let res: { status: number; json: unknown };
  try {
    if (via === 'deployed') {
      const r = await fetch(`${URL_}/functions/v1/license_extract`, { method: 'POST', headers,
        body: JSON.stringify({ __secret: SECRET, subject: SUBJECT, mode: 'license', ...payload }), signal: AbortSignal.timeout(150_000) });
      res = { status: r.status, json: await r.json().catch(() => null) };
    } else {
      const req = LX.licenceExtractRequest(payload, SUBJECT);
      const r = await fetch(`${URL_}/functions/v1/ai_gateway`, { method: 'POST', headers, body: JSON.stringify({ __secret: SECRET, ...req }), signal: AbortSignal.timeout(150_000) });
      const j = await r.json().catch(() => null);
      res = { status: r.status, json: LX.licenceFromGateway(r.ok, j) };
    }
  } catch (e) { res = { status: 0, json: { error: String((e as Error)?.message || e) } }; }
  const j = res.json as { ok?: boolean; doc?: unknown; error?: string; cost_usd?: number } | null;
  // A scan's activities as the model read them go through the same trade reading as process_docs gives them (photo_text).
  let model_trades: string[] = [];
  const acts = (j?.ok ? (j.doc as { activities?: string[] }).activities : null) || [];
  if (via === 'gateway' && acts.length && !(c.activities || []).length) {
    deps ??= await liveTradeDeps(createClient(URL_, SERVICE, { auth: { persistSession: false } }), 'document_intake_accuracy', { subject: SUBJECT, headers });
    deps.budget.left = 40;
    const ev = await readDocForTrades({ path: d.file, name: d.file, kind: 'licence', bytes, mime: d.mime, photo_text: modelReadText('licence', acts) }, deps);
    model_trades = [...new Set((ev.trades || []).map((t) => t.code))].sort();
  }
  out.push({ id: d.id, asked: true, status: res.status, ok: !!j?.ok, doc: j?.doc ?? null, model_trades, ...merge(c, j?.ok ? j.doc as Record<string, unknown> : null), error: j?.ok ? null : [j?.error, (j as { detail?: string })?.detail].filter(Boolean).join(': ').slice(0, 400) || JSON.stringify(j).slice(0, 200), ms: Date.now() - t0 });
  console.log(`${d.id}: ${res.status} ${j?.ok ? 'read' : 'not read: ' + String(j?.error ?? '').slice(0, 80)}`);
}
// A PHOTO-ONLY COMPANY PROFILE (ruling 1177): the picture goes to license_extract's profile mode, exactly as
// supplier_api.process_docs now sends it, and the services it reads are read for trades through photo_text.
for (const d of truth.docs) {
  // A profile PDF with no text layer goes to the same mode as a file, as supplier_api.process_docs sends it (13 Oct 2026).
  const noTextPdf = /pdf/i.test(d.mime) && code[d.id]?.trades?.status === 'needs_ocr';
  if (via === 'none' || d.kind !== 'profile' || !d.file || !(/^image\//.test(d.mime) || noTextPdf)) continue;
  if (Deno.env.get('QD_ONLY') && !Deno.env.get('QD_ONLY')!.split(',').includes(d.id)) continue;
  const bytes = await Deno.readFile(`${dir}/${d.file}`);
  let b64 = ''; for (let i = 0; i < bytes.length; i += 0x8000) b64 += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  let jd: any = null;
  for (let attempt = 0; attempt < 2 && !jd?.ok; attempt++) {
    const r = await fetch(`${URL_}/functions/v1/license_extract`, { method: 'POST', headers, signal: AbortSignal.timeout(150_000),
      body: JSON.stringify({ __secret: Deno.env.get('QD_SECRET_EXTRACT'), subject: SUBJECT, mode: 'profile', ...(noTextPdf ? { file_b64: btoa(b64), mime: d.mime, filename: d.file } : { images: [{ b64: btoa(b64), mime: d.mime }] }) }) });
    jd = await r.json().catch(() => null);
  }
  let model_trades: string[] = [];
  const services: string[] = jd?.ok ? (jd.profile?.services || []) : [];
  if (services.length) {
    deps ??= await liveTradeDeps(createClient(URL_, SERVICE, { auth: { persistSession: false } }), 'document_intake_accuracy', { subject: SUBJECT, headers });
    deps.budget.left = 40;
    const ev = await readDocForTrades({ path: d.file, name: d.file, kind: 'profile', bytes, mime: d.mime, photo_text: modelReadText('profile', services) }, deps);
    model_trades = [...new Set((ev.trades || []).map((t) => t.code))].sort();
  }
  out.push({ id: d.id, asked: true, ok: !!jd?.ok, profile: jd?.profile ?? null, error: jd?.ok ? null : String(jd?.error || 'no answer'), model_trades });
  console.log(`${d.id}: ${jd?.ok ? 'read ' + services.length + ' services' : 'not read'}`);
}
await Deno.writeTextFile(outPath, JSON.stringify({ via, run_tag: TAG, read_at: new Date().toISOString(), docs: out }, null, 1));
