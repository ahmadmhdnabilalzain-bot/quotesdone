// drawing_boq — a DRAFT bill of quantities read off drawing PAGE IMAGES by a vision model. It is an
// estimate for briefing and matching, never a certified take-off, and it can only measure what is
// legible on the pages it is given: no CAD entities, no schedules it cannot read, no scale it is
// not shown. Confidence and missing_info are part of the answer, not decoration.
//
// Restored 9 Sep 2026 (deleted by the 137-function sweep, 182308b, with customer_api:618 still
// calling it — the buyer got HTTP 200 with ok:false and was told nothing).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { tooLargeToParse } from '../_shared/parse_ceiling.ts';
import { observe } from '../_shared/observe.ts';
import { pdfPages } from '../_shared/pdf_text_positions.ts';
import { boqFromPages } from './boq_from_text.ts';
import { boqFromDrawingSet, lengthsForSet, mergeLengths, type ScheduleTable } from './drawing_set.ts';
import { boqFromSheet } from './boq_from_sheet.ts';
import { boqFromExtracted } from './boq_from_document.ts';
import { readDocument } from '../_shared/doc_read/index.ts';
import { cadSupplierBoq } from '../_shared/cad_identity.ts';
import { empty } from '../_shared/doc_read/types.ts';
import { drawingInput } from './drawing_input.ts';
import { CONFIRM_MAX_TOKENS, CONFIRM_ROUTE, CONFIRM_SYS, confirmUserText, mergeConfirm, parseConfirm, redactedPageFor, type ConfirmReply, type RedactedPage, type RedactionRun } from './confirm.ts';
import { lineKey } from '../_shared/boq_open_lines.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
// Routed through ai_gateway (v3 multimodal passthrough) - the model ladder now lives in the gateway.
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
// ── THE CONFIRM STEP (14 Sep 2026, confirm.ts) ────────────────────────────────────────────────────────
// One vision call per drawing that checks the CODED draft; off unless app_secrets
// drawing_boq_confirm_enabled is 'on'. Even then the call goes through ai_gateway under task_class
// 'drawing_boq_confirm', where the founder's hold still refuses it unless public.paid_route_exception
// enables that one route (token cap, daily spend cap). Any refusal, error or unparseable reply leaves
// the coded result standing, its open lines marked "not confirmed by a second reading".
// The ONLY image it can send is `page`: a redacted page drawing_redact recorded as complete
// (confirm.ts redactedPageFor), downloaded here by its recorded path. It takes no request input.
// A take-off counted by code names its author as code, so the confirm routes normally; a draft with no author named is
// 'unknown' and the confirm is withheld (#880 review, item 4).
// deno-lint-ignore no-explicit-any
const withCodeAuthor = (b: any) => (b && typeof b === 'object' && !Array.isArray(b) ? { ...b, author_model: b.author_model ?? 'deterministic' } : b);
// `author` is the model that drafted the lines, or 'deterministic' when code counted them. drawing_boq_confirm is a
// review class (model_policy.reviews_class): ai_gateway refuses it without counterpart_model and routes it away from
// the author's family (every_review_class_is_judged_by_another_family_than_its_author.sql, founder instruction ~891).
async function confirmStep(lines: any[], page: RedactedPage, author: string): Promise<Record<string, unknown>> {
  const { data: file, error } = await admin.storage.from('drawing-files').download(page.path);
  if (error || !file) { const m = mergeConfirm(lines, null); return { boq: m.lines, confirm: m.status, confirm_detail: { why: 'redacted_page_unreadable' } }; }
  const u8 = new Uint8Array(await file.arrayBuffer()); let bin = '';
  for (let i = 0; i < u8.length; i += 0x8000) bin += String.fromCharCode(...u8.subarray(i, i + 0x8000));
  const key = await sec('cred_fn_ai');
  let reply: ConfirmReply | null = null; let why = 'no_reply';
  try {
    const r = await fetch(GW, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({
      __secret: key, fn: 'drawing_boq', task_class: CONFIRM_ROUTE, counterpart_model: author, max: CONFIRM_MAX_TOKENS, temperature: 0, sys: CONFIRM_SYS,
      input: [{ role: 'user', content: [{ type: 'text', text: confirmUserText(lines) }, { type: 'image_url', image_url: { url: dataUrl(btoa(bin), 'image/jpeg') } }] }] }) });
    const jd = await r.json();
    if (r.ok && jd?.ok !== false && jd?.content) { reply = parseConfirm(String(jd.content), new Set(lines.map((l: any) => lineKey(l)))); why = reply ? 'ok' : 'unparseable'; }
    else why = String(jd?.outcome || jd?.error || 'refused');
  } catch (_e) { why = 'exception'; }
  const m = mergeConfirm(lines, reply);
  return { boq: m.lines, confirm: m.status, confirm_detail: { why, redaction_job_id: page.job_id, disagreements: m.disagreements, model_only: m.model_only } };
}

function parseJson(t:string){ try{return JSON.parse(t);}catch{ const m=t.match(/\{[\s\S]*\}/); if(m){try{return JSON.parse(m[0]);}catch{}} return {}; } }
function dataUrl(b64: string, mime: string){ return `data:${mime};base64,${String(b64).replace(/^data:[^;]+;base64,/,'')}`; }
function scrub(s: unknown){ let t = String(s == null ? '' : s); t = t.replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '[removed]'); t = t.replace(/\b(?:https?:\/\/|www\.)[^\s)]+/gi, '[removed]'); return t; }

const CATS = 'civil_construction, fit_out_interior, mep_electrical, mep_plumbing, mep_hvac, joinery_carpentry, flooring_tiling, painting_finishes, aluminium_glass, false_ceiling_partitions, steel_fabrication, waterproofing, landscaping, signage, cleaning_facilities, swimming_pools';

const SYS = `You are a UAE quantity surveyor. You read CONSTRUCTION / FIT-OUT / MEP / architectural drawings (floor plans, elevations, sections, layouts, schedules, single-line diagrams) and produce a DRAFT Bill of Quantities (BOQ) that a contractor could price.\n\nPRIVACY (CRITICAL): your output is shown to competing suppliers who must NOT be able to identify the client or project. NEVER read out, copy or include ANY identifying information from the drawing. Specifically ignore and never repeat: the title block's company / consultant / architect / contractor names, client or owner names, any person names, phone numbers, emails, websites, the project name or title, drawing or project numbers, plot / parcel / makani numbers, and the site or project address. You MAY use the title block ONLY for scale, drawing type and dimensions. Output ONLY generic technical scope. If any text field (summary, descriptions, basis, keywords, assumptions, missing_info) would contain a name, company, phone, email or address, leave it out or generalise it (e.g. say 'a villa', not the address; 'ground floor', not the project name).\n\nRead EVERY drawing page. Use the title block, scale bar, stated dimensions, room/area labels, schedules (door/window/finish/fixture schedules), legends and symbol counts. Where a scale or explicit dimensions are given, compute areas (sqm), lengths (m) and counts (nos). Where you must assume, say so and lower the confidence.\n\nProduce measurable BOQ line items grouped into sections (e.g. Demolition, Blockwork, Flooring, Painting, Doors, Electrical points, Plumbing fixtures, HVAC, Ceiling). For each item give: a clear generic description, quantity, unit (sqm / m / nos / lot), the dimensions or basis used, and a per-item confidence. Keep to the most relevant items (aim for under 40). Be concise in every text field.\n\nIMPORTANT: this is an AI ESTIMATE for guidance and supplier matching, NOT a certified take-off. Be honest. Never invent quantities you cannot see. Flag everything you assumed and everything you could not determine.\n\nOutput ONLY the JSON object, no markdown, no prose before or after:\n{\"drawing_type\":string,\"category\":one of [${CATS}] or \"\",\"summary\":string,\"scale_detected\":string,\"total_area_sqm\":number|null,\"boq\":[{\"section\":string,\"description\":string,\"qty\":number|null,\"unit\":string,\"basis\":string,\"confidence\":\"low\"|\"medium\"|\"high\"}],\"keywords\":[string],\"assumptions\":[string],\"missing_info\":[string],\"confidence\":\"low\"|\"medium\"|\"high\"}\ncategory = best single match from the list for supplier matching. keywords = 4-10 short terms describing the trades/materials shown (for matching). If you cannot read the drawing at all, return confidence \"low\", empty boq, and explain in missing_info.`;

Deno.serve(observe('drawing_boq', async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'drawing_boq');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    // TOO BIG TO PARSE IS REFUSED BEFORE IT IS PARSED (22 Sep 2026, it_engineer, CONN-06). This
    // function decoded whatever base64 arrived and ran a PDF/CAD parse over it; past the edge CPU cap
    // that is HTTP 546, which kills the isolate — no catch, no row update, no finding. A refusal the
    // customer can act on is better than a kill nobody sees. See _shared/parse_ceiling.ts.
    const tooBig = tooLargeToParse([body.original_b64, body.file_b64, body.images]);
    if (tooBig) return J({ ok: false, ...tooBig }, 413);
    const hint = body.hint ? String(body.hint).slice(0,400) : '';
    // 14 Sep 2026. A BOQ SPREADSHEET the customer attached (customer_api analyze_boq). It is already a
    // table of quantities, so it is read cell by cell with no model and no key, before anything below.
    // THE CONFIRM STEP, called by customer_api AFTER redaction. Given only the coded lines and the
    // redaction run's id; the page comes from that run's record, never from this request.
    if (body.mode === 'confirm') {
      const lines = Array.isArray(body.boq) ? body.boq.slice(0, 120) : [];
      const flag = String((await sec('drawing_boq_confirm_enabled')) || '').toLowerCase();
      if (!['on', 'true', '1'].includes(flag) || !lines.length) return J({ ok: true, boq: lines, confirm: 'off' });
      const jobId = String(body.redaction_job_id || '');
      const { data: run } = /^[0-9a-f-]{36}$/i.test(jobId)
        ? await admin.from('drawing_redaction_runs').select('id,status,pages_in,pages_out,output_paths').eq('id', jobId).maybeSingle()
        : { data: null };
      const page = redactedPageFor(run as RedactionRun | null);
      if (!page) { const m = mergeConfirm(lines, null); return J({ ok: true, boq: m.lines, confirm: m.status, confirm_detail: { why: 'redaction_not_verified' } }); }
      // No author named: 'unknown' — the confirm is withheld, never routed as if code wrote it (every reader now names its author).
      const author = typeof body.author_model === 'string' && body.author_model.trim() ? body.author_model.trim().slice(0, 200) : 'unknown';
      return J({ ok: true, ...(await confirmStep(lines, page, author)) });
    }
    // 22 Sep 2026. THE LENGTHS, as a second call after the take-off (drawing_set.ts, "THE LENGTHS ARE A SECOND
    // CALL"): the same PDF read WITH its CAD layers, duct and pipe runs measured at the printed scale, and
    // merged into the BOQ the first call returned. If this call dies, the caller keeps that BOQ.
    if (body.mode === 'lengths') {
      const set = body.boq && typeof body.boq === 'object' && Array.isArray(body.boq.boq) ? body.boq : null;
      const b64 = String(body.original_b64 || '');
      if (!set || !/^(data:[^;]+;base64,)?JVBER/.test(b64)) return J({ ok: false, error: 'lengths_need_a_pdf_and_its_boq' }, 400);
      const bytes = Uint8Array.from(atob(b64.replace(/^data:[^;]+;base64,/, '')), (c) => c.charCodeAt(0));
      return J({ ok: true, boq: mergeLengths({ ...set, missing_info: Array.isArray(set.missing_info) ? set.missing_info : [] }, lengthsForSet(await pdfPages(bytes))) });
    }
    if (body.mode === 'sheet') {
      const r = boqFromSheet(String(body.file_b64 || ''), String(body.mime || ''), String(body.filename || ''), hint);
      return r.ok ? J({ ok: true, boq: r.boq }) : J({ ok: false, error: r.error, detail: r.detail }, 422);
    }
    // 14 Sep 2026 (founder: "the sales agent need to be extremely capable of reading all types of
    // document"). ANY document _shared/doc_read opens — Word, PowerPoint, ODF, RTF, text, email, DXF,
    // IFC, GAEB, zip, PDF — read with no model. ocr_text is the customer's browser OCR of a photo.
    const ocrText = String(body.ocr_text || '').slice(0, 200_000);
    // 14 Sep 2026. The OCR plan's lines WITH their page boxes (ocrPlan.ts) and the browser's symbol
    // counts. Both are customer-controlled input: shapes are validated here, and the counts are only
    // ever ESTIMATES the customer is asked to confirm — the server re-does the address cross-check.
    const drawing = drawingInput(body.ocr_lines, body.ocr_width, body.symbol_counts, ocrText);
    if (body.mode === 'document') {
      const r = await readDocument(String(body.file_b64 || ''), String(body.filename || ''), String(body.mime || ''));
      if (!r.ok) return J({ ok: false, error: r.error, detail: r.detail }, 422);
      // 22 Sep 2026 (redaction audit, #827): nothing a CAD file says about its own job reaches a BOQ line.
      // Every CAD reader (ASCII and binary DXF, DWG) hands back the DXF text it measured as dxf_text.
      const boq = boqFromExtracted(r, hint, ocrText, drawing);
      return J({ ok: true, boq: withCodeAuthor(r.dxf_text !== undefined ? cadSupplierBoq(boq, r.dxf_text) : boq), kind: r.kind, needs: r.needs });
    }
    // 14 Sep 2026. THE DETERMINISTIC PATH. Every model route is held, so the vision call below
    // returned ai_error on every drawing and the customer's file never informed the brief (website
    // audit 14 Sep, finding 3). A PDF drawing usually carries its schedules and area tags as real
    // text, and boq_from_text reads those with no model. It runs when there is no AI key, when the
    // gateway refuses, or when the caller asks for it (deterministic:true). It needs the ORIGINAL
    // PDF (original_b64, or file_b64 with a PDF mime): page images carry no text layer.
    // 14 SEP 2026. original_b64 was taken as a PDF whatever it was. The portal sends original_b64 for
    // EVERY upload (NewRequest.tsx), so a photographed or exported drawing (PNG/JPEG/WebP) never
    // reached the photo branch below and the customer's browser OCR was thrown away - measured on a
    // real fire-alarm layout submitted through the customer path: boq [] with the OCR text unused.
    // Only bytes that ARE a PDF (the mime says so, or they begin %PDF = base64 'JVBER') go this way.
    const cand = String(body.original_b64 || body.file_b64 || '');
    const pdfB64 = (/pdf/i.test(String(body.mime || '')) || /^(data:[^;]+;base64,)?JVBER/.test(cand)) ? cand : '';
    const deterministic = async (why: string) => {
      // A photo has no text layer: the customer's browser OCR (ocr_text) is what can be read of it.
      if (!pdfB64) {
        if (!ocrText && !drawing.lines?.length) return null;
        // No confirm here: it runs only as mode 'confirm', after redaction (see below).
        return J({ ok: true, boq: { ...boqFromExtracted(empty('image'), hint, ocrText, drawing), fallback_reason: why, author_model: 'deterministic' } });
      }
      try {
        const bytes = Uint8Array.from(atob(pdfB64.replace(/^data:[^;]+;base64,/, '')), (c) => c.charCodeAt(0));
        // Without the CAD layers: the lengths are their own call (mode 'lengths', drawing_set.ts).
        const pages = await pdfPages(bytes, undefined, { layers: false });
        // 21 Sep 2026 (founder instruction 580): a CAD drawing SET is taken off as a set — tags, air
        // devices, keyed notes, sizes — with the portal's OCR of its schedules (schedule_tables, bounded
        // by customer_api) naming make and model. Only when nothing on it is countable does the older
        // "<qty> <unit>" text reader run.
        const sched = Array.isArray(body.schedule_tables) ? (body.schedule_tables as ScheduleTable[]).slice(0, 40).filter((t) => t && Array.isArray(t.rows)) : [];
        const set = boqFromDrawingSet(pages, hint, sched);
        if (set) return J({ ok: true, boq: { ...set, fallback_reason: why, author_model: 'deterministic' } });
        const out = boqFromPages(pages, hint);
        return J({ ok: true, boq: { ...out, fallback_reason: why, author_model: 'deterministic' } });
      } catch (_e) { return null; }
    };
    const key = await sec('cred_fn_ai');
    if (!key || body.deterministic === true) {
      const d = await deterministic(key ? 'requested' : 'no_ai_key');
      if (d) return d;
      if (!key) return J({ error: 'no ai key', deterministic: pdfB64 ? 'pdf_unreadable' : 'no_pdf_supplied' }, 500);
    }

    const content: any[] = [{ type: 'text', text: `Customer note (context only): ${hint||'(none)'}. Read the attached drawing pages and return the DRAFT BOQ JSON. Remember: never include any names, company, contact or address from the drawing.` }];
    const imgs: any[] = Array.isArray(body.images) ? body.images : [];
    if (imgs.length) {
      for (const im of imgs.slice(0, 10)) { const b = (im && (im.b64 || im.data)) || im; const m = (im && im.mime) || 'image/jpeg'; if (b && typeof b === 'string') content.push({ type: 'image_url', image_url: { url: dataUrl(b, String(m)) } }); }
    } else if (body.file_b64) {
      const mime = String(body.mime || 'application/octet-stream');
      if (/^image\//.test(mime)) content.push({ type: 'image_url', image_url: { url: dataUrl(String(body.file_b64), mime) } });
      else content.push({ type: 'file', file: { filename: String(body.filename||'drawing.pdf'), file_data: dataUrl(String(body.file_b64), mime||'application/pdf') } });
    } else { return J({ error: 'no file' }, 400); }
    if (content.length < 2) return J({ error: 'no readable image' }, 400);

    let rawContent = '';
    let authorModel = 'unknown';
    let ai: any = {};
    try {
      const payload = { __secret: key, fn: 'drawing_boq', max: 8000, temperature: 0.1, sys: SYS, input: [{ role: 'user', content }] };
      const r = await fetch(GW, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
      const jd = await r.json();
      if (!r.ok || jd?.ok === false) { const d = await deterministic('ai_gateway_refused'); if (d) return d; return J({ error: 'ai_error', detail: jd?.detail || jd?.error || '', deterministic: pdfB64 ? 'pdf_unreadable' : 'no_pdf_supplied', meta: JSON.stringify(jd).slice(0,600) }, 502); }
      rawContent = jd?.content || '';
      // The draft's author, carried back by customer_api into mode 'confirm' so the confirm is routed to another family.
      authorModel = typeof jd?.model === 'string' && jd.model ? jd.model : 'unknown';
      if (body.__debug) return J({ ok: true, _len: String(rawContent).length, finish: jd?.finish_reason });
      ai = parseJson(rawContent || '{}');
    } catch (e) { const d = await deterministic('ai_exception'); if (d) return d; return J({ error: 'ai_exception', detail: String((e as Error)?.message || e) }, 502); }

    if (!Array.isArray(ai.boq)) ai.boq = [];
    ai.boq = ai.boq.slice(0, 120).map((li: any) => ({ section: scrub(li?.section||'General'), description: scrub(li?.description||''), qty: (li?.qty===null||li?.qty==='')?null:(Number(li?.qty)||null), unit: scrub(li?.unit||''), basis: scrub(li?.basis||''), confidence: ['low','medium','high'].includes(li?.confidence)?li.confidence:'low' }));
    ai.keywords = Array.isArray(ai.keywords) ? ai.keywords.map((s:any)=>scrub(s)).slice(0,12) : [];
    ai.assumptions = Array.isArray(ai.assumptions) ? ai.assumptions.map((s:any)=>scrub(s)).slice(0,20) : [];
    ai.missing_info = Array.isArray(ai.missing_info) ? ai.missing_info.map((s:any)=>scrub(s)).slice(0,20) : [];
    ai.total_area_sqm = (ai.total_area_sqm===null||ai.total_area_sqm==='')?null:(Number(ai.total_area_sqm)||null);
    ai.drawing_type = scrub(ai.drawing_type||'');
    ai.category = String(ai.category||'');
    ai.summary = scrub(ai.summary||'');
    ai.scale_detected = scrub(ai.scale_detected||'');
    if (!['low','medium','high'].includes(ai.confidence)) ai.confidence = 'low';
    ai.author_model = authorModel;
    return J({ ok: true, boq: ai });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
}));
