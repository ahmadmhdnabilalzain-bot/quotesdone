// drawing_boq — a DRAFT bill of quantities read off drawing PAGE IMAGES by a vision model. It is an
// estimate for briefing and matching, never a certified take-off, and it can only measure what is
// legible on the pages it is given: no CAD entities, no schedules it cannot read, no scale it is
// not shown. Confidence and missing_info are part of the answer, not decoration.
//
// Restored 9 Sep 2026 (deleted by the 137-function sweep, 182308b, with customer_api:618 still
// calling it — the buyer got HTTP 200 with ok:false and was told nothing).
import { parseJson as readModelJson } from '../_shared/model_json.ts';
import '../_shared/doc_read/workbook_local.ts'; // reads workbooks and .doc/.msg here with SheetJS (why one line: that file's header)
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal, secretOk } from '../_shared/internal_auth.ts';
import { tooLargeToParse } from '../_shared/parse_ceiling.ts';
import { observe } from '../_shared/observe.ts';
import { scrubIdentityText } from '../_shared/identity_text.ts';
import { linesFromRuns, pdfPages } from '../_shared/pdf_text_positions.ts';
import { isQuotationReading, pricedKind, quotationGate, quotationTerms, termsToKeep } from './quotation_gate.ts';
import { boqFromPages } from './boq_from_text.ts';
import { boqFromDrawingSet, lengthsForSet, mergeLengths, setBeforeModel, type ScheduleTable } from './drawing_set.ts';
import { boqFromSheet } from './boq_from_sheet.ts';
import { boqFromExtracted } from './boq_from_document.ts';
import { readDocument } from '../_shared/doc_read/index.ts';
import { readEveryAttachment, gatewayVision, b64Bytes } from '../_shared/read_every_attachment.ts';
import { DATA_NOT_INSTRUCTIONS, untrustedBlock } from '../_shared/untrusted.ts';
import { mergeReading } from './cross_check.ts';
import { DRAWING_KINDS, drawingIdentityTerms, gateDrawingBoq, pdfIdentityTerms, setIdentityTerms } from '../_shared/drawing_identity_gate.ts';
import { empty } from '../_shared/doc_read/types.ts';
import { drawingInput } from './drawing_input.ts';
import { parseVisionCounts, reconcile, visionUserText, VISION_COUNT_FLAG, VISION_COUNT_MAX_TOKENS, VISION_COUNT_ROUTE, VISION_COUNT_SYS } from './vision_count.ts';
import { CONFIRM_MAX_TOKENS, CONFIRM_ROUTE, CONFIRM_SYS, confirmUserText, mergeConfirm, parseConfirm, redactedPageFor, type ConfirmReply, type RedactedPage, type RedactionRun } from './confirm.ts';
import { lineKey } from '../_shared/boq_open_lines.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
// Routed through ai_gateway (v3 multimodal passthrough) - the model ladder now lives in the gateway.
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';
// ONE BUDGET FOR THE WHOLE READ (it_engineer, 12 Nov 2026; ledger 1642; final audit H4 and its review). The function must ANSWER
// before the platform kills it (150 s edge wall), whatever the model does, so a read has DRAWING_BUDGET_MS from the moment its
// request arrives. The model call is bounded by what is left of it less FALLBACK_RESERVE_MS, which the code reading (a second
// parse of the PDF and the identity gate: under 1 s for a sheet, measured on the villa fixture) and the response keep. A
// model that is cut there leaves the code reading answering (deterministic / codeAnswer). customer_api analyze_drawing has
// its own ANALYZE_DRAWING_BUDGET_MS (140 s) around this one and the lengths call; the portal waits 150 s
// (DRAWING_READ_TIMEOUT_MS), LONGER than that budget, so the customer always reads the function's own answer and the
// portal's timer only catches a dead connection. How long high takes past 55 s is not measured (8 of 9 were cut at the old
// 55 s wall): every read records its outcome (boq.model_read: finished / cut_at_budget / failed, its ms and the budget) for
// the paid journey to read. prevented by: drawing_boq/a_cut_drawing_read_answers_with_the_code_reading.test.ts
export const DRAWING_BUDGET_MS = 115_000;
export const FALLBACK_RESERVE_MS = 10_000;
/** What the model call may wait (ms), declared to ai_gateway (whose wall is this less 3 s): the read's budget left, less the reserve. */
export const modelWaitMs = (readAt: number, now = Date.now()) => readAt + DRAWING_BUDGET_MS - FALLBACK_RESERVE_MS - now;
/** Under this left, the model is not asked at all: the code reading answers (ai_gateway refuses a wall under 8 s anyway). */
export const MIN_MODEL_WAIT_MS = 8_000;
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
// secretOk() is the shared one, in ../_shared/internal_auth.ts.
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

// deno-lint-ignore no-explicit-any
function parseJson(t:string){ return readModelJson<any>(t, { wholeDecides: true }) ?? {}; }   // _shared/model_json.ts
function dataUrl(b64: string, mime: string){ return `data:${mime};base64,${String(b64).replace(/^data:[^;]+;base64,/,'')}`; }
// The model's take-off text: e-mails and URLs, and since 3 Nov 2026 the shared identity shapes (_shared/identity_text.ts).
function scrub(s: unknown){ let t = String(s == null ? '' : s); t = t.replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '[removed]'); t = t.replace(/\b(?:https?:\/\/|www\.)[^\s)]+/gi, '[removed]'); return scrubIdentityText(t, '[removed]'); }

const CATS = 'civil_construction, fit_out_interior, mep_electrical, mep_plumbing, mep_hvac, joinery_carpentry, flooring_tiling, painting_finishes, aluminium_glass, false_ceiling_partitions, steel_fabrication, waterproofing, landscaping, signage, cleaning_facilities, swimming_pools';

// 13 Nov 2026 (sales_engineer; founder ruling 1683; anonymity audit A, L2): the reading FIRST says what the attached file IS
// (document_kind) and whether a supplier of that trade could quote from it alone (sufficiency), because a customer's existing
// quotation reached this prompt as a "drawing" and nothing here told the model it was another supplier's priced offer. The
// customer_api route acts on document_kind (a quotation is rebuilt as our inquiry and never pictured, quotation_gate.ts) and
// the intake asks for what `sufficiency.missing` names. Code backstops both: quotation_gate on the text, looksPriced on the
// text layer.
const KIND_RULES = `FIRST set document_kind: \"drawing\", \"boq\" (items, no prices), \"quotation\" (any priced offer, proforma, estimate or invoice from a supplier or contractor), \"photo\" or \"other\". For a quotation give only its items: description, qty, unit and any make, model, standard, warranty or origin it specifies (make in brackets); never a price, rate, amount, total, VAT, payment term, name, contact, address, project or reference number; basis \"as listed in the customer's document\". Then sufficiency: verdict \"sufficient\" if a supplier of this trade could price every line from the file alone, else \"not_yet\" with missing: what that supplier still needs, in plain words.\n\n`;
const SYS = `You are a UAE quantity surveyor. ${KIND_RULES}You read CONSTRUCTION / FIT-OUT / MEP / architectural drawings (floor plans, elevations, sections, layouts, schedules, single-line diagrams) and produce a DRAFT Bill of Quantities (BOQ) that a contractor could price.\n\nPRIVACY (CRITICAL): your output is shown to competing suppliers who must NOT be able to identify the client or project. NEVER read out, copy or include ANY identifying information from the drawing. Specifically ignore and never repeat: the title block's company / consultant / architect / contractor names, client or owner names, any person names, phone numbers, emails, websites, the project name or title, drawing or project numbers, plot / parcel / makani numbers, and the site or project address. You MAY use the title block ONLY for scale, drawing type and dimensions. Output ONLY generic technical scope. If any text field (summary, descriptions, basis, keywords, assumptions, missing_info) would contain a name, company, phone, email or address, leave it out or generalise it (e.g. say 'a villa', not the address; 'ground floor', not the project name).\n\nRead EVERY drawing page. Use the title block, scale bar, stated dimensions, room/area labels, schedules (door/window/finish/fixture schedules), legends and symbol counts. Where a scale or explicit dimensions are given, compute areas (sqm), lengths (m) and counts (nos). Where you must assume, say so and lower the confidence.\n\nMETHOD (measure as a quantity surveyor, NRM2 / POMI conventions): count every TAGGED item (e.g. FD-1, WC-1, FCU-1, SD) once for each time it is drawn on a PLAN view - never in a legend, schedule, key, note or title block; give each tag its own line whose description starts with the tag exactly as printed (\"FD-1 - floor drain\"); counts in nos, lengths in m along centre-lines at the printed scale, areas in sqm net as drawn. If a text layer is supplied, use it to read tags exactly and still count only what sits on the plan.\n\nProduce measurable BOQ line items grouped into sections (e.g. Demolition, Blockwork, Flooring, Painting, Doors, Electrical points, Plumbing fixtures, HVAC, Ceiling). For each item give: a clear generic description, quantity, unit (sqm / m / nos / lot), the dimensions or basis used, and a per-item confidence. Keep to the most relevant items (aim for under 40). Be concise in every text field.\n\nIMPORTANT: this is an AI ESTIMATE for guidance and supplier matching, NOT a certified take-off. Be honest. Never invent quantities you cannot see. Flag everything you assumed and everything you could not determine.\n\nOutput ONLY the JSON object, no markdown, no prose before or after:\n{\"document_kind\":\"drawing\"|\"boq\"|\"quotation\"|\"photo\"|\"other\",\"sufficiency\":{\"verdict\":\"sufficient\"|\"not_yet\",\"missing\":[string]},\"drawing_type\":string,\"category\":one of [${CATS}] or \"\",\"summary\":string,\"scale_detected\":string,\"total_area_sqm\":number|null,\"boq\":[{\"section\":string,\"description\":string,\"qty\":number|null,\"unit\":string,\"basis\":string,\"confidence\":\"low\"|\"medium\"|\"high\"}],\"keywords\":[string],\"assumptions\":[string],\"missing_info\":[string],\"confidence\":\"low\"|\"medium\"|\"high\"}\ncategory = best single match from the list for supplier matching. keywords = 4-10 short terms describing the trades/materials shown (for matching). If you cannot read the drawing at all, return confidence \"low\", empty boq, and explain in missing_info.`;

Deno.serve(observe('drawing_boq', async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const readAt = Date.now();   // the read's own budget runs from here (DRAWING_BUDGET_MS)
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
    // 19 Oct 2026. THE VISION COUNT (vision_count.ts): a model counts each legend symbol on the REDACTED page of a
    // photo or scan, after redaction, like the confirm. Body: {mode:'vision_count', redaction_job_id, legend:[{type,en}],
    // code_counts, addresses}. Off when the flag is off, the page is not verified, or the model refuses: code stands.
    if (body.mode === 'vision_count') {
      const legend = (Array.isArray(body.legend) ? body.legend : []).slice(0, 30).filter((t: any) => t && typeof t.type === 'string').map((t: any) => ({ type: String(t.type).slice(0, 60), en: String(t.en || t.type).slice(0, 80) }));
      const code: Record<string, number> = {};
      for (const t of legend) { const n = Number(body.code_counts?.[t.type]); if (Number.isInteger(n) && n >= 0) code[t.type] = n; }
      const addresses = Number.isInteger(Number(body.addresses)) ? Number(body.addresses) : null;
      const flag = String((await sec(VISION_COUNT_FLAG)) || 'on').toLowerCase();
      if (['off', 'false', '0'].includes(flag) || !legend.length) return J({ ok: true, ...reconcile(code, null, addresses), why: 'off' });
      const jobId = String(body.redaction_job_id || '');
      const { data: run } = /^[0-9a-f-]{36}$/i.test(jobId) ? await admin.from('drawing_redaction_runs').select('id,status,pages_in,pages_out,output_paths').eq('id', jobId).maybeSingle() : { data: null };
      const page = redactedPageFor(run as RedactionRun | null);
      if (!page) return J({ ok: true, ...reconcile(code, null, addresses), why: 'redaction_not_verified' });
      const { data: file } = await admin.storage.from('drawing-files').download(page.path);
      if (!file) return J({ ok: true, ...reconcile(code, null, addresses), why: 'redacted_page_unreadable' });
      const u8 = new Uint8Array(await file.arrayBuffer()); let bin = '';
      for (let i = 0; i < u8.length; i += 0x8000) bin += String.fromCharCode(...u8.subarray(i, i + 0x8000));
      let vision: Record<string, number> | null = null, why = 'no_reply';
      try {
        const r = await fetch(GW, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({
          __secret: await sec('cred_fn_ai'), fn: 'drawing_boq', task_class: VISION_COUNT_ROUTE, max: VISION_COUNT_MAX_TOKENS, temperature: 0, sys: VISION_COUNT_SYS,
          input: [{ role: 'user', content: [{ type: 'text', text: visionUserText(legend) }, { type: 'image_url', image_url: { url: dataUrl(btoa(bin), 'image/jpeg') } }] }] }) });
        const jd = await r.json();
        if (r.ok && jd?.ok !== false && jd?.content) { vision = parseVisionCounts(String(jd.content), legend.map((t: any) => t.type)); why = vision ? 'ok' : 'unparseable'; }
        else why = String(jd?.outcome || jd?.error || 'refused');
      } catch (_e) { why = 'exception'; }
      return J({ ok: true, ...reconcile(code, vision, addresses), vision, why, redaction_job_id: page.job_id });
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
    // GAEB, zip, PDF — read with no model. ocr_text is the customer's browser OCR of a photo.
    const ocrText = String(body.ocr_text || '').slice(0, 200_000);
    // 14 Sep 2026. The OCR plan's lines WITH their page boxes (ocrPlan.ts) and the browser's symbol
    // counts. Both are customer-controlled input: shapes are validated here, and the counts are only
    // ever ESTIMATES the customer is asked to confirm — the server re-does the address cross-check.
    const drawing = drawingInput(body.ocr_lines, body.ocr_width, body.symbol_counts, ocrText);
    if (body.mode === 'document') {
      const r = await readDocument(String(body.file_b64 || ''), String(body.filename || ''), String(body.mime || ''), 0, { pdfCadDrawingsOnly: true });
      if (!r.ok) return J({ ok: false, error: r.error, detail: r.detail }, 422);
      // 22 Sep 2026 (redaction audit, #827): nothing a CAD file says about its own job reaches a BOQ line.
      // Every CAD reader (ASCII and binary DXF, DWG) hands back the DXF text it measured as dxf_text.
      // RULING 1177 (12 Oct 2026): a photo or a scan with no browser OCR was answered with an empty take-off. It is now
      // read by the vision model (_shared/read_every_attachment: one more asking, the gateway's second model), and held
      // with a clearer-copy request only when both askings fail.
      let seen = ocrText;
      if (r.needs === 'ocr' && !ocrText.trim() && !drawing.lines?.length) {
        const key = await sec('cred_fn_ai');
        const a = await readEveryAttachment(b64Bytes(String(body.file_b64 || '')), String(body.filename || 'document'), String(body.mime || ''), key ? gatewayVision(GW, key, { subject: body.subject ?? null }) : null);
        if (a.status !== 'read') return J({ ok: false, error: 'document_unreadable', detail: String(a.reason || '').slice(0, 200), held: 'unreadable_after_model' }, 422);
        seen = a.text;
      }
      const boq0 = boqFromExtracted(r, hint, seen, drawing);
      // A PRICED DOCUMENT read by code (QUOTATION_NOTE) passes the quotation gate with the terms its own text states
      // (quotation_gate.ts, 13 Nov 2026): measured on the audit's ZZ DEMO quotation, the code reading kept the old supplier's
      // detail code "FT-SD-04" beside its reference "FT/Q/2026/0412"; the gate removes a code that shares the reference's prefix.
      const qt = isQuotationReading(boq0) ? quotationTerms(String(r.text || seen || '').split('\n')) : null;
      const boq = qt ? { ...quotationGate(boq0, qt), old_supplier_terms: termsToKeep(qt) } : boq0;
      // 23 Sep 2026 (founder 696/698/701/703): a DRAWING's take-off (DXF, DWG, PDF) is redacted
      // with the terms the file states about itself, then RE-READ; a line still naming a party is dropped and
      // identity left anywhere else withholds the take-off. See _shared/drawing_identity_gate.ts.
      const cad = r.dxf_text !== undefined;
      if (!cad && !DRAWING_KINDS.has(r.kind)) return J({ ok: true, boq: withCodeAuthor(boq), kind: r.kind, needs: r.needs });
      // 10 Nov 2026 (evidence run ea40c830): a PDF read here is the portal's OCR of the rendered sheet, so its title strip's
      // own names (setIdentityTerms, read from the file's text layer) are gated as well, OCR misreads included.
      const pdfT = r.kind === 'pdf' ? (await pdfIdentityTerms(b64Bytes(String(body.file_b64 || '')))).terms || [] : [];
      const g = gateDrawingBoq(boq, [...drawingIdentityTerms(r.text || seen, r.dxf_text), ...pdfT], cad);
      return J({ ok: true, boq: g.boq ? withCodeAuthor(g.boq) : null, kind: r.kind, needs: r.needs, identity_dropped_lines: g.dropped_lines, ...(g.boq ? {} : { identity_held: true }) });
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
    // EVERY TAKE-OFF OF A DRAWING PASSES THE GATE (10 Nov 2026, evidence run ea40c830). The coded set merged with the model
    // was gated (cross_check.mergeReading) and the document mode was; the model's reading alone, the coded fallback and a
    // photo's OCR went out with the scrubber's shapes only, so a title-block name the shapes do not know was kept.
    // A SUMMARY THAT NAMES THE PARTY IS REMOVED WHOLE, NOT EVERY LINE WITH IT (12 Nov 2026, it_engineer; final audit H4). The
    // coded reading's summary is the customer's own note (boq_from_text.ts), and the gate holds a take-off whose text outside
    // the lines carries a title-strip term. Measured on journey 2's villa sheet (run d9a04dbc, 11 Nov 23:49): the model was
    // cut at the wall, the code reading had its 12 lines, and the customer's "G+1 private villa in Al Barsha South" matched
    // the strip's project name ("g 1 priv", "te villa"), so the whole reading was held and the customer got 0 lines. The
    // same as cross_check.ts mergeReading does for a model summary: the summary goes, the clean lines stay gated as before.
    // prevented by: drawing_boq/a_cut_drawing_read_answers_with_the_code_reading.test.ts
    // deno-lint-ignore no-explicit-any
    const gated = (boq: any, terms: string[]) => {
      let g = gateDrawingBoq(boq, terms, false);
      if (!g.boq && boq && typeof boq === 'object' && String(boq.summary || '').trim()) g = gateDrawingBoq({ ...boq, summary: '' }, terms, false);
      return J({ ok: true, boq: withRead(g.boq), identity_dropped_lines: g.dropped_lines, ...(g.boq ? {} : { identity_held: true }) });
    };
    const deterministic = async (why: string) => {
      // A photo has no text layer: the customer's browser OCR (ocr_text) is what can be read of it.
      if (!pdfB64) {
        if (!ocrText && !drawing.lines?.length) return null;
        // No confirm here: it runs only as mode 'confirm', after redaction (see below).
        return gated({ ...boqFromExtracted(empty('image'), hint, ocrText, drawing), fallback_reason: why, author_model: 'deterministic' }, drawingIdentityTerms(ocrText));
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
        const terms = setIdentityTerms(pages);
        if (set) return gated({ ...set, fallback_reason: why, author_model: 'deterministic' }, terms);
        const out = boqFromPages(pages, hint);
        return gated({ ...out, fallback_reason: why, author_model: 'deterministic' }, terms);
      } catch (_e) { return null; }
    };
    // 27 OCT 2026 — A COUNTABLE PDF SET IS COUNTED BY CODE, WITH THE MODEL ON (founder ledger 580; "routine work is
    // code, not LLM"). The code path above ran only with no AI key, a refusal or deterministic:true. Since ruling 1260
    // the key is always there, so every PDF set went to the vision model. MEASURED on production, 27 Oct 2026, the
    // 8-sheet ZZ DEMO mechanical set (scripts/e2e/drawing_reaches_suppliers.mjs): the model returned 6 lines - EF-1 and
    // EF-2 read 2 each against 1, WC/L-1, the 2,400 type-A air devices and the 16,432.8 m of 26x18 duct were missing -
    // where boqFromDrawingSet on the same text layer reads all 7 exactly (and the lengths call adds the duct). So when
    // the text layer yields a drawing set that code read completely, that set is the answer; otherwise the model drafts.
    // Not changed: a photo, a scan and a PDF with no countable tags still go to the model as before.
    // COVERAGE FLOOR (27 Oct 2026, independent review): only a set code read COMPLETELY answers here - every tag-shaped
    // run on its plans read, at least one tag. A set where code reads a few tags and misses most goes to the model as
    // before. The measurement behind the floor is in drawing_set.ts (countedCompletely).
    // 3 NOV 2026 — THE MODEL READS THE DRAWING FIRST, CODE CROSS-CHECKS IT (cross_check.ts; founder via the coordinator:
    // "it should feel as if I'm attaching a drawing to you - you understand it"). The set code counts completely is no
    // longer the whole answer: it is read here, and MERGED into the model's reading below (agreements confirmed,
    // disagreements flagged to_confirm, code's printed-tag count kept as the quantity). The text layer goes to the model
    // with the pages. With no model input, no key, a refusal or an error, the coded set answers alone, as before.
    // pdfText is the model's copy only (12k characters); the gate reads every page (setIdentityTerms, cross_check.ts).
    // What the model read did (finished / cut_at_budget / failed), on the boq this function answers with and in its log.
    let modelRead: { outcome: string; ms: number; wait_ms: number; budget_ms: number } | null = null;
    const noteRead = (outcome: string, askedAt: number, waitMs: number) => {
      modelRead = { outcome, ms: Date.now() - askedAt, wait_ms: waitMs, budget_ms: DRAWING_BUDGET_MS };
      console.log('[drawing_boq] model_read ' + JSON.stringify(modelRead));
    };
    // deno-lint-ignore no-explicit-any
    const withRead = (boq: any) => (boq && typeof boq === 'object' && !Array.isArray(boq) && modelRead ? { ...boq, model_read: modelRead } : boq);
    let codeSet: any = null, pdfText = '', idTerms: string[] = [], pdfLines: string[] = [];
    if (pdfB64 && body.deterministic !== true) {
      try {
        const bytes = Uint8Array.from(atob(pdfB64.replace(/^data:[^;]+;base64,/, '')), (c) => c.charCodeAt(0));
        const sched = Array.isArray(body.schedule_tables) ? (body.schedule_tables as ScheduleTable[]).slice(0, 40).filter((t) => t && Array.isArray(t.rows)) : [];
        const pages = await pdfPages(bytes, undefined, { layers: false });
        pdfText = pages.map((p) => p.runs.map((r) => r.text).join(' ')).join('\n').slice(0, 12_000);
        pdfLines = linesFromRuns(pages).split('\n').map((l) => l.trim()).filter(Boolean);
        const set = setBeforeModel(pages, hint, sched);
        // The terms first: a set is never merged without them (a throw here leaves the model drafting alone). Read for
        // every PDF since 10 Nov 2026: the model's reading alone is gated with them too (the last return below).
        idTerms = setIdentityTerms(pages);
        if (set) codeSet = set;
      } catch (_e) { /* not a readable PDF text layer: the model drafts alone, as before */ }
    }
    const codeAnswer = () => J({ ok: true, boq: withRead({ ...codeSet, fallback_reason: 'code_counted_the_set', author_model: 'deterministic' }) });
    const modelHasInput = (Array.isArray(body.images) && body.images.length > 0) || !!body.file_b64;
    if (codeSet && !modelHasInput) return codeAnswer();
    const key = await sec('cred_fn_ai');
    if (codeSet && !key) return codeAnswer();
    if (!key || body.deterministic === true) {
      const d = await deterministic(key ? 'requested' : 'no_ai_key');
      if (d) return d;
      if (!key) return J({ error: 'no ai key', deterministic: pdfB64 ? 'pdf_unreadable' : 'no_pdf_supplied' }, 500);
    }

    // the drawing's printed text and the customer's note are data, never instructions (untrusted.ts, 3 Nov 2026)
    const content: any[] = [{ type: 'text', text: `Read the attached drawing pages and return the DRAFT BOQ JSON. Remember: never include any names, company, contact or address from the drawing. ${DATA_NOT_INSTRUCTIONS}\nThe customer's note (context only):` + untrustedBlock(hint || '(none)', 'NOTE')
      // 3 Nov 2026 (cross_check.ts): the PDF's own text layer, for reading tags, schedules and dimensions exactly - fenced as data
      + (pdfText.trim() ? "\nThe PDF's own text layer (read tags, schedules and dimensions from it exactly):" + untrustedBlock(pdfText, 'ATTACHMENT') : '') }];
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
      // THE DRAWING READ FITS ITS BUDGET (it_engineer, 12 Nov 2026; ledger 1642; final audit H4). It declared no wait, so the
      // gateway's default 55 s wall applied. drawing_and_boq_analysis (gpt-6-luna-pro) at its default effort, 10 Nov: 11 calls,
      // p50 33.9 s, max 42.6 s. At high since 11 Nov: 8 of 9 cut at 54.6-55.4 s with nothing, one answered at 46.9 s
      // (ai_cost_log 102823-103159). It stays high (it reads documents, ruling 1630) and waits what is left of the read's
      // budget (DRAWING_BUDGET_MS above); cut there, the code reading answers.
      const waitMs = modelWaitMs(readAt);
      if (waitMs < MIN_MODEL_WAIT_MS) { noteRead('cut_at_budget', Date.now(), waitMs); throw new Error('drawing_budget: ' + waitMs + ' ms left, the model was not asked'); }
      const payload = { __secret: key, fn: 'drawing_boq', max: 8000, temperature: 0.1, sys: SYS, input: [{ role: 'user', content }], client_timeout_ms: waitMs };
      const askedAt = Date.now();
      let r: Response;
      try { r = await fetch(GW, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload), signal: AbortSignal.timeout(waitMs + 1_000) }); }
      catch (e) { noteRead('cut_at_budget', askedAt, waitMs); throw e; }
      const jd = await r.json();
      noteRead(r.ok && jd?.ok !== false ? 'finished' : jd?.error === 'gateway_deadline' ? 'cut_at_budget' : 'failed', askedAt, waitMs);
      if (!r.ok || jd?.ok === false) { if (codeSet) return codeAnswer(); const d = await deterministic('ai_gateway_refused'); if (d) return d; return J({ error: 'ai_error', detail: jd?.detail || jd?.error || '', deterministic: pdfB64 ? 'pdf_unreadable' : 'no_pdf_supplied', meta: JSON.stringify(jd).slice(0,600) }, 502); }
      rawContent = jd?.content || '';
      // The draft's author, carried back by customer_api into mode 'confirm' so the confirm is routed to another family.
      authorModel = typeof jd?.model === 'string' && jd.model ? jd.model : 'unknown';
      if (body.__debug) return J({ ok: true, _len: String(rawContent).length, finish: jd?.finish_reason });
      ai = parseJson(rawContent || '{}');
    } catch (e) { if (codeSet) return codeAnswer(); const d = await deterministic('ai_exception'); if (d) return d; return J({ error: 'ai_exception', detail: String((e as Error)?.message || e) }, 502); }

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
    // What the file IS and whether it is enough to quote: the model's word, checked for shape only.
    ai.document_kind = ['drawing', 'boq', 'quotation', 'photo', 'other'].includes(ai.document_kind) ? ai.document_kind : 'drawing';
    ai.sufficiency = ai.sufficiency && typeof ai.sufficiency === 'object' && ['sufficient', 'not_yet'].includes(ai.sufficiency.verdict)
      ? { verdict: ai.sufficiency.verdict, missing: Array.isArray(ai.sufficiency.missing) ? ai.sufficiency.missing.map((m: any) => scrub(m)).filter(Boolean).slice(0, 8) : [] } : null;
    // A priced document (the model's word, or money on the text layer) is rebuilt as our inquiry before anything else reads it.
    const pk = pdfLines.length ? pricedKind(pdfLines.join('\n')) : null;
    if (ai.document_kind !== 'quotation' && pk === 'quotation') ai.document_kind = 'quotation';
    if (isQuotationReading(ai)) ai = quotationGate(ai, quotationTerms(pdfLines));
    else if (pk === 'priced') ai = quotationGate(ai, { parties: [], refs: [], prefixes: [] }, 'priced');
    if (codeSet) {
      // The model read it; code's complete count of the same text layer cross-checks it (cross_check.ts mergeReading). A
      // reply with no line (prose, truncated, empty) leaves the coded set answering unchanged; the merged take-off passes
      // the drawing identity gate on every page's text and the title strip's names, so a model line naming a party is dropped.
      const g = mergeReading(ai, codeSet, idTerms);
      if (g.boq) return J({ ok: true, boq: withRead(g.boq), identity_dropped_lines: g.dropped_lines });
      // What the gate found: a 'seed:' entry carries the party's own name, so it is logged as 'seed' and never by value.
      console.warn(`[drawing_boq] the model's reading was not merged; the coded set answers alone (${[...new Set(g.found.map((f) => (f.startsWith('seed:') ? 'seed' : f)))].join(', ')})`);
      return codeAnswer();
    }
    return gated(ai, idTerms);
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
}));
