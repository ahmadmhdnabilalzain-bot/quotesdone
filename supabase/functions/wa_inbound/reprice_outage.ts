// reprice_outage.ts — A RE-PRICE THE MODEL COULD NOT READ IS SAID, AND READ ONCE MORE LATER (customer_support, 10 Nov 2026;
// supplier follow-up #1909 item 2, founder ruling 1608).
//
// MEASURED on origin/main: wa_inbound reads "change my price to 72,556" with one gateway call (speculation.ts
// directiveRead). When that call failed (a model outage, a timeout, an unparseable answer) it answered null, which
// supplier_directive.ts read as "not a change": the message fell through to the ordinary answer, the price never moved,
// and nothing told the supplier it had not been applied.
//
// NOW: a failed reading is an OUTAGE, not a "no". When the supplier's message states at least one amount:
//   1. he is told at once, in English, that nothing has changed, that we will read it once more when the reader is back,
//      and how to change the price himself in the supplier portal now (a code-written notice: no model answered, ruling
//      1339's outage case);
//   2. the message is filed ONCE (dedupe on the MessageSid) in customer_support's reasoning queue under the surface
//      wa_inbound.supplier_reprice. Its options are "no change" and the amounts HIS message states, nothing else, so the
//      replay can only pick a number he wrote; fn_reason_apply_wa_inbound__supplier_reprice applies it through the same
//      fn_supplier_apply_change, within 48 hours of his message, and tells him the result (scripts/sql/
//      a_whatsapp_reprice_the_model_could_not_read_is_said_and_read_once_more.sql).
// A message with no amount cannot be a re-price (directive_gate.ts), so it takes the ordinary path as before.
// prevented by: wa_inbound/reprice_outage.test.ts
import { amountsInOwnWords } from './directive_gate.ts';

export const REPRICE_SURFACE = 'wa_inbound.supplier_reprice';
export const PORTAL = 'https://quotesdone.com/portal';

/** The directive reading's answer: a reading, or an outage (no model read the message). */
// instruction (16 Nov 2026, sales_engineer): the same reading also says whether the message is one of the supplier's instructions
// about his requests or his work (supplier_instruction.ts reads it fully, with his facts, only when this says so: no extra call per turn)
export type DirectiveReading = { change?: boolean; amount?: unknown; instruction?: string; outage?: undefined } | { outage: true; why: string } | null;

/** What the supplier is told when the reader is down and his message states an amount (English: suppliers always). */
export function outageNotice(amounts: string[]): string {
  const named = amounts.length === 1 ? 'AED ' + Number(amounts[0]).toLocaleString('en-US') : 'an amount';
  return 'Thank you, we have your message. If it asks to change your quotation price (to ' + named + '): we could not apply it just now, '
    + 'because our message reader is unavailable, so nothing has changed on your quotation. We will read your message once more as soon as it is back, '
    + 'change the price only to an amount you wrote, and confirm it here. To change it yourself now, open the request in the supplier portal: ' + PORTAL;
}

/** The held question the replay reasons over: pick "no_change" or one of the amounts his own message states. */
export function repriceHold(o: { from: string; body: string; messageSid: string | null; amounts: string[] }) {
  const body = o.body.slice(0, 1500);
  const subject = { channel: 'whatsapp', phone: o.from, message_sid: o.messageSid, body };
  return {
    p_seat: 'customer_support', p_surface: REPRICE_SURFACE, p_question: body,
    p_request: {
      seat: 'customer_support', surface: REPRICE_SURFACE, question: body, subject, lean: true, plan: { steps: [] }, research: false,
      context: { audience: 'supplier', language: 'en', conversation: [{ role: 'supplier', text: body }], turn_id: 'wa:' + (o.messageSid || o.from + ':' + body.slice(0, 40)) },
      decision: { name: 'supplier_reprice', options: [
        { id: 'no_change', meaning: 'the message does not instruct us to change their quotation price to a stated total (a question, a relative change such as "a bit cheaper", anything else, or unsure)' },
        ...o.amounts.map((a) => ({ id: 'amount:' + a, meaning: 'they instruct us to change their quotation price to a new total of AED ' + a })),
      ] },
    },
    p_plan: {}, p_subject: subject, p_reason: 'directive_reader_outage', p_dedupe_key: 'wa_reprice:' + (o.messageSid || o.from + ':' + body.slice(0, 40)),
  };
}

/** The outage branch: null when the message states no amount (it cannot be a re-price; the ordinary path answers it). */
export function repriceOutagePlan(reading: DirectiveReading, from: string, body: string, messageSid: string | null) {
  if (!reading || reading.outage !== true) return null;
  const amounts = amountsInOwnWords(body);
  if (!amounts.length) return null;
  return { notice: outageNotice(amounts), hold: repriceHold({ from, body, messageSid, amounts }), amounts };
}
