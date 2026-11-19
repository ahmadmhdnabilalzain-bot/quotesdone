// inquiry_intake/message_limit.ts — THE 100-MESSAGE LIMIT (10 Nov 2026, founder ledger 1572: "Hard limit 100 messages per
// inquiry"). handle.ts reads the stage (capStage); at message 100 and past it the turn is this module's capTurn, and from
// message 95 the reply is summaryAtLimit. Moved verbatim from handle.ts (19 Nov 2026, it_engineer; ledgers 1714/1715/1556:
// handle.ts was 1,418 lines).
// deno-lint-ignore-file no-explicit-any
import { ACTOR } from '../_shared/intake_requirements.ts';
import { defaultDeps } from '../_shared/think.ts';
import { capRule, mergeState, type CapStage } from '../_shared/inquiry_state.ts';
import { intakeVoice } from './slots.ts';
import { J, admin, logRun } from './shared.ts';
import type { TurnClock } from './turn_clock.ts';

/** Message 100 (stage 'handoff') and past it ('over'): the request is held and handed to the sales engineer. */
export async function capTurn(c: { stage: CapStage; replyNo: number; turns: any[]; draft: any; cust: any; text: string; ar: boolean; clock: TurnClock;
  allText: string; stKey: string; userTexts: () => string[] }): Promise<Response> {
  const { stage, replyNo, turns, draft, cust, text, ar, clock, allText, stKey, userTexts } = c;
  // THE SALES ENGINEER TAKES IT FROM HERE. The specs still open are the last stamped turn's; the handoff is opened once
  // per request (fn_seat_handoff dedupes). Message 100 is the model's sentence saying so (ruling 1339: the draft only
  // when OpenRouter is down); past 100 no reply is written at all.
  let lastSlots: any = null;
  for (let i = turns.length - 1; i >= 0; i--) if (turns[i] && turns[i].role === 'assistant' && turns[i].slots) { lastSlots = turns[i].slots; break; }
  const open: string[] = Array.isArray(lastSlots?.missing_keys) ? lastSlots.missing_keys.map(String) : [];
  const { data: hid } = await admin.rpc('fn_seat_handoff', { p_from: 'customer_support', p_to: 'sales_engineer', p_type: 'spec.not_sure',
    p_subject_table: 'inquiry_intake', p_subject_id: String(draft.id),
    p_payload: { intake_id: draft.id, customer_id: cust?.id || null, not_sure: open, category: draft.category ?? null,
      waiting_for: 'sales_engineer to continue this request with the customer: the conversation reached its 100-message limit (ledger 1572)' } })
    .then((r: { data: unknown }) => r, () => ({ data: null }));
  let capMsg = '';
  let capBy: 'model' | 'outage_fallback' | 'none' | 'not_sent' = 'not_sent';
  if (stage === 'handoff') {
    const capDraft = ar
      ? 'وصلت هذه المحادثة إلى حدها الأقصى. يتابع معكم مهندس المبيعات لدينا طلبكم كاملًا هنا، ولا حاجة إلى إعادة كتابة أي شيء.'
      : 'This conversation has reached its limit. Our sales engineer now has your whole request and will continue with you here; there is no need to repeat anything.';
    const v = await intakeVoice(defaultDeps(admin, 'inquiry_intake'), { draft: capDraft, lang: ar ? 'ar' : 'en', message: text, conversation: turns.slice(0, -1),
      deadline: clock.replyDeadline(), rule: capRule('handoff', replyNo) });
    capMsg = v.text; capBy = v.by;
    if (capMsg) turns.push({ role: 'assistant', text: capMsg, agent: ACTOR, slots: { ...(lastSlots || {}), status: 'held', at: new Date().toISOString() } });
  }
  const { error: capErr } = await admin.from('inquiry_intake').update({ status: 'held', raw_input: allText.slice(0, 4000), turns, updated_at: new Date().toISOString() }).eq('id', draft.id);
  if (capErr) return J({ error: 'intake_unavailable', message: 'Your request could not be saved. Nothing has been submitted - please try again.' }, 503);
  await mergeState(admin, stKey, 'request_chat', { turn: userTexts().length, message_count: turns.length, status: 'handed_off', intake_id: String(draft.id), ...(Number(hid) ? { handoff_id: Number(hid) } : {}) });
  await logRun('ok', { capped: 1, reply_no: replyNo, stage, reply_by: capBy, handoff: Number(hid) || null }, 'the request chat reached its 100-message limit (ledger 1572): held and handed to the sales engineer' + (stage === 'over' ? '; no reply was sent past message 100' : ''));
  return J({ ok: true, intake_id: draft.id, status: 'held', capped: true, stage, category: draft.category ?? null, assistant_message: capMsg, questions: [], next_question: null,
    missing: open, reply_by: capBy, agent: ACTOR, agent_name: ar ? 'مهندس مبيعات QuotesDone' : 'QuotesDone sales engineer' });
}

/** From message 95: the reply is what the request holds and what is still open, to confirm. */
export function summaryAtLimit(details: unknown, missing: unknown, ar: boolean): string {
  const held = Object.entries((details as Record<string, unknown>) || {}).map(([k, v]) => `${k.replace(/_/g, ' ')}: ${String(v).slice(0, 120)}`);
  const openQs = (Array.isArray(missing) ? missing.map(String) : []).slice(0, 6);
  return (ar ? 'هذا ملخص طلبكم حتى الآن: ' : 'Here is your request as we hold it: ') + (held.join('; ') || '-') + '. '
    + (openQs.length ? (ar ? 'ما زال مفتوحًا: ' : 'Still open: ') + openQs.join('; ') + '. ' : '')
    + (ar ? 'هل هذا صحيح؟' : 'Is this correct?');
}
