// A SUPPLIER-MAILBOX REPLY LEAVES ONLY WHEN THE READING OF THE MAIL SAID ANSWER, CHECKED AT SEND TIME (customer_support,
// 11 Nov 2026, founder ruling 1633). MEASURED: notifications 129468, 134514 and 138326 took the registration template to
// azure-noreply@microsoft.com and supportmail@techsupport.microsoft.com, written by a handoff that never read email_triage's
// decline. fn_inbox_send now refuses such a reply when it is queued; this is the same rule at the last moment, so a row any
// path wrote (a direct insert, a replay, a row queued before the rule existed) is asked again before the provider call.
// The rule is ONE routine, public.fn_mailbox_reply_may_leave
// (scripts/sql/a_reply_from_the_supplier_mailbox_leaves_only_when_the_reading_said_answer.sql); this file only decides
// which rows to ask about and what to do with the answer.
// prevented by: send_outbox/mailbox_reply_gate.test.ts
import { M365_REPLY_KIND } from './m365_lane.ts';

/** A reply into the supplier mailbox's conversations (or the follow-up one promises): the rows the gate is asked about. */
export function mailboxReplyGated(n: { type?: unknown; kind?: unknown; dedupe_key?: unknown }): boolean {
  const k = String(n.dedupe_key ?? '');
  if (k.startsWith('supplier_reply_followup:')) return true;
  return n.type === 'inbound_reply' && (n.kind === M365_REPLY_KIND || k.startsWith('mailbox_auto_reply:') || k.startsWith('mailbox_person_reply:'));
}

export type GateVerdict = { send: true } | { send: false; refused: true; why: string } | { send: false; refused: false; why: string };
// deno-lint-ignore no-explicit-any
type Rpc = (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: any; error: { message: string } | null }>;

/** Ask the gate. A refusal is final (the row is never sent); a gate that cannot be read is NOT a yes: the row waits and is
 *  asked again (an outage, or the functions deployed a minute before the SQL that defines the gate). */
export async function askMailboxGate(rpc: Rpc, notificationId: number): Promise<GateVerdict> {
  const { data, error } = await rpc('fn_mailbox_reply_may_leave', { p_notification_id: notificationId });
  if (error) return { send: false, refused: false, why: 'the supplier-mailbox send gate could not be read (' + String(error.message).slice(0, 160) + ')' };
  const v = (data ?? {}) as { allow?: unknown; reason?: unknown };
  if (v.allow === true) return { send: true };
  return { send: false, refused: true, why: String(v.reason || 'the supplier-mailbox send gate refused it') };
}

/** How long a row waits when the gate could not be read. */
export const GATE_UNREADABLE_WAIT_MS = 10 * 60_000;
