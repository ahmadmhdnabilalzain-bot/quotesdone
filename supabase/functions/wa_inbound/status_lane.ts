// status_lane.ts - THE SIMPLE ASKS ON WHATSAPP RUN ON A SMALL MODEL WITH CODE-FIXED FACTS (it_engineer for cost, customer_support's
// channel; 10 Nov 2026, founder ruling 1571: "Simple tasks (WhatsApp status questions, invoice copies, 'your quotation / comparison
// report is ready' updates, sign-up verification) do not need Sonnet 5.5 ... Complicated WhatsApp asks can send the customer to the
// app"). Design: docs/reports/2026-11-10-design-model-routing.md section 5b.
//
// MEASURED (production ai_cost_log, 10 Nov 2026): a WhatsApp status answer ran on conversation_reply (Sonnet 5.5) with the company
// brief, 23,036 tokens in (20,207 cached) and 159 out, USD 0.0118 a reply. On this lane it is ~2.5k tokens on status_reply
// (model_policy: Luna Pro > Qwen 3.8 Flash), about USD 0.0003 (E).
//
// WHAT DECIDES THE LANE is the REASONED intent (wa_inbound/classification.ts whatsappReadings), never the body's words:
//   status   my_status, my_documents, my_quotes, my_requests, my_jobs, by_id, invoice_copy, verification_code: the sender's own
//            rows (fn_wa_context, fn_wa_fact_pack) and the database's answer for the intent (fn_wa_answer) are the facts, and
//            only they: no brief, no FAQ, no company block. The last STATUS_HISTORY_TURNS turns ride along.
//   app      new_request (a new job, drawings, several trades): one short reply that carries the request chat's link exactly.
//   conversation  everything else, and EVERY turn where a person is needed: the full path (conversation_reply with the brief).
// The words are the model's on every lane (ruling 1339); a code-written line only in an outage, through the held notice.
// prevented by: wa_inbound/status_lane.test.ts
import { newRequestLink } from '../_shared/size_question.ts';

export const STATUS_INTENTS: ReadonlySet<string> = new Set(['my_status', 'my_documents', 'my_quotes', 'my_requests', 'my_jobs', 'by_id', 'invoice_copy', 'verification_code']);
export const APP_INTENTS: ReadonlySet<string> = new Set(['new_request']);
/** model_policy's class for the status and app lanes. */
export const STATUS_CLASS = 'status_reply';
/** Turns of the conversation a status answer hears (a status ask is about now, not the whole history). */
export const STATUS_HISTORY_TURNS = 6;
export type Lane = 'status' | 'app' | 'conversation';

/** The lane for a reasoned intent. A person needed always takes the full path, whatever was asked. */
export function laneOf(intent: string | null | undefined, needsPerson: boolean): Lane {
  if (needsPerson || !intent) return 'conversation';
  if (STATUS_INTENTS.has(intent)) return 'status';
  if (APP_INTENTS.has(intent)) return 'app';
  return 'conversation';
}

/** What a lane's reply must carry exactly: the request chat's link (app), the request or job numbers the database answer names
 *  (status; at most 3, '#1043' or 'Job 1043' as written there). A draft without one is rewritten by the model (aiReply `must`). */
export function laneMust(lane: Lane, databaseAnswer: string, lang: 'en' | 'ar'): string[] {
  if (lane === 'app') return [newRequestLink(lang)];
  if (lane !== 'status') return [];
  const refs = String(databaseAnswer || '').match(/#\d{3,}|\b(?:Job|Request|Inquiry) \d{3,}\b/g) ?? [];
  return [...new Set(refs)].slice(0, 3);
}

/** The status lane's rules, after WA_RULES (model_says.ts): the facts are code's, the words are theirs. */
// Eval A run 2 (qd_run:evala2cf02438201, 10 Nov 2026): told "the comparison report is prepared once the quotes are in" with 3 of 3
// quotes in, Luna Pro wrote that the report "is ready now". A state is stated only as the facts state it (as INTAKE_RULES says
// for the request chat).
export const STATUS_RULES = 'This is a simple ask: answer it from the facts above in two or three short sentences, with every number, date and reference exactly as the facts give it. Where the facts point to a page or button, name it as written. Do not add anything the facts do not state. Never say that a report is ready, a request is complete, a quote is accepted or anything has been sent unless the facts say so in those words.';
