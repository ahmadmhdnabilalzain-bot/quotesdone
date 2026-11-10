// resend_inbound step: which mail is finance mail, the bookkeeper hand-over and the expenses-mailbox sender gate. Moved out of index.ts's handler unchanged (9 Nov 2026);
// the handler in index.ts calls the steps in the order they ran inline, each handing on what the next one reads.
import type { Out as MarketingRepliesOut } from './marketing_replies.ts';
import { M365_INBOUND_PREFIX } from '../../_shared/m365_reply_inbox.ts';
import { admin, J, sec, logRun } from '../lib/runtime.ts';
import { EXPENSE_MAILBOX, FINANCE_BOXES } from '../lib/receipt_consts.ts';

export async function expenseGate(ctx: MarketingRepliesOut) {
    const { emailId, to, toLocal, expenseSenderOk, from, subject, providerEmailId, text } = ctx;
    // ---- Forwarded receipt / subscription -> finance ----
    // 6 SEP 2026: a receipt nobody could book goes to the BOOKKEEPER (handToBookkeeper), never to the founder.
    // 23 SEP 2026 (founder_instruction 886-903): WHAT the email is (a statement, a receipt and its cadence, a
    // Meta ads invoice, a licence or domain renewal, or none of these) and WHO issued it are REASONED
    // (_shared/reasoned_books.ts); only the figures are parsed (_shared/receipt_parse.ts). Under the model hold
    // nothing is booked on a guess: the email is held for the bookkeeper and the accountant's queue replays it.
    // Mail handed from a tenant mailbox other than supplier@ never reaches the expense or bookkeeper path (review, 2 Nov 2026):
    // its sender is never a permitted forwarder (the reader does not hand them), so a stranger's invoice is plain correspondence.
    const tenantHanded = emailId.startsWith(M365_INBOUND_PREFIX) && to !== String(await sec('invite_m365_mailbox') || '').trim().toLowerCase();
    let receiptish = FINANCE_BOXES.has(toLocal);
    if (tenantHanded) receiptish = false;
    // deno-lint-ignore prefer-const -- reassigned by the receipts step, which takes it from this step's result
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
        from_email: from, to_email: to, subject, provider_email_id: providerEmailId,
        body: '[REFUSED — sender is not on app_secrets.expense_forwarders] nothing was booked, no document was stored, no supplier record was touched.\n\n' + (text || '').slice(0, 4000),
        attachments_count: 0, matched_existing: false, needs_review: true,
      }).select('id').maybeSingle();
      await handToBookkeeper(refusedRow?.id, [], `Mail to ${to} from ${from} was REFUSED: that address is not on app_secrets.expense_forwarders. Nothing was booked and no attachment was stored. Decide whether this sender should be added to the allowlist; if it is a company expense, add them and ask for a re-forward.`);
      await logRun('ok', { expenses_mailbox: 1, authorised: 0, from, to }, 'mail to the expenses mailbox was refused: ' + from + ' is not on the expense forwarder allowlist. Recorded as inbound_messages#' + (refusedRow?.id ?? '?') + ' and handed to the accountant.');
      return J({ ok: true, receipt: false, booked: false, reason: 'sender_not_allowlisted' });
    }
    return { ...ctx, tenantHanded, receiptish, receiptReason, handToBookkeeper, isExpenseMailbox };
}
export type Out = Exclude<Awaited<ReturnType<typeof expenseGate>>, Response>;
