// A PARTNERSHIP E-MAIL REACHES THE CEO WITH THE SENDER'S FACTS (ceo, OPS_LOOPS, 16 Nov 2026; hole H10 of the COO hunt).
//
// MEASURED (READ, origin/main 55489dde7): email_triage's model reads a message as `partnership`, customer_support answers it
// through the model, and nothing follows: no seat duty, no pipeline, no owner. A real company hands a partnership proposal to
// the person who decides partnerships. Here that is the CEO seat: this files the handoff partnership.proposed
// (customer_support -> ceo) with the sender's facts (the account facts email_triage already gathered for its reply) and the
// proposal as UNTRUSTED text. Its handler (fn_ceo_partnership_take, scripts/sql/a_partnership_email_reaches_the_ceo_with_the_senders_facts.sql)
// asks the CEO seat's model to decide pursue or decline, and that answer closes the handoff. The meaning (that this IS a
// partnership) is the triage model's reading; this code only routes by it.
// prevented by: email_triage/partnership.test.ts
type Admin = { rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{ data?: unknown; error: { message: string } | null }> };
export interface PartnershipMail { id: number | string; from_email?: string | null; to_email?: string | null; subject?: string | null; body?: string | null }

export function partnershipPayload(m: PartnershipMail, summary: string, facts: string): Record<string, unknown> {
  const from = String(m.from_email || '').trim();
  return {
    inbound_message_id: m.id,
    from_email: from || null,
    sender_domain: from.includes('@') ? from.split('@').pop()!.toLowerCase() : null,
    to_email: m.to_email ?? null,
    subject: String(m.subject || '').slice(0, 200),
    summary: String(summary || '').slice(0, 500),
    // the sender's own words: data for the CEO seat to read, never instructions
    proposal_untrusted: String(m.body || '').slice(0, 3000),
    sender_facts: String(facts || '').slice(0, 3000),
    replied_by: 'customer_support (its model answered the sender in the thread)',
    ask: 'Decide whether QuotesDone pursues this partnership or declines it, with the reason and the next step.',
  };
}

/** Hand a message the triage model read as a partnership to the CEO seat. Never throws: a failure is logged and counted. */
export async function handPartnershipToCeo(admin: Admin, m: PartnershipMail, summary: string, facts: string): Promise<'handed' | 'failed'> {
  try {
    const { error } = await admin.rpc('fn_seat_handoff', { p_from: 'customer_support', p_to: 'ceo', p_type: 'partnership.proposed',
      p_subject_table: 'inbound_messages', p_subject_id: String(m.id), p_payload: partnershipPayload(m, summary, facts) });
    if (error) { console.error('email_triage partnership handoff', m.id, error.message); return 'failed'; }
    return 'handed';
  } catch (e) {
    console.error('email_triage partnership handoff', m.id, String((e as Error)?.message || e));
    return 'failed';
  }
}
