// optin_code.ts - A SUPPLIER WHO SAID YES TO JOB REQUESTS ON WHATSAPP CONFIRMS HIS NUMBER BY SENDING, FROM IT, THE CODE OUR E-MAIL
// GAVE HIM (marketing, 16 Nov 2026; agent L2_OPTIN; ledger 1184/1373; _shared/whatsapp_offer.ts). The same proof a company member
// gives (member_phone.ts): he writes to us first, from the number that should receive the requests, so no number is ever messaged
// before it agreed. Only an 8-digit code in a short message is checked (code compares a reference, it reads no meaning); the
// number that sent it is the number recorded (fn_supplier_whatsapp_optin_confirm). The reply is written by the model from the
// routine's result (rulings 1195-1197), as every WhatsApp reply. A customer's number is never this step.
// prevented by: wa_inbound/optin_code.test.ts
import { admin, sec, TW } from './shared.ts';
import { sendWa, toContact } from './replies.ts';
import { optinCodeIn } from '../_shared/whatsapp_offer.ts';
import type { WaTurn } from './turn.ts';

/** What the reply says, from the routine's answer. null: not an opt-in code (the ordinary turn answers the message). */
export function optinSituation(r: { ok?: boolean; code?: string; company_name?: string } | null): string | null {
  if (!r || r.code === 'no_code' || r.code === 'no_pending_code') return null;
  if (r.ok) {
    return `A supplier sent, from this number, the code our e-mail gave him after he agreed to get job requests on WhatsApp. Confirmed: job requests for ${r.company_name ?? 'his company'} `
      + 'now come to this WhatsApp number as well as by e-mail. Thank him and say so in two sentences; he can reply STOP at any time to stop them.';
  }
  return `A supplier sent a code to confirm this WhatsApp number for job requests, and it was not accepted (${
    r.code === 'too_many_tries' ? 'too many wrong codes from this number today: he can try again tomorrow, or reply to our e-mail for a new code'
    : r.code === 'number_belongs_to_another' ? 'this number is already registered to another account with us, so it cannot be used for this company'
    : r.code === 'declined' ? 'his company told us it does not want WhatsApp messages; he can change that by replying to our e-mail'
    : 'the code could not be checked'}). Say so briefly; nothing was changed.`;
}

export async function optinCode(t: WaTurn): Promise<Response | undefined> {
  const { From, Body, Profile, MessageSid, receivedAt, audience, logRun, waInsert, sayFor, heldTurn } = t;
  if (audience === 'customer') return undefined;
  const code = optinCodeIn(Body);
  if (!code) return undefined;
  const { data: d, error } = await admin.rpc('fn_supplier_whatsapp_optin_confirm', { p_phone: From, p_code: code });
  if (error) { await logRun('error', { route: 'optin_code' }, 'a WhatsApp opt-in code was not checked: ' + error.message + '; the turn continues.'); return undefined; }
  const r = d as { ok?: boolean; code?: string; company_name?: string } | null;
  const situation = optinSituation(r);
  if (!situation) return undefined;   // not an opt-in code: the ordinary turn answers
  const out = await sayFor('supplier')(situation, 'en');
  let reply = out ? toContact(out.slice(0, 1200)) : '';
  const enabled = (await sec('wa_autoreply_enabled')) === 'true';
  let sent = false; let sendErr: string | undefined = reply ? undefined : 'no_model_reply';
  if (enabled && reply) { const s = await sendWa(From, reply); sent = s.ok; sendErr = s.err; }
  if (!reply) { const h = await heldTurn('supplier', 'en', situation, 'optin_code'); reply = h.notice; sent = h.sent; sendErr = h.err ?? undefined; }
  try {
    await waInsert(receivedAt, {
      wa_from: From, wa_to: 'whatsapp:' + (await sec('twilio_wa_from')), profile_name: Profile, inbound: Body, reply, lang: 'en', escalated: false, sent,
      meta: { enabled, audience: 'supplier', route: 'optin_code', confirmed: r?.ok === true, refusal: r?.ok ? null : r?.code ?? null, send_error: sendErr || null, message_sid: MessageSid || null },
    });
  } catch (_e) { /* the reply already went out */ }
  await logRun(r?.ok ? 'ok' : 'error', { audience: 'supplier', route: 'optin_code', confirmed: r?.ok === true, sent }, 'supplier WhatsApp opt-in ' + (r?.ok ? 'confirmed' : 'not confirmed: ' + String(r?.code)));
  return TW(200);
}
