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
import { serviceVocab, tradeLabelVocab } from './service_vocabulary.ts';

export type TradeHit = {
  code: string;
  via: 'exact_code' | 'meaning';
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
};

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

const lineHolding = (lines: string[], phrase: string) => (lines.find((l) => l.includes(phrase)) ?? phrase).slice(0, 180);

/** Both paths over one text. Never throws: a path that could not run says so in its state. */
export async function tradesOfText(text: string, deps: TradeResolveDeps, opts: { supplyOnly?: boolean } = {}): Promise<TradeRead> {
  const lines = textLines(text);
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
    tradeLabels: await tradeLabelVocab(admin),
    normTrades: async (phrases) => {
      const { data: m, error: e } = await admin.rpc('fn_norm_trades_many', { p_texts: phrases.slice(0, EXACT_MAX_PHRASES) });
      return e || !m || typeof m !== 'object' ? null : m as Record<string, string[]>;
    },
  };
}
