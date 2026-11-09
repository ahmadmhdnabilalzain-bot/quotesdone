// resend_inbound step: the founder's replies to the social calendar, an approval email and the video idea plan. Moved out of index.ts's handler unchanged (9 Nov 2026);
// the handler in index.ts calls the steps in the order they ran inline, each handing on what the next one reads.
import type { Out as ReadMailOut } from './read_mail.ts';
import { fromDomainAuthenticated } from '../../_shared/suppression_policy.ts';
import { approvalTokenOf, calendarTokenOf, isCalendarReply, ownWords, planTokenOf, replyIntent } from '../../_shared/marketing_calendar_mail.ts';
import { admin, J, logRun } from '../lib/runtime.ts';
import { fetchInboundEmail } from '../lib/inbound_fetch.ts';

export async function marketingReplies(ctx: ReadMailOut) {
    const { to, subject, d, resendEmailId, rkey, from, providerEmailId, fullText, fullHtml, atts } = ctx;
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
    return { ...ctx };
}
export type Out = Exclude<Awaited<ReturnType<typeof marketingReplies>>, Response>;
