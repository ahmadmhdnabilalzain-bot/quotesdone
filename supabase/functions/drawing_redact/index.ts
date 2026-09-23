// drawing_redact - blacks out client/consultant/contractor/project identifiers (title block, logos, address,
// contacts, drawing/project numbers) on drawing pages so a REDACTED copy can be shared with suppliers.
// Fail-closed: any page we cannot confidently clean is skipped (not shared). Internal-only: __secret auth.
//
// WHAT IT IS AND WHAT IT IS NOT — stated here because the output is shown to competing suppliers
// and the customer is told their drawing was cleaned. This is a PIXEL OVERLAY: the page is decoded
// as an image, black rectangles are composited over regions a vision model named, the result is
// re-encoded as JPEG, and a second, independent vision pass looks at the JPEG the supplier will
// actually see. That is the whole mechanism.
//
// It therefore CANNOT see, and has never seen: CAD layers, block attributes, xref paths, embedded
// document properties or thumbnails, PDF text layers or annotations, or the FILENAME. Its input is
// already-rasterised pages, so anything that is not visible as ink on those pages is outside its
// reach entirely — it is not "usually caught", it is not examined. Identity that lives in a layer
// name or in file metadata leaves this function untouched.
//
// What it does do honestly: the second pass fails CLOSED. A page that is not verified clean — for
// any reason, including the check failing to run — is NOT uploaded and NOT shared. Callers must
// treat pages_out < pages_in as pages the supplier will never see.
//
// Restored 9 Sep 2026 (deleted by the 137-function sweep, 182308b, with customer_api:615 still
// calling it — every buyer since was told their drawing had been attached when nothing ran).
// Routed through ai_gateway (v3 multimodal passthrough) - the model ladder now lives in the gateway.
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { requireInternal } from '../_shared/internal_auth.ts';
import { tooLargeToParse } from '../_shared/parse_ceiling.ts';
import { Image } from 'https://deno.land/x/imagescript@1.2.17/mod.ts';
import { observe } from '../_shared/observe.ts';
import { pdfPages, type PdfPage } from '../_shared/pdf_text_positions.ts';
import { textLayerBoxes } from '../_shared/drawing_identity_text.ts';
import { supplierPageReadable } from '../_shared/supplier_copy.ts';

// ── DETERMINISTIC REDACTION, 14 Sep 2026 ─────────────────────────────────────────────────────────
// Every model route is held, so detection below fails and no drawing page has reached a supplier
// (website audit 14 Sep, finding 3: pages_out=0, redaction_complete=false). Two model-free inputs:
//
// 1. manual_boxes — the customer draws the boxes. One entry per image: an array of normalised
//    {x,y,w,h} (an EMPTY array is the customer's own statement that the page shows nothing to hide);
//    a missing/non-array entry means the page was not reviewed and is NOT published. The customer
//    owns the drawing and is the one person who knows which names on it are theirs, so their boxes
//    are the redaction and no model vote is needed — method 'manual'.
// 2. The PDF text layer — when original_b64 is the source PDF, identity text that exists as real
//    text (emails, URLs, phones, company-suffix names, and "Drawn by / Client / Project / Plot"
//    labels with the words beside them) is located and boxed on the matching raster page. Added to
//    BOTH paths. It never publishes a page on its own: a logo or a scanned title block has no text,
//    so text-layer boxes without the customer's review or the verifier are not a clean page.
//    The detector itself (ID_TEXT, ID_LABEL, textLayerBoxes) lives in _shared/drawing_identity_text.ts
//    since 21 Sep 2026, where its test proves it against the demo plan.
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }
// FAIL-CLOSED 27 Jul 2026: sec() returns undefined/'' when the app_secrets read fails or the row is
// missing, and the guard below compared strictly, so a caller posting {} matched and gained full
// service-role authority on a function that requires no JWT. The stored secret must now be a real
// value before any caller value can equal it.
const secretOk = (v: unknown): v is string => typeof v === 'string' && v.trim().length >= 24;
function parseJson(t:string){ try{return JSON.parse(t);}catch{ const m=t.match(/\{[\s\S]*\}/); if(m){try{return JSON.parse(m[0]);}catch{}} return null; } }
// Chunked so a full-page JPEG cannot blow the argument limit: String.fromCharCode(...bytes)
// overflows the stack well before a 1600px drawing page finishes encoding.
function bytesToB64(u8: Uint8Array){ let out=''; const CH=0x8000; for(let i=0;i<u8.length;i+=CH){ out+=String.fromCharCode.apply(null, Array.from(u8.subarray(i,i+CH)) as any); } return btoa(out); }
function stripB64(s:string){ return String(s).replace(/^data:[^;]+;base64,/,''); }
function b64ToBytes(b64:string){ const bin=atob(stripB64(b64)); const a=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)a[i]=bin.charCodeAt(i); return a; }
// 21 Sep 2026: 1600 px across a 36x24 in sheet is 44 dpi — a 1/8-in note is 7 px tall and a supplier
// cannot read the tags this whole change exists to keep (founder instruction 580: the drawing content
// must survive). The portal already sends 2600 px (pdfRaster MAX_EDGE); it is now kept, not shrunk.
// Measured locally (deno, imagescript 1.2.17, a real 2600 px sheet): decode 455 ms, paint + encode 270 ms
// at 2600 against 422 + 279 ms with the resize to 1600 — skipping the resize pays for the bigger encode,
// so customer_api's 4-pages-per-call batch was kept - and on 22 Sep 2026 the edge killed those calls
// (546, 8 of 8 pages lost). customer_api now sends ONE page per call (REDACT_BATCH, measured there).
const MAXW = 2600;
// MARGIN pads a MODEL's region (a guess). The server's own boxes (anonymise.titleBlockBoxes, sent as
// manual_boxes by customer_api) are computed from text positions and already padded; a 3% pad on them
// cut 1 in off the drawing beside every title block (measured on the mechanical set: the notes column
// and the VAV schedule lost their right edge). They get SERVER_MARGIN instead.
const MARGIN = 0.03;
const SERVER_MARGIN = 0.004;

const SYS = `You are a privacy redaction assistant for construction / architectural / MEP drawings that will be shared with COMPETING suppliers. For EACH page image, find EVERY area containing information that could identify the client, the project, or the firms involved — so a supplier cannot identify or contact them.\nCover: the title block (usually a vertical strip on the right edge or a horizontal strip along the bottom), and any consultant / architect / engineer / contractor / developer / owner / client names, company logos, stamps, signatures, addresses, plot / parcel / makani numbers, project name or number, BUILDING or TOWER or VILLA name, COMMUNITY / DISTRICT / AREA name, drawing number or reference, revision number, phone numbers, emails and websites — wherever they appear (including next to the legend).\nALSO cover the NAMES OF INDIVIDUALS anywhere on the sheet: "Drawn by", "Checked by", "Approved by", "Prepared by", "Reviewed by" and any personal name beside a signature or a stamp. A draughtsman's or an approving engineer's name identifies the project to anyone in the trade as surely as the firm's does. (The text masker missed exactly these two on the one real drawing this platform has processed, which is why they are named here explicitly.)\nDo NOT cover the technical drawing, dimensions, room/space names, grid bubbles, north arrow, or the legend's SYMBOL EXPLANATIONS themselves — only the identifying text/logos. The distinction matters and is deliberate: the founder's instruction is that the legend must not show PROJECT DETAILS, not that the symbol key should be destroyed. A supplier who cannot read "◻ = single socket outlet" cannot price the job, and a drawing nobody can quote from is not anonymised, it is wasted.\nBe GENEROUS: if unsure whether a block is identifying, INCLUDE it. It is far better to over-cover than to leak.\nReturn STRICT JSON ONLY: {\"pages\":[{\"i\":0,\"has_identity\":true,\"regions\":[{\"x\":0.80,\"y\":0.0,\"w\":0.20,\"h\":1.0}]}]} — x,y,w,h are fractions 0..1 of the page (x,y = top-left corner of the box). One object per page, in the SAME order as the images. If a page truly has no identifying info, set has_identity=false and regions=[].`;

// POST-REDACTION VERIFICATION (independent audit 9.2). Detection above is a single multimodal
// call. It can return regions and still miss a small logo or a phone number, and when it returns
// has_identity:false the page was previously uploaded UNMODIFIED with the run recorded 'complete'.
// Every page is now re-examined AFTER rendering, adversarially and with no knowledge of what the
// first pass claimed. Anything it flags is refused, not published. Uncertainty counts as dirty.
const VERIFY_SYS = `You are the final check before a REDACTED construction drawing is shared with COMPETING suppliers. You are looking at the page EXACTLY as the supplier will see it.
Report ANY remaining information that could identify the client, the project, or the firms involved: company names, logos, stamps, signatures, addresses, plot/parcel/makani numbers, project names or numbers, BUILDING / TOWER / VILLA names, COMMUNITY / DISTRICT / AREA names, drawing numbers or references, phone numbers, emails, websites, or personal names — including a name beside "Drawn by", "Checked by" or "Approved by". Text inside a black box is covered and does not count - only report what is still LEGIBLE.
Do not report the technical drawing, dimensions, room names, grid bubbles, north arrow or legend symbols.
Do not report headings that describe the SHEET'S OWN CONTENT rather than a party: "GENERAL NOTES", "MECHANICAL GENERAL NOTES", "ABBREVIATIONS", "LEGEND", "KEYED NOTES", "SCHEDULE", "DEMOLITION NOTES" and the like are not identifying, and neither are equipment tags (AHU-3, VAV-2-1, EF-1), specification clause numbers, or the note text itself. Report a heading ONLY if it names or locates a person, a company or a project.
A VIEW TITLE IS NOT AN IDENTITY. "MECHANICAL DEMOLITION - LOWER LEVEL", "MECHANICAL NEW WORK UPPER LEVEL", "PLAN", "SECTION A-A" and any scale notation ("1/8\\" = 1'-0\\"", "1:100") describe what is drawn and are exactly what a supplier needs in order to quote; never report them. A REVISIONS block is not an identity either: revision numbers, dates and descriptions are drawing history. Report a revision entry ONLY when it carries a person's name or initials, or a firm's name.
Weigh what you report. A page is refused entirely on your answer, and refusing a page for a view title or a scale means the buyer's drawing reaches nobody - which helps no one and protects nothing.
Return STRICT JSON ONLY: {"clean": true, "found": []} or {"clean": false, "found": ["consultant name top right", "phone number in title block"]}.
If you cannot read the image, or you are unsure, answer {"clean": false, "found": ["uncertain"]}.`;

// ── DO NOT ROUTE THESE CALLS TO model_policy.redaction_detection. MEASURED 13 Aug 2026. ────────
//
// The obvious change, and it is wrong. model_policy holds a row `redaction_detection` whose
// rationale reads "must include independent post-redaction verification and fail closed" — written
// for exactly these calls. Neither passes a task_class; before 23 Sep 2026 fn_ai_route matched
// nothing for the verify pass and said so in its own `why`: 'no policy for "drawing_redact_verify",
// fell back to general_drafting'.
//
//                              model                          max_tokens   cache
//   what ran until 23 Sep 26   ~anthropic/claude-haiku-latest        900    true
//   redaction_detection        google/gemini-3.8-flash              1200    false
//     (No caller. It moved from gemini-3.1-flash-lite only because founder_instruction 854 retired
//      that model everywhere; its fallback is openai/gpt-5.6-sol.)
//   what runs now (find)       openai/gpt-5.6-sol                   8000    true
//                              via fn_task_class drawing_redact -> document_extraction
//                              fallback anthropic/claude-opus-5.5
//   what runs now (verify)     openai/gpt-5.6-sol                   2000    true
//                              fallback anthropic/claude-opus-5.5
//
// UPDATED 23 Sep 2026 (it_engineer), under founder_instruction 854: GPT Sol 5.6 replaced Qwen 3.8 Max
// on every class Qwen held, and the founder moved the verify pass from opus-5.5 to Sol as well. These
// calls still do not go to redaction_detection, and the verify pass is not on google.
//
// READ THE TWO LINES ABOVE TOGETHER, because the point is which model is where. On the normal path the
// FIND pass and the VERIFY pass now run the SAME model. Under 841/844 the verify had been one model
// further up than the find (opus-5.5 over Qwen) precisely so that a miss in the find was checked by a
// different opinion rather than the same one asked twice. The founder decided 854 with that trade in
// front of him; it is recorded here, not re-argued.
//
// So what makes a find miss survivable on the normal path is no longer model independence. It is this
// function's own fail-closed handling below — truncated, unparseable and exception all mean NOT clean,
// and the page is refused rather than published. That is load-bearing on EVERY path now, not
// defensive decoration. ON THE FALLBACK PATH the verify reaches anthropic/claude-opus-5.5, a different
// model from the find, and the independence returns.
//
// SUPERSEDED 23 Sep 2026 (it_engineer, founder instruction ~891: a reviewer is never the author's family).
// The verify now names the find's model as counterpart_model and ai_gateway routes it through
// fn_ai_route_review: find on Sol -> verify on Opus, find on Opus -> verify on Sol, gemini-3.8-flash (a third
// family) behind either. The fail-closed handling below stays load-bearing all the same.
// See scripts/sql/every_seat_gets_the_model_its_own_work_needs.sql §4 and
// scripts/sql/gpt_sol_takes_every_qwen_class_and_one_gemini_takes_every_gemini_class.sql.
//
// Passing task_class:'redaction_detection' was tried on staging and measured against the same
// three fixtures before and after. Before: all three pages cleared the verifier and published.
// After: cases 1 and 3 were REFUSED, and verify_detail named the fixture's eight planted
// identifiers verbatim — AL NAHDA CONSULTANTS, MR OMAR BIN FAISAL, VILLA 42, PLOT 345-8871,
// +971 4 555 1234, info@alnahda-consult.ae, AN-2026-114 — as still legible.
//
// THE PUBLISHED JPGs WERE THEN PULLED FROM drawing-files AND LOOKED AT. Both are correctly
// redacted: on case 1 the whole title block is one solid black rectangle, and on case 3 the
// diagonal watermark is covered by a staircase of black boxes across the sheet plus the title
// block. Nothing the verifier "found" is visible in either image. It reported what a title block
// USUALLY contains, primed by its own prompt, from an area that is solid black.
//
// So the pack's policy would make the redactor worse in the way that matters least visibly: it
// refuses correctly-cleaned drawings, and it fills verify_detail with fiction that the next
// session would read as evidence of a leak. A policy that exists and governs nothing is normally a
// build order. This one was measured first, and the measurement said no. Reverted; production was
// never changed. If the model is revisited, re-run scripts/staging/prove_redaction_retry.mjs and
// LOOK AT THE JPG before believing either verifier.
//
// THE SECOND PASS WAS BEING TOLD EXACTLY WHERE TO LOOK AND NOBODY LISTENED.
//
// verifyPage returns a precise, located list — "Company name/logo visible in bottom right corner
// (appears to be a triangular architectural firm logo with text)", "REVISIONS block in the title
// block area". That list was written to drawing_redaction_runs.verify_detail and used for nothing
// else: the loop below did `skipped++; continue`. So the system knew what was still showing, knew
// roughly where, and published nothing — on a product whose whole promise is that a customer can
// share a drawing.
//
// The blanket right-22%/bottom-12% fallback that was tried and removed on 13 Aug failed because it
// was aimed at a GUESS about where identity lives. This is aimed at the answer: the detector gets a
// second look at ONE page with the verifier's own findings as its brief, and covers those. Bounded
// to a single extra attempt per refused page, so a drawing costs at most one extra detect and one
// extra verify per page that actually failed.
const RETRY_SYS = `You are re-redacting ONE page of a construction drawing that has already been redacted once and REFUSED by an independent checker. You are given the page exactly as it stands now, and the checker's own list of what is STILL visible.
Your job is to cover EXACTLY what the checker named, and nothing else. Work out where each named item is on the page and return a box over it, generously sized — a box slightly too big is free, a box slightly too small means the page is refused again.
Do NOT cover the technical drawing, dimensions, room names, grid bubbles, north arrow, legend symbols, view titles, scale notations or note text. Those are what the supplier needs in order to quote, and the checker has been told not to report them.
Areas already filled solid black are done; do not box them again.
Return STRICT JSON ONLY: {"regions":[{"x":0.80,"y":0.88,"w":0.20,"h":0.12}]} — x,y,w,h are fractions 0..1 of the page (x,y = top-left corner). If you genuinely cannot locate any of the named items, return {"regions":[]}.`;

// A FAILED MEASUREMENT IS NOT A LEAK. The verifier is instructed to answer "uncertain" when it
// cannot read the image, and this function's own error paths emit verify_truncated /
// verify_unparseable / verify_exception. Those four say NOTHING about whether the page is clean —
// they say the check did not run. Masking more of the page in response is aiming at nothing; the
// right answer is to ask again. A page that stays unreadable is still refused, so the gate holds.
const NO_ANSWER = new Set(['uncertain', 'verify_truncated', 'verify_unparseable', 'verify_exception']);
const isNoAnswer = (found: string[]) => found.length > 0 && found.every((f) => NO_ANSWER.has(String(f).trim()));

async function retryRegions(key: string, jpgB64: string, found: string[]): Promise<{ regions: Array<{x:number;y:number;w:number;h:number}>; model: string | null }> {
  try {
    const r = await fetch(GW, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ __secret: key, fn: 'drawing_redact', response_format: { type: 'json_object' }, temperature: 0, sys: RETRY_SYS,
        input: [{ role: 'user', content: [
          { type: 'text', text: 'The checker refused this page. It reported, verbatim:\n- ' + found.join('\n- ') + '\n\nCover exactly those. Return the JSON.' },
          { type: 'image_url', image_url: { url: 'data:image/jpeg;base64,' + jpgB64 } }] }] }) });
    const jd = await r.json();
    const model = typeof jd?.model === 'string' && jd.model ? jd.model : null;
    if (jd?.truncated === true || jd?.finish_reason === 'length') return { regions: [], model };
    const parsed = parseJson(jd?.content || '');
    const regions = Array.isArray(parsed?.regions) ? parsed.regions : [];
    return { model, regions: regions
      .map((g: any) => ({ x: Number(g.x) || 0, y: Number(g.y) || 0, w: Number(g.w) || 0, h: Number(g.h) || 0 }))
      .filter((g: any) => g.w > 0 && g.h > 0) };
  } catch (_e) { return { regions: [], model: null }; }
}

// THE VERIFY IS NEVER THE FIND'S FAMILY (founder instruction ~891, 23 Sep 2026). `authors` names every model that
// boxed this page (the find, and the retry when it ran); ai_gateway routes identity_redaction_verify through
// fn_ai_route_review away from all of their families, with google/gemini-3.8-flash as a third-family fallback
// (scripts/sql/every_review_class_is_judged_by_another_family_than_its_author.sql). An unknown author fails closed:
// the gateway answers "no independent reviewer" and the page is refused, never published unverified.
async function verifyPage(key: string, jpgB64: string, authors: string): Promise<{ clean: boolean; found: string[] }> {
  try {
    const r = await fetch(GW, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      // `max: 400` was here, and it was the whole defect. MEASURED 5 Aug 2026, same image, same
      // prompt, same model, only the ceiling changed:
      //
      //   max 400  -> output_tokens 396, finish_reason 'length', truncated TRUE,  36 chars,
      //              cut off mid-JSON at `"found` — parseJson returns null
      //   no max   -> output_tokens 724, finish_reason 'stop',   truncated FALSE, 423 chars,
      //              parses, and correctly names the consultant, client, project and plot number
      //
      // Session 9 read the failure as "the verifier cannot parse what gemini returns" and pinned
      // the function to general_drafting to keep it off google. That diagnosis was wrong: it reads
      // gemini fine. This is the FIFTH instance of §5's "a token ceiling inside the output's
      // natural range", and gemini spends most of its budget on reasoning tokens, so a 400-token
      // ceiling on a vision check never had room for the answer.
      body: JSON.stringify({ __secret: key, fn: 'drawing_redact_verify', counterpart_model: authors, response_format: { type: 'json_object' }, temperature: 0, sys: VERIFY_SYS,
        input: [{ role: 'user', content: [
          { type: 'text', text: 'Check this redacted page. Return the JSON.' },
          { type: 'image_url', image_url: { url: 'data:image/jpeg;base64,' + jpgB64 } }] }] }) });
    const jd = await r.json();
    // A TRUNCATION IS NOT A PARSE FAILURE, and calling it one cost a session. ai_gateway has
    // returned `truncated` and `finish_reason` all along (§5: "Use it."), and this function threw
    // both away, so a ceiling problem and a model-output-shape problem produced the identical
    // symptom `verify_unparseable`. Both still fail CLOSED — an unverified page is never published
    // — but the reason is now distinguishable in verify_detail, which is what makes the difference
    // between raising a ceiling and rewriting a parser.
    if (jd?.truncated === true || jd?.finish_reason === 'length') return { clean: false, found: ['verify_truncated'] };
    const parsed = parseJson(jd?.content || '');
    if (!parsed || typeof parsed.clean !== 'boolean') return { clean: false, found: ['verify_unparseable'] };
    return { clean: parsed.clean === true, found: Array.isArray(parsed.found) ? parsed.found.map(String).slice(0, 8) : [] };
  } catch (_e) {
    return { clean: false, found: ['verify_exception'] };
  }
}


// REDACTION PROVENANCE 2 Aug 2026 (external security review). WHY: suppliers are served the paths
// this function returns as SIGNED URLs before any reveal fee is paid, and supplier_api will sign
// ANY object in the 'drawing-files' bucket - including the customer's ORIGINAL, unredacted upload,
// which lives in that same bucket under drawings/<customer_id>/. Until now these paths were only
// RETURNED to the caller and were then copied into inquiries.drawing_redacted_paths straight from
// the create_inquiry REQUEST BODY, so nothing server-side knew which paths were genuinely produced
// by a redaction run, who owned them, or how many pages had actually been cleaned. Every run is now
// recorded in public.drawing_redaction_runs and create_inquiry resolves what may be attached from
// that table alone. Recording is therefore load-bearing, not telemetry: if the insert fails the run
// is reported as unrecorded (recorded:false) and its paths will be refused downstream - fail-closed,
// exactly like a page we could not clean.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
async function recordRun(id: string, body: any, o: { status: string; paths: string[]; pages_in: number; pages_out: number; skipped: number; pages_verified?: number; verify_failed?: number; verify_detail?: any }): Promise<boolean> {
  try {
    const custId = typeof body?.owner_customer_id === 'string' && UUID_RE.test(body.owner_customer_id) ? body.owner_customer_id : null;
    const { error } = await admin.from('drawing_redaction_runs').insert({
      id,
      customer_id: custId,
      owner_email: body?.owner_email ? String(body.owner_email).toLowerCase().slice(0, 320) : null,
      caller_ref: body?.prefix ? String(body.prefix).slice(0, 400) : null,
      source_path: body?.source_path ? String(body.source_path).slice(0, 400) : null,
      output_paths: o.paths,
      pages_in: o.pages_in,
      pages_out: o.pages_out,
      skipped: o.skipped,
      status: o.status,
      pages_verified: o.pages_verified ?? 0,
      verify_failed: o.verify_failed ?? 0,
      verify_detail: o.verify_detail ?? null,
    });
    return !error;
  } catch (_e) { return false; }
}

Deno.serve(observe('drawing_redact', async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  try {
    const body = await req.json().catch(() => ({} as any));
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called.
    const __auth = await requireInternal(admin, body?.__secret, 'drawing_redact');
    if (!__auth.ok) return J({ error: 'forbidden' }, 403);
    // TOO BIG TO PARSE IS REFUSED BEFORE IT IS PARSED (22 Sep 2026, it_engineer, CONN-06). The pixel
    // work plus the PDF text layer is what put this function past the edge CPU cap (HTTP 546, 8 of 8
    // pages lost). The page COUNT was already capped here; the SIZE never was. See
    // _shared/parse_ceiling.ts — and note the refusal comes back before job_id means anything, so no
    // half-run is recorded for a request that was never begun.
    const tooBig = tooLargeToParse([body.images, body.original_b64]);
    if (tooBig) return J({ ok: false, ...tooBig }, 413);
    const job_id = crypto.randomUUID();
    // ANONYMITY 27 Jul 2026. These objects are handed to matched suppliers as SIGNED URLs before any
    // reveal or payment, and a signed URL necessarily contains the object path. The path is therefore
    // untrusted output: anything a caller puts in it is readable by every supplier who is matched.
    // Callers used to supply the whole prefix and both of them embedded an identifier plus a clock —
    // customer_api sent `redacted/<customers.id>/<Date.now()>` and attach_photos sends
    // `refphoto/<user.id>/<Date.now()>` — so a supplier could correlate the same buyer across every
    // RFQ they ever post, which is exactly the identity QuotesDone charges a reveal fee to disclose.
    // The caller's prefix now selects ONLY the namespace (its first path segment, e.g. 'redacted' or
    // 'refphoto'); the identifying remainder is discarded and replaced here with an opaque random
    // UUID that is not derivable from the customer, the inquiry or the time. This is deliberately
    // enforced at the single point where the stored path is built, so no caller — present or future —
    // can reintroduce the leak. Retrieval is unaffected: the paths returned below are stored verbatim
    // in inquiries.drawing_redacted_paths, which remains the only source of truth for reading,
    // signing and deleting these objects. Nothing anywhere reconstructs or prefix-lists this path.
    const ns = (String(body.prefix || 'redacted').split('/')[0] || 'redacted').replace(/[^A-Za-z0-9._-]/g, '_');
    const prefix = `${ns}/${crypto.randomUUID()}/page`;
    const imgs: any[] = Array.isArray(body.images) ? body.images.slice(0, 8) : [];
    if (!imgs.length) { const recorded = await recordRun(job_id, body, { status: 'empty', paths: [], pages_in: 0, pages_out: 0, skipped: 0 }); return J({ ok: true, job_id, recorded, paths: [], pages_in: 0, pages_out: 0 }); }

    // Text layer of the source PDF, if the caller sent it. page_offset maps this batch's images onto
    // PDF pages, because customer_api sends a drawing set to this function 4 pages at a time.
    const pageOffset = Math.max(0, Number(body.page_offset) || 0);
    let pdf: PdfPage[] = [];
    if (body.original_b64 && typeof body.original_b64 === 'string') {
      // Only THIS batch's pages are interpreted (22 Sep 2026): parsing the whole set on every call, on top
      // of the pixel work, put each 4-page call past the edge CPU cap - HTTP 546, 8 of 8 pages lost, on
      // production with an 8-sheet 36x24 set at 2600 px (scripts/e2e/drawing_reaches_suppliers.mjs).
      try { pdf = await pdfPages(b64ToBytes(body.original_b64), [pageOffset, pageOffset + imgs.length], { layers: false }); } catch (_e) { pdf = []; }
    }
    const textBoxes = (i: number) => textLayerBoxes(pdf, pageOffset + i);
    const paintBoxes = (target: any, gs: Array<{x:number;y:number;w:number;h:number}>, pad = SERVER_MARGIN) => {
      const W2 = target.width, H2 = target.height;
      for (const g of gs) {
        let x = Math.floor((g.x - pad) * W2), y = Math.floor((g.y - pad) * H2);
        let w = Math.ceil((g.w + 2 * pad) * W2), h = Math.ceil((g.h + 2 * pad) * H2);
        x = Math.max(0, Math.min(x, W2 - 1)); y = Math.max(0, Math.min(y, H2 - 1));
        w = Math.max(1, Math.min(w, W2 - x)); h = Math.max(1, Math.min(h, H2 - y));
        target.composite(new Image(w, h).fill(0x000000ff), x, y);
      }
    };

    // ── MANUAL PATH: the customer's own boxes, no model involved ──────────────────────────────────
    if (Array.isArray(body.manual_boxes)) {
      const paths: string[] = []; let skipped = 0; let textHits = 0; const detail: any[] = [];
      for (let i = 0; i < imgs.length; i++) {
        const mb = body.manual_boxes[i];
        if (!Array.isArray(mb)) { skipped++; detail.push({ page: i, skipped: 'not_reviewed_by_customer' }); continue; }
        try {
          const boxes = mb.slice(0, 60).map((g: any) => ({ x: Math.max(0, Math.min(1, Number(g?.x) || 0)), y: Math.max(0, Math.min(1, Number(g?.y) || 0)), w: Math.max(0, Math.min(1, Number(g?.w) || 0)), h: Math.max(0, Math.min(1, Number(g?.h) || 0)) })).filter((g: any) => g.w > 0 && g.h > 0);
          const tl = textBoxes(i); textHits += tl.boxes.length;
          // FAIL CLOSED (founder, 14 Sep 2026: nothing that identifies the customer may reach a
          // supplier). The leak audit measured this path publishing a scanned page untouched when the
          // customer sent an empty box list. A page whose words cannot be read here (a scan, a photo,
          // a rotated page) and on which the customer drew nothing has been checked by nobody: it is
          // HELD, never published, and the run is recorded as partial or failed.
          const pg = pdf[pageOffset + i];
          const readable = !!(pg && pg.runs && pg.runs.length) && !tl.rotated;
          // TRUST BOUNDARY (14 Sep 2026): boxes come from the customer's browser and prove nothing on a
          // page the server cannot read. Such a page is held whatever boxes arrived with it.
          if (!supplierPageReadable(pg, tl.rotated)) { skipped++; detail.push({ page: i, skipped: boxes.length ? 'held_unverifiable_client_boxes_ignored' : 'held_unverified_no_text_no_boxes' }); continue; }
          const b = (imgs[i] && (imgs[i].b64 || imgs[i].data)) || imgs[i];
          let img = await Image.decode(b64ToBytes(String(b)));
          if (img.width > MAXW) img = img.resize(MAXW, Image.RESIZE_AUTO);
          paintBoxes(img, [...boxes, ...tl.boxes]);
          const jpg = await img.encodeJPEG(82);
          const path = `${prefix}_p${i}.jpg`;
          const up = await admin.storage.from('drawing-files').upload(path, jpg, { contentType: 'image/jpeg', upsert: true });
          if (up.error) { skipped++; detail.push({ page: i, skipped: 'upload_failed' }); continue; }
          paths.push(path); detail.push({ page: i, manual_boxes: boxes.length, text_layer_boxes: tl.boxes.length, rotated: tl.rotated || undefined });
        } catch (_e) { skipped++; detail.push({ page: i, skipped: 'decode_failed' }); }
      }
      const status = paths.length === 0 ? 'failed' : (paths.length < imgs.length ? 'partial' : 'complete');
      const recorded = await recordRun(job_id, body, { status, paths, pages_in: imgs.length, pages_out: paths.length, skipped, pages_verified: 0, verify_failed: 0, verify_detail: { method: 'manual', pages: detail } });
      return J({ ok: true, job_id, recorded, paths, pages_in: imgs.length, pages_out: paths.length, skipped, pages_verified: 0, verify_failed: 0, verify_detail: detail, status, method: 'manual', text_layer_hits: textHits, redaction_complete: recorded && paths.length === imgs.length });
    }

    const key = await sec('cred_fn_ai');
    // No model and no customer boxes: nothing may be published. Say what would unblock it.
    if (!key) { const recorded = await recordRun(job_id, body, { status: 'detect_failed', paths: [], pages_in: imgs.length, pages_out: 0, skipped: imgs.length }); return J({ ok: false, error: 'no_ai_key', job_id, recorded, needs_manual_boxes: true, redaction_complete: false }, 200); }

    const content: any[] = [{ type: 'text', text: 'Find identifying regions to black out on each of the following ' + imgs.length + ' drawing page(s). Return the JSON.' }];
    for (const im of imgs) { const b = (im && (im.b64 || im.data)) || im; const m = (im && im.mime) || 'image/jpeg'; if (b && typeof b === 'string') content.push({ type: 'image_url', image_url: { url: 'data:' + m + ';base64,' + stripB64(b) } }); }
    const regionsByPage: Record<number, {x:number;y:number;w:number;h:number}[]> = {};
    const identityByPage: Record<number, boolean> = {};
    let findModel = 'unknown';   // the model that boxed the pages; the verify must be of another family
    try {
      // `max: 2000` removed 5 Aug 2026, same reasoning as the verify call above and the same
      // reasoning that fixed doc_extract and license_extract: ai_gateway takes min(caller, policy),
      // so a caller literal can only ever LOWER document_extraction's 8000, never raise it.
      //
      // This one is the more dangerous of the two, because its output scales with PAGE COUNT: one
      // object per page, each carrying a regions array. A single-page drawing fits inside 2,000
      // comfortably, which is precisely why the journey never crossed it — the same blind spot that
      // hid doc_extract's ceiling until a real page was measured at 1,996 / 2,170 / 2,051. A
      // six-page drawing set is a different distribution entirely, and the failure lands as
      // `detect_failed` on a PRIVACY control.
      const r = await fetch(GW, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: key, fn: 'drawing_redact', response_format: { type: 'json_object' }, temperature: 0, sys: SYS, input: [{ role: 'user', content }] }) });
      const jd = await r.json();
      if (typeof jd?.model === 'string' && jd.model) findModel = jd.model;
      // Fails closed either way — nothing is published — but `detect_truncated` says "raise the
      // ceiling" where `detect_failed` says "the model misbehaved", and session 9 lost a day to
      // exactly that confusion on the verify call.
      if (jd?.truncated === true || jd?.finish_reason === 'length') { const recorded = await recordRun(job_id, body, { status: 'detect_truncated', paths: [], pages_in: imgs.length, pages_out: 0, skipped: imgs.length }); return J({ ok: false, error: 'detect_truncated', job_id, recorded, needs_manual_boxes: true, redaction_complete: false }, 200); }
      const parsed = parseJson(jd?.content || '');
      if (!parsed || !Array.isArray(parsed.pages)) { const recorded = await recordRun(job_id, body, { status: 'detect_failed', paths: [], pages_in: imgs.length, pages_out: 0, skipped: imgs.length }); return J({ ok: false, error: 'detect_failed', job_id, recorded, needs_manual_boxes: true, redaction_complete: false }, 200); }
      for (const p of parsed.pages) { const i = Number(p?.i); if (!Number.isFinite(i)) continue; identityByPage[i] = p?.has_identity !== false; regionsByPage[i] = Array.isArray(p?.regions) ? p.regions.map((g:any)=>({x:Number(g.x)||0,y:Number(g.y)||0,w:Number(g.w)||0,h:Number(g.h)||0})).filter((g:any)=>g.w>0&&g.h>0) : []; }
    } catch (_e) { const recorded = await recordRun(job_id, body, { status: 'detect_exception', paths: [], pages_in: imgs.length, pages_out: 0, skipped: imgs.length }); return J({ ok: false, error: 'detect_exception', job_id, recorded, needs_manual_boxes: true, redaction_complete: false }, 200); }

    const paths: string[] = []; let skipped = 0; let verified = 0; let verifyFailed = 0; const verifyDetail: any[] = [];
    for (let i = 0; i < imgs.length; i++) {
      try {
        const regions = regionsByPage[i] || [];
        const hasId = identityByPage[i] !== false;
        // A page the model says has identity but gives no regions for is unusable - unchanged.
        if (hasId && regions.length === 0) { skipped++; continue; }
        // has_identity:false used to mean 'upload it untouched'. One unverified model judgement
        // is not enough to publish a page to competitors; it now falls through to the
        // verification pass below like every other page.
        const b = (imgs[i] && (imgs[i].b64 || imgs[i].data)) || imgs[i];
        let img = await Image.decode(b64ToBytes(String(b)));
        if (img.width > MAXW) img = img.resize(MAXW, Image.RESIZE_AUTO);
        // Boxing is its own step now because the retry below has to do it again, with regions the
        // verifier asked for rather than the ones the first detection pass guessed at.
        const paint = (target: any, gs: Array<{x:number;y:number;w:number;h:number}>) => {
          const W2 = target.width, H2 = target.height;
          for (const g of gs) {
            let x = Math.floor((g.x - MARGIN) * W2), y = Math.floor((g.y - MARGIN) * H2);
            let w = Math.ceil((g.w + 2 * MARGIN) * W2), h = Math.ceil((g.h + 2 * MARGIN) * H2);
            x = Math.max(0, Math.min(x, W2 - 1)); y = Math.max(0, Math.min(y, H2 - 1));
            w = Math.max(1, Math.min(w, W2 - x)); h = Math.max(1, Math.min(h, H2 - y));
            target.composite(new Image(w, h).fill(0x000000ff), x, y);
          }
        };
        // Identity the text layer locates is boxed as well as what the model named; the verifier
        // below still decides whether the page is published.
        paint(img, [...regions, ...textBoxes(i).boxes]);
        let jpg = await img.encodeJPEG(82);
        // Adversarial second pass over what the supplier will actually see. Fails closed.
        //
        // A BLANKET TITLE-BLOCK FALLBACK WAS TRIED HERE AND REMOVED (13 Aug 2026). Masking the
        // right 22% and bottom 12% of any page the verifier refused, then re-checking once, was
        // measured on the same real 6-sheet mechanical set across three runs: the yield stayed at
        // 4 of 6 with it and without it. It cost an extra vision call per failing page and blacked
        // out a third of a drawing for no measured gain, so it is not here. What the verifier
        // actually still reports on the two refused pages is a logo in a corner and a REVISIONS
        // block — not the title strip. Anything that replaces this should be aimed there.
        let vr = await verifyPage(key, bytesToB64(jpg), findModel);
        let attempt = 1;
        if (!vr.clean) {
          // ONE more attempt, and its shape depends on what the refusal actually was.
          if (isNoAnswer(vr.found)) {
            // The check did not run. Re-ask the same image; nothing about the page is known to be
            // wrong, so masking more of it would be aiming at nothing.
            attempt = 2;
            vr = await verifyPage(key, bytesToB64(jpg), findModel);
          } else {
            // The check ran and named what is left. Cover exactly that, then re-verify.
            const retry = await retryRegions(key, bytesToB64(jpg), vr.found);
            const extra = retry.regions;
            if (extra.length) {
              attempt = 2;
              paint(img, extra);
              jpg = await img.encodeJPEG(82);
              vr = await verifyPage(key, bytesToB64(jpg), [findModel, retry.model ?? 'unknown'].join(','));
            }
          }
        }
        // Still refused after the second attempt: unchanged behaviour, the page is not published.
        // The ledger now records which attempt decided it, so "the retry never helps" is a query
        // rather than an opinion the next session has to take on trust.
        if (!vr.clean) { verifyFailed++; skipped++; verifyDetail.push({ page: i, attempts: attempt, found: vr.found }); continue; }
        if (attempt > 1) verifyDetail.push({ page: i, attempts: attempt, recovered: true });
        verified++;
        const path = `${prefix}_p${i}.jpg`;
        const up = await admin.storage.from('drawing-files').upload(path, jpg, { contentType: 'image/jpeg', upsert: true });
        if (up.error) { skipped++; continue; }
        paths.push(path);
      } catch (_e) { skipped++; continue; }
    }
    const status = paths.length === 0 ? 'failed' : (paths.length < imgs.length ? 'partial' : 'complete');
    const recorded = await recordRun(job_id, body, { status, paths, pages_in: imgs.length, pages_out: paths.length, skipped, pages_verified: verified, verify_failed: verifyFailed, verify_detail: verifyDetail.length ? verifyDetail : null });
    return J({ ok: true, job_id, recorded, paths, pages_in: imgs.length, pages_out: paths.length, skipped, pages_verified: verified, verify_failed: verifyFailed, verify_detail: verifyDetail, status, method: 'model', redaction_complete: recorded && paths.length === imgs.length });
  } catch (e) { return J({ ok: false, error: String((e as Error)?.message || e) }, 200); }
}));
