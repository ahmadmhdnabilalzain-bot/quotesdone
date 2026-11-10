// think/figures.ts — a figure in an answer, read in context, so code can prove it is printed in a source (moved whole from _shared/think.ts).

/** Arabic-Indic and Eastern Arabic-Indic digits as ASCII, so a figure written either way is the same figure. */
const asciiDigits = (s: string) => s.replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x0660)).replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x06F0));
/** Lower case, ASCII digits, no thousands commas, split into words, numbers and '%'. */
const toks = (s: string) => asciiDigits(String(s ?? '').toLowerCase()).replace(/(\d),(?=\d{3})/g, '$1').match(/\d+(?:\.\d+)?|%|[\p{L}]+/gu) ?? [];
const FUNCTION_WORDS = new Set(['a', 'an', 'the', 'per', 'of', 'to', 'for', 'in', 'on', 'at', 'and', 'or', 'is', 'are', 'be', 'by', 'up', 'within', 'about']);
const isNum = (t: string) => /^\d/.test(t);
const COMPARATOR_TAIL = new Set(['than', 'least', 'most']);
/** A figure in context: the word before it and the first content word (or %) after it, as they appear in the text. */
export type Figure = { num: string; before: string | null; after: string | null };
function figuresIn(t: string[]): Figure[] {
  return t.flatMap((x, i) => {
    if (!isNum(x)) return [];
    const back = t.slice(Math.max(0, i - 4), i).reverse().filter((y) => !FUNCTION_WORDS.has(y));
    // a comparator keeps the word it compares ("more than 3" is not "less than 3")
    const before = back[0] && !isNum(back[0]) ? (COMPARATOR_TAIL.has(back[0]) && back[1] && !isNum(back[1]) ? back[1] + ' ' + back[0] : back[0]) : null;
    // '%' is part of the figure, and the word after it is still compared ("3% of the quote" is not "3% of the subscription")
    const pct = t[i + 1] === '%';
    const after = t.slice(i + (pct ? 2 : 1), i + (pct ? 5 : 4)).find((y) => !FUNCTION_WORDS.has(y)) ?? null;
    return [{ num: pct ? x + '%' : x, before, after: after && !isNum(after) ? after : null }];
  });
}
export function figuresOf(answer: string): Figure[] { return figuresIn(toks(answer)); }
/**
 * True only when the answer states at least one figure and EVERY figure is printed in ONE of the sources with the same
 * word before it and the same content word after it ("AED 1500 ... month" is not "AED 1500 ... year"; "USD 1500" is not
 * "AED 1500"). Anything else - no figure, or one figure that differs - goes to the independent model.
 */
export function figuresGrounded(answer: string, sources: string[]): boolean {
  const figs = figuresOf(answer);
  if (!figs.length) return false;
  const inSrc = sources.map((s) => figuresIn(toks(s)));
  // an answer figure with nothing after it ("costs 3%.") claims no unit to contradict; one with a word must match it
  const same = (a: Figure, b: Figure) => a.num === b.num && a.before === b.before && (a.after === null || a.after === b.after);
  return figs.every((f) => inSrc.some((src) => src.some((g) => same(f, g))));
}
