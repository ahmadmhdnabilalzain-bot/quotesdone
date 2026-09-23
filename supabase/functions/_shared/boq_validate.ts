// boq_validate — the structural checks a quantity surveyor runs on a BOQ before it is priced, in code (23 Sep 2026).
//
// WHY. Founder instruction 64: OpenConstructionERP is the minimum bar for reading documents, and its
// `validation` module checks every BOQ for missing quantities, duplicate items and impossible values
// before the estimate is used. Our readers (doc_read, drawing_boq) produced lines and nobody checked
// the SET: a zip holding a sheet and its PDF could state "Floor tiling 120 sqm" and "Floor tiling
// 95 sqm", and both reached the supplier with no word that they disagree.
//
// HOW IT DECIDES (rule 890: reasoning, never keyword matching). Each check is a property of the
// numbers and units themselves, not of what the words mean:
//   missing_qty    qty is null: the line exists but states no amount.
//   bad_qty        qty is not a finite number above zero; nobody prices -3 sqm or NaN.
//   unknown_unit   the unit is not one whose physical dimension we know, so the line cannot be
//                  compared or converted (the table below is a units table, not a meaning table).
//   conflict       the SAME item (same section, same normalised description) is stated twice with
//                  amounts that disagree once converted to one unit, or in units of different
//                  dimensions (a length and an area). Exact repeats are deduplicated upstream, so a
//                  repeat that survives to here is a disagreement.
//
// WHAT IT NEVER DOES. It changes no line and drops no line; the findings travel beside the BOQ and
// each becomes one missing_info sentence, so the customer and the supplier see the doubt. It reads
// no price (none reaches it: boq_from_document strips them).

export type Dim = 'length' | 'area' | 'volume' | 'count' | 'mass' | 'lump';
// unit (lower-case, spaces and dots removed) -> [dimension, factor to that dimension's SI base]
const UNITS: Record<string, [Dim, number]> = {
  m: ['length', 1], lm: ['length', 1], rm: ['length', 1], mm: ['length', 0.001], cm: ['length', 0.01], km: ['length', 1000],
  ft: ['length', 0.3048], lf: ['length', 0.3048], 'م': ['length', 1], 'مط': ['length', 1],
  sqm: ['area', 1], m2: ['area', 1], 'm²': ['area', 1], sm: ['area', 1], sqft: ['area', 0.09290304], sf: ['area', 0.09290304],
  ft2: ['area', 0.09290304], 'م2': ['area', 1], 'م²': ['area', 1],
  cum: ['volume', 1], m3: ['volume', 1], 'm³': ['volume', 1], cbm: ['volume', 1], l: ['volume', 0.001], ltr: ['volume', 0.001],
  litre: ['volume', 0.001], 'م3': ['volume', 1], 'م³': ['volume', 1],
  nos: ['count', 1], no: ['count', 1], nr: ['count', 1], pcs: ['count', 1], pc: ['count', 1], ea: ['count', 1], each: ['count', 1],
  set: ['count', 1], sets: ['count', 1], unit: ['count', 1], units: ['count', 1], 'عدد': ['count', 1],
  kg: ['mass', 1], t: ['mass', 1000], ton: ['mass', 1000], tonne: ['mass', 1000], tons: ['mass', 1000], 'كغ': ['mass', 1], 'طن': ['mass', 1000],
  lot: ['lump', 1], ls: ['lump', 1], item: ['lump', 1], sum: ['lump', 1],
};
export const unitOf = (u: string): [Dim, number] | null => UNITS[String(u || '').toLowerCase().replace(/[\s.]+/g, '')] ?? null;

export type Line = { section?: string; description: string; qty: number | null; unit: string };
export type Finding = { check: 'missing_qty' | 'bad_qty' | 'unknown_unit' | 'conflict'; lines: number[]; say: string };

const norm = (s: string) => String(s || '').toLowerCase().replace(/\s+/g, ' ').trim();
const fmt = (n: number) => String(Math.round(n * 1000) / 1000);

export function validateBoq(lines: Line[]): Finding[] {
  const out: Finding[] = [];
  const groups = new Map<string, number[]>();
  lines.forEach((l, i) => {
    const d = String(l.description || '').slice(0, 80);
    if (l.qty == null) out.push({ check: 'missing_qty', lines: [i], say: `"${d}" states no quantity.` });
    else if (typeof l.qty !== 'number' || !Number.isFinite(l.qty) || l.qty <= 0) out.push({ check: 'bad_qty', lines: [i], say: `"${d}" states a quantity of ${l.qty}, which cannot be priced.` });
    if (l.unit && !unitOf(l.unit)) out.push({ check: 'unknown_unit', lines: [i], say: `"${d}" is measured in "${String(l.unit).slice(0, 20)}", a unit we cannot compare or convert.` });
    if (norm(l.description)) { const k = `${norm(l.section || '')}|${norm(l.description)}`; groups.set(k, [...(groups.get(k) || []), i]); }
  });
  for (const idx of groups.values()) {
    if (idx.length < 2) continue;
    const known = idx.map((i) => ({ u: unitOf(lines[i].unit), q: lines[i].qty })).filter((x) => x.u);
    const d = String(lines[idx[0]].description).slice(0, 80);
    if (new Set(known.map((x) => x.u![0])).size > 1) {
      out.push({ check: 'conflict', lines: idx, say: `"${d}" is stated ${idx.length} times in different kinds of unit (${[...new Set(idx.map((i) => lines[i].unit))].join(', ')}).` });
      continue;
    }
    const base = known.filter((x) => typeof x.q === 'number' && Number.isFinite(x.q) && x.q > 0).map((x) => (x.q as number) * x.u![1]);
    // Two amounts agree within 0.5%: a rounding difference between two exports of one sheet.
    if (base.length > 1 && Math.max(...base) - Math.min(...base) > 0.005 * Math.max(...base)) {
      out.push({ check: 'conflict', lines: idx, say: `"${d}" is stated ${idx.length} times with different quantities (${idx.map((i) => `${fmt(Number(lines[i].qty))} ${lines[i].unit}`).join(', ')}); the supplier should price the one the drawings support.` });
    }
  }
  return out;
}
