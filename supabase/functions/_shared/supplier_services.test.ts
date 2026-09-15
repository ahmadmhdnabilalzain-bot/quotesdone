// The Services checklist's pure rules and the voice path, with transcribe stubbed: no network, no
// model, no database. The voice flag is OFF in production (decision_policy supplier_voice_input_enabled).
import { assertEquals } from 'jsr:@std/assert@1';
import {
  b64Bytes, checkVoice, cleanExtras, langOf, preparedTrades, splitServices, transcribeServiceNote,
  VOICE, VOICE_PER_HOUR, type VoiceDeps,
} from './supplier_services.ts';

Deno.test('splitServices: known keys are ticks, everything else is the supplier\'s own words', () => {
  const known = new Set(['hvac.ducting', 'hvac.vrf_chiller']);
  const r = splitServices(['hvac.ducting', 'Chiller overhaul', '', 'hvac.ducting', 'صيانة مكيفات'], known);
  assertEquals(r.selected, ['hvac.ducting']);
  assertEquals(r.extras, ['Chiller overhaul', 'صيانة مكيفات']);
});

Deno.test('cleanExtras: trimmed, one space, case-insensitive dedupe, clipped, capped', () => {
  assertEquals(cleanExtras(['  Pool   heating ', 'pool heating', 'x', 42, null]), ['Pool heating', '42']);
  assertEquals(cleanExtras(Array.from({ length: 40 }, (_, i) => 'svc ' + i)).length, 25);
  assertEquals(cleanExtras(['a'.repeat(300)])[0].length, 120);
});

Deno.test('langOf: Arabic letters decide, empty is empty', () => {
  assertEquals(langOf('تركيب مكيفات'), 'ar');
  assertEquals(langOf('AC installation'), 'en');
  assertEquals(langOf('  '), '');
});

Deno.test('preparedTrades: confirmed wins; before a confirm, on file then documents, no repeats', () => {
  const cap = { trades: ['hvac'], proposed_trades: ['hvac', 'plumbing'] };
  assertEquals(preparedTrades(cap, true), [{ code: 'hvac', source: 'confirmed' }]);
  assertEquals(preparedTrades(cap, false), [{ code: 'hvac', source: 'on_file' }, { code: 'plumbing', source: 'documents' }]);
  assertEquals(preparedTrades(null, false), []);
});

const wav = 'UklGR' + 'A'.repeat(400);
Deno.test('checkVoice: type, size and length limits', () => {
  assertEquals(checkVoice({ audio_b64: wav, mime: 'audio/webm' }), { ok: false, code: 'voice_bad_type', status: 415 });
  assertEquals(checkVoice({ audio_b64: 'abc', mime: 'audio/wav' }), { ok: false, code: 'voice_empty', status: 400 });
  assertEquals(checkVoice({ audio_b64: 'A'.repeat(4_000_000), mime: 'audio/wav' }), { ok: false, code: 'voice_too_large', status: 413 });
  assertEquals(checkVoice({ audio_b64: wav, mime: 'audio/wav', duration_ms: VOICE.max_seconds * 1000 + 5000 }), { ok: false, code: 'voice_too_long', status: 413 });
  const ok = checkVoice({ audio_b64: wav, mime: 'audio/wav;codecs=1', duration_ms: 3000 });
  assertEquals(ok.ok, true);
  assertEquals(b64Bytes('QUJD'), 3);
  assertEquals(b64Bytes('QQ=='), 1);
});

function deps(over: Partial<VoiceDeps> = {}) {
  const audits: Record<string, unknown>[] = []; let calls = 0;
  const d: VoiceDeps = {
    enabled: async () => true,
    recentCount: async () => audits.filter((a) => a.outcome !== 'flag_off' && a.outcome !== 'rate_limited').length,
    audit: async (r) => { audits.push(r); },
    start: async (r) => { const row = { ...r }; audits.push(row); return async (p) => { Object.assign(row, p); }; },
    transcribe: async () => { calls++; return { ok: true, text: 'تركيب مكيفات سبليت' }; },
    ...over,
  };
  return { d, audits, calls: () => calls };
}

Deno.test('voice: flag off refuses before anything is sent, and is audited', async () => {
  const x = deps({ enabled: async () => false });
  const [s, o] = await transcribeServiceNote(7, { audio_b64: wav, mime: 'audio/wav' }, x.d);
  assertEquals([s, o.code], [503, 'voice_input_off']);
  assertEquals(x.calls(), 0);
  assertEquals(x.audits.map((a) => a.outcome), ['flag_off']);
});

Deno.test('voice: the per-supplier hourly limit refuses without sending', async () => {
  const x = deps({ recentCount: async () => VOICE_PER_HOUR + 1 });
  const [s, o] = await transcribeServiceNote(7, { audio_b64: wav, mime: 'audio/wav' }, x.d);
  assertEquals([s, o.code], [429, 'voice_rate_limited']);
  assertEquals(x.calls(), 0);
  assertEquals(x.audits.map((a) => a.outcome), ['rate_limited']);
});

Deno.test('voice: parallel requests count each other, so the cap is never overshot', async () => {
  const x = deps();
  for (let i = 0; i < VOICE_PER_HOUR - 1; i++) x.audits.push({ outcome: 'transcribed' });
  const results = await Promise.all([1, 2, 3].map(() => transcribeServiceNote(7, { audio_b64: wav, mime: 'audio/wav' }, x.d)));
  const admitted = results.filter(([s]) => s === 200).length;
  assertEquals(admitted <= 1, true);
});

Deno.test('splitServices: a key-shaped word the list does not hold is kept, not dropped', () => {
  assertEquals(splitServices(['hvac.retired_code'], new Set()).extras, ['hvac.retired_code']);
});

Deno.test('voice: a transcribed note returns text + language and the audit holds no text', async () => {
  const x = deps();
  const [s, o] = await transcribeServiceNote(7, { audio_b64: wav, mime: 'audio/wav', duration_ms: 2000 }, x.d);
  assertEquals([s, o.ok, o.lang], [200, true, 'ar']);
  assertEquals(o.text, 'تركيب مكيفات سبليت');
  assertEquals(x.audits.length, 1);
  assertEquals(x.audits[0].outcome, 'transcribed');
  assertEquals('text' in x.audits[0], false);
});

Deno.test('voice: a provider failure is a 502, audited as failed', async () => {
  const x = deps({ transcribe: async () => ({ ok: false, error: 'hold' }) });
  const [s, o] = await transcribeServiceNote(7, { audio_b64: wav, mime: 'audio/wav' }, x.d);
  assertEquals([s, o.code], [502, 'voice_failed']);
  assertEquals(x.audits[0].outcome, 'failed');
});
