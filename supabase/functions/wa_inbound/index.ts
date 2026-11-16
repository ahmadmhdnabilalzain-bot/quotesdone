// wa_inbound v10 - smart WhatsApp responder on the API number (+1 218 316 6814).
// v5-v9: see history below. v10 adds WEBHOOK AUTHENTICITY (see PROVENANCE block).
// v5: may share the published WhatsApp contact (+1 218 316 6814) when someone asks for a human.
// v6: BIDI-SAFE Arabic (LTR runs wrapped in U+2066/U+2069 isolates).
// v7: AUDIENCE AWARENESS via fn_identify_contact() phone lookup + wording inference.
// v8: SEND FAILURES ARE NO LONGER SILENT.
// v9: agent_runs instrumentation on the LLM-failure and top-level-catch paths.
// v12: ROUTED THROUGH ai_gateway. The hand-rolled OpenRouter fetch is gone. try_faq=true lets the
//      approved FAQ corpus answer with NO MODEL AT ALL, and rate_key gives this endpoint the
//      per-sender ceiling it never had (20 messages/hour per WhatsApp number). The reply contract
//      is unchanged - the model still returns {reply,lang,audience,escalate}; only the transport
//      moved. A Level 0 FAQ answer arrives as plain prose, so it is wrapped in the same envelope.
// v16 (13 Aug 2026): MEDIA IN. This function has read `Body` since it was written and has never
//      looked at MediaUrl0. A supplier doing exactly what the invitation asks — attach your trade
//      licence — got a courteous reply about how QuotesDone works and the document went nowhere:
//      not to storage, not to license_extract, not onto the lead, not even into doc_reviews, so
//      nothing recorded that it had arrived. The same journey by EMAIL has worked for weeks. This
//      is that path, reused rather than reinvented: same bucket, same sanitiser, same extractor,
//      same columns, same audit row.
//
// 9 Nov 2026 (customer_support): THE HANDLER IS SPLIT BY SUBJECT. This file keeps the entry point and the order the turn runs in;
// every block is the code it always was, moved unchanged (where a block reassigned a local another block reads, it is now t.<name>, see turn.ts):
//   shared.ts        the service-role client, secrets reader, IT finding, agent_runs logger, throttled alert
//   signature.ts     webhook authenticity: provenance lookup and X-Twilio-Signature
//   replies.ts       toContact (guard + bidi) and sendWa
//   media.ts         download one attachment from Twilio, store/read/apply it to a lead
//   faq.ts           the question embedding and the approved-FAQ retrieval
//   turn.ts          the state of one turn (what handleInbound's locals became)
//   arrival.ts       read the request, echo/redelivery, authenticate, store on arrival, STOP, invite reply
//   say.ts           the model's words and the held notice
//   spec_offer.ts    a customer's answer to the no-exact-spec alternatives
//   identify.ts      who is this number, the reads started beside the classification, the timeline
//   classification.ts the welcome + menu wiring, the readings, the menu answer
//   compose.ts       the facts the reply is composed from
//   speculation.ts   the reply and the price-change reading started beside the classification
//   founder.ts       the founder's command channel
//   hear.ts          a voice note is heard: its transcript becomes the turn's Body (10 Nov 2026)
//   media_in.ts      a document arrived
//   supplier_directive.ts a supplier's price change
//   general_turn.ts  the database answers first, the model words it, send, record, report
//   burst.ts         the turn gate: several messages in a few seconds get one reply; a loop with an auto-responder stops
//   holding.ts       the typing indicator and the holding line while the reply is written (ruling 1636)
import '../_shared/doc_read/workbook_local.ts'; // reads workbooks and .doc/.msg here with SheetJS (why one line: that file's header)
import { observe } from '../_shared/observe.ts';
import { ackThenWork, detach } from '../_shared/async_webhook.ts';
import { admin, TW, withTurnSecrets } from './shared.ts';
import { newTurn } from './turn.ts';
import { acceptArrival } from './arrival.ts';
import { makeSay } from './say.ts';
import { specOfferReply } from './spec_offer.ts';
import { identify, readTimeline } from './identify.ts';
import { answerFromTheMenu, startClassification } from './classification.ts';
import { startSpeculation } from './speculation.ts';
import { founderTurn } from './founder.ts';
import { mediaIn } from './media_in.ts';
import { hearVoiceNote } from './hear.ts';
import { supplierDirective } from './supplier_directive.ts';
import { memberPhone } from './member_phone.ts';
import { answerTurn } from './general_turn.ts';
import { turnGate } from './burst.ts';
import { endTurnHolding } from './holding.ts';

// TWILIO IS ANSWERED AT ONCE; THE MESSAGE IS HANDLED AFTER (23 Sep 2026). Reasoning (think()) is several
// model calls and Twilio allows 15 s, so a Twilio form post gets its empty <Response/> immediately and the
// handler below runs under EdgeRuntime.waitUntil (_shared/async_webhook.ts). Replies were always sent by
// the REST API (sendWa), never in the webhook response. An internal JSON caller still waits for the result.
Deno.serve(observe('wa_inbound', async (req) => {
  if ((req.headers.get('content-type') || '').includes('application/json')) return await handleInbound(req);
  const copy = await detach(req);
  return ackThenWork(TW(200), () => handleInbound(copy), 'wa_inbound');
}));

// every setting is read once per turn (shared.ts withTurnSecrets, R7 10 Nov 2026)
function handleInbound(req: Request): Promise<Response> { return withTurnSecrets(() => handleTurn(req)); }

async function handleTurn(req: Request): Promise<Response> {
  const t = newTurn();
  const { logRun } = t;
  let crashed = false;
  try {
    const arrived = await acceptArrival(t, req); if (arrived) return arrived;
    await hearVoiceNote(t);
    const gated = await turnGate(t); if (gated) return gated;   // a burst is answered once; a loop with a machine stops (burst.ts)
    makeSay(t);
    const specOffer = await specOfferReply(t); if (specOffer) return specOffer;
    await identify(t);
    const memberCode = await memberPhone(t); if (memberCode) return memberCode;   // a company member confirming his number (member_phone.ts)
    await startClassification(t);
    startSpeculation(t);
    const fromMenu = await answerFromTheMenu(t); if (fromMenu) return fromMenu;
    await readTimeline(t);
    const founder = await founderTurn(t); if (founder) return founder;
    const document = await mediaIn(t); if (document) return document;
    const repriced = await supplierDirective(t); if (repriced) return repriced;
    return await answerTurn(t);
  } catch (e) {
    crashed = true;
    await logRun('error', {}, 'exception (the arrival row stays at stage received; fn_wa_arrival_sweep hands it to customer_support): ' + String((e as Error)?.message || e));
    return TW(200);
  } finally {
    // A turn that FINISHED but wrote no row of its own (a branch that answers without waInsert) closes its arrival row,
    // so only a crashed or killed turn is left at 'received' for fn_wa_arrival_sweep (5 minutes, once, to customer_support).
    if (!crashed && t.arrivalId != null) {
      try {
        const h = await admin.from('wa_messages').update({ meta: { stage: 'handled', message_sid: t.messageSidSeen || null } }).eq('id', t.arrivalId).eq('meta->>stage', 'received').select('id');
        if (!h.error && (h.data?.length ?? 0) === 0) await admin.rpc('fn_wa_arrival_turn_finished', { p_wa_message_id: t.arrivalId });
      } catch (_e) { /* the sweep will escalate it: noisy, never silent */ }
    }
    // The turn is over: a holding line not yet sent never goes now, and one in flight lands before the worker ends (holding.ts).
    // The turn is over: the holding line is released, and if it went and no reply followed (the turn threw, or ended on a branch
    // that sent nothing), the turn is filed for the model's re-ask, so the person told "shortly" is answered (holding.ts).
    try { await endTurnHolding(t); } catch (_e) { /* the arrival sweep still hands the message to customer_support */ }
    // The case step (say.ts): once, for the reply that was delivered; kept alive past the turn (case_memory.ts waitUntil).
    // The words are recorded without the bidi isolates sendWa added (review round 2).
    try { t.stopListening?.(); if (t.caseAfter && t.deliveredReply) t.caseAfter(t.deliveredReply.replace(/[\u2066-\u2069]/g, '')); } catch (_e) { /* caseCatchup owes it */ }
    // The review of a decision (started beside the reply) is filed even when the turn threw after it started.
    try {
      await t.reviewP;
    } catch (_e) { /* fileReviewRequest never throws; a lost review row must never cost the turn */ }
  }
}
