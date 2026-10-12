// THE TRADES A SUPPLIER'S TEXT NAMES — by exact code, or by meaning over stored vectors. Never by its words.
// Seat: sales_engineer. 29 Sep 2026, founder ledger 1054 (round 3 of 1018), against ruling 890 ("no word
// matching anywhere").
//
// WHAT THIS REPLACES. trade_words.ts found a trade wherever one of its aliases occurred in a document, word-start
// anchored: "Activities: Plumbing works and drainage maintenance" -> plumbing, because 'plumbing' and 'drainage'
// are aliases. #893 made the SQL side exact on 23 Sep 2026 (fn_norm_trades accepts a live code or an intake slug
// and returns NULL for free text); the TypeScript side kept reading words for suppliers' documents until this
// file. trade_words.ts is gone; its Arabic folding and alias pattern live on in alias_pattern.ts for the SERVICE
// alias index (decision point 93, still pending), which is not a trade decision.
//
// TWO PATHS, the ones the rest of the system uses:
//   1. EXACT CODE. A line or list item that IS a live taxonomy code or an intake slug, as public.fn_norm_trades
//      resolves it ("HVAC", "Electrical", "Carpentry"). The database routine decides, through
//      fn_norm_trades_many (one call per text), so there is one definition of "exact". A sentence resolves to
//      nothing, as it does in SQL.
//   2. MEANING. The lines are read clause by clause (meaningClauses), each embedded by embed_ml in its own space
//      (gte-small for English, the multilingual e5 for Arabic; free, in-region, not OpenRouter: meaning_embed.ts)
//      and compared with the stored vectors of every active service (embedding_gte / embedding_ml) by
//      service_meaning.proposeByMeaning - the rule the Services tab reads a catalogue with: similarity above
//      MEANING_FLOOR AND the line holds the head word of that service's name (a nearest neighbour alone is never
//      accepted). An accepted service names its trade; the evidence is the line, the service and the similarity.
// Nothing else proposes a trade. A line that neither IS a code nor MEANS a service proposes nothing, and a text
// whose meaning could not be read says so (meaning: embedding_unavailable / budget_spent), never "no trades".
//
// CEILING (stated, not hidden): meaning reads at most MEANING_MAX_LINES clauses per call, and a caller reading
// several documents shares one budget of that size (each clause is one embed_ml call; service_meaning.ts has the
// measurement). The clauses holding a service head word go first (meaningCandidates).
import { contentWords, MEANING_MAX_LINES, meaningCandidates, meaningClauses, proposeByMeaning, type MeaningService } from './service_meaning.ts';
import { splitPhrases } from './service_rewrite.ts';
import { embedLines, remoteEmbedder, type Embedder } from './meaning_embed.ts';
import { serviceVocab, tradeArNameVocab, tradeLabelVocab } from './service_vocabulary.ts';
import { isNameOrReachLine, saysInstallWork, supplyOnlyOf } from './catalogue_read.ts';
import { NAME_LABELS } from './document_expiry.ts';

export type TradeHit = {
  code: string;
  via: 'exact_code' | 'exact_name' | 'meaning';
  /** what named it: the exact phrase, or the service the line means (its English label, lower case) */
  phrases: string[];
  /** the supplier's own line it was found on */
  snippet: string;
  /** meaning only: the cosine similarity of the line to the service's stored vector */
  similarity?: number;
};
export type ExactState = 'on' | 'unavailable' | 'nothing_to_read';
export type MeaningState = 'on' | 'service_vectors_missing' | 'embedding_unavailable' | 'budget_spent' | 'nothing_to_read';
export type TradeRead = { trades: TradeHit[]; exact: ExactState; meaning: MeaningState };

export type TradeResolveDeps = {
  /** public.fn_norm_trades over many phrases (public.fn_norm_trades_many): only the phrases that resolve,
   *  phrase -> codes; null when the database could not be asked. */
  normTrades: (phrases: string[]) => Promise<Record<string, string[]> | null>;
  /** The active services with their stored vectors; read once per request. */
  services: MeaningService[];
  /** A clause -> its vector in the given space (meaning_embed.remoteEmbedder); null when it failed. */
  embed: Embedder;
  /** Lines meaning may still read in this request, shared by every text read with these deps. */
  budget: { left: number };
  /** taxonomy_trade code -> its English label: lets meaning accept a line naming a trade in general (service_meaning.proposeByMeaning). */
  tradeLabels?: Record<string, string>;
  /** taxonomy_trade code -> its Arabic name (label_ar): the exact-name path for an Arabic work clause. */
  tradeNamesAr?: Record<string, string>;
};

// ── THE TRADE'S OWN ARABIC NAME (12 Oct 2026, sales_engineer) ─────────────────────────────────────────────────────
// A UAE licence often prints its activities in Arabic only. Meaning cannot confirm them: on the e5 vectors the
// activity "أعمال الألمنيوم" scores 0.868, the company name "فالكون الألمنيوم ذ.م.م" 0.850 and the metal trader
// "تجارة الألمنيوم والنحاس" 0.862 (ML_FLOOR 0.83) - no separation. So an Arabic clause is read by NAME, exactly:
//   * the clause is WORK (catalogue_read's own install/contracting words: أعمال، مقاولات، تركيب ...) and not
//     supply-only - a company name and a trading clause ("تجارة ...") name no work and propose nothing;
//   * it holds a WHOLE part of the trade's own Arabic name (taxonomy_trade.label_ar, work words left out): the first
//     part whole, one word or several ("الأعمال الكهربائية" -> كهربائية; "تنسيق الحدائق" both words), or a later
//     part of several words whole ("أدوات صحية"). No single word of a longer part decides: "أعمال تنسيق المشاريع" is
//     not landscaping, "تركيب أدوات المطبخ" not plumbing, "أعمال التشطيبات الداخلية" not painting (review of #1312);
//   * a name two trades share decides nothing - unless one of them puts its CODE at that part of its English
//     name ("Aluminium & cladding" / "الألمنيوم والتكسية"): الألمنيوم is the aluminium trade, not non_ferrous_metals
//     ("الألمنيوم والنحاس والمعادن غير الحديدية").
// Words fold like contentWords (letters, ال) and nothing else: no plural folding, so "الدهان" is not "الدهانات".
// ponytail: Arabic clauses only, and only by the names in the table; a supplier's word the table's name lacks is
// reached by correcting the trade's Arabic name, never by a list here.
const arWords = (s: string) => contentWords(s);
const AR_PART = /[\u060C,&()/]|\s+\u0648\s*|\s+(?=\u0648\u0627\u0644)/;   // the Arabic comma, or the joining "and"
const isArabic = (s: string) => /[\u0600-\u06FF]/.test(s);

/** Arabic head word -> the ONE trade it names (see above). */
export function arabicNameHeads(labelsAr: Record<string, string>, labelsEn: Record<string, string> = {}): Map<string, string> {
  const claims = new Map<string, Set<string>>(), codeOf = new Map<string, string>();
  for (const [code, ar] of Object.entries(labelsAr)) {
    const arParts = String(ar ?? '').split(AR_PART).map((p) => arWords(p.replace(/^\u0648(?=\u0627\u0644)/, '')).filter((w) => !saysInstallWork(w)));
    const enParts = String(labelsEn[code] ?? '').split(/[&,()/]| and /).map((p) => contentWords(p));
    const cw = contentWords(code.replace(/_/g, ' '));
    arParts.forEach((p, i) => {
      if (!p.length) return;
      // The trade is named only by a WHOLE part of its name: the first part (one word or several - "تنسيق الحدائق",
      // never "تنسيق" alone: "أعمال تنسيق المشاريع" is not landscaping), or a later part of several words. A word of a
      // later part never decides alone: "تركيب أدوات المطبخ" is not plumbing, "أعمال التشطيبات الداخلية" is not painting.
      const whole = p.join(' ');
      // A one-word later part is a single word of the name, so it decides nothing either ("التشطيبات").
      for (const k of new Set(i === 0 || p.length > 1 ? [whole] : [])) {
        if (!claims.has(k)) claims.set(k, new Set());
        claims.get(k)!.add(code);
      }
      if (cw.length === 1 && enParts.length === arParts.length && enParts[i]?.length === 1 && enParts[i][0] === cw[0]) codeOf.set(whole, code);
    });
  }
  const out = new Map<string, string>();
  for (const [h, codes] of claims) {
    if (codes.size === 1) out.set(h, [...codes][0]);
    else if (codeOf.has(h)) out.set(h, codeOf.get(h)!);
  }
  return out;
}

/** The trades an Arabic WORK clause names by a trade's own Arabic name; [] for anything else. */
export function tradesByArabicName(clause: string, heads: Map<string, string>): { code: string; word: string }[] {
  if (!isArabic(clause) || !saysInstallWork(clause) || supplyOnlyOf(clause).supply_only) return [];
  const seen = new Map<string, string>();
  // the name's words IN ORDER and side by side: "أعمال تنسيق المشاريع والحدائق" holds تنسيق and حدائق, not "تنسيق الحدائق"
  const seq = ` ${arWords(clause).join(' ')} `;
  for (const [k, c] of heads) if (!seen.has(c) && seq.includes(` ${k} `)) seen.set(c, k);
  return [...seen].map(([code, word]) => ({ code, word }));
}

// A code or slug is a few words at most ("engineering and architectural consultancies" is the longest slug).
export const EXACT_MAX_WORDS = 5;
export const EXACT_MAX_PHRASES = 400;
export const TEXT_MAX = 80_000;

/** The lines of a text worth reading (two characters or more), one space each, in order, once. */
export function textLines(text: string): string[] {
  return [...new Set(String(text ?? '').slice(0, TEXT_MAX).split(/\r?\n/)
    .map((l) => l.replace(/\s+/g, ' ').trim()).filter((l) => l.length >= 2))];
}

/** The phrases that could BE a code or a slug: whole lines and list items of a few words. */
export function exactCandidates(lines: string[]): string[] {
  const out = new Set<string>();
  for (const p of splitPhrases(lines.join('\n'), TEXT_MAX, EXACT_MAX_PHRASES * 4)) {
    if (p.split(' ').length <= EXACT_MAX_WORDS && p.length <= 60) out.add(p);
    if (out.size >= EXACT_MAX_PHRASES) break;
  }
  return [...out];
}

// A NAME PRINTED WITHOUT A LEGAL SUFFIX (12 Oct 2026, unsuffixed-names). isNameOrReachLine knows a name only by its
// suffix, so "ZZ DEMO Falcon Cleaning" still proposed cleaning. A name is known two more ways, both exact:
//   the LAYOUT  a line that is a labelled name field ("Company Name:", "Trade Name:", "الاسم التجاري:" - the labels
//               document_expiry reads the licence's name by) is a name, whatever follows the label;
//   the NAMES   the supplier's registered company name, the licence's legal name (read by code or by the model) and
//               the names the document's own name fields print: wherever one occurs in a line it is cut out, with or
//               without its legal suffix, and the rest of the line is still read ("ZZ DEMO Falcon Cleaning provides
//               painting works" keeps "provides painting works"). Nothing similar is guessed: only the exact name.
const LEGAL_SUFFIX = /[\s,.\-]*(?:l\.?\s?l\.?\s?c\.?|fz[\s-]?llc|fze|fzco|est\.?|establishment|\u0630\s?\.?\s?\u0645\s?\.?\s?\u0645\.?)\s*$/iu;
const escRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const NAME_FIELD = new RegExp('^\\s*(?:' + NAME_LABELS.map(escRe).join('|') + ')(?![\\p{L}])\\s*[:：\\-]?', 'iu');
export const isNameField = (line: string): boolean => NAME_FIELD.test(line);
/** Each name as printed and without its legal suffix; a form shorter than five characters is not used. */
export function nameForms(names: (string | null | undefined)[]): string[] {
  const out = new Set<string>();
  for (const n of names) {
    let f = String(n ?? '').replace(/\s+/g, ' ').trim();
    while (f) {
      if (f.length >= 5 && /\p{L}{2}/u.test(f)) out.add(f.toLowerCase());
      const cut = f.replace(LEGAL_SUFFIX, '').trim();
      if (cut === f) break;
      f = cut;
    }
  }
  return [...out].sort((a, b) => b.length - a.length);
}
const EDGE = /^[\s\-–—:|,.]+|[\s\-–—:|,.]+$/g;
/** The line with every known name cut out; null when it is a name field, or nothing but a name was on it. */
export function withoutNames(line: string, forms: string[]): string | null {
  if (isNameField(line)) return null;
  let l = line;
  for (const f of forms) l = l.replace(new RegExp('(?<![\\p{L}\\p{N}])' + escRe(f).replace(/ /g, '\\s+') + '(?![\\p{L}\\p{N}])', 'giu'), ' ');
  if (l === line) return line;
  l = l.replace(/\s+/g, ' ').replace(EDGE, '').trim();
  return /\p{L}{2}/u.test(l) ? l : null;
}

const lineHolding = (lines: string[], phrase: string) => (lines.find((l) => l.includes(phrase)) ?? phrase).slice(0, 180);

/** Both paths over one text. Never throws: a path that could not run says so in its state. */
export async function tradesOfText(text: string, deps: TradeResolveDeps, opts: { supplyOnly?: boolean; names?: (string | null | undefined)[] } = {}): Promise<TradeRead> {
  // A NAME OR CONTACT LINE PROPOSES NOTHING, by any path (12 Oct 2026, accuracy suite). "Legal Name: ZZ DEMO Falcon
  // Cleaning LLC" was proposed cleaning (head_word), its "Legal Name" label legal_services (meaning 0.82), and
  // "... Falcon Glazing LLC" glazing (0.821): a company's name says who it is, never what it does, and a wrong trade
  // sends a request to the wrong supplier. The line is dropped before both paths when it carries a legal-entity suffix
  // (LLC, FZE, FZCO, ذ.م.م), an e-mail, a web address or a phone number (catalogue_read.isNameOrReachLine) - never on a
  // bare "mobile" or an address word, which work lines carry ("Mobile crane hire", "Office fit-out, 3 floors").
  // A name printed WITHOUT a suffix is cut out by its layout and by the known names (withoutNames, above).
  const forms = nameForms(opts.names ?? []);
  const lines = [...new Set(textLines(text).filter((l) => !isNameOrReachLine(l))
    .map((l) => withoutNames(l, forms)).filter((l): l is string => !!l && l.length >= 2))];
  const hits = new Map<string, TradeHit>();
  const add = (h: TradeHit) => {
    const cur = hits.get(h.code);
    if (!cur) { hits.set(h.code, h); return; }
    for (const p of h.phrases) if (cur.phrases.length < 5 && !cur.phrases.includes(p)) cur.phrases.push(p);
  };

  // 1. exact codes, decided by the database's own routine
  let exact: ExactState = 'nothing_to_read';
  const cands = exactCandidates(lines);
  if (cands.length) {
    let map: Record<string, string[]> | null = null;
    try { map = await deps.normTrades(cands); } catch { map = null; }
    exact = map ? 'on' : 'unavailable';
    for (const [phrase, codes] of Object.entries(map ?? {})) {
      for (const code of Array.isArray(codes) ? codes : []) {
        add({ code, via: 'exact_code', phrases: [phrase.toLowerCase()], snippet: lineHolding(lines, phrase) });
      }
    }
  }

  // 1b. an Arabic work clause, by the trade's own Arabic name (exact; see tradesByArabicName)
  if (deps.tradeNamesAr) {
    const heads = arabicNameHeads(deps.tradeNamesAr, deps.tradeLabels);
    for (const l of lines) for (const clause of l.split(/[\u060C,;|]+/)) {
      for (const { code, word } of tradesByArabicName(clause, heads)) add({ code, via: 'exact_name', phrases: [word], snippet: l.slice(0, 180) });
    }
  }

  // 2. meaning, over the stored service vectors
  let meaning: MeaningState = 'nothing_to_read';
  if (lines.some((l) => l.length >= 3)) {
    // Each line clause by clause; the evidence is the supplier's whole line.
    const origin = new Map<string, string>();
    // A ONE-word piece split off a longer line is not read by meaning (7 Oct 2026, accuracy suite ledger 1162): "Glass
    // and Glazing Works" splits into "Glass", whose nearest service is "cosmetic & perfume glass" with its head word in
    // it, and a glazing contractor was proposed for glass containers; "أعمال تبليط الأرضيات والجدران" splits into
    // "الجدران" (walls) and a tiling contractor was proposed for wallpaper. The piece only qualifies its neighbour; the
    // exact path above has already put it to fn_norm_trades ("glass" -> glazing). A line that IS one word (a catalogue
    // heading "UPS") is still read by meaning, as before.
    const oneWord = (s: string) => s.trim().split(/\s+/).length < 2;
    for (const l of lines) for (const c of meaningClauses(l)) if (!origin.has(c) && !(oneWord(c) && !oneWord(l.replace(/[\/|:;,،.\-]+/g, ' ')))) origin.set(c, l);
    if (!deps.services.some((s) => s.vec || s.vec_ml)) meaning = 'service_vectors_missing';
    else if (deps.budget.left <= 0) meaning = 'budget_spent';
    else if (origin.size) {
      const todo = meaningCandidates([...origin.keys()], deps.services, Math.min(MEANING_MAX_LINES, deps.budget.left));
      deps.budget.left -= todo.length;
      const read = await embedLines(todo, deps.embed);
      if (!read.some((l) => l.vec)) meaning = 'embedding_unavailable';
      else {
        meaning = 'on';
        const codeWords = await codeWordsOf(lines, deps);
        const props = proposeByMeaning(read, deps.services, { supplyOnly: opts.supplyOnly, tradeLabels: deps.tradeLabels, codeWords });
        for (const p of props) {
          const line = origin.get(p.lines[0] ?? '') ?? p.lines[0] ?? '';
          add({ code: p.trade, via: 'meaning', phrases: [p.label_en.toLowerCase()], snippet: line.slice(0, 180), similarity: p.similarity });
        }
      }
    }
  }
  return { trades: [...hits.values()].sort((a, b) => a.code.localeCompare(b.code)), exact, meaning };
}

/** The single words of the text that public.fn_norm_trades resolves to exactly ONE trade (a live code, or a stored
 *  intake alias such as "aluminum"), keyed as contentWords folds them; {} when the database could not be asked. */
export async function codeWordsOf(lines: string[], deps: TradeResolveDeps): Promise<Record<string, string>> {
  const raw = [...new Set(lines.join(' ').toLowerCase().split(/[^\p{L}]+/u).filter((w) => w.length >= 3 && contentWords(w).length === 1))].slice(0, EXACT_MAX_PHRASES);
  if (!raw.length) return {};
  let map: Record<string, string[]> | null = null;
  try { map = await deps.normTrades(raw); } catch { map = null; }
  const out: Record<string, string> = {};
  for (const [w, codes] of Object.entries(map ?? {})) if (Array.isArray(codes) && codes.length === 1) out[contentWords(w)[0]] = codes[0];
  return out;
}

/** The deps as an edge function builds them: the database routine, the stored vectors, embed_ml. */
// deno-lint-ignore no-explicit-any
export async function liveTradeDeps(admin: any, caller = 'supplier_doc_trades'): Promise<TradeResolveDeps> {
  return {
    services: await serviceVocab(admin), embed: remoteEmbedder(admin, caller), budget: { left: MEANING_MAX_LINES },
    tradeLabels: await tradeLabelVocab(admin), tradeNamesAr: await tradeArNameVocab(admin),
    normTrades: async (phrases) => {
      const { data: m, error: e } = await admin.rpc('fn_norm_trades_many', { p_texts: phrases.slice(0, EXACT_MAX_PHRASES) });
      return e || !m || typeof m !== 'object' ? null : m as Record<string, string[]>;
    },
  };
}
