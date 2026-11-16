// THE STORED SERVICE VECTORS' RECIPE (sales_engineer, 21 Sep 2026; cut to this on 16 Nov 2026 by it_engineer).
//
// Every active service carries a 384-dimension gte-small vector of its names (taxonomy_trade_service.embedding_gte) and a
// multilingual e5 vector (embedding_ml), written by scripts/kb/embed_taxonomy_services.mjs from serviceEmbedText /
// serviceMlText, current while their sha is textSha of that text. service_vocabulary.serviceVocab reads them back through
// parseVec.
//
// THE CODE MATCHER THAT READ THEM IS GONE (16 Nov 2026, simplification wave A, DUP item 5). proposeByMeaning proposed the
// nearest service to a catalogue line when a head word or alias of it agreed (decision points 92 and 93), embedding each line
// through meaning_embed.ts. Founder ruling 1627 (11 Nov 2026): a service is understood by the model reading the documents, not
// by matching; _shared/trade_resolve.ts had already deleted every code proposal path, and nothing at runtime called it
// (grep: 0 runtime callers; production: no routine or cron names it). It was removed with its helpers, its tests and
// meaning_embed.ts; scripts/checks/services_are_named_by_exact_name_or_meaning_never_by_alias_words.test.mjs keeps it out.
import type { ServiceTerm } from './service_rewrite.ts';

export type Vec = number[];
export type MeaningService = ServiceTerm & { vec: Vec | null; vec_ml?: Vec | null };

/** English aliases only (gte-small is an English model). */
const enAliases = (s: { aliases?: string[] | null }) => (s.aliases || []).filter((a) => !/[؀-ۿ]/.test(a)).slice(0, 16);

/** What a service's gte-small vector is made from: its English name and English aliases, its Arabic name, and
 *  its trade's names. The embedding script, the live checks and the sha that says a stored vector is current all
 *  use this one function, so a vector always means the same words. (Aliases feed the VECTOR, never a string
 *  match: 29 Sep 2026, decision point 93 (b).) */
export const serviceEmbedText = (s: { label_en: string; label_ar: string; aliases?: string[] | null }, trade: { label: string; label_ar?: string | null }) => {
  const en = enAliases(s);
  return `${s.label_en}${en.length ? ': ' + en.join(', ') : ''} (${trade.label}). ${s.label_ar} (${trade.label_ar ?? ''})`;
};

/** What a service's multilingual vector is made from: both names, every alias, and the trade's names. */
export const serviceMlText = (s: { label_en: string; label_ar: string; aliases?: string[] | null }, trade: { label: string; label_ar?: string | null }) =>
  [s.label_en, s.label_ar, ...(s.aliases || []).slice(0, 24), trade.label, trade.label_ar ?? ''].filter(Boolean).join('; ');

/** SHA-256 (hex) of the text a vector was made from: a stored vector is current when its sha is this. */
export async function textSha(text: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** A pgvector value as PostgREST returns it ("[0.1,0.2,...]"), or an array, or null. */
export function parseVec(v: unknown): Vec | null {
  if (Array.isArray(v)) return v.length && v.every((x) => typeof x === 'number') ? v as Vec : null;
  if (typeof v !== 'string' || !v.startsWith('[')) return null;
  try { const a = JSON.parse(v); return Array.isArray(a) && a.length ? a as Vec : null; } catch { return null; }
}
