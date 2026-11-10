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

// Store, read and APPLY one attachment to the sender's lead. Deliberately the same sequence
// resend_inbound uses for an emailed licence — sanitize, upload, extract, update, file a
// doc_reviews row — so a supplier gets the same outcome whichever way they send it.
export async function handleSupplierDoc(leadId: number, url: string, declaredMime: string, fromPhone: string, allowInline: boolean):
    Promise<{ ok: boolean; applied: string[]; note: string }> {
  const got = await fetchTwilioMedia(url, allowInline);
  // The download error names hosts, credentials and HTTP codes, and this note is quoted to the supplier
  // (22 Sep 2026): the real reason goes to the function log, the supplier gets a plain sentence.
  if (!got.bytes) {
    console.error('wa_inbound media download failed:', got.err || 'no bytes');
    return { ok: false, applied: [], note: 'the file could not be downloaded from WhatsApp — please send it again' };
  }

  const mime = got.mime || declaredMime || 'application/octet-stream';
  const ext = /pdf/i.test(mime) ? 'pdf' : /png/i.test(mime) ? 'png' : /jpe?g/i.test(mime) ? 'jpg' : 'bin';
  const fname = 'whatsapp-licence-' + Date.now() + '.' + ext;

  // The mime came from a header a sender controls. Sniff the bytes, refuse anything that is not a
  // PDF or a real image, and strip EXIF/GPS off a photographed document before it is stored.
  const sc = await sanitizeAndScan({ input: got.bytes, declaredMime: mime, filename: fname, allow: SAFE_UPLOAD,
                                     scan: { source: 'wa_inbound.supplier_doc', subject: fromPhone, filename: fname, bucket: 'supplier-docs' } });
  if (!sc.ok) return { ok: false, applied: [], note: sc.body.error === 'malware_detected'
    ? 'that file was refused by our malware scanner — please check it and send a clean copy'
    : 'that file type is not accepted — please send a PDF or a photo of the licence' };
  const san = sc.result;

  const path = 'inbound/' + leadId + '/' + Date.now() + '_' + fname;
  const up = await admin.storage.from('supplier-docs').upload(path, san.bytes, { contentType: san.mime, upsert: true });
  if (up && (up as { error?: unknown }).error) return { ok: false, applied: [], note: 'the file could not be stored' };

  const docSecret = await sec('cred_fn_wa_docs');
  let doc: Record<string, string> | null = null;
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

  // The document is attached whatever the extraction did — a licence we could not read is still a
  // licence on file, and license_doc_path is what unblocks the approval gate.
  const upd: Record<string, unknown> = {
    license_doc_path: path, license_doc_name: fname, doc_extracted_at: new Date().toISOString(),
    // What the old licence printed never judges a new one (2 Nov 2026, ledger 1442).
    trade_license_no: null, license_authority: null, license_expiry: null,
    // The name printed on this licence, read by the vision model off the photo or scan; null = not read,
    // and the review then holds the registration for a human (licence_name_unread).
    licence_legal_name: licenceNameFromModel(doc),
  };
  const applied: string[] = [];
  // 'low' confidence never overwrites a stored fact. license_extract returns confidence 'low' both
  // for an unreadable scan AND for a response that was truncated into {} — the two are
  // indistinguishable from here, so neither is allowed to change a number on the record.
  if (doc && doc.confidence !== 'low') {
    if (doc.license_number) { upd.trade_license_no = doc.license_number; applied.push('licence no ' + doc.license_number); }
    if (doc.license_authority) { upd.license_authority = doc.license_authority; applied.push('authority'); }
    if (doc.expiry_date) { upd.license_expiry = doc.expiry_date; applied.push('expiry ' + doc.expiry_date); }
    if (doc.city) upd.license_city = doc.city;
    if (doc.trn) { upd.trn = doc.trn; applied.push('TRN'); }
  }
  // Review of #962: a licence number another claimed company holds is set aside (the file and the other
  // readings are still written) and sent to a human, instead of failing the whole record update.
  const { error: uErr, licenceSetAside } = await updateLeadSettingAsideClashingLicence(admin as unknown as LeadWriter, leadId, upd, 'wa_inbound');
  if (licenceSetAside) { const i = applied.findIndex((a) => a.startsWith('licence no ')); if (i >= 0) applied.splice(i, 1); }
  if (uErr) return { ok: false, applied: [], note: 'the file was stored but the record could not be updated' };

  try {
    await admin.from('doc_reviews').insert({
      lead_id: leadId, from_email: null, subject: 'WhatsApp from ' + fromPhone.replace('whatsapp:', ''),
      file_name: fname, file_path: path, mime: san.mime, ai_relevant: true, ai_category: 'trade_license',
      ai_summary: doc ? ('read from WhatsApp: ' + [doc.legal_name, doc.license_number, doc.expiry_date].filter(Boolean).join(' / ')) : 'stored from WhatsApp; extraction returned nothing',
      ai_suggested_field: 'license_doc_path', ai_confidence: doc?.confidence || 'low',
      status: 'pending', auto_applied: applied.length > 0, extracted: doc,
    });
  } catch (_e) { /* the lead is already updated; a lost audit row must not undo that */ }

  return { ok: true, applied,
           note: applied.length ? 'read and applied' : 'stored, but the details could not be read confidently' };
}
