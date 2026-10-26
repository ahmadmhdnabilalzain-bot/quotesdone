// THE ALIAS PATTERN — how one alias is found in a folded text, English and Arabic. Seat: sales_engineer.
//
// WHAT THIS FILE IS NOW (29 Sep 2026, founder ledger 1054, against ruling 890). It was trade_words.ts, the
// TypeScript twin of public.fn_norm_trades' old word matcher, and its tradesFromText proposed a supplier's
// TRADES from the aliases its documents contained. #893 made the SQL side exact on 23 Sep 2026; the TS side is
// now gone too: a supplier's text names a trade only by an exact code or by meaning over stored vectors
// (trade_resolve.ts). What stays here is the folding and the pattern, which are not a trade decision:
//   * arNorm / foldForMatch - the Arabic folding public.fn_ar_norm applies (service_meaning.contentWords and the
//     service rewrite compare folded words with it);
//   * termPattern - the word-start pattern the SERVICE alias index (service_rewrite.ts; decision point 93,
//     services.from_text, still pending) and the catalogue's supply-only / installation cue words
//     (catalogue_read.ts) are matched with. Replacing those with meaning is decision point 93's work, not this
//     file's; until it is done they keep this one rule rather than a second copy of it.
//
// THE RULES (unchanged; they were written with the SQL matcher #893 retired):
//   1. The input is folded the way public.fn_ar_norm folds it: tashkeel and tatweel removed; أ إ آ ٱ → ا,
//      ى → ي, ة → ه, ؤ → و, ئ → ي; Arabic-Indic digits → 0-9. Then runs of '-', '_', '/', '.' become one
//      space. The alias is folded the same way, so an alias may be stored as it is spelt (نجارة).
//   2. A term is an alias or the code itself, at least 3 characters after folding.
//   3. It matches at the START of a word (Postgres '\m'), case-insensitive; the end stays open, so a
//      stem such as سباك also matches سباكة and سباكين. On this database '\m' already treats Arabic
//      letters as word characters (measured: 'بنجارة' ~ '\mنجارة' is false, 'اعمال نجارة' is true).
//   4. An ARABIC term may carry, before its first word, the definite article and the one-letter
//      proclitics that attach to it — ال, و ف ب ل ك, والـ بالـ فالـ كالـ, لل ولل فلل — and each later
//      word may carry ال — after its conjunction و when it starts with one (نفط وغاز → النفط والغاز).
//      So the alias "مكافحة حريق" matches "مكافحة الحريق", "لمكافحة الحريق" and "ومكافحة حريق".
//      Aliases are therefore stored WITHOUT ال; the SQL file refuses one that has it. The one-letter
//      proclitics are deliberate: بنجارة is "with carpentry". The shared fixture holds a sentence of
//      common words that begin with those letters and must resolve to nothing.
//   An English term is matched exactly as before this file: rule 4 never applies to it.
const MARK = /[ً-ٰٕـۖ-ۭ]/;
const FOLD: Record<string, string> = { 'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ٱ': 'ا', 'ى': 'ي', 'ة': 'ه', 'ؤ': 'و', 'ئ': 'ي' };
for (let d = 0; d < 10; d++) FOLD[String.fromCharCode(0x0660 + d)] = String(d);
const SEP = /[-_/.]/;
const ARABIC_START = /^[ء-ي]/;
// Character-for-character the pattern of the retired SQL word matcher (#893 removed it from fn_norm_trades).
const PROCLITIC = '(?:[وفبلك]?ال|[وف]?لل|[وفبلك])?';
// A later word takes ال, after its conjunction و if it has one. The SQL builds the same string with
// replace(replace(x, ' ', ' (?:ال)?'), ' (?:ال)?و', ' و(?:ال)?').
const laterWord = (w: string) => (w.startsWith('و') ? 'و(?:ال)?' + w.slice(1) : '(?:ال)?' + w);

const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** public.fn_ar_norm, in TypeScript. */
export function arNorm(s: string): string {
  let out = '';
  for (const c of String(s ?? '')) if (!MARK.test(c)) out += FOLD[c] ?? c;
  return out;
}

/** The text as the matcher sees it (rule 1), with the index in the ORIGINAL text of every character,
 *  so the evidence snippet is the supplier's own line, not the folded one. */
export function foldForMatch(text: string): { norm: string; at: number[] } {
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
  const body = ARABIC_START.test(a)
    ? PROCLITIC + esc(a).split(' ').map((w, i) => (i ? laterWord(w) : w)).join(' ')
    : esc(a);
  return new RegExp('(?<![\\p{L}\\p{N}_])' + body, 'iu');
}
