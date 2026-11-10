// spec_offer.ts - AN ANSWER TO "NO SUPPLIER QUOTED YOUR EXACT SPEC": a customer's "2", "option 2", "yes" or "no" to the numbered
// alternatives. Moved out of index.ts's handleInbound unchanged (9 Nov 2026, customer_support). A Response means the message
// was such an answer and the turn is over; undefined means it was not and the normal route runs.
import { arabicTextsFor } from '../_shared/reasoned_governance.ts';
import { registeredLocale } from '../_shared/registered_locale.ts';
import { acceptedMessage, apologyMessage, offerTexts, type OfferForText } from '../_shared/line_specs/no_exact_spec.ts';
import { defaultDeps } from '../_shared/think.ts';
import { admin, sec, TW } from './shared.ts';
import { sendWa, toContact } from './replies.ts';
import type { WaTurn } from './turn.ts';

// ---- AN ANSWER TO "NO SUPPLIER QUOTED YOUR EXACT SPEC" (14 Sep 2026, agent: customer_support) ----
// Founder, 14 Sep 2026 (founder_instruction #321): when no supplier could quote the customer's exact
// spec, customer_support asks on WhatsApp which of the numbered alternatives to proceed with. The
// customer answers here: "2", "٢", "option 2", "yes" (one option) or "no"/"لا".
// THE ROUTINE OWNS PARSING. fn_spec_offer_whatsapp_reply finds the customer by phone and their oldest
// open offer, reads the text and records the answer; this block only speaks the result. handled:false
// (or any rpc fault) means this message is not such an answer, and the normal route below runs
// exactly as before. Text only: a file is never an answer to a numbered question.
export async function specOfferReply(t: WaTurn): Promise<Response | undefined> {
  const { From, Body, Profile, MessageSid, media, receivedAt, logRun, waInsert, sayFor, heldTurn } = t;
  if (Body && !media.length) {
    let so: Record<string, any> | null = null;
    try {
      const { data, error } = await admin.rpc('fn_spec_offer_whatsapp_reply', { p_phone: From.replace(/^whatsapp:/i, ''), p_text: Body.slice(0, 500) });
      if (error) await logRun('error', { route: 'spec_offer_reply', rpc_error: 1 }, 'fn_spec_offer_whatsapp_reply failed, so this message took the normal route: ' + error.message);
      else so = (data || null) as Record<string, any> | null;
    } catch (e) {
      await logRun('error', { route: 'spec_offer_reply', rpc_error: 1 }, 'fn_spec_offer_whatsapp_reply threw, so this message took the normal route: ' + String((e as Error)?.message || e));
    }
    if (so?.handled === true) {
      let lang: 'en' | 'ar' = 'en';
      if (so.customer_id) lang = await registeredLocale(admin, { role: 'customer', customerId: String(so.customer_id) });
      let text = '';
      const sayC = (situation: string, must?: string[]) => sayFor('customer')(situation, lang, must);
      // notice: the templated confirmation went out because OpenRouter was down (founder_instruction 1339). The accepted
      // offer's confirmation is a reply to their message, so the model writes it from the template; never otherwise.
      let notice = false;
      if (so.ok === true) {
        const { data: offer } = await admin.from('spec_alternative_offer')
          .select('item,label_en,label_ar,requested,alternatives,accepted_value,inquiry_id').eq('id', so.offer_id).single();
        const { data: inq } = await admin.from('inquiries').select('rfq_no').eq('id', offer?.inquiry_id ?? so.inquiry_id).maybeSingle();
        if (offer) {
          const o = { ...offer, accepted_value: offer.accepted_value ?? so.accepted_value ?? null } as OfferForText;
          const arTexts = so.state === 'accepted' ? await arabicTextsFor(defaultDeps(admin, 'wa_inbound'), lang, offerTexts(o), { fileOnly: true }) : undefined;
          const msg = so.state === 'accepted' ? acceptedMessage(o, lang, { rfqNo: inq?.rfq_no, arTexts }) : apologyMessage(o, lang, 'declined', { rfqNo: inq?.rfq_no });
          if (msg.untranslated?.length) {
            // Never an Arabic reply with English in it. A fixed acknowledgement (no free text) answers now; the full
            // confirmation is parked and goes by email and WhatsApp once its Arabic is reasoned (fn_arabic_outbound_flush).
            text = await sayC('They chose an alternative and the choice is recorded. The full written confirmation is on its way to them by email and WhatsApp shortly. Thank them; do not restate the offer.');
            const { data: cu } = so.customer_id ? await admin.from('customers').select('email').eq('id', String(so.customer_id)).maybeSingle() : { data: null };
            if (cu?.email) {
              const base = { type: 'spec_offer_accepted', kind: 'customer_support_spec_offer_accepted', to_role: 'customer', inquiry_id: String(offer.inquiry_id ?? so.inquiry_id), subject: msg.subject, body: msg.body, status: 'queued', lang, requested_by: 'customer_support', sender: 'customer_support' };
              const rows = [{ ...base, channel: 'email', to_email: cu.email, dedupe_key: `spec_offer:${so.offer_id}:accepted:email` },
                            { ...base, channel: 'whatsapp', to_email: cu.email, dedupe_key: `spec_offer:${so.offer_id}:accepted:whatsapp` }];
              const { error: pErr } = await admin.rpc('fn_arabic_outbound_park', { p_texts: msg.untranslated, p_rows: rows });
              if (pErr) await logRun('error', { route: 'spec_offer_reply', parked: 0 }, 'the Arabic confirmation could not be parked: ' + pErr.message);
            }
          } else if (so.state === 'accepted') {
            text = await sayC('They chose an alternative and it is recorded. Our written confirmation, to convey accurately in your own words (keep the job number, the item and the accepted value exactly):\n' + msg.body,
              inq?.rfq_no ? [String(inq.rfq_no)] : undefined);
            if (!text && t.sayOutage) { text = msg.body; notice = true; }   // OpenRouter down: the template is the outage fallback
          }
          else text = await sayC('They declined the alternatives offered for job ' + String(inq?.rfq_no ?? '') + '. What we tell them about it (convey it accurately):\n' + msg.body);
        }
      } else if (so.error === 'unknown_option') {
        const n = Number(so.options || 0);
        text = await sayC(`Their reply did not match any of the ${n} numbered alternatives we offered. Ask them to reply with the option number (1 to ${n}), or NO to decline them all.`);
      }
      // The answer is already recorded by the routine; a missing offer row must not make it silent.
      if (!text) text = await sayC('Their answer to the alternatives we offered has been received and recorded.');
      let replyS = text ? toContact(text.slice(0, 1200)) : '';
      const enabledS = (await sec('wa_autoreply_enabled')) === 'true';
      let sentS = false; let sendErrS: string | undefined = replyS ? undefined : 'no_model_reply';
      if (enabledS && replyS) { const r = await sendWa(From, replyS); sentS = r.ok; sendErrS = r.err; }
      let heldS = false;
      if (!replyS) { const h = await heldTurn('customer', lang, 'The no-exact-spec routine recorded their answer: ' + JSON.stringify(so), 'spec_offer_reply'); replyS = h.notice; sentS = h.sent; sendErrS = h.err ?? undefined; heldS = true; }
      if (so.ok === true && so.offer_id) {
        try { await admin.rpc('fn_spec_offer_mark', { p_offer: so.offer_id, p_action: 'answered', p_notification_ids: [] }); }
        catch (_e) { /* best effort: the answer itself is recorded */ }
      }
      try {
        await waInsert(receivedAt, {
          wa_from: From, wa_to: 'whatsapp:' + (await sec('twilio_wa_from')), profile_name: Profile,
          inbound: Body, reply: replyS, lang, escalated: false, sent: sentS,
          meta: { enabled: enabledS, audience: 'customer', route: 'spec_offer_reply', result: so, model_written: !notice && !heldS, notification: notice, held_notice: heldS,
                  send_error: sendErrS || null, provenance_verified: true, message_sid: MessageSid || null },
        });
      } catch (_e) { /* the reply already went out */ }
      await logRun('ok', { route: 'spec_offer_reply', state: so.state || so.error || null, sent: sentS },
        'customer answered a no-exact-spec offer by WhatsApp: ' + String(so.state || so.error || 'unknown'));
      return TW(200);
    }
  }
}
