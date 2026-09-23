// reasoned_governance — decision-point batch B7: the Arabic of a person's own words is written by reasoning.
// Seat: ceo (registry owner of trade_glossary_ar); the documents themselves are the sales_engineer's, so the
// reasoning runs in that seat. 23 Sep 2026, founder_instruction 886-903 (ledger 890: no word matching).
//
// BEFORE. trade_glossary_ar.ts turned a supplier's or customer's English into Arabic by substituting known
// phrases, longest first, and re-ordering noun groups; what it did not know was printed as English on a
// secondary line. The founder: "what is arabic is not fully in arabic, many english words here and there".
// NOW. Every free-text line an Arabic document or message needs is translated natively by think() (seat
// sales_engineer, surface sales_engineer.document_arabic) and cached in public.arabic_translation, so a line is
// reasoned once. A document is built only when EVERY line it needs has its Arabic; otherwise it is HELD —
// never sent half-translated. Under the founder's model hold the lines are filed in the seat's queue; the
// replay translates them and fn_reason_apply_sales_engineer__document_arabic stores them, so the next request
// for the document is served from the cache without a model call.
//
// The SQL half of this batch (challenge, what-if, knowledge jurisdiction) files its questions from SQL with
// fn_reason_hold: scripts/sql/governance_reads_keys_and_reasons_rather_than_spotting_words.sql.
import { think, parseJson, type ThinkDeps, type ThinkResult } from './think.ts';

export const ARABIC_SURFACE = 'sales_engineer.document_arabic';
/** Source characters per reasoned batch. The gateway caps a reply at ~900 tokens and Arabic runs ~1 token per
 * 2-3 characters, so 600 source characters (≈ 700 Arabic characters, ≈ 300 tokens, plus the JSON) leaves room. */
export const ARABIC_BATCH_CHARS = 600;

// A script test, not a meaning test: does the string already carry Arabic letters / any Latin letters.
const arabicScript = (s: string) => /[؀-ۿ]/.test(s);
const latinScript = (s: string) => /[A-Za-z]/.test(s);
/** A line that needs translating: it has Latin letters (a line wholly in Arabic, or only digits, needs none). */
export const needsArabic = (s: string) => !!s && latinScript(s);

/** The question one batch asks. The answer must be ONE JSON object keyed by the line numbers. */
export function arabicQuestion(texts: string[]): string {
  return 'Translate each numbered line into native, professional Gulf Arabic as a UAE sales engineer would write it on a '
    + 'quotation — the meaning, not word by word. Keep brand names, model and grade codes, standards and numbers exactly as written. '
    + 'Put ONLY one JSON object in "answer", keyed by the line number, e.g. {"1":"...","2":"..."}.\n'
    + texts.map((t, i) => `${i + 1}. ${t}`).join('\n');
}

/** The reasoned answer → {source: arabic}, keeping only lines whose value is Arabic script. Pure (format parsing). */
export function arabicPairs(texts: string[], answer: string): Record<string, string> {
  const o = parseJson<Record<string, unknown>>(answer) ?? {};
  const out: Record<string, string> = {};
  texts.forEach((t, i) => { const v = o[String(i + 1)]; if (typeof v === 'string' && arabicScript(v)) out[t] = v.trim(); });
  return out;
}

async function sha(s: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('').slice(0, 32);
}

/** Batches of whole lines under ARABIC_BATCH_CHARS (a longer single line is its own batch). */
export function batches(texts: string[], max = ARABIC_BATCH_CHARS): string[][] {
  const out: string[][] = []; let cur: string[] = []; let n = 0;
  for (const t of texts) {
    if (cur.length && n + t.length > max) { out.push(cur); cur = []; n = 0; }
    cur.push(t); n += t.length;
  }
  if (cur.length) out.push(cur);
  return out;
}

export type ArabicOf = { map: Record<string, string>; complete: boolean; missing: string[]; results: ThinkResult[] };

/** Native Arabic for every text: cache first, then think() per batch. complete=false means at least one line has
 * no Arabic yet (held under the hold, or the model failed) — the caller must not print it half-translated. */
export async function arabicOf(deps: ThinkDeps, o: { texts: string[]; subject?: Record<string, unknown> }): Promise<ArabicOf> {
  const texts = [...new Set(o.texts.map((t) => String(t ?? '').trim()).filter(needsArabic))];
  const map: Record<string, string> = {};
  const results: ThinkResult[] = [];
  if (!texts.length) return { map, complete: true, missing: [], results };
  const { data } = await deps.rpc('fn_arabic_translations', { p_sources: texts });
  if (data && typeof data === 'object') for (const [k, v] of Object.entries(data as Record<string, unknown>)) if (typeof v === 'string') map[k] = v;
  for (const chunk of batches(texts.filter((t) => !map[t]))) {
    const result = await think(deps, {
      seat: 'sales_engineer', surface: ARABIC_SURFACE, question: arabicQuestion(chunk),
      context: { audience: 'customer', language: 'ar' }, research: false,
      subject: { ...(o.subject ?? {}), sources: chunk }, dedupeKey: 'arabic:' + await sha(chunk.join('\u0001')),
    });
    results.push(result);
    if (result.status !== 'answered') continue;
    const pairs = arabicPairs(chunk, result.answer);
    if (Object.keys(pairs).length) await deps.rpc('fn_arabic_translation_store', { p_pairs: pairs, p_held_id: null });
    Object.assign(map, pairs);
  }
  const missing = texts.filter((t) => !map[t]);
  return { map, complete: missing.length === 0, missing, results };
}

/** For a message (not a document): the Arabic of whatever lines could be reasoned now, or undefined on an English
 * message. A line still held is quoted as written by the message itself, and its question waits in the queue. */
export async function arabicTextsFor(deps: ThinkDeps, lang: string, texts: string[]): Promise<Record<string, string> | undefined> {
  if (lang !== 'ar') return undefined;
  // A failure to reason never stops the message: the lines are quoted as written instead.
  try { return (await arabicOf(deps, { texts })).map; } catch (_e) { return {}; }
}

/** Build an Arabic document: the builder reports the lines it could not print (`untranslated`); they are
 * translated by reasoning and the document is rebuilt with them. Any line still without Arabic → held (null). */
export async function nativeArabic<T extends { untranslated: string[] }>(deps: ThinkDeps, build: (arTexts: Record<string, string>) => T,
  o: { subject?: Record<string, unknown> } = {}): Promise<{ doc: T | null; held: boolean; missing: string[] }> {
  const first = build({});
  if (!first.untranslated.length) return { doc: first, held: false, missing: [] };
  const r = await arabicOf(deps, { texts: first.untranslated, subject: o.subject });
  if (!r.complete) return { doc: null, held: true, missing: r.missing };
  const second = build(r.map);
  return second.untranslated.length ? { doc: null, held: true, missing: second.untranslated } : { doc: second, held: false, missing: [] };
}
