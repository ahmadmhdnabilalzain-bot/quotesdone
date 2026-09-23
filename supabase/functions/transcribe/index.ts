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
import { readTranscript } from '../_shared/provider_signals.ts';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string): Promise<string | null> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || null; }
const GW = Deno.env.get('SUPABASE_URL')! + '/functions/v1/ai_gateway';
const PROMPT = 'Transcribe the spoken words in this audio EXACTLY as spoken, word for word. The speaker may talk in Arabic, English, or a mix of both (United Arab Emirates). Output ONLY the transcribed words and nothing else. Do NOT translate, summarise, correct, complete, punctuate creatively, or invent anything. Keep numbers, measurements and units as spoken. If the audio contains no clear human speech - for example silence, background noise, music, or a tone - say so in the speech field, and never guess or fabricate any sentence. Reply with ONE JSON object and nothing else: {"speech": true, "text": "<the transcribed words>"} when there is speech, {"speech": false, "text": ""} when there is none.';

Deno.serve(observe('transcribe', async (req) => {
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
    const format = __san.result.mime === 'audio/mpeg' ? 'mp3' : 'wav';   // sniffed, not claimed
    if (!b64 || b64.length < 100) return J({ error: 'empty_audio' }, 400);
    if (b64.length > 22_000_000) return J({ error: 'Audio too long. Please keep it under about 2 minutes.' }, 413);
    const secret = await sec('cred_fn_ai'); if (!secret) return J({ error: 'transcription_not_configured' }, 500);

    const content = [ { type: 'text', text: PROMPT }, { type: 'input_audio', input_audio: { data: b64, format } } ];
    let text: string | null = null; let lastErr = '';
    try {
      const r = await fetch(GW, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ __secret: secret, fn: 'transcribe', temperature: 0, max: 1024, input: [{ role: 'user', content }] }) });
      const j = await r.json();
      if (!r.ok || j?.ok === false) { lastErr = JSON.stringify(j?.detail || j?.error || j).slice(0, 220); }
      else {
        // 23 SEP 2026 (founder_instruction 886-903): "was there speech?" is the model's structured answer
        // ({speech, text}, _shared/provider_signals.ts), never a placeholder regex over its words. A reply that is
        // not that object is unreadable: the caller is asked to try again rather than handed a guess.
        const read = readTranscript(j?.content);
        if (read) text = read.text; else lastErr = 'transcription_unreadable: the model did not return {speech, text}';
      }
    } catch (e) { lastErr = String((e as Error)?.message || e); }
    if (text === null) return J({ error: 'transcription_failed', detail: lastErr }, 502);
    return J({ ok: true, text });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
}));
