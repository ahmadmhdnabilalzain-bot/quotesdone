// AN UNANSWERED MAIL IS HANDED OVER AS A MAIL, NOT AS A REVIEW (customer_support, 19 Nov 2026; ledger 1436).
// Agent: customer_support held-mail retrier.
//
// MEASURED (production, 19 Nov 2026): when email_triage could not send an answer (inbound_messages 2169, 12 Nov: fn_inbox_send
// refused "read as unclear"), it filed review.requested to the CEO seat. That kind MEANS "a customer or supplier asked us to review
// an automated decision" (seat_handoff_kind), its payload carried only the inbound id and an ask, and its handler waited for "the
// ceo verdict on review request ?". At its 48 h clock the CEO's model (ceo.overdue_handoff) was shown that, chose 'answer', and
// wrote "this handoff does not identify the decision or the point you want reviewed" (agent_actions 393159, 18 Nov): dismissed,
// and the supplier heard nothing.
//
// NOW it is mail.unanswered, customer_support to customer_support (the seat that owns the mail), registered with a 24 h clock in
// scripts/sql/an_unanswered_mail_is_handed_to_its_seat_with_its_facts.sql. Its payload is the mail: the inbound id, the sender, the
// owner seat, when it arrived and how long it has waited, the subject, the start of what they wrote (fenced, untrusted), the draft
// if one exists, and why the answer failed, in `what` (the field the CEO's overdue question reads). Past the clock the existing
// escalation (fn_handoff_overdue_escalate, fn_ceo_files_judgements) puts it to the CEO with the owner customer_support, whose
// choices are 'chase' (a ceo.order to customer_support to answer it, due in 2 days, the CEO's words saying what to answer) or
// 'close' with the reason. No parallel path: the registry, the clock, the CEO's question and the order are the estate's own.
// An answer that goes closes it (email_triage closeUnansweredHandover).
// prevented by: email_triage/unanswered_mail.test.ts
export const UNANSWERED_KIND = 'mail.unanswered';
export const OWNER_SEAT = 'customer_support';

export type UnansweredMail = { id: number; from_email: string | null; to_email: string | null; subject: string | null; body: string | null; created_at?: string | null };

/** The fn_seat_handoff arguments for a mail whose answer could not be sent. Pure. */
export function unansweredMailHandoff(m: UnansweredMail, o: { error: string; draft?: string | null; now?: number }) {
  const now = o.now ?? Date.now();
  const received = Date.parse(String(m.created_at ?? ''));
  const waitedHours = Number.isFinite(received) ? Math.max(0, Math.round((now - received) / 360_000) / 10) : null;
  const draft = String(o.draft ?? '').trim().slice(0, 1500) || null;
  const subject = String(m.subject ?? '').slice(0, 200);
  const error = String(o.error ?? '').slice(0, 300);
  const what = 'Answer or close, with the reason, the e-mail inbound_messages #' + m.id + ' from ' + String(m.from_email ?? 'an unknown sender')
    + ' to ' + String(m.to_email ?? '?') + ' ("' + subject + '"), received ' + String(m.created_at ?? 'at an unrecorded time')
    + (waitedHours != null ? ', unanswered for ' + waitedHours + ' h' : '') + '. Owner: ' + OWNER_SEAT + '. Why no answer went: ' + error + '.'
    + (draft ? ' A draft exists (in `draft`), never sent.' : ' No draft exists.');
  return {
    p_from: 'customer_support', p_to: 'customer_support', p_type: 'mail.unanswered', p_subject_table: 'inbound_messages', p_subject_id: String(m.id),
    p_payload: {
      inbound_message_id: m.id, from_email: m.from_email, to_email: m.to_email, subject, owner_seat: OWNER_SEAT,
      received_at: m.created_at ?? null, waited_hours: waitedHours, error, draft,
      body_untrusted: String(m.body ?? '').slice(0, 1500),
      what, ask: 'The sender has heard nothing. Have the answer written and sent in the thread, or close it with the reason they are owed nothing.',
    },
  };
}

// deno-lint-ignore no-explicit-any
type Db = any;
/** The mail was answered: its open mail.unanswered hand-over is complete. Never throws (the answer has gone). */
export async function closeUnansweredHandover(admin: Db, id: number, by: string): Promise<void> {
  try {
    const { data } = await admin.from('agent_actions').select('id').eq('kind', 'handoff').eq('target_id', UNANSWERED_KIND + ':' + id)
      .eq('status', 'pending');
    for (const r of (data ?? []) as { id: number }[]) {
      await admin.rpc('fn_seat_handoff_complete', { p_id: r.id, p_evidence: { answered: true, inbound_message_id: id, by } });
    }
  } catch (_e) { /* the CEO's overdue question can still close it as moot, with the reason */ }
}
