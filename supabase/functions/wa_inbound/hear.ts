// hear.ts - A VOICE NOTE IS HEARD, then answered as the words it carried (customer_support, it_engineer 10 Nov 2026).
// Founder evidence scenario 3: "a customer sending a voice note only" reaches an inquiry end to end.
//
// Runs right after the arrival is accepted and BEFORE anything reads Body (say, the spec-offer answer, identify's FAQ
// retrieval, the classification, the interview): when the message is a voice note and nothing else, it is downloaded
// (host pinned, media.ts), sniffed (it must really be audio), measured, capped and transcribed
// (_shared/speech_to_text.ts). On success the transcript BECOMES this turn's Body and the media list is emptied, so the
// rest of the turn is exactly a typed message: the same intake, the same interview turn, the same records. Before that
// the speaker is sent their own words back in a fixed frame ("I heard: ..."), so a mishearing is corrected by typing
// before it becomes a request. On any failure the turn is left as it arrived and media_in.ts gives the honest "please
// type it" reply, told why (t.voiceNotHeard).
//
// Not heard on purpose: the founder's number (a misheard command is not a risk his channel takes), a message that also
// carries a caption or a file, an internal JSON replay (it has no Twilio media to fetch, unless inline).
// prevented by: wa_inbound/a_voice_note_is_heard_and_answered_as_typed_text.test.ts
import { heardReceipt, sttConfig, transcribeAudio, STT_KEYS, type SttResult } from '../_shared/speech_to_text.ts';
import { SAFE_AUDIO } from '../_shared/attachment.ts';
import { sanitizeAndScan } from '../_shared/malware.ts';
import { admin, sec, GATEWAY } from './shared.ts';
import { fetchTwilioMedia } from './media.ts';
import { sendWa, toContact } from './replies.ts';
import { waRow } from './wa_row.ts';
import type { WaTurn } from './turn.ts';

/** Why a voice note was not heard, for media_in.ts's honest reply. */
export type NotHeard = Extract<SttResult, { ok: false }>['reason'] | 'cap' | 'not_downloaded' | 'refused';

export async function hearVoiceNote(t: WaTurn): Promise<void> {
  const { From, Body, MessageSid, media, internalCaller, receivedAt, Profile } = t;
  if (!media.length || Body.trim() || !media.every((m) => /^audio\//i.test(m.mime))) return;
  const cfg = await sttConfig(sec);
  if (cfg.provider === 'off') { t.voiceNotHeard = 'off'; return; }

  // who is speaking: the founder's voice note is never turned into a command
  let audience = 'unknown';
  try { const { data } = await admin.rpc('fn_identify_contact', { p_phone: From }); if (data?.audience) audience = String(data.audience); } catch (_e) { /* unknown */ }
  if (audience === 'founder') return;

  // THE DAILY CAPS, claimed before the call (the media_read_claim pattern, media_in.ts): every concurrent voice note sees
  // the others' claims, so no more than the cap reach a provider. A failed claim hears nothing.
  const since = new Date(Date.now() - 86_400_000).toISOString();
  const { data: claim } = await admin.from('wa_messages').insert(waRow(receivedAt, { wa_from: From, wa_to: '', profile_name: Profile,
    inbound: '', reply: '', lang: 'en', escalated: false, sent: false,
    meta: { route: 'voice_claim', voice_claim: true, provider: cfg.provider, message_sid: MessageSid || null } })).select('id').maybeSingle();
  if (!claim?.id) { t.voiceNotHeard = 'cap'; return; }
  const [{ count: mine }, { count: all }] = await Promise.all([
    admin.from('wa_messages').select('id', { count: 'exact', head: true }).eq('wa_from', From).gte('created_at', since).eq('meta->>voice_claim', 'true').lte('id', claim.id),
    admin.from('wa_messages').select('id', { count: 'exact', head: true }).gte('created_at', since).eq('meta->>voice_claim', 'true').lte('id', claim.id),
  ]);
  const record = async (patch: Record<string, unknown>) => {
    try { await admin.from('wa_messages').update(patch).eq('id', claim.id); } catch (_e) { /* the turn goes on either way */ }
  };
  if (mine == null || all == null || mine > cfg.perSenderDaily || all > cfg.dailyCap) {
    t.voiceNotHeard = 'cap';
    await record({ meta: { route: 'voice_claim', voice_claim: true, provider: cfg.provider, heard: false, why: 'cap', mine, all } });
    return;
  }

  const m = media[0];
  const got = await fetchTwilioMedia(m.url, internalCaller);
  if (!got.bytes) { t.voiceNotHeard = 'not_downloaded'; await record({ meta: { route: 'voice_claim', voice_claim: true, heard: false, why: 'not_downloaded' } }); return; }
  const sc = await sanitizeAndScan({ input: got.bytes, declaredMime: got.mime || m.mime, filename: 'voice-note', allow: SAFE_AUDIO,
    maxBytes: 17 * 1024 * 1024, stripMetadata: false, scan: { source: 'wa_inbound.voice_note', subject: From, filename: 'voice-note', bucket: null } });
  if (!sc.ok) { t.voiceNotHeard = 'refused'; await record({ meta: { route: 'voice_claim', voice_claim: true, heard: false, why: 'refused:' + sc.body.error } }); return; }

  const heard = await transcribeAudio(sc.result.bytes, sc.result.mime, cfg, {
    hfToken: cfg.provider === 'hf' ? await sec(STT_KEYS.hfToken) : null,
    gatewayUrl: GATEWAY, gatewaySecret: cfg.provider === 'gateway' ? await sec('cred_fn_ai') : null,
    subject: { phone: From },
  });
  if (!heard.ok) {
    t.voiceNotHeard = heard.reason;
    await record({ meta: { route: 'voice_claim', voice_claim: true, provider: cfg.provider, heard: false, why: heard.reason, seconds: heard.seconds ?? null, ms: heard.ms ?? null, detail: heard.detail ?? null } });
    return;
  }

  // THEIR OWN WORDS, SHOWN BACK FIRST. A receipt in a fixed frame around what they said, not a reply: the answer that
  // follows is the model's, as for any typed message (rulings 1195-1197).
  const receipt = toContact(heardReceipt(heard.text, audience));
  const enabled = (await sec('wa_autoreply_enabled')) === 'true';
  let sent = false; let sendErr: string | null = null;
  if (enabled && receipt) { const r = await sendWa(From, receipt); sent = r.ok; sendErr = r.err ?? null; }
  await record({ reply: receipt, sent, lang: heard.lang, ...(sent ? { replied_at: new Date().toISOString() } : {}),
    meta: { route: 'voice_heard', voice_claim: true, provider: cfg.provider, heard: true, seconds: heard.seconds, ms: heard.ms,
            transcript: heard.text.slice(0, 2000), send_error: sendErr, message_sid: MessageSid || null } });

  t.voice = { heard: true, provider: cfg.provider, seconds: heard.seconds, ms: heard.ms, transcript_chars: heard.text.length };
  t.Body = heard.text;
  t.media = [];
}
