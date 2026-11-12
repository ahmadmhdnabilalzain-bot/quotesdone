// _shared/speech_to_text.ts: the one hearing for WhatsApp voice notes and the portal recorder (it_engineer, 10 Nov 2026).
// No provider is called: every fetch here is a stub that records what it was sent. Red before the module existed.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { oggOpus } from './ogg_fixture.ts';
import { audioSeconds, heardReceipt, HF_INFERENCE, isStockLine, sttConfig, STT_DEFAULTS, transcribeAudio, type SttConfig } from './speech_to_text.ts';

const cfg = (over: Partial<SttConfig> = {}): SttConfig => ({ provider: 'hf', ...STT_DEFAULTS, ...over });
type Sent = { url: string; init: RequestInit };
const stubFetch = (answer: (s: Sent) => Response | Promise<Response>, sent: Sent[] = []) =>
  (async (url: string | URL | Request, init?: RequestInit) => { const s = { url: String(url), init: init ?? {} }; sent.push(s); return await answer(s); }) as typeof fetch;

Deno.test('a voice note\'s length is read from the file itself (ogg/opus granule, wav header)', () => {
  assertEquals(audioSeconds(oggOpus(37.5)), 37.5);
  const wav = new Uint8Array(44 + 32000 * 3); const dv = new DataView(wav.buffer);
  wav.set(new TextEncoder().encode('RIFF'), 0); wav.set(new TextEncoder().encode('WAVEfmt '), 8); dv.setUint32(16, 16, true);
  dv.setUint32(28, 32000, true); wav.set(new TextEncoder().encode('data'), 36); dv.setUint32(40, 32000 * 3, true);
  assertEquals(audioSeconds(wav), 3);
  assertEquals(audioSeconds(new Uint8Array(100)), null, 'an unknown container says nothing');
});

Deno.test('no provider configured is off: nothing is called, and the caller gives the honest reply', async () => {
  const c = await sttConfig(async () => '');
  assertEquals(c.provider, 'off');
  const sent: Sent[] = [];
  const r = await transcribeAudio(oggOpus(5), 'audio/ogg', c, { fetch: stubFetch(() => new Response('{}'), sent) });
  assertEquals(r, { ok: false, reason: 'off', provider: 'off' });
  assertEquals(sent.length, 0);
});

Deno.test('the caps are config, with bounded defaults', async () => {
  const c = await sttConfig(async (k) => ({ voice_transcription_provider: 'gateway', voice_transcription_max_seconds: '60', voice_transcription_daily_cap: 'lots',
    voice_transcription_timeout_ms: '999999' } as Record<string, string>)[k] ?? null);
  assertEquals([c.provider, c.maxSeconds, c.dailyCap, c.timeoutMs], ['gateway', 60, STT_DEFAULTS.dailyCap, STT_DEFAULTS.timeoutMs]);
});

// final audit 12 Nov 2026, customer_journey B1: no voice_transcription_* key exists in app_secrets, the reader hands '' for a
// missing key, and Number('') is 0, inside the cap's range: the daily cap and the per-sender cap read 0, and the portal recorder
// (transcribe/index.ts, today >= dailyCap) refused every note with transcription_daily_cap. An unset or blank key is the default.
Deno.test('an unset cap is the default cap, never zero (a missing key must not refuse every voice note)', async () => {
  for (const missing of [() => Promise.resolve(''), () => Promise.resolve(null), () => Promise.resolve('   ')]) {
    const c = await sttConfig(missing as (k: string) => Promise<string | null>);
    assertEquals([c.dailyCap, c.perSenderDaily, c.maxSeconds, c.timeoutMs],
      [STT_DEFAULTS.dailyCap, STT_DEFAULTS.perSenderDaily, STT_DEFAULTS.maxSeconds, STT_DEFAULTS.timeoutMs]);
  }
  // a cap the founder sets to 0 on purpose still means "hear none"
  const zero = await sttConfig((k) => Promise.resolve(k === 'voice_transcription_daily_cap' ? '0' : null));
  assertEquals(zero.dailyCap, 0);
});

Deno.test('Hugging Face Whisper: the bytes go as they arrived, with the token, to the configured model; Arabic is detected', async () => {
  const sent: Sent[] = [];
  const r = await transcribeAudio(oggOpus(8), 'audio/ogg', cfg(), { hfToken: 'hf_stub', fetch: stubFetch(() => Response.json({ text: ' أبغى مظلة سيارات للفيلا ' }), sent) });
  assert(r.ok, JSON.stringify(r));
  assertEquals([r.ok && r.text, r.ok && r.lang, r.ok && r.seconds], ['أبغى مظلة سيارات للفيلا', 'ar', 8]);
  assertEquals(sent[0].url, HF_INFERENCE + 'openai/whisper-large-v3-turbo');
  assertEquals((sent[0].init.headers as Record<string, string>).Authorization, 'Bearer hf_stub');
  assertEquals((sent[0].init.headers as Record<string, string>)['Content-Type'], 'audio/ogg');
});

Deno.test('no token is no_key, a long note is refused before any call, and a stock subtitle line is silence', async () => {
  const sent: Sent[] = [];
  const f = stubFetch(() => Response.json({ text: 'Thank you for watching.' }), sent);
  assertEquals((await transcribeAudio(oggOpus(5), 'audio/ogg', cfg(), { fetch: f })).ok === false, true);
  assertEquals((await transcribeAudio(oggOpus(5), 'audio/ogg', cfg(), { fetch: f }) as { reason: string }).reason, 'no_key');
  assertEquals((await transcribeAudio(oggOpus(121), 'audio/ogg', cfg(), { hfToken: 'x', fetch: f }) as { reason: string }).reason, 'too_long');
  assertEquals(sent.length, 0, 'nothing is sent for a refused note');
  assertEquals((await transcribeAudio(oggOpus(5), 'audio/ogg', cfg(), { hfToken: 'x', fetch: f }) as { reason: string }).reason, 'silent');
  assert(isStockLine('شكرا للمشاهدة') && !isStockLine('thanks, I need a quote for tiling'));
});

Deno.test('a provider that does not answer in time is a timeout, never a hang', async () => {
  const f = stubFetch((s) => new Promise((_res, rej) => s.init.signal?.addEventListener('abort', () => rej(s.init.signal?.reason))));
  const t0 = Date.now();
  const r = await transcribeAudio(oggOpus(5), 'audio/ogg', cfg({ timeoutMs: 3000 }), { hfToken: 'x', fetch: f });
  assertEquals((r as { reason: string }).reason, 'timeout');
  assert(Date.now() - t0 < 5000);
});

Deno.test('the gateway route sends the sniffed format and reads the structured {speech,text} answer', async () => {
  const sent: Sent[] = [];
  const f = stubFetch(() => Response.json({ ok: true, content: '{"speech": true, "text": "I need 40 m2 of porcelain tiles"}' }), sent);
  const r = await transcribeAudio(oggOpus(6), 'audio/ogg', cfg({ provider: 'gateway' }), { gatewayUrl: 'https://db.invalid/functions/v1/ai_gateway', gatewaySecret: 's', fetch: f });
  assert(r.ok && r.text === 'I need 40 m2 of porcelain tiles' && r.lang === 'en', JSON.stringify(r));
  assertEquals(JSON.parse(String(sent[0].init.body)).input[0].content[1].input_audio.format, 'ogg');
  const silent = await transcribeAudio(oggOpus(6), 'audio/ogg', cfg({ provider: 'gateway' }), { gatewayUrl: 'u', gatewaySecret: 's',
    fetch: stubFetch(() => Response.json({ ok: true, content: '{"speech": false, "text": ""}' })) });
  assertEquals((silent as { reason: string }).reason, 'silent');
});

Deno.test('what they said is shown back in their language; a supplier is always answered in English', () => {
  assert(heardReceipt('أبغى مظلة', 'customer').startsWith('سمعتُ منكم: «أبغى مظلة»'));
  assert(heardReceipt('أبغى مظلة', 'supplier').startsWith('I heard: "أبغى مظلة"'));
  assert(heardReceipt('I need a quote', 'visitor').includes('type the correction'));
});
