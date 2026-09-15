// TRADE WORDS — the TypeScript twin of public.fn_norm_trades, in English AND Arabic. Seat: sales_engineer.
//
// One matcher, no dependencies, so the Deno supplier-document reader (supplier_doc_trades.ts) and the
// Node parity check (scripts/checks/arabic_trade_words_resolve_the_same_in_sql_and_ts.test.mjs) run
// the same code. The SQL it mirrors is scripts/sql/an_arabic_document_names_its_trades_in_arabic.sql.
//
// MEASURED 15 Sep 2026, before this file: all 40 active taxonomy_trade codes had English aliases
// only (0 aliases containing an Arabic letter), so fn_norm_trades('نجارة وألمنيوم') returned {} and an
// Arabic-only company profile proposed no trades.
//
// THE RULES, identical on both sides:
//   1. The input is folded the way public.fn_ar_norm folds it: tashkeel and tatweel removed; أ إ آ ٱ → ا,
//      ى → ي, ة → ه, ؤ → و, ئ → ي; Arabic-Indic digits → 0-9. Then runs of '-', '_', '/', '.' become one
//      space. The alias is folded the same way, so an alias may be stored as it is spelt (نجارة).
//   2. A term is an alias or the code itself, at least 3 characters after folding.
//   3. It matches at the START of a word (Postgres '\m'), case-insensitive; the end stays open, so a
//      stem such as سباك also matches سباكة and سباكين. On this database '\m' already treats Arabic
//      letters as word characters (measured: 'بنجارة' ~ '\mنجارة' is false, 'اعمال نجارة' is true).
//   4. An ARABIC term may carry, before its first word, the definite article and the one-letter
//      proclitics that attach to it — ال, و ف ب ل ك, والـ بالـ فالـ كالـ, لل ولل فلل — and each later
//      word may carry ال. So the alias "مكافحة حريق" matches "مكافحة الحريق", "لمكافحة الحريق" and
//      "ومكافحة حريق". Aliases are therefore stored WITHOUT ال; the SQL file refuses one that has it.
//   An English term is matched exactly as before this file: rule 4 never applies to it.
//
// EXACT OR NONE. Every alias names exactly one code. There is no similarity, no stemmer, no model:
// a word that is not an alias (or does not start with one) proposes nothing.
export type TradeTerm = { code: string; aliases?: string[] | null };
export type TradeHit = { code: string; phrases: string[]; snippet: string };

const MARK = /[ً-ٰٕـۖ-ۭ]/;
const FOLD: Record<string, string> = { 'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا', 'ى': 'ي', 'ة': 'ه', 'ؤ': 'و', 'ئ': 'ي' };
for (let d = 0; d < 10; d++) FOLD[String.fromCharCode(0x0660 + d)] = String(d);
const SEP = /[-_/.]/;
const ARABIC_START = /^[ء-ي]/;
// Kept character-for-character equal to the SQL pattern; the parity check compares their results.
const PROCLITIC = '(?:[وفبلك]?ال|[وف]?لل|[وفبلك])?';
const INNER_ARTICLE = ' (?:ال)?';

const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** public.fn_ar_norm, in TypeScript. */
export function arNorm(s: string): string {
  let out = '';
  for (const c of String(s ?? '')) if (!MARK.test(c)) out += FOLD[c] ?? c;
  return out;
}

/** The text as the matcher sees it (rule 1), with the index in the ORIGINAL text of every character,
 *  so the evidence snippet is the supplier's own line, not the folded one. */
function foldForMatch(text: string): { norm: string; at: number[] } {
  let norm = '';
  const at: number[] = [];
  let inSep = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (MARK.test(c)) continue; // removed before the separator rule, as fn_ar_norm runs first in SQL
    if (SEP.test(c)) {
      if (!inSep) { norm += ' '; at.push(i); inSep = true; }
      continue;
    }
    inSep = false;
    norm += FOLD[c] ?? c;
    at.push(i);
  }
  return { norm, at };
}

/** The regular expression for one term, or null when it is too short to be a term (rule 2). */
export function termPattern(term: string): RegExp | null {
  const a = arNorm(term);
  if (a.length < 3) return null;
  const body = ARABIC_START.test(a) ? PROCLITIC + esc(a).split(' ').join(INNER_ARTICLE) : esc(a);
  return new RegExp('(?<![\\p{L}\\p{N}_])' + body, 'iu');
}

/** Every trade whose alias (or code) the text names, with the phrases and the line they were found on. */
export function tradesFromText(text: string, vocab: TradeTerm[]): TradeHit[] {
  const src = String(text ?? '');
  const { norm, at } = foldForMatch(src);
  const hits: TradeHit[] = [];
  for (const t of vocab) {
    const terms = [...(t.aliases || []), t.code].filter((a): a is string => typeof a === 'string');
    const phrases: string[] = [];
    let snippet = '';
    for (const a of terms) {
      const re = termPattern(a);
      const m = re ? re.exec(norm) : null;
      if (!m) continue;
      if (!phrases.includes(a.toLowerCase())) phrases.push(a.toLowerCase());
      if (!snippet) {
        const s = at[m.index];
        const e = at[m.index + m[0].length - 1] + 1;
        const start = src.lastIndexOf('\n', s) + 1;
        const endNl = src.indexOf('\n', e);
        const line = src.slice(start, endNl < 0 ? src.length : endNl);
        const rel = s - start;
        snippet = line.slice(Math.max(0, rel - 70), rel + (e - s) + 70).replace(/\s+/g, ' ').trim();
      }
    }
    if (phrases.length) hits.push({ code: t.code, phrases: phrases.slice(0, 5), snippet: snippet.slice(0, 180) });
  }
  return hits;
}
