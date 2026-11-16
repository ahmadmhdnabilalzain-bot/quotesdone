// THE PER-TURN FACTS RIDE AFTER THE CONVERSATION, NOT IN THE SYSTEM PROMPT (it_engineer, cost, 10 Nov 2026).
//
// The prompt is cached as a prefix (ai_gateway/system_message.ts): the knowledge brief (sys_shared, sys_stable), then the
// caller's sys, then the earlier turns with a breakpoint on the last one (withHistoryBreakpoint, the 5-minute tier). A prefix
// pays the cache READ rate (USD 0.10 per million on claude-sonnet-5.5) only while every byte before the breakpoint is the same
// as on the last call; one changed byte and everything after it is WRITTEN again (USD 2.50 per million, 25x the read).
// Rates measured exactly on ai_cost_log, 600 rows, 20 days to 10 Nov 2026: input 2.00, read 0.10, write-1h 4.00,
// write-5m 2.50, output 10.00 per million tokens.
//
// site_assistant put three blocks that change with every message INSIDE sys, before the earlier turns:
//   - the trade knowledge retrieved for THIS message (given_trade_knowledge.ts, up to 6 rows of ~1,260 characters);
//   - the signed-in person's live account data (fn_wa_context);
//   - their case timeline (fn_contact_timeline, 30 newest events).
// So on every turn that carried one of them, sys and the whole conversation after it were written to the cache again.
// Measured, ai_cost_log 2-3 Nov 2026 (the same brief layout on both paths): site_assistant visitor_chat wrote 1,254-1,742
// cache tokens a call, wa_inbound (whose per-turn facts already ride after the history, ai_reply.ts) 175-183.
// The blocks now ride with the message, after the history, exactly as aiReply and the portal (sales_engineer/actions/
// portal.ts) already send their facts. Their words are unchanged; with none of them the message is sent as it always was.
// prevented by: site_assistant/turn_facts.test.ts
import { givenBlock, type GivenRow } from '../_shared/given_trade_knowledge.ts';
import { generaliseOwnRequestFacts, OWN_REQUEST_RULE } from '../_shared/own_request_facts.ts';

/** The signed-in person's own live account data, as the widget has always worded it ('' for a visitor). */
export function liveFacts(live: Record<string, unknown> | null, uiLang: string): string {
  if (!live) return '';
  // 16 Nov 2026 (ledger 1711): each quote's letter and price, as their portal shows it, and what they asked; a customer's
  // record carries OWN_REQUEST_RULE, the same rule WhatsApp, the portal chat and e-mail give the model
  const own = (live as { scope?: unknown }).scope === 'customer' ? ' ' + OWN_REQUEST_RULE : '';
  return `THIS PERSON IS SIGNED IN. Their OWN live account data, scoped in SQL to them alone:\n${JSON.stringify(generaliseOwnRequestFacts(live))}\nAnswer about their account from it directly; never tell them to log in. Before a reveal, price_band is only a rounded average: never present it as a quote, and never name or describe a supplier.${own} Their portal is in ${uiLang === 'ar' ? 'ARABIC; name its buttons in Arabic as printed ("طلب جديد", "طلباتي", "المستندات", "الرسائل", "الحساب")' : 'ENGLISH; name its buttons as printed ("New request", "My requests", "Documents", "Messages", "Account")'}.`;
}

/** Their case timeline (fn_contact_timeline events, newest first; '' when there are none). */
export function timelineFacts(events: unknown): string {
  return Array.isArray(events) && events.length
    ? `THEIR CASE TIMELINE (newest first; every channel and every seat; theirs only). Never contradict it, and never tell them something is pending that it shows as done:\n${JSON.stringify(events)}`
    : '';
}

// (imported here, beside its one use, so the live-account wording above stays its own change)
import { supplierStanding } from '../_shared/supplier_known.ts';

/** This turn's facts, in the order sys used to carry them: live account, timeline, trade knowledge. */
export function turnFacts(o: { live: Record<string, unknown> | null; uiLang: string; timeline: unknown; given: GivenRow[] }): string {
  // a signed-in supplier's standing in the words every supplier door uses ('' for anyone else; _shared/supplier_known.ts, 16 Nov 2026)
  return [liveFacts(o.live, o.uiLang), supplierStanding(o.live), timelineFacts(o.timeline), givenBlock(o.given)].map((b) => b.trim()).filter(Boolean).join('\n\n');
}

/** The newest user turn: this turn's facts, then the message. No facts: the message alone, byte for byte as before. */
export function turnContent(facts: string, message: string): string {
  return facts.trim() ? facts.trim() + '\n\nMESSAGE:\n' + message : message;
}
