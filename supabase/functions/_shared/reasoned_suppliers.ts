// reasoned_suppliers — the sales engineer's decision points on prices, supplier profiles and quotations,
// moved off word lists onto think(). Seat: sales_engineer. 23 Sep 2026, founder_instruction 886-903
// (batch B5 of decision_points.json: orders 39-46).
//
// Each function asks think() one question and returns { value | null, result } (reasoned_decisions.ts'
// shape). null means HELD (the founder's model hold, or a model that failed): the caller does the safe,
// non-committal thing, never a keyword guess. Where the answer has an effect in the database, the held
// question is queued under its surface and fn_reason_apply_<surface> (scripts/sql/
// prices_supplier_profiles_and_quote_quality_are_read_by_reasoning.sql) applies it when the hold lifts.
import { think, type ThinkDeps } from './think.ts';
import type { Reasoned } from './reasoned_decisions.ts';

const answered = (r: { status: string }) => r.status === 'answered';
/** A field counts only with a value AND the words that state it (think() has already checked they are verbatim). */
// deno-lint-ignore no-explicit-any
const stated = (r: any, k: string) => { const f = r.decision?.fields?.[k]; return !!(f && String(f.value ?? '').trim() && String(f.evidence ?? '').trim()); };

// ── 39 quote_extract.document ─────────────────────────────────────────────────────────────────────
/** The commercial terms a quotation states, each with the words that state it. */
export const QUOTE_TERMS = [
  { key: 'lead_time', question: 'the lead / delivery / completion time the supplier commits to' },
  { key: 'validity', question: 'how long the offer is valid' },
  { key: 'payment_terms', question: 'the payment terms' },
  { key: 'warranty', question: 'the warranty or guarantee given' },
  { key: 'exclusions', question: 'what the quotation excludes' },
  { key: 'conditions', question: 'whether installation is included, or it is supply only, and any other condition of the offer' },
] as const;
export type QuoteTermKey = typeof QUOTE_TERMS[number]['key'];

/** Surface quote_extract.document. Not queued when held: the supplier is looking at the form now and types
 *  the terms himself; a replay later would have no form to fill. */
export async function quoteTerms(deps: ThinkDeps, o: { text: string }): Promise<Reasoned<Partial<Record<QuoteTermKey, string>>>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'quote_extract.document', question: o.text.slice(0, 6000), queueWhenHeld: false,
    context: { audience: 'supplier', conversation: [{ role: 'supplier', text: o.text.slice(0, 6000) }] },
    decision: { name: 'quotation_terms', fields: QUOTE_TERMS.map((t) => ({ key: t.key, question: t.question })) },
  });
  if (!answered(result)) return { value: null, result };
  const out: Partial<Record<QuoteTermKey, string>> = {};
  for (const t of QUOTE_TERMS) {
    const f = result.decision?.fields?.[t.key];
    if (stated(result, t.key)) out[t.key] = String(f!.value).trim();
  }
  return { value: out, result };
}

// ── 40 sql.fn_price_guidance ──────────────────────────────────────────────────────────────────────
export type PriceReading = { trade: string | null; asks_price: boolean; item: string | null };
/** Does the question ask what something costs, and which published trade is it about? The trade list is
 *  what fn_price_guidance(null) returns. Not queued when held: the visitor is answered now from the FAQ
 *  and the corpus, and a price for a chat already closed has nobody to go to. */
export async function priceQuestion(deps: ThinkDeps, o: { question: string; trades: string[]; audience?: 'visitor' | 'customer' | 'supplier' }): Promise<Reasoned<PriceReading>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'sql.fn_price_guidance', question: o.question.slice(0, 2000), queueWhenHeld: false,
    context: { audience: o.audience ?? 'visitor', conversation: [{ role: o.audience ?? 'visitor', text: o.question.slice(0, 2000) }] },
    decision: {
      name: 'price_trade',
      options: [
        ...o.trades.map((t) => ({ id: t, meaning: `they ask what ${t.replace(/-/g, ' ')} work or material costs` })),
        { id: 'other_trade', meaning: 'they ask what something costs, but it is none of the trades listed' },
        { id: 'not_a_price_question', meaning: 'they do not ask what something costs (fees of the platform, coverage, documents, how it works ...)' },
      ],
      fields: [{ key: 'item', question: 'the specific item, material or job they ask the price of, in their words (empty if only the trade)' }],
    },
  });
  if (!answered(result)) return { value: null, result };
  const choice = result.decision?.choice ?? null;
  const item = result.decision?.fields?.item?.value?.trim() || null;
  if (choice && o.trades.includes(choice)) return { value: { trade: choice, asks_price: true, item }, result };
  return { value: { trade: null, asks_price: choice === 'other_trade', item }, result };
}

/** The trades we publish for, then the reasoned trade, then the bands: the whole price answer for a caller
 *  that has only the visitor's words. Held -> { reason: 'held' }. */
export async function priceGuidanceFor(deps: ThinkDeps, question: string, limit = 6, audience?: 'visitor' | 'customer' | 'supplier') {
  const rpc = deps.rpc;
  const { data: list, error } = await rpc('fn_price_guidance', { p_trade: null, p_limit: limit });
  if (error || !list) return { ok: false, reason: 'unavailable' };
  const r = await priceQuestion(deps, { question, trades: Array.isArray(list.trades) ? list.trades.map(String) : [], audience });
  if (!r.value) return { ok: false, reason: 'held', held: true };
  if (!r.value.trade) return { ok: false, reason: r.value.asks_price ? 'no_trade_matched' : 'not_a_price_question', asked_item: r.value.item };
  const { data: pg, error: e2 } = await rpc('fn_price_guidance', { p_trade: r.value.trade, p_limit: limit, p_asked_item: r.value.item });
  return e2 || !pg ? { ok: false, reason: 'unavailable' } : pg;
}

// ── 42 sql.fn_supplier_twin, 43 sql.fn_supplier_portfolio_gaps ────────────────────────────────────
// A field is filled ONLY when the summary says the company does it (value and evidence are its own words,
// think() refuses anything else); left out when it does not say so or says it does not ("we do not install").
const SAYS = 'the words in which the company says it does this itself — leave empty if it does not say so, or says it does not';
export const CAPABILITY_KINDS = [
  { key: 'manufacturing', question: `MANUFACTURING or fabricating products: ${SAYS}` },
  { key: 'installation', question: `INSTALLING or executing the work on site: ${SAYS}` },
  { key: 'maintenance', question: `MAINTENANCE, servicing or repair after handover: ${SAYS}` },
  { key: 'design', question: `DESIGN or engineering design: ${SAYS}` },
] as const;
type Kinds = Record<typeof CAPABILITY_KINDS[number]['key'], boolean>;

/** What the capability summary says the company does. Queued when held; the replay records the reading. */
export async function capabilityKinds(deps: ThinkDeps, o: { leadId: number; summary: string; summaryMd5: string }): Promise<Reasoned<Kinds>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'sql.fn_supplier_twin', question: o.summary.slice(0, 4000),
    dedupeKey: `supplier_twin:${o.leadId}:${o.summaryMd5}`, subject: { lead_id: o.leadId, summary_md5: o.summaryMd5 },
    context: { audience: 'internal', conversation: [{ role: 'supplier', text: o.summary.slice(0, 4000) }] },
    decision: { name: 'capabilities', fields: CAPABILITY_KINDS.map((k) => ({ key: k.key, question: k.question })) },
  });
  if (!answered(result)) return { value: null, result };
  return { value: { manufacturing: stated(result, 'manufacturing'), installation: stated(result, 'installation'), maintenance: stated(result, 'maintenance'), design: stated(result, 'design') }, result };
}

/** Which listed service (of the trades the supplier confirmed) does his own word name, if any? */
export async function ownWordService(deps: ThinkDeps, o: { supplierId: number; word: string; candidates: { key: string; label: string }[] }): Promise<Reasoned<string | 'none'>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'sql.fn_supplier_portfolio_gaps', question: o.word.slice(0, 200),
    dedupeKey: `own_word:${o.supplierId}:${o.word.slice(0, 200)}`, subject: { supplier_id: o.supplierId, word: o.word },
    context: { audience: 'internal' },
    decision: {
      name: 'service_named',
      options: [...o.candidates.map((c) => ({ id: c.key, meaning: `the supplier's words name the service "${c.label}"` })),
        { id: 'none', meaning: 'the words name none of these services, or several at once' }],
    },
  });
  return { value: answered(result) ? result.decision?.choice ?? null : null, result };
}

/** Reads what is due for one supplier (fn_supplier_readings_due) and records each reading, reasoned or
 *  queued. Runs after the portal's response (EdgeRuntime.waitUntil), so a page never waits on a model.
 *  `max` bounds the model calls one page view can start. */
export async function readSupplierProfile(deps: ThinkDeps, leadId: number, max = 4): Promise<{ read: number; held: number }> {
  const { data: due, error } = await deps.rpc('fn_supplier_readings_due', { p_lead_id: leadId });
  if (error || !due) return { read: 0, held: 0 };
  let read = 0, held = 0, budget = max;
  if (due.capability && budget-- > 0) {
    const r = await capabilityKinds(deps, { leadId, summary: String(due.capability.summary), summaryMd5: String(due.capability.summary_md5) });
    await deps.rpc('fn_supplier_capability_reading_record', { p_lead_id: leadId, p_summary_md5: due.capability.summary_md5, p_kinds: r.value, p_held_id: r.result.held_id ?? null });
    if (r.value) read++; else held++;
  }
  const candidates = (due.candidates ?? []) as { key: string; label: string }[];
  for (const word of (due.own_words ?? []) as string[]) {
    if (budget-- <= 0) break;
    const r = candidates.length ? await ownWordService(deps, { supplierId: leadId, word, candidates }) : null;
    // No candidate service at all: nothing it could name, so the reading is "none" without a model.
    const reasoned = r === null || r.value !== null;
    await deps.rpc('fn_supplier_own_word_reading_record', {
      p_supplier_id: leadId, p_word: word, p_service_key: r && r.value && r.value !== 'none' ? r.value : null,
      p_reasoned: reasoned, p_held_id: r?.result.held_id ?? null,
    });
    if (reasoned) read++; else held++;
  }
  return { read, held };
}

// ── 45 sql.trg_quote_quality ──────────────────────────────────────────────────────────────────────
/** Which category aspects does the quote state? Reads fn_quote_aspects_due, reasons, records. Held: the
 *  reading is recorded as queued and the quote's category verdict stays 'needs_reasoning' (not a pass). */
export async function reasonQuoteAspects(deps: ThinkDeps, quoteId: string): Promise<{ status: 'none_due' | 'reasoned' | 'held'; present?: string[] }> {
  const { data: due, error } = await deps.rpc('fn_quote_aspects_due', { p_quote_id: quoteId });
  if (error || !due) return { status: 'none_due' };
  const aspects = (due.aspects ?? []) as { aspect: string; label: string; note?: string | null }[];
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'sql.trg_quote_quality', question: String(due.text ?? '').slice(0, 6000),
    dedupeKey: `quote_aspects:${quoteId}:${due.content_md5}`, subject: { quote_id: quoteId, content_md5: due.content_md5 },
    context: { audience: 'internal', trade: String(due.spec_group ?? ''), conversation: [{ role: 'supplier', text: String(due.text ?? '').slice(0, 6000) }] },
    decision: {
      name: 'aspects_stated',
      fields: aspects.map((a) => ({ key: a.aspect, question: `Does the quotation state the ${a.label}${a.note ? ` (${a.note})` : ''}? If so, the words that state it; if not, leave empty.` })),
    },
  });
  const present = answered(result)
    ? aspects.map((a) => a.aspect).filter((k) => stated(result, k))
    : null;
  await deps.rpc('fn_quote_aspect_reading_record', { p_quote_id: quoteId, p_content_md5: due.content_md5, p_present: present, p_held_id: result.held_id ?? null });
  return present ? { status: 'reasoned', present } : { status: 'held' };
}
