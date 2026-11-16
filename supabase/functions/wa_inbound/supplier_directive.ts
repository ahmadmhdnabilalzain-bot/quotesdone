// supplier_directive.ts - A SUPPLIER ASKING FOR A CHANGE, NOT AN ANSWER (v18): "adjust my quotation price" is applied by
// fn_supplier_apply_change, scoped in SQL by phone. Moved out of index.ts's handleInbound unchanged (9 Nov 2026, customer_support).
// A Response means the change was applied or refused and the turn is over; undefined means it was not a change.
import { amountInOwnWords, supplierDirectiveAllowed } from './directive_gate.ts';
import { admin, sec, TW } from './shared.ts';
import { sendWa, toContact } from './replies.ts';
import type { WaTurn } from './turn.ts';
import { repriceOutagePlan } from './reprice_outage.ts';
import { type Ask, outcomeFacts, supplierInstructionTurn } from '../_shared/supplier_instruction.ts';
import { defaultDeps } from '../_shared/think.ts';
import { isDemoPhone } from '../_shared/demo_identity.ts';
import { waSenderRole } from '../_shared/supplier_company.ts';

// ---- A SUPPLIER ASKING FOR A CHANGE, NOT AN ANSWER (v18) ---------------
// "Adjust my quotation price" is the one verb on the supplier's list, and until now this
// function could only describe what a supplier would have to go and do themselves.
//
// The same shape the founder's settings got, with one difference that matters: the SCOPING IS
// NOT THE MODEL'S JOB. fn_supplier_apply_change resolves the supplier from the phone number in
// SQL and decides everything — which quotation, whether it is committed, whether a customer
// has already paid to reveal them, whether the move is a fat-fingered zero — so the worst a
// misclassification can do is produce a refusal. The model's entire job is turning a sentence
// into a number.
//
// cache_ttl_min: 0 IS LOAD-BEARING, for the reason measured on 13 Aug: ai_gateway's cache does
// a SEMANTIC lookup at 0.95 over (sys_stable + sys).slice(0,400) + convo.slice(0,800), and a
// classifier whose system prompt dwarfs its one-line input gets the PREVIOUS caller's answer.
// Three different founder messages were all classified as the first one's directive that way.
// Twilio-vouched only, never the internal JSON path, and only an amount they wrote (directive_gate.ts, 3 Nov 2026).
export async function supplierDirective(t: WaTurn): Promise<Response | undefined> {
  const { From, Body, Profile, MessageSid, audience, internalCaller, directiveRead, receivedAt, logRun, waInsert, sayFor, heldTurn } = t;
  if (supplierDirectiveAllowed({ audience, internalCaller })) {
    try {
      const parsed = await directiveRead();   // started beside the classification (above); asked here when it was not
      // THE READER IS DOWN (reprice_outage.ts, 10 Nov 2026): a message that states an amount is told so now and filed for
      // one more reading; nothing is applied on a guess. Without an amount it cannot be a re-price: the ordinary path answers.
      // a VIEWER's confirmed number reads, it never re-prices, now or from a held reading (review supplierw2; supplier_company.ts
      // VIEWER_MAY). Asked only when there is a price to change, so an ordinary message pays no extra round trip.
      const viewer = async () => (await waSenderRole(admin, From)).role === 'viewer';
      const out0 = repriceOutagePlan(parsed, From, Body, MessageSid || null);
      if (out0 && !(await viewer())) {
        const { data: heldId, error: holdErr } = await admin.rpc('fn_reason_hold', out0.hold);
        const enabledO = (await sec('wa_autoreply_enabled')) === 'true';
        const r = enabledO ? await sendWa(From, out0.notice) : { ok: false, err: 'autoreply_disabled' };
        try {
          await waInsert(receivedAt, {
            wa_from: From, wa_to: 'whatsapp:' + (await sec('twilio_wa_from')), profile_name: Profile,
            inbound: Body, reply: out0.notice, lang: 'en', escalated: false, sent: r.ok,
            meta: { enabled: enabledO, audience: 'supplier', route: 'supplier_directive_outage', applied: false, held_id: Number(heldId) || null,
                    hold_error: holdErr?.message ?? null, amounts: out0.amounts, why: parsed && 'why' in parsed ? parsed.why : null,
                    send_error: r.err || null, provenance_verified: true, message_sid: MessageSid || null },
          });
        } catch (_e) { /* the notice already went out */ }
        await logRun('error', { audience: 'supplier', route: 'supplier_directive_outage', applied: false, sent: r.ok, held: heldId ? 1 : 0 },
          'a supplier WhatsApp message with an amount could not be read for a price change (reader unavailable): told so, nothing applied, ' + (heldId ? 'filed for one more reading as held question ' + heldId : 'NOT filed: ' + String(holdErr?.message || 'fixture or no row')));
        return TW(200);
      }
      const ownAmount = parsed && parsed.outage !== true && parsed.change === true ? amountInOwnWords(parsed.amount, Body) : null;
      if (ownAmount && !(await viewer())) {
        const { data: applied } = await admin.rpc('fn_supplier_apply_change', {
          p_phone: From, p_field: 'quote_price', p_value: ownAmount,
          p_inbound: Body.slice(0, 1500), p_channel: 'whatsapp',
        });
        if (applied) {
          // The routine decided (re-priced or refused); the model says it to the supplier, in English (1195-1197).
          const out = await sayFor('supplier')('They asked to change their quotation price to AED ' + ownAmount + '. The pricing routine result, to report accurately (applied or refused, old and new total, the reason):\n' + JSON.stringify(applied), 'en');
          let replyD = out ? toContact(out.slice(0, 1200)) : '';
          const enabledD = (await sec('wa_autoreply_enabled')) === 'true';
          let sentD = false; let sendErrD: string | undefined = replyD ? undefined : 'no_model_reply';
          if (enabledD && replyD) { const r = await sendWa(From, replyD); sentD = r.ok; sendErrD = r.err; }
          if (!replyD) { const h = await heldTurn('supplier', 'en', 'The pricing routine result: ' + JSON.stringify(applied), 'supplier_directive'); replyD = h.notice; sentD = h.sent; sendErrD = h.err ?? undefined; }
          try {
            await waInsert(receivedAt, {
              wa_from: From, wa_to: 'whatsapp:' + (await sec('twilio_wa_from')), profile_name: Profile,
              inbound: Body, reply: replyD, lang: 'en', escalated: false, sent: sentD,
              meta: { enabled: enabledD, audience: 'supplier', route: 'supplier_directive',
                      applied: applied?.ok === true, directive: applied, send_error: sendErrD || null,
                      provenance_verified: true, message_sid: MessageSid || null },
            });
          } catch (_e) { /* the reply already went out */ }
          await logRun(applied?.ok === true ? 'ok' : 'error',
            { audience: 'supplier', route: 'supplier_directive', applied: applied?.ok === true, sent: sentD },
            applied?.ok === true
              ? ('supplier re-priced a quotation by WhatsApp: ' + String(applied?.old) + ' -> ' + String(applied?.new))
              : ('supplier price change REFUSED: ' + String(applied?.refusal || '').slice(0, 200)));
          return TW(200);
        }
      }
      // HIS OTHER INSTRUCTIONS (16 Nov 2026, sales_engineer; SUPPLIER holes 2 and 7, FAILURES 2): "not for me", "stop sending me
      // painting jobs", "I'm available", a yes/no to a proposed removal, "the figure is correct". The reading above names the kind;
      // the full reading, with his own requests and profile, and the scoped write are _shared/supplier_instruction.ts.
      const hint = parsed && parsed.outage !== true ? String((parsed as { instruction?: unknown }).instruction ?? 'none') : 'none';
      if (hint && hint !== 'none') { const done = await supplierInstruction(t); if (done) return done; }
    } catch (_e) { /* a classifier failure must never swallow their message: fall through and answer it */ }
  }
}

async function supplierInstruction(t: WaTurn): Promise<Response | undefined> {
  const { From, Body, Profile, MessageSid, receivedAt, logRun, waInsert, sayFor, heldTurn } = t;
  // the number's CONFIRMED supplier, as fn_identify_contact reads it (fn_whatsapp_owner): never a supplier named in the message
  const { data: owner } = await admin.rpc('fn_whatsapp_owner', { p_phone: From });
  const sid = Number(((Array.isArray(owner) ? owner[0] : owner) as { lead_id?: unknown } | null)?.lead_id) || 0;
  if (!sid) return undefined;
  const deps = defaultDeps(admin, 'wa_inbound');
  const ask: Ask = async (sys, input) => (await deps.llm('synthesise', sys, input, { taskClass: 'json_extraction', seat: 'sales_engineer', max: 400, timeoutMs: 25_000,
    subject: isDemoPhone(From) ? { fixture: true, phone: From } : { phone: From }, internal: true })).content ?? null;
  // who is writing: a company member's confirmed number carries his role; otherwise the number is the owner's (16 Nov 2026)
  const sender = await waSenderRole(admin, From);
  const r = await supplierInstructionTurn(admin, ask, { supplierId: sid, message: Body, channel: 'whatsapp', sender });
  if (!r.handled || !r.outcome) return undefined;   // not one of his instructions, or unreadable: the ordinary reply answers it
  const situation = 'The supplier wrote to us about his job requests or the work we send him. ' + outcomeFacts(r.outcome);
  const out = await sayFor('supplier')(situation, 'en');
  let reply = out ? toContact(out.slice(0, 1200)) : '';
  const enabled = (await sec('wa_autoreply_enabled')) === 'true';
  let sent = false; let sendErr: string | undefined = reply ? undefined : 'no_model_reply';
  if (enabled && reply) { const s = await sendWa(From, reply); sent = s.ok; sendErr = s.err; }
  if (!reply) { const h = await heldTurn('supplier', 'en', situation, 'supplier_instruction'); reply = h.notice; sent = h.sent; sendErr = h.err ?? undefined; }
  try {
    await waInsert(receivedAt, {
      wa_from: From, wa_to: 'whatsapp:' + (await sec('twilio_wa_from')), profile_name: Profile,
      inbound: Body, reply, lang: 'en', escalated: false, sent,
      meta: { enabled, audience: 'supplier', route: 'supplier_instruction', instruction: r.outcome.kind, done: r.outcome.done,
              send_error: sendErr || null, provenance_verified: true, message_sid: MessageSid || null },
    });
  } catch (_e) { /* the reply already went out */ }
  await logRun(r.outcome.done ? 'ok' : 'error', { audience: 'supplier', route: 'supplier_instruction', applied: r.outcome.done, sent },
    'supplier instruction by WhatsApp: ' + r.outcome.kind + (r.outcome.done ? ' (recorded)' : ' (not recorded: ' + r.outcome.facts.slice(0, 160) + ')'));
  return TW(200);
}
