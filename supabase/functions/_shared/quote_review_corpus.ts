// quote_review_corpus.ts — MEASURES the generaliser and the review notes on the 24-trade corpus, before and after.
// Seat: sales_engineer. 10 Nov 2026, founder ledger 1588-1590. Pure: no I/O, no model, no clock (the corpus's NOW).
//
// BEFORE is what the customer was shown until this change, reproduced with the code that did it:
//   * every stored line passed supplier_api's save scrub (identity_scrub.ts scrubLine: contact shapes and the supplier's
//     own name) and was then served as stored — brand and model columns raw on the quotation PDF and in quote_compare's
//     tables, the free text raw in my_inquiries;
//   * the only deviations the customer saw were the technical table's term rows (line_specs/compare.ts): a lead time
//     after the required date, a warranty under the minimum, installation not included. Nothing compared origin, grade,
//     quantity or missing / excluded scope (deterministic.ts: "missing_from_request: [], spec_deviation: []").
// AFTER is what each surface now serves: generaliseLine / generaliseQuoteTerms on every line and term, generaliseDeep
// on the technical table, and the sales engineer's notes (quote_review_notes.ts).
//   leaks        a planted identifier (brand, model, product line, the supplier's name, phone, e-mail) still readable
//   caught       planted deviations a note (after) or a differing term row (before) reports, on the planted line
//   false flags  a deviation note on the CONTROL quote, which answers the request exactly
//   over-redacted a specification token of the control (SS316, 600x600, IP65 ...) the customer no longer reads
import { CORPUS, NOW, specOf, type CorpusTrade } from './quote_review.fixture.ts';
import { DEVIATION_CODES, reviewNotes, type ReviewNote } from './quote_review_notes.ts';
import { ctxOfQuote, generaliseDeep, generaliseLine, generaliseQuoteTerms } from './quote_generalise.ts';
import { scrubIdentity, scrubLine } from '../supplier_api/identity_scrub.ts';
import { technicalComparison } from './line_specs/compare.ts';
import { requirementsOf, type Line } from './line_specs/assess.ts';
import type { QuoteIn, QuoteLineIn } from './quote_review_notes.ts';

export type Side = { leaks: number; ids: number; leaked: string[] };
export type TradeResult = {
  code: string; group: string;
  before: { deviant: Side; control: Side; caught: number; false_flags: number };
  after: { deviant: Side; control: Side; caught: number; false_flags: number; over_redacted: string[]; missed: string[]; extra: string[]; notes: ReviewNote[] };
  planted: number;
};

const S = (v: unknown) => String(v ?? '');
const TEXT = ['description', 'brand', 'model', 'specification', 'notes', 'country_of_origin'] as const;
const TERMS = ['lead_time', 'validity', 'warranty', 'payment_terms', 'scope', 'conditions', 'exclusions', 'notes'] as const;
// deno-lint-ignore no-explicit-any
const strings = (v: any, out: string[] = []): string[] => { if (typeof v === 'string') out.push(v); else if (Array.isArray(v)) v.forEach((x) => strings(x, out)); else if (v && typeof v === 'object') Object.values(v).forEach((x) => strings(x, out)); return out; };
const found = (text: string, ids: string[]) => ids.filter((id) => text.toLowerCase().includes(id.toLowerCase()));

/** The stored rows: what supplier_api's save scrub left (the state both BEFORE and AFTER start from). */
function stored(t: CorpusTrade, lines: QuoteLineIn[], quote: QuoteIn) {
  const hits: string[] = [];
  const ls = lines.map((l) => scrubLine(l as Record<string, unknown>, t.supplier, hits) as QuoteLineIn);
  const q: Record<string, unknown> = { ...quote };
  for (const k of TERMS) if (typeof q[k] === 'string') q[k] = scrubIdentity(q[k] as string, t.supplier, hits);
  return { lines: ls, quote: q as QuoteIn };
}
function table(t: CorpusTrade, quotes: { id: string; lines: QuoteLineIn[]; quote: QuoteIn }[]) {
  return technicalComparison({ category: t.code, request_lines: t.request.map((r, i) => ({ line_no: i + 1, description: S(r.description), qty: r.qty ?? null, unit: r.unit ?? null })),
    requirements: requirementsOf(specOf(t)), on_hold: 0, now: NOW,
    quotes: quotes.map((x, i) => ({ quote_id: x.id, label_en: 'Supplier ' + 'AB'[i], label_ar: 'المورّد ' + 'AB'[i], supplier_letter: 'AB'[i], option_no: 1,
      lines: x.lines.map((l) => ({ ...l, line_no: Number(l.line_no), description: S(l.description) }) as Line),
      terms: { lead_time: x.quote.lead_time, warranty: x.quote.warranty, scope: x.quote.scope, exclusions: x.quote.exclusions, conditions: x.quote.conditions, notes: x.quote.notes, terms_spec: null, price_ex_vat: 1 } })) });
}

export function measureTrade(t: CorpusTrade): TradeResult {
  const request = { lines: t.request.map((r, i) => ({ ...r, line_no: i + 1 })), spec: specOf(t), summary: t.summary, now: NOW };
  const ctl = stored(t, t.control.lines, t.control.quote), dev = stored(t, t.deviant.lines, t.deviant.quote);
  const tech = table(t, [{ id: 'ctl', ...ctl }, { id: 'dev', ...dev }]);
  // ---- BEFORE: the stored words as served, and the term rows the table already flagged
  const beforeText = (x: typeof ctl) => [...x.lines.flatMap((l) => TEXT.map((k) => S((l as Record<string, unknown>)[k]))), ...TERMS.map((k) => S((x.quote as Record<string, unknown>)[k])), ...strings(tech)].join('\n');
  const termFlag = (code: string, qid: string) => tech.terms.find((r) => r.code === code)?.cells.find((c) => c.quote_id === qid)?.flag === 'differs';
  const beforeCaught = t.deviant.planted.filter((p) => (p.code === 'lead_time_late' && termFlag('delivery', 'dev')) || (p.code === 'warranty_short' && termFlag('warranty', 'dev'))
    || (p.code === 'scope_excluded' && p.line_no == null && termFlag('installation', 'dev'))).length;
  const beforeFalse = ['delivery', 'warranty', 'installation'].filter((c) => termFlag(c, 'ctl')).length;
  // ---- AFTER: every surface's generalisation, and the notes
  const afterSide = (x: typeof ctl) => {
    const ctx = ctxOfQuote(x.lines, [t.supplier]);
    const ls = x.lines.map((l) => generaliseLine(l as Record<string, unknown>, ctx));
    const q = generaliseQuoteTerms(x.quote as Record<string, unknown>, ctx);
    return { ctx, text: [...ls.flatMap((l) => TEXT.map((k) => S(l[k]))), ...TERMS.map((k) => S(q[k]))].join('\n') };
  };
  const aCtl = afterSide(ctl), aDev = afterSide(dev);
  const techAfter = strings(generaliseDeep(tech, { supplierNames: [t.supplier], brands: [...(aCtl.ctx.brands || []), ...(aDev.ctx.brands || [])], models: [...(aCtl.ctx.models || []), ...(aDev.ctx.models || [])] })).join('\n');
  const notesDev = reviewNotes({ request, quote: dev.quote, lines: dev.lines, supplierNames: [t.supplier] });
  const notesCtl = reviewNotes({ request, quote: ctl.quote, lines: ctl.lines, supplierNames: [t.supplier] });
  const noteText = (ns: ReviewNote[]) => ns.flatMap((n) => [n.en, n.ar]).join('\n');
  const afterDevText = [aDev.text, techAfter, noteText(notesDev)].join('\n'), afterCtlText = [aCtl.text, techAfter, noteText(notesCtl)].join('\n');
  const hit = (p: { code: string; line_no: number | null }) => notesDev.some((n) => n.code === p.code && (n.line_no ?? null) === (p.line_no ?? null));
  const missed = t.deviant.planted.filter((p) => !hit(p)).map((p) => `${p.code}@${p.line_no ?? 'quote'}`);
  const extra = notesDev.filter((n) => DEVIATION_CODES.has(n.code) && !t.deviant.planted.some((p) => p.code === n.code && (p.line_no ?? null) === (n.line_no ?? null))).map((n) => `${n.code}@${n.line_no ?? 'quote'}`);
  const falseCtl = notesCtl.filter((n) => DEVIATION_CODES.has(n.code));
  const side = (text: string, ids: string[]): Side => { const leaked = found(text, ids); return { leaks: leaked.length, ids: ids.length, leaked }; };
  return {
    code: t.code, group: t.group, planted: t.deviant.planted.length,
    before: { deviant: side(beforeText(dev), t.deviant.ids), control: side(beforeText(ctl), t.control.ids), caught: beforeCaught, false_flags: beforeFalse },
    after: { deviant: side(afterDevText, t.deviant.ids), control: side(afterCtlText, t.control.ids), caught: t.deviant.planted.length - missed.length,
      false_flags: falseCtl.length, over_redacted: t.control.keep.filter((k) => !aCtl.text.includes(k)), missed, extra: [...extra, ...falseCtl.map((n) => `CONTROL ${n.code}@${n.line_no ?? 'quote'}: ${n.en}`)], notes: notesDev },
  };
}

export function measureCorpus(corpus: CorpusTrade[] = CORPUS): TradeResult[] { return corpus.map(measureTrade); }
