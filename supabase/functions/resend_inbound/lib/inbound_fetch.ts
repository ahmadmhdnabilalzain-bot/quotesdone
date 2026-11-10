// resend_inbound: fetching the full email and its attachments from Resend, and the licence/profile extractor call. Moved out of index.ts unchanged (9 Nov 2026).
import { timedFetch } from '../../_shared/timed_fetch.ts';
import { safeFetch } from '../../_shared/safe_url.ts';
import { SUPA_URL, logRun } from './runtime.ts';
// Resend's webhook enters at us-east-1; the extractor runs beside the database (_shared/db_region.ts; it_engineer, 10 Nov 2026).
import { inDbRegion } from '../../_shared/db_region.ts';
import { b64ToBytes, bytesToB64 } from './mail_parse.ts';

// A TIMEOUT ON EVERY RESEND API READ (it_engineer, 10 Nov 2026, channels audit R7): these two reads had none, so a stalled Resend
// answer held the webhook's worker until the edge wall-clock killed it, and the e-mail was lost with no record. 15 s, as the
// attachment download below (ATTACH_FETCH); a timeout reads as null, the caller's existing "not fetched" path.
// prevented by: resend_inbound/inbound_fetch_timeout.test.ts
export const RESEND_READ_MS = 15_000;
export async function fetchInboundEmail(emailId:string, rkey:string){ try{ const r=await fetch(`https://api.resend.com/emails/inbound/${emailId}`,{headers:{Authorization:`Bearer ${rkey}`}, signal: AbortSignal.timeout(RESEND_READ_MS)}); if(!r.ok) return null; return await r.json(); }catch{ return null; } }
// SSRF FIX 9 Sep 2026 -------------------------------------------------------------------------
// Both fetch sites below took a URL out of a REQUEST BODY field and handed it to bare fetch() —
// no scheme check, no host check, no timeout, no size cap — inside a service_role function sitting
// on the same network as Supabase's internal endpoints. `http://169.254.169.254/…`,
// `http://127.0.0.1:54321/…` and `file://` were all reachable. The endpoint is Svix-HMAC verified
// with a 5-minute skew window, so an arbitrary internet caller could not reach it: the attacker had
// to control what Resend forwarded as attachment metadata. That is why this is moderate and not
// critical, and it is not a reason to leave it. _shared/safe_url.ts refuses the target, re-checks
// the FINAL url after redirects, aborts after 15s and stops reading at 25 MB — the same ceiling
// sanitizeUpload applies to the bytes a few lines further down.
//
// A REFUSAL IS RECORDED, never a silent null. The caller counts a null as a LOST attachment, and
// "we would not fetch that URL" is a different event from "Resend would not give us the file".
export const ATTACH_FETCH = { timeoutMs: 15_000, maxBytes: 25 * 1024 * 1024 };
export async function fetchAttachmentUrl(u: string, where: string): Promise<Uint8Array|null> {
  const r = await safeFetch(u, ATTACH_FETCH);
  if (r.ok) return r.bytes;
  if (r.error === 'url_refused' || r.error === 'url_refused_after_redirect') {
    await logRun('error', { ssrf_refused: 1, stage: where, reason: r.detail, url: String(u).slice(0, 120) },
      'resend_inbound REFUSED to fetch an attachment URL (' + r.detail + ') at ' + where + '. Until 9 Sep 2026 this function fetched that URL unchecked from inside the service-role network, so the cloud metadata address and loopback services were reachable through attachment metadata. If this fires on genuine Resend traffic the attachment host has changed and the allow rules need widening — it has NOT fired on a real delivery as of this writing.');
  }
  return null;
}
export async function fetchInboundAttachmentBytes(emailId:string, attId:string, rkey:string){ try{ const r=await fetch(`https://api.resend.com/emails/inbound/${emailId}/attachments/${attId}`,{headers:{Authorization:`Bearer ${rkey}`}, signal: AbortSignal.timeout(RESEND_READ_MS)}); if(!r.ok) return null; const j=await r.json(); const o=j.data||j; const u=o.download_url||o.url; if(!u) return null; return await fetchAttachmentUrl(String(u), 'resend_download_url'); }catch{ return null; } }
export async function attachmentBytes(a:any, emailId:string, rkey:string|undefined){ if (a.content) return b64ToBytes(String(a.content)); if (a.url || a.download_url) { const by = await fetchAttachmentUrl(String(a.url||a.download_url), 'webhook_attachment_url'); if (by) return by; } if (a.id && emailId && rkey) return await fetchInboundAttachmentBytes(emailId, String(a.id), rkey); return null; }
export async function extractDoc(mode:string, bytes:Uint8Array, mime:string, fname:string, inbSecret:string){ try{ const isImg=/^image\//.test(mime); const payload:any = isImg ? { __secret:inbSecret, mode, images:[{ b64: bytesToB64(bytes), mime }] } : { __secret:inbSecret, mode, file_b64: bytesToB64(bytes), mime, filename: fname }; const r=await timedFetch(inDbRegion(`${SUPA_URL}/functions/v1/license_extract`),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}); const j=await r.json(); return (j&&j.ok)?j:null; }catch{ return null; } }
