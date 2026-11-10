// general_turn.ts - THE DATABASE ANSWERS FIRST (v19), then the model words it: route through fn_wa_route, compose the facts, take the
// speculative draft or ask the reply, guard it, send it (or the held notice), record the turn, report a failed send or an escalation to
// the CEO seat, and log the run. Moved out of index.ts's handleInbound (9 Nov 2026, customer_support); the reply state is read from and
// written to the turn as t.<name>.
import { fileReviewRequest } from '../_shared/review_request.ts';
import { isDemoPhone } from '../_shared/demo_identity.ts';
import { defaultDeps } from '../_shared/think.ts';
import { composeSituation } from './compose.ts';
import { laneOf } from './status_lane.ts';
import { admin, sec, TW } from './shared.ts';
import { sendWa, toContact } from './replies.ts';
import type { WaTurn } from './turn.ts';

// ---- THE DATABASE ANSWERS FIRST (v19, 7 Sep 2026) ----------------------
// The WhatsApp brain built in SQL -- fn_wa_route, fn_wa_record_turn, fn_wa_fact_pack, the
// intent table, the off-topic sentence, the founder-number rule -- was finished and connected
// to nothing: this function still went straight to a model for every public message. It is
// connected here.
//
// WHY THE DATABASE GOES FIRST. Every fact about a person, a job, a quote or a price comes from
// their own row or from the company register, and a model asked to recall those invents them.
// fn_wa_route matches the message against the intent table and, for everything it recognises,
// hands back a finished sentence built from those rows. That answer costs nothing, cannot
// drift, and is the same answer every time the same question is asked.
//
// WHAT IT DOES NOT DO. It never shadows the supplier price-change directive above (that block
// returns before this one is reached) and it never shadows a document (the media branch
// returns too). When the route says a model is needed -- another language, a complaint, a
// question the table does not carry -- this falls THROUGH to the model path below, which now
// also receives the fact pack, so the model supplies language and the database still supplies
// every fact.
//
// THE TURN IS RECORDED EITHER WAY, inbound and outbound, so the agent has a memory of the
// conversation and the 24-hour window is opened by the INBOUND message alone -- which is what
// WhatsApp's own rules say opens it.
export async function answerTurn(t: WaTurn): Promise<Response> {
  const { From, Body, Profile, MessageSid, media, audience, timelineEvents, timings, mark, receivedAt, logRun, waInsert, menuDeps, needsPersonP, speculative, specAbort, adopt, say, heldTurn } = t;
  let route: Record<string, unknown> | null = null;
  // WHETHER THIS NEEDS A PERSON IS REASONED, NOT MATCHED (23 Sep 2026, founder_instruction 886-903).
  // fn_wa_route used to decide it with a word list over the body ('legal' escalated "is it legal to
  // build a pool?"; "you took my money and vanished" was not escalated). think() reads the message; under
  // the hold the answer is null, the message waits in customer_support's queue, and nobody is escalated
  // on a guess (_shared/reasoned_decisions.ts).
  let needsPerson: boolean | null = null;
  if (Body.trim()) needsPerson = await needsPersonP();
  mark('classified');
  // A person asked to review an automated decision (ledger 1152): it is filed with the seat that owns that decision
  // (review_route), decided by another model family. Only asked when the reasoning above already said a person.
  // IT RUNS BESIDE THE REPLY, NOT BEFORE IT (customer_support, 3 Nov 2026). Measured on the real exchange on main (run
  // 41530397323, ai_cost_log 66624 and 66653): its think() took 19 s and 25 s in series ahead of the reply on the lean "scam"
  // turn, so the reply started ~65 s after arrival, ran out of its 90 s budget and the person got nothing. The reply reads
  // nothing it writes; it is awaited in the turn's finally, so a throw after this line still files it. Prevented by: the_whole_exchange.test.ts.
  t.reviewP = needsPerson === true
    ? fileReviewRequest(admin, defaultDeps(admin, 'wa_inbound'), { channel: 'whatsapp', requester: From, message: Body,
        surface: 'wa_inbound.review_of_decision', dedupeKey: MessageSid || From + ':' + Body.slice(0, 40),
        audience: audience === 'supplier' ? 'supplier' : 'customer', subjectTable: 'wa_conversation', subjectId: From })
    : Promise.resolve(null);
  // Held is not "no". Until the reasoning runs, the CEO seat SEES the message (visibility, no page), so a
  // complaint is never silently parked; the replay then gives the contact on WhatsApp if a person is needed.
  if (needsPerson === null && Body.trim()) {
    try {
      await admin.rpc('fn_support_report_to_ceo', {
        p_idempotency_key: 'wa:held:' + (MessageSid || From + ':' + Body.slice(0, 40)), p_severity: 'routine',
        p_subject: 'A WhatsApp message is waiting to be reasoned (model hold): whether it needs a person is not yet known',
        p_evidence: { from: From, message: Body.slice(0, 300) },
        p_attempted: ['answered from the database', 'queued the person check in customer_support\'s reasoning queue'],
        p_requested: 'Visibility only. It is reasoned and answered on WhatsApp the moment the hold lifts.',
      });
    } catch (_e) { /* visibility must not block the reply */ }
  }
  let routedIntent: string | null | undefined;
  try {
    // The intent is the REASONED meaning (above), never the body's words: null = held, 'none' = no row fits.
    const meaning = await menuDeps.intent(Body);
    const read = meaning === null ? null : meaning.startsWith('intent:') ? meaning.slice(7) : meaning;
    // A PERSON IS NEEDED AND NO INTENT ROW WAS READ: the row for a person (customer_support, 3 Nov 2026). Run 41544169700: the lean
    // reading of "I want to speak to a person please" did not settle (intent null, 26 s), its fallback person check said yes, and
    // the route got no intent where the full shape gave contact_human. Same rule as whatsappReadings, for the case the reading
    // itself returned nothing. Prevented by: the_whole_exchange.test.ts.
    const intent = (read === null || read === 'none') && needsPerson === true ? 'contact_human' : read;
    routedIntent = intent;
    const { data } = await admin.rpc('fn_wa_route', { p_phone: From, p_body: Body.slice(0, 4000), p_has_audio: media.length > 0, p_needs_person: needsPerson, p_intent: intent });
    route = (data || null) as Record<string, unknown> | null;
  } catch (_e) { /* the brain being unreachable must never lose their message */ }

  try {
    await admin.rpc('fn_wa_record_turn', {
      p_phone: From, p_direction: 'in', p_body: Body.slice(0, 4000),
      p_intent: (route?.deterministic_intent as string) || null,
      p_fact_pack: (route?.fact_pack as unknown) ?? null,
    });
  } catch (_e) { /* memory is worth less than the reply */ }

  const routeAction = String(route?.action || '');
  // 1195-1197 (12 Oct 2026): no stored sentence is ever the reply — not fn_wa_route's deterministic answer, not the
  // welcome, not an FAQ row, not even under the hold. They are FACTS the model answers from (below). With no model
  // (the hold, every model in the chain failing) nothing conversational is sent; the meaning waits in the queue.

  const { situation, ids, lean } = await composeSituation(t, route);
  // THE LANE (status_lane.ts, ruling 1571): a status, invoice-copy or code ask is worded on status_reply from the sender's own
  // facts; a new job gets the request chat's link; everything else, and every turn needing a person, takes the full path.
  const lane = laneOf(routedIntent, needsPerson === true || route?.needs_a_person === true);
  timings.lane = lane === 'status' ? 1 : lane === 'app' ? 2 : 0;
  mark('facts_ready');
  // The speculative draft is the reply only when the real route's inputs are exactly the ones it was composed on.
  // An empty draft (rate-limited, aborted, refused) is no draft: the reply is then asked on the real route, as before.
  const adoptable = speculative && needsPerson === false && routedIntent === 'none' && route?.needs_a_person === false;
  const spec = adoptable ? await speculative : null;
  if (!(spec && spec.text)) specAbort.abort();   // discarded: stop paying for it
  const drafted = spec && spec.text ? spec : null;
  timings.speculative = drafted ? 1 : 0;
  // A person is needed: the facts carry the contact and what to say, so the last chance may answer without the brief.
  t.factsAnswer = needsPerson === true || route?.needs_a_person === true || routedIntent === 'contact_human';
  let reply = (drafted ? adopt(drafted) : lane === 'conversation' ? await say(situation)
    : await t.sayLane(lane, lean, String(route?.deterministic_reply || ''))).slice(0, 1200);
  mark('reply_written');
  const llmFailed = !reply;
  const escalate = route?.needs_a_person === true || t.modelEscalate;
  const lang = /[؀-ۿ]/.test(reply || Body) ? 'ar' : 'en';
  const audienceFinal = audience;
  if (!reply) {
    try { await menuDeps.recordGap(Body, 'no_model_answer'); } catch (_e) { /* */ }
  }
  // The model's reply is checked before it is sent (support_reply_guard.ts): '' = refused after aiReply's own rewrites.
  if (reply) { reply = toContact(reply); if (!reply) t.sayAttempts.push('support_reply_guard refused the written reply'); }

  const enabled = (await sec('wa_autoreply_enabled')) === 'true';
  let sent = false; let sendErr: string | undefined;
  let heldNotice = false;
  if (reply) { if (enabled) { const r = await sendWa(From, reply); sent = r.ok; sendErr = r.err; } }
  else {
    // The turn is queued for the model's answer; the fixed held notice goes out now only if OpenRouter is down (1339).
    const h = await heldTurn(audience === 'supplier' ? 'supplier' : audience === 'customer' ? 'customer' : 'visitor', lang, situation, t.sayOutage ? 'no_model_answer' : t.sayProblems.length || !llmFailed ? 'guard_refused' : 'no_usable_answer_in_budget');
    reply = h.notice; sent = h.sent; sendErr = h.err ?? undefined; heldNotice = !!h.notice;
  }

  let rowSaved = true;
  try { const { error: wErr } = await waInsert(receivedAt, { wa_from: From, wa_to: 'whatsapp:' + (await sec('twilio_wa_from')), profile_name: Profile, inbound: Body, reply, lang, escalated: escalate, sent, meta: { timings, enabled, reply_attempts: t.sayAttempts, matched_faq_ids: ids, timeline_events: timelineEvents, route_action: routeAction || null, held_notice: heldNotice, model_written: !heldNotice, route_intent: route?.deterministic_intent ?? null, inference_held: route?.inference_held === true, asked_for_a_person: route?.needs_a_person === true, bidi_isolated: /[⁦]/.test(reply), audience: audienceFinal, audience_source: audience !== 'unknown' ? 'phone_lookup' : 'inferred', send_error: sendErr || null, provenance_verified: true, message_sid: MessageSid || null, ...(t.voice ? { voice: t.voice } : {}) } }); if (wErr) rowSaved = false; } catch (_e) { rowSaved = false; }


  // A captured fixture send (isDemoPhone: never handed to Twilio) is not a failed delivery: the QA channels run of 19 Oct
  // 2026 filed support_ceo_report 13811/13812/13887/13890 'A WhatsApp reply could not be delivered' for ZZ DEMO numbers.
  if (enabled && !sent && !isDemoPhone(From)) {
    // A FAILED SEND IS THE CEO'S, not the founder's. It was a founder_alerts row and an email
    // to him; under constitution 1.2 neither agent sends him unsolicited operational alerts.
    try {
      await admin.rpc('fn_support_report_to_ceo', {
        p_idempotency_key: 'wa:send_failed:' + (MessageSid || From),
        p_severity: 'elevated',
        p_subject: 'A WhatsApp reply could not be delivered',
        p_evidence: { to: From, provider_error: sendErr || null, audience: audienceFinal },
        p_attempted: ['composed the reply', 'attempted delivery through the configured sender'],
        p_requested: 'Decide whether to retry on this channel or reach the customer another way.',
      });
    } catch (_e) { /* */ }
    // THE EMAIL ASKING HIM TO 'FOLLOW UP BY HAND' IS GONE. That is a human dependency, and the
    // CEO report queued just above already carries the same failure to the seat that can act on
    // it. Constitution 1.2: neither agent sends him unsolicited operational alerts.
  }

  if (escalate) {
    // AN ESCALATION GOES TO THE CEO. This wrote an email to the founder and a founder_alerts
    // row saying a message "needs a human". Under constitution 1.2 there is no human queue and
    // no founder escalation: the CEO is the final internal authority and the one that can act.
    try {
      await admin.rpc('fn_support_report_to_ceo', {
        p_idempotency_key: 'wa:escalation:' + (MessageSid || From),
        p_severity: 'serious',
        p_subject: 'A WhatsApp conversation needs a decision support cannot make',
        p_evidence: { from: From, message: Body.slice(0, 400), audience: audienceFinal, replied: sent },
        p_attempted: ['answered from live account facts and approved knowledge', 'checked the standing grant'],
        p_requested: 'Decide the outcome, or issue a standing grant that covers it.',
      });
    } catch (_e) { /* */ }
  }

  const counts = { audience: audienceFinal, lang, escalated: escalate, autoreply_enabled: enabled, sent, llm_failed: llmFailed, faq_matches: ids.length, row_saved: rowSaved, provenance_verified: 1 };
  if (llmFailed) await logRun('error', counts, 'no model answered - the held notice was sent and the turn queued for the model');
  else if (enabled && !sent) await logRun('error', counts, 'reply composed but Twilio refused to send: ' + (sendErr || 'unknown'));
  else if (!rowSaved) await logRun('error', counts, 'reply handled but wa_messages row failed to save - conversation history will be incomplete');
  else await logRun('ok', counts, escalate ? 'escalated to founder' : '');

  return TW(200);
}
