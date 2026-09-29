// THE MEANING LAYER — what a line MEANS, not only which words it holds. Seat: sales_engineer. 21 Sep 2026.
//
// Founder, 21 Sep 2026: "i dont wanna end up having agents doing word matching only. they need to have
// the understanding/logic and reasoning". "We distribute office printers and copiers" is plainly office
// equipment, and a list of aliases will always be one phrasing behind the next supplier. Since 29 Sep 2026
// (ruling 890, decision point 93) this layer is the ONLY way a line that is not written exactly as a service
// names one: the alias rules of service_rewrite.ts are gone, and what is exact is decided there by equality.
//
// HOW. Every active service carries a 384-dimension vector of its English and Arabic names and its
// trade's (taxonomy_trade_service.embedding_gte, written by scripts/kb/embed_taxonomy_services.mjs
// through the free in-region gte-small model — ai_gateway {action:'embed'}, which is NOT OpenRouter).
// A line no service is written exactly as is embedded the same way at request time (gte_embed.ts). The
// line's nearest ELIGIBLE service is proposed only when:
//   1. the cosine similarity clears MEANING_FLOOR, and
//   2. A WORD agrees, not another vector: the line holds a HEAD word of that service's name (the
//      thing it is — "copiers" for "Photocopiers & copiers", "trays" for "Cable trays") or one of
//      its aliases.
//
// THE `two_lines` RULE IS GONE (22 Sep 2026, finding SP-F-06). It accepted a service when two
// separate lines landed on it above a stricter cosine floor and NO word anywhere agreed — which is
// still similarity alone, twice. It cannot be otherwise: two lines of one supplier's catalogue are
// written by the same hand about the same business, so the second line is not an independent
// witness, it is the same near-neighbour drawn again. The founder's rule is "either exact match or
// no match", and the estate's own lesson is that a nearest neighbour is always found and has to be
// corroborated by lexemes. A line that only looks similar is now left to the supplier's own words,
// where the sales engineer sees it.
// Eligible: installation, contracting and after-sales services (service_rewrite.isInstallWork) are only
// candidates for a line that itself speaks of such work — "we distribute printers" is not "we repair
// printers" — and never for a supply-only company.
//
// A NEAREST NEIGHBOUR ALONE IS NEVER ACCEPTED. Every line has one, however unrelated. Measured 21 Sep
// 2026 against the live service names: unrelated catalogue lines ("Gold partner", "We are a family
// business since 1990", "Convenience for merchants and customers") score 0.79-0.84 against their
// nearest service; real ones 0.82-0.92. The bands overlap, so similarity is a ranking, not evidence.
// A shared WORD alone is not evidence either: "Cables" shares "cable" with "Cable trays & containment"
// at 0.893 and is not cable trays — which is why the corroborating word has to be the head of the name.
//
// ARABIC. gte-small is an English model: an Arabic line scores 0.85 against Cybersecurity as readily as
// against printers (measured: "نوزع الطابعات وآلات النسخ للمكاتب" -> cybersecurity 0.858). The head-word
// rule rejects that. Since 29 Sep 2026 an Arabic line is read in the MULTILINGUAL space instead: the trimmed
// multilingual-e5-small already deployed for knowledge (embed_ml), against taxonomy_trade_service.embedding_ml
// (serviceMlText, stored by scripts/kb/embed_taxonomy_services.mjs), above ML_FLOOR and corroborated the same
// way (an Arabic alias of the service in the line; Arabic names have no English head word).
//
// WHAT IT NEVER DOES. It never reads spec-table rows (catalogue_read.ts drops them first — "DVR Storage
// Upto 6TB" is a product property), never overrides a service found exactly, and everything it
// adds is a proposal the supplier confirms, shown with the line that supports it.
import { arNorm } from './alias_pattern.ts';
import { isInstallWork, isStop, servicePattern, type ServiceTerm } from './service_rewrite.ts';
import { saysInstallWork } from './catalogue_read.ts';

export type Vec = number[];
/** Which vector space a line is read in: gte-small (English) or the multilingual e5 (Arabic). */
export type Space = 'gte' | 'ml';
export type MeaningService = ServiceTerm & { vec: Vec | null; vec_ml?: Vec | null };
export type MeaningLine = { text: string; vec: Vec | null; space?: Space };
export type MeaningProposal = {
  key: string; trade: string; label_en: string; label_ar: string; similarity: number;
  because: 'head_word' | 'alias'; word: string | null; lines: string[];
};

// Calibrated 21 Sep 2026 on gte-small (numbers above and in service_meaning.test.ts).
export const MEANING_FLOOR = 0.82;
// The multilingual e5 floor, calibrated 29 Sep 2026 on the live service vectors (query/query cosine; see
// scripts/checks/services_are_named_by_exact_name_or_meaning_never_by_alias_words.test.mjs for the numbers).
export const ML_FLOOR = 0.83;
// THE READ BUDGET (29 Sep 2026). Lines were embedded inside the caller's worker, one gte-small run each, so 16 was
// the ceiling the edge CPU cap allowed. Every line is now embedded by the embed_ml function (meaning_embed.ts):
// each call is its own worker, and the caller only waits. MEASURED on production 29 Sep 2026 through embed_ml:
// a gte-small inference costs ~119 ms of the embedding worker (median over 30, the same auth path without the
// inference as the baseline), an e5 query ~517 ms; 40 lines at 8 in flight took the caller <= 5.2 s of wall and no
// CPU of its own. 40 covers the ZZ DEMO catalogue's 26 candidate lines with room for its clauses.
export const MEANING_MAX_LINES = 40;

/** Which space a text is read in: any Arabic letter -> the multilingual model; otherwise gte-small. */
export const meaningSpace = (text: string): Space => (/[؀-ۿ]/.test(String(text ?? '')) ? 'ml' : 'gte');

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

/** THE CLAUSES meaning reads (29 Sep 2026, decision point 93 (b)). One nearest service is read per line, so a
 *  sentence that holds a service and something else ("supply and install ducting for the new majlis") was read
 *  as whichever was nearer. It is split at the connectives a list uses (and, or, with, including, plus, & + /, and
 *  in Arabic a spaced و or و joined to the article: والأسقف -> الأسقف); and a clause is cut where a preposition of
 *  purpose or place begins (for, in, at, from; not "to", which is also "need to supply"), keeping what comes before it — "install ducting | for the
 *  new majlis", "AMC contracts | for towers and villas": what follows says where or for whom, not what is done.
 *  ("of" is not cut: "supply of cable trays" names its service after it.) Each clause holding a content word is
 *  read. Grammar, not vocabulary: nothing here decides which service a clause is. */
export function meaningClauses(text: string): string[] {
  // Punctuation first, then the prepositional tail of each piece ("... for towers and villas" goes whole), then the
  // connectives inside what is left.
  const out = String(text ?? '').split(/[,،;؛]/)
    .map((c) => c.split(/\s+(?:for|in|at|from)\s+/i)[0])
    .flatMap((c) => c.split(/\s+(?:and|or|with|including|plus)\s+|\s*[&+/]\s*|\s+و\s+|\s+(?=وال)/i))
    .map((c) => c.replace(/^و(?=ال)/, '').replace(/\s+/g, ' ').trim())
    .filter((c) => c.length >= 3 && contentWords(c).length > 0);
  return out.length ? [...new Set(out)] : [];
}

/** A pgvector value as PostgREST returns it ("[0.1,0.2,...]"), or an array, or null. */
export function parseVec(v: unknown): Vec | null {
  if (Array.isArray(v)) return v.length && v.every((x) => typeof x === 'number') ? v as Vec : null;
  if (typeof v !== 'string' || !v.startsWith('[')) return null;
  try { const a = JSON.parse(v); return Array.isArray(a) && a.length ? a as Vec : null; } catch { return null; }
}

export function cosine(a: Vec, b: Vec): number {
  let d = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length && i < b.length; i++) { d += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
  return na && nb ? d / Math.sqrt(na * nb) : 0;
}

/** The content words of a text: folded, lower-case, not glue, a plural s and a leading ال / وال removed. */
export function contentWords(text: string): string[] {
  return [...new Set(arNorm(String(text ?? '')).toLowerCase().split(/[^\p{L}\p{N}]+/u)
    .filter((w) => w.length >= 3 && !isStop(w) && !/^\d+$/.test(w))
    .map((w) => w.replace(/^(?:وال|ال)(?=\p{L}{3})/u, '').replace(/(?<=\p{L}{3})s$/u, '')))];
}

/** The head words of a service's English name: the last content word of each part between '&', ',' and
 *  brackets. "Photocopiers & copiers" -> photocopier, copier; "Cable trays & containment" -> tray,
 *  containment; "Office machines (shredders, laminators, binders)" -> machine, shredder, laminator, binder. */
export function headWords(label_en: string): string[] {
  const out: string[] = [];
  for (const part of String(label_en ?? '').split(/[&,()/]| and /)) {
    const cw = contentWords(part);
    if (cw.length) out.push(cw[cw.length - 1]);
  }
  return [...new Set(out)];
}

/** Which lines to spend the MEANING_MAX_LINES embeddings on. A line holding no head word of any service
 *  can only ever be accepted by two-line agreement, so lines that hold one go first. Measured 21 Sep 2026
 *  on the real catalogue: 88 candidate lines, and the one that meaning reads as toners ("...our
 *  high-quality toners.") was the 70th in document order. */
export function meaningCandidates(lines: string[], services: ServiceTerm[], max = MEANING_MAX_LINES): string[] {
  const heads = new Set(services.flatMap((s) => headWords(s.label_en)));
  const uniq = [...new Set(lines.map((l) => l.trim()).filter((l) => l.length >= 3))];
  const worded = uniq.filter((l) => contentWords(l).some((w) => heads.has(w)));
  return [...worded, ...uniq.filter((l) => !worded.includes(l))].slice(0, max);
}

/** The head words of a service's ARABIC name: the FIRST content word of each part between و, '،' and '&' —
 *  an Arabic name puts its head first ("الأسقف المعلقة" -> اسقف; "قواطع الجبس" -> قواطع; "مجاري الهواء
 *  والتهوية" -> مجاري, تهويه). Folded like contentWords (ال removed, fn_ar_norm's letters). */
export function headWordsAr(label_ar: string): string[] {
  const out: string[] = [];
  for (const part of String(label_ar ?? '').split(/[،,&()/]|\s+و\s*|\s+(?=وال)/)) {
    const cw = contentWords(part.replace(/^و(?=ال)/, ''));
    if (cw.length) out.push(cw[0]);
  }
  return [...new Set(out)];
}

// How many nearest services an ARABIC line shortlists (the multilingual space; see proposeByMeaning).
export const ML_TOP = 5;

/** THE CORROBORATING WORD (decision point 92's rule): a head word of the service's name in the line (English for an
 *  English line; Arabic too for an Arabic one), else one of its aliases. It never NAMES a service — the vector did —
 *  it only refuses a vector hit nothing in the line agrees with. */
export function corroborate(s: MeaningService, words: Set<string>, norm: string, ml: boolean): { because: 'head_word' | 'alias' | null; word: string | null } {
  const head = [...headWords(s.label_en), ...(ml ? headWordsAr(s.label_ar) : [])].find((w) => words.has(w)) ?? null;
  if (head) return { because: 'head_word', word: head };
  const alias = (s.aliases || []).find((a) => a.length >= 4 && servicePattern(a)?.test(norm)) ?? null;
  return alias ? { because: 'alias', word: alias } : { because: null, word: null };
}

/** The proposals, strongest first. `stated` are the keys already found exactly (never re-proposed). */
export function proposeByMeaning(lines: MeaningLine[], services: MeaningService[],
  opts: { stated?: string[]; supplyOnly?: boolean; floor?: number; mlFloor?: number } = {}): MeaningProposal[] {
  const stated = new Set(opts.stated || []);
  const eligible = services.filter((s) => !(opts.supplyOnly && isInstallWork(s)));
  type Cand = { s: MeaningService; sim: number; line: string; because: 'head_word' | 'alias' | null; word: string | null };
  const byKey = new Map<string, Cand[]>();
  for (const line of lines.slice(0, MEANING_MAX_LINES)) {
    if (!line.vec) continue;
    // A line is compared in the space it was embedded in: an Arabic line with the multilingual vectors.
    const ml = line.space === 'ml';
    const floor = ml ? (opts.mlFloor ?? ML_FLOOR) : (opts.floor ?? MEANING_FLOOR);
    const work = saysInstallWork(line.text);
    const ranked: [number, MeaningService][] = [];
    for (const s of eligible) {
      const sv = ml ? s.vec_ml : s.vec;
      if (!sv) continue;
      if (!work && isInstallWork(s)) continue;
      ranked.push([cosine(line.vec, sv), s]);
    }
    ranked.sort((a, b) => b[0] - a[0]);
    // English (gte-small): the ONE nearest service, as calibrated 21 Sep 2026. Arabic (e5): the nearest ML_TOP
    // above the floor, the first a name word corroborates — measured 29 Sep 2026, the multilingual space ranks the
    // right service 1st-5th (الدهانات: forgings 0.854, then painting 0.850), and noise scores as high, so the
    // corroborating word decides and the vector only shortlists.
    const shortlist = ranked.slice(0, ml ? ML_TOP : 1).filter(([c]) => c >= floor);
    const words = new Set(contentWords(line.text));
    const norm = arNorm(line.text);
    const pick = shortlist.find(([, s]) => corroborate(s, words, norm, ml).because) ?? shortlist[0];
    if (!pick) continue;
    const [sim, best] = pick;
    const key = `${best.trade_code}.${best.code}`;
    if (stated.has(key)) continue;
    const { because, word } = corroborate(best, words, norm, ml);
    const list = byKey.get(key) || [];
    list.push({ s: best, sim, line: line.text, because, word });
    byKey.set(key, list);
  }
  const out: MeaningProposal[] = [];
  for (const [key, cands] of byKey) {
    const worded = cands.find((c) => c.because);
    const because = worded?.because;
    if (!worded || !because) continue;   // a nearest neighbour is never accepted, however many lines find it
    out.push({
      key, trade: worded.s.trade_code, label_en: worded.s.label_en, label_ar: worded.s.label_ar,
      similarity: Math.round(Math.max(...cands.map((c) => c.sim)) * 1000) / 1000,
      because, word: worded.word,
      lines: [...new Set(cands.map((c) => c.line))].slice(0, 3),
    });
  }
  return out.sort((a, b) => b.similarity - a.similarity);
}
