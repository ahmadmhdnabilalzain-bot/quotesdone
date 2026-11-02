// A STOP THE WORD LIST MISSES IS CAUGHT BY THE TRIAGE, AND NEVER ANSWERED (28 Oct 2026, sales_engineer; founder ledger
// 1401, the supplier-journey audit).
//
// The deterministic reading (_shared/unsubscribe_mailbox.ts isUnsubscribeRequest) runs first, in resend_inbound, and
// decides a stop with no model. What it cannot list reaches email_triage as an ordinary invitation reply, and email_triage
// ANSWERS it. Measured on production 28 Oct 2026 (auditor A, run 490a318b, inbound_messages 1449): "Please remove me /
// stop" to supplier@ was answered "Understood. We will not contact you again..." while the address stayed sendable, so
// the next nudge would still have gone. #1724 widens the word list on supplier@; its independent review measured 20
// realistic declines it still does not read (0/20): "Please unsubscribe me from your mailing list.", "We are not
// interested at the moment.", "Please don't send us any more emails.", "Thanks but no thanks", "unsubscibe",
// "نحن غير مهتمين", "الرجاء عدم مراسلتنا", ... A list will not keep up with how people decline.
//
// email_triage reads every mail with a real model call (#1714: SYS, category, never cached), so SYS now offers opt_out,
// and when the model reads opt_out on an INVITED SUPPLIER'S REPLY TO supplier@ (the mail email_triage would otherwise
// answer: customer_mail.ts invitationReplyAnswerable lifted its internal skip):
//   * the stop is applied behind the SAME three gates as resend_inbound's (suppression_policy.ts replyStopRefusal),
//     with the lane-aware sender verdict resend_inbound stored on the row (raw.sender_authenticated);
//   * the reply is never answered, and the row says what was done (ai_category opt_out, ai_summary);
//   * a stop a gate refuses, or one that cannot be recorded, is kept for a person (needs_review), exactly like
//     resend_inbound's refused stop.
// The coordinator, 28 Oct 2026: "A miss means mailing someone who asked us to stop (a compliance risk); a false positive
// loses one lead. Lean toward honouring." What an opt-out stops is unchanged: the cold outreach only (OPT_OUT_TYPES),
// never a sign-in code or a registered supplier's request for quotation.
// NOT CHANGED: every other mail. A customer's "cancel my request" to info@ is classified and answered as before; the
// category is recorded, nothing is suppressed.
import { replyStopRefusal } from '../_shared/suppression_policy.ts';

export const OPT_OUT_CATEGORY = 'opt_out';

// AN UNREAD CLASSIFICATION IS NOT A CLEARANCE (3 Nov 2026, independent review of #1728). makeLlm never throws: on a
// failure or a timeout it returns null, and a reply with no JSON object (or one that does not parse) left the category at
// 'other'. backstopApplies was then false and the mail went on to reply1(), whose own model calls can succeed, so a
// "please remove me" to supplier@ could still be answered while the address stayed sendable (the 28 Oct failure). On the
// backstop's scope (an invited supplier's reply to supplier@) an unread classification is held exactly as a refused
// stop is: never answered, needs_review, triaged_at set. The selector reads only triaged_at null, so it is not re-run.
export const UNREAD_CATEGORY = 'triage_unread';
export const UNREAD_SUMMARY = 'Not answered: the triage model gave no readable classification (no answer, or no category in parseable JSON), '
  + "and an invited supplier's reply to supplier@ may be a stop. Kept for a person to review.";

export type Triage = { parsed: boolean; category: string; summary: string; reply: string };
/** Reads the triage model's answer exactly as before; parsed is false for no answer, no JSON object, bad JSON, or no category. */
export function readTriage(out: string | null | undefined): Triage {
  const none: Triage = { parsed: false, category: 'other', summary: '', reply: '' };
  const mm = out ? out.match(/\{[\s\S]*\}/) : null;
  if (!mm) return none;
  try {
    const pj = JSON.parse(mm[0]);
    return { parsed: typeof pj?.category === 'string' && pj.category.trim() !== '', category: String(pj?.category || 'other').slice(0, 40),
      summary: String(pj?.summary || '').slice(0, 500), reply: String(pj?.reply || '').slice(0, 4000) };
  } catch (_e) { return none; }
}

/** An invited supplier's reply to supplier@ whose classification did not read is held, never answered. */
export function holdsUnread(invitationReply: boolean, parsed: boolean): boolean {
  return invitationReply === true && parsed !== true;
}

export type BackstopMail = { id: number; from_email: string | null; raw?: Record<string, unknown> | null };

/** The model read this mail as a stop, and it is an invited supplier's reply to supplier@ that would otherwise be answered. */
export function backstopApplies(category: unknown, invitationReply: boolean): boolean {
  return invitationReply === true && String(category ?? '') === OPT_OUT_CATEGORY;
}

// deno-lint-ignore no-explicit-any
type Db = any;
/** Applies the stop the model read, behind replyStopRefusal's gates; records it on the row; never answers. */
export async function applyBackstop(admin: Db, m: BackstopMail, protectedList: string[]): Promise<{ suppressed: boolean; why: string }> {
  const from = String(m.from_email || '').trim().toLowerCase();
  const why = from ? await replyStopRefusal(admin, { from, protectedList, authenticated: () => m.raw?.sender_authenticated === true }) : 'no sender address';
  let failed = '';
  if (!why) {
    const { error } = await admin.from('email_suppressions').upsert({ email: from, reason: 'unsubscribe', source: 'reply' }, { onConflict: 'email', ignoreDuplicates: true });
    if (error) failed = 'the suppression could not be recorded: ' + String(error.message || error).slice(0, 200);
  }
  const summary = why ? 'Asked to stop (the triage read it as opt_out). NOT APPLIED: ' + why + '. Not answered; kept for a person to review.'
    : failed ? 'Asked to stop (the triage read it as opt_out). NOT APPLIED: ' + failed + '. Not answered; kept for a person to review.'
    : 'Asked to stop (the triage read it as opt_out): suppressed exactly as an unsubscribe reply is (email_suppressions, unsubscribe, reply). Not answered.';
  await admin.from('inbound_messages').update({ ai_category: OPT_OUT_CATEGORY, ai_summary: summary, ai_draft_reply: null, needs_review: !!(why || failed) }).eq('id', m.id);
  return { suppressed: !why && !failed, why: why || failed };
}
