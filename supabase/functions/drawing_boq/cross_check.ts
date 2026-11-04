// cross_check — the MODEL reads the drawing first; code's exact count of the same text layer CROSS-CHECKS it
// (3 Nov 2026, sales_engineer; founder via the coordinator: "it should feel as if I'm attaching a drawing to you —
// you understand it"). Until today a PDF set that code counted completely was answered by code alone and the model
// never saw it (27 Oct, ledger 580), so the customer got tag counts and nothing of what the drawing is about.
//
// Now both read the same PDF at once (no added wait: the model call is the clock either way) and they are merged:
//   * a line code counted and the model also listed with the SAME quantity -> confirmed by both (cross_check.agrees);
//   * the same line with a DIFFERENT quantity -> code's count stays the quantity (it is the printed tags counted one
//     by one: on 27 Oct the model doubled EF-1/EF-2 and missed three items on the set code read 7/7), the model's figure
//     is kept beside it, and the line is marked to_confirm so the sales engineer asks the customer (boq_open_lines.ts);
//   * a line only code found -> kept, marked that the model did not list it;
//   * a line only the model found (scope code cannot count: finishes, areas, notes) -> kept as the model's ESTIMATE,
//     to_confirm, never as a read quantity.
// Nothing is gated on agreement: every disagreement is FLAGGED in the line and in missing_info.
// deno-lint-ignore-file no-explicit-any
import { linesFromRuns, type PdfPage } from '../_shared/pdf_text_positions.ts';
import { stripSeeds, titleStrip } from '../_shared/anonymise.ts';
import { drawingIdentityTerms, gateDrawingBoq } from '../_shared/drawing_identity_gate.ts';

type Line = Record<string, any>;
const tagOf = (l: Line): string | null => {
  const m = String(l.type || '').match(/^tag:([A-Z0-9][A-Z0-9/.-]*?)(?::|$)/i);
  return m ? m[1].toUpperCase() : null;
};
const text = (l: Line) => `${l.item || ''} ${l.description || ''} ${l.section || ''}`.toUpperCase();
/** The model line names this tag as a whole token (FD-1 is not FD-10; "FD1" and "FD 1" are FD-1). */
function names(tag: string, l: Line): boolean {
  const [type, n] = [tag.replace(/-?\d+[A-Z]?$/, ''), (tag.match(/(\d+[A-Z]?)$/) || [])[1]];
  if (!n) return new RegExp(`(^|[^A-Z0-9])${type}([^A-Z0-9]|$)`).test(text(l));
  return new RegExp(`(^|[^A-Z0-9])${type.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}[- ]?${n}([^0-9A-Z]|$)`).test(text(l));
}
const sameQty = (a: unknown, b: unknown) => a != null && b != null && Math.abs(Number(a) - Number(b)) < 1e-9;

export type CrossChecked = { boq: Line[]; agreed: number; disagreed: string[]; code_only: string[]; model_only: number };

/** Merge the model's draft lines with code's completely-counted set (both from the same PDF). */
export function crossCheck(modelLines: Line[], codeLines: Line[]): CrossChecked {
  const used = new Set<number>();
  const out: Line[] = [];
  const disagreed: string[] = [], codeOnly: string[] = [];
  let agreed = 0;
  for (const c of codeLines) {
    const tag = tagOf(c);
    const hits = tag ? modelLines.map((m, i) => [m, i] as const).filter(([m, i]) => !used.has(i) && names(tag, m)) : [];
    hits.forEach(([, i]) => used.add(i));
    if (!hits.length) { out.push({ ...c, cross_check: { by: 'model', model_qty: null, agrees: null } }); if (tag) codeOnly.push(tag); continue; }
    const modelQty = hits.reduce((a, [m]) => a + (Number(m.qty) || 0), 0);
    if (sameQty(modelQty, c.qty)) { agreed++; out.push({ ...c, cross_check: { by: 'model', model_qty: modelQty, agrees: true } }); continue; }
    disagreed.push(`${tag} (drawing text ${c.qty}, model ${modelQty})`);
    out.push({ ...c, qty_status: 'to_confirm', estimate: c.qty, cross_check: { by: 'model', model_qty: modelQty, agrees: false } });
  }
  let modelOnly = 0;
  modelLines.forEach((m, i) => {
    if (used.has(i)) return;
    modelOnly++;
    out.push({ ...m, ...(m.qty != null ? { qty_status: 'to_confirm', estimate: m.qty } : {}), cross_check: { by: 'code', code_qty: null, agrees: null } });
  });
  return { boq: out, agreed, disagreed, code_only: codeOnly, model_only: modelOnly };
}

/** The notes the customer and the supplier read about the cross-check (src/lib/boqNotes.ts renders them in Arabic). */
export function crossCheckNotes(x: CrossChecked): string[] {
  const notes: string[] = [];
  if (x.disagreed.length) notes.push(`The drawing reading and the count of the drawing's own tags disagree on ${x.disagreed.join('; ')}; the tag count is shown and is confirmed with the customer.`);
  if (x.code_only.length) notes.push(`Counted from the drawing's own tags but not listed by the drawing reading: ${x.code_only.join(', ')}.`);
  if (x.model_only) notes.push(`${x.model_only} line(s) come from the drawing reading alone; they are estimates and are confirmed with the customer.`);
  return notes;
}

// THE IDENTITY TERMS OF THE MERGED TAKE-OFF (3 Nov 2026, independent review of #1837). The gate was first fed the text
// the model is sent: runs space-joined per page and cut at 12,000 characters. Joined that way a label runs into the
// next one, so the terms come out as fragments; measured on zzPdfSet: "ZZ DEMO ORBIT ZZ DEMO ORBIT CONSULTING ENGINEERS
// LLC TEL +971 4 000 0017 zz.orbi" and "ZZ DEMO Rashid Kareem PROJECT: ... DR" (the drafter lost, "consulting" a seed),
// where linesFromRuns over every page - what scan_takeoff and pdf_vector_redact read - gives "ZZ DEMO Rashid Kareem",
// "ZZ DEMO Harbour Tower", "ZZ Demo Drafter", "ZZ DEMO ORBIT". The title strip's own names (the seeds drawing_set.ts
// scrubs its lines with) are added, so a party printed only in the strip is gated too - WITHOUT their label: the gate
// splits every term into words (seedTerms), and a whole strip run "drawn by zz demo drafter" made "drawn" a seed, so
// the coded basis "tag FD-1 drawn 7x on P-1.01" reached suppliers as "tag FD-1 █ 7x" (second review, same day). An
// address is left to the contact patterns, which match it whole.
const STRIP_LABEL = /^(?:client|owner|employer|customer|consultant|contractor|developer|architect|engineer|project(?: (?:name|title|location|address|no|number))?|location|site(?: address)?|address|attn|attention|contact|(?:drawn|checked|approved|designed|prepared|reviewed) by|(?:drawing|dwg|sheet|job) (?:no|number)|tel|fax|phone|mob(?:ile)?|e ?mail)\b\s*/i;
export function setIdentityTerms(pages: PdfPage[]): string[] {
  const strip = pages.flatMap((p) => { const s = titleStrip(p); return s ? stripSeeds(p, s) : []; })
    .filter((t) => !t.includes('@')).map((t) => t.replace(STRIP_LABEL, '').trim()).filter((t) => t.length >= 4);
  return [...new Set([...drawingIdentityTerms(linesFromRuns(pages)), ...strip])];
}

/** The model's normalised reading merged into code's completely-counted set, then gated. `boq: null` = answer with the
 *  code set alone: the model gave no line (its reply was prose, truncated or empty), or identity was left outside the lines. */
export function mergeReading(ai: Line, codeSet: Line, terms: string[]): { boq: Line | null; dropped_lines: number; found: string[] } {
  // A reply with no line is no reading: merging it would blank the coded set's summary and sign it with the model.
  if (!Array.isArray(ai.boq) || !ai.boq.length) return { boq: null, dropped_lines: 0, found: ['model_gave_no_line'] };
  const x = crossCheck(ai.boq, codeSet.boq || []);
  const or = (k: string) => ai[k] || codeSet[k] || '';
  const merged = { ...codeSet, ...ai, boq: x.boq,
    summary: or('summary'), drawing_type: or('drawing_type'), scale_detected: or('scale_detected'), category: or('category'),
    total_area_sqm: ai.total_area_sqm ?? codeSet.total_area_sqm ?? null,
    missing_info: [...new Set([...(codeSet.missing_info || []), ...crossCheckNotes(x), ...(ai.missing_info || [])])].slice(0, 30),
    keywords: [...new Set([...(codeSet.keywords || []), ...(ai.keywords || [])])].slice(0, 12),
    cross_check: { by: 'deterministic', agreed: x.agreed, disagreed: x.disagreed, code_only: x.code_only, model_only: x.model_only } };
  const g = gateDrawingBoq(merged, terms, false);
  return { boq: g.boq, dropped_lines: g.dropped_lines, found: g.found };
}
