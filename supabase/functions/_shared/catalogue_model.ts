// WHAT CODE CANNOT READ — the model paths. Seat: sales_engineer. 21 Sep 2026; switched ON 10 Nov 2026 under rulings 1175/1260.
//
// Founder, 21 Sep 2026: "i am not saying strictly i dont wanna use LLM ... in case it was needed then
// dont agree with me", and (instruction 576) "it needs to understand the photos even". Two things code
// cannot do on this path:
//   text   a catalogue or description with no readable structure — free-form prose, or a scan whose
//          text the supplier's browser could not recognise — read for {product_types, services}.
//   photo  what a product photo SHOWS (a printer, a DVR, a shelf of toner). The text IN a photo is
//          already read free, in the supplier's own browser (tesseract.js, SupplierCatalogUpload.tsx).
// Both go through ai_gateway on the sales_engineer route (_shared/llm.ts makeLlmRich — the one client
// every seat uses; no provider of our own) and ONLY when their decision_policy switch is on:
//   supplier_catalogue_model_enabled, supplier_photo_vision_enabled — seeded {"enabled": false} by
//   scripts/sql/a_catalogue_is_read_as_a_catalogue_and_two_trades_join_the_taxonomy.sql while OpenRouter was on hold,
//   and switched ON by scripts/sql/the_supplier_catalogue_and_photo_readers_follow_the_rulings_that_keep_the_models_on.sql:
//   founder rulings 1175 (7 Oct 2026, "keep open router always on") and 1260 (19 Oct 2026, "open router stays on").
// OFF (a switch turned off again, or an absent row) is said, not hidden: the supplier sees an honest line in English and
// Arabic that promises nothing and asks for his own words, and nothing pretends the photo or the prose was understood.
// 10 Nov 2026: the line used to say "waiting on the language model, which is switched off for now" - a promise about a
// switch that the rulings had already settled, shown to suppliers for seven weeks.
//
// WHAT COMES BACK IS CHECKED, NOT TRUSTED. The model is asked for JSON; a service key it names is kept
// only if it is an active taxonomy key (no invented service reaches a supplier), confidence is clamped
// to 0..1, and the result is a PROPOSAL the supplier confirms, like everything else on this tab.

// deno-lint-ignore no-explicit-any
type Admin = any;

export const CATALOGUE_MODEL_FLAG = 'supplier_catalogue_model_enabled';
export const PHOTO_VISION_FLAG = 'supplier_photo_vision_enabled';
export type ModelKind = 'text' | 'photo';
export const FLAG_OF: Record<ModelKind, string> = { text: CATALOGUE_MODEL_FLAG, photo: PHOTO_VISION_FLAG };

export const OFF_MESSAGE: Record<ModelKind, { en: string; ar: string }> = {
  text: {
    en: 'We read everything we could in this file automatically. Please describe anything else your company does in your own words below.',
    ar: 'قرأنا آليًا كل ما أمكن قراءته في هذا الملف. يُرجى وصف أي خدمات أخرى تقدّمها شركتكم بكلماتكم في الأسفل.',
  },
  photo: {
    en: 'We read the text in this photo. Please describe in your own words what it shows.',
    ar: 'قرأنا النص الموجود في هذه الصورة. يُرجى وصف ما تُظهره بكلماتكم.',
  },
};
const FAILED_MESSAGE = {
  en: 'The model could not read this one. Nothing was changed; please describe it in your own words.',
  ar: 'تعذّر على النموذج قراءة هذا الملف. لم يتغيّر شيء؛ يُرجى وصفه بكلماتك.',
};

export type ModelRead = { product_types: string[]; services: string[]; confidence: number; reason: string };
export type ModelOutcome =
  | { state: 'off'; kind: ModelKind; message_en: string; message_ar: string }
  | { state: 'read'; kind: ModelKind; read: ModelRead; source: 'model_text' | 'model_vision' }
  | { state: 'failed'; kind: ModelKind; message_en: string; message_ar: string; detail: string };
/** The gateway, injected: the default is _shared/llm.ts on the sales_engineer route; tests pass a stub. */
export type GatewayCall = (system: string, messages: unknown[]) => Promise<{ content: string | null; error: string | null }>;

/** decision_policy switch, the same shape supplier_voice_input_enabled uses. Absent row = OFF. */
export async function modelSwitchOn(admin: Admin, kind: ModelKind): Promise<boolean> {
  const { data } = await admin.from('decision_policy').select('value').eq('key', FLAG_OF[kind]).maybeSingle();
  const v = data?.value;
  return v === true || (!!v && typeof v === 'object' && (v as { enabled?: unknown }).enabled === true);
}

const SYSTEM = [
  'You are the sales engineer of a UAE construction and supply marketplace, reading a supplier\'s catalogue page or product photo.',
  'Reply with JSON only: {"product_types": string[], "services": string[], "confidence": number, "reason": string}.',
  'product_types: the kinds of products shown or listed, in plain English, at most 12.',
  'services: ONLY keys from the list you are given, for what this supplier provides. A company that imports, wholesales or stocks goods is NOT proposed installation or maintenance work unless the page says it does that work.',
  'confidence: 0 to 1. reason: one sentence naming what on the page supports the answer.',
].join('\n');

/** The model's reply, validated: unknown keys dropped, lists bounded, confidence clamped. */
export function parseModelRead(content: string | null, knownKeys: Set<string>): ModelRead | null {
  if (!content) return null;
  const m = /\{[\s\S]*\}/.exec(content);
  if (!m) return null;
  try {
    const j = JSON.parse(m[0]) as Record<string, unknown>;
    const list = (v: unknown, n: number) => (Array.isArray(v) ? v.map((x) => String(x ?? '').trim()).filter(Boolean).slice(0, n) : []);
    const c = Number(j.confidence);
    return {
      product_types: list(j.product_types, 12).map((s) => s.slice(0, 80)),
      services: [...new Set(list(j.services, 25).filter((k) => knownKeys.has(k)))],
      confidence: Number.isFinite(c) ? Math.min(1, Math.max(0, c)) : 0,
      reason: String(j.reason ?? '').slice(0, 300),
    };
  } catch { return null; }
}

async function defaultGateway(system: string, messages: unknown[]): Promise<{ content: string | null; error: string | null }> {
  // Imported only when a switch is ON: llm.ts builds its client at import time.
  const { makeLlmRich, SONNET_FIRST } = await import('./llm.ts');
  const llm = makeLlmRich(SONNET_FIRST, { fn: 'sales_engineer', agent: 'sales_engineer', max: 600 });
  const r = await llm(system, '', 600, '', { messages });
  return { content: r.content, error: r.error };
}

/** Read text or a photo with the model — or say honestly that the switch is off. Never throws. */
export async function readWithModel(admin: Admin, kind: ModelKind,
  input: { text?: string; image_b64?: string; mime?: string }, knownKeys: Set<string>,
  call: GatewayCall = defaultGateway): Promise<ModelOutcome> {
  if (!(await modelSwitchOn(admin, kind))) return { state: 'off', kind, message_en: OFF_MESSAGE[kind].en, message_ar: OFF_MESSAGE[kind].ar };
  const keys = [...knownKeys].sort().join(', ');
  const content = kind === 'photo'
    ? [{ type: 'text', text: `Service keys: ${keys}` },
       { type: 'image_url', image_url: { url: `data:${input.mime || 'image/jpeg'};base64,${String(input.image_b64 || '')}` } }]
    : `Service keys: ${keys}\n\nCatalogue text:\n${String(input.text || '').slice(0, 12_000)}`;
  try {
    const r = await call(SYSTEM, [{ role: 'system', content: SYSTEM }, { role: 'user', content }]);
    const read = parseModelRead(r.content, knownKeys);
    if (!read) return { state: 'failed', kind, message_en: FAILED_MESSAGE.en, message_ar: FAILED_MESSAGE.ar, detail: String(r.error || 'no JSON in the reply').slice(0, 200) };
    return { state: 'read', kind, read, source: kind === 'photo' ? 'model_vision' : 'model_text' };
  } catch (e) {
    return { state: 'failed', kind, message_en: FAILED_MESSAGE.en, message_ar: FAILED_MESSAGE.ar, detail: String((e as Error)?.message || e).slice(0, 200) };
  }
}
