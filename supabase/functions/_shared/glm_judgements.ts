// glm_judgements — four judgements moved from code to GLM 5.3 Flash, queued while the model is off.
// Seat: it_engineer (the queue) for the sales_engineer and customer_support call sites. 24 Sep 2026.
// The SQL half (queue, effects): scripts/sql/four_judgements_move_to_glm_and_wait_in_a_queue_while_the_model_is_off.sql.
//
//   quote_spec_match      a ≠ cell of the technical comparison (line_specs/compare.ts decided it is not an exact
//                         match by code) -> is it a GENUINE mismatch (SS304 quoted for SS316) or does it meet the
//                         request? Feeds the comparison report and the quote review (fn_quote_spec_mismatches).
//   repeat_request        below pg_trgm's 0.5, same customer + category within 30 min -> the same job reworded or in
//                         another language, or a different job?
//   supplier_trade_words  the supplier's own words -> EXACT taxonomy_trade codes, or none. Never a nearest guess:
//                         a code outside the taxonomy fails the reading. One exact trade is offered to the supplier to
//                         confirm; several or none leave the proposal pending with the question to ask.
//   unknown_sender_mail   mail from a sender who is no lead, customer or staff -> its category and a summary.
//
// EVERY JUDGEMENT RUNS ON think() WITH THE GLM CLASS FORCED (glmOnly): the decompose and synthesis calls go to
// model_policy routine_employee_reasoning (z-ai/glm-5.3-flash). There is no per-day limit (founder_instruction 987,
// 24 Sep 2026: no caps on LLM spend). HELD — the model hold, a failed reading, an answer
// outside the format — leaves the row queued. Nothing here reads meaning from words: the only string handling is
// parsing the format the model was told to answer in, and exact set membership of taxonomy codes.
import { think, type ThinkDeps } from './think.ts';
import { heldFromGate } from './llm_hold.ts';

export const KINDS = ['quote_spec_match', 'repeat_request', 'supplier_trade_words', 'unknown_sender_mail'] as const;
export type Kind = typeof KINDS[number];
/** The class every non-verify step of these judgements is billed to. Verify is never asked for (stakes normal). */
export const GLM_CLASS = 'routine_employee_reasoning';
/** At most this many ≠ cells in one judgement, so one think() stays inside its 900-token answer. */
export const MAX_CELLS = 12;
export const MAIL_CATEGORIES = ['supplier_document', 'supplier_question', 'customer_question', 'complaint', 'billing', 'partnership', 'spam', 'other'] as const;

export type Row = { id: number; kind: Kind; subject_key: string; input: Record<string, unknown>; attempts: number };
export type SpecCell = { line_no: number; attr: string; requested: string; quoted: string };
export type Outcome =
  | { status: 'done'; result: Record<string, unknown>; model: string | null }
  | { status: 'held'; reason: string; counts: boolean };   // counts = a failed reading (toward the three tries)

/** The same deps with every model step on the GLM class. Verify keeps its class (it must be another family). */
export function glmOnly(deps: ThinkDeps): ThinkDeps {
  return { ...deps, llm: (phase, system, input, o) => deps.llm(phase, system, input, { ...o, taskClass: phase === 'verify' ? o.taskClass : GLM_CLASS }) };
}

const held = (reason: string, counts: boolean): Outcome => ({ status: 'held', reason, counts });
// A think() that came back held for any reason but the model hold made (or tried) paid model calls and failed: that is
// a failed reading and counts toward the three tries. Before 24 Sep review it was deferred uncounted, so a refused
// draft (model_failed) was re-judged every tick for ever - an unbounded paid loop with no customer behind it.
export const heldFrom = (reason: string | undefined): Outcome => held(reason ?? 'held', (reason ?? '') !== 'model_hold');

// WHERE THE VERDICT TRAVELS. think()'s decision FIELDS are extraction only (the value must sit inside words copied
// from the conversation), and a verdict is not an extraction. So each judgement is a decision over OPTIONS (checked
// by think's validator) and its per-item detail is written in the answer in a dictated line format, "key: value".
// Reading that format back is parsing our own contract, not reading meaning; a reply outside it is a failed reading.
/** "key: value" lines of the answer, keys lower-cased. */
export function answerLines(answer: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const l of String(answer ?? '').split('\n')) { const i = l.indexOf(':'); if (i > 0) out[l.slice(0, i).trim().toLowerCase()] = l.slice(i + 1).trim(); }
  return out;
}
/** A cell line is "meets" or "mismatch - <the difference>". Only the leading word is read. */
export function cellVerdict(v: string): 'mismatch' | 'meets' | null {
  const head = String(v ?? '').trim().toLowerCase().split(/[\s:.,-]+/)[0];
  return head === 'mismatch' ? 'mismatch' : head === 'meets' ? 'meets' : null;
}

// ── the four questions ────────────────────────────────────────────────────────────────────────────
async function specMatch(deps: ThinkDeps, input: Record<string, unknown>): Promise<Outcome> {
  const cells = (Array.isArray(input.cells) ? input.cells : []) as SpecCell[];
  if (!cells.length) return { status: 'done', result: { quote_id: input.quote_id, cells: [] }, model: null };
  const listing = cells.map((c, i) => `c${i}: line ${c.line_no}, ${c.attr} - requested "${c.requested}", quoted "${c.quoted}"`).join('\n');
  const r = await think(deps, {
    seat: 'sales_engineer', surface: 'glm.quote_spec_match', queueWhenHeld: false, research: false,
    question: 'For each cell, does the quoted value meet the customer\'s requested specification? Write one line per cell: '
      + '"c<n>: meets" when the quoted value is the same or a grade the customer would accept, or "c<n>: mismatch - <the difference in a few words>" '
      + '(e.g. "c0: mismatch - SS304 quoted, SS316 requested, lower corrosion grade").\n' + listing,
    context: { audience: 'internal', conversation: [{ role: 'seat', text: listing }] },
    decision: { name: 'quote_spec_match', options: [
      { id: 'all_meet', meaning: 'every cell meets the request' },
      { id: 'some_mismatch', meaning: 'at least one cell is a genuine mismatch with the request' }] },
  });
  if (r.status !== 'answered') return heldFrom(r.reason);
  const ln = answerLines(r.answer);
  const out = [];
  for (let i = 0; i < cells.length; i++) {
    const v = ln[`c${i}`] ?? ''; const verdict = cellVerdict(v);
    if (!verdict) return held(`cell c${i} was not answered in the format`, true);
    out.push({ ...cells[i], mismatch: verdict === 'mismatch', why: verdict === 'mismatch' ? v.replace(/^\s*mismatch\s*[-:]?\s*/i, '').slice(0, 300) : null });
  }
  const any = out.some((c) => c.mismatch);
  if (any !== (r.decision?.choice === 'some_mismatch')) return held('the decision and the cell lines disagree', true);
  return { status: 'done', result: { quote_id: input.quote_id, cells: out }, model: r.model ?? null };
}

async function sameRequest(deps: ThinkDeps, input: Record<string, unknown>): Promise<Outcome> {
  const r = await think(deps, {
    seat: 'sales_engineer', surface: 'glm.repeat_request', queueWhenHeld: false, research: false,
    question: 'Is the later request the same job as the earlier one from the same customer?',
    context: { audience: 'internal', conversation: [
      { role: 'customer', text: 'EARLIER: ' + String(input.earlier ?? '') },
      { role: 'customer', text: 'LATER: ' + String(input.later ?? '') }] },
    decision: { name: 'repeat_request', options: [
      { id: 'same', meaning: 'the later request asks for the same job as the earlier one - reworded, shortened, or in another language (English / Arabic)' },
      { id: 'different', meaning: 'the later request is a different job (another item, place, scope or quantity)' }] },
  });
  if (r.status !== 'answered') return heldFrom(r.reason);
  const c = r.decision?.choice;
  if (c !== 'same' && c !== 'different') return held('no option chosen', true);
  return { status: 'done', result: { verdict: c, inquiry_id: input.inquiry_id, earlier_id: input.earlier_id, why: r.answer.slice(0, 300) }, model: r.model ?? null };
}

async function tradeWords(deps: ThinkDeps, input: Record<string, unknown>, taxonomy: { code: string; label: string }[]): Promise<Outcome> {
  if (!taxonomy.length) return held('taxonomy unreadable', false);
  const known = new Set(taxonomy.map((t) => t.code));
  const words = String(input.words ?? '');
  const r = await think(deps, {
    seat: 'sales_engineer', surface: 'glm.supplier_trade_words', queueWhenHeld: false, research: false,
    question: 'Which of our trades do these words of the supplier name? Exact trade or none - never the nearest. '
      + 'Choose the one trade\'s code; "several" when the words name more than one listed trade, then write a line "codes: <code>, <code>"; '
      + '"none" when they name no listed trade. For several or none also write a line "ask: <the one question to put to the supplier>".',
    context: { audience: 'internal', conversation: [{ role: 'supplier', text: words }] },
    decision: { name: 'supplier_trade_words', options: [
      ...taxonomy.map((t) => ({ id: t.code, meaning: t.label })),
      { id: 'several', meaning: 'the words name more than one of the listed trades (e.g. combined MEP)' },
      { id: 'none', meaning: 'the words name none of the listed trades, or are too vague to tell - never the nearest' }] },
  });
  if (r.status !== 'answered') return heldFrom(r.reason);
  const choice = String(r.decision?.choice ?? ''); const ln = answerLines(r.answer);
  let codes: string[] = [];
  if (known.has(choice)) codes = [choice];
  else if (choice === 'several') {
    codes = [...new Set((ln.codes ?? '').split(',').map((s) => s.trim()).filter(Boolean))];
    if (codes.length < 2 || codes.some((c) => !known.has(c))) return held('several named, but not two or more exact taxonomy codes - refused, never guessed', true);
  } else if (choice !== 'none') return held('no option chosen', true);
  return { status: 'done', result: { proposal_id: input.proposal_id, codes, ask: codes.length === 1 ? null : (ln.ask || null) }, model: r.model ?? null };
}

async function mailKind(deps: ThinkDeps, input: Record<string, unknown>): Promise<Outcome> {
  const r = await think(deps, {
    seat: 'customer_support', surface: 'glm.unknown_sender_mail', queueWhenHeld: false, research: false,
    question: 'What kind of email is this, from a sender we do not know? Choose its category; the answer is one factual sentence on what the sender wants.',
    context: { audience: 'internal', conversation: [{ role: 'visitor', text: `From: ${input.from ?? ''}\nSubject: ${input.subject ?? ''}\n\n${String(input.body ?? '').slice(0, 4000)}` }] },
    decision: { name: 'unknown_sender_mail', options: MAIL_CATEGORIES.map((c) => ({ id: c, meaning: c.replace(/_/g, ' ') })) },
  });
  if (r.status !== 'answered') return heldFrom(r.reason);
  const c = r.decision?.choice ?? '';
  if (!(MAIL_CATEGORIES as readonly string[]).includes(c)) return held('no category chosen', true);
  return { status: 'done', result: { category: c, summary: r.answer.slice(0, 500), message_id: input.message_id }, model: r.model ?? null };
}

// ── one row ───────────────────────────────────────────────────────────────────────────────────────
/** Judge one queued row: the model hold first (waiting is not a failure), then GLM. Never throws. */
export async function judge(deps: ThinkDeps, row: Row, taxonomy: () => Promise<{ code: string; label: string }[]>): Promise<Outcome> {
  try {
    // The hold is asked first: while the model is off the row waits and no try is counted.
    let gate = null; try { gate = await deps.gate(); } catch (_e) { gate = null; }
    if (heldFromGate(gate)) return held('model_hold', false);
    const d = glmOnly(deps);
    switch (row.kind) {
      case 'quote_spec_match': return await specMatch(d, row.input);
      case 'repeat_request': return await sameRequest(d, row.input);
      case 'supplier_trade_words': return await tradeWords(d, row.input, await taxonomy());
      case 'unknown_sender_mail': return await mailKind(d, row.input);
      default: return held('unknown kind', true);
    }
  } catch (e) { return held('error: ' + String((e as Error)?.message ?? e).slice(0, 200), true); }
}

/** Take up to `limit` due rows (optionally only `ids`), judge each, and record the answer or defer the row. */
export async function drain(deps: ThinkDeps, limit = 5, ids: number[] | null = null): Promise<{ done: number; held: number; failed_reading: number }> {
  const out = { done: 0, held: 0, failed_reading: 0 };
  const due = await deps.rpc('fn_glm_judgement_due', { p_limit: limit, p_ids: ids });
  if (due.error || !Array.isArray(due.data)) return out;
  let tax: { code: string; label: string }[] | null = null;
  const taxonomy = async () => {
    if (tax) return tax;
    const r = await deps.rpc('fn_glm_taxonomy_trades', {});
    tax = Array.isArray(r.data) ? r.data as { code: string; label: string }[] : [];
    return tax;
  };
  for (const row of due.data as Row[]) {
    const o = await judge(deps, row, taxonomy);
    if (o.status === 'done') { await deps.rpc('fn_glm_judgement_resolve', { p_id: row.id, p_result: o.result, p_model: o.model }); out.done++; }
    else { await deps.rpc('fn_glm_judgement_defer', { p_id: row.id, p_error: o.reason, p_counts: o.counts }); if (o.counts) out.failed_reading++; else out.held++; }
  }
  return out;
}

/** The ≠ cells of one quote from a technical comparison, chunked into judgement inputs (code decides ≠; GLM judges). */
// deno-lint-ignore no-explicit-any
export function differingCells(technical: any, quoteId: string): SpecCell[] {
  const cells: SpecCell[] = [];
  for (const line of technical?.lines ?? []) for (const a of line?.attributes ?? []) {
    if (!a?.requested) continue;
    for (const c of a.cells ?? []) if (c?.quote_id === quoteId && c.flag === 'differs' && c.value)
      cells.push({ line_no: Number(line.request_line?.line_no ?? line.row), attr: String(a.label_en ?? a.code), requested: String(a.requested), quoted: String(c.value) });
  }
  return cells;
}
export function chunks<T>(xs: T[], n = MAX_CELLS): T[][] { const o: T[][] = []; for (let i = 0; i < xs.length; i += n) o.push(xs.slice(i, i + n)); return o; }
