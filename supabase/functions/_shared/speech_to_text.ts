// speech_to_text.ts - ONE way to turn a voice note into the speaker's words, for every door that takes speech:
// WhatsApp voice notes (wa_inbound/hear.ts) and the portal's recorder fallback (transcribe/index.ts).
// Seat: customer_support (WhatsApp) with it_engineer, 10 Nov 2026. Founder evidence scenario 3: "a customer sending a
// voice note only" must reach an inquiry end to end.
//
// WHAT WAS MEASURED BEFORE THIS FILE (10 Nov 2026, production, SELECT only):
//   - WhatsApp audio was never downloaded or heard: media_in.ts answered "please type", fn_wa_route.transcription_gap says
//     whether Gemini takes a Twilio ogg "is NOT established".
//   - transcribe/index.ts (the portal's fallback recorder) asks ai_gateway task class speech_transcription =
//     google/gemini-3.8-flash on OpenRouter ($0.825 in / $3.75 out per Mtok, model_registry), behind the OpenRouter hold.
//   - No speech key exists in the estate: app_secrets has no key matching hf|hugging|whisper|transcri|groq|deepgram|openai|
//     speech|audio, and the edge secrets are the Supabase ones, MS_*, SERPER_API_KEY, SITE_ERROR_INGEST_SECRET and
//     ML_MODEL_HF_REPO (a public model repo name for embed_ml, not a token).
//
// THE PROVIDERS, cheapest first (config key voice_transcription_provider; anything else, or the key missing, = 'off'):
//   'hf'      Hugging Face Inference (router.huggingface.co/hf-inference), openai/whisper-large-v3-turbo by default
//             (voice_transcription_hf_model). Whisper takes the WhatsApp ogg/opus bytes as they arrive, detects Arabic or
//             English itself, and is billed per compute second against the account's monthly free credit, then
//             pay-as-you-go. NEEDS app_secrets.hf_inference_token (a fine-grained token of the Quotesdone HF account with
//             "Make calls to Inference Providers"): founder-held, not in the estate today.
//   'gateway' ai_gateway task class speech_transcription (gemini-3.8-flash, the funded OpenRouter key that already exists).
//             Audio is ~32 tokens a second, so a minute is ~1,920 input tokens: ~USD 0.0016 in + ~0.0008 out = ~USD 0.0025 a
//             minute (~AED 0.009). Behind the OpenRouter hold, and whether the provider takes 'ogg' as an input_audio
//             format is the live check's to establish.
//   'off'     the honest reply: the voice note was not heard, please type it. The default until a key is configured.
//
// THE CAPS (config, read per call; defaults in STT_DEFAULTS): a per-call ceiling in seconds (measured from the file
// itself where the container says, else from its size), a daily ceiling across the estate, and a per-sender daily
// ceiling. A call has a hard timeout. Nothing here ever retries a timed-out call.
//
// prevented by: _shared/speech_to_text.test.ts and wa_inbound/a_voice_note_is_heard_and_answered_as_typed_text.test.ts
//
// THE LIVE CHECK (NOT RUN: no provider was called to build this; run it once the key exists). From a reserved fixture number
// (+971 50 000 00xx, isDemoPhone, so the receipt and the reply are captured, never sent), POST wa_inbound's internal JSON path
// (ops.wa_replay credential) with Body '' and MediaUrl0 = a data:audio/ogg;base64 URL of a 10-15 s ZZ DEMO voice note, once
// in Gulf Arabic and once in English ("ZZ DEMO I need a car park shade for my villa in Dubai Hills, six by five metres").
// Expected: the voice_claim row reads route 'voice_heard', heard true, ms under 6,000, the transcript names the job; the
// turn's row carries the transcript as inbound and meta.voice; the receipt starts "I heard" / "سمعتُ منكم".
// Expected cost: 'hf' - a 15 s note is about a second of Whisper compute, inside the account's monthly free credit (read the
// Hugging Face billing page after the check); 'gateway' - ~480 audio + ~250 prompt input tokens and ~80 out, ~USD 0.001 a
// note (gemini-3.8-flash, model_registry 10 Nov 2026), at most two calls on the portal door (one retry on an unreadable
// answer), one on WhatsApp.
import { readTranscript } from './provider_signals.ts';

export type SttProvider = 'off' | 'hf' | 'gateway';
export type SttConfig = {
  provider: SttProvider; maxSeconds: number; maxBytes: number; dailyCap: number; perSenderDaily: number; timeoutMs: number; hfModel: string;
};
export type SttResult =
  | { ok: true; text: string; lang: 'ar' | 'en'; provider: SttProvider; seconds: number | null; ms: number }
  | { ok: false; reason: 'off' | 'no_key' | 'too_long' | 'silent' | 'failed' | 'timeout'; provider: SttProvider; detail?: string; seconds?: number | null; ms?: number };

export const STT_KEYS = {
  provider: 'voice_transcription_provider', maxSeconds: 'voice_transcription_max_seconds', dailyCap: 'voice_transcription_daily_cap',
  perSender: 'voice_transcription_per_sender_daily', timeoutMs: 'voice_transcription_timeout_ms', hfModel: 'voice_transcription_hf_model',
  hfToken: 'hf_inference_token',
} as const;
export const STT_DEFAULTS: Omit<SttConfig, 'provider'> = {
  maxSeconds: 120,                // WhatsApp voice notes run long; two minutes is a full description of a job
  maxBytes: 4 * 1024 * 1024,      // the ceiling when the container gives no duration (opus voice ~16-32 kbit/s: 2 min < 0.5 MB)
  dailyCap: 300,                  // every voice note heard in 24 h, across every sender: 300 x 2 min x USD 0.0025 = USD 1.50 on 'gateway'
  perSenderDaily: 20,
  timeoutMs: 25_000,              // WhatsApp's own reply budget is the constraint, not the provider
  hfModel: 'openai/whisper-large-v3-turbo',
};
export const HF_INFERENCE = 'https://router.huggingface.co/hf-inference/models/';

// An empty or blank value is UNSET, never 0: Number('') is 0, so an unset daily cap read 0 and the portal recorder refused
// every voice note with transcription_daily_cap (final audit 12 Nov 2026, customer_journey B1; no voice_transcription_* key
// exists in app_secrets). A non-numeric value is the default as before; a deliberate '0' still means 0.
const num = (v: string | null | undefined, d: number, lo: number, hi: number) => {
  const s = String(v ?? '').trim();
  if (!s) return d;
  const n = Number(s); return Number.isFinite(n) && n >= lo && n <= hi ? n : d;
};
/** The configuration, read through the caller's app_secrets reader. A missing or unknown provider is 'off'. */
export async function sttConfig(sec: (k: string) => Promise<string | null | undefined>): Promise<SttConfig> {
  const [p, ms, dc, ps, to, model] = await Promise.all([STT_KEYS.provider, STT_KEYS.maxSeconds, STT_KEYS.dailyCap, STT_KEYS.perSender,
    STT_KEYS.timeoutMs, STT_KEYS.hfModel].map((k) => sec(k).then((v) => v ?? '', () => '')));
  const provider: SttProvider = p === 'hf' || p === 'gateway' ? p : 'off';
  return {
    provider, maxSeconds: num(ms, STT_DEFAULTS.maxSeconds, 5, 600), maxBytes: STT_DEFAULTS.maxBytes,
    dailyCap: num(dc, STT_DEFAULTS.dailyCap, 0, 100_000), perSenderDaily: num(ps, STT_DEFAULTS.perSenderDaily, 0, 1000),
    timeoutMs: num(to, STT_DEFAULTS.timeoutMs, 3000, 60_000),
    hfModel: /^[\w.-]+\/[\w.-]+$/.test(model || '') ? model! : STT_DEFAULTS.hfModel,
  };
}

/** Seconds of audio, read from the container itself, or null when this container does not say.
 *  OGG (WhatsApp voice notes are ogg/opus): the granule position of the LAST page / 48 kHz (Opus always counts at 48 kHz;
 *  Vorbis at its own rate, read from the identification header). WAV: data bytes / byte rate. */
export function audioSeconds(b: Uint8Array): number | null {
  const ascii = (o: number, n: number) => String.fromCharCode(...b.subarray(o, o + n));
  if (b.length > 32 && ascii(0, 4) === 'OggS') {
    let last = -1;
    for (let i = b.length - 27; i >= 0; i--) { if (b[i] === 0x4f && b[i + 1] === 0x67 && b[i + 2] === 0x67 && b[i + 3] === 0x53) { last = i; break; } }
    if (last < 0) return null;
    const dv = new DataView(b.buffer, b.byteOffset + last + 6, 8);
    const granule = Number(dv.getBigUint64(0, true));
    const head = ascii(28, 8);
    let rate = 48000;
    if (head.startsWith('\x01vorbis')) rate = new DataView(b.buffer, b.byteOffset + 28 + 12, 4).getUint32(0, true) || 48000;
    return granule > 0 && granule < 2 ** 50 ? Math.round((granule / rate) * 10) / 10 : null;
  }
  if (b.length > 44 && ascii(0, 4) === 'RIFF' && ascii(8, 4) === 'WAVE') {
    const dv = new DataView(b.buffer, b.byteOffset, b.length);
    let off = 12; let byteRate = 0;
    while (off + 8 <= b.length) {
      const id = ascii(off, 4); const size = dv.getUint32(off + 4, true);
      if (id === 'fmt ' && off + 16 <= b.length) byteRate = dv.getUint32(off + 16, true);
      if (id === 'data') return byteRate ? Math.round((size / byteRate) * 10) / 10 : null;
      off += 8 + size + (size % 2);
    }
  }
  return null;
}

// WHISPER WRITES WORDS INTO SILENCE. On silence, noise or music it is known to return stock subtitle lines ("Thank you for
// watching", the Arabic "please subscribe" lines, a lone "you"). A transcript that is only such a line is no speech.
const STOCK_LINES = [/^(thank(s| you)( so much)?( for watching)?[.!]*|you[.!]*|bye[.!]*|\.+|music|\[music\]|\(music\))$/i,
  /^(شكرا|شكرًا|شكراً)( لكم)?( (على |علي )?(للمشاهدة|المشاهدة))?[.!]*$/, /^(اشتركوا|اشترك) (في|فى) القناة[.!]*$/, /^ترجمة نانسي قنقر$/];
export function isStockLine(text: string): boolean {
  const t = text.trim().replace(/\s+/g, ' ');
  return !t || STOCK_LINES.some((r) => r.test(t));
}

const PROMPT = 'Transcribe the spoken words in this audio EXACTLY as spoken, word for word. The speaker may talk in Arabic (any Gulf or UAE dialect), English, or a mix of both. Output ONLY the transcribed words. Do NOT translate, summarise, correct, complete, or invent anything. Keep numbers, measurements and units as spoken. If the audio contains no clear human speech (silence, background noise, music, a tone), say so in the speech field and never guess a sentence. Reply with ONE JSON object and nothing else: {"speech": true, "text": "<the transcribed words>"} when there is speech, {"speech": false, "text": ""} when there is none.';

function b64(u8: Uint8Array): string {
  let bin = ''; const c = 0x8000;
  for (let i = 0; i < u8.length; i += c) bin += String.fromCharCode.apply(null, Array.from(u8.subarray(i, i + c)));
  return btoa(bin);
}
const FORMAT: Record<string, string> = { 'audio/ogg': 'ogg', 'audio/mpeg': 'mp3', 'audio/wav': 'wav', 'audio/webm': 'webm', 'audio/mp4': 'm4a', 'audio/flac': 'flac' };

export type SttDeps = {
  fetch?: typeof fetch;
  /** the ai_gateway URL and its credential (provider 'gateway') */
  gatewayUrl?: string; gatewaySecret?: string | null;
  /** app_secrets.hf_inference_token (provider 'hf') */
  hfToken?: string | null;
  /** who is speaking, for the gateway's cost attribution (never sent to Hugging Face) */
  subject?: Record<string, unknown>;
};

/** Hear one voice note. `mime` must be the SNIFFED container (sanitizeAndScan), never the sender's claim. */
export async function transcribeAudio(bytes: Uint8Array, mime: string, cfg: SttConfig, deps: SttDeps): Promise<SttResult> {
  const t0 = Date.now(); const provider = cfg.provider; const f = deps.fetch ?? fetch;
  if (provider === 'off') return { ok: false, reason: 'off', provider };
  const seconds = audioSeconds(bytes);
  if ((seconds != null && seconds > cfg.maxSeconds) || bytes.byteLength > cfg.maxBytes) return { ok: false, reason: 'too_long', provider, seconds };
  // Whisper has no "was there speech?" field, so ONLY its output is held against the stock subtitle lines; the gateway's
  // structured {speech, text} answer decides on its own (decision point transcribe.no_speech, never a word list there).
  const done = (text: string, whisper = false): SttResult => {
    const clean = text.replace(/\s+/g, ' ').trim().slice(0, 4000);
    if (!clean || (whisper && isStockLine(clean))) return { ok: false, reason: 'silent', provider, seconds, ms: Date.now() - t0 };
    return { ok: true, text: clean, lang: /[؀-ۿ]/.test(clean) ? 'ar' : 'en', provider, seconds, ms: Date.now() - t0 };
  };
  const fail = (e: unknown): SttResult => {
    const name = (e as Error)?.name;
    return { ok: false, reason: name === 'TimeoutError' || name === 'AbortError' ? 'timeout' : 'failed', provider, seconds,
             detail: String((e as Error)?.message || e).slice(0, 200), ms: Date.now() - t0 };
  };
  try {
    if (provider === 'hf') {
      if (!deps.hfToken) return { ok: false, reason: 'no_key', provider, seconds };
      const r = await f(HF_INFERENCE + cfg.hfModel, { method: 'POST', body: new Blob([bytes as Uint8Array<ArrayBuffer>]),
        headers: { Authorization: 'Bearer ' + deps.hfToken, 'Content-Type': mime || 'application/octet-stream', Accept: 'application/json' },
        signal: AbortSignal.timeout(cfg.timeoutMs) });
      const j = await r.json().catch(() => null) as { text?: unknown; error?: unknown } | null;
      if (!r.ok || typeof j?.text !== 'string') return { ok: false, reason: 'failed', provider, seconds, detail: 'HTTP ' + r.status + ' ' + String(j?.error ?? '').slice(0, 160), ms: Date.now() - t0 };
      return done(j.text, true);
    }
    if (!deps.gatewaySecret || !deps.gatewayUrl) return { ok: false, reason: 'no_key', provider, seconds };
    const format = FORMAT[mime] ?? 'wav';
    const r = await f(deps.gatewayUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(cfg.timeoutMs),
      body: JSON.stringify({ __secret: deps.gatewaySecret, fn: 'transcribe', subject: deps.subject ?? null, temperature: 0, max: 1024,
        response_format: { type: 'json_object' },
        input: [{ role: 'user', content: [{ type: 'text', text: PROMPT }, { type: 'input_audio', input_audio: { data: b64(bytes), format } }] }] }) });
    const j = await r.json().catch(() => null);
    if (!r.ok || j?.ok === false) return { ok: false, reason: 'failed', provider, seconds, detail: JSON.stringify(j?.detail || j?.error || j).slice(0, 200), ms: Date.now() - t0 };
    const read = readTranscript(j?.content);
    if (!read) return { ok: false, reason: 'failed', provider, seconds, detail: 'not the {speech,text} object', ms: Date.now() - t0 };
    if (!read.speech) return { ok: false, reason: 'silent', provider, seconds, ms: Date.now() - t0 };
    return done(read.text);
  } catch (e) { return fail(e); }
}

/** What the speaker is shown back, so a mishearing is corrected before it becomes a request: their own words in a fixed
 *  frame. A supplier is always answered in English (28 Sep 2026); a customer in the language they spoke. */
export function heardReceipt(text: string, audience: string): string {
  const words = text.replace(/\s+/g, ' ').trim().slice(0, 700);
  if (audience !== 'supplier' && /[؀-ۿ]/.test(words)) return 'سمعتُ منكم: «' + words + '»\nإن لم يكن هذا ما قصدتموه، اكتبوا التصحيح هنا.';
  return 'I heard: "' + words + '"\nIf that is not what you said, just type the correction here.';
}
