import { normText } from '../../_shared/line_specs/model.ts';
import { OPTION_HEAD } from '../../_shared/line_specs/options.ts';
import { type BoqRow, type WLine } from './types.ts';

// ---------------------------------------------------------------------------------------------
// Matching the BOQ to the quotation, by words.
// ---------------------------------------------------------------------------------------------
const STOP = new Set(['and', 'the', 'for', 'with', 'all', 'per', 'including', 'incl', 'supply', 'install', 'installation', 'fixing',
  'item', 'items', 'work', 'works', 'provide', 'providing', 'nos', 'sqm', 'each', 'type', 'توريد', 'تركيب', 'وتركيب', 'مع', 'في', 'من', 'على']);
const toks = (s: unknown) => normText(String(s ?? '')).toLowerCase().split(/[^\p{L}\p{N}]+/u)
  .filter((w) => w.length >= 3 && !STOP.has(w) && !/^\d+$/.test(w)).map((w) => w.replace(/ies$/, 'y').replace(/s$/, ''));
const UNIT: [RegExp, string][] = [
  [/^(m2|m²|sqm|sq\.?\s?m(?:tr|t)?|square\s*met(?:er|re)s?|متر مربع|م2|م²)$/i, 'm2'],
  [/^(m3|m³|cum|cbm|cu\.?\s?m|cubic\s*met(?:er|re)s?|متر مكعب|م3)$/i, 'm3'],
  [/^(lm|rm|rmt|r\.m|l\.m|m|mtrs?|met(?:er|re)s?|linear\s*met(?:er|re)s?|running\s*met(?:er|re)s?|متر طولي|م\.ط|متر|م)$/i, 'm'],
  [/^(nos?|nr|pcs?|pieces?|each|ea|units?|عدد|قطعة|حبة|وحدة)$/i, 'nr'],
  [/^(sets?|طقم|مجموعة)$/i, 'set'],
  [/^(ls|l\.s|lot|lump\s*sum|job|مقطوعية)$/i, 'ls'],
  [/^(kg|kgs|kilograms?|كغ|كجم)$/i, 'kg'],
  [/^(t|tons?|tonnes?|طن)$/i, 't'],
  [/^(l|ltr|litres?|liters?|لتر)$/i, 'l'],
];
/** A unit in one spelling, so "sqm" and "m²" agree. An unknown unit is returned as written. */
export function normUnit(u: unknown): string {
  const s = normText(String(u ?? '')).toLowerCase().replace(/\.$/, '');
  if (!s) return '';
  for (const [re, v] of UNIT) if (re.test(s)) return v;
  return s;
}
const priced = (l: WLine) => (Number(l.amount) || 0) > 0 || (Number(l.unit_price) || 0) > 0;
const heading = (l: WLine) => OPTION_HEAD.test(l.description) && !priced(l);

/**
 * Each BOQ line to at most one quotation line and back: the pair sharing the largest share of the
 * BOQ line's words wins first. Half the BOQ line's words, or three words, is a match.
 * ponytail: word overlap, not meaning — "WC" and "water closet" do not match. The supplier sees the
 * unmatched line by name and answers "BOQ line 3 is my line 2" or prices it; add a synonym table
 * when a real quotation shows it is needed.
 */
export function matchBoq(boq: BoqRow[], lines: WLine[]): Map<number, number> {
  const cand: { i: number; j: number; s: number }[] = [];
  boq.forEach((b, i) => {
    const bt = toks(b.description); if (!bt.length) return;
    lines.forEach((l, j) => {
      if (heading(l)) return;
      const lt = new Set(toks(l.description));
      const shared = bt.filter((t) => lt.has(t)).length;
      const s = shared / bt.length;
      if (s >= 0.5 || shared >= 3) cand.push({ i, j, s });
    });
  });
  cand.sort((a, b) => b.s - a.s || a.i - b.i || a.j - b.j);
  const out = new Map<number, number>(); const used = new Set<number>();
  for (const c of cand) { if (out.has(c.i) || used.has(c.j)) continue; out.set(c.i, c.j); used.add(c.j); }
  return out;
}

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { heading, priced, toks };
