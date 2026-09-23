// reasoned_intake — the sales engineer's decision points on intake and quotations, migrated off word
// lists onto think(). Seat: sales_engineer. 23 Sep 2026, founder_instruction 886-903 (ledger 890: no word
// matching anywhere). Batch B4 of decision_points.json: orders 31-38.
//
// Each function asks think() one decision — named options, or fields filled only with the person's own
// words (the validator refuses a value it cannot find verbatim) — and returns the value or null:
//   * a value  — reasoned (models live);
//   * null     — held: the question is filed in the sales engineer's queue and replayed when the hold
//                lifts. The CALLER does the safe thing (asks, holds, answers from data). Never a keyword
//                guess. What each caller does under the hold is written in decision_points.json `held`.
// Pure format parsing (a number's digits, an ISO date, a unit spelling) stays in the callers; what text
// MEANS is decided here. Where the portal can offer a structured choice (a tapped option, a button, a
// select), the caller takes that first and asks nothing.
import { think, type ThinkDeps, type ThinkResult } from './think.ts';

export type Reasoned<T> = { value: T | null; result: ThinkResult };
export type Stated = Record<string, { value: string; evidence: string }>;
type Opt = { id: string; meaning: string };
type Field = { key: string; question: string };
const answered = (r: ThinkResult) => r.status === 'answered';
const fieldsOf = (r: ThinkResult): Stated => (answered(r) ? r.decision?.fields ?? {} : {});
const choiceOf = (r: ThinkResult) => (answered(r) ? r.decision?.choice ?? null : null);

// ── 34 classify.urgency_emirate ─────────────────────────────────────────────────────────────────────
export const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Fujairah', 'Umm Al Quwain', 'Al Ain'] as const;
export const NOT_STATED = 'not_stated';

/** Which emirate is the job in, as the customer said it (any language, any spelling)? not_stated when they have not said. */
export async function emirateOf(deps: ThinkDeps, o: { conversation: string; dedupeKey?: string; subject?: Record<string, unknown> }): Promise<Reasoned<string>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'classify.urgency_emirate', question: o.conversation.slice(0, 4000), dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'customer' },
    decision: { name: 'emirate', options: [
      ...EMIRATES.map((e) => ({ id: e, meaning: e === 'Al Ain' ? 'the job is in Al Ain (the Al Ain region of Abu Dhabi emirate)' : `the job is in ${e}` })),
      { id: NOT_STATED, meaning: 'the customer has not said where the job is, or only named a place whose emirate cannot be known from what they wrote' },
    ] },
  });
  return { value: choiceOf(result), result };
}

/** How soon must someone act: a safety risk or active damage, within about 48 hours, or neither? */
export async function urgencyOf(deps: ThinkDeps, o: { conversation: string; dedupeKey?: string; subject?: Record<string, unknown> }): Promise<Reasoned<'emergency' | 'urgent' | 'normal'>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'classify.urgency_emirate', question: o.conversation.slice(0, 4000), dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'customer' },
    decision: { name: 'urgency', options: [
      { id: 'emergency', meaning: 'a safety risk or damage happening now (a gas leak, flooding, a burst pipe, no power, sparking)' },
      { id: 'urgent', meaning: 'they need someone within about 48 hours, however they word it' },
      { id: 'normal', meaning: 'anything else, including a job with a date weeks away or no date at all' },
    ] },
  });
  const c = choiceOf(result);
  return { value: c === 'emergency' || c === 'urgent' || c === 'normal' ? c : null, result };
}

// ── 33 interview.answers ────────────────────────────────────────────────────────────────────────────
/** Which of the category's questions has the customer ALREADY answered, in their own words? */
export async function interviewAnswers(deps: ThinkDeps, o: {
  conversation: string; fields: { key: string; question: string; options?: string[] | null }[]; category: string; dedupeKey?: string; subject?: Record<string, unknown>;
}): Promise<Reasoned<Stated>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'interview.answers', question: o.conversation.slice(0, 4000), dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'customer', trade: o.category, conversation: [{ role: 'customer', text: o.conversation.slice(0, 4000) }] },
    decision: { name: 'interview_answers', fields: o.fields.map((f) => ({ key: f.key, question: f.question + (f.options?.length ? ` (the offered answers: ${f.options.join(' | ')})` : '') })) },
  });
  return { value: answered(result) ? fieldsOf(result) : null, result };
}

// ── 32 intake_requirements.parse ────────────────────────────────────────────────────────────────────
/** The sales engineer's question (installation, warranty, material, date), as think() is asked it. */
export type ReqAsk = { key: string; question: string; options: Opt[]; fields?: Field[] };
export const NOT_ANSWERED = 'not_answered';
/**
 * Does the conversation answer this one question, and with which option? `fields` carry the free part an
 * option needs (a material in the customer's own words, a date as they wrote it, a warranty period).
 */
export async function requirementAnswer(deps: ThinkDeps, o: { ask: ReqAsk; conversation: string; justAsked: boolean; dedupeKey?: string; subject?: Record<string, unknown> }): Promise<Reasoned<{ choice: string; fields: Stated }>> {
  const lead = o.justAsked ? 'The customer\'s LAST message replies to this question. ' : 'Has the customer already answered this question anywhere in the conversation? ';
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'intake_requirements.parse', question: `${lead}Question: ${o.ask.question}`, dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'customer', conversation: [{ role: 'customer', text: o.conversation.slice(0, 4000) }] },
    decision: { name: o.ask.key, options: [...o.ask.options, { id: NOT_ANSWERED, meaning: 'the conversation does not answer this question (a reply about something else, or no reply yet)' }], fields: o.ask.fields },
  });
  const c = choiceOf(result);
  return { value: c ? { choice: c, fields: fieldsOf(result) } : null, result };
}

// ── 35 sales_engineer.brief_trades ──────────────────────────────────────────────────────────────────
/** Which of the taxonomy's trades does this brief ask for? A trade is in the set only with the brief's own words as evidence. */
export async function briefTrades(deps: ThinkDeps, o: { brief: string; trades: { code: string; label: string }[]; dedupeKey?: string; subject?: Record<string, unknown> }): Promise<Reasoned<string[]>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'sales_engineer.brief_trades', question: o.brief.slice(0, 4000), dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'customer', conversation: [{ role: 'customer', text: o.brief.slice(0, 4000) }] },
    decision: { name: 'trades', fields: o.trades.map((t) => ({ key: t.code, question: `the customer's words that ask for ${t.label} work or supply (only if they do)` })) },
  });
  const codes = new Set(o.trades.map((t) => t.code));
  return { value: answered(result) ? Object.keys(fieldsOf(result)).filter((k) => codes.has(k)) : null, result };
}

// ── 36 line_specs.options_derive_vat ────────────────────────────────────────────────────────────────
export type VatBasis = 'exclusive' | 'inclusive' | 'not_registered';
/** What the supplier's words say about VAT: prices exclude it, include it, the supplier is not registered, or nothing. */
export async function vatBasis(deps: ThinkDeps, o: { text: string; dedupeKey?: string; subject?: Record<string, unknown> }): Promise<Reasoned<VatBasis | 'not_stated'>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'line_specs.options_derive_vat', question: o.text.slice(0, 4000), dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'supplier' },
    decision: { name: 'vat_basis', options: [
      { id: 'exclusive', meaning: 'the prices are stated before VAT / VAT is extra, however worded' },
      { id: 'inclusive', meaning: 'the prices already include VAT' },
      { id: 'not_registered', meaning: 'the supplier is not VAT-registered, or no VAT applies to them' },
      { id: 'not_stated', meaning: 'the text says nothing about VAT, or is unclear about it' },
    ] },
  });
  const c = choiceOf(result);
  return { value: c === 'exclusive' || c === 'inclusive' || c === 'not_registered' || c === 'not_stated' ? c : null, result };
}

/** A quote form's own text: brand / model / specification per line, the exclusions and whether installation is included — only where the supplier wrote them. */
export async function quoteTextFacts(deps: ThinkDeps, o: { lines: { n: number; description: string }[]; scope: string; dedupeKey?: string; subject?: Record<string, unknown> }): Promise<Reasoned<Stated>> {
  const text = [...o.lines.map((l) => `Line ${l.n}: ${l.description}`), o.scope ? `Scope: ${o.scope}` : ''].filter(Boolean).join('\n').slice(0, 6000);
  const fields: Field[] = [
    ...o.lines.flatMap((l) => [
      { key: `line_${l.n}_brand`, question: `the brand or manufacturer line ${l.n} states` },
      { key: `line_${l.n}_model`, question: `the model, product or range line ${l.n} states` },
      { key: `line_${l.n}_specification`, question: `the specification line ${l.n} states` },
    ]),
    { key: 'exclusions', question: 'what the scope says is excluded / not included' },
    { key: 'installation_included', question: 'the words of the scope saying installation IS included in the price (only if it says so)' },
  ];
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'line_specs.options_derive_vat', question: 'Read what this quotation form states.', dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'supplier', conversation: [{ role: 'supplier', text }] },
    decision: { name: 'quote_text_facts', fields },
  });
  return { value: answered(result) ? fieldsOf(result) : null, result };
}

// ── 37 drawing_boq.vocabulary ───────────────────────────────────────────────────────────────────────
/**
 * A drawing's own words, read by meaning: which printed text (a legend entry, a CAD block name) names each
 * device type, what kind of drawing the title says it is, which printed labels are rooms. Every value is
 * text copied from the drawing, so the parser consumes it by exact lookup.
 */
export async function drawingVocabulary(deps: ThinkDeps, o: {
  texts: string[]; types: { type: string; en: string }[]; title?: string | null; dedupeKey?: string; subject?: Record<string, unknown>;
}): Promise<Reasoned<Stated>> {
  const text = [o.title ? `TITLE: ${o.title}` : '', ...o.texts.slice(0, 200)].filter(Boolean).join('\n').slice(0, 8000);
  const fields: Field[] = [
    ...o.types.map((t) => ({ key: `device:${t.type}`, question: `the printed text (legend entry or block name) that names a ${t.en}` })),
    ...(o.title ? [{ key: 'drawing_type', question: 'the words of the TITLE that say what kind of drawing it is (e.g. a fire alarm layout)' }] : []),
    ...Array.from({ length: 12 }, (_, i) => ({ key: `room:${i + 1}`, question: `the ${i + 1}${['st', 'nd', 'rd'][i] ?? 'th'} distinct room or space name printed on the plan` })),
  ];
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'drawing_boq.vocabulary', question: 'Read what this drawing names.', dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'internal', conversation: [{ role: 'customer', text }] },
    decision: { name: 'drawing_vocabulary', fields },
  });
  return { value: answered(result) ? fieldsOf(result) : null, result };
}

/** A drawing set's keyed notes: which instruct work to be done (provide, install, replace ...), as opposed to "to remain" or a
 *  reference, and which of those remove or demolish. Keys are '<sheet>:<n>'. */
export async function scopeNotes(deps: ThinkDeps, o: { notes: { key: string; text: string }[]; dedupeKey?: string; subject?: Record<string, unknown> }): Promise<Reasoned<{ scope: string[]; demolish: string[] }>> {
  const notes = o.notes.slice(0, 60);
  const text = notes.map((x) => `Note ${x.key}: ${x.text}`).join('\n').slice(0, 8000);
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'drawing_boq.vocabulary', question: 'Which keyed notes instruct work to be done, and which of those remove or demolish?', dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'internal', conversation: [{ role: 'customer', text }] },
    decision: { name: 'scope_notes', fields: notes.flatMap((x) => [
      { key: `scope|${x.key}`, question: `the words of note ${x.key} that instruct work to be done (only if it does; not "to remain", "existing", or a reference)` },
      { key: `demolish|${x.key}`, question: `the words of note ${x.key} saying something is removed or demolished (only if it says so)` },
    ]) },
  });
  if (!answered(result)) return { value: null, result };
  const f = Object.keys(fieldsOf(result));
  return { value: { scope: f.filter((k) => k.startsWith('scope|')).map((k) => k.slice(6)), demolish: f.filter((k) => k.startsWith('demolish|')).map((k) => k.slice(9)) }, result };
}

// ── 38 service_rewrite.install ──────────────────────────────────────────────────────────────────────
/**
 * Which of a trade's catalogue services are installation / contracting / after-sales WORK, as opposed to supply?
 * One decision per trade: 975 active services in 195 trades, at most 10 in one (measured on production 23 Sep 2026),
 * so 195 reasonings rather than 975.
 * A service is work only with the words of its own name as evidence; a service not named is supply. The same
 * request is queued by SQL for every trade with an unreasoned service (fn_service_install_queue in
 * scripts/sql/the_sales_engineer_reasons_intake_and_quotations_instead_of_matching_words.sql — keep the two equal)
 * and applied to taxonomy_trade_service.install_work by fn_reason_apply_service_rewrite__install.
 */
export function serviceInstallRequest(o: { trade_code: string; services: { code: string; label_en: string }[] }) {
  return {
    seat: 'sales_engineer' as const, surface: 'service_rewrite.install',
    question: `Which of these ${o.trade_code} services are work done on site or after sale?`,
    dedupeKey: 'service_install:' + o.trade_code, subject: { trade_code: o.trade_code },
    context: { audience: 'internal' as const, conversation: [{ role: 'seat' as const, text: o.services.map((x) => `${x.code}: ${x.label_en}`).join('\n') }] },
    decision: { name: 'install_work', fields: o.services.map((x) => ({ key: x.code, question: `the words of "${x.label_en}" that make it installation, contracting, maintenance, design or approvals work a company that only sells goods does not do (only if it is such work, and not a supply service)` })) },
  };
}
export async function serviceInstallWork(deps: ThinkDeps, o: { trade_code: string; services: { code: string; label_en: string }[] }): Promise<Reasoned<Record<string, boolean>>> {
  const result = await think(deps, serviceInstallRequest(o));
  if (!answered(result)) return { value: null, result };
  const work = new Set(Object.keys(fieldsOf(result)));
  return { value: Object.fromEntries(o.services.map((x) => [x.code, work.has(x.code)])), result };
}

// ── 31 supplier_api.quote_review_match ──────────────────────────────────────────────────────────────
/** Which of the supplier's quotation lines prices each BOQ line? Values are "Line N" copied from the listing. */
export async function boqMatch(deps: ThinkDeps, o: { boq: { n: number; description: string; qty?: string; unit?: string }[]; lines: { n: number; description: string }[]; dedupeKey?: string; subject?: Record<string, unknown> }): Promise<Reasoned<Record<string, number>>> {
  const listing = o.lines.map((l) => `Line ${l.n}: ${l.description}`).join('\n').slice(0, 6000);
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'supplier_api.quote_review_match', question: 'Which of the supplier\'s lines prices each BOQ line?', dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'internal', conversation: [{ role: 'supplier', text: listing }] },
    decision: { name: 'boq_match', fields: o.boq.map((b) => ({ key: `boq_${b.n}`, question: `the supplier line ("Line N: ...", copied) that prices BOQ line ${b.n}: ${b.description}${b.qty ? ` — ${b.qty} ${b.unit ?? ''}` : ''} (only if one does)` })) },
  });
  if (!answered(result)) return { value: null, result };
  const out: Record<string, number> = {};
  const taken = new Set<number>();
  for (const [k, v] of Object.entries(fieldsOf(result))) {
    // Format: the value is the listing's own "Line N" label, copied verbatim.
    const n = Number(/^boq_(\d+)$/.exec(k)?.[1]); const j = Number(/^\s*line\s+(\d+)\b/i.exec(v.value)?.[1] ?? /^\s*line\s+(\d+)\b/i.exec(v.evidence)?.[1]);
    if (Number.isInteger(n) && Number.isInteger(j) && o.lines.some((l) => l.n === j) && !taken.has(j)) { out[String(n)] = j; taken.add(j); }
  }
  return { value: out, result };
}

/** A supplier's reply in the quotation chat: which open points it answers, in the supplier's own words. */
export async function supplierReply(deps: ThinkDeps, o: { text: string; points: Field[]; dedupeKey?: string; subject?: Record<string, unknown> }): Promise<Reasoned<Stated>> {
  const result = await think(deps, {
    seat: 'sales_engineer', surface: 'supplier_api.quote_review_reply', question: o.text.slice(0, 4000), dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'supplier', conversation: [{ role: 'supplier', text: o.text.slice(0, 4000) }] },
    decision: { name: 'supplier_reply', fields: o.points },
  });
  return { value: answered(result) ? fieldsOf(result) : null, result };
}

/** A supplier's question in the quotation chat, answered by the sales engineer from the job's open points. */
export async function supplierQuestion(deps: ThinkDeps, o: { question: string; open: string[]; job: string; language: 'en' | 'ar'; dedupeKey?: string; subject?: Record<string, unknown> }): Promise<ThinkResult> {
  return await think(deps, {
    seat: 'sales_engineer', surface: 'supplier_api.quote_review_question', question: o.question.slice(0, 2000), dedupeKey: o.dedupeKey, subject: o.subject,
    context: { audience: 'supplier', language: o.language, case: { job: o.job, open_points: o.open.slice(0, 20),
      rules: 'The customer compares prices excluding VAT and never sees the supplier\'s VAT details, TRN or identity; the customer\'s identity stays private until they reveal a quotation; a business below AED 375,000 is not VAT-registered and needs no TRN.' } },
  });
}
