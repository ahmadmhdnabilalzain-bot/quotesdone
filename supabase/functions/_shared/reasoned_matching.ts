// reasoned_matching — what a customer's request and a supplier's quotation MEAN, read by reasoning.
// Seat: sales_engineer. 23 Sep 2026, founder_instruction 886-903 (ledger 890: no word matching anywhere);
// decision points 24 and 26-30 of decision_points.json (batch B3). Follows reasoned_decisions.ts: one decision,
// one function, a think() call, and a value that is null when the reasoning is held.
//
//   tradeOfWords         which live trade a supplier's own words name             (sql.fn_norm_trades)
//   catalogueCategoryOf  which catalogue category a visitor's words ask for         (sql.fn_kb_route)
//   productsAsked        which of a supplier's products an enquiry asks for         (sql.fn_supplier_product_match)
//   reasonedOffers       whether a quoted value is GENUINELY not the customer's spec (line_specs.same_value)
//   readQuote            what each line of a quotation states, exactly, and its terms (line_specs.assess,
//                        line_specs.vague for the trade of a composite quote's line)
//
// Exact or none: a value read from a quotation is kept only with the supplier's own words as verbatim evidence
// (think()'s validator refuses anything else), so a vague or unstated detail stays missing and the quote is
// held. UNDER THE HOLD every function returns null / nothing, files ONE question in the sales_engineer queue
// (dedupeKey), and the caller does the safe thing: the visitor is asked to describe the job, the product list
// is not scored, no alternative is offered to a customer, and a quote is held with every detail asked of the
// supplier — whose own statement in the portal releases it. Nothing falls back to a keyword.
import { think, type ThinkDeps, type ThinkResult } from './think.ts';
import { COMPOSITE, lineTradeOptions, TRADES, tradeOfCategory, attrsOf } from './line_specs/model.ts';
import { componentAttr, lineText, materialNames, READ, type Line, type Requirements, type Terms, type TermsSpec } from './line_specs/assess.ts';
import type { SpecOffer } from './line_specs/no_exact_spec.ts';

export type Reasoned<T> = { value: T | null; result: ThinkResult };
const answered = (r: ThinkResult) => r.status === 'answered';

/** Which live trade do a supplier's own words name? [] = none. Exact trade or none (surface sql.fn_norm_trades). */
export async function tradeOfWords(deps: ThinkDeps, o: { text: string; trades: { code: string; label: string }[] }): Promise<Reasoned<string[]>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'sql.fn_norm_trades', question: o.text.slice(0, 500), dedupeKey: 'trade_words:' + o.text.slice(0, 120).toLowerCase(),
    context: { audience: 'supplier' },
    decision: { name: 'trade', options: [
      ...o.trades.map((t) => ({ id: t.code, meaning: `the words name ${t.label} work or supply, exactly that trade` })),
      { id: 'none', meaning: 'the words name no trade in this list exactly' },
    ] },
  });
  const choice = answered(result) ? result.decision?.choice ?? null : null;
  return { value: choice == null ? null : choice === 'none' ? [] : [choice], result };
}

/** Which catalogue category does the visitor's description ask for? 0 = none of them. (surface sql.fn_kb_route) */
export async function catalogueCategoryOf(deps: ThinkDeps, o: {
  text: string; categories: { catalog_num: number; live_name: string }[]; audience?: 'customer' | 'visitor'; dedupeKey?: string; subject?: Record<string, unknown>;
  /** false for a caller with no channel to answer on later (a public page): held, the person is asked now. */
  queue?: boolean;
}): Promise<Reasoned<number>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'sql.fn_kb_route', question: o.text.slice(0, 2000), dedupeKey: o.dedupeKey, subject: o.subject, queueWhenHeld: o.queue,
    context: { audience: o.audience ?? 'visitor' },
    decision: { name: 'catalogue_category', options: [
      ...o.categories.map((c) => ({ id: 'c' + c.catalog_num, meaning: `the job is ${c.live_name}` })),
      { id: 'none', meaning: 'it is none of these, or it does not say what is needed' },
    ] },
  });
  const choice = answered(result) ? result.decision?.choice ?? null : null;
  return { value: choice == null ? null : choice === 'none' ? 0 : Number(choice.slice(1)) || 0, result };
}

/** Which one of this supplier's products does the enquiry ask for? [] = none. (surface sql.fn_supplier_product_match) */
export async function productsAsked(deps: ThinkDeps, o: {
  want: string; products: { product_id: string; name: string | null; brand?: string | null; model?: string | null; description?: string | null }[];
  inquiryId: string; leadId: number;
}): Promise<Reasoned<string[]>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'sql.fn_supplier_product_match', question: o.want.slice(0, 4000),
    dedupeKey: `product_match:${o.inquiryId}:${o.leadId}`, subject: { inquiry_id: o.inquiryId, supplier_id: o.leadId },
    context: { audience: 'supplier' },
    decision: { name: 'product_asked', options: [
      ...o.products.map((p) => ({ id: 'p' + p.product_id, meaning: `the enquiry asks for this product: ${[p.name, p.brand, p.model].filter(Boolean).join(' / ')}${p.description ? ' — ' + p.description.slice(0, 160) : ''}` })),
      { id: 'none', meaning: 'the enquiry asks for none of these products' },
    ] },
  });
  const choice = answered(result) ? result.decision?.choice ?? null : null;
  return { value: choice == null ? null : choice === 'none' ? [] : [choice.slice(1)], result };
}

/**
 * Of the offers the comparison proposes (no quote's value is textually the customer's), keep only those where
 * reasoning finds every quoted value a GENUINELY different specification. One whose quoted value IS the spec,
 * written differently ("10 millimetres" for "10mm"), is dropped: that supplier did quote it. Held: nothing is
 * offered for that inquiry this time; the sweep asks again next tick. (surface line_specs.same_value)
 */
export async function reasonedOffers(deps: ThinkDeps, offers: SpecOffer[], inquiryId: string): Promise<{ offers: SpecOffer[]; held: number; same: number }> {
  const kept: SpecOffer[] = []; let held = 0, same = 0;
  for (const sp of offers) {
    const question = `The customer asked for ${sp.label_en} = "${sp.requested}" on the item "${sp.item}". The suppliers quoted:\n`
      + sp.alternatives.map((a) => `${a.option_id}) "${a.value}"`).join('\n');
    const r = await think(deps, {
      seat: 'sales_engineer', surface: 'line_specs.same_value', question,
      dedupeKey: `spec_offer:${inquiryId}:${sp.line_no}:${sp.attr}`, subject: { inquiry_id: inquiryId, line_no: sp.line_no, attr: sp.attr },
      context: { audience: 'customer' },
      decision: { name: 'exact_spec_quoted', options: [
        { id: 'all_different', meaning: 'every quoted value is a genuinely different specification from what the customer asked for' },
        ...sp.alternatives.map((a) => ({ id: a.option_id, meaning: `"${a.value}" IS exactly the specification asked ("${sp.requested}"), only written differently` })),
      ] },
    });
    if (!answered(r)) { held++; continue; }
    if (r.decision?.choice === 'all_different') kept.push(sp); else same++;
  }
  return { offers: kept, held, same };
}

// ── THE QUOTATION, READ ──────────────────────────────────────────────────────────────────────────────
// COST (review of #893). Lines per reasoning call: the answer must fit the gateway's output cap (~900 tokens) —
// each line asks its trade's attributes with verbatim evidence — and each batch carries its own text. Lines past
// MAX_READ_LINES are left unread and asked of the supplier. A line ALREADY read (any 'reasoned' value on it) is
// not read again, so the review's turns, the preflight and the gate pay for a line once.
// ponytail: sequential think() calls inside the request; move the read to a queue if quotes grow past ~20 lines.
export const LINES_PER_CALL = 2;
export const MAX_READ_LINES = 20;
const alreadyRead = (l: Line) => Object.values(l.spec_source ?? {}).includes('reasoned');
/** What reasoning read: per line, values and READ keys to add to its spec (source 'reasoned'); the terms it found. */
export type QuoteReading = { lines: Record<number, Record<string, string>>; terms: TermsSpec };

const TERM_FIELDS: { key: string; question: string }[] = [
  { key: 'delivery', question: 'the delivery date or lead time, exactly as written (a number of days, weeks or months, or a date)' },
  { key: 'installation_included', question: 'the words that say installation IS included' },
  { key: 'installation_excluded', question: 'the words that say installation is NOT included (supply only, by others, excluded)' },
  { key: 'installation_detail', question: 'the installation scope or timeline, exactly as written' },
  { key: 'warranty_period', question: 'the warranty period, exactly as written (e.g. 2 years)' },
  { key: 'warranty_coverage', question: 'what the warranty covers, exactly as written' },
];

/**
 * Read a quotation: its terms, the trade of each line of a composite quote, and every detail each line states.
 * Null when any step is held — the quote is then assessed on what the supplier stated in keyed fields only,
 * so it is held and he is asked. One held question per quote (dedupeKey quote_read:<id>).
 */
export async function readQuote(deps: ThinkDeps, o: { quoteId: string; category: string | null; lines: Line[]; terms: Terms; requirements: Requirements }): Promise<QuoteReading | null> {
  const quoteTrade = tradeOfCategory(o.category);
  const composite = COMPOSITE.has(quoteTrade);
  const base = { seat: 'sales_engineer' as const, dedupeKey: 'quote_read:' + o.quoteId, subject: { quote_id: o.quoteId } };
  const out: QuoteReading = { lines: {}, terms: {} };
  const put = (n: number, k: string, v: string) => { (out.lines[n] ??= {})[k] = v; };
  const lines = o.lines.filter((l) => !alreadyRead(l)).slice(0, MAX_READ_LINES);
  const ts = o.terms.terms_spec ?? {};

  // 1. The quote-level terms the supplier has not already stated in the portal.
  const termFields = TERM_FIELDS.filter((f) => f.key === 'delivery' ? !ts.delivery?.value
    : f.key.startsWith('installation') ? !ts.installation?.included : !ts.warranty?.period);
  if (termFields.length) {
    const text = [['LEAD TIME', o.terms.lead_time], ['WARRANTY', o.terms.warranty], ['SCOPE', o.terms.scope], ['CONDITIONS', o.terms.conditions],
      ['EXCLUSIONS', o.terms.exclusions], ['NOTES', o.terms.notes]].filter(([, v]) => v && String(v).trim()).map(([k, v]) => `${k}: ${v}`)
      .concat(lines.map((l) => `LINE ${l.line_no}: ${lineText(l).slice(0, 300)}`)).join('\n').slice(0, 6000);
    const r = await think(deps, { ...base, surface: 'line_specs.assess', question: text,
      context: { audience: 'supplier', trade: quoteTrade, conversation: [{ role: 'supplier', text }] },
      decision: { name: 'quote_terms', fields: termFields } });
    if (!answered(r)) return null;
    const f = r.decision?.fields ?? {};
    if (f.delivery?.value) out.terms.delivery = { value: f.delivery.value, source: 'reasoned' };
    // Both, or neither: not a statement either way, so it stays asked.
    const inc = !!f.installation_included?.value, exc = !!f.installation_excluded?.value;
    if (inc !== exc) out.terms.installation = { included: inc ? 'yes' : 'no', detail: f.installation_detail?.value ?? null, source: 'reasoned' };
    if (f.warranty_period?.value) out.terms.warranty = { period: f.warranty_period.value, coverage: f.warranty_coverage?.value ?? '', source: 'reasoned' };
  }

  // 2. A composite quote (fit-out, MEP ...): the trade each line is, or none (labour, a fee, a heading).
  const tradeOf: Record<number, string | null> = {};
  for (const l of lines) {
    if (!composite) { tradeOf[l.line_no] = TRADES[quoteTrade] ? quoteTrade : null; continue; }
    const text = `LINE ${l.line_no}: ${lineText(l).slice(0, 1500)}`;
    const r = await think(deps, { ...base, surface: 'line_specs.vague', question: text, context: { audience: 'supplier', trade: quoteTrade },
      decision: { name: 'line_trade', options: [
        ...lineTradeOptions(quoteTrade).map((t) => ({ id: t, meaning: `a ${TRADES[t].en} item: a material or product of that trade` })),
        { id: 'none', meaning: 'no trade material: labour, transport, a fee, a discount, a heading or a lump sum' },
      ] } });
    if (!answered(r)) return null;
    const t = r.decision?.choice ?? 'none';
    put(l.line_no, READ.trade, t);
    tradeOf[l.line_no] = t !== 'none' && TRADES[t] ? t : null;
  }

  // 3. Every detail each line states, in batches, each with the supplier's own words as evidence.
  const comps = (o.requirements?.materials ?? []).filter((m) => m?.component && m.component !== 'main');
  const asked = lines.filter((l) => tradeOf[l.line_no] || (!composite && comps.length));
  for (let i = 0; i < asked.length; i += LINES_PER_CALL) {
    const batch = asked.slice(i, i + LINES_PER_CALL);
    const text = batch.map((l) => `LINE ${l.line_no}: ${lineText(l).slice(0, 1500)}`).join('\n');
    const fields = batch.flatMap((l) => {
      const n = l.line_no; const t = tradeOf[n]; const attrs = attrsOf(t);
      return [
        ...attrs.map((a) => ({ key: `L${n}__${a.code}`, question: `line ${n} — ${a.en}${a.unit ? ` (${a.unit})` : ''}: the exact value this line states; leave it out if the line does not state it or states it vaguely (TBD, as per drawing, equivalent, to be confirmed)` })),
        ...attrs.filter((a) => a.conditional).map((a) => ({ key: `L${n}__na__${a.code}`, question: `line ${n}: if "${a.en}" does not apply to what this line is, the words of the line that show what it is` })),
        ...(composite ? [] : [{ key: `L${n}__not_material`, question: `line ${n}: if this line carries no material to specify (labour, transport, a fee, a discount, a heading, a lump sum), the words that say so` }]),
        ...comps.flatMap((m) => {
          const label = materialNames(m).en; const a = componentAttr(m, t, attrs);
          return [{ key: `L${n}__names__${m.component}`, question: `line ${n}: the words that name the customer's "${label}"` },
            ...(attrs.some((x) => x.code === a.code) ? [] : [{ key: `L${n}__${a.code}`, question: `line ${n}: the material of the ${label}, exactly as written` }])];
        }),
      ];
    });
    const r = await think(deps, { ...base, surface: 'line_specs.assess', question: text,
      context: { audience: 'supplier', trade: quoteTrade, conversation: [{ role: 'supplier', text }] },
      decision: { name: 'stated_specs', fields } });
    if (!answered(r)) return null;
    for (const [k, v] of Object.entries(r.decision?.fields ?? {})) {
      const m = k.match(/^L(\d+)__(na__|names__)?(.+)$/);   // our own key format, parsed
      if (!m || !v?.value) continue;
      const n = Number(m[1]);
      if (m[2] === 'na__') put(n, READ.na(m[3]), v.value);
      else if (m[2] === 'names__') put(n, READ.names(m[3]), v.value);
      else if (m[3] === 'not_material') put(n, READ.notMaterial, v.value);
      else put(n, m[3], v.value);
    }
  }
  return out;
}

/** The lines and terms with what reasoning read written in (source 'reasoned'). What the supplier stated himself is never overwritten. */
export function applyReading(lines: Line[], terms: TermsSpec | null | undefined, reading: QuoteReading | null): { lines: Line[]; terms_spec: TermsSpec } {
  const ts: TermsSpec = { ...(terms ?? {}) };
  if (!reading) return { lines, terms_spec: ts };
  if (reading.terms.delivery && !ts.delivery?.value) ts.delivery = reading.terms.delivery;
  if (reading.terms.installation && !ts.installation?.included) ts.installation = reading.terms.installation;
  if (reading.terms.warranty && !ts.warranty?.period) ts.warranty = reading.terms.warranty;
  return {
    terms_spec: ts,
    lines: lines.map((l) => {
      const add = Object.fromEntries(Object.entries(reading.lines[l.line_no] ?? {}).filter(([k]) => !l.spec?.[k]));
      if (!Object.keys(add).length) return l;
      return { ...l, spec: { ...add, ...(l.spec ?? {}) }, spec_source: { ...Object.fromEntries(Object.keys(add).map((k) => [k, 'reasoned' as const])), ...(l.spec_source ?? {}) } };
    }),
  };
}
