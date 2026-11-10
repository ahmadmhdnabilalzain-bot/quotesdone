// media.ts - MEDIA IN (v16): download one WhatsApp attachment from Twilio (host pinned) and store, read and apply it to a
// supplier's lead. Moved out of index.ts unchanged (9 Nov 2026, customer_support).
import { admin, sec } from './shared.ts';
import { inDbRegion } from '../_shared/db_region.ts';
import { SAFE_UPLOAD } from '../_shared/attachment.ts';
// MALWARE WATCH, 9 Sep 2026 — see _shared/malware.ts. WhatsApp media arrives from any number that
// can reach the API line, which makes it the least-authenticated file entry in the estate.
import { sanitizeAndScan } from '../_shared/malware.ts';
import { licenceNameFromModel } from '../_shared/document_expiry.ts';
import { type LeadWriter, updateLeadSettingAsideClashingLicence } from '../_shared/duplicate_company.ts';

// ---- MEDIA IN (v16) --------------------------------------------------------------------------
function b64(u8: Uint8Array): string {
  let bin = ''; const c = 0x8000;
  for (let i = 0; i < u8.length; i += c) bin += String.fromCharCode.apply(null, Array.from(u8.subarray(i, i + c)));
  return btoa(bin);
}

// Twilio's MediaUrl needs Basic auth and then 307s to a pre-signed S3 URL. Deno's fetch drops the
// Authorization header on a cross-origin redirect, which is exactly right here: the redirect target
// carries its own signature and must not also receive our API key.
//
// THE HOST IS PINNED, AND THAT IS THE POINT. MediaUrl0 arrives inside the request body. Provenance
// or an HMAC signature proves the body came from Twilio, but this function ALSO has an
// authenticated JSON path, and "fetch whatever URL the payload names" is a server-side request
// forgery primitive one bug away either way — an attacker-chosen MediaUrl aimed at an internal
// address would be fetched with our own network position. Only api.twilio.com is fetched.
//
// `allowInline` permits a data: URL, and ONLY the authenticated internal path sets it. That path
// already requires the ops.wa_replay credential and exists to replay a message through the real
// code; a data: URL carries its own bytes, names no host and reaches no network, so it is the one
// safe way to exercise this leg where no Twilio media exists to replay. The Twilio webhook path
// cannot reach it.
export async function fetchTwilioMedia(url: string, allowInline: boolean):
    Promise<{ bytes: Uint8Array | null; mime: string; err?: string }> {
  const isInline = /^data:/i.test(url);
  if (isInline && !allowInline) return { bytes: null, mime: '', err: 'inline media is only accepted from an authenticated internal caller' };
  if (!isInline) {
    let host = '';
    try { host = new URL(url).hostname.toLowerCase(); } catch (_e) { /* malformed */ }
    if (host !== 'api.twilio.com') return { bytes: null, mime: '', err: 'media URL is not on api.twilio.com and was not fetched' };
  }
  const kSid = isInline ? '' : (await sec('twilio_api_key_sid') || '');
  const kSec = isInline ? '' : (await sec('twilio_api_key_secret') || '');
  if (!isInline && (!kSid || !kSec)) return { bytes: null, mime: '', err: 'twilio credentials not configured' };
  try {
    const ctrl = new AbortController(); const tt = setTimeout(() => ctrl.abort(), 20000);
    const r = await fetch(url, {
      headers: isInline ? {} : { 'Authorization': 'Basic ' + btoa(kSid + ':' + kSec) },
      signal: ctrl.signal,
    });
    clearTimeout(tt);
    if (!r.ok) return { bytes: null, mime: '', err: 'twilio media fetch HTTP ' + r.status };
    const buf = new Uint8Array(await r.arrayBuffer());
    // 12 MB ceiling: WhatsApp caps documents at 16 MB and base64 inflates by a third, so anything
    // larger cannot be handed to the extractor as a data URL anyway. Refuse loudly, not silently.
    if (buf.byteLength > 12 * 1024 * 1024) return { bytes: null, mime: '', err: 'file is larger than 12 MB' };
    return { bytes: buf, mime: r.headers.get('content-type') || '' };
  } catch (e) { return { bytes: null, mime: '', err: String((e as Error)?.message || e).slice(0, 160) }; }
}

/** The caption words fn_wa_attach_document files as a licence; the CAPTION never decides that here, the reader does. */
const CAPTION_SAYS_LICENCE = /(trade|licence|license|رخصة|رخصه)/i;

/** Read as a UAE trade licence WITH CONFIDENCE: a named, readable, medium/high read that found the licence number.
 *  Anything less (a product photo, a blank page, an Arabic-only 'low' read, an extraction that failed) is not a licence
 *  reading and never touches the licence record. Exported for wa_inbound/a_supplier_file_is_a_licence_only_when_read_as_one.test.ts. */
// deno-lint-ignore no-explicit-any
export function isConfidentLicence(doc: any): boolean {
  return !!doc && doc.unreadable !== true && ['medium', 'high'].includes(String(doc.confidence))
    && /[\p{L}\p{N}]{2}/u.test(String(doc.license_number || ''));
}

export type SupplierDocOutcome = {
  ok: boolean; applied: string[]; note: string;
  /** 'licence' = applied to the licence record; 'pending' = kept as a pending document for a person; undefined = not stored */
  filed?: 'licence' | 'pending';
  /** what fn_wa_attach_document did with a pending file (classified_as, attached) */
  intake?: { classified_as?: string; attached?: boolean; intake_id?: number } | null;
  /** what the reader saw, in plain words, for the reply */
  seen?: string;
};

// Store and read one attachment from a supplier's lead, and APPLY it to the licence record ONLY when the reader read a
// trade licence with confidence. Same sequence resend_inbound uses for an emailed licence — sanitize, upload, extract,
// update, file a doc_reviews row — so a supplier gets the same outcome whichever way they send it.
//
// R1 OF THE CHANNELS AUDIT (it_engineer, 10 Nov 2026; supplier registration is the founder's priority 1). This used to
// file ANY image or PDF a supplier lead sent as their trade licence: it replaced license_doc_path and cleared the licence
// number, authority, expiry and licensed name whatever the reader made of the file, so a product photo sent on WhatsApp
// (reproduced in the audit) took a registered supplier's verified licence off their record. On WhatsApp, unlike the
// portal's licence slot or a licence emailed in reply to our ask, nothing says the file IS a licence. Now:
//   - read as a licence with confidence (isConfidentLicence) -> applied exactly as the portal and the email doors apply
//     a licence (ledger 1442: what the old licence printed never judges a new one);
//   - anything else -> stored, handed to fn_wa_attach_document (wa_document_intake: it attaches a profile or signed terms
//     the caption names and keeps the rest as unknown), filed in doc_reviews as PENDING for a person, and the licence
//     fields are never written. The supplier is told what was received and that their record did not change.
// prevented by: wa_inbound/a_supplier_file_is_a_licence_only_when_read_as_one.test.ts
export async function handleSupplierDoc(leadId: number, url: string, declaredMime: string, fromPhone: string, allowInline: boolean,
                                        caption = ''): Promise<SupplierDocOutcome> {
  const got = await fetchTwilioMedia(url, allowInline);
  // The download error names hosts, credentials and HTTP codes, and this note is quoted to the supplier
  // (22 Sep 2026): the real reason goes to the function log, the supplier gets a plain sentence.
  if (!got.bytes) {
    console.error('wa_inbound media download failed:', got.err || 'no bytes');
    return { ok: false, applied: [], note: 'the file could not be downloaded from WhatsApp — please send it again' };
  }

  const mime = got.mime || declaredMime || 'application/octet-stream';
  const ext = /pdf/i.test(mime) ? 'pdf' : /png/i.test(mime) ? 'png' : /jpe?g/i.test(mime) ? 'jpg' : 'bin';
  // A neutral name: the file is not called a licence before it has been read as one (fn_wa_attach_document also reads
  // the storage path for its keywords, and "licence" in the name would file it as one).
  const fname = 'whatsapp-file-' + Date.now() + '.' + ext;

  // The mime came from a header a sender controls. Sniff the bytes, refuse anything that is not a
  // PDF or a real image, and strip EXIF/GPS off a photographed document before it is stored.
  const sc = await sanitizeAndScan({ input: got.bytes, declaredMime: mime, filename: fname, allow: SAFE_UPLOAD,
                                     scan: { source: 'wa_inbound.supplier_doc', subject: fromPhone, filename: fname, bucket: 'supplier-docs' } });
  if (!sc.ok) return { ok: false, applied: [], note: sc.body.error === 'malware_detected'
    ? 'that file was refused by our malware scanner — please check it and send a clean copy'
    : 'that file type is not accepted — please send a PDF or a photo' };
  const san = sc.result;

  const path = 'inbound/' + leadId + '/' + Date.now() + '_' + fname;
  const up = await admin.storage.from('supplier-docs').upload(path, san.bytes, { contentType: san.mime, upsert: true });
  if (up && (up as { error?: unknown }).error) return { ok: false, applied: [], note: 'the file could not be stored' };

  const docSecret = await sec('cred_fn_wa_docs');
  // deno-lint-ignore no-explicit-any
  let doc: any = null;
  if (docSecret) {
    try {
      const isImg = /^image\//.test(san.mime);
      const payload = isImg
        ? { __secret: docSecret, mode: 'license', images: [{ b64: b64(san.bytes), mime: san.mime }] }
        : { __secret: docSecret, mode: 'license', file_b64: b64(san.bytes), mime: san.mime, filename: fname };
      // in the database's region, not the caller's (_shared/db_region.ts): license_extract measured us-east-1 p50 13.6 s, ap-southeast-1 6.3 s
      const r = await fetch(inDbRegion(Deno.env.get('SUPABASE_URL')! + '/functions/v1/license_extract'), {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload), signal: AbortSignal.timeout(90000),
      });
      const j = await r.json().catch(() => null);
      if (j?.ok && j.doc) doc = j.doc;
    } catch (_e) { /* the file is stored either way; say so rather than claiming it was read */ }
  }

  const subject = 'WhatsApp from ' + fromPhone.replace('whatsapp:', '');

  if (!isConfidentLicence(doc)) {
    // NOT A LICENCE READING: kept, never filed as the licence. A caption naming a licence is not taken at its word
    // (the reader did not see one); any other caption is passed on, so "company profile" still files a profile.
    const intakeCaption = caption && !CAPTION_SAYS_LICENCE.test(caption) ? caption.slice(0, 300) : null;
    let intake: SupplierDocOutcome['intake'] = null;
    try {
      const { data, error } = await admin.rpc('fn_wa_attach_document', { p_phone: fromPhone, p_storage_path: path, p_caption: intakeCaption,
                                                                         p_media_kind: san.mime, p_turn_id: null });
      if (!error && data) intake = data as SupplierDocOutcome['intake'];
    } catch (_e) { /* the doc_reviews row below still records the file for a person */ }
    const readLicenceLow = !!doc && doc.unreadable !== true;   // a licence-like read too weak to apply
    const seen = readLicenceLow ? 'it looks like a licence but could not be read confidently'
      : /^image\//.test(san.mime) ? 'a photo that did not read as a trade licence' : 'a document that did not read as a trade licence';
    try {
      await admin.from('doc_reviews').insert({
        lead_id: leadId, from_email: null, subject, file_name: fname, file_path: path, mime: san.mime,
        ai_relevant: readLicenceLow, ai_category: readLicenceLow ? 'trade_license_unconfirmed' : 'unknown',
        ai_summary: 'stored from WhatsApp, NOT applied to the licence record: ' + seen
          + (intake?.classified_as && intake.classified_as !== 'unknown' ? '; caption filed it as ' + intake.classified_as : ''),
        ai_suggested_field: null, ai_confidence: doc?.confidence || 'low',
        status: 'pending', auto_applied: false, extracted: { licence_read: doc, intake },
      });
    } catch (_e) { /* the file is stored and in wa_document_intake; a lost audit row must not fail the turn */ }
    return { ok: true, applied: [], filed: 'pending', intake, seen,
             note: 'kept as a pending document, not filed as the licence (' + seen + ')' };
  }

  // A LICENCE, READ WITH CONFIDENCE: applied exactly as the portal and the email doors apply one.
  const upd: Record<string, unknown> = {
    license_doc_path: path, license_doc_name: fname, doc_extracted_at: new Date().toISOString(),
    // What the old licence printed never judges a new one (2 Nov 2026, ledger 1442).
    trade_license_no: null, license_authority: null, license_expiry: null,
    // The name printed on this licence, read by the vision model off the photo or scan.
    licence_legal_name: licenceNameFromModel(doc),
  };
  const applied: string[] = [];
  if (doc.license_number) { upd.trade_license_no = doc.license_number; applied.push('licence no ' + doc.license_number); }
  if (doc.license_authority) { upd.license_authority = doc.license_authority; applied.push('authority'); }
  if (doc.expiry_date) { upd.license_expiry = doc.expiry_date; applied.push('expiry ' + doc.expiry_date); }
  if (doc.city) upd.license_city = doc.city;
  if (doc.trn) { upd.trn = doc.trn; applied.push('TRN'); }
  // Review of #962: a licence number another claimed company holds is set aside (the file and the other
  // readings are still written) and sent to a human, instead of failing the whole record update.
  const { error: uErr, licenceSetAside } = await updateLeadSettingAsideClashingLicence(admin as unknown as LeadWriter, leadId, upd, 'wa_inbound');
  if (licenceSetAside) { const i = applied.findIndex((a) => a.startsWith('licence no ')); if (i >= 0) applied.splice(i, 1); }
  if (uErr) return { ok: false, applied: [], note: 'the file was stored but the record could not be updated' };

  try {
    await admin.from('doc_reviews').insert({
      lead_id: leadId, from_email: null, subject, file_name: fname, file_path: path, mime: san.mime, ai_relevant: true, ai_category: 'trade_license',
      ai_summary: 'read from WhatsApp: ' + [doc.legal_name, doc.license_number, doc.expiry_date].filter(Boolean).join(' / '),
      ai_suggested_field: 'license_doc_path', ai_confidence: doc.confidence,
      status: 'pending', auto_applied: applied.length > 0, extracted: doc,
    });
  } catch (_e) { /* the lead is already updated; a lost audit row must not undo that */ }

  return { ok: true, applied, filed: 'licence', seen: 'a trade licence', note: 'read and applied' };
}
