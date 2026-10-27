// openrouter_down — the ONE test of "the OpenRouter call failed", the only door a code-written reply may pass through.
// Seats: sales_engineer and customer_support. Founder ruling, 27 Oct 2026 ~14:15Z (founder_instruction 1339), verbatim:
//   "the engineer and customer support never replies without llm unless the server of open router is down"
//
// Meaning: every message these two seats send to a customer or supplier is written by the model (via ai_gateway →
// OpenRouter). Code still decides WHAT to say (the question, the slot, the options, a routine's result) and checks the
// words (figures, the reply guard, dropping an unsafe sentence). A code-written or templated reply is allowed ONLY when
// the model call itself FAILED: a network error, a 5xx, a timeout or our turn's deadline, the provider circuit open (the
// founder's hold included), or no credential to reach the gateway at all.
//
// What is NOT an outage, and so never licenses a code-written reply: a model that ANSWERED and whose answer was refused
// by a guard, unparseable, wrapped in JSON, or dropped sentence by sentence; a 4xx; the gateway's rate limit for one
// sender (a separate status notice, not a reply). In those cases the model is up: it is asked again, its safe sentences
// are kept, or nothing conversational is sent and the turn is queued for the model.
//
// Measured before this file (27 Oct 2026, the audit behind PR "replies only through the model"): every fallback in the
// reply paths fired on "the reply is ''", which aiReply returns both when no model answered AND when every draft was
// refused by the guards — so wa_inbound's held notice, the supplier quote-review held notice, the intake's
// HELD_FOR_SPECS and replyFromState, and the deterministic interview all sent code text while a model was answering.
// prevented by: _shared/openrouter_down.test.ts, scripts/checks/replies_are_written_by_the_model_unless_openrouter_is_down.test.mjs

/** Error text that means the call never got a model answer because the provider path failed. Matched against the
 *  error strings this estate already produces: llm.ts (client_timeout_*, client_error, gateway_http_5xx,
 *  no_credential, credential_check_unavailable), brief_answer.ts ('HTTP 5xx', fetch messages), ai_reply.ts
 *  ('deadline: …', 'threw'), inquiry_intake's llm() ('fetch_failed'), the gateway's circuit outcome (circuit_open,
 *  'every model route … open-circuit'), and think.ts's hold reasons (model_hold, founder_hold). */
export const OUTAGE_ERROR = new RegExp([
  String.raw`client_timeout`, String.raw`client_error`, String.raw`fetch_failed`, String.raw`\bthrew\b`,
  String.raw`gateway_http_5\d\d`, String.raw`\bHTTP 5\d\d\b`, String.raw`\bhttp:? ?5\d\d\b`,
  String.raw`deadline`, String.raw`timed? ?out`, String.raw`timeout`, String.raw`abort`,
  String.raw`network`, String.raw`connection`, String.raw`ECONN`, String.raw`dns`, String.raw`error sending request`,
  String.raw`circuit_open`, String.raw`open-circuit`, String.raw`founder_hold`, String.raw`model_hold`, String.raw`no_paid_ai`,
  String.raw`no_credential`, String.raw`no gateway credential`, String.raw`no_model_credential`, String.raw`credential_check_unavailable`,
  String.raw`provider (?:down|unavailable|error)`, String.raw`upstream`, String.raw`overloaded`, String.raw`service unavailable`,
].join('|'), 'i');

/** True when this error (and, if given, this HTTP status) says the model call FAILED rather than answered.
 *  An empty error with no 5xx/0 status is not an outage: something answered. */
export function isOpenRouterDown(error: unknown, http?: number | null): boolean {
  if (typeof http === 'number' && (http === 0 || http >= 500)) return true;
  // A 4xx is an answer, never an outage, whatever words follow it: llm.ts appends the gateway's own outcome and error
  // text after 'gateway_http_<status>', and that text can say "timeout", "upstream" or "connection" on a 400
  // (independent review of #1647).
  if (typeof http === 'number' && http >= 400 && http < 500) return false;
  const e = String(error ?? '').trim();
  if (/^gateway_http_4\d\d\b|\bHTTP 4\d\d\b/i.test(e)) return false;
  return !!e && OUTAGE_ERROR.test(e);
}

/** The reply to send: the model's words; or, ONLY when the model call failed (outage), the code-written fallback;
 *  otherwise '' (the model is up but nothing it wrote may be sent — the caller sends nothing and queues the turn).
 *  This is the sanctioned door: scripts/checks/replies_are_written_by_the_model_unless_openrouter_is_down.test.mjs
 *  fails when a reply path returns a code-written sentence any other way. */
export function modelOrOutage(r: { reply?: string | null; outage?: boolean }, codeText: string): string {
  const said = String(r.reply ?? '').trim();
  if (said) return said;
  return r.outage === true ? codeText : '';
}
