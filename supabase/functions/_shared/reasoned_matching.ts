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
import { readerOfTheirOwnText, think, type ThinkDeps, type ThinkResult } from './think.ts';
import { COMPOSITE, lineTradeOptions, TRADES, tradeOfCategory, attrsOf } from './line_specs/model.ts';
import { componentAttr, lineText, materialNames, READ, type Line, type Requirements, type Terms, type TermsSpec } from './line_specs/assess.ts';
import type { SpecOffer } from './line_specs/no_exact_spec.ts';
import { heldFromGate, type GateAnswer } from './llm_hold.ts';

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
// The line questions of one step run in parallel, and an ANSWERED question is remembered for this worker's life
// (READS below), so the review, the preflight and the gate of one submission ask each question once.
//
// THE SAME QUOTATION READS THE SAME WAY, EVERY TIME (sales_engineer, 2 Nov 2026). The memo above was per edge worker,
// and the preflight ("check before sending") and the real submission are two requests that usually land on two
// workers, so each asked the model afresh — at temperature 0.2, through the gateway's routing. One field read in the
// first and not the second turned an accepted quote into a held one: measured on the nightly journey, the IDENTICAL
// demo quotations were held in run 41417049225 (complete quote: preflight would_accept, submission spec_hold) and
// accepted in run 41422665440 (where the two-option quotation was held instead). An answered reading is now settled
// in public.line_spec_reading under a sha-256 of the normalised question (the supplier's lines and terms) and the
// decision asked (the trade's attributes and the customer's named components), and the FIRST stored answer is the
// one every later read of that same text uses — preflight, submission, resubmission, any worker, any day. The model
// is asked only for text never read before, at temperature 0. A held or failed read is not stored (it is asked again).
// prevented by: _shared/line_specs/the_same_quote_gets_the_same_verdict.test.ts
// ponytail: a settled reading never expires; a better prompt or model reads only new text. Add a version to the key
// the day a reader change must re-read old quotations.
export const LINES_PER_CALL = 2;
export const MAX_READ_LINES = 40;
const alreadyRead = (l: Line) => Object.values(l.spec_source ?? {}).includes('reasoned');
const READS = new Map<string, ThinkResult>();
/** Tests only: forget remembered answers so each case starts cold (a new edge worker). */
export const forgetReads = () => { READS.clear(); storeFailures = 0; };
const normQ = (s: string) => String(s ?? '').replace(/\s+/g, ' ').trim();
async function sha256(s: string): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)))].map((b) => b.toString(16).padStart(2, '0')).join('');
}
type Settled = { decision: NonNullable<ThinkResult['decision']>; model: string | null; confidence: number };
const fromSettled = (s: Settled, key: string): ThinkResult => ({
  status: 'answered', answer: '', decision: s.decision, model: s.model ?? null, confidence: Number(s.confidence) || 0,
  steps: [{ id: 'settled', kind: 'retrieve', goal: 'this exact text was read before; that reading is the reading', status: 'done', detail: { reading_key: key } }],
  context_used: {} as ThinkResult['context_used'], missing_context: [], sources: [], asked_back: null, verified: null,
});
// A store that cannot be read or written is not silent (review of #1799): logged every time, and the third in one worker
// is an IT finding — without the store the gate is back to asking the model per request.
let storeFailures = 0;
async function storeFailed(deps: ThinkDeps, fn: string, why: string) {
  console.error(`settledRead: ${fn} failed: ${why}`);
  if (++storeFailures !== 3) return;
  await deps.rpc('fn_it_engineer_finding_upsert', { p_issue_key: 'quote_gate_reading_store_unavailable', p_title: 'The quote gate could not read or write its settled readings, so a quotation may be read differently per request',
    p_where: 'supabase/functions/_shared/reasoned_matching.ts settledRead', p_blast: 'customer_facing', p_affected: 1, p_evidence: { fn, why: why.slice(0, 300), failures_in_worker: storeFailures },
    p_ruled_out: [], p_undetermined: [], p_raised_by: 'sales_engineer' }).catch(() => null);
}
async function storedReading(deps: ThinkDeps, key: string): Promise<Settled | null> {
  const got = await deps.rpc('fn_line_spec_reading_get', { p_keys: [key] }).catch((e) => ({ data: null, error: { message: String(e) } }));
  if (got?.error) { await storeFailed(deps, 'fn_line_spec_reading_get', got.error.message); return null; }
  const s = got?.data && typeof got.data === 'object' ? (got.data as Record<string, Settled>)[key] : null;
  return s && typeof s === 'object' && s.decision && typeof s.decision === 'object' ? s : null;
}
// THE READER'S VERSION IS IN THE KEY (review of #1799). Bump it whenever a reader's prompt, its fields or the model
// ruling for its surface changes, so a changed reader re-reads rather than reusing an old reading. The model itself is
// routed by the gateway after the key is made (the stored row records which model answered), so it is this constant,
// not the routed model id, that retires old readings. 2 = the first settled version (2 Nov 2026).
export const READER_VERSION = 2;
/** One reading of a supplier's own text, settled: the first answer stored for this exact question is every later answer. */
export async function settledRead(deps: ThinkDeps, req: Parameters<typeof think>[1], version: number = READER_VERSION): Promise<ThinkResult> {
  const key = await sha256('quote_gate_read\u0001' + JSON.stringify([version, req.surface, normQ(req.question), req.decision]));
  const remember = (r: ThinkResult) => { if (READS.size >= 200) READS.delete(READS.keys().next().value!); READS.set(key, r); return r; };
  const hit = READS.get(key); if (hit) return hit;
  const before = await storedReading(deps, key);
  if (before) return remember(fromSettled(before, key));
  const r = await think(deps, { temperature: 0, ...req });
  if (!answered(r) || !r.decision) return r;
  const put = await deps.rpc('fn_line_spec_reading_put', { p_rows: [{ key, found: { decision: r.decision, model: r.model ?? null, confidence: r.confidence, reader_version: version } }] })
    .catch((e) => ({ data: null, error: { message: String(e) } }));
  if (put?.error) await storeFailed(deps, 'fn_line_spec_reading_put', put.error.message);
  // Two workers reading the same new text at once: the row stored first wins (put keeps the first), so both use it.
  const first = await storedReading(deps, key);
  return remember(first ? fromSettled(first, key) : r);
}
const ask = settledRead;
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
  const base = { seat: 'sales_engineer' as const, dedupeKey: 'quote_read:' + o.quoteId, subject: { quote_id: o.quoteId }, ...readerOfTheirOwnText("read what the supplier's own quotation states") };
  const out: QuoteReading = { lines: {}, terms: {} };
  const put = (n: number, k: string, v: string) => { (out.lines[n] ??= {})[k] = v; };
  const lines = o.lines.filter((l) => !alreadyRead(l)).slice(0, MAX_READ_LINES);
  const ts = o.terms.terms_spec ?? {};

  // 1. The quote-level terms the supplier has not already stated in the portal. It does not depend on the lines' trade or
  //    specs (steps 2-3), so it runs BESIDE them, not before them (13 Oct 2026: the review's chain was 7 calls in a row).
  const termFields = TERM_FIELDS.filter((f) => f.key === 'delivery' ? !ts.delivery?.value
    : f.key.startsWith('installation') ? !ts.installation?.included : !ts.warranty?.period);
  const termsStep: Promise<boolean> = (async () => {
    if (!termFields.length) return true;
    const text = [['LEAD TIME', o.terms.lead_time], ['WARRANTY', o.terms.warranty], ['SCOPE', o.terms.scope], ['CONDITIONS', o.terms.conditions],
      ['EXCLUSIONS', o.terms.exclusions], ['NOTES', o.terms.notes]].filter(([, v]) => v && String(v).trim()).map(([k, v]) => `${k}: ${v}`)
      .concat(lines.map((l) => `LINE ${l.line_no}: ${lineText(l).slice(0, 300)}`)).join('\n').slice(0, 6000);
    const r = await ask(deps, { ...base, surface: 'line_specs.assess', question: text,
      context: { audience: 'supplier', trade: quoteTrade, conversation: [{ role: 'supplier', text }] },
      decision: { name: 'quote_terms', fields: termFields } });
    if (!answered(r)) return false;
    const f = r.decision?.fields ?? {};
    if (f.delivery?.value) out.terms.delivery = { value: f.delivery.value, source: 'reasoned' };
    // Both, or neither: not a statement either way, so it stays asked.
    const inc = !!f.installation_included?.value, exc = !!f.installation_excluded?.value;
    if (inc !== exc) out.terms.installation = { included: inc ? 'yes' : 'no', detail: f.installation_detail?.value ?? null, source: 'reasoned' };
    if (f.warranty_period?.value) out.terms.warranty = { period: f.warranty_period.value, coverage: f.warranty_coverage?.value ?? '', source: 'reasoned' };
    return true;
  })().catch(() => false);

  // Under the model hold the readers are not forked: the terms ask is held and queued, and that ONE question for the
  // quote is the whole answer (as before); in parallel the lines would queue a second.
  if (heldFromGate((await deps.gate().catch(() => null)) as GateAnswer) && !(await termsStep)) return null;

  // 2. A composite quote (fit-out, MEP ...): the trade each line is, or none (labour, a fee, a heading).
  const tradeOf: Record<number, string | null> = {};
  const trades = composite ? await Promise.all(lines.map((l) => { const text = `LINE ${l.line_no}: ${lineText(l).slice(0, 1500)}`; return ask(deps, { ...base, surface: 'line_specs.vague', question: text, context: { audience: 'supplier', trade: quoteTrade },
      decision: { name: 'line_trade', options: [
        ...lineTradeOptions(quoteTrade).map((t) => ({ id: t, meaning: `a ${TRADES[t].en} item: a material or product of that trade` })),
        { id: 'none', meaning: 'no trade material: labour, transport, a fee, a discount, a heading or a lump sum' },
      ] } }); })) : [];
  if (trades.some((r) => !answered(r))) { await termsStep; return null; }
  lines.forEach((l, i) => {
    if (!composite) { tradeOf[l.line_no] = TRADES[quoteTrade] ? quoteTrade : null; return; }
    const t = trades[i].decision?.choice ?? 'none';
    put(l.line_no, READ.trade, t);
    tradeOf[l.line_no] = t !== 'none' && TRADES[t] ? t : null;
  });

  // 3. Every detail each line states, in batches, each with the supplier's own words as evidence.
  const comps = (o.requirements?.materials ?? []).filter((m) => m?.component && m.component !== 'main');
  const asked = lines.filter((l) => tradeOf[l.line_no] || (!composite && comps.length));
  const batches: Line[][] = [];
  for (let i = 0; i < asked.length; i += LINES_PER_CALL) batches.push(asked.slice(i, i + LINES_PER_CALL));
  const results = await Promise.all(batches.map((batch) => {
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
    return ask(deps, { ...base, surface: 'line_specs.assess', question: text,
      context: { audience: 'supplier', trade: quoteTrade, conversation: [{ role: 'supplier', text }] },
      decision: { name: 'stated_specs', fields } });
  }));
  if (!(await termsStep) || results.some((r) => !answered(r))) return null;
  for (const r of results) {
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
