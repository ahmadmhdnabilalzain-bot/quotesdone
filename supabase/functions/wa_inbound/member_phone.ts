// member_phone.ts - A COMPANY MEMBER CONFIRMS HIS WHATSAPP NUMBER BY SENDING, FROM IT, THE CODE HIS PORTAL SHOWED HIM (customer_support,
// 16 Nov 2026; agent SUPPLIER_W2; SUPPLIER hole 4). WhatsApp knew one owner number per company; an estimator writing from his own
// phone was a stranger. A member signed in to the portal asks for a code (supplier_api member_phone_code); the number that sends it
// here becomes his company's voice (fn_supplier_member_confirm_phone, then fn_whatsapp_owner's member branch). Only a number we do
// not know yet is offered this step, and only a six-digit code is checked: code compares a reference, it reads no meaning.
// The reply is written by the model from the routine's result (rulings 1195-1197), as every WhatsApp reply.
// prevented by: wa_inbound/member_phone.test.ts
import { admin, sec, TW } from './shared.ts';
import { sendWa, toContact } from './replies.ts';
import type { WaTurn } from './turn.ts';

/** The six-digit code in a short message from an unknown number, or null (a longer message is a conversation, not a code). */
export function codeIn(body: string): string | null {
  const b = String(body || '').replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660)).trim();
  if (b.length > 60) return null;
  const m = b.match(/(?:^|\D)(\d{6})(?:\D|$)/);
  return m ? m[1] : null;
}

export async function memberPhone(t: WaTurn): Promise<Response | undefined> {
  const { From, Body, Profile, MessageSid, receivedAt, audience, logRun, waInsert, sayFor, heldTurn } = t;
  if (audience !== 'unknown') return undefined;
  const code = codeIn(Body);
  if (!code) return undefined;
  const { data: d, error } = await admin.rpc('fn_supplier_member_confirm_phone', { p_phone: From, p_code: code });
  if (error || !d || (d as { code?: string }).code === 'no_pending_code') return undefined;   // not a member's code: the ordinary turn answers
  const r = d as { ok?: boolean; code?: string; name?: string; role?: string; company_name?: string };
  const situation = r.ok
    ? `A member of a supplier company sent the code his portal showed him, from this number. Confirmed: this number now speaks for ${r.company_name ?? 'his company'} on WhatsApp, as ${r.role === 'estimator' ? 'an estimator (he can ask about jobs, say a job is not for the company, and his quotations are the company\'s)' : 'a viewer (he can ask about the company\'s jobs; only the owner or an estimator can act)'}. Greet ${r.name ?? 'him'} and say so in two sentences.`
    : `Someone sent a code to confirm his WhatsApp number for a supplier company, and it was not accepted (${r.code === 'too_many_tries' ? 'too many wrong codes: he must ask his portal for a new code' : 'the code is wrong or expired: he should ask his portal (Settings, Team) for a new code and send it from this number'}). Say so briefly; nothing was changed.`;
  const out = await sayFor('supplier')(situation, 'en');
  let reply = out ? toContact(out.slice(0, 1200)) : '';
  const enabled = (await sec('wa_autoreply_enabled')) === 'true';
  let sent = false; let sendErr: string | undefined = reply ? undefined : 'no_model_reply';
  if (enabled && reply) { const s = await sendWa(From, reply); sent = s.ok; sendErr = s.err; }
  if (!reply) { const h = await heldTurn('supplier', 'en', situation, 'member_phone'); reply = h.notice; sent = h.sent; sendErr = h.err ?? undefined; }
  try {
    await waInsert(receivedAt, {
      wa_from: From, wa_to: 'whatsapp:' + (await sec('twilio_wa_from')), profile_name: Profile, inbound: Body, reply, lang: 'en', escalated: false, sent,
      meta: { enabled, audience: 'supplier', route: 'member_phone', confirmed: r.ok === true, refusal: r.ok ? null : r.code ?? null, send_error: sendErr || null, message_sid: MessageSid || null },
    });
  } catch (_e) { /* the reply already went out */ }
  await logRun(r.ok ? 'ok' : 'error', { audience: 'supplier', route: 'member_phone', confirmed: r.ok === true, sent }, 'company member WhatsApp number ' + (r.ok ? 'confirmed' : 'not confirmed: ' + String(r.code)));
  return TW(200);
}
