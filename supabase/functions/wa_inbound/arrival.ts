// arrival.ts - THE FIRST HALF OF A TURN: read the request (Twilio form or authenticated internal JSON), drop an echo and a
// redelivery, authenticate the form path (signature, else provenance), store the message on arrival, honour STOP and file
// a supplier lead's invite reply. Moved out of index.ts's handleInbound unchanged (9 Nov 2026, customer_support); the
// request fields it reads are put on the turn at the end, for the phases after it. A Response means the turn is over.
import { requireInternal } from '../_shared/internal_auth.ts';
// 22 Sep 2026 (customer_support, instruction 759): the URL Twilio signs, and the welcome + menu.
import { isOwnNumber } from '../_shared/twilio_inbound_signature.ts';
import { isStop } from '../_shared/marketing_send_gate.ts';
import { admin, alertThrottled, itFinding, sec, TW } from './shared.ts';
import { verifyProvenance, verifyTwilioSignature } from './signature.ts';
import { mediaItems, waRow } from './wa_row.ts';
import type { WaTurn } from './turn.ts';

export async function acceptArrival(t: WaTurn, req: Request): Promise<Response | undefined> {
  const { logRun, receivedAt, waInsert } = t;
  let From = '', Body = '', Profile = '', MessageSid = '';
  // An interactive list or button reply names the option chosen (the menu, 22 Sep 2026).
  let ListId = '', ButtonPayload = '';
  const media: { url: string; mime: string }[] = [];
  let trusted = false; // true once we know the request really came from Twilio (or an internal caller)
  // NOT the same as `trusted`: a valid Twilio signature also sets trusted. This is true only for
  // an authenticated internal JSON caller, and it is the sole thing that permits inline media.
  let internalCaller = false;
  // True only when X-Twilio-Signature verified: the one proof a founder setting change accepts (directive_gate.ts).
  let signatureVerified = false;
  const formParams: Record<string, string> = {}; // every POST param, needed for signature validation
  let locationOf: Record<string, string> | null = null; // the JSON path's location fields (the form path reads formParams)
  const ct = req.headers.get('content-type') || '';

  if (ct.includes('application/json')) {
    const j = await req.json().catch(() => ({} as any));
    // SECURITY FIX 19 Jul 2026: this used to be
    //   if (j.__secret !== undefined && j.__secret !== await sec('inbound_secret')) return TW(200);
    // which only rejected a WRONG secret - a JSON POST with NO __secret at all skipped the check
    // entirely and reached the send path. Now fails closed.
    // AUDIT 9.5 (3 Aug 2026): the gate now asks fn_internal_auth, which accepts both the new
    // per-context credential and the legacy shared secret, and records which one called. The
    // fail-closed property the 19 Jul 2026 fix established is preserved: requireInternal
    // refuses an absent credential and refuses when the verifier cannot be reached.
    const __auth = await requireInternal(admin, j?.__secret, 'wa_inbound');
    if (!__auth.ok) {
      await logRun('error', { authorised: 0, path: 'json' }, 'wa_inbound rejected a JSON caller with a missing or wrong inbound secret. Until 19 Jul 2026 a JSON POST with no __secret was ACCEPTED and could trigger an outbound WhatsApp to any number, so this rejection may be a scanner probing the old hole. No message was processed and nothing was sent.');
      return TW(200);
    }
    From = j.From || ''; Body = j.Body || ''; Profile = j.ProfileName || ''; MessageSid = j.MessageSid || '';
    ListId = String(j.ListId || ''); ButtonPayload = String(j.ButtonPayload || '');
    locationOf = { Latitude: String(j.Latitude ?? ''), Longitude: String(j.Longitude ?? ''), Address: String(j.Address ?? ''), Label: String(j.Label ?? '') };
    for (let i = 0; i < Number(j.NumMedia || 0) && i < 5; i++) {
      if (j['MediaUrl' + i]) media.push({ url: String(j['MediaUrl' + i]), mime: String(j['MediaContentType' + i] || '') });
    }
    trusted = true; internalCaller = true; // authenticated internal caller (replay tooling)
  } else {
    const p = new URLSearchParams(await req.text());
    From = p.get('From') || ''; Body = p.get('Body') || ''; Profile = p.get('ProfileName') || ''; MessageSid = p.get('MessageSid') || p.get('SmsMessageSid') || '';
    ListId = p.get('ListId') || ''; ButtonPayload = p.get('ButtonPayload') || '';
    // Signature validation needs every POST param, not just the four we consume.
    for (const [k, v] of p.entries()) formParams[k] = v;
    for (let i = 0; i < Number(p.get('NumMedia') || 0) && i < 5; i++) {
      const u = p.get('MediaUrl' + i);
      if (u) media.push({ url: u, mime: p.get('MediaContentType' + i) || '' });
    }
  }
  // A SHARED LOCATION IS A MESSAGE (it_engineer, 10 Nov 2026, channels audit). WhatsApp sends a location pin with an EMPTY Body and
  // no media, only Latitude / Longitude (Address and Label when the pin names a place), so the guard below dropped it before the
  // redelivery guard, the arrival row or any log: a customer who shared their site was stored nowhere and answered never. It is
  // now the turn's text, in our own fixed words (what they shared, never a reading of it); the signature still covers every
  // posted parameter (formParams), because Body is rebuilt here, after they were collected.
  // prevented by: the_whole_exchange.test.ts (a shared location is stored and answered).
  if (!Body && !media.length) Body = locationText(ct.includes('application/json') ? null : formParams, locationOf);
  // A WhatsApp attachment usually arrives with an EMPTY Body — the caption is optional. The
  // original guard returned 200 and dropped it, which is the whole of why an attached trade
  // licence achieved nothing even before the media params went unread.
  if (!From || (!Body && !media.length)) return TW(200);

  // AN ECHO IS NOT A CONVERSATION (22 Sep 2026). A message whose sender is our own WhatsApp number is
  // our own traffic coming back; answering it would have the company talk to itself, once per reply.
  if (isOwnNumber(From, await sec('twilio_wa_from'))) {
    await logRun('ok', { echo: 1 }, 'ignored a webhook whose sender is our own WhatsApp number; nothing was answered');
    return TW(200);
  }

  // IDEMPOTENCY. Twilio redelivers a webhook it believes timed out, and until now nothing here
  // remembered a MessageSid: a redelivery meant a second model call, a second WhatsApp reply and
  // a second wa_messages row. The primary key on wa_inbound_seen IS the guard - the second
  // delivery loses the insert and we return 200 having done nothing. This must stay ABOVE the
  // founder branch below, which deliberately answers after the 15-second wall.
  // ONLY A UNIQUE VIOLATION IS A REDELIVERY (it_engineer, 3 Nov 2026, failure drill D10). Every error on this insert was
  // read as "already accepted": a 500, a statement timeout or a connection reset on wa_inbound_seen returned 200 here,
  // before the arrival row is written, so the message was stored nowhere, answered never, and agent_runs said 'ok'
  // duplicate. Measured by the drill: 3 of 3 such faults ended with no reply, no row and no finding. Now any other error
  // falls back to the arrival rows (meta.message_sid, written below for every authenticated message): a row there is a
  // redelivery; none (or that read failing too) and the turn goes on, answered once, and it_engineer gets a finding.
  // prevented by: wa_inbound/drill_inbound_faults.test.ts
  if (MessageSid) {
    const { error: seenErr, status: seenStatus } = await admin.from('wa_inbound_seen')
      .insert({ message_sid: MessageSid, wa_from: From });
    let dupErr = seenErr && (seenStatus === 409 || seenErr.code === '23505') ? seenErr : null;
    if (seenErr && !dupErr) {
      const prior = await admin.from('wa_messages').select('id').eq('meta->>message_sid', MessageSid).limit(1);
      if (!prior.error && (prior.data?.length ?? 0) > 0) dupErr = seenErr;
      else await itFinding('wa_inbound:seen_insert_failed', 'wa_inbound_seen refused a WhatsApp MessageSid for a reason that is not a duplicate; the message was answered without the redelivery guard',
        { message_sid: MessageSid, error: seenErr.message, code: seenErr.code ?? null, status: seenStatus ?? null, fallback_read_error: prior.error?.message ?? null });
    }
    if (dupErr) {
      await logRun('ok', { duplicate: 1, message_sid: MessageSid },
        'Twilio redelivered ' + MessageSid + ' which was already accepted; no second reply was sent.');
      return TW(200);
    }
  }

  // ---- WEBHOOK AUTHENTICITY (form path only) -----------------------------
  // Preferred: HMAC signature (cryptographic proof). Fallback: provenance lookup.
  if (!trusted) {
    const sig = await verifyTwilioSignature(req, formParams);
    if (sig.checked && !sig.valid) {
      try {
        await waInsert(receivedAt, { wa_from: From, wa_to: 'whatsapp:' + (await sec('twilio_wa_from')), profile_name: Profile, inbound: Body, reply: '', lang: 'en', escalated: false, sent: false, meta: { signature_checked: true, signature_valid: false, signature_reason: sig.reason, signature_urls_tried: sig.urls || null, message_sid: MessageSid || null, no_autoreply_reason: 'failed X-Twilio-Signature' } });
      } catch (_e) { /* */ }
      await alertThrottled('wa_bad_signature', 'warn', 'A WhatsApp webhook FAILED X-Twilio-Signature validation and was rejected (' + sig.reason + '). Unlike the provenance path this is cryptographic proof of forgery, not an inconclusive lookup. Throttled to one alert per 30 minutes.');
      await logRun('error', { authorised: 0, path: 'form', signature_checked: 1, signature_valid: 0 }, 'wa_inbound REJECTED a webhook that failed HMAC-SHA1 signature validation: ' + sig.reason + '. No LLM call and no outbound message were made. The payload was stored in wa_messages. A genuine Twilio webhook cannot fail this check, so this is a forgery or a misconfigured auth token.');
      return TW(403);
    }
    if (sig.checked && sig.valid) {
      trusted = true; signatureVerified = true; // cryptographic proof - stronger than the provenance lookup, skip it
      await logRun('ok', { authorised: 1, path: 'form', signature_checked: 1, signature_valid: 1 }, 'wa_inbound accepted a webhook on verified X-Twilio-Signature. The provenance lookup was skipped because the signature is cryptographic proof of origin and does not need a confirming REST call.');
    }
  }

  if (!trusted) {
    const prov = await verifyProvenance(MessageSid, From);
    if (!prov.verified) {
      // Preserve the message either way - a real supplier reply must not be lost just because
      // Twilio's API was unreachable - but do NOT run the LLM and do NOT send anything.
      try {
        await waInsert(receivedAt, { wa_from: From, wa_to: 'whatsapp:' + (await sec('twilio_wa_from')), profile_name: Profile, inbound: Body, reply: '', lang: 'en', escalated: false, sent: false, meta: { provenance_verified: false, provenance_reason: prov.reason, twilio_api_reachable: prov.apiReachable, message_sid: MessageSid || null, no_autoreply_reason: 'unverified webhook' } });
      } catch (_e) { /* */ }

      if (prov.apiReachable) {
        await alertThrottled('wa_forged_webhook', 'warn', 'A WhatsApp webhook could not be verified against Twilio and was ignored (' + prov.reason + '). Someone may be probing the wa_inbound endpoint to use our WhatsApp number as a relay. Throttled to one alert per 30 minutes.');
        await logRun('error', { authorised: 0, path: 'form', provenance_verified: 0, twilio_api_reachable: 1 }, 'wa_inbound REJECTED an unverifiable WhatsApp webhook: ' + prov.reason + '. No LLM call and no outbound message were made. The payload was stored in wa_messages for inspection. This is the forged-webhook path, NOT a genuine supplier being ignored.');
      } else {
        await alertThrottled('wa_verify_unavailable', 'warn', 'WhatsApp auto-reply is paused because Twilio could not be reached to verify inbound webhooks (' + prov.reason + '). Genuine messages are still being SAVED but are not getting an automatic reply - check wa_messages and follow up by hand until this clears.');
        await logRun('error', { authorised: 0, path: 'form', provenance_verified: 0, twilio_api_reachable: 0 }, 'wa_inbound could not verify a WhatsApp webhook because Twilio was unreachable (' + prov.reason + '), so it saved the message WITHOUT auto-replying. This may well be a REAL supplier message that got no answer - it needs manual follow-up. Silence here is a verification outage, not an absence of inbound messages.');
      }
      return TW(200);
    }
  }

  // ---- STORED ON ARRIVAL (see arrivalId above): before any model call, before any branch can return ----
  {
    const { data: arr, error: arrErr } = await admin.from('wa_messages').insert(waRow(receivedAt, {
      wa_from: From, wa_to: 'whatsapp:' + (await sec('twilio_wa_from')), profile_name: Profile, inbound: Body, reply: '',
      lang: /[؀-ۿ]/.test(Body) ? 'ar' : 'en', escalated: false, sent: false,
      meta: { stage: 'received', provenance_verified: true, message_sid: MessageSid || null, media: media.length, ...(media.length ? { media_items: mediaItems(media) } : {}) } })).select('id').single();
    if (arrErr) await logRun('error', { arrival_saved: 0 }, 'wa_inbound could not store an authenticated message on arrival: ' + arrErr.message + '. The turn continues and writes its row at the end, as before.');
    else { t.arrivalId = (arr as { id: number }).id; t.messageSidSeen = MessageSid; }
  }
  // ---- "STOP" IS AN OPT-OUT, HONOURED AT ONCE (marketing, 19 Oct 2026, ruling 1184) ----
  // The supplier invitation template tells the recipient to reply STOP. Every lead on this number is set to
  // whatsapp_opt='none' and any invitation still queued to it is cancelled; nothing is replied (UAE PDPL / TDRA:
  // an objection ends the messaging, it does not start a conversation).
  if (isStop(Body)) {
    const { data: opt, error: optErr } = await admin.rpc('fn_wa_supplier_invite_opt_out', { p_from: From });
    // Only a number that is a lead's ends here; anyone else (the founder's command channel, a customer) goes on to
    // the normal turn, so a STOP that is not an opt-out is never swallowed.
    const hit = !optErr && (Number(opt?.leads_opted_out) > 0 || Number(opt?.invitations_cancelled) > 0);
    if (optErr) await logRun('error', { opt_out: 0 }, 'STOP received but the opt-out failed: ' + optErr.message + '; the message continues as a normal turn.');
    if (hit) {
      await logRun('ok', { opt_out: 1 }, 'STOP honoured: ' + JSON.stringify(opt));
      return TW(200);
    }
  }
  // ---- A SUPPLIER LEAD'S OPT-IN IS THE BUTTON OR A YES TO THE CONSENT QUESTION, NEVER JUST A MESSAGE ----
  // (marketing, 27 Oct 2026, rulings 1184 and 1341.) Meta lets a business send a template only to a person who opted
  // in. Founder ledger 1341: an opt-in counts only when the supplier taps "Set up my page" (ButtonPayload
  // 'supplier_invite_yes') or answers yes to a message that asked the consent question; "who is this?" is not one.
  // fn_marketing_files_wa_invite_reply decides with fn_wa_optin_rule (the one shared check) and records an opt-in only
  // then. ButtonPayload is passed as Twilio sent it, so a typed "Set up my page" (no payload) is not a tap. When the
  // lead was invited on any channel and has no company page yet the message is still filed as 'invite.reply'
  // marketing -> sales_engineer. It never ends the turn: the supplier still gets the normal answer.
  if (!isStop(Body)) {
    const { error: repErr } = await admin.rpc('fn_marketing_files_wa_invite_reply', { p_from: From, p_body: Body.slice(0, 4000), p_button_payload: ButtonPayload || null });
    if (repErr) await logRun('error', { invite_reply: 0 }, 'a WhatsApp message from a possible supplier lead was not filed: ' + repErr.message + '; the turn continues.');
  }
  Object.assign(t, { From, Body, Profile, MessageSid, ListId, ButtonPayload, media, internalCaller, signatureVerified });
}

/** A WhatsApp location pin as the turn's text: "Shared a location: <label>, <address> (lat, long)"; '' when the request carries none. */
export function locationText(form: Record<string, string> | null, json: Record<string, string> | null): string {
  const f = form ?? json ?? {};
  const lat = String(f.Latitude || '').trim(), lng = String(f.Longitude || '').trim();
  if (!/^-?\d{1,3}(\.\d+)?$/.test(lat) || !/^-?\d{1,3}(\.\d+)?$/.test(lng)) return '';
  const place = [f.Label, f.Address].map((x) => String(x || '').trim().slice(0, 200)).filter(Boolean).join(', ');
  return 'Shared a location: ' + (place ? place + ' ' : '') + '(' + lat + ', ' + lng + ')';
}
