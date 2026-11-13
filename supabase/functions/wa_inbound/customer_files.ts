// customer_files.ts - A REGISTERED CUSTOMER'S FILE ON WHATSAPP REACHES THEIR REQUEST (it_engineer, 10 Nov 2026; channels audit R2,
// HIGH). Seat: customer_support (WhatsApp) for the conversation; the drawing path it reuses is the portal's (sales_engineer's).
//
// Measured on main: media_in.ts sent every file from a number with no SUPPLIER lead down the "number with no account" branch, so
// a signed-in customer's photo or drawing was read under a stranger's daily cap, filed against nothing, and answered as if they
// had no account; a DWG or DXF was refused outright (the sanitizer allowed PDF and images only). Now, for a number whose
// confirmed owner is a customer (fn_whatsapp_owner):
//   1. the file is downloaded (host pinned, media.ts, its 12 MB edge ceiling), sniffed against SAFE_UPLOAD + SAFE_CAD (a DWG or
//      DXF is accepted by its own magic, whatever the sender declared) and stored where the portal stores a drawing
//      (drawing-files, drawings/<customer>/...);
//   2. it is attached to the customer's NEWEST OPEN REQUEST (inquiries, not closed: _shared/request_closed.ts), else their open
//      intake (inquiry_intake), else a new intake is started for it; a documents row names it against that record, so it is
//      in the customer's vault (fn_customer_document_refs) like a chat attachment;
//   3. a drawing (PDF, DWG, DXF) goes the portal's way: drawing_boq reads the take-off ('document' mode for CAD, the PDF's own
//      text layer otherwise), drawing_redact mode 'cad' draws a CAD sheet with the identity left out, a CAD file too big for
//      the edge is queued for the CAD reader (cad_read_jobs), and a request with no drawing gets this one as its drawing. A
//      drawing suppliers could be shown only once redacted stays HELD (drawing_redacted_paths empty) until it is.
// The customer is told, in their own language, by the model (rulings 1195-1197), what was received and where it went.
// NEEDS app_secrets.cred_fn_wa_drawings (scripts/sql/a_customers_whatsapp_drawing_is_read_like_a_portal_upload.sql, not
// applied): until it exists, drawing_boq and drawing_redact refuse the call, the file is still stored and attached, and the
// drawing stays held for suppliers.
// prevented by: wa_inbound/a_customers_file_reaches_their_request.test.ts
import { SAFE_CAD, SAFE_UPLOAD } from '../_shared/attachment.ts';
import { sanitizeAndScan } from '../_shared/malware.ts';
import { isClosedRequest } from '../_shared/request_closed.ts';
import { seedTerms } from '../_shared/anonymise.ts';
import { cadSupplierBoq, dxfTextOf } from '../_shared/cad_identity.ts';
import { inDbRegion } from '../_shared/db_region.ts';
import { admin, sec } from './shared.ts';
import { fetchTwilioMedia } from './media.ts';

export type CustomerFileResult = { ok: boolean; kind?: 'drawing' | 'cad' | 'photo'; target?: string; note: string; boqLines?: number; queued?: boolean; held?: boolean };

const SUPA = () => Deno.env.get('SUPABASE_URL')!;
const b64 = (u8: Uint8Array) => { let s = ''; for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, Array.from(u8.subarray(i, i + 0x8000))); return btoa(s); };
const EXT: Record<string, string> = { 'application/pdf': 'pdf', 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/vnd.dwg': 'dwg', 'image/vnd.dxf': 'dxf' };

/** The customer behind a WhatsApp number, or null (the number's confirmed owner, fn_whatsapp_owner). */
export async function customerOf(from: string): Promise<{ id: string; email: string; name: string; phone: string } | null> {
  try {
    const { data } = await admin.rpc('fn_whatsapp_owner', { p_phone: from });
    const o = (Array.isArray(data) ? data[0] : data) as { party_kind?: string; customer_id?: string | null } | null;
    if (o?.party_kind !== 'customer' || !o.customer_id) return null;
    const { data: c } = await admin.from('customers').select('id,email,full_name,phone').eq('id', o.customer_id).maybeSingle();
    return { id: String(o.customer_id), email: String(c?.email || ''), name: String(c?.full_name || ''), phone: String(c?.phone || from.replace(/^whatsapp:/, '')) };
  } catch (_e) { return null; }
}

/** Where a file from this customer belongs: their newest open request, else their open intake, else a new intake. */
export async function targetOf(cust: { id: string; email: string }, caption: string): Promise<{ table: 'inquiries' | 'inquiry_intake'; id: string; hasDrawing: boolean; ref: string } | null> {
  const { data: inq } = await admin.from('inquiries').select('id,status,drawing_file_path').eq('customer_id', cust.id).order('created_at', { ascending: false }).limit(10);
  const open = ((inq || []) as { id: string; status: string; drawing_file_path: string | null }[]).find((r) => !isClosedRequest(r.status));
  if (open) return { table: 'inquiries', id: String(open.id), hasDrawing: !!open.drawing_file_path, ref: 'their open request' };
  const { data: it } = await admin.from('inquiry_intake').select('id,status').eq('customer_id', cust.id).in('status', ['needs_info', 'ready']).order('updated_at', { ascending: false }).limit(1);
  const intake = ((it || []) as { id: string }[])[0];
  if (intake) return { table: 'inquiry_intake', id: String(intake.id), hasDrawing: false, ref: 'the request they are preparing' };
  const { data: made } = await admin.from('inquiry_intake').insert({ customer_id: cust.id, email: cust.email || null, status: 'needs_info',
    raw_input: caption.slice(0, 2000) || null, turns: [] }).select('id').maybeSingle();
  return made?.id ? { table: 'inquiry_intake', id: String(made.id), hasDrawing: false, ref: 'a new request started for this file' } : null;
}

/** Store, attach and (for a drawing) read one file. Never throws: every failure is a plain note for the reply. */
export async function customerFile(cust: { id: string; email: string; name: string; phone: string }, target: NonNullable<Awaited<ReturnType<typeof targetOf>>>,
                                   m: { url: string; mime: string }, n: number, allowInline: boolean): Promise<CustomerFileResult> {
  const got = await fetchTwilioMedia(m.url, allowInline);
  if (!got.bytes) return { ok: false, note: /larger than/.test(got.err || '') ? 'it is larger than the 12 MB WhatsApp can hand us; it can be uploaded on the request page instead' : 'it could not be downloaded from WhatsApp' };
  const sc = await sanitizeAndScan({ input: got.bytes, declaredMime: got.mime || m.mime || 'application/octet-stream', filename: 'whatsapp-file-' + n,
    allow: [...SAFE_UPLOAD, ...SAFE_CAD], maxBytes: 12 * 1024 * 1024,
    scan: { source: 'wa_inbound.customer_file', subject: cust.id, filename: 'whatsapp-file-' + n, bucket: 'drawing-files' } });
  if (!sc.ok) return { ok: false, note: sc.body.error === 'malware_detected' ? 'it was refused by our malware scanner' : 'that file type cannot be accepted (a PDF, a photo, or a DWG/DXF drawing can)' };
  const mime = sc.result.mime; const bytes = sc.result.bytes;
  const kind: CustomerFileResult['kind'] = /dwg|dxf/.test(mime) ? 'cad' : mime === 'application/pdf' ? 'drawing' : 'photo';
  const name = 'whatsapp-' + Date.now() + '-' + n + '.' + (EXT[mime] || 'bin');
  const path = `drawings/${cust.id}/${Date.now()}_${name}`;
  const up = await admin.storage.from('drawing-files').upload(path, bytes, { contentType: mime, upsert: false });
  if ((up as { error?: unknown }).error) return { ok: false, note: 'it could not be stored' };
  try {
    await admin.from('documents').insert({ bucket: 'drawing-files', path, file_name: name, kind: kind === 'photo' ? 'whatsapp_photo' : 'whatsapp_drawing',
      ref_table: target.table, ref_id: target.id, mime, status: 'received' });
  } catch (_e) { /* the file is stored; the vault row is best effort, as for a chat attachment (messages_api) */ }
  // A PHOTO is kept with the request for the customer and our team; it is NOT offered to suppliers (13 Nov 2026, review
  // item 13: the customer was never told). The reply says so, and how to share a drawing instead.
  if (kind === 'photo') return { ok: true, kind, target: target.ref, held: true, note: 'a photo, added to ' + target.ref + '; photos are kept with the request and are not sent to suppliers - a drawing can be shared as a PDF or a CAD file (DWG/DXF)' };

  // A DRAWING GOES THE PORTAL'S WAY (customer_api analyze_drawing): read for the take-off, redacted before any supplier sees it.
  const secret = await sec('cred_fn_wa_drawings');
  const fileB64 = b64(bytes);
  let boqLines: number | undefined; let queued = false; let redacted: string[] = [];
  try {
    const r = await fetch(inDbRegion(SUPA() + '/functions/v1/drawing_boq'), { method: 'POST', headers: { 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(60_000),
      body: JSON.stringify(kind === 'cad' ? { __secret: secret, mode: 'document', file_b64: fileB64, mime, filename: name }
        : { __secret: secret, images: [], original_b64: fileB64, mime, ocr_text: '' }) });
    const jd = await r.json().catch(() => null);
    if (jd?.ok && jd.boq) {
      const boq = kind === 'cad' ? cadSupplierBoq(jd.boq, dxfTextOf(fileB64)) : jd.boq;
      boqLines = Array.isArray((boq as { boq?: unknown[] })?.boq) ? (boq as { boq: unknown[] }).boq.length : undefined;
    }
    // too big or too dense for the edge: the CAD reader takes it (cad_read_jobs, the portal's queue)
    if (kind === 'cad' && ((jd?.ok && jd.kind === 'dwg' && jd.needs === 'cad_conversion') || r.status === 546 || r.status >= 500)) {
      const { data: job } = await admin.from('cad_read_jobs').insert({ customer_id: cust.id, owner_email: cust.email, source_path: path, file_name: name, mime,
        bytes: bytes.byteLength, why: r.status === 546 ? 'edge_worker_died' : r.status >= 500 ? 'edge_reader_failed' : 'over_edge_ceiling' }).select('id').maybeSingle();
      queued = !!job?.id;
    }
  } catch (_e) { /* the file is stored and attached; the take-off is read when it can be */ }
  // THE SAME REDACTION AND THE SAME ALL-OR-NOTHING GATE AS THE PORTAL (13 Nov 2026, sales_engineer; anonymity audit B
  // finding I3). Before, only a CAD file was redacted here (its preview); a PDF wrote nothing it had proved and the
  // request carried no drawing, and nothing said why. Now every drawing goes through drawing_redact, and a path reaches
  // drawing_redacted_paths only from a RECORDED run that returned exactly the one page or file asked for:
  //   * CAD: the preview (mode 'cad') decides; the anonymised DXF (mode 'file') rides with it only when its own verifier
  //     proved it (customer_api lib/drawings.redactCad, the same order);
  //   * PDF: the anonymised vector PDF (mode 'file': every identifying run cut, key plans and pictures cut, metadata gone,
  //     re-read and proved). The portal's JPEG preview needs the browser's raster, which a WhatsApp file does not come
  //     with; a PDF the file route holds (a scan, a sheet it cannot prove) attaches NOTHING and stays held.
  // A held drawing is said in the reply (held: true) and suppliers are shown no page of it.
  const seeds = seedTerms({ name: cust.name, email: cust.email, phone: cust.phone, extra: [name] });
  // The CAD preview's string reading rides to the file (read once, second review item 8); a set past its model budget is
  // said in plain words (overBudget).
  let reading: unknown = null, overBudget = false;
  const redactOne = async (mode: 'cad' | 'file'): Promise<string | null> => {
    try {
      const r = await fetch(inDbRegion(SUPA() + '/functions/v1/drawing_redact'), { method: 'POST', headers: { 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(150_000),
        body: JSON.stringify({ __secret: secret, mode, original_b64: fileB64, seed_terms: seeds, prefix: 'redacted', owner_customer_id: cust.id, owner_email: cust.email, source_path: path, ...(mode === 'file' && reading ? { strings_reading: reading } : {}) }) });
      const rj = await r.json().catch(() => null);
      if (rj?.strings_reading) reading = rj.strings_reading;
      if (rj?.customer_message || rj?.held_reason === 'pixels_budget') overBudget = true;
      return rj?.ok && rj.recorded && rj.job_id && Array.isArray(rj.paths) && rj.paths.length === 1 && rj.redaction_complete !== false ? String(rj.paths[0]) : null;
    } catch (_e) { return null; }
  };
  if (kind === 'cad') {
    const preview = await redactOne('cad');
    if (preview) { redacted = [preview]; const file = await redactOne('file'); if (file) redacted.push(file); }
  } else {
    const file = await redactOne('file');
    if (file) redacted = [file];
  }
  // the request's drawing, when it has none: suppliers are shown it only through verified redacted pages (held otherwise)
  if (target.table === 'inquiries' && !target.hasDrawing) {
    try {
      await admin.from('inquiries').update({ drawing_file_path: path, drawing_file_name: name, drawing_redacted_paths: redacted.length ? redacted : null })
        .eq('id', target.id).is('drawing_file_path', null);
      target.hasDrawing = true;
    } catch (_e) { /* the documents row still names it against the request */ }
  }
  return { ok: true, kind, target: target.ref, boqLines, queued, held: !redacted.length,
           // THE REPLY IS TRUE (13 Nov 2026, review item 13): `held` used to be returned and never read, so a held drawing
           // was described as shown to suppliers with the details removed. A held drawing is said to be held, with what
           // to send instead; a scanned PDF (no text to cut) and a PDF whose released copy still needs its page check,
           // which only the request page can run, are held here.
           note: (kind === 'cad' ? 'a CAD drawing' : 'a drawing') + ', added to ' + target.ref
             + (boqLines ? '; ' + boqLines + ' take-off lines were read from it' : queued ? '; it is large, so it is being read by our drawing reader' : '; its take-off is read next')
             + (redacted.length ? '; suppliers are shown it only with the customer\'s details removed'
               : overBudget ? '; it is NOT shown to suppliers yet: there are too many large sheets to check today - the customer can send only the sheets suppliers need, or try again tomorrow'
               : '; it is NOT shown to suppliers yet, because it could not be cleared of every detail that identifies the customer here - uploading it on the request page (where the customer checks the pages first), or sending the CAD file (DWG/DXF) or a vector PDF instead of a scan, lets it be shared') };
}
