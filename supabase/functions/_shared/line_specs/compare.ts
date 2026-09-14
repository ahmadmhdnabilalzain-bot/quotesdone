// line_specs/compare.ts — the line-by-line technical comparison the report renders.
//
// The founder, 14 Sep 2026: "the comparison report need to be more detailed technically. its not a
// matter of delivery time only or installation". This builds, for each line of the customer's
// request, every quote's value for every specification attribute of that line's trade, plus the
// three quote-level terms (delivery, installation, warranty), each flagged against what the customer
// asked for: ✓ matches, ≠ differs, — missing. The exact shape is the contract in
// docs/contracts/technical_comparison.md; the PDF is drawn by another seat's code from this data.
//
// Held quotes never appear here (they are drafts and never reach the comparison); the report is
// told only how many are on hold. Pure: no I/O.
import { assessQuote, readDelivery, type Line, type Requirements, type Terms } from './assess.ts';
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
export type AttrRow = { code: string; label_en: string; label_ar: string; unit: string | null; unit_ar: string | null; mandatory: boolean; requested: string | null; requested_source: 'boq' | 'intake' | 'no_preference' | null; cells: Cell[] };
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

/** The request's own values per attribute for one request line: from its BOQ wording, then the customer's intake answers. */
// `fromRequest` is false when the row's wording is a QUOTE's own line (no BOQ): a quote's own values
// are never its own baseline, or every quote would "match the request" by construction.
function requestedFor(rl: RequestLine, trade: string | null, attrs: Attr[], req: Requirements, fromRequest: boolean) {
  const out: Record<string, { value: string; source: 'boq' | 'intake' | 'no_preference' }> = {};
  if (fromRequest) for (const a of attrs) { const v = a.find(rl.description); if (v) out[a.code] = { value: v, source: 'boq' }; }
  for (const m of req?.materials ?? []) {
    if (!m?.component) continue;
    const hit = normText(rl.description).toLowerCase().includes(normText(m.component).toLowerCase()) || similarity(m.component, rl.description) >= 0.34;
    if (!hit) continue;
    const noPref = /^no[_\s-]?preference$|^لا تفضيل$/i.test(String(m.value || '').trim());
    const targets = m.attr ? attrs.filter((a) => a.code === m.attr) : attrs;
    for (const a of targets) {
      if (noPref) { out[a.code] = { value: 'no_preference', source: 'no_preference' }; continue; }
      const v = m.attr ? normText(m.value) : a.find(m.value);
      if (v) out[a.code] = { value: v, source: 'intake' };
    }
  }
  return trade ? out : {};
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
    const text = r.rl?.description ?? (() => { const [qid, ln] = [...r.picks.entries()][0]; return assessed.find((x) => x.q.quote_id === qid)!.a.lines.find((l) => l.line_no === ln)!.description; })();
    const lt = tradeOfLine(trade, text) ?? (() => { const [qid, ln] = [...r.picks.entries()][0] ?? []; return qid ? assessed.find((x) => x.q.quote_id === qid)!.a.lines.find((l) => l.line_no === ln)?.trade ?? null : null; })();
    const attrs = lt ? TRADES[lt].attrs : [];
    const requested = r.rl ? requestedFor(r.rl, lt, attrs, req, fromRequest) : {};
    const attributes: AttrRow[] = attrs.map((a) => {
      const rq = requested[a.code];
      const noPref = rq?.source === 'no_preference';
      const cells = assessed.map(({ q, a: qa }) => {
        const ln = r.picks.get(q.quote_id);
        const l = ln != null ? qa.lines.find((x) => x.line_no === ln) : undefined;
        if (!l) return cellOf(q.quote_id, true, null, noPref ? null : rq?.value ?? null, noPref);
        const qLine = q.lines.find((x) => x.line_no === ln)!;
        const asked = attrsForLine(l.trade ?? lt!, `${qLine.description} ${qLine.specification ?? ''}`).some((x) => x.code === a.code) || l.asked.includes(a.code);
        return cellOf(q.quote_id, asked, l.spec[a.code] ?? null, noPref ? null : rq?.value ?? null, noPref, { source: l.source[a.code] ?? null, quote_line_no: ln });
      });
      return { code: a.code, label_en: a.en, label_ar: a.ar, unit: a.unit ?? null, unit_ar: a.unit_ar ?? null, mandatory: a.mandatory, requested: rq && !noPref ? rq.value : null, requested_source: rq?.source ?? null, cells };
    }).filter((row) => row.mandatory || row.requested || row.cells.some((c) => c.value));
    return { row: i + 1, item: safe(text) ?? '', request_line: fromRequest ? r.rl : null, trade: lt, trade_en: lt ? TRADES[lt].en : null, trade_ar: lt ? TRADES[lt].ar : null, attributes };
  });

  // Quote-level terms, against the customer's intake answers.
  const noPref = (v: unknown) => v === 'no_preference';
  const dBy = req?.delivery_by ? new Date(req.delivery_by) : null;
  const dByOk = dBy && !isNaN(dBy.getTime()) ? dBy : null;
  const deliveryRow: TermRow = { code: 'delivery', label_en: 'Delivery / lead time', label_ar: 'التسليم / مدة التنفيذ', requested: dByOk ? req!.delivery_by! : null, requested_source: dByOk ? 'intake' : null,
    cells: assessed.map(({ q, a }) => {
      const t = a.terms.delivery; let flag: Flag = t.value ? (dByOk ? 'stated' : 'stated') : 'missing';
      if (t.value && dByOk) {
        const due = t.date ? new Date(t.date) : (t.days != null ? new Date(input.now.getTime() + t.days * 864e5) : null);
        flag = due && !isNaN(due.getTime()) ? (due.getTime() <= dByOk.getTime() + 864e5 ? 'match' : 'differs') : 'stated';
      }
      return { quote_id: q.quote_id, applies: true, value: safe(t.value), flag, marker: MARKER[flag] };
    }) };
  const instReq = req?.installation ?? null;
  const installationRow: TermRow = { code: 'installation', label_en: 'Installation', label_ar: 'التركيب', requested: instReq && instReq !== 'no_preference' ? instReq : null, requested_source: instReq === 'no_preference' ? 'no_preference' : instReq ? 'intake' : null,
    cells: assessed.map(({ q, a }) => {
      const t = a.terms.installation;
      const value = t.included ? (t.included === 'yes' ? `Included${t.detail ? ' — ' + t.detail : ''}` : 'Not included (supply only)') : null;
      const want = instReq === 'required' ? 'yes' : instReq === 'not_required' ? 'no' : null;
      const flag = flagOf(t.applies, t.included, want, noPref(instReq), (x, y) => x === y);
      return { quote_id: q.quote_id, applies: t.applies, value: safe(value), flag, marker: MARKER[flag] };
    }) };
  const wReq = req?.warranty ?? null;
  const wNoPref = noPref(wReq?.required);
  const warrantyRow: TermRow = { code: 'warranty', label_en: 'Warranty', label_ar: 'الضمان', requested: wReq?.min_months ? `${wReq.min_months} months minimum` : (wReq?.required === true ? 'required' : null), requested_source: wNoPref ? 'no_preference' : (wReq?.min_months || wReq?.required === true ? 'intake' : null),
    cells: assessed.map(({ q, a }) => {
      const t = a.terms.warranty;
      const value = t.period ? `${t.period}${t.coverage ? ' — ' + t.coverage : ''}` : null;
      let flag: Flag = flagOf(t.applies, value, null, wNoPref);
      if (flag === 'stated' && wReq?.min_months && t.months != null) flag = t.months >= wReq.min_months ? 'match' : 'differs';
      else if (flag === 'stated' && wReq?.required === true) flag = 'match';
      return { quote_id: q.quote_id, applies: t.applies, value: safe(value), flag, marker: MARKER[flag] };
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
