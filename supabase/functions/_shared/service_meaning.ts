// THE MEANING LAYER — what a line MEANS, not only which words it holds. Seat: sales_engineer. 21 Sep 2026.
//
// Founder, 21 Sep 2026: "i dont wanna end up having agents doing word matching only. they need to have
// the understanding/logic and reasoning". The word rules (service_rewrite.ts) name a service only when
// one of its aliases is in the line. "We distribute office printers and copiers" is plainly office
// equipment, and a list of aliases will always be one phrasing behind the next supplier.
//
// HOW. Every active service carries a 384-dimension vector of its English and Arabic names and its
// trade's (taxonomy_trade_service.embedding_gte, written by scripts/kb/embed_taxonomy_services.mjs
// through the free in-region gte-small model — ai_gateway {action:'embed'}, which is NOT OpenRouter).
// A line the word rules left unnamed is embedded the same way at request time (gte_embed.ts). The
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
// rule rejects that, so Arabic gains nothing here and loses nothing — Arabic is served by the word rules.
//
// WHAT IT NEVER DOES. It never reads spec-table rows (catalogue_read.ts drops them first — "DVR Storage
// Upto 6TB" is a product property), never overrides a service the word rules found, and everything it
// adds is a proposal the supplier confirms, shown with the line that supports it.
import { arNorm } from './alias_pattern.ts';
import { isInstallWork, isStop, servicePattern, type ServiceTerm } from './service_rewrite.ts';
import { saysInstallWork } from './catalogue_read.ts';

export type Vec = number[];
export type MeaningService = ServiceTerm & { vec: Vec | null };
export type MeaningLine = { text: string; vec: Vec | null };
export type MeaningProposal = {
  key: string; trade: string; label_en: string; label_ar: string; similarity: number;
  because: 'head_word' | 'alias'; word: string | null; lines: string[];
};

// Calibrated 21 Sep 2026 on gte-small (numbers above and in service_meaning.test.ts).
export const MEANING_FLOOR = 0.82;
// Bounded CPU: each line is one gte-small inference inside the edge function (whose CPU cap no deadline
// bounds). ponytail: 16 lines per request; a longer catalogue's remaining lines are not read by meaning.
export const MEANING_MAX_LINES = 16;

/** What a service's vector is made from: its EN and AR names with its trade's. The embedding script
 *  and every test use this one function, so a vector always means the same words. */
export const serviceEmbedText = (s: { label_en: string; label_ar: string }, trade: { label: string; label_ar?: string | null }) =>
  `${s.label_en} (${trade.label}). ${s.label_ar} (${trade.label_ar ?? ''})`;

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

/** The proposals, strongest first. `stated` are the keys the word rules already found (never re-proposed). */
export function proposeByMeaning(lines: MeaningLine[], services: MeaningService[],
  opts: { stated?: string[]; supplyOnly?: boolean; floor?: number } = {}): MeaningProposal[] {
  const floor = opts.floor ?? MEANING_FLOOR;
  const stated = new Set(opts.stated || []);
  const withVec = services.filter((s) => s.vec && !(opts.supplyOnly && isInstallWork(s)));
  type Cand = { s: MeaningService; sim: number; line: string; because: 'head_word' | 'alias' | null; word: string | null };
  const byKey = new Map<string, Cand[]>();
  for (const line of lines.slice(0, MEANING_MAX_LINES)) {
    if (!line.vec) continue;
    const work = saysInstallWork(line.text);
    let best: MeaningService | null = null; let sim = -1;
    for (const s of withVec) {
      if (!work && isInstallWork(s)) continue;
      const c = cosine(line.vec, s.vec!);
      if (c > sim) { sim = c; best = s; }
    }
    if (!best || sim < floor) continue;
    const key = `${best.trade_code}.${best.code}`;
    if (stated.has(key)) continue;
    const words = new Set(contentWords(line.text));
    const head = headWords(best.label_en).find((w) => words.has(w)) ?? null;
    const norm = arNorm(line.text);
    const alias = head ? null : (best.aliases || []).find((a) => a.length >= 4 && servicePattern(a)?.test(norm)) ?? null;
    const list = byKey.get(key) || [];
    list.push({ s: best, sim, line: line.text, because: head ? 'head_word' : alias ? 'alias' : null, word: head ?? alias });
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
