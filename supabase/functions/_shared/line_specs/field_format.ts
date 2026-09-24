// field_format — what the FORMAT of a quote line settles about a required spec, without a model.
// Seat: sales_engineer (the quote hold desk); engine: it_engineer. 24 Sep 2026.
//
// WHY THIS IS NOT WORD MATCHING (founder rule 890): nothing here reads what a word MEANS. It reads a number beside a
// unit mark, exactly as receipt_parse reads an amount beside a currency mark. The unit comes from the pack's own
// checklist label (in brackets: "rated capacity (tonnes)"), never from guessing what the supplier meant:
//   * a spec whose label names a unit needs a number: a line with no digit at all cannot state it -> absent;
//   * exactly one spec of the checklist in that unit and exactly one "<number> <unit>" on the line -> that verbatim
//     text is the value;
//   * anything else (no unit in the label, two readings, none) is AMBIGUOUS and reasoned_specs asks think().
// It lives apart from reasoned_specs.ts because that file's registry proof (decision_points.json,
// quote.line_specs_readerless) forbids a regex there: the judgement stays there, the format parser stays here.
import type { Attr } from './model.ts';

const UNITS = new Set(['mm', 'cm', 'm', 'm2', 'm3', 'mm2', 'kg', 't', 'tonne', 'ton', 'l', 'litre', 'liter', 'minute', 'hour', 'day', 'year', 'month', 'kw', 'kva', 'v', 'hz', '%', 'gsm', 'micron']);
const singular = (u: string) => u.toLowerCase().replace(/s$/, '');
/** The unit a spec's own label names in brackets, if it is one of the units above. */
export function labelUnit(label: string): string | null {
  for (const m of String(label).matchAll(/\(([^()]{1,10})\)/g)) { const u = singular(m[1].trim()); if (UNITS.has(u)) return u; }
  return null;
}
/** What shape alone decides for one line: values present (verbatim), codes absent, and the specs still ambiguous. */
export function shapeDecides(text: string, checklist: Attr[]): { present: Record<string, string>; absent: string[]; ambiguous: Attr[] } {
  const present: Record<string, string> = {}; const absent: string[] = []; const ambiguous: Attr[] = [];
  const hasDigit = /\d/.test(text);
  const perUnit = new Map<string, number>();
  for (const a of checklist) { const u = labelUnit(a.en); if (u) perUnit.set(u, (perUnit.get(u) ?? 0) + 1); }
  for (const a of checklist) {
    const u = labelUnit(a.en);
    if (!u) { ambiguous.push(a); continue; }
    if (!hasDigit) { absent.push(a.code); continue; }
    const esc = u.replace(/[.*+?^${}()|[\]\\%]/g, '\\$&');
    const hits = [...text.matchAll(new RegExp(`\\d+(?:[.,]\\d+)?\\s*${esc}${/^[a-z]/.test(u) ? 's?\\b' : ''}`, 'gi'))];
    if (perUnit.get(u) === 1 && hits.length === 1) present[a.code] = hits[0][0];
    else ambiguous.push(a);
  }
  return { present, absent, ambiguous };
}
