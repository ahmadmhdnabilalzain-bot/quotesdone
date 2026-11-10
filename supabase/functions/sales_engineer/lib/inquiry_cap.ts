// inquiry_cap — the portal chat reaches its 100-message limit and the sales engineer takes the request over (10 Nov 2026,
// sales_engineer; founder ledger 1572: "Hard limit 100 messages per inquiry").
//
// At message 100 (_shared/inquiry_state.ts capStage 'handoff') the portal job becomes a request the customer does not have
// to retell: an inquiry_intake row is written from the job's own transcript (every turn, marked carried), held, with the
// conversation's state carried onto it (fn_inquiry_state_carry), and the sales engineer gets the same handoff a request
// held for unsettled specs opens (spec.not_sure, registered; its handler writes to the customer about the open items).
// Past message 100 (`over`) nothing more is said to the customer; the same call makes sure the hand-off exists.
// Idempotent: a job already handed off (its row carries brief.carried_from = the episode's key) is never written twice, and
// fn_seat_handoff opens one handoff per type and subject. Every step answers null rather than throw: the reply never waits
// on it. prevented by: sales_engineer/inquiry_cap.test.ts
import { carriedTurns, carryState, intakeKey, mergeState } from '../../_shared/inquiry_state.ts';
import type { ChatMsg } from '../../_shared/chat_history.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;
export interface CapHandoff { intakeId: string | null; handoffId: number | null; created: boolean }

export async function handOffAtCap(admin: Admin, o: { customerId: string; episodeKey: string; transcript: ChatMsg[]; from: number;
  category: string | null; open: string[] }): Promise<CapHandoff> {
  let intakeId: string | null = null; let created = false;
  try {
    const { data: had } = await admin.from('inquiry_intake').select('id').eq('customer_id', o.customerId).eq('brief->>carried_from', o.episodeKey).limit(1);
    intakeId = Array.isArray(had) && had[0]?.id ? String(had[0].id) : null;
    if (!intakeId) {
      const { data: c } = await admin.from('customers').select('email').eq('id', o.customerId).maybeSingle();
      const { data: row } = await admin.from('inquiry_intake').insert({ customer_id: o.customerId, email: c?.email ?? null, status: 'held', category: o.category,
        turns: carriedTurns(o.transcript, o.from), brief: { details: {}, state: 'interview', carried_from: o.episodeKey, held_for: 'message_cap' } }).select('id').maybeSingle();
      intakeId = row?.id ? String(row.id) : null;
      created = !!intakeId;
      if (intakeId) await carryState(admin, o.episodeKey, intakeKey(intakeId), 'request_chat', intakeId);
    }
  } catch { /* the hand-off below still names the conversation */ }
  let handoffId: number | null = null;
  try {
    const { data } = await admin.rpc('fn_seat_handoff', { p_from: 'customer_support', p_to: 'sales_engineer', p_type: 'spec.not_sure',
      p_subject_table: intakeId ? 'inquiry_intake' : 'inquiry_state', p_subject_id: intakeId ?? o.episodeKey,
      p_payload: { intake_id: intakeId, customer_id: o.customerId, not_sure: o.open, category: o.category, conv_key: o.episodeKey,
        waiting_for: 'sales_engineer to continue this request with the customer: the conversation reached its 100-message limit (ledger 1572)' } });
    handoffId = Number(data) || null;
  } catch { /* fn_seat_handoff failing is the IT engineer's finding; nothing is said to the customer that is not true */ }
  const patch = { status: 'handed_off' as const, ...(handoffId ? { handoff_id: handoffId } : {}) };
  await Promise.all([mergeState(admin, o.episodeKey, 'portal_assistant', patch), intakeId ? mergeState(admin, intakeKey(intakeId), 'request_chat', patch) : null]);
  return { intakeId, handoffId, created };
}
