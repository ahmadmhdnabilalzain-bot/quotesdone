// transcribe — server-side speech-to-text via OpenRouter audio models (funded key that powers the agents).
// Replaces the browser Web Speech API (broke on Safari/iOS, poor with UAE Arabic/English mixed speech).
// Client records WAV. Prompt is NEUTRAL + anti-hallucination (no domain priming) so silence/noise returns empty. Auth-gated.
import { createClient } from 'jsr:@supabase/supabase-js@2';
const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', ...CORS } });
async function sec(k: string): Promise<string | null> { const { data } = await admin.from('app_secrets').select('value').eq('key', k).maybeSingle(); return (data?.value as string) || null; }
const PROMPT = 'Transcribe the spoken words in this audio EXACTLY as spoken, word for word. The speaker may talk in Arabic, English, or a mix of both (United Arab Emirates). Output ONLY the transcribed words and nothing else. Do NOT translate, summarise, correct, complete, punctuate creatively, or invent anything. Keep numbers, measurements and units as spoken. If the audio contains no clear human speech - for example silence, background noise, music, or a tone - output an empty string only, and never guess or fabricate any sentence.';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const jwt = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
    const { data: { user } } = await admin.auth.getUser(jwt);
    if (!user) return J({ error: 'Not signed in' }, 401);
    const body = await req.json().catch(() => ({}));
    let b64 = String(body.audio_b64 || body.audio || '');
    b64 = b64.replace(/^data:[^;,]*;base64,/, '').replace(/^data:[^,]*,/, '');
    const mime = String(body.mime || 'audio/wav').toLowerCase();
    const format = mime.includes('mp3') || mime.includes('mpeg') ? 'mp3' : 'wav';
    if (!b64 || b64.length < 100) return J({ error: 'empty_audio' }, 400);
    if (b64.length > 22_000_000) return J({ error: 'Audio too long. Please keep it under about 2 minutes.' }, 413);
    const key = await sec('openrouter_api_key'); if (!key) return J({ error: 'transcription_not_configured' }, 500);

    const payload = { messages: [{ role: 'user', content: [ { type: 'text', text: PROMPT }, { type: 'input_audio', input_audio: { data: b64, format } } ] }], temperature: 0, max_tokens: 1024 };
    let text: string | null = null; let lastErr = '';
    for (const model of ['google/gemini-2.5-flash', 'google/gemini-2.5-flash-lite', 'google/gemini-2.5-pro']) {
      try {
        const r = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', headers: { 'Authorization': 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify({ model, ...payload }) });
        const j = await r.json();
        if (!r.ok) { lastErr = JSON.stringify(j?.error || j).slice(0, 220); continue; }
        const c = j?.choices?.[0]?.message?.content;
        let t = (typeof c === 'string' ? c : Array.isArray(c) ? c.map((p: any) => p?.text || '').join('') : '').trim();
        // strip common non-speech placeholders a model might emit
        if (/^(\(|\[)?\s*(no (clear )?(human )?speech|silence|inaudible|no audio|blank|empty)\s*(\)|\])?\.?$/i.test(t)) t = '';
        text = t; break;
      } catch (e) { lastErr = String((e as Error)?.message || e); }
    }
    if (text === null) return J({ error: 'transcription_failed', detail: lastErr }, 502);
    return J({ ok: true, text });
  } catch (e) { return J({ error: String((e as Error)?.message || e) }, 500); }
});
