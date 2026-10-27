// resend_inbound v15 - inbound emails. Webhook metadata-only; body via GET /emails/inbound/{id}; attachments via
// /attachments/{id} -> download_url. Receipts -> finance. Supplier docs -> store + AI classify + AUTO-EXTRACT
// (trade licence -> licence no/authority/emirate/expiry/TRN; profile/catalogue -> capability) applied to the matched lead.
// v12: agent_runs instrumentation for silently-lost inbound documents.
// v13: Svix signature verification (see PROVENANCE below).
// v14: DUPLICATE-EXPENSE FIX (see DEDUP below).
// v15: RECEIPT ARCHIVE RETRY + BACKFILL (see v15 FIX below). v14's dedup guard returned before any
//      upload was attempted, which silently made "re-forward the email to retry" impossible.
// v16 (6 Sep 2026): DETERMINISTIC RECEIPT EXTRACTION FIRST (_shared/receipt_parse.ts); the model is the
//      fallback. A receipt nobody could book is handed to the BOOKKEEPER (fn_receipt_hand_to_bookkeeper)
//      and its rows carry owner_role, so the founder's Inbox and Reviews never show his own receipts.
//
// v13 SECURITY FIX 19 Jul 2026 -----------------------------------------------------------------
// v12 authenticated ONLY on a shared token in the QUERY STRING (?s=...). The full URL including
// that token is stored in the Resend dashboard, lands in browser history and referrer headers, and
// is written to any proxy or access log that records request lines. Anyone holding it could forge
// inbound email events and, because this function BOOKS EXPENSES and WRITES SUPPLIER RECORDS,
// could inject fabricated expense_entries rows, overwrite a supplier's trade licence number, TRN
// and capability summary, and upload arbitrary files into the supplier-docs bucket.
// v13 verifies the SVIX SIGNATURE Resend signs each delivery with (svix-id, svix-timestamp,
// svix-signature) against app_secrets.resend_inbound_signing_secret. The ?s= token is KEPT as a
// second factor - both must now pass. The body is read ONCE as raw text because the signature is
// over the exact bytes; it is parsed only after verification succeeds.
import { readEveryAttachment, envGatewayVision, clearerCopyAsk } from '../_shared/read_every_attachment.ts';
import { timedFetch } from '../_shared/timed_fetch.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { paidProviderGate } from '../_shared/paid_gate.ts';
import { makeLlmRich } from '../_shared/llm.ts';
import { sanitizeUpload, SAFE_UPLOAD } from '../_shared/attachment.ts';
// MALWARE WATCH, 9 Sep 2026 — see _shared/malware.ts. Inbound mail is the classic malware carrier
// and this function archives what arrives, so the verdict has to be taken before the object is
// written, not after.
import { sanitizeAndScan } from '../_shared/malware.ts';
import { parseAmount, parseReceipt } from '../_shared/receipt_parse.ts';
import { pdfText } from '../_shared/pdf_text.ts';
import { safeFetch } from '../_shared/safe_url.ts';
// A receipt whose email carried no vendor file gets a PDF PRINT of the email, not a .html blob.
import { emailPrintPdf } from '../_shared/email_print.ts';
import { observe } from '../_shared/observe.ts';
import { requestDelivery } from '../_shared/deliver.ts';
import { statementRowText, takeInStatement } from '../_shared/bank_statement_intake.ts';
import { defaultDeps, type ThinkDeps } from '../_shared/think.ts';
import { documentKind, readingOf, receiptVendor, type ExpenseMail } from '../_shared/reasoned_books.ts';
import { isUnsubscribeRequest } from '../_shared/unsubscribe_mailbox.ts';
import { fromDomainAuthenticated, microsoftDomainAuthenticated, neverSuppressible, OPT_OUT_TYPES } from '../_shared/suppression_policy.ts';
import { approvalTokenOf, calendarTokenOf, isCalendarReply, ownWords, planTokenOf, replyIntent } from '../_shared/marketing_calendar_mail.ts';
import { registerRowsFor } from '../_shared/expense_mailbox.ts';
import { M365_INBOUND_PREFIX } from '../_shared/m365_reply_inbox.ts';
import { licenceNameFromModel } from '../_shared/document_expiry.ts';
import { type LeadWriter, updateLeadSettingAsideClashingLicence } from '../_shared/duplicate_company.ts';
import { orSafeEmail } from '../_shared/or_filter_email.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const SUPA_URL = Deno.env.get('SUPABASE_URL')!;
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
const MODEL = 'anthropic/claude-sonnet-5';
const classify = makeLlmRich([MODEL], { max: 500, temperature: 0.1, fn: 'resend_inbound' });
async function sec(k: string){ const {data}=await admin.from('app_secrets').select('value').eq('key',k).maybeSingle(); return data?.value as string|undefined; }

// Observability -------------------------------------------------------------
const T0 = Date.now();
async function logRun(status: string, counts: Record<string, unknown>, note: string) {
  try {
    await admin.from('agent_runs').insert({ agent: 'resend_inbound', status, counts,
      note: String(note || '').slice(0, 500),
      started_at: new Date(T0).toISOString(), finished_at: new Date().toISOString() });
  } catch (_e) { /* never let logging drop an inbound email */ }
}

// Webhook authenticity ------------------------------------------------------
function timingSafeEq(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}
// Svix/Standard-Webhooks: base64(HMAC-SHA256(secret, "<id>.<timestamp>.<rawBody>")).
async function verifySvix(secret: string, rawBody: string, h: Headers): Promise<{ ok: boolean; reason: string }> {
  const id = h.get('svix-id') || h.get('webhook-id');
  const ts = h.get('svix-timestamp') || h.get('webhook-timestamp');
  const sigHeader = h.get('svix-signature') || h.get('webhook-signature');
  if (!id || !ts || !sigHeader) return { ok: false, reason: 'missing svix-id / svix-timestamp / svix-signature headers - not a genuine Resend delivery' };
  const skew = Math.abs(Date.now() / 1000 - Number(ts));
  if (!Number.isFinite(skew)) return { ok: false, reason: 'unparseable svix-timestamp' };
  if (skew > 300) return { ok: false, reason: 'timestamp is ' + Math.round(skew) + 's from now, outside the 5 minute replay window' };
  try {
    const b64 = secret.startsWith('whsec_') ? secret.slice(6) : secret;
    const keyBytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    const ck = await crypto.subtle.importKey('raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const mac = new Uint8Array(await crypto.subtle.sign('HMAC', ck, new TextEncoder().encode(id + '.' + ts + '.' + rawBody)));
    const expected = btoa(String.fromCharCode(...mac));
    for (const part of sigHeader.split(' ')) {
      const candidate = part.includes(',') ? part.split(',')[1] : part;
      if (candidate && timingSafeEq(candidate, expected)) return { ok: true, reason: 'ok' };
    }
    return { ok: false, reason: 'signature mismatch - payload was not signed with our endpoint secret' };
  } catch (e) { return { ok: false, reason: 'verification error: ' + String((e as Error)?.message || e).slice(0, 120) }; }
}

function addr(v: unknown){ if(!v) return ''; if(Array.isArray(v)) v=v[0]; const s=String((v as any)?.email||(v as any)?.address||v); const m=s.match(/<([^>]+)>/); return (m?m[1]:s).trim().toLowerCase(); }
function parseJson(t:string){ try{return JSON.parse(t);}catch{ const m=t.match(/\{[\s\S]*\}/); if(m){try{return JSON.parse(m[0]);}catch{}} return {}; } }
function stripHtml(s:string){ return String(s||'').replace(/<style[\s\S]*?<\/style>/gi,' ').replace(/<script[\s\S]*?<\/script>/gi,' ').replace(/<[^>]+>/g,' ').replace(/&nbsp;/g,' ').replace(/&amp;/g,'&').replace(/&#36;/g,'$').replace(/\s+/g,' ').trim(); }
function pickBody(d:any){ const t = d?.text || d?.plain || d?.['body-plain'] || d?.['stripped-text'] || d?.email?.text || d?.parsed?.text || ''; const h = d?.html || d?.['body-html'] || d?.email?.html || d?.parsed?.html || ''; let body = String(t||''); if (!body && h) body = stripHtml(String(h)); return body; }
function b64ToBytes(b64:string){ const bin=atob(b64.replace(/^data:[^;]+;base64,/,'')); const a=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++)a[i]=bin.charCodeAt(i); return a; }
function bytesToB64(u8:Uint8Array){ let bin=''; const c=0x8000; for(let i=0;i<u8.length;i+=c){ bin+=String.fromCharCode.apply(null, Array.from(u8.subarray(i,i+c))); } return btoa(bin); }
async function fetchInboundEmail(emailId:string, rkey:string){ try{ const r=await fetch(`https://api.resend.com/emails/inbound/${emailId}`,{headers:{Authorization:`Bearer ${rkey}`}}); if(!r.ok) return null; return await r.json(); }catch{ return null; } }
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
const ATTACH_FETCH = { timeoutMs: 15_000, maxBytes: 25 * 1024 * 1024 };
async function fetchAttachmentUrl(u: string, where: string): Promise<Uint8Array|null> {
  const r = await safeFetch(u, ATTACH_FETCH);
  if (r.ok) return r.bytes;
  if (r.error === 'url_refused' || r.error === 'url_refused_after_redirect') {
    await logRun('error', { ssrf_refused: 1, stage: where, reason: r.detail, url: String(u).slice(0, 120) },
      'resend_inbound REFUSED to fetch an attachment URL (' + r.detail + ') at ' + where + '. Until 9 Sep 2026 this function fetched that URL unchecked from inside the service-role network, so the cloud metadata address and loopback services were reachable through attachment metadata. If this fires on genuine Resend traffic the attachment host has changed and the allow rules need widening — it has NOT fired on a real delivery as of this writing.');
  }
  return null;
}
async function fetchInboundAttachmentBytes(emailId:string, attId:string, rkey:string){ try{ const r=await fetch(`https://api.resend.com/emails/inbound/${emailId}/attachments/${attId}`,{headers:{Authorization:`Bearer ${rkey}`}}); if(!r.ok) return null; const j=await r.json(); const o=j.data||j; const u=o.download_url||o.url; if(!u) return null; return await fetchAttachmentUrl(String(u), 'resend_download_url'); }catch{ return null; } }
async function attachmentBytes(a:any, emailId:string, rkey:string|undefined){ if (a.content) return b64ToBytes(String(a.content)); if (a.url || a.download_url) { const by = await fetchAttachmentUrl(String(a.url||a.download_url), 'webhook_attachment_url'); if (by) return by; } if (a.id && emailId && rkey) return await fetchInboundAttachmentBytes(emailId, String(a.id), rkey); return null; }
async function extractDoc(mode:string, bytes:Uint8Array, mime:string, fname:string, inbSecret:string){ try{ const isImg=/^image\//.test(mime); const payload:any = isImg ? { __secret:inbSecret, mode, images:[{ b64: bytesToB64(bytes), mime }] } : { __secret:inbSecret, mode, file_b64: bytesToB64(bytes), mime, filename: fname }; const r=await timedFetch(`${SUPA_URL}/functions/v1/license_extract`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}); const j=await r.json(); return (j&&j.ok)?j:null; }catch{ return null; } }
const SYS = `You classify a document a supplier emailed to QuotesDone, a UAE building & fit-out marketplace. Decide if it relates to the supplier's company profile and what it is. Return STRICT JSON only: {\"relevant\":boolean,\"category\":\"trade_license\"|\"company_profile\"|\"catalogue\"|\"certificate\"|\"vat_trn\"|\"bank_letter\"|\"insurance\"|\"other\",\"summary\":string,\"suggested_field\":string|null,\"confidence\":\"low\"|\"medium\"|\"high\"}. suggested_field = the profile detail it informs or null.`;
// The founder confirmed this address on 9 Sep 2026: the accountant "collects expenses from the
// email expenses@mail.quotesdone.com". Same mail. subdomain as docs@mail.quotesdone.com.
const EXPENSE_MAILBOX = 'expenses@mail.quotesdone.com';
async function sha256hex(s: string){ const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)); return Array.from(new Uint8Array(d)).map((b)=>b.toString(16).padStart(2,'0')).join(''); }
const dbxSafe = (s: string) => String(s||'').replace(/[\\/:*?"<>|\r\n\t]+/g,' ').replace(/\s+/g,' ').trim();
// WHICH MAILBOX the sender addressed is structured data, the one fact the sender chose: mail to a finance mailbox
// is expense mail. What any OTHER email is -- a receipt, a statement, or a supplier's document -- is MEANING, and
// is reasoned (_shared/reasoned_books.ts documentKind); the subject/sender regex that decided it (isReceiptish) is
// gone (23 Sep 2026, founder_instruction 886-903, decision point accountant.resend_receiptish).
const FINANCE_BOXES = new Set(['receipts','receipt','billing','expenses','expense','finance','accounts','accounting','fin','subscriptions','subscription','bills','bill']);
// The reasoning engine's model, embedder and database. A test injects a mocked one; nothing else does.
let thinkDeps: ThinkDeps | null = null;
export function useThinkDeps(d: ThinkDeps | null) { thinkDeps = d; }
// Exported so its test drives the real handler; the runtime serves it (a test sets RESEND_INBOUND_NO_SERVE).
export const handler = observe('resend_inbound', async (req) => {
  try {
    const url = new URL(req.url);
    const s = url.searchParams.get('s');
    const ibs = await sec('inbound_secret'); const rit = await sec('resend_inbound_token');
    // 28 Sep 2026: two refusals at 12:37 UTC could not be attributed - the row said nothing about the
    // caller. A genuine Resend delivery always carries svix-* headers; record whether this one did, the
    // user agent, and the token's length only (never its value), so the next refusal names its source.
    if (!s || (s !== ibs && s !== rit)) { await logRun('error', { authorised: 0, stage: 'query_token',
        token_len: s ? s.length : 0, svix_headers: !!(req.headers.get('svix-id') || req.headers.get('webhook-id')),
        user_agent: (req.headers.get('user-agent') || '').slice(0, 120), method: req.method },'resend_inbound rejected a caller with a bad or missing ?s token. No inbound email was processed - if this was genuine Resend traffic, a supplier document or forwarded receipt has been dropped.'); return J({ error: 'forbidden' }, 403); }
    // AUDIT 9.5 (3 Aug 2026) - THE INSTRUMENT, not the fix. This endpoint accepts the omnipotent
    // shared secret as a ?s= query token, and the shared secret is due to be withdrawn on 10 Aug.
    // Whether that breaks inbound email depends entirely on which value Resend's configured webhook
    // URL actually carries, and that cannot be read from here. So: say so, loudly, every time the
    // shared secret is the value that authorised. Seven days of silence means Resend is on the
    // dedicated token and withdrawal is safe; a single one of these means it is not, and the URL
    // must be re-issued with resend_inbound_token BEFORE the secret is withdrawn.
    if (ibs && s === ibs && s !== rit) {
      await logRun('error', { authorised: 1, stage: 'query_token', via: 'legacy_shared_secret' },
        'resend_inbound was authorised by the SHARED SECRET, not by resend_inbound_token. When the shared secret is withdrawn this endpoint will start refusing genuine Resend deliveries and inbound supplier email will silently stop. Re-issue the Resend inbound webhook URL with resend_inbound_token before withdrawal.');
    }

    // Read the body ONCE as raw text - the Svix signature covers the exact bytes.
    const raw = await req.text();
    const signingSecret = await sec('resend_inbound_signing_secret');
    if (!signingSecret) { await logRun('error', { authorised: 0, stage: 'no_signing_secret' }, 'resend_inbound could not read resend_inbound_signing_secret from app_secrets, so it cannot confirm this email really came from Resend. The delivery was REJECTED rather than trusted on the query token alone. Inbound receipts and supplier documents are paused until the secret is restored.'); return J({ error: 'signing secret unavailable' }, 503); }
    const v = await verifySvix(signingSecret, raw, req.headers);
    if (!v.ok) { await logRun('error', { authorised: 0, stage: 'signature', reason: v.reason }, 'resend_inbound REJECTED a delivery that failed Svix signature verification (' + v.reason + '). Until 19 Jul 2026 a leaked ?s token alone was enough to book fake expenses and overwrite supplier licence data. If this fires on genuine Resend traffic, check the signing secret in app_secrets matches the endpoint in the Resend dashboard.'); return J({ error: 'invalid signature' }, 401); }

    let p: any = {}; try { p = JSON.parse(raw); } catch (_e) { p = {}; }
    const isResend = p?.type === 'email.received' && p?.data;
    let d = isResend ? p.data : (p.data || p);
    const emailId = String(d.email_id || d.id || '');
    // 6 Oct 2026: a reply read from the Microsoft 365 mailbox (_shared/m365_reply_inbox.ts) arrives with its body,
    // headers and files inline and an id of 'm365:<Graph immutable id>'. Resend has no such email, so it is never
    // asked for one; the id is still the provider_email_id that makes a second delivery a duplicate.
    const resendEmailId = emailId.startsWith(M365_INBOUND_PREFIX) ? '' : emailId;
    // 6 SEP 2026 (MASTER_PLAN A6): the classifier no longer holds a provider key. It reaches the
    // model through ai_gateway like every other caller; `key` below is only "is classification on".
    const rkey = await sec('resend_api_key'); const key = await sec('cred_fn_resend_inbound'); const inbSecret = await sec('cred_fn_ai');
    let text = pickBody(d);
    let atts: any[] = Array.isArray(d.attachments) ? d.attachments : [];
    // The RFC headers a customer reply needs (Message-ID, for In-Reply-To) and the ones that say a machine sent
    // it (Auto-Submitted, Content-Type); kept from the webhook, or from the full read below when it runs.
    let hdrs: Record<string, unknown> | null = (d.headers && typeof d.headers === 'object') ? d.headers : null;
    if ((!text || text.length < 20 || !atts.length) && resendEmailId && rkey) {
      const full = await fetchInboundEmail(resendEmailId, rkey);
      if (full) { const fd = full.data || full; if (fd.headers && typeof fd.headers === 'object') hdrs = { ...fd.headers, ...(hdrs || {}) }; const fb = pickBody(fd); if (fb && fb.length > text.length) text = fb; if (Array.isArray(fd.attachments) && fd.attachments.length) atts = fd.attachments; if (!d.subject && fd.subject) d = { ...d, subject: fd.subject }; if (!d.from && fd.from) d = { ...d, from: fd.from }; if (!d.to && fd.to) d = { ...d, to: fd.to }; if (!d.html && fd.html) d = { ...d, html: fd.html }; }
      else if (emailId) await logRun('error', { email_id: emailId }, 'could not fetch full inbound email from Resend - body and attachments may be incomplete');
    }
    // 14 SEP 2026 (founder: "all conversations need to be saved"). The 8,000-character cut below is
    // for the model prompts only. What is STORED is the whole email, its HTML and Resend's own id,
    // because Resend keeps inbound mail about a month and after that the row is the only copy.
    const fullText = String(text||''); const fullHtml: string | null = String(d.html || d['body-html'] || '') || null;
    const providerEmailId: string | null = emailId || null;
    // A REDELIVERY IS NOT A NEW EMAIL (22 Sep 2026, founder instruction 705). Every path below ends by
    // recording the email in inbound_messages under Resend's own id (unique index), but the receipt
    // reader, the document classifier and license_extract ran BEFORE that record was looked at, so a
    // Resend retry of an email we had already handled paid for the same model reads again and then
    // lost the insert to the unique index. An email already on file is answered here, before any
    // model call. A first delivery that died before its record was written is not on file, so it is
    // still processed in full; a re-forward is a new email with a new id.
    if (providerEmailId) {
      const { data: seen } = await admin.from('inbound_messages').select('id').eq('provider_email_id', providerEmailId).limit(1);
      if (seen && seen.length) {
        await logRun('ok', { redelivery: 1, email_id: providerEmailId }, 'resend_inbound received email ' + providerEmailId + ' again; it is already on file as inbound message ' + seen[0].id + ', so nothing was re-read and no model was asked.');
        return J({ ok: true, duplicate: true, inbound_message_id: seen[0].id });
      }
    }
    text = fullText.slice(0,8000);
    const from = addr(d.from); const to = addr(d.to); const subject = String(d.subject||'').slice(0,300);
    const toLocal = to.split('@')[0] || '';
    const adminList = String(await sec('admin_emails')||'management@quotesdone.com').toLowerCase().split(',').map((x)=>x.trim()).filter(Boolean);
    const fwdList = String(await sec('expense_forwarders')||'').toLowerCase().split(',').map((x)=>x.trim()).filter(Boolean);
    const expenseSenderOk = [...adminList, ...fwdList].includes(from);
    const owner = adminList[0] || 'management@quotesdone.com';

    // ---- HIS REPLY TO THE MONTHLY SOCIAL CALENDAR (23 Sep 2026, marketing; founder_instruction 872) ----
    // "I can reply to the email and say approve and that's it." A reply to calendar+<token>@mail.quotesdone.com
    // (or carrying "[ref <token>]" in its subject) is read here and nowhere else: never as a receipt or a
    // supplier document. This side reads the mail -- token, sender, the receiving server's SPF/DKIM/DMARC
    // verdict (fromDomainAuthenticated, the same gate the unsubscribe path uses) and what the reply says
    // (replyIntent) -- and fn_marketing_calendar_reply decides: founder + authenticated + this calendar's token
    // + content unchanged since it was sent + month not over + "approve". It answers him itself.
    if (isCalendarReply({ to, subject })) {
      const calHdrs = d.headers?.['authentication-results'] ? d.headers
        : ((resendEmailId && rkey) ? await (async () => { const f: any = await fetchInboundEmail(resendEmailId, rkey); return (f?.data || f)?.headers; })() : null);
      const verdict = { token: calendarTokenOf({ to, subject }) || '', from_email: from,
        authenticated: fromDomainAuthenticated(calHdrs?.['authentication-results'], from), message_id: providerEmailId || '', intent: replyIntent(fullText),
        // his own words (quote cut off): a reply that is not exactly "approve" becomes the marketing seat's change request
        text: ownWords(fullText).slice(0, 4000) };
      const { data: out, error: cErr } = await admin.rpc('fn_marketing_calendar_reply', { p: verdict });
      await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject,
        body: '[MONTHLY CALENDAR REPLY: ' + (cErr ? 'error ' + cErr.message : String((out as any)?.outcome)) + '; authenticated ' + verdict.authenticated + ', read as ' + verdict.intent + ']\n\n' + fullText,
        html: fullHtml, provider_email_id: providerEmailId, attachments_count: 0, matched_existing: !!(out as any)?.campaign_key,
        needs_review: !!cErr || (out as any)?.outcome === 'not_the_founder' });
      await logRun(cErr ? 'error' : 'ok', { calendar_reply: 1, outcome: (out as any)?.outcome ?? null, authenticated: verdict.authenticated, intent: verdict.intent },
        'monthly calendar reply from ' + from + ': ' + (cErr ? 'fn_marketing_calendar_reply failed: ' + cErr.message : String((out as any)?.outcome)));
      return J({ ok: !cErr, calendar_reply: true, outcome: (out as any)?.outcome ?? null });
    }

    // ---- HIS REPLY TO AN ARTICLE OR LAUNCH-PLAN APPROVAL EMAIL (28 Sep 2026, marketing) ----
    // Reply-To approve+<token>@mail.quotesdone.com. Same gate as the calendar: fn_marketing_approval_reply
    // approves only for the founder, SPF/DKIM/DMARC-authenticated, saying exactly "approve"; anything else he
    // writes is filed as a change for the marketing seat and nothing is published.
    const approveToken = approvalTokenOf({ to, subject });
    if (approveToken) {
      const aHdrs = d.headers?.['authentication-results'] ? d.headers
        : ((resendEmailId && rkey) ? await (async () => { const f: any = await fetchInboundEmail(resendEmailId, rkey); return (f?.data || f)?.headers; })() : null);
      const av = { token: approveToken, from_email: from, authenticated: fromDomainAuthenticated(aHdrs?.['authentication-results'], from),
        message_id: providerEmailId || '', intent: replyIntent(fullText), text: ownWords(fullText).slice(0, 4000) };
      const { data: out, error: aErr } = await admin.rpc('fn_marketing_approval_reply', { p: av });
      await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject,
        body: '[MARKETING APPROVAL REPLY: ' + (aErr ? 'error ' + aErr.message : String((out as any)?.outcome)) + '; authenticated ' + av.authenticated + ', read as ' + av.intent + ']\n\n' + fullText,
        html: fullHtml, provider_email_id: providerEmailId, attachments_count: 0, matched_existing: !!((out as any)?.article || (out as any)?.plan_doc),
        needs_review: !!aErr || (out as any)?.outcome === 'not_the_founder' });
      await logRun(aErr ? 'error' : 'ok', { approval_reply: 1, outcome: (out as any)?.outcome ?? null, authenticated: av.authenticated, intent: av.intent },
        'marketing approval reply from ' + from + ': ' + (aErr ? 'fn_marketing_approval_reply failed: ' + aErr.message : String((out as any)?.outcome)));
      return J({ ok: !aErr, approval_reply: true, outcome: (out as any)?.outcome ?? null });
    }

    // ---- HIS REPLY TO THE MONTHLY VIDEO IDEA PLAN (24 Sep 2026, marketing) ----
    // The plan email's Reply-To is plan+<token>@mail.quotesdone.com. Whatever he sends back -- his content, links,
    // or changes to the ideas -- is filed for the marketing seat by fn_marketing_month_plan_reply (same sender and
    // SPF/DKIM/DMARC rules as the calendar); the seat then builds and loads the calendar, and the calendar email
    // for his "approve" follows by itself (fn_marketing_calendar_due).
    const planToken = planTokenOf({ to, subject });
    if (planToken) {
      const pHdrs = d.headers?.['authentication-results'] ? d.headers
        : ((resendEmailId && rkey) ? await (async () => { const f: any = await fetchInboundEmail(resendEmailId, rkey); return (f?.data || f)?.headers; })() : null);
      const pv = { token: planToken, from_email: from, authenticated: fromDomainAuthenticated(pHdrs?.['authentication-results'], from),
        message_id: providerEmailId || '', text: ownWords(fullText).slice(0, 4000),
        attachments: atts.map((a: any) => String(a?.filename || a?.name || '')).filter(Boolean).slice(0, 50) };
      const { data: out, error: pErr } = await admin.rpc('fn_marketing_month_plan_reply', { p: pv });
      await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject,
        body: '[MONTHLY IDEA PLAN REPLY: ' + (pErr ? 'error ' + pErr.message : String((out as any)?.outcome)) + '; authenticated ' + pv.authenticated + ']\n\n' + fullText,
        html: fullHtml, provider_email_id: providerEmailId, attachments_count: pv.attachments.length, matched_existing: !!(out as any)?.month,
        needs_review: !!pErr || (out as any)?.outcome === 'not_the_founder' });
      await logRun(pErr ? 'error' : 'ok', { plan_reply: 1, outcome: (out as any)?.outcome ?? null, authenticated: pv.authenticated },
        'monthly idea plan reply from ' + from + ': ' + (pErr ? 'fn_marketing_month_plan_reply failed: ' + pErr.message : String((out as any)?.outcome)));
      return J({ ok: !pErr, plan_reply: true, outcome: (out as any)?.outcome ?? null });
    }

    // ---- Forwarded receipt / subscription -> finance ----
    // 6 SEP 2026: a receipt nobody could book goes to the BOOKKEEPER (handToBookkeeper), never to the founder.
    // 23 SEP 2026 (founder_instruction 886-903): WHAT the email is (a statement, a receipt and its cadence, a
    // Meta ads invoice, a licence or domain renewal, or none of these) and WHO issued it are REASONED
    // (_shared/reasoned_books.ts); only the figures are parsed (_shared/receipt_parse.ts). Under the model hold
    // nothing is booked on a guess: the email is held for the bookkeeper and the accountant's queue replays it.
    let receiptish = FINANCE_BOXES.has(toLocal);
    let receiptReason = '';
    const handToBookkeeper = async (inboundId: number | null | undefined, reviewIds: number[], reason: string) => {
      if (!inboundId) return null;
      const { data, error } = await admin.rpc('fn_receipt_hand_to_bookkeeper', { p_inbound_id: inboundId, p_review_ids: reviewIds, p_reason: reason.slice(0, 600) });
      if (error) await logRun('error', { inbound_id: inboundId, reviews: reviewIds }, 'fn_receipt_hand_to_bookkeeper failed: ' + String(error.message || '').slice(0, 200) + ' - the receipt row is held with no owner');
      return data as number | null;
    };

    // ---- THE EXPENSES MAILBOX IS EXPENSE MAIL AND NOTHING ELSE (9 Sep 2026) ----
    // app_secrets.expense_forwarders is the allowlist of people permitted to forward receipts.
    // WHY THE GATE MOVED HERE. Until today the allowlist was consulted only AFTER an amount had
    // been read. Mail from an unknown sender that did not parse as a receipt fell straight through
    // to the supplier-document branch further down, which uploads attachments and WRITES TO leads.
    // A stranger could never reach the ledger, but could reach a supplier record. Mail addressed to
    // the expenses mailbox is now refused before either path — and RECORDED, never dropped: the
    // refusal becomes an inbound_messages row and an accountant task, because "this is not from a
    // permitted forwarder" is a decision someone should see, not silence.
    const isExpenseMailbox = to === EXPENSE_MAILBOX || toLocal === 'expenses';
    if (isExpenseMailbox && !expenseSenderOk) {
      const { data: refusedRow } = await admin.from('inbound_messages').insert({
        from_email: from, to_email: to, subject,
        body: '[REFUSED — sender is not on app_secrets.expense_forwarders] nothing was booked, no document was stored, no supplier record was touched.\n\n' + (text || '').slice(0, 4000),
        attachments_count: 0, matched_existing: false, needs_review: true,
      }).select('id').maybeSingle();
      await handToBookkeeper(refusedRow?.id, [], `Mail to ${to} from ${from} was REFUSED: that address is not on app_secrets.expense_forwarders. Nothing was booked and no attachment was stored. Decide whether this sender should be added to the allowlist; if it is a company expense, add them and ask for a re-forward.`);
      await logRun('ok', { expenses_mailbox: 1, authorised: 0, from, to }, 'mail to the expenses mailbox was refused: ' + from + ' is not on the expense forwarder allowlist. Recorded as inbound_messages#' + (refusedRow?.id ?? '?') + ' and handed to the accountant.');
      return J({ ok: true, receipt: false, booked: false, reason: 'sender_not_allowlisted' });
    }

    // ---- AN UNSUBSCRIBE BY EMAIL IS HONOURED HERE (21 Sep 2026, customer_support) ----
    // See _shared/unsubscribe_mailbox.ts for the measurement: the reply path the supplier mail offered
    // had no reader. The sender is suppressed exactly as the link does it, except that an existing row
    // is left alone -- a hard bounce or complaint is a deliverability fact and must not be relabelled a
    // preference.
    // A FROM HEADER CAN BE FORGED (independent review, 22 Sep 2026). Svix proves Resend delivered this,
    // not who wrote it, so three gates stand before any suppression, and a request that fails one is kept
    // for customer_support to review (inbound_messages, needs_review) -- never applied:
    //   1. never our own domains, the admin addresses, the expense forwarders or the expense mailbox;
    //   2. the receiving server (SES) must have authenticated the From domain (_shared/suppression_policy.ts);
    //   3. we must actually have sent this address an invitation or reminder -- the only mail an opt-out stops.
    if (!isExpenseMailbox && from && isUnsubscribeRequest({ to, subject, text: fullText })) {
      let why = '';
      if (neverSuppressible(from, [...adminList, ...fwdList, EXPENSE_MAILBOX])) {
        why = 'a protected address (our own domain, an admin address or an expense forwarder)';
      } else {
        // The webhook is metadata-only; the headers come from GET /emails/inbound/{id} (measured 22 Sep 2026).
        const hdrs = d.headers?.['authentication-results'] ? d.headers
          : ((resendEmailId && rkey) ? await (async () => { const f: any = await fetchInboundEmail(resendEmailId, rkey); return (f?.data || f)?.headers; })() : null);
        // a reply handed in from the Microsoft 365 mailbox carries EOP's verdict, not SES's (suppression_policy.ts)
        const m365Reply = String(providerEmailId || '').startsWith('m365:');
        const authenticated = m365Reply ? microsoftDomainAuthenticated(hdrs?.['authentication-results'], from)
          : fromDomainAuthenticated(hdrs?.['authentication-results'], from);
        if (!authenticated) {
          why = 'the receiving server did not authenticate the sender domain (no aligned DMARC, DKIM or SPF pass)';
        } else {
          const { count } = await admin.from('notifications').select('id', { count: 'exact', head: true })
            .ilike('to_email', from.replace(/[\\%_]/g, '\\$&')).in('type', [...OPT_OUT_TYPES]).eq('status', 'sent');
          if (!count) why = 'we never sent this address an invitation or reminder';
        }
      }
      if (why) {
        await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject,
          body: '[UNSUBSCRIBE REQUEST NOT APPLIED: ' + why + '. customer_support to review.]\n\n' + fullText, html: fullHtml,
          provider_email_id: providerEmailId, attachments_count: 0, matched_existing: false, needs_review: true });
        await logRun('ok', { unsubscribe: 1, suppressed: 0, from }, 'unsubscribe email from ' + from + ' NOT applied: ' + why + '; kept for review.');
        return J({ ok: true, unsubscribe: true, suppressed: false, review: why });
      }
      const { error: supErr } = await admin.from('email_suppressions')
        .upsert({ email: from, reason: 'unsubscribe', source: 'reply' }, { onConflict: 'email', ignoreDuplicates: true });
      await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject, body: fullText, html: fullHtml,
        provider_email_id: providerEmailId, attachments_count: 0, matched_existing: false, needs_review: !!supErr });
      await logRun(supErr ? 'error' : 'ok', { unsubscribe: 1, suppressed: supErr ? 0 : 1, from },
        supErr ? ('an unsubscribe email from ' + from + ' could NOT be recorded: ' + String(supErr.message || '').slice(0, 200) + ' - kept for review so a person removes them')
               : ('unsubscribe by email: ' + from + ' is suppressed and will not be mailed again.'));
      return J({ ok: true, unsubscribe: true, suppressed: !supErr }, supErr ? 500 : 200);
    }

    const booksDeps = thinkDeps ?? defaultDeps(admin, 'resend_inbound');
    const svixKey = req.headers.get('svix-id') || req.headers.get('webhook-id') || '';
    const mail: ExpenseMail = { emailId: emailId || ('svix:' + svixKey), from, to, subject, text,
      filenames: atts.map((a) => String(a.filename || a.name || '')), mailbox: isExpenseMailbox ? 'expenses' : 'other', providerEmailId };
    const { data: booksCtx } = await admin.rpc('fn_accountant_reading_context');
    const renewals = Array.isArray(booksCtx?.renewals) ? booksCtx.renewals : [];
    const register = Array.isArray(booksCtx?.register) ? booksCtx.register : [];
    // An email to any OTHER mailbox: is it the company's own spending at all? Reasoned over the envelope and
    // the note. Held: it takes the supplier-document path below, which stores and classifies nothing on a guess,
    // and the replay hands it to the bookkeeper if it is reasoned to be an expense document.
    // Only mail that could carry a document of our spending is asked at all: it has an attachment, or it comes from
    // a permitted expense forwarder (structured facts, no word read). Anything else is plain correspondence.
    let kind: string | null = null;
    // true while what the email is, or who issued it, waits for reasoning: the accountant's queue owns it then, and
    // it is NOT also handed to the bookkeeper (one owner, no double path); the replay re-runs the sweep for it.
    let reasoningHeld = false;
    if (!receiptish && (atts.length > 0 || expenseSenderOk)) {
      kind = (await documentKind(booksDeps, mail, renewals, register)).value;
      receiptish = kind !== null && kind !== 'other';
      reasoningHeld = kind === null;
    }

    let att: { bytes: Uint8Array; name: string; mime: string; ext: string } | null = null;
    if (receiptish) {
      try {
        // 9 SEP 2026 — READ THE DOCUMENT, NOT JUST THE COVERING NOTE.
        // A receipt forwarded to this mailbox is usually a PDF with an empty note, so parsing only
        // `text` read nothing and every such receipt went to review. The attachment is fetched
        // FIRST now, sanitised by the shared sanitiser (_shared/attachment.ts, by magic bytes — the
        // receipt path was the one upload site that skipped it and wrote the sender's declared
        // content-type onto the storage object), and its text layer is read deterministically by
        // _shared/pdf_text.ts. No model is involved and none is required.
        for (const a of atts.slice(0, 8)) {
          const fn = String(a.filename || a.name || '');
          const mm = String(a.content_type || a.contentType || '');
          if (!(/pdf|^image\//i.test(mm) || /\.(pdf|jpe?g|png|webp)$/i.test(fn))) continue;
          const by = await attachmentBytes(a, emailId, rkey);
          if (!by || !by.length) continue;
          const sc = await sanitizeAndScan({ input: by, declaredMime: mm, filename: fn, allow: SAFE_UPLOAD,
                                             scan: { source: 'resend_inbound.receipt', subject: String(from || ''), filename: fn, bucket: 'receipt-files' } });
          if (!sc.ok) { await logRun('ok', { receipt: true, attachment_refused: sc.body.error, file: fn.slice(0, 80) }, 'a receipt attachment was refused (' + sc.body.error + ': ' + sc.body.detail + '); it was not archived and its text was not read'); continue; }
          const san = sc.result;
          att = { bytes: san.bytes, name: fn || ('receipt.' + san.ext), mime: san.mime, ext: san.ext };
          if (san.mime === 'application/pdf') break;   // a PDF is the receipt; an image is a fallback
        }
        let docText = '';
        if (att && att.mime === 'application/pdf') {
          docText = await pdfText(att.bytes);
          if (!docText) receiptReason = 'The attached PDF carries no text layer we can trust — it is scanned, or uses a font we cannot map — so nothing was read from it. ';
        } else if (att) {
          receiptReason = 'The receipt is an image, which has no text layer. ';
        }
        // RULING 1177 (12 Oct 2026): a scanned PDF or a photographed receipt is READ by the vision model (_shared/
        // read_every_attachment: one more asking, the gateway's second model). Held only when both askings fail.
        if (att && !docText) {
          const seen = await readEveryAttachment(att.bytes, att.name, att.mime, envGatewayVision());
          if (seen.status === 'read') { docText = seen.text.slice(0, 8000); receiptReason = ''; }
          else receiptReason += 'The vision model could not read it either (' + String(seen.reason || 'no answer').slice(0, 80) + '), so it is held for a clearer copy. ';
        }
        // A CSV export (the .csv extension is a file-format fact) is read as text; it is used only if the message is
        // reasoned to be a statement, and the reasoning reads it too.
        let csvText = '';
        for (const a of atts.slice(0, 8)) {
          if (!/\.csv$/i.test(String(a.filename || a.name || ''))) continue;
          const by = await attachmentBytes(a, emailId, rkey);
          if (by && by.length <= 5 * 1024 * 1024) { csvText = new TextDecoder().decode(by); break; }
        }
        // WHAT IS IT, read with the document: the real Mashreq statement names its bank only inside the PDF, so
        // the reasoning reads the rows statementRowText rebuilds from it (or pdf_text's text layer, or the CSV).
        const rowText = att && att.mime === 'application/pdf' ? await statementRowText(att) : '';
        if (kind === null) {
          kind = (await documentKind(booksDeps, { ...mail, docText: [rowText || docText, csvText.slice(0, 2000)].filter(Boolean).join('\n').slice(0, 4000) }, renewals, register)).value;
          reasoningHeld = kind === null;
          if (kind === null) receiptReason += 'What this document is waits for reasoning: the model is held, so it is not booked on a guess; the accountant\x27s queue replays it. ';
          else if (kind === 'other') receiptReason += 'Reasoned: this is not a document of the company\x27s own spending, so nothing was booked. ';
        }
        // 15 SEP 2026 — A BANK STATEMENT IS NOT A RECEIPT. Taken in by the SAME routine the accountant's
        // expense_sweep uses (_shared/bank_statement_intake.ts), before any receipt handling.
        if (kind === 'bank_statement' && isExpenseMailbox && expenseSenderOk) {
          const stRef = emailId ? 'resend:' + emailId : 'svix:' + svixKey;
          const stIn = await takeInStatement(admin, {
            from, subject, filenames: atts.map((a) => String(a.filename || a.name || '')),
            pdf: att && att.mime === 'application/pdf' ? att : null, csvText, docText, rowText, readNote: receiptReason,
            sourceRef: stRef, archivePath: 'bank/' + new Date().toISOString().slice(0, 10) + '/' + (emailId || svixKey || Date.now()) });
          {
            await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject, html: fullHtml, provider_email_id: providerEmailId,
              body: `[BANK STATEMENT — taken in as ${stRef}, ${stIn.lines} line(s)${stIn.problem ? ', does NOT add up, recorded unreadable' : ''}]${stIn.doc_path ? ' document: ' + stIn.doc_path : ''}\n\n` + fullText,
              attachments_count: stIn.doc_path ? 1 : 0, matched_existing: false, needs_review: !!stIn.error });
            await logRun(stIn.error ? 'error' : 'ok', { expenses_mailbox: 1, bank_statement: true, source_ref: stRef, lines: stIn.lines, adds_up: stIn.adds_up },
              stIn.error ? 'bank statement recognised but fn_accountant_bank_statement_ingest failed: ' + stIn.error
                         : 'bank statement taken in as ' + stRef + (stIn.problem ? ' — it does not add up: ' + stIn.problem : ''));
            return J({ ok: true, receipt: false, bank_statement: true, source_ref: stRef, ...stIn }, stIn.error ? 500 : 200);
          }
        }
        // the PDF text is APPENDED, so the forwarded "From:" header at the top of the note still
        // identifies the original vendor and a figure in the note still wins over one in the file
        const parseBody = docText ? (text + '\n' + docText) : text;

        let ex: any = {};
        const reading = kind ? readingOf(kind) : null;
        if (reading && !parseAmount(parseBody) && !parseAmount(subject)) {
          receiptReason += 'No amount could be read beside a currency mark, so nothing was booked and nothing was estimated. ';
        } else if (reading) {
          // Who issued it: one of the vendors the books already carry, else the name as the document writes it.
          const vendor = (await receiptVendor(booksDeps, { ...mail, docText: docText.slice(0, 4000) }, Array.isArray(booksCtx?.vendors) ? booksCtx.vendors : [])).value;
          const det = vendor ? parseReceipt({ subject, body: parseBody, vendor, period: reading.period }) : null;
          if (det) {
            ex = { is_receipt: true, vendor: det.vendor, amount: det.amount, currency: det.currency, date: det.date, period: det.period, recurring: det.recurring, vat: det.vat, trn: det.trn,
                   read_as: reading.readAs, renews_item: reading.renewsItem, note: subject + ' [reasoned: ' + kind + '; ' + det.basis + (docText ? ' src=pdf_text' : '') + ']' };
          } else if (!vendor) {
            reasoningHeld = true;
            receiptReason += 'Who issued this waits for reasoning: the model is held, so it is not booked on a guess; the accountant\x27s queue replays it. ';
          }
        }
        if (ex && ex.is_receipt === true && ex.vendor && Number(ex.amount) > 0) {
          const amount = Number(ex.amount);
          const currency = String(ex.currency||'USD').toUpperCase().replace(/[^A-Z]/g,'').slice(0,3) || 'USD';
          const charged = /^\d{4}-\d{2}-\d{2}$/.test(String(ex.date)) ? String(ex.date) : new Date().toISOString().slice(0,10);
          const vendor = String(ex.vendor).slice(0,120);
          const cad = String(ex.period)==='annual' ? 'annual' : (String(ex.period)==='one_off' ? 'one_off' : 'monthly');
          const recurring = ex.recurring === true || cad === 'monthly' || cad === 'annual';
          if (!expenseSenderOk) {
            const { data: heldRow } = await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject, body: `[receipt received but NOT booked — sender not allowlisted] ${vendor} ${amount} ${currency}`, attachments_count: 0, matched_existing: false, needs_review: true }).select('id').maybeSingle();
            // 6 Sep 2026: the bookkeeper decides whether an unknown sender's receipt is ours; the founder is not paged
            await handToBookkeeper(heldRow?.id, [], `Receipt from ${from} for ${vendor} ${amount} ${currency} was NOT booked: the sender is not on app_secrets.expense_forwarders. Decide whether it is a company expense; if so add the sender to the allowlist and book it.`);
            await logRun('ok', { receipt: true, booked: false, vendor, amount, currency }, 'receipt not booked: sender ' + from + ' is not on the expense allowlist');
            return J({ ok:true, receipt:true, booked:false, reason:'sender_not_allowlisted' });
          }

          // IDEMPOTENCY 9 Sep 2026 — KEYED ON THE MESSAGE, NOT ON WHAT WE READ FROM IT ---------
          // The guard below this one keys on vendor+date, which is derived from the extraction and
          // therefore cannot tell a redelivery that parsed differently from a genuine second
          // same-day charge. Resend's inbound email_id is stable across its own retries, so it is
          // the honest key; expense_entries.source_msg_id is unique on it.
          // THE LOOKUP IS UNFILTERED BY STATUS, deliberately. A status-filtered guard over a unique
          // key is the fn_agent_action_work_sweep trap: a previously failed row occupies the key
          // without satisfying the guard, so the guard says "go ahead", the insert then violates
          // the index, and the work is lost with no record of why. Here ANY row holding the key is
          // found, and the redelivery becomes an evidence backfill onto it.
          // It cannot deadlock: one row, one index, no second table in the statement, and the
          // storage upload finishes before the insert opens — no transaction ever waits on a fetch.
          const svixId = req.headers.get('svix-id') || req.headers.get('webhook-id') || '';
          const msgKey = emailId ? ('resend:' + emailId)
            : (svixId ? 'svix:' + svixId
                      : 'digest:' + (await sha256hex([from, to, subject, vendor, charged, amount, currency].join('|'))).slice(0, 32));
          const { data: priorRows } = await admin.from('expense_entries').select('id,doc_path,amount,currency').eq('source_msg_id', msgKey).limit(1);
          const priorRow: any = priorRows?.[0] || null;

          // DEDUP FIX 19 Jul 2026 -------------------------------------------------------------
          // This used to match vendor + charged_on + AMOUNT. Resend RETRIES a delivery that timed
          // out or errored, and the extractor does not always read an identical amount from the
          // same email twice (one pass read a Resend renewal as 20 USD, a re-delivery of the very
          // same receipt read it as 76.39 AED). Because the amounts differed, the old guard let a
          // SECOND expense through and the same real cost was counted twice.
          // Now ANY existing entry for the same vendor on the same date blocks the booking. If the
          // amount differs it is flagged for review rather than silently booked - a genuine second
          // same-day charge from one vendor is possible, but rare enough to deserve a human look,
          // and under-booking with an alert is far safer than silently double-counting costs.
          const { data: sameDay } = await admin.from('expense_entries').select('id,amount,currency,doc_path').eq('vendor', vendor).eq('charged_on', charged).limit(5);
          // v15 FIX 3 Aug 2026 - RECEIPT ARCHIVE BACKFILL --------------------------------------
          // v14 returned from this guard BEFORE any upload was attempted. That made the remedy
          // printed by v_expense_receipt_gap - "re-forward the vendor email to the inbound address
          // to retry" - a no-op: the re-forward was discarded as a duplicate and the entry kept
          // doc_path NULL for ever. Returning non-200 on a failed archive would not help either,
          // because Resend's own redelivery lands on this same guard. A receipt whose expense
          // entry is missing its document is not a duplicate to discard, it IS the retry - so fall
          // through and archive it against the EXISTING row instead of inserting a second one.
          // Restricted to an exact vendor+date+amount+currency match, because a same-day entry
          // with a DIFFERENT amount may be a genuine second charge and attaching this document to
          // it would file the wrong evidence against a real expense.
          // 9 Sep 2026: the row holding this message's key wins outright. It IS this receipt, so a
          // redelivery repairs it (missing document, missing GL posting) rather than being reported
          // as somebody else's duplicate.
          const gapRow: any = priorRow || (sameDay || []).find((x:any) => !x.doc_path && Number(x.amount) === amount && String(x.currency||'').toUpperCase() === currency) || null;
          if (!priorRow && sameDay && sameDay.length && !gapRow) {
            const exact = sameDay.some((x:any) => Number(x.amount) === amount && String(x.currency||'').toUpperCase() === currency);
            const { data: dupRow } = await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject, body: `[receipt dup] ${vendor} ${amount} ${currency} ${charged}${exact?'':' (amount differs from existing entry - flagged)'}`, attachments_count: 0, matched_existing: false, needs_review: !exact }).select('id').maybeSingle();
            // 6 Sep 2026: a same-day different-amount receipt is the bookkeeper's call (second charge or re-read), not the founder's
            if (!exact) await handToBookkeeper(dupRow?.id, [], `A receipt for ${vendor} dated ${charged} showing ${amount} ${currency} was NOT booked: an expense from that vendor already exists on that date (${sameDay.map((x:any)=>x.amount+' '+x.currency).join(', ')}). Usually the same receipt read twice; if it is a genuine second charge, book it.`);
            await logRun('ok', { receipt: true, deduped: true, vendor, amount, currency, exact_match: exact }, exact ? 'duplicate receipt ignored - an identical expense was already booked for this vendor and date.' : ('receipt NOT booked: an expense from ' + vendor + ' already exists on ' + charged + ' with a DIFFERENT amount (' + sameDay.map((x:any)=>x.amount+' '+x.currency).join(', ') + ' vs ' + amount + ' ' + currency + '). Flagged for review - most likely a redelivery read differently by the extractor, but could be a real second charge.'));
            return J({ ok:true, receipt:true, deduped:true, vendor, amount, currency });
          }

          // 9 Sep 2026: the attachment was already fetched and SANITISED above (magic bytes, EXIF
          // stripped). Re-fetching it here was a second download of the same file and, worse, the
          // old loop wrote the SENDER'S declared content-type onto the storage object — this was
          // the one upload site in the function that did not go through _shared/attachment.ts.
          // 9 SEP 2026 — EVERY EXPENSE RECORD CARRIES A DOCUMENT YOU CAN OPEN, AND THE RECORD SAYS
          // WHICH KIND IT IS. The founder: "i wanna be able to click any record and see the actual
          // invoice or receipt or email print pdf if none exist".
          //
          // Until today the no-attachment branch stored `receipt.html`, text/html — the raw message
          // body in a <pre>. Five of the nine receipts booked through this function held exactly
          // that. It is not a document anyone can hand to an auditor, and nothing in the schema
          // could tell it apart from the vendor's real invoice: both were just "the doc_path".
          // Now the fallback is a PDF PRINT of the email, rendered by pdf_native, and doc_kind
          // records WHICH of the two classes of evidence this row holds. The HTML upload survives
          // only as the fallback-of-the-fallback, so a pdf_native outage degrades the document
          // rather than losing the email.
          let docPath: string | null = null;
          let docName = 'receipt.html';
          let docType = 'text/html';
          let docKind: 'vendor_document' | 'email_print' = 'email_print';
          let docNote: string | null = null;
          let upErr = ''; let upAttempts = 0;

          if (att) {
            docName = att.name; docType = att.mime; docKind = 'vendor_document';
            docNote = "The vendor's own file, taken off the source email (Resend inbound " + (emailId || 'delivery') + ').';
            // v15: three attempts. A refused archive is usually transient, and a receipt that is
            // separated from the expense it evidences is a VAT-record gap, not a cosmetic one.
            for (let attempt = 1; attempt <= 3 && !docPath; attempt++) {
              upAttempts = attempt;
              const rpN = `receipts/${charged}/${Date.now()}_${vendor.replace(/[^A-Za-z0-9._-]/g,'_')}.${att.ext}`;
              try { const up = await admin.storage.from('receipt-files').upload(rpN, att.bytes, { contentType: docType, upsert: true }); if (!up.error) docPath = rpN; else upErr = String(up.error.message||'').slice(0,150); }
              catch (e) { upErr = String((e as Error)?.message||e).slice(0,150); }
              if (!docPath && attempt < 3) await new Promise((r) => setTimeout(r, 400 * attempt));
            }
          } else {
            upAttempts = 1;
            const printed = await emailPrintPdf(admin, SUPA_URL, {
              entryId: gapRow?.id ?? null, vendor, amount, currency, chargedOn: charged,
              sourceMsgId: msgKey, subject, from, to, date: new Date().toISOString(),
              text, html: String(d.html || ''), attachmentNames: [],
            });
            if (printed.ok) {
              // pdf_native NAMED this path; it is used exactly as returned.
              docPath = printed.path; docName = printed.name; docType = 'application/pdf';
              docNote = 'The source email carried no vendor file, so this is a PDF print of the email itself.';
              if (printed.glyphsDropped) await logRun('error', { receipt: true, glyphs_dropped: printed.glyphsDropped, entry: msgKey }, 'the email print for ' + vendor + ' dropped ' + printed.glyphsDropped + ' character(s) the brand fonts could not render; the invisible inbox padding is stripped before rendering, so this count is real content missing from the printed document.');
            } else {
              const html = String((d.html)|| text || subject);
              const bytes = new TextEncoder().encode('<meta charset=\"utf-8\"><pre style=\"font:14px/1.5 monospace;white-space:pre-wrap\">'+html.replace(/</g,'&lt;')+'</pre>');
              docNote = 'The source email carried no vendor file, and the email could not be printed to PDF ('
                + printed.reason + '), so the message body is archived as HTML instead.';
              for (let attempt = 1; attempt <= 3 && !docPath; attempt++) {
                upAttempts = attempt;
                const rpN = `receipts/${charged}/${Date.now()}_${vendor.replace(/[^A-Za-z0-9._-]/g,'_')}.html`;
                try { const up = await admin.storage.from('receipt-files').upload(rpN, bytes, { contentType: 'text/html', upsert: true }); if (!up.error) docPath = rpN; else upErr = String(up.error.message||'').slice(0,150); }
                catch (e) { upErr = String((e as Error)?.message||e).slice(0,150); }
                if (!docPath && attempt < 3) await new Promise((r) => setTimeout(r, 400 * attempt));
              }
            }
          }
          const ext = docType === 'application/pdf' ? 'pdf' : (att ? att.ext : 'html');
          // ---- The two things every booked receipt owes the company ----
          // 1. THE LEDGER. fn_gl_sync_business() already knows how to post an expense_entries row
          //    (gl_expense_map -> account, 6300 fallback, USD at gl_settings.usd_to_aed) — but
          //    cron.job holds exactly one job in this project and it is not that one, so nothing
          //    ever calls it and a booked expense would never reach gl_journal. fn_expense_post_to_gl
          //    posts THIS entry under the same source/source_ref the bulk routine uses, so the two
          //    can never double-post, and it splits stated VAT to 1150 (VAT Recoverable), which
          //    nothing in the estate had ever debited.
          //    ponytail: posting inline is the entry point that exists; if the ledger ever grows
          //    enough that this matters, schedule fn_gl_sync_business and delete the call.
          // 2. THE EVIDENCE OFF-SITE. doc_backups is the Sales Engineer's existing filing contract
          //    and dropbox_backup reads it by status, not by entity, so an 'expense' row needs no
          //    change there. dedupe_key makes a redelivery a no-op.
          const fileAndPost = async (entryId: number | null | undefined, dPath: string | null, dName: string, dType: string) => {
            if (!entryId) return { journal: null as number | null, filed: false };
            const { data: jid, error: glErr } = await admin.rpc('fn_expense_post_to_gl', { p_entry_id: entryId });
            if (glErr) await logRun('error', { entry_id: entryId }, 'expense #' + entryId + ' was booked but did NOT reach the ledger: fn_expense_post_to_gl failed with ' + String(glErr.message || '').slice(0, 200) + '. gl_journal understates costs until it is posted.');
            let filed = false;
            if (dPath) {
              const { error: bkErr } = await admin.from('doc_backups').insert({
                entity: 'expense', entity_id: String(entryId), doc_type: 'Receipt',
                bucket: 'receipt-files', path: dPath, file_name: dName.slice(0, 180),
                dropbox_path: `/QuotesDone Backup/Finance/Receipts/${charged.slice(0, 7)}/${dbxSafe(vendor)} ${charged} - ${dbxSafe(dName)}`,
                source: 'storage', dedupe_key: 'E:' + entryId + ':receipt:' + dPath,
              });
              filed = !bkErr;   // a unique-key conflict on a redelivery is the guard working
            }
            return { journal: (jid as number | null) ?? null, filed };
          };

          if (gapRow) {
            // BACKFILL ONLY. The expense is already booked and the subscription row already
            // exists; attaching the evidence must not book it a second time and must not re-run
            // the subscription upsert. Nothing below this branch runs.
            if (docPath && !gapRow.doc_path) await admin.from('expense_entries').update({ doc_path: docPath, doc_name: docName.slice(0,180), doc_content_type: docType, doc_kind: docKind, doc_note: docNote, source_msg_id: msgKey }).eq('id', gapRow.id);
            // idempotent: posts only if this entry has no journal yet, files only if not filed yet
            const rep = await fileAndPost(gapRow.id, docPath || gapRow.doc_path || null, docName, docType);
            await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject, body: `[receipt archive ${docPath?'backfilled':'RETRY FAILED'}] entry #${gapRow.id} ${vendor} ${amount} ${currency} on ${charged}${rep.journal?` journal #${rep.journal}`:''}`, attachments_count: docPath?1:0, matched_existing: true, needs_review: !docPath });
            await logRun(docPath ? 'ok' : 'error', { receipt: true, booked: false, archive_backfill: true, entry_id: gapRow.id, vendor, amount, currency, doc_archived: !!docPath, upload_attempts: upAttempts },
              docPath ? ('receipt archive backfilled onto expense_entries#' + gapRow.id + ' - no second expense was booked')
                      : ('receipt archive retry FAILED for expense_entries#' + gapRow.id + ' after ' + upAttempts + ' attempt(s): ' + upErr + '. The expense is still booked without its document; v_expense_receipt_gap will keep reporting it.'));
            return J({ ok: true, receipt: true, archive_backfill: true, entry_id: gapRow.id, vendor, amount, currency, doc: docPath });
          }
          // The category is what files this against the chart of accounts: 'Subscription' and
          // 'Usage' are both rows in gl_expense_map (-> 6000 Software & AI). Nothing here invents
          // an account code; the mapping table decides, with 6300 General & Administrative as the
          // fallback for a category the table does not carry.
          const vatAmt = Number(ex.vat) > 0 && Number(ex.vat) < amount ? Number(ex.vat) : null;
          const trn = /^\d{15}$/.test(String(ex.trn||'')) ? String(ex.trn) : null;
          const { data: insRow } = await admin.from('expense_entries')
            .upsert({ vendor, category: recurring ? 'Subscription' : 'Usage', amount, currency, charged_on: charged,
              note: ('auto from forwarded ' + (recurring?'subscription':'receipt') + ': ' + String(ex.note||subject)).slice(0,300),
              source: 'receipt', doc_path: docPath, doc_name: docName.slice(0,180), doc_content_type: docType,
              doc_kind: docPath ? docKind : null, doc_note: docPath ? docNote : null,
              source_msg_id: msgKey, vat_amount: vatAmt, vendor_trn: trn, read_as: ex.read_as ?? null, renews_item: ex.renews_item ?? null },
              { onConflict: 'source_msg_id', ignoreDuplicates: true })
            .select('id').maybeSingle();
          let entryId: number | null = (insRow?.id as number | undefined) ?? null;
          if (!entryId) {
            // a concurrent redelivery won the unique key between the lookup and this insert; read
            // its row rather than inventing a second expense
            const { data: won } = await admin.from('expense_entries').select('id').eq('source_msg_id', msgKey).limit(1);
            entryId = (won?.[0]?.id as number | undefined) ?? null;
          }
          const posted = await fileAndPost(entryId, docPath, docName, docType);
          let bookedSub = false;
          if (recurring) {
            const erow = { vendor, category: 'Subscription', description: String(ex.note||subject).slice(0,300), amount, currency, cadence: cad, expense_date: charged, active: true, source: 'email_forward', confidence: 'medium', note: ('auto from forwarded subscription receipt' + (docPath?' (document archived)':'')) };
            // the SAME vendor by identity, never a LIKE pattern (founder_instruction 890; _shared/expense_mailbox.ts)
            const ex0 = await registerRowsFor(admin, vendor);
            if (ex0 && ex0.length) await admin.from('expenses').update(erow).eq('id', ex0[0].id);
            else await admin.from('expenses').insert(erow);
            bookedSub = true;
          }
          await admin.from('inbound_messages').insert({ from_email: from, to_email: to, subject, body: `[expense ${recurring?'subscription':'one-off'}] ${vendor} ${amount} ${currency} on ${charged}${docPath?' +'+ext:''}` + '\n\n' + fullText, html: fullHtml, provider_email_id: providerEmailId, attachments_count: docPath?1:0, matched_existing: false, needs_review: false });
          try{ await requestDelivery(admin, { type:'expense_logged', to_email: owner, to_role:'admin', channel:'email', subject:`Expense logged: ${vendor} ${amount} ${currency}`, body:`Logged from your forwarded email.\n\nVendor: ${vendor}\nAmount: ${amount} ${currency}\nDate: ${charged}\nType: ${recurring?(cad+' subscription'):'one-off'}` }); }catch(_e){}
          // v15: keyed on docPath, not upErr. upErr now holds the LAST error of up to three
          // attempts, so a retry that eventually succeeded would otherwise be reported as failed -
          // and fn_watch_failed_runs pages on any error row.
          await logRun(docPath ? 'ok' : 'error', { receipt: true, booked: true, entry_id: entryId, vendor, amount, currency, vat: vatAmt, trn: !!trn, recurring, cadence: cad, doc_archived: !!docPath, dropbox_queued: posted.filed, gl_journal: posted.journal, upload_attempts: upAttempts, msg_key: msgKey }, docPath ? '' : ('expense booked but the receipt document failed to archive after ' + upAttempts + ' attempt(s): ' + upErr + '. Re-forward the vendor email to the inbound address - v15 will archive it onto the existing entry without booking a second expense.'));
          return J({ ok: true, receipt: true, entry_id: entryId, vendor, amount, currency, vat: vatAmt, trn, charged_on: charged, recurring, cadence: cad, booked_subscription: bookedSub, doc: docPath, gl_journal: posted.journal });
        }
      } catch (e) { await logRun('error', { from, subject }, 'receipt handling threw, fell through to document handling: ' + String((e as Error)?.message||e).slice(0,200)); }
    }

    // ---- HELD FOR REVIEW: a receipt we could not read is never guessed at ----
    // Reaching here from the expenses mailbox means no amount could be read with confidence. The
    // seat's own grant says "A receipt that cannot be read is held for review, never guessed at":
    // nothing is defaulted, nothing is estimated, nothing is booked at zero. It must ALSO stop
    // here rather than fall through to the supplier-document branch below — mail to the expenses
    // mailbox has nothing to do with a supplier record, and that fall-through is exactly how four
    // of the founder's own receipts became "Reviews pending" on his screen in early September.
    // The document is still archived, in receipt-files where the accountant will look for it.
    if (isExpenseMailbox) {
      let heldPath: string | null = null;
      if (att) {
        const hp = `receipts/held/${new Date().toISOString().slice(0,10)}/${Date.now()}_${att.name.replace(/[^A-Za-z0-9._-]/g,'_')}`;
        const up = await admin.storage.from('receipt-files').upload(hp, att.bytes, { contentType: att.mime, upsert: true });
        if (!up.error) heldPath = hp;
      }
      const { data: heldRow } = await admin.from('inbound_messages').insert({
        from_email: from, to_email: to, subject, html: fullHtml, provider_email_id: providerEmailId,
        body: `[HELD — nothing booked: ${(receiptReason || 'no amount could be read').slice(0, 200)}]${heldPath ? ' document: receipt-files/' + heldPath : ' (no readable attachment)'}\n\n` + fullText,
        attachments_count: heldPath ? 1 : 0, matched_existing: false, needs_review: true,
        // Held for the accountant's reasoning (the model hold): the row is the accountant's while it waits, so it never
        // reads as the founder's (receipts_never_wait_on_the_founder, 24 Sep 2026: the Anthropic receipt, row 161).
        ...(reasoningHeld ? { owner_role: 'accountant' } : {}),
      }).select('id').maybeSingle();
      if (!reasoningHeld) await handToBookkeeper(heldRow?.id, [], (receiptReason || 'No amount could be read from this email.') + (heldPath ? ' The document is archived at receipt-files/' + heldPath + '. Read it, then book the expense in expense_entries (source \'receipt\') and post it with fn_expense_post_to_gl.' : ' No attachment could be read, so ask for a re-forward.'));
      await logRun('ok', { expenses_mailbox: 1, receipt: true, booked: false, held: true, doc_archived: !!heldPath, from, subject }, 'receipt HELD for review, not guessed at: ' + (receiptReason || 'no amount could be read').slice(0, 300));
      return J({ ok: true, receipt: true, booked: false, held: true, reason: kind === null ? 'awaiting_reasoning' : kind === 'other' ? 'not_an_expense_document' : 'amount_unreadable', doc: heldPath });
    }

    // ---- Supplier document handling (store + classify + AUTO-EXTRACT + apply) ----
    let lead: any = null;
    if (orSafeEmail(from)) { const { data } = await admin.from('leads').select('id,company_name,claimed_by,emirate,trn,services,products,capability_summary,service_emirates,catalog_doc_paths,verified').or(`email.eq.${from},claimed_by.eq.${from}`).limit(1).maybeSingle(); lead = data; }
    let stored = 0; const reviews: number[] = []; const appliedSummary: string[] = []; const unreadDocs: string[] = [];
    let lostAttachments = 0; let uploadFailures = 0; let classifyFailures = 0; let refusedAttachments = 0; let classifySkipped = 0;
    for (const a of atts.slice(0,6)) {
      const fname = String(a.filename || a.name || 'document').slice(0,180);
      const mime = String(a.content_type || a.contentType || 'application/octet-stream');
      const rawBytes = await attachmentBytes(a, emailId, rkey);
      // previously a silent 'continue' - a supplier's trade licence could vanish with no record
      if (!rawBytes) { lostAttachments++; continue; }
      // AUDIT 9.1 (3 Aug 2026): mime came from the sender's content_type header and was written
      // onto the storage object and into the model prompt unexamined. Sniff the bytes, refuse
      // anything that is not a PDF or a real image, strip EXIF/GPS from photographed documents.
      // A refusal is counted separately from a LOST attachment: they are different failures and an
      // operator needs to tell "we would not accept it" from "we could not fetch it".
      const __sc = await sanitizeAndScan({ input: rawBytes, declaredMime: mime, filename: fname, allow: SAFE_UPLOAD,
                                           scan: { source: 'resend_inbound.supplier_doc', subject: String(from || ''), filename: fname, bucket: 'supplier-docs' } });
      if (!__sc.ok) { refusedAttachments++; continue; }
      const __san = __sc.result;
      const bytes = __san.bytes;
      const sniffedMime = __san.mime;
      const path = `inbound/${lead?.id||'unknown'}/${Date.now()}_${fname.replace(/[^A-Za-z0-9._-]/g,'_')}`;
      const up = await admin.storage.from('supplier-docs').upload(path, bytes, { contentType: sniffedMime, upsert: true });
      // the upload result was never checked: a failed upload still counted as stored
      if (up && (up as any).error) { uploadFailures++; continue; }
      stored++;
      let ai:any = { relevant:null, category:'other', summary:'', suggested_field:null, confidence:'low' };
      if (key) {
        const content:any[] = [{ type:'text', text:`Email from supplier ${lead?.company_name||from}. Subject: ${subject}. Body: ${text}. Attached file: ${fname} (${mime}). Classify this document.` }];
        if (/^image\//.test(sniffedMime)) { try { content.push({ type:'image_url', image_url:{ url:`data:${sniffedMime};base64,${bytesToB64(bytes)}` } }); } catch {} }
        // ZERO-COST GUARD (16 Aug 2026). This is the estate's only direct
        // POST to OpenRouter's /chat/completions - real paid inference, on a path an inbound
        // supplier email triggers, and it consulted nothing. Every other caller reaches the
        // provider through ai_gateway, which calls fn_llm_preflight. This one asks the same
        // question the gateway asks, and a gate it cannot read is CLOSED.
        let paidAllowed = false;
        { const g = await paidProviderGate(admin, MODEL); paidAllowed = g.allowed; }
        if (['1', 'true', 'yes', 'on'].includes(String(Deno.env.get('NO_PAID_AI') ?? Deno.env.get('OPENROUTER_DISABLED') ?? '').toLowerCase())) paidAllowed = false;
        if (!paidAllowed) {
          // Not a failure: the document is stored and the lead is recorded either way. The
          // classification is simply absent, and says so, rather than being guessed for free.
          ai = { ...ai, summary: 'skipped_due_to_zero_cost_mode: attachment stored and linked; no classification, because every paid inference route is held.' };
          classifySkipped++;
        } else try {
          // 6 SEP 2026 (MASTER_PLAN A6): through the one door. The gateway has taken a full OpenAI
          // `messages` array, image parts included, since 11 Aug (inferCaps marks vision); the
          // "does not proxy image payloads" comment that kept this call direct was stale. The
          // gateway runs fn_llm_preflight, the hold, the budget and the cost ledger; the direct
          // POST above ran none of them and was the estate's last inference call outside it.
          const r = await classify(SYS, '', 500, '', { messages: [{ role: 'system', content: SYS }, { role: 'user', content }] });
          if (r.content) ai = { ...ai, ...parseJson(r.content) }; else classifyFailures++;
        } catch { classifyFailures++; }
      }
      const cat = String(ai.category||'other');
      let extracted:any = null; const fields:string[] = [];
      if (lead && inbSecret) {
        if (cat === 'trade_license') {
          const ex = await extractDoc('license', bytes, mime, fname, inbSecret);
          if (!ex?.doc) unreadDocs.push(fname);   // ruling 1177: nothing read at all -> ask for a clearer copy (a low-confidence read WAS read; it goes to review)
          if (ex && ex.doc) { extracted = ex.doc; const dc = ex.doc; const u:any = { license_doc_path: path, license_doc_name: fname, doc_extracted_at: new Date().toISOString(),
              // The name printed on this licence (a scan is read by the vision model); null = not read, and the
              // sales engineer's review then holds the registration for a human (licence_name_unread).
              licence_legal_name: licenceNameFromModel(dc) };
            if (dc.confidence !== 'low') {
              if (dc.license_number) { u.trade_license_no = dc.license_number; fields.push('licence no '+dc.license_number); }
              if (dc.license_authority) { u.license_authority = dc.license_authority; fields.push('authority'); }
              if (dc.expiry_date) { u.license_expiry = dc.expiry_date; fields.push('expiry '+dc.expiry_date); }
              if (dc.city) u.license_city = dc.city;
              if (dc.emirate && !lead.emirate) u.emirate = dc.emirate;
              if (dc.trn && !lead.trn) { u.trn = dc.trn; fields.push('TRN'); }
            }
            // Review of #962: this write's result was discarded. A licence number another claimed company
            // holds is now set aside (the document path and expiry are still written) and sent to a human.
            const w = await updateLeadSettingAsideClashingLicence(admin as unknown as LeadWriter, lead.id, u, 'resend_inbound');
            if (w.licenceSetAside) { const i = fields.findIndex((f) => f.startsWith('licence no ')); if (i >= 0) fields[i] = 'licence no set aside for review (held by another claimed company)'; }
            if (w.error) { console.error('resend_inbound: licence readings not saved —', String(w.error.message ?? '')); fields.length = 0; }
          }
        } else if (cat === 'company_profile' || cat === 'catalogue') {
          const ex = await extractDoc('profile', bytes, mime, fname, inbSecret);
          if (!ex?.profile) unreadDocs.push(fname);
          const u:any = { doc_extracted_at: new Date().toISOString() };
          if (cat === 'company_profile') u.company_profile_doc_path = path;
          if (cat === 'catalogue') { const cur = Array.isArray(lead.catalog_doc_paths)?lead.catalog_doc_paths:[]; u.catalog_doc_paths = [...cur, path]; }
          if (ex && ex.profile) { extracted = ex.profile; const pr = ex.profile;
            if (pr.confidence !== 'low') {
              if (pr.summary && !lead.capability_summary) { u.capability_summary = pr.summary; fields.push('capability'); }
              if (Array.isArray(pr.services) && pr.services.length && !lead.services) u.services = pr.services;
              if (Array.isArray(pr.products) && pr.products.length && !lead.products) u.products = pr.products;
              if (Array.isArray(pr.emirates) && pr.emirates.length && !(Array.isArray(lead.service_emirates)&&lead.service_emirates.length)) u.service_emirates = pr.emirates;
            }
          }
          await admin.from('leads').update(u).eq('id', lead.id);
        }
        if (fields.length) appliedSummary.push(fname + ' → ' + fields.join(', '));
      }
      const { data: rev } = await admin.from('doc_reviews').insert({ lead_id: lead?.id||null, from_email: from, subject, file_name: fname, file_path: path, mime, ai_relevant: ai.relevant, ai_category: ai.category, ai_summary: String(ai.summary||'').slice(0,1000), ai_suggested_field: ai.suggested_field, ai_confidence: ai.confidence, status: 'pending', auto_applied: fields.length>0, extracted: extracted }).select('id').maybeSingle();
      if (rev?.id) reviews.push(rev.id);
    }
    // 28 SEP 2026 (customer_support): a mail with no document to apply is correspondence, and email_triage answers
    // it. It was needs_review=false, which email_triage's selection excludes, so a customer's question was stored
    // and never read. raw keeps what the reply and noAutoReply need (_shared/customer_mail.ts).
    const hv = (k: string) => { const v = hdrs?.[k] ?? hdrs?.[k.toLowerCase()]; return v == null ? null : String(Array.isArray(v) ? v[0] : v); };
    // WHO SENT IT IS PROVEN, NOT READ OFF THE FROM HEADER (customer_support, 19 Oct 2026, review of #1498): email_triage
    // gives a reply the sender's own account only when the receiving server authenticated the From domain (aligned
    // DMARC, DKIM or SPF pass, fromDomainAuthenticated). The webhook is metadata-only, so the headers are read when absent.
    const authHdrs = hdrs?.['authentication-results'] ? hdrs : ((resendEmailId && rkey) ? await (async () => { const f: any = await fetchInboundEmail(resendEmailId, rkey); return (f?.data || f)?.headers; })() : null);
    const rawFacts = { message_id: String(d.message_id || hv('message-id') || '') || null, auto_submitted: hv('auto-submitted'),
      // 27 Oct 2026 (marketing): the other auto-reply marks, so an out-of-office never takes an invited lead's one
      // invite.reply handoff (fn_marketing_files_invite_reply reads them)
      x_auto_response_suppress: hv('x-auto-response-suppress'), precedence: hv('precedence'), x_autoreply: hv('x-autoreply') ?? hv('x-autorespond'),
      in_reply_to: hv('in-reply-to'), references: hv('references'),
      content_type: hv('content-type'), sender_authenticated: fromDomainAuthenticated(authHdrs?.['authentication-results'], from), calendar: atts.some((a: any) => /text\/calendar|application\/ics/i.test(String(a.content_type || a.contentType || '')) || /\.ics$/i.test(String(a.filename || ''))) };
    const { data: inbRow } = await admin.from('inbound_messages').insert({ lead_id: lead?.id||null, from_email: from, to_email: to, subject, body: fullText, html: fullHtml, provider_email_id: providerEmailId, attachments_count: stored, matched_existing: !!lead, needs_review: appliedSummary.length===0 && (stored>0 || !receiptish), raw: rawFacts }).select('id').maybeSingle();
    // Answered within the minute, not on the 15-minute tick: email_triage is woken for this one message.
    if (inbRow?.id && appliedSummary.length === 0 && !receiptish && (await sec('email_triage_enabled')) === 'true') {
      const wake = timedFetch(`${SUPA_URL}/functions/v1/email_triage`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ __secret: await sec('cred_fn_resend_inbound'), message_id: inbRow.id }) }, 55_000).then((r) => r.body?.cancel()).catch(() => {});
      (globalThis as any).EdgeRuntime?.waitUntil?.(wake);
    }
    // 6 Sep 2026: a receipt-ish email that reached this path was NOT booked. It is finance's work from here —
    // one org_task for the bookkeeper, and the rows carry that owner so neither OS surface shows them to the founder.
    if (receiptish && !lead && !reasoningHeld) await handToBookkeeper(inbRow?.id, reviews, receiptReason || 'The receipt path did not book this email.');
    if (lead && appliedSummary.length) {
      try{ await requestDelivery(admin, { type:'supplier_doc_applied', to_email: owner, to_role:'admin', lead_id: lead.id, channel:'email', subject:`Supplier record auto-updated: ${lead.company_name||('Lead #'+lead.id)}`, body:`A document from ${from} was read and applied to ${lead.company_name||('Lead #'+lead.id)}:\n\n${appliedSummary.join('\n')}\n\nReview it in the CRM if needed.` }); }catch(_e){}
    }
    if (from && from !== 'onboarding@resend.dev' && stored>0 && lead) await requestDelivery(admin, { type:'doc_received', to_email: from, to_role:'supplier', lead_id: lead?.id||null, subject:'We received your document', body: unreadDocs.length
      // RULING 1177 (12 Oct 2026): this said 'updated your records' even when nothing could be read. A document both the
      // code and the model could not read is now answered with a clearer-copy request (suppliers: always English), and
      // the clearer copy, sent to the same address, is read by this same path when it arrives.
      ? `Thank you${lead?.company_name?' '+lead.company_name:''} — we received ${stored} document(s). ` + unreadDocs.map((n) => clearerCopyAsk('supplier', 'en', n)).join(' ')
      : `Thank you${lead?.company_name?' '+lead.company_name:''} — we received ${stored} document(s) and ${appliedSummary.length ? 'updated your records' : 'our team will add them to your profile'}.`, status:'queued' });
    const counts = { from, matched_lead: lead?.id||null, attachments: atts.length, stored, refused_attachments: refusedAttachments, lost_attachments: lostAttachments, upload_failures: uploadFailures, classify_failures: classifyFailures, classify_skipped_zero_cost: classifySkipped, applied: appliedSummary.length, signature_verified: 1 };
    if (lostAttachments || uploadFailures) await logRun('error', counts, 'INBOUND DOCUMENTS LOST - ' + lostAttachments + ' attachment(s) could not be downloaded from Resend and ' + uploadFailures + ' failed to upload to storage. Sender: ' + from + ', subject: ' + subject.slice(0, 120));
    else if (atts.length || stored) await logRun('ok', counts, appliedSummary.length ? ('applied: ' + appliedSummary.join('; ').slice(0, 300)) : (lead ? '' : 'no matching lead for sender'));
    return J({ ok: true, matched_lead: lead?.id||null, stored, reviews, applied: appliedSummary });
  } catch (e) { const m = String((e as Error)?.message || e); await logRun('error', {}, 'exception (inbound email dropped): ' + m); return J({ error: m }, 500); }
});
if (!Deno.env.get('RESEND_INBOUND_NO_SERVE')) Deno.serve(handler);
