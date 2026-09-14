// line_specs/options.ts — two options on one submission are two quotations.
//
// Founder, 14 Sep 2026: "if a supplier wanted to share 2 options on his quote, they will be considered
// two different quotations, they cant be merged in one. so each will have its own ID in the system."
//
// A submission is split when its lines carry an option heading ("Option 1", "Option B", "Alternative
// 2", "الخيار 2", "البديل الثاني") or an explicit `option` key set by the document reader. Lines above
// the first heading are common to every option and are carried into each; the commercial terms
// (lead time, validity, payment, warranty, exclusions) are the submission's and are copied onto each
// option by the caller. A total stated for an option wins over the sum of its lines. Deterministic:
// no heading, no split.
export const OPTION_HEAD = /^\s*(?:(?:option|alternative|alt\.?|choice|offer)\s*(?:no\.?|#)?\s*(\d{1,2}|[a-e]\b|one|two|three|four|five)|(?:البديل|الخيار|العرض البديل|خيار|بديل)\s*(?:رقم\s*)?([0-9٠-٩]{1,2}|الأول|الاول|الثاني|الثالث|الرابع|أ|ب|ج|د)?)\s*[:\-–.)]?/i;

const WORD: Record<string, number> = { one: 1, two: 2, three: 3, four: 4, five: 5, 'الأول': 1, 'الاول': 1, 'الثاني': 2, 'الثالث': 3, 'الرابع': 4, 'أ': 1, 'ب': 2, 'ج': 3, 'د': 4 };
export function optionNumber(heading: string, fallback: number): number {
  const m = String(heading || '').match(OPTION_HEAD);
  const g = (m && (m[1] || m[2])) || '';
  const d = g.replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x660));
  if (/^\d+$/.test(d)) return Number(d);
  if (/^[a-e]$/i.test(d)) return d.toLowerCase().charCodeAt(0) - 96;
  return WORD[d.toLowerCase()] ?? WORD[d] ?? fallback;
}

export type OptionLine = { description: string; amount?: number | null; unit_price?: number | null; option?: string | number | null; [k: string]: unknown };
export type SplitOption<L> = { option_no: number; heading: string | null; lines: L[]; total: number | null };

const isHeading = (l: OptionLine) => OPTION_HEAD.test(String(l.description || '')) && !(Number(l.amount) > 0) && !(Number(l.unit_price) > 0);

/** Split lines into options. One option (option_no 1, every line) when nothing marks a second. */
export function splitOptions<L extends OptionLine>(lines: L[], totals: Record<string, number> = {}): SplitOption<L>[] {
  const keyed = lines.some((l) => l.option != null && String(l.option) !== '');
  const heads = lines.filter(isHeading);
  if (!keyed && heads.length < 2) return [{ option_no: 1, heading: null, lines: lines.filter((l) => !isHeading(l)), total: null }];
  const shared: L[] = [];
  const byNo = new Map<number, SplitOption<L>>();
  let cur: SplitOption<L> | null = null;
  for (const l of lines) {
    if (keyed) {
      if (l.option == null || String(l.option) === '') { shared.push(l); continue; }
      const n = /^\d+$/.test(String(l.option)) ? Number(l.option) : optionNumber('option ' + String(l.option), byNo.size + 1);
      if (!byNo.has(n)) byNo.set(n, { option_no: n, heading: 'Option ' + n, lines: [], total: null });
      if (!isHeading(l)) byNo.get(n)!.lines.push(l);
      continue;
    }
    if (isHeading(l)) {
      const n = optionNumber(l.description, byNo.size + 1);
      cur = byNo.get(n) ?? { option_no: n, heading: String(l.description).trim().slice(0, 60), lines: [], total: null };
      byNo.set(n, cur); continue;
    }
    (cur ? cur.lines : shared).push(l);
  }
  const out = [...byNo.values()].sort((a, b) => a.option_no - b.option_no);
  for (const o of out) {
    o.lines = [...shared, ...o.lines];
    const t = totals[String(o.option_no)];
    o.total = typeof t === 'number' && t > 0 ? t : null;
  }
  return out.length ? out : [{ option_no: 1, heading: null, lines, total: null }];
}

/** The amount of one option: its stated total, else the sum of its priced lines, else null. */
export function optionAmount(o: SplitOption<OptionLine>): number | null {
  if (o.total && o.total > 0) return o.total;
  const s = o.lines.reduce((acc, l) => acc + (Number(l.amount) > 0 ? Number(l.amount) : 0), 0);
  return s > 0 ? Math.round(s * 100) / 100 : null;
}

export const optionLabel = (n: number, lang: 'en' | 'ar') => (lang === 'ar' ? `الخيار ${n}` : `Option ${n}`);
