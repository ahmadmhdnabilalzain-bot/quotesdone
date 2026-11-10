import { siteCors } from '../_shared/site_origins.ts';
// transcribe — server-side speech-to-text via OpenRouter audio models (funded key that powers the agents).
// Replaces the browser Web Speech API (broke on Safari/iOS, poor with UAE Arabic/English mixed speech).
// Client records WAV. Prompt is NEUTRAL + anti-hallucination (no domain priming) so silence/noise returns empty. Auth-gated.
// Routed through ai_gateway (v3 multimodal passthrough carries the input_audio block verbatim).
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { sanitizeOrMessage, SAFE_AUDIO } from '../_shared/attachment.ts';
// MALWARE WATCH, 9 Sep 2026 — see _shared/malware.ts. A signed-in customer's voice note is still a
// customer file entering the estate, and it is billed to a model, so it gets the same verdict.
import { sanitizeAndScan } from '../_shared/malware.ts';
import { observe } from '../_shared/observe.ts';
import { sttConfig, transcribeAudio, STT_KEYS } from '../_shared/speech_to_text.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string): Promise<string | null> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || null; }
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';

Deno.serve(siteCors(observe('transcribe', async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user) return J({ error: 'Not signed in' }, 401);
    const body = await req.json().catch(() => ({}));
    let b64 = String(body.audio_b64 || body.audio || '');
    b64 = b64.replace(/^data:[^;,]*;base64,/, '').replace(/^data:[^,]*,/, '');
    const mime = String(body.mime || 'audio/wav').toLowerCase();
    // AUDIT 9.1 (3 Aug 2026): the format posted to the model came from body.mime — the caller's
    // own claim — and the bytes were never looked at, so anything at all could be sent as
    // "audio/wav" and billed for. sniff() now knows the audio magics, so the real container
    // decides and a PDF or an executable dressed as a voice note is refused.
    const __san = await sanitizeAndScan({ input: b64, declaredMime: mime, filename: 'voice-note',
                                          allow: SAFE_AUDIO, maxBytes: 17 * 1024 * 1024,
                                          stripMetadata: false,
                                          scan: { source: 'transcribe.voice_note', subject: user.id, filename: 'voice-note' } });
    if (!__san.ok) return J(__san.body, __san.status);
    if (!b64 || b64.length < 100) return J({ error: 'empty_audio' }, 400);
    if (b64.length > 22_000_000) return J({ error: 'Audio too long. Please keep it under about 2 minutes.' }, 413);
    // ONE HEARING FOR EVERY DOOR (it_engineer, 10 Nov 2026): the provider, the per-call ceiling, the daily ceiling and the
    // timeout are _shared/speech_to_text.ts's, the same WhatsApp voice notes use (wa_inbound/hear.ts). This door keeps the
    // route it always had (ai_gateway) while the configured provider is 'off', so the portal and the supplier service note
    // are not narrowed by a WhatsApp setting. R7 of the channels audit: the gateway fetch had no timeout at all; a stalled
    // provider held the recorder's spinner until the edge wall-clock killed the function.
    // prevented by: _shared/speech_to_text.test.ts
    const cfg0 = await sttConfig(sec);
    const cfg = { ...cfg0, provider: cfg0.provider === 'off' ? 'gateway' as const : cfg0.provider, maxBytes: 17 * 1024 * 1024 };
    const since = new Date(Date.now() - 86_400_000).toISOString();
    const { count: today } = await admin.from('agent_runs').select('id', { count: 'exact', head: true }).eq('agent', 'transcribe').gte('started_at', since);
    if (today != null && today >= cfg.dailyCap) return J({ ok: false, error: 'transcription_daily_cap', text: '' }, 429);
    let text: string | null = null; let lastErr = ''; let unreadable = false;
    // RULING 1177 (12 Oct 2026): an unreadable answer is asked once more before the user is asked to record again;
    // a timeout is never asked again (the provider is already slow; the user records again).
    for (let attempt = 1; attempt <= 2 && text === null; attempt++) {
      unreadable = false;
      const heard = await transcribeAudio(__san.result.bytes, __san.result.mime, cfg, {
        gatewayUrl: GW, gatewaySecret: cfg.provider === 'gateway' ? await sec('cred_fn_ai') : null,
        hfToken: cfg.provider === 'hf' ? await sec(STT_KEYS.hfToken) : null, subject: { user_id: user.id } });
      if (heard.ok) text = heard.text;
      else if (heard.reason === 'silent') text = '';
      else if (heard.reason === 'too_long') return J({ error: 'Audio too long. Please keep it under about 2 minutes.' }, 413);
      else if (heard.reason === 'no_key') return J({ error: 'transcription_not_configured' }, 500);
      else if (heard.reason === 'timeout') { lastErr = 'timeout'; break; }
      else { lastErr = heard.detail || heard.reason; unreadable = /speech,text/.test(lastErr); }
    }
    // Not the structured answer (a truncated or malformed reply): no guess, the user is simply asked to record again.
    if (unreadable) return J({ ok: false, error: 'transcription_unreadable', text: '', message: String(body.lang || '').toLowerCase().startsWith('ar') ? 'تعذّرت علينا قراءة هذا التسجيل بوضوح. يُرجى تسجيله مرة أخرى في مكان أهدأ.' : 'We could not read that recording clearly. Please record it again, somewhere quieter.' }, 200);
    if (text === null) return J({ error: 'transcription_failed', detail: lastErr }, 502);
    return J({ ok: true, text });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
})));
