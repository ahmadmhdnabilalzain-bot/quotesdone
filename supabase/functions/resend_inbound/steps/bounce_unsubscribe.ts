// resend_inbound step: a bounce that came back as mail, and an unsubscribe by email. Moved out of index.ts's handler unchanged (9 Nov 2026);
// the handler in index.ts calls the steps in the order they ran inline, each handing on what the next one reads.
import { whereAddress } from '../../_shared/address_filter.ts';
import type { Out as ExpenseGateOut } from './expense_gate.ts';
import { permanentlyBouncedAddress } from '../../_shared/mailbox_bounce.ts';
import { isUnsubscribeRequest } from '../../_shared/unsubscribe_mailbox.ts';
import { replyStopRefusal, senderAuthenticated } from '../../_shared/suppression_policy.ts';
import { admin, J, logRun } from '../lib/runtime.ts';
import { fetchInboundEmail } from '../lib/inbound_fetch.ts';
import { EXPENSE_MAILBOX } from '../lib/receipt_consts.ts';

export async function bounceUnsubscribe(ctx: ExpenseGateOut) {
    const { from, fullText, isExpenseMailbox, to, subject, adminList, fwdList, d, resendEmailId, rkey, providerEmailId, fullHtml } = ctx;
    // ---- A BOUNCE THAT COMES BACK AS MAIL (1 Nov 2026, sales_engineer): _shared/mailbox_bounce.ts ----
    const bounced = permanentlyBouncedAddress(from, fullText);
    if (bounced) {
      const { data: invited } = await whereAddress(admin.from('notifications').select('lead_id'), 'to_email', bounced).in('type', ['supplier_invite', 'supplier_invite_nudge']).eq('status', 'sent').limit(1);
      if (invited?.length) {
        await admin.from('email_suppressions').upsert({ email: bounced, reason: 'hard_bounce:permanent', source: 'mailbox_report' }, { onConflict: 'email' });
        await whereAddress(admin.from('leads').update({ invite_status: 'bounced' }), 'email', bounced).in('invite_status', ['queued', 'sent']);
      }
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
      // The three gates, in this order, live in suppression_policy.ts replyStopRefusal since 28 Oct 2026, so email_triage's
      // opt_out backstop stands behind exactly the same ones: protected address, authenticated From domain, invited address.
      const why = await replyStopRefusal(admin, { from, protectedList: [...adminList, ...fwdList, EXPENSE_MAILBOX], authenticated: async () => {
        // The webhook is metadata-only; the headers come from GET /emails/inbound/{id} (measured 22 Sep 2026).
        const hdrs = d.headers?.['authentication-results'] ? d.headers
          : ((resendEmailId && rkey) ? await (async () => { const f: any = await fetchInboundEmail(resendEmailId, rkey); return (f?.data || f)?.headers; })() : null);
        // a reply handed in from the Microsoft 365 mailbox carries EOP's verdict, not SES's (suppression_policy.ts)
        return senderAuthenticated(providerEmailId, hdrs?.['authentication-results'], from);
      } });
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
    return { ...ctx };
}
export type Out = Exclude<Awaited<ReturnType<typeof bounceUnsubscribe>>, Response>;
