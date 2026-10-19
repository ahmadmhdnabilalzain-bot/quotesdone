// reasoned_suppliers — the sales engineer's decision points on prices, supplier profiles and quotations,
// moved off word lists onto think(). Seat: sales_engineer. 23 Sep 2026, founder_instruction 886-903
// (batch B5 of decision_points.json: orders 39-46, and 84-87 found by the batch).
//
// Each function asks think() one question and returns { value | null, result } (reasoned_decisions.ts'
// shape). null means HELD (the founder's model hold, or a model that failed): the caller does the safe,
// non-committal thing, never a keyword guess. Where the answer has an effect in the database, the held
// question is queued under its surface and fn_reason_apply_<surface> (scripts/sql/
// prices_supplier_profiles_and_quote_quality_are_read_by_reasoning.sql) applies it when the hold lifts.
import { readerOfTheirOwnText, think, type ThinkDeps } from './think.ts';
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
    // THE CHOICE IS OVER THE LIST GIVEN HERE, so there is nothing to plan or retrieve: no decompose call (12 Oct 2026,
    // customer_support — this ran beside every widget reply and, at two serial calls, was its slowest leg: 14-21 s).
    plan: { steps: [] },
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

// THE PRE-FILTER DECIDES ONLY WHETHER TO SPEND A REASONING CALL, NEVER THE ANSWER (#888 review: every chat
// message and public request paid for a think()). The question is embedded (gte-small, free, in-region) and
// compared with a few price-question exemplars in both languages; below the floor, no reasoning is spent and
// the caller treats it as "no price block" — exactly what it does under the hold. Above it, the REASONING
// decides whether it is a price question at all and which trade. A miss costs one price block, never a
// wrong price. PRICE_PREFILTER_FLOOR is a calibration knob, NOT measured for these exemplars: 0.80 sits at
// the bottom of the band think.ts measured for gte-small (paraphrases 0.847-0.924, unrelated 0.760-0.816),
// chosen to let a paraphrase through and spend a call on some unrelated questions rather than miss one.
export const PRICE_EXEMPLARS = [
  'how much does it cost', 'what is the price per square metre', 'what should this job cost in Dubai',
  'give me a price range for the work', 'what is the rate for supply and installation',
  'كم تكلفة هذا العمل', 'ما هو سعر المتر المربع', 'كم يكلف التركيب في دبي',
];
export const PRICE_PREFILTER_FLOOR = 0.80;
/** Per sender, per hour: price reasonings one address or account may start (rl_check). */
export const PRICE_REASONING_PER_HOUR = 20;
const cos = (a: number[], b: number[]) => { let d = 0, x = 0, y = 0; for (let i = 0; i < a.length; i++) { d += a[i] * b[i]; x += a[i] * a[i]; y += b[i] * b[i]; } return x && y ? d / Math.sqrt(x * y) : 0; };
// One gte-small vector per exemplar, kept for the life of the worker (the model is fixed; the text is ours).
const exemplarVecs = new Map<string, number[]>();
async function plausiblyAPriceQuestion(deps: ThinkDeps, question: string): Promise<boolean | null> {
  const q = await deps.embed(question.slice(0, 500)).catch(() => null);
  if (!q) return null;
  for (const e of PRICE_EXEMPLARS) if (!exemplarVecs.has(e)) { const v = await deps.embed(e).catch(() => null); if (v) exemplarVecs.set(e, v); }
  const vs = [...exemplarVecs.values()];
  if (!vs.length) return null;
  return Math.max(...vs.map((v) => cos(q, v))) >= PRICE_PREFILTER_FLOOR;
}

/** The trades we publish for, then the reasoned trade, then the bands: the whole price answer for a caller
 *  that has only the visitor's words. Held -> { reason: 'held' }. `sender` (an address or account) is
 *  rate-limited per hour before any reasoning is spent. */
export async function priceGuidanceFor(deps: ThinkDeps, question: string, limit = 6, audience?: 'visitor' | 'customer' | 'supplier', sender = 'unknown') {
  const rpc = deps.rpc;
  // Without an embedding (the embedder failed) the pre-filter cannot say no, so it lets the reasoning decide.
  if ((await plausiblyAPriceQuestion(deps, question)) === false) return { ok: false, reason: 'not_a_price_question', prefilter: true };
  const { data: allowed } = await rpc('rl_check', { p_key: 'price_reasoning:' + sender, p_limit: PRICE_REASONING_PER_HOUR, p_seconds: 3600 });
  if (allowed === false) return { ok: false, reason: 'rate_limited' };
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

// ── 84 sql.fn_os_catalog_test_gate (45 sql.trg_quote_quality is structural since 24 Sep 2026) ─────────────────────────────────────
type Aspect = { aspect: string; label: string; note?: string | null };
/** Which of these category aspects does the text state? Used by the catalogue test gate. Present = a value AND the words that state it. */
export async function aspectsStated(deps: ThinkDeps, o: { surface: string; text: string; aspects: Aspect[]; trade?: string; queueWhenHeld?: boolean; dedupeKey?: string; subject?: Record<string, unknown> }): Promise<Reasoned<string[]>> {
  const text = o.text.slice(0, 8000);
  const result = await think(deps, {
    seat: 'sales_engineer', surface: o.surface, question: text, queueWhenHeld: o.queueWhenHeld, dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'internal', trade: o.trade ?? null, conversation: [{ role: 'supplier', text }] },
    decision: {
      name: 'aspects_stated',
      fields: o.aspects.map((a) => ({ key: a.aspect, question: `Does the quotation state the ${a.label}${a.note ? ` (${a.note})` : ''}? If so, the words that state it; if not, leave empty.` })),
    },
  });
  return { value: answered(result) ? o.aspects.map((a) => a.aspect).filter((k) => stated(result, k)) : null, result };
}

/** The catalogue test gate over a sample: the aspects of the category (fn_os_catalog_test_gate with none
 *  present), the reasoned reading of the sample, then the verdict. Not queued: an admin test has nobody to
 *  deliver a late verdict to. Held -> { held: true }, never a verdict from matching the sample's words. */
export async function catalogTestGate(deps: ThinkDeps, category: string, sample: string) {
  const { data: empty, error } = await deps.rpc('fn_os_catalog_test_gate', { p_category: category, p_present: [] });
  if (error || !empty) return { ok: false, reason: 'unavailable' };
  const aspects = (empty.aspects ?? []) as Aspect[];
  if (!aspects.length || !sample.trim()) return empty;
  const r = await aspectsStated(deps, { surface: 'sql.fn_os_catalog_test_gate', text: sample, aspects, trade: category, queueWhenHeld: false });
  if (!r.value) return { ok: false, reason: 'held', held: true };
  const { data } = await deps.rpc('fn_os_catalog_test_gate', { p_category: category, p_present: r.value });
  return data;
}

// ── 86 sql.fn_org_task_consume_tick (its price branch and its FAQ lexemes) ──────────────────────────
/** Reads the knowledge-gap tasks whose QUESTION has no reading (fn_org_task_questions_due) and records, per
 *  question, which published trade price or which approved public FAQ answers it, or neither. The FAQ
 *  candidates are the nearest by meaning (gte-small, fn_org_task_question_candidates): a shortlist only, the
 *  reasoning chooses. Held: recorded as queued; fn_reason_apply_sql__fn_org_task_consume_tick records the
 *  answer when the hold lifts, and the tick parks the task meanwhile. Run by resilience_ping. */
export async function reasonOrgTaskQuestions(deps: ThinkDeps, limit = 3): Promise<{ read: number; held: number }> {
  const { data: due, error } = await deps.rpc('fn_org_task_questions_due', { p_limit: limit });
  if (error || !due) return { read: 0, held: 0 };
  const trades = (due.trades ?? []) as string[];
  let read = 0, held = 0;
  for (const q of (due.questions ?? []) as { task_id: number; question: string; question_md5: string }[]) {
    const e = await deps.embed(q.question.slice(0, 500)).catch(() => null);
    const faqs = e ? ((await deps.rpc('fn_org_task_question_candidates', { p_embedding: '[' + e.join(',') + ']', p_k: 8 })).data ?? []) as { id: number; question: string }[] : [];
    const result = await think(deps, {
      seat: 'sales_engineer', surface: 'sql.fn_org_task_consume_tick', question: q.question.slice(0, 2000),
      dedupeKey: `org_task_q:${q.task_id}:${q.question_md5}`, subject: { task_id: q.task_id, question_md5: q.question_md5 },
      context: { audience: 'customer' },
      decision: {
        name: 'what_answers_it',
        options: [
          ...trades.map((t) => ({ id: 'price:' + t, meaning: `it asks what ${t.replace(/-/g, ' ')} work or material costs` })),
          ...faqs.map((f) => ({ id: 'faq:' + f.id, meaning: `this approved FAQ answers it: "${f.question.slice(0, 200)}"` })),
          { id: 'neither', meaning: 'none of these answers it' },
        ],
      },
    });
    const choice = answered(result) ? result.decision?.choice ?? 'neither' : null;
    await deps.rpc('fn_org_task_question_reading_record', { p_task_id: q.task_id, p_question_md5: q.question_md5, p_choice: choice, p_reasoned: choice !== null, p_held_id: result.held_id ?? null });
    if (choice !== null) read++; else held++;
  }
  return { read, held };
}
