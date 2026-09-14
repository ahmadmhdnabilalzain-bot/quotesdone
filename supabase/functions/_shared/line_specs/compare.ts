// line_specs/compare.ts — the line-by-line technical comparison the report renders.
//
// The founder, 14 Sep 2026: "the comparison report need to be more detailed technically. its not a
// matter of delivery time only or installation". This builds, for each line of the customer's
// request, every quote's value for every specification attribute of that line — the trade's
// standard ones and every component the customer named in the intake — plus the three quote-level
// terms (delivery, installation, warranty), each flagged against what the customer asked for:
// ✓ matches, ≠ differs, — missing. The baseline is the customer's intake answers
// (inquiries.spec.customer_requirements, docs/contracts/intake_answers.md): a warranty shorter than the
// customer's minimum is ≠, never ✓; "no preference" matches any stated value; "other" (the customer's
// own words) is shown beside the supplier's value and never auto-flagged. The exact shape is the
// contract in docs/contracts/technical_comparison.md.
//
// Held quotes never appear here (they are drafts and never reach the comparison); the report is
// told only how many are on hold. Pure: no I/O.
import { assessQuote, componentAttr, componentOnLine, customerAnswer, customerRequires, lineDefs, MATERIAL_ATTRS, readDelivery, requestedValue, type Line, type Requirements, type Terms } from './assess.ts';
import { attrsForLine, normText, TRADES, tradeOfCategory, tradeOfLine, type Attr } from './model.ts';
import { maskIdentityNumbers } from '../identity_numbers.ts';

export type Flag = 'match' | 'differs' | 'missing' | 'stated' | 'not_applicable';
export const MARKER: Record<Flag, string> = { match: '✓', differs: '≠', missing: '—', stated: '', not_applicable: 'n/a' };

export type CmpQuote = { quote_id: string; label_en: string; label_ar: string; supplier_letter: string; option_no: number; lines: Line[]; terms: Terms };
// Values shown to the customer never carry a TRN or licence number (identity_numbers.ts), and no VAT
// figure is part of this dataset at all: price_ex_vat is the only price.
const safe = (v: string | null) => (v == null ? null : maskIdentityNumbers(v).replace(/\s{2,}/g, ' ').trim() || null);
export type RequestLine = { line_no: number; description: string; qty?: number | string | null; unit?: string | null };
export type Cell = { quote_id: string; value: string | null; source: 'extracted' | 'supplier_portal' | null; quote_line_no: number | null; flag: Flag; marker: string };
export type ReqSource = 'boq' | 'intake' | 'intake_other' | 'no_preference';
export type AttrRow = { code: string; label_en: string; label_ar: string; unit: string | null; unit_ar: string | null; mandatory: boolean; requested: string | null; requested_source: ReqSource | null; cells: Cell[] };
export type LineRow = { row: number; item: string; request_line: RequestLine | null; trade: string | null; trade_en: string | null; trade_ar: string | null; attributes: AttrRow[] };
export type TermCell = { quote_id: string; applies: boolean; value: string | null; flag: Flag; marker: string };
export type TermRow = { code: 'delivery' | 'installation' | 'warranty'; label_en: string; label_ar: string; requested: string | null; requested_source: 'intake' | 'no_preference' | null; cells: TermCell[] };
export type TechnicalComparison = {
  contract: 'technical_comparison'; version: 1; generated_at: string; trade: string; on_hold: number;
  quotes: { quote_id: string; label_en: string; label_ar: string; supplier_letter: string; option_no: number; price_ex_vat: number | null }[];
  lines: LineRow[]; terms: TermRow[]; legend: Record<Flag, string>;
};

const tokens = (s: string) => new Set(normText(s).toLowerCase().replace(/[^\p{L}\p{N} ]+/gu, ' ').split(' ').filter((w) => w.length > 2));
function similarity(a: string, b: string): number {
  const A = tokens(a), B = tokens(b); if (!A.size || !B.size) return 0;
  let n = 0; for (const w of A) if (B.has(w)) n++;
  return n / (A.size + B.size - n);
}
const firstNum = (s: string) => { const m = normText(s).match(/(\d+(?:\.\d+)?)/); return m ? Number(m[1]) : null; };
const canon = (s: string) => normText(s).toLowerCase().replace(/[^\p{L}\p{N}.]+/gu, '');
export function sameValue(a: string, b: string): boolean {
  const x = firstNum(a), y = firstNum(b);
  if (x != null && y != null) return Math.abs(x - y) <= Math.max(0.001, 0.01 * Math.max(Math.abs(x), Math.abs(y)));
  const p = canon(a), q = canon(b);
  return !!p && !!q && (p === q || p.includes(q) || q.includes(p));
}
function flagOf(applies: boolean, value: string | null, requested: string | null, noPref: boolean, same = sameValue): Flag {
  if (!applies) return 'not_applicable';
  if (!value) return 'missing';
  if (noPref) return 'match';
  if (!requested) return 'stated';
  return same(value, requested) ? 'match' : 'differs';
}
const cellOf = (quote_id: string, applies: boolean, value: string | null, requested: string | null, noPref: boolean, extra: Partial<Cell> = {}): Cell => {
  const flag = flagOf(applies, value, requested, noPref);
  return { quote_id, value: safe(value), source: null, quote_line_no: null, flag, marker: MARKER[flag], ...extra };
};

/**
 * The customer's own values per attribute for one row: from its BOQ wording (only when the row IS a
 * request line — a quote's own values are never its own baseline, or every quote would "match the
 * request" by construction), then from the intake's component answers.
 */
function requestedFor(rl: RequestLine, trade: string | null, attrs: Attr[], req: Requirements, fromRequest: boolean) {
  const out: Record<string, { value: string; source: ReqSource }> = {};
  if (fromRequest) for (const a of attrs) { const v = a.find(rl.description); if (v) out[a.code] = { value: v, source: 'boq' }; }
  const base = trade ? attrsForLine(trade, rl.description) : [];
  for (const m of req?.materials ?? []) {
    if (!m?.component || (m.component !== 'main' && !componentOnLine(m, rl.description))) continue;
    const a = componentAttr(m, trade, base);
    if (/^no[_\s-]?preference$/i.test(String(m.choice ?? ''))) { out[a.code] = { value: 'no_preference', source: 'no_preference' }; continue; }
    const v = requestedValue(m);
    if (v) out[a.code] = { value: v, source: m.choice === 'other' ? 'intake_other' : 'intake' };
  }
  return out;
}

export function technicalComparison(input: { category: string | null; request_lines: RequestLine[]; requirements: Requirements; quotes: CmpQuote[]; on_hold: number; now: Date }): TechnicalComparison {
  const trade = tradeOfCategory(input.category);
  const req = input.requirements ?? null;
  const assessed = input.quotes.map((q) => ({ q, a: assessQuote({ category: input.category, lines: q.lines, terms: q.terms, requirements: req }) }));

  // The backbone: the customer's request lines; with no BOQ, the lines of the most itemised quote.
  let backbone: RequestLine[] = input.request_lines.filter((r) => r && String(r.description || '').trim());
  const fromRequest = backbone.length > 0;
  if (!backbone.length) {
    const richest = assessed.slice().sort((x, y) => y.a.lines.filter((l) => l.material).length - x.a.lines.filter((l) => l.material).length)[0];
    backbone = richest ? richest.a.lines.filter((l) => l.material).map((l) => ({ line_no: l.line_no, description: l.description })) : [];
  }

  // Each quote line joins the backbone line it most resembles (once); anything left is its own row.
  const rows: { rl: RequestLine | null; picks: Map<string, number> }[] = backbone.map((rl) => ({ rl, picks: new Map() }));
  for (const { q, a } of assessed) {
    const used = new Set<number>();
    for (const r of rows) {
      if (!r.rl) continue;
      let best = -1, score = 0;
      for (const l of a.lines) { if (!l.material || used.has(l.line_no)) continue; const s = similarity(r.rl.description, l.description); if (s > score) { score = s; best = l.line_no; } }
      if (best >= 0 && score >= 0.2) { r.picks.set(q.quote_id, best); used.add(best); }
    }
    for (const l of a.lines) if (l.material && !used.has(l.line_no)) rows.push({ rl: null, picks: new Map([[q.quote_id, l.line_no]]) });
  }

  const lines: LineRow[] = rows.map((r, i) => {
    const firstPick = [...r.picks.entries()][0];
    const pickedLine = firstPick ? assessed.find((x) => x.q.quote_id === firstPick[0])!.a.lines.find((l) => l.line_no === firstPick[1]) : undefined;
    const text = r.rl?.description ?? pickedLine?.description ?? '';
    const lt = tradeOfLine(trade, text) ?? pickedLine?.trade ?? null;
    // The row's attributes: what this line is asked for (trade standard + the customer's components),
    // then the trade's remaining attributes so a stated extra still has a row to appear in.
    const defs = lineDefs(lt, text, req);
    const replaced = defs.some((d) => d.code.startsWith('component_'));
    const attrs: Attr[] = [...defs, ...(lt ? TRADES[lt].attrs.filter((a) => !defs.some((d) => d.code === a.code) && !(replaced && MATERIAL_ATTRS.includes(a.code))) : [])];
    const requested = r.rl ? requestedFor(r.rl, lt, attrs, req, fromRequest) : {};
    const attributes: AttrRow[] = attrs.map((a) => {
      const rq = requested[a.code];
      const noPref = rq?.source === 'no_preference';
      const baseline = rq && rq.source !== 'no_preference' && rq.source !== 'intake_other' ? rq.value : null;
      const cells = assessed.map(({ q, a: qa }) => {
        const ln = r.picks.get(q.quote_id);
        const l = ln != null ? qa.lines.find((x) => x.line_no === ln) : undefined;
        // MEASURED 14 Sep 2026, both live e2e comparisons: all 20 "missing" cells were a quote with NO
        // line on the row (another supplier's own item), and the report told the customer "not stated —
        // ask for it". A quote that does not include an item is not missing a detail of it: not_applicable.
        if (!l) return cellOf(q.quote_id, false, null, baseline, noPref);
        // On a line the quote does include, a detail is owed only when it is MANDATORY for that line; a
        // mandatory one left unstated holds the quote (assess.ts, rankable), so a compared quote never
        // carries one. An optional detail the supplier did not state is not_applicable, not "missing".
        const owed = l.defs.some((d) => d.code === a.code && d.mandatory);
        return cellOf(q.quote_id, owed || !!l.spec[a.code], l.spec[a.code] ?? null, baseline, noPref, { source: l.source[a.code] ?? null, quote_line_no: ln });
      });
      return { code: a.code, label_en: a.en, label_ar: a.ar, unit: a.unit ?? null, unit_ar: a.unit_ar ?? null, mandatory: defs.some((d) => d.code === a.code && d.mandatory), requested: rq && !noPref ? rq.value : null, requested_source: rq?.source ?? null, cells };
    }).filter((row) => row.mandatory || row.requested || row.requested_source || row.cells.some((c) => c.value));
    return { row: i + 1, item: safe(text) ?? '', request_line: fromRequest ? r.rl : null, trade: lt, trade_en: lt ? TRADES[lt].en : null, trade_ar: lt ? TRADES[lt].ar : null, attributes };
  });

  // Quote-level terms, against the customer's intake answers.
  const rb = req?.required_by;
  const dBy = rb && !rb.flexible && rb.date ? new Date(rb.date) : null;
  const dByOk = dBy && !isNaN(dBy.getTime()) ? dBy : null;
  const deliveryRow: TermRow = { code: 'delivery', label_en: 'Delivery / lead time', label_ar: 'التسليم / مدة التنفيذ', requested: dByOk ? String(rb!.date) : null, requested_source: dByOk ? 'intake' : null,
    cells: assessed.map(({ q, a }) => {
      const t = a.terms.delivery; let flag: Flag = t.value ? 'stated' : 'missing';
      if (t.value && dByOk) {
        const due = t.date ? new Date(t.date) : (t.days != null ? new Date(input.now.getTime() + t.days * 864e5) : null);
        flag = due && !isNaN(due.getTime()) ? (due.getTime() <= dByOk.getTime() + 864e5 ? 'match' : 'differs') : 'stated';
      }
      return { quote_id: q.quote_id, applies: true, value: safe(t.value), flag, marker: MARKER[flag] };
    }) };
  const instWant = customerAnswer(req, 'installation');
  const installationRow: TermRow = { code: 'installation', label_en: 'Installation', label_ar: 'التركيب', requested: instWant === 'yes' ? 'required' : instWant === 'no' ? 'not_required' : null, requested_source: instWant ? 'intake' : null,
    cells: assessed.map(({ q, a }) => {
      const t = a.terms.installation; const applies = customerRequires(req, 'installation');
      const value = t.included ? (t.included === 'yes' ? `Included${t.detail ? ' — ' + t.detail : ''}` : 'Not included (supply only)') : null;
      const flag: Flag = !applies ? 'not_applicable' : !t.included ? 'missing' : instWant ? (t.included === instWant ? 'match' : 'differs') : 'stated';
      return { quote_id: q.quote_id, applies, value: safe(value), flag, marker: MARKER[flag] };
    }) };
  const wWant = customerAnswer(req, 'warranty');
  const minM = Number(req?.warranty?.min_months) > 0 ? Number(req!.warranty!.min_months) : null;
  const warrantyRow: TermRow = { code: 'warranty', label_en: 'Warranty', label_ar: 'الضمان', requested: minM ? `${minM} months minimum` : (wWant === 'yes' ? 'required' : wWant === 'no' ? 'not_required' : null), requested_source: minM || wWant ? 'intake' : null,
    cells: assessed.map(({ q, a }) => {
      const t = a.terms.warranty; const applies = customerRequires(req, 'warranty');
      const value = t.period ? `${t.period}${t.coverage ? ' — ' + t.coverage : ''}` : null;
      // A warranty below the customer's minimum is ≠ — never ✓ (founder, 14 Sep 2026).
      const flag: Flag = !applies ? 'not_applicable' : !value ? 'missing' : minM != null && t.months != null ? (t.months >= minM ? 'match' : 'differs') : wWant === 'yes' && minM == null ? 'match' : 'stated';
      return { quote_id: q.quote_id, applies, value: safe(value), flag, marker: MARKER[flag] };
    }) };

  return {
    contract: 'technical_comparison', version: 1, generated_at: input.now.toISOString(), trade, on_hold: input.on_hold,
    quotes: input.quotes.map(({ quote_id, label_en, label_ar, supplier_letter, option_no, terms }) => ({ quote_id, label_en, label_ar, supplier_letter, option_no, price_ex_vat: Number(terms.price_ex_vat) > 0 ? Number(terms.price_ex_vat) : null })),
    lines, terms: [deliveryRow, installationRow, warrantyRow], legend: MARKER,
  };
}

// ---------------------------------------------------------------------------------------------
// THE RENDERER'S VIEW. The comparison-report PDF (PR #611, _shared/quote_documents.ts) reads
// `analysis.technical` as its own TechnicalComparison: supplier labels as columns, each attribute's
// values keyed by label, flags match | differs | missing | na, and the three terms under lead_time /
// installation / warranty. This produces exactly that from the full dataset, so the renderer needs
// no change; the full dataset is served beside it as `analysis.technical_detail`.
//   stated (a value, no baseline) → 'match': the value is stated and the quote passed the gate.
//   not_applicable → 'na'.
// ---------------------------------------------------------------------------------------------
export type RenderFlag = 'match' | 'differs' | 'missing' | 'na';
export type RenderCell = { value?: string | null; flag: RenderFlag; note?: string | null };
export type RendererTechnical = {
  suppliers: string[];
  lines: { line_no?: number | null; item: string; qty?: string | number | null; unit?: string | null;
    attributes: { key: string; label?: string | null; unit?: string | null; requested?: string | null; values: Record<string, RenderCell> }[] }[];
  terms?: { lead_time?: RenderTerm | null; installation?: RenderTerm | null; warranty?: RenderTerm | null } | null;
};
type RenderTerm = { applicable?: boolean | null; requested?: string | null; values: Record<string, RenderCell> };
const rflag = (f: Flag): RenderFlag => (f === 'not_applicable' ? 'na' : f === 'stated' ? 'match' : f);

export function rendererView(t: TechnicalComparison, lang: 'en' | 'ar'): RendererTechnical {
  const ar = lang === 'ar';
  const labelOf = new Map(t.quotes.map((q) => [q.quote_id, q.label_en]));
  const values = (cells: { quote_id: string; value: string | null; flag: Flag }[]) =>
    Object.fromEntries(cells.map((c) => [labelOf.get(c.quote_id)!, { value: c.value, flag: rflag(c.flag) }]));
  const term = (code: TermRow['code']): RenderTerm | null => {
    const r = t.terms.find((x) => x.code === code); if (!r) return null;
    return { applicable: r.cells.some((c) => c.applies), requested: r.requested, values: values(r.cells) };
  };
  return {
    suppliers: t.quotes.map((q) => q.label_en),
    lines: t.lines.map((l) => ({
      line_no: l.request_line?.line_no ?? null, item: l.item, qty: l.request_line?.qty ?? null, unit: l.request_line?.unit ?? null,
      attributes: l.attributes.map((a) => ({ key: a.code, label: ar ? a.label_ar : a.label_en, unit: a.unit ? (ar ? a.unit_ar ?? a.unit : a.unit) : null, requested: a.requested, values: values(a.cells) })),
    })),
    terms: { lead_time: term('delivery'), installation: term('installation'), warranty: term('warranty') },
  };
}

/**
 * THE RANKING TAKES ONLY COMPLETE QUOTES (14 Sep 2026). A held quote is a draft and never reaches the
 * comparison, but the ranking must not rest on a status column alone: the PDF redesign's fit-out
 * sample shortlisted a supplier at #3 whose own data said "material spec not stated". Every quote
 * offered to the ranking is assessed again here with the same gate; one that would be held is
 * removed and only counted.
 */
export function rankable<Q extends { lines: Line[]; terms: Terms }>(quotes: Q[], category: string | null, requirements: Requirements): { rankable: Q[]; held: number } {
  const out: Q[] = []; let held = 0;
  for (const q of quotes) { if (assessQuote({ category, lines: q.lines, terms: q.terms, requirements }).held) held++; else out.push(q); }
  return { rankable: out, held };
}

export { readDelivery };
