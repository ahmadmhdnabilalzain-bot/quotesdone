// customer_api — documents a customer sends: cad_read_status, analyze_boq, analyze_document, analyze_drawing.
//
// The if-chain below is index.ts's own, moved line for line with its original indentation, so each
// `if (action === …)` reads exactly as it did and the checks that locate a handler by that line still find it.
// index.ts calls this group with the request's context and returns the first Response a group gives.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 2,516-line index.ts split into modules, a pure move).
import { clearerCopyAsk } from '../../_shared/clearer_copy.ts';
import { SAFE_UPLOAD, SAFE_SHEET, SAFE_DOCS } from '../../_shared/attachment.ts';
import { seedTerms, titleBlockBoxes } from '../../_shared/anonymise.ts';
import { supplierBoxes } from '../../_shared/supplier_copy.ts';
import { cadSupplierBoq, dxfTextOf } from '../../_shared/cad_identity.ts';
import { budgetNote, cadNote, fileHeldNote, drawingHandoff, heldRun } from '../drawing_hold.ts';
import { isPhotoOrScan, visionCountBody, applyVisionCounts } from '../vision_count_wire.ts';
import { documentLocale } from '../../_shared/registered_locale.ts';
import { pdfPages } from '../../_shared/pdf_text_positions.ts';
import { LENGTHS_FAILED_NOTE, LENGTHS_QUEUED_NOTE } from '../../drawing_boq/length_notes.ts';
import { timedFetch } from '../../_shared/timed_fetch.ts';
import { DRAWING_FORMAT_ERROR, drawingFormatRefusal, drawingFormatRefused } from '../../_shared/drawing_format.ts';
import { cadJobNeedsRedispatch, claimCadDispatch } from '../cad_dispatch.ts';
import { type ActionCtx, J, SERVICE, SUPABASE_URL, admin, getSecret } from '../context.ts';
import { MAX_DRAWING_PAGES, cadQueueReason, cadReadHeld, drawingOcr, queueCadRead, recordHeld, redactCad, redactFile, scheduleTables, storeOriginal } from '../lib/drawings.ts';

/** analyze_drawing answers inside this (ms from its request), 10 s before the 150 s edge wall. See the action below. */
export const ANALYZE_DRAWING_BUDGET_MS = 140_000;

export async function documentActions(c: ActionCtx): Promise<Response | undefined> {
  const { body, action, email, cust } = c;
    // ATTACH A BOQ (founder, 14 Sep 2026: "describe a job / drop a drawing is fine but add attach a
    // BOQ also"). A spreadsheet BOQ (xlsx / xls / csv). drawing_boq mode 'sheet' sniffs it by its
    // bytes, caps it at 5 MB, refuses macros and encryption, and reads cached cell values with no model.
    // Only a file it accepted is stored, beside drawings, with the same owner ledger row, so pdpl_erase
    // finds it the same way. A PDF BOQ does not come here: analyze_drawing reads its text layer.
    // THE TAKE-OFF OF A QUEUED CAD DRAWING (22 Sep 2026, see queueCadRead). Only the job's own customer
    // gets an answer; anyone else's id reads as not found.
    if (action === 'cad_read_status') {
      const id = String(body.job_id || '');
      if (!/^[0-9a-f-]{36}$/i.test(id)) return J({ ok: false, error: 'not_found' }, 404);
      const { data: job } = await admin.from('cad_read_jobs').select('status, result, boq_in, finished_at, created_at, claimed_at').eq('id', id).eq('customer_id', cust.id).maybeSingle();
      if (!job) return J({ ok: false, error: 'not_found' }, 404);
      const redo = cadJobNeedsRedispatch(job as any);
      if (redo === 'held' && await claimCadDispatch(admin, id)) await cadReadHeld(id, 'not_taken_by_the_cad_read_routine_within_its_interval');
      // 24 Sep 2026: the worker also DRAWS a CAD file the edge could not, for suppliers (cad_read_worker.ts
      // supplierDrawing); its recorded page comes back here so the customer's request can carry it.
      const res = job.status === 'done' ? (job.result as any) : null;
      const pages = res?.redaction_complete === true && Array.isArray(res.drawing_redacted_paths) ? res.drawing_redacted_paths.map((p: unknown) => String(p)) : [];
      // THE PHOTO'S LEGEND, COUNTED ON THE PAGE THE WORKER PROVED CLEAN (27 Oct 2026, ledger 580; ./vision_count_wire.ts).
      // Once per job: the reply is kept on the job's result, so a poll every 15 s does not pay for it again.
      const vcIn = (job.boq_in as any)?.vision_count;
      let counted: { boq: unknown; vision_count: unknown } | null = null;
      if (res && pages.length && vcIn && Array.isArray((job.boq_in as any)?.vision_lines)) {
        let vj = res.vision_count ?? null;
        // AT MOST 3 ASKINGS PER JOB (independent review of #1641, 27 Oct 2026): only a success was kept, so a failing
        // model call was paid again on every 15 s poll for as long as the customer's page stayed open. A failure is now
        // kept too, with its count; after the third the code's counts stand for good.
        const tries = Number((vj as any)?.attempts) || 0;
        if (!vj || (vj.ok !== true && tries < 3)) {
          try {
            // 60 s: one vision call on one page (VISION_COUNT_MAX_TOKENS 600); past it the code's counts stand and the next poll retries.
            const vr = await timedFetch(`${SUPABASE_URL}/functions/v1/drawing_boq`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: await getSecret('cred_fn_customer_api'), mode: 'vision_count', redaction_job_id: String(res.redaction_job_id || ''), ...vcIn }) }, 60_000);
            vj = await vr.json().catch(() => null);
          } catch (_e) { vj = null; }
          vj = vj && typeof vj === 'object' ? { ok: vj.ok === true, counts: vj.counts ?? null, source: vj.source ?? null, agrees: vj.agrees ?? null, vision: vj.vision ?? null, why: vj.why ?? null, attempts: tries + 1 } : { ok: false, why: 'no_reply', attempts: tries + 1 };
          await admin.from('cad_read_jobs').update({ result: { ...res, vision_count: vj } }).eq('id', id);
        }
        counted = { boq: applyVisionCounts((job.boq_in as any).vision_lines, vj), vision_count: { source: vj?.source ?? null, why: vj?.why ?? null, agrees: vj?.agrees ?? null } };
      }
      return J({ ok: true, status: job.status, ...(job.status === 'queued' || job.status === 'running' ? { held_for: 'sales_engineer' } : {}), boq: res?.boq ?? null, ...(counted ? { counted_boq: counted.boq, vision_count: counted.vision_count } : {}), ...(pages.length ? { drawing_redacted_paths: pages, redaction_job_id: String(res.redaction_job_id || ''), redaction_job_ids: Array.isArray(res.redaction_job_ids) ? res.redaction_job_ids.map((x: unknown) => String(x)) : [String(res.redaction_job_id || '')], redaction_complete: true, drawing_held: false } : {}) });
    }

    if (action === 'analyze_boq') {
      const name = String(body.file_name || 'boq').slice(0, 180);
      const mime = String(body.mime || '');
      { const refused = drawingFormatRefusal(name, mime); if (refused) return J(refused, 415); }
      const b64 = String(body.file_b64 || '');
      if (!b64) return J({ ok: false, error: 'empty_upload' }, 400);
      // 5 MB of bytes is about 6.7 MB of base64: refused here before anything is decoded or forwarded.
      if (b64.length > 7 * 1024 * 1024) return J({ ok: false, error: 'file_too_large', code: 'file_too_large', message: 'That file is too large. Please upload a smaller version.', message_ar: 'هذا الملف كبير جدًا. يُرجى رفع نسخة أصغر.' }, 413);
      const hint = String(body.hint || '').slice(0, 400);
      const secret = await getSecret('cred_fn_customer_api');
      let jd: any = null;
      try {
        const r = await fetch(`${SUPABASE_URL}/functions/v1/drawing_boq`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, mode: 'sheet', file_b64: b64, mime, filename: name, hint }) });
        jd = await r.json();
      } catch (_e) { /* answered below as boq_unreadable */ }
      // Ruling 1177: an unreadable file is answered with a clearer-copy request in the customer's own language.
      if (!jd?.ok) return J({ ok: false, error: String(jd?.error || 'boq_unreadable'), detail: String(jd?.detail || '').slice(0, 200), message: clearerCopyAsk('customer', documentLocale(body.lang, cust.locale), name) });
      const path = await storeOriginal(cust.id, email, name, mime, b64, SAFE_SHEET);
      return J({ ok: true, boq: jd.boq, drawing_file_path: path, drawing_file_name: name, drawing_redacted_paths: [], stored: !!path });
    }

    // EVERY DOCUMENT (14 Sep 2026; founder: "the sales agent need to be extremely capable of reading
    // all types of document"). Word, PowerPoint, ODF, RTF, text, email (.eml/.msg), DXF, GAEB,
    // zip and PDF are read by drawing_boq mode 'document' with no model; a photo arrives with the
    // customer's browser OCR as ocr_text. The same 20 MB ceiling as doc_read; stored only if accepted.
    if (action === 'analyze_document') {
      const name = String(body.file_name || 'document').slice(0, 180);
      const mime = String(body.mime || '');
      { const refused = drawingFormatRefusal(name, mime); if (refused) return J(refused, 415); }
      const b64 = String(body.file_b64 || '');
      if (!b64) return J({ ok: false, error: 'empty_upload' }, 400);
      if (b64.length > 27 * 1024 * 1024) return J({ ok: false, error: 'file_too_large', code: 'file_too_large', message: 'That file is too large. Please upload a smaller version.', message_ar: 'هذا الملف كبير جدًا. يُرجى رفع نسخة أصغر.' }, 413);
      const hint = String(body.hint || '').slice(0, 400);
      const secret = await getSecret('cred_fn_customer_api');
      let jd: any = null; let st = 0;
      try {
        const r = await fetch(`${SUPABASE_URL}/functions/v1/drawing_boq`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, mode: 'document', file_b64: b64, mime, filename: name, hint, ocr_text: String(body.ocr_text || '').slice(0, 200_000), ...drawingOcr(body) }) });
        st = r.status; jd = await r.json().catch(() => null);
      } catch (_e) { /* answered below as document_unreadable */ }
      // A DXF (ASCII or binary) too heavy for the edge is queued for the CAD worker like a DWG (22 Sep 2026).
      const cadWhy = /\.(dxf|dwg)$/i.test(name) ? cadQueueReason(st, jd) : null;
      if (cadWhy) {
        const p = await storeOriginal(cust.id, email, name, mime, b64, SAFE_DOCS);
        const job = p ? await queueCadRead({ customerId: cust.id, email, path: p, name, mime, b64Len: b64.length, why: cadWhy }) : null;
        if (job) return J({ ok: true, boq: null, kind: 'dxf', needs: 'cad_conversion', drawing_file_path: p, drawing_file_name: name, drawing_redacted_paths: [], stored: true, note: 'cad_queued', cad_job_id: job });
      }
      if (jd?.error === DRAWING_FORMAT_ERROR) return J(drawingFormatRefused(), 415);
      if (!jd?.ok) return J({ ok: false, error: String(jd?.error || 'document_unreadable'), detail: String(jd?.detail || '').slice(0, 200), message: clearerCopyAsk('customer', documentLocale(body.lang, cust.locale), name) });
      const path = await storeOriginal(cust.id, email, name, mime, b64, SAFE_DOCS);
      // A DXF's take-off carries the file's own names (layers, blocks, title block): cad_identity takes them
      // out before the customer's portal holds the BOQ it will send (22 Sep 2026). The CAD FILE is never
      // shared; since 24 Sep 2026 a DRAWING of it is, with its identity left out (redactCad), and when that
      // cannot be drawn the drawing is held and the customer is told so, as analyze_drawing does.
      const cad = /\.(dxf|dwg)$/i.test(name) || /dxf|dwg/i.test(mime);
      if (!cad) return J({ ok: true, boq: jd.boq, kind: jd.kind || null, needs: jd.needs || null, drawing_file_path: path, drawing_file_name: name, drawing_redacted_paths: [], stored: !!path });
      const red = path ? await redactCad({ secret, b64, custId: cust.id, email, path, seeds: seedTerms({ name: cust.full_name || '', email: cust.email || email, phone: cust.phone || '', extra: [name] }) }) : null;
      const hand = red ? drawingHandoff(red.meta, path, red.redacted) : { drawing_redacted_paths: [], drawing_held: false };
      if (red && hand.drawing_held && path) await recordHeld(heldRun({ customerId: cust.id, email, sourcePath: path, meta: red.meta, reason: String(red.reason) }));
      // Too dense to draw inside the edge's CPU cap (cad_render RENDER_MAX_SEGMENTS): the CAD worker draws it.
      const denseJob = red?.reason === 'cad_render_too_dense' && path ? await queueCadRead({ customerId: cust.id, email, path, name, mime, b64Len: b64.length, why: 'over_edge_ceiling' }) : null;
      return J({ ok: true, boq: jd.boq ? cadSupplierBoq(jd.boq, dxfTextOf(b64)) : jd.boq, kind: jd.kind || null, needs: jd.needs || null, drawing_file_path: path, drawing_file_name: name, stored: !!path, ...(red ? red.meta : {}), ...hand, ...(denseJob ? { note: 'cad_queued', cad_job_id: denseJob } : {}) });
    }

    if (action === 'analyze_drawing') {
      // ONE BUDGET FOR THE WHOLE ANALYSIS (it_engineer, 12 Nov 2026; ledger 1642; review of the effort fix): it answers inside
      // ANALYZE_DRAWING_BUDGET_MS, 10 s before the 150 s edge wall, so the customer reads our answer and never a killed
      // worker. drawing_boq keeps its own DRAWING_BUDGET_MS (115 s) inside it; the lengths call gets what is left, and one
      // that is cut there is read off the request path (the queue the 546 path already uses). The portal waits 150 s, longer.
      const analyzeAt = Date.now();
      let images: any[] = Array.isArray(body.images) ? body.images.slice(0, MAX_DRAWING_PAGES) : [];
      const name = String(body.drawing_file_name || 'drawing').slice(0, 180);
      const mime = String(body.mime || 'application/octet-stream');
      // Founder ruling 28 Sep 2026: a drawing is PDF or CAD (DWG/DXF) only (_shared/drawing_format.ts).
      { const refused = drawingFormatRefusal(name, mime); if (refused) return J(refused, 415); }
      const hint = String(body.hint || '').slice(0, 400);
      const path = body.original_b64 ? await storeOriginal(cust.id, email, name, mime, String(body.original_b64)) : null;
      const secret = await getSecret('cred_fn_customer_api');
      const isCad = /\.(dwg|dxf)$/i.test(name) || /dwg|dxf|autocad|acad/i.test(mime);
      // 24 Sep 2026: a CAD original is no longer sent to cad_convert (a paid CloudConvert raster the server could
      // not verify, so every such picture was held). It is DRAWN from its own entities, identity left out.
      const cadRed = !images.length && isCad && body.original_b64 && path
        ? await redactCad({ secret, b64: String(body.original_b64), custId: cust.id, email, path, seeds: seedTerms({ name: cust.full_name || '', email: cust.email || email, phone: cust.phone || '', extra: [name] }) })
        : null;
      const cadHand = cadRed ? drawingHandoff(cadRed.meta, path, cadRed.redacted) : { drawing_redacted_paths: [] as string[], drawing_held: !!path, share_redacted: false as const };
      if (cadRed && cadHand.drawing_held && path) await recordHeld(heldRun({ customerId: cust.id, email, sourcePath: path, meta: cadRed.meta, reason: String(cadRed.reason) }));
      // A drawing too dense to draw inside the edge's CPU cap (review of #967: 546 at ~400k segments) is drawn by
      // the CAD worker, like a DWG past the edge's ceiling; the customer's screen polls it (cad_queued).
      const denseJob = cadRed?.reason === 'cad_render_too_dense' && path
        ? await queueCadRead({ customerId: cust.id, email, path, name, mime, b64Len: String(body.original_b64).length, why: 'over_edge_ceiling' }) : null;
      const cadOut = { ...(cadRed ? cadRed.meta : {}), ...cadHand, ...cadNote(true, cadHand), ...budgetNote(cadRed?.reason === 'pixels_budget'), ...(denseJob ? { note: 'cad_queued' as const, cad_job_id: denseJob } : {}) };
      // WHY THE NOTE IS SPECIFIC NOW (11 Aug 2026). Spec #7 §3 names "a customer uploads a ZIP file
      // instead of a PDF" and "a PDF is corrupted" as two of its sixteen exception scenarios.
      // Measured before changing anything: neither crashed — both fell through to the single note
      // 'no_readable_pages', which is true and useless. The customer is told nothing they can act
      // on, and sending a ZIPPED DRAWING SET is normal practice in UAE construction, so this is the
      // likeliest of the sixteen to actually happen. The recovery strategy for both is the same and
      // it is not a retry: tell the person exactly what to send instead.
      const isArchive = /\.(zip|rar|7z|tar|tgz|gz)$/i.test(name)
        || /(^|[^a-z])(zip|rar|7z|x-7z|x-tar|gzip|compressed)([^a-z]|$)/i.test(mime);
      if (!images.length && isCad && body.original_b64) {
        // No picture of the sheet, so nothing a supplier can be shown - but the CAD file itself is still
        // read for its take-off (doc_read dwg / dxf). The drawing stays held for suppliers.
        let boq: unknown = null; let st = 0; let jd: any = null;
        try {
          const r = await fetch(`${SUPABASE_URL}/functions/v1/drawing_boq`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, mode: 'document', file_b64: body.original_b64, mime, filename: name, hint }) });
          st = r.status; jd = await r.json().catch(() => null); if (jd?.ok && jd.boq) boq = cadSupplierBoq(jd.boq, dxfTextOf(String(body.original_b64)));
        } catch (_e) { /* answered below with boq null */ }
        const why = cadQueueReason(st, jd);
        if (why && path) {
          const job = await queueCadRead({ customerId: cust.id, email, path, name, mime, b64Len: String(body.original_b64).length, why });
          if (job) return J({ ok: true, boq: null, drawing_file_path: path, drawing_file_name: name, ...cadOut, note: 'cad_queued', cad_job_id: job });
        }
        if (boq) return J({ ok: true, boq, drawing_file_path: path, drawing_file_name: name, ...cadOut });
      }
      if (!images.length) {
        const note = isCad ? 'cad_not_converted' : (isArchive ? 'archive_not_supported' : 'no_readable_pages');
        const advice = isCad
          ? 'We could not convert this CAD file. Please export it to PDF and upload that.'
          : (isArchive
            ? 'This is a compressed archive, so we cannot read the drawings inside it. Please extract it and upload the PDF or image files themselves — you can attach up to 10 pages.'
            : 'We could not read any pages from this file. It may be corrupted, password-protected, or saved in a format we cannot open. Please re-export it as a PDF or upload clear images of each page.');
        return J({ ok: true, boq: null, drawing_file_path: path, drawing_file_name: name,
                   drawing_redacted_paths: [], drawing_held: !!path, share_redacted: false, ...(isCad ? cadOut : {}), note, advice });
      }
      try {
        const redPrefix = `redacted/${crypto.randomUUID()}/page`;
        // REDACTION IS BATCHED (13 Aug 2026), because one call over a real drawing set does not
        // survive. MEASURED on staging with a genuine 6-sheet consultant mechanical set rasterised
        // exactly as the portal rasterises it: 1-4 pages return 200 (22.9s / 24.2s / 27.6s / 37.2s),
        // 5 pages return HTTP 546 WORKER_RESOURCE_LIMIT at 37.5s. imagescript decodes each page to
        // full-resolution RGBA before resizing to MAXW, so cost is per page and the isolate is
        // killed outright - which means drawing_redact's own recordRun never runs and NOTHING is
        // written. The customer saw a successful upload with zero redacted pages and no trace.
        // Four pages per call is the measured ceiling with a page in hand; the loop is sequential
        // so two batches never run concurrently against the same budget.
        // 22 SEP 2026 — ONE PAGE PER CALL. Since #794 the portal's pages are kept at 2600 px (a 36x24 sheet
        // readable to a supplier) and at that size four pages did not survive: on production an 8-sheet set
        // came back 546 WORKER_RESOURCE_LIMIT on both 4-page calls (12.0 s and 8.9 s), 8 of 8 pages lost,
        // the drawing held (scripts/e2e/drawing_reaches_suppliers.mjs). drawing_redact now also interprets
        // only its own pages of the original. Measured per page, see the PR: decode + paint + encode of a
        // 2600 px sheet plus that one page's text layer.
        const REDACT_BATCH = 1;
        // CUSTOMER-DRAWN REDACTION (website audit 14 Sep 2026). Under the model hold drawing_redact
        // verifies nothing, so a drawing never reached a supplier. The portal now lets the customer
        // box what must be hidden; drawing_redact applies those boxes deterministically. One entry
        // per page, normalised 0..1 {x,y,w,h}; anything malformed is dropped here, never forwarded.
        const c01 = (v: unknown) => { const n = Number(v); return Number.isFinite(n) ? Math.min(1, Math.max(0, n)) : 0; };
        let manualBoxes: { x: number; y: number; w: number; h: number }[][] | null = Array.isArray(body.manual_boxes)
          ? body.manual_boxes.slice(0, 10).map((pg: unknown) => Array.isArray(pg)
            ? pg.slice(0, 40).map((bx: any) => ({ x: c01(bx?.x), y: c01(bx?.y), w: c01(bx?.w), h: c01(bx?.h) })).filter((bx) => bx.w > 0 && bx.h > 0)
            : [])
          : null;
        // THE TITLE BLOCK, BOXED WITHOUT A MODEL, AND THE TRUST BOUNDARY (14 Sep 2026). A PDF drawing's
        // title block, revision table and every run carrying this customer's name / email / phone /
        // file name or a plot, Makani, address or permit pattern are boxed by the SERVER from the stored
        // original's own text positions. The customer's boxes come from their browser and prove nothing:
        // they are only ever added as extra cover (supplier_copy.supplierBoxes). When the server cannot
        // derive the boxes itself — any photo, scan or CAD raster (no text layer), a rotated page, a
        // title block it did not find, a residual it could not cover — no boxes are sent at all, and
        // drawing_redact holds every page. Fail closed.
        let serverBoxes: { x: number; y: number; w: number; h: number }[][] | null = null;
        // Words on the PDF's own text layer; 0 means a scan (see SCANNED PAGES below). -1: not a PDF / unread.
        let pdfWords = -1;
        if (/pdf/i.test(mime) && body.original_b64) {
          try {
            const bytes = Uint8Array.from(atob(String(body.original_b64).replace(/^data:[^;]+;base64,/, '')), (c) => c.charCodeAt(0));
            const pp = await pdfPages(bytes, undefined, { layers: false });
            pdfWords = pp.reduce((n, pg) => n + pg.runs.length, 0);
            const tb = titleBlockBoxes(pp, seedTerms({ name: cust.full_name || '', email: cust.email || email, phone: cust.phone || '', extra: [name] }));
            serverBoxes = supplierBoxes(tb, manualBoxes, images.length);
          } catch (_e) { serverBoxes = null; }
        }
        manualBoxes = serverBoxes;
        const redactBatch = async (slice: any[], from: number) => {
          const r = await fetch(`${SUPABASE_URL}/functions/v1/drawing_redact`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, images: slice, prefix: redPrefix, owner_customer_id: cust.id, owner_email: email, source_path: path, page_offset: from, original_b64: body.original_b64 || null, ...(manualBoxes ? { manual_boxes: manualBoxes.slice(from, from + slice.length) } : {}) }) });
          return await r.json();
        };
        // original_b64 lets drawing_boq read a PDF's own text layer with no model — the hold-proof path.
        // A CAD FILE IS READ, NOT PICTURED (22 Sep 2026, sales_engineer; founder instructions 31, 63, 64).
        // doc_read now opens a DWG (LibreDWG) and runs the DXF take-off, but the portal sends a .dwg here,
        // to analyze_drawing, and this call gave drawing_boq only the rasterised sheets: the reader had no
        // way in. The CAD original goes to drawing_boq's 'document' mode for the take-off; cad_convert's
        // pictures above are still what drawing_redact covers for suppliers.
        const boqBody = isCad && body.original_b64
          ? { __secret: secret, mode: 'document', file_b64: body.original_b64, mime, filename: name, hint }
          : { __secret: secret, hint, images, original_b64: body.original_b64 || null, mime, ocr_text: String(body.ocr_text || '').slice(0, 200_000), ...drawingOcr(body), ...scheduleTables(body) };
        const boqP = timedFetch(`${SUPABASE_URL}/functions/v1/drawing_boq`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify(boqBody) }, Math.max(5_000, analyzeAt + ANALYZE_DRAWING_BUDGET_MS - Date.now()));
        let redacted: string[] = []; const redJobs: string[] = []; let redIn = 0; let redOut = 0; let redDied = 0;
        // drawing_redact says needs_manual_boxes when its automatic detection could not run (no model
        // under the hold) — the portal opens the customer's box editor on exactly that signal.
        let needsManual = false;
        // A page held because the set is past what the model check may spend is said to the customer (budgetNote).
        let budgetHit = false;
        // Only pass paths back to the client once drawing_redact has RECORDED the run server-side
        // (drawing_redaction_runs). An unrecorded run cannot be verified at create_inquiry, so its
        // paths are unusable — dropping them here lands on the existing total-failure behaviour
        // (inquiry goes out with no drawing) instead of a confusing rejection later.
        for (let i = 0; i < images.length; i += REDACT_BATCH) {
          const slice = images.slice(i, i + REDACT_BATCH);
          try {
            const rj = await redactBatch(slice, i);
            const inN = Number(rj?.pages_in || 0);
            if (rj?.needs_manual_boxes === true) needsManual = true;
            if (rj?.customer_message) budgetHit = true;
            // A 546 answers JSON too - {code:'WORKER_RESOURCE_LIMIT'} with no pages_in - so an
            // isolate death is counted as pages LOST rather than as a batch that carried no pages.
            if (!inN && !rj?.ok) { redDied += slice.length; redIn += slice.length; continue; }
            redIn += inN; redOut += Number(rj?.pages_out || 0);
            if (rj?.ok && rj?.recorded && rj?.job_id && Array.isArray(rj.paths)) { redacted = redacted.concat(rj.paths.map((x: any) => String(x))); redJobs.push(String(rj.job_id)); }
          } catch (_e) { redDied += slice.length; redIn += slice.length; }
        }
        const boqRes = await Promise.allSettled([boqP]).then((a) => a[0]);
        // redaction_complete compared redOut >= redIn, and both are 0 when the redactor dies before
        // it can report anything - so total failure read as "complete". It now requires that pages
        // were sent AND that every one of them came back.
        const redMeta = { redaction_job_id: redJobs[0] || null, redaction_job_ids: redJobs, redaction_pages_in: redIn, redaction_pages_out: redOut, redaction_pages_lost: redDied, redaction_complete: redIn > 0 && redOut === redIn, needs_manual_boxes: false /* the customer's boxes no longer make a page shareable (trust boundary, 14 Sep 2026), so they are not asked for */, ...budgetNote(budgetHit) /* a budget hold is said (drawing_hold.budgetNote) */ };
        // THE HOLD IS DECIDED AND RECORDED HERE (audit 21 Sep 2026, finding 9; ./drawing_hold.ts).
        // Anything short of every page verified hands back NO redacted paths and share_redacted:false,
        // and writes one 'held' row against the stored original so the unshared drawing is visible.
        // A fully redacted PDF also goes out as the anonymised VECTOR PDF (redactFile), beside its page previews.
        let fileHeld: string | null = null;
        if (redMeta.redaction_complete && path && !isCad && body.original_b64 && /^JVBERi0/.test(String(body.original_b64).replace(/^data:[^;]+;base64,/, ''))) {
          const f = await redactFile({ secret, b64: String(body.original_b64), custId: cust.id, email, path, seeds: seedTerms({ name: cust.full_name || '', email: cust.email || email, phone: cust.phone || '', extra: [name] }) });
          if (f && 'path' in f) { redacted.push(f.path); redJobs.push(f.job); }
          else if (f && 'held' in f) fileHeld = f.held;
        }
        const hand = drawingHandoff(redMeta, path, redacted);
        if (hand.drawing_held && path) {
          const reason = serverBoxes ? 'server_boxes_sent_pages_refused' : (needsManual ? 'no_server_boxes_and_model_refused' : (redDied ? 'redactor_died' : 'pages_not_verified'));
          await recordHeld(heldRun({ customerId: cust.id, email, sourcePath: path, meta: redMeta, reason }));
        }
        // SCANNED PAGES ARE READ BY OCR OFF THE REQUEST PATH (24 Sep 2026, sales_engineer; founder instruction 579:
        // "OCR for scanned drawings"). A photo or a PDF with no text layer gives the server no words to box, so the
        // edge holds it, and until today it stayed held for ever. Its page rasters (what a supplier would see) are
        // stored like any original, and the CAD worker OCRs, boxes, re-reads and publishes them only when clean
        // (_shared/scan_redact.ts). If the store or the queue fails, the drawing simply stays held.
        let scanJob: string | null = null;
        if (hand.drawing_held && path && !isCad && images.length && (/^image\//i.test(mime) || pdfWords === 0)) {
          const pagePaths: string[] = [];
          for (let i = 0; i < images.length; i++) {
            const im = images[i];
            const b64 = String((im && (im.b64 || im.data)) || im || '');
            const pth = b64 ? await storeOriginal(cust.id, email, `scan_page_${i + 1}.jpg`, 'image/jpeg', b64, SAFE_UPLOAD) : null;
            if (!pth) { pagePaths.length = 0; break; }
            pagePaths.push(pth);
          }
          if (pagePaths.length === images.length) scanJob = await queueCadRead({ customerId: cust.id, email, path, name, mime, b64Len: String(body.original_b64 || '').length, why: 'scan_needs_ocr', boqIn: { scan_pages: pagePaths } });
        }
        const scanNote = scanJob ? { note: 'scan_queued', cad_job_id: scanJob } : {};
        // pdf_words (10 Nov 2026): the composer reads a PDF in the browser by OCR ONLY when this says it has no text layer (0).
        // It used to OCR any PDF that came back without lines - including one whose read it had itself cut off at 30 s.
        if (boqRes.status !== 'fulfilled') return J({ ok: false, error: 'analysis_exception', detail: 'boq_fetch_failed', drawing_file_path: path, drawing_file_name: name, pdf_words: pdfWords, ...redMeta, ...hand }, 200);
        const jd = await boqRes.value.json().catch(() => null);
        // A CAD original the edge could not read (past its ceiling, or its worker died) is read off the
        // request path; the pictured sheets above still went through redaction for suppliers.
        const cadWhy = isCad && body.original_b64 ? cadQueueReason(boqRes.value.status, jd) : null;
        if (cadWhy && path) {
          const job = await queueCadRead({ customerId: cust.id, email, path, name, mime, b64Len: String(body.original_b64).length, why: cadWhy });
          if (job) return J({ ok: true, boq: null, drawing_file_path: path, drawing_file_name: name, ...redMeta, ...hand, note: 'cad_queued', cad_job_id: job });
        }
        // A REFUSAL IS A REFUSAL, WITH A STATUS (audit CP-03 / CP-10). This answered HTTP 200 with
        // ok:false and an English code, so every log, probe and proxy read it as a success.
        if (!jd?.ok) return J({ ok: false, error: 'analysis_failed', code: 'analysis_failed', message: 'We could not read that drawing. Your file is saved — please describe the job in your own words and we will carry on.', message_ar: 'تعذّر علينا قراءة هذا المخطط. ملفك محفوظ — يُرجى وصف العمل بكلماتك ونكمل معك.', detail: jd?.detail || jd?.error || '', drawing_file_path: path, drawing_file_name: name, pdf_words: pdfWords, ...redMeta, ...hand }, 502);
        // THE CONFIRM STEP RUNS ONLY NOW, after redaction has finished and every page came back
        // (review of #642: it used to run in parallel and could see the original page). drawing_boq
        // re-reads the run by id and uses its recorded redacted page, or marks the lines unconfirmed.
        // A CAD take-off loses the file's own names here (cad_identity, 22 Sep 2026); a PDF's is gated below.
        const boqOut = isCad && jd.boq ? cadSupplierBoq(jd.boq, dxfTextOf(String(body.original_b64 || ''))) : jd.boq;
        let lengthsJob: string | null = null;
        // THE LENGTHS (22 Sep 2026): a drawing set read from a PDF gets its duct and pipe lengths from a SECOND
        // drawing_boq call that reads the CAD layers (drawing_set.ts, "THE LENGTHS ARE A SECOND CALL"). If it
        // fails or is killed, boqOut stands with its counted lines, and the customer is told why no lengths.
        if (boqOut && boqOut.method === 'drawing_set' && /pdf/i.test(mime) && body.original_b64) {
          try {
            const lengthsLeft = analyzeAt + ANALYZE_DRAWING_BUDGET_MS - Date.now();
            const lr = lengthsLeft < 3_000 ? null : await timedFetch(`${SUPABASE_URL}/functions/v1/drawing_boq`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, mode: 'lengths', boq: boqOut, original_b64: body.original_b64 }) }, lengthsLeft).catch(() => null);
            const lj = lr ? await lr.json().catch(() => null) : null;
            // A big set's lengths killed the edge worker (measured 22 Sep 2026: 546 at 40 synthetic sheets,
            // 200 at 20), or did not finish inside the analysis budget (queued under the same reason: the table's check
            // allows no other), the counted take-off goes back now, and the CAD worker merges the lengths in.
            if ((!lr || lr.status === 546) && path && Array.isArray(boqOut.boq)) {
              const job = await queueCadRead({ customerId: cust.id, email, path, name, mime, b64Len: String(body.original_b64).length, why: 'pdf_lengths_worker_died', boqIn: boqOut });
              if (job) { lengthsJob = job; boqOut.missing_info = [LENGTHS_QUEUED_NOTE, ...(Array.isArray(boqOut.missing_info) ? boqOut.missing_info : [])]; }
            }
            if (lj?.ok && lj.boq && Array.isArray(lj.boq.boq)) Object.assign(boqOut, lj.boq);
            else if (!lengthsJob && Array.isArray(boqOut.boq) && boqOut.boq.some((l: any) => /^(duct|pipe):/.test(String(l?.type || '')) && l?.qty == null)) boqOut.missing_info = [LENGTHS_FAILED_NOTE, ...(Array.isArray(boqOut.missing_info) ? boqOut.missing_info : [])];
          } catch (_e) { /* the counted take-off stands */ }
        }
        // THE VISION COUNT FOR A PHOTO OR A SCAN (27 Oct 2026, ledger 580; ./vision_count_wire.ts says what was measured).
        // Its page is redacted later, by the CAD worker's OCR (scanJob above): this edge holds every photo and scan page.
        // So the legend's count request rides on that job, and cad_read_status runs it once the worker's run is recorded.
        if (scanJob && boqOut && isPhotoOrScan(mime, pdfWords, isCad)) {
          const vcBody = visionCountBody(boqOut.boq);
          if (vcBody) {
            const { data: jr } = await admin.from('cad_read_jobs').select('boq_in').eq('id', scanJob).maybeSingle();
            await admin.from('cad_read_jobs').update({ boq_in: { ...((jr?.boq_in as Record<string, unknown>) || {}), vision_count: vcBody, vision_lines: boqOut.boq } }).eq('id', scanJob);
          }
        }
        if (boqOut && Array.isArray(boqOut.boq) && boqOut.boq.length) {
          try {
            const cr = await fetch(`${SUPABASE_URL}/functions/v1/drawing_boq`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${SERVICE}` }, body: JSON.stringify({ __secret: secret, mode: 'confirm', boq: boqOut.boq, author_model: typeof boqOut.author_model === 'string' ? boqOut.author_model : 'unknown', redaction_job_id: redMeta.redaction_complete ? redJobs[0] : null }) });
            const cj = await cr.json();
            if (cj?.ok && Array.isArray(cj.boq)) { boqOut.boq = cj.boq; boqOut.confirm = cj.confirm; if (cj.confirm_detail) boqOut.confirm_detail = cj.confirm_detail; }
          } catch (_e) { /* the coded result stands */ }
        }
        return J({ ok: true, boq: boqOut, drawing_file_path: path, drawing_file_name: name, pdf_words: pdfWords, ...redMeta, ...hand, ...cadNote(isCad && !!body.original_b64, hand), ...fileHeldNote(fileHeld), ...scanNote, ...(lengthsJob ? { note: 'lengths_queued', cad_job_id: lengthsJob } : {}) });
      } catch (e) { return J({ ok: false, error: 'analysis_exception', detail: String((e as Error)?.message || e), drawing_file_path: path, drawing_file_name: name, drawing_redacted_paths: [], drawing_held: !!path, share_redacted: false }, 200); }
    }
}
