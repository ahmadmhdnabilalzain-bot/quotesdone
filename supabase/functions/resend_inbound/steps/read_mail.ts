// resend_inbound step: the payload read into one mail (body, attachments, headers, parties) and the redelivery short-cut. Moved out of index.ts's handler unchanged (9 Nov 2026);
// the handler in index.ts calls the steps in the order they ran inline, each handing on what the next one reads.
import type { Out as AuthenticateOut } from './authenticate.ts';
import { M365_INBOUND_PREFIX } from '../../_shared/m365_reply_inbox.ts';
import { admin, J, sec, logRun } from '../lib/runtime.ts';
import { addr, pickBody } from '../lib/mail_parse.ts';
import { fetchInboundEmail, RESEND_READ_MS } from '../lib/inbound_fetch.ts';

export async function readMail(ctx: AuthenticateOut) {
    const { raw } = ctx;
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
      // A READ THAT FAILED IS READ AGAIN (it_engineer, 15 Nov 2026). Resend's webhook is metadata only, so with no body in the
      // delivery a failed read left nothing to read: a receipt was held as "no amount", a supplier's mail stored empty. This
      // runs inside the queue's reader now (lib/queue.ts), where a throw is a failed attempt read again after a backoff and,
      // on the fifth, a message handed to its seat with this reason. A delivery that carried its own body goes on as before.
      else if (emailId && !text) throw new Error('the e-mail could not be read from Resend (GET /emails/inbound/' + resendEmailId + ' answered with an error or not within ' + Math.round(RESEND_READ_MS / 1000) + ' s), and the delivery carries no body of its own');
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
    return { ...ctx, d, emailId, resendEmailId, rkey, key, inbSecret, text, atts, hdrs, fullText, fullHtml, providerEmailId, from, to, subject, toLocal, adminList, fwdList, expenseSenderOk, owner };
}
export type Out = Exclude<Awaited<ReturnType<typeof readMail>>, Response>;
