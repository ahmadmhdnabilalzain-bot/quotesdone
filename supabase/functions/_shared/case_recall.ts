// "WE DID THAT BEFORE — WHAT DID WE DO, WAS IT FINALISED?" Seat: it_engineer (shared platform). 23 Sep 2026.
//
// The founder, 23 Sep 2026: a seat that meets a case like one it handled before must remember it, the
// way a real employee does, and it must be structural for every seat. Standing rule: by MEANING, never
// by word matching. This is the one call every seat makes BEFORE it decides:
//
//   const memory = await recallCases(admin, { seat, path, situation, trade });
//
// It embeds the situation with the in-runtime gte-small session (free, in-region, not OpenRouter —
// gte_embed.ts) and asks public.fn_case_recall for the nearest past cases above the measured floor
// (0.84; paraphrases scored 0.847-0.924, unrelated cases 0.760-0.816 — the SQL file carries the
// numbers). The cases come back masked: another customer's name, e-mail or phone never leaves here.
//
// WHAT THE SEAT MUST DO WITH IT: `memory.rule` is the instruction. Where a FINALISED prior case exists
// the seat references it by its case number, or states why this case differs. A model path puts
// `precedentBlock(memory)` into its system prompt; a deterministic path returns `memory` as evidence
// in its answer. When the vector cannot be computed the result says so (available:false) — it never
// pretends there was nothing to remember.
//
// scripts/checks/every_seat_recalls_before_it_decides.test.mjs fails if a decision path loses its call.
//
// TWO SPACES (23 Sep 2026). When fn_ml_read_space answers 'ml', the situation is embedded with
// multilingual-e5-small by the embed_ml function (ml_embed_client.ts: the model never loads in this worker) and put to fn_case_recall_ml, so an Arabic situation meets its English
// precedent. A vector a caller passes in `embedding` is a gte-small vector (every caller computes it with
// embedLine for its own gte knowledge search), so it is used only on the gte path. If the multilingual
// embedder cannot answer, the call falls back to gte-small and fn_case_recall.
import { embedLine } from './gte_embed.ts';
import { embedQueryMlRemote, readSpace } from './ml_embed_client.ts';

export type RecalledCase = {
  case_id: number; seat: string; case_kind: string; trade: string | null; situation: string;
  decision: string | null; reasoning: string | null; outcome: string | null; finalised: boolean;
  finalised_at: string | null; lessons: string[]; correction: string | null; corrected_by: string | null;
  similarity: number; opened_at: string; source: string | null;
};
export type CaseMemory = {
  seat: string; path: string; available: boolean; reason?: string;
  cases: RecalledCase[]; finalised_precedent: boolean; rule: string | null;
  judgement_id?: number | null;   // the seat_judgement row this recall opened (the outcome lands on it)
  handoffs?: HandoffNote[];       // open handoffs to this seat on this case, each with its note - read FIRST
};
// THE HANDOFF NOTE (founder instruction 1013 item 6, 29 Sep 2026). Every handoff carries detail.summary -
// known / tried / needed / evidence - built by code from the case's rows (scripts/sql/
// every_handoff_carries_a_note_of_what_is_known_tried_and_needed.sql). The receiving seat reads it
// before its past cases, the way a colleague reads the note on the file before anything else.
export type HandoffNote = {
  handoff_id: number; from: string | null; conversation: string | null; opened_at: string; status: string;
  summary: {
    // ledger 1013 (19 Oct 2026): the four fields every note states, built by code in fn_handoff_summary
    context?: string; decision?: string; open_asks?: string[]; deadline?: string; deadline_source?: string;
    known: Record<string, unknown>; tried: Record<string, unknown>; needed: Record<string, unknown>; evidence: string[];
  };
};

export const RECALL_EMBED_MS = 1500;
// The gateway may be loading the multilingual model on a cold worker; past this the call takes the gte path.
export const RECALL_EMBED_ML_MS = 8000;

export function precedentRule(cases: RecalledCase[]): string | null {
  const fin = cases.filter((c) => c.finalised);
  if (fin.length) {
    return `A finalised prior case exists (${fin.map((c) => '#' + c.case_id).join(', ')}). Reference it by its number and follow what was decided, or state plainly why this case differs.`;
  }
  if (cases.length) {
    return `A similar prior case was started but never finalised (${cases.map((c) => '#' + c.case_id).join(', ')}). Say so, and do not treat its unfinished decision as settled.`;
  }
  return null;
}

// deno-lint-ignore no-explicit-any
type Rpc = { rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: any; error: { message: string } | null }> };

export async function recallCases(admin: Rpc, o: {
  seat: string; path: string; situation: string; trade?: string | null; k?: number;
  caseKind?: string | null; otherSeats?: boolean; exclude?: { table: string; id: string } | null;
  embedding?: number[] | string | null;
  embeddingMl?: number[] | null;              // a multilingual vector the caller already has: recalled in the ml space
  // The caller's own embedder (ThinkDeps.embed). Given, the recall never runs gte-small in this worker: both spaces are
  // asked of it, so a heartbeat caller (heartbeatDeps, gte-small in embed_ml) keeps its 2 s CPU cap even when the
  // multilingual call fails and the recall falls back to gte. Absent, the recall embeds as it always did.
  embed?: (text: string, space?: 'gte' | 'ml') => Promise<number[] | null>;
  subject?: Record<string, unknown> | null;   // what the judgement is about; defaults to `exclude`
  record?: boolean;                           // default true: every recall opens its judgement row
}): Promise<CaseMemory> {
  const m = await recallOnly(admin, o);
  m.handoffs = await handoffNotes(admin, o.seat, o.subject ?? (o.exclude ? { table: o.exclude.table, id: o.exclude.id } : null));
  if (o.record === false) return m;
  // THE RECALL RECORD (learning loop, 23 Sep 2026). Every judgement a seat makes is opened here WITH the
  // memory it recalled, so its real outcome can be written back onto it and the seat's accuracy measured
  // (scripts/sql/every_judgement_learns_from_its_outcome.sql). Recording never fails the decision.
  try {
    const subject = o.subject ?? (o.exclude ? { table: o.exclude.table, id: o.exclude.id } : null);
    const { data, error } = await admin.rpc('fn_judgement_record', {
      p_seat: o.seat, p_surface: o.path, p_subject: subject, p_question: String(o.situation || '').slice(0, 2000), p_recall: recallTrace(m),
    });
    m.judgement_id = error ? null : Number(data) || null;
  } catch (_e) { m.judgement_id = null; }
  return m;
}

/** THE JUDGEMENT IS OPENED, NOTHING IS RECALLED (it_engineer, 10 Nov 2026, WhatsApp latency R4/R5). For a caller whose
 *  reasoning could not use a recalled case anyway (think(): a lean choice among fixed options for an external audience,
 *  where another party's case never reaches the prompt), the learning loop's row is still opened, with a recall trace that
 *  says why nothing was recalled; the embedding and the recall routines are not asked. */
export async function openJudgementWithoutRecall(admin: Rpc, o: { seat: string; path: string; situation: string; subject?: Record<string, unknown> | null; reason: string }): Promise<CaseMemory> {
  const m: CaseMemory = { seat: o.seat, path: o.path, available: false, reason: o.reason, cases: [], finalised_precedent: false, rule: null, handoffs: [] };
  try {
    const { data, error } = await admin.rpc('fn_judgement_record', {
      p_seat: o.seat, p_surface: o.path, p_subject: o.subject ?? null, p_question: String(o.situation || '').slice(0, 2000), p_recall: recallTrace(m),
    });
    m.judgement_id = error ? null : Number(data) || null;
  } catch (_e) { m.judgement_id = null; }
  return m;
}

async function recallOnly(admin: Rpc, o: Parameters<typeof recallCases>[1]): Promise<CaseMemory> {
  const base = { seat: o.seat, path: o.path, cases: [] as RecalledCase[], finalised_precedent: false, rule: null, handoffs: [] as HandoffNote[] };
  const text = String(o.situation || '').trim();
  if (!text) return { ...base, available: false, reason: 'no_situation' };
  try {
    // A caller that already embedded (or tried to) passes `embedding`, even null: a second gte-small
    // session in the same worker is memory the edge runtime does not have to spare.
    const ask = o.embed;
    const ml = o.embeddingMl ?? ((await readSpace(admin)) === 'ml'
      ? await (ask ? ask(text, 'ml').catch(() => null) : embedQueryMlRemote(admin, text, 'case_recall:' + o.seat, RECALL_EMBED_ML_MS)) : null);
    const vec = ml ?? ('embedding' in o ? o.embedding
      : ask ? await ask(text, 'gte').catch(() => null)
      : await Promise.race([embedLine(text), new Promise<null>((r) => setTimeout(() => r(null), RECALL_EMBED_MS))]));
    if (!vec) return { ...base, available: false, reason: 'embedding_unavailable' };
    const { data, error } = await admin.rpc(ml ? 'fn_case_recall_ml' : 'fn_case_recall', {
      p_seat: o.seat, p_embedding: typeof vec === 'string' ? vec : '[' + vec.join(',') + ']',
      p_trade: o.trade ?? null, p_k: o.k ?? 5, p_case_kind: o.caseKind ?? null,
      // A SEAT RECALLS ITS OWN CASES unless it asks for more (28 Sep 2026, learning-loop audit C14). The
      // default was every seat's cases, so a customer-facing think() could put an accountant's or the CEO's
      // internal case into a customer reply's prompt. The CEO oversees every seat and keeps the wide view.
      p_other_seats: o.otherSeats ?? o.seat === 'ceo',
      p_exclude_source_table: o.exclude?.table ?? null, p_exclude_source_id: o.exclude?.id ?? null,
    });
    if (error) return { ...base, available: false, reason: 'recall_failed: ' + error.message };
    const cases = (Array.isArray(data?.cases) ? data.cases : []) as RecalledCase[];
    return { ...base, available: true, cases, finalised_precedent: cases.some((c) => c.finalised), rule: precedentRule(cases) };
  } catch (e) {
    return { ...base, available: false, reason: 'recall_failed: ' + String((e as Error)?.message || e) };
  }
}

/** Open handoffs to this seat on this case. Only with a named case: a note never leaks across cases. */
async function handoffNotes(admin: Rpc, seat: string, subject: Record<string, unknown> | null): Promise<HandoffNote[]> {
  const id = subject?.id == null ? '' : String(subject.id);
  if (!id) return [];
  try {
    const { data, error } = await admin.rpc('fn_seat_handoff_notes', {
      p_seat: seat, p_subject_table: subject?.table == null ? null : String(subject.table), p_subject_id: id,
    });
    return !error && Array.isArray(data) ? data as HandoffNote[] : [];
  } catch (_e) { return []; }
}

/** The handoff notes, the FIRST thing a model path reads. Empty when no handoff is open on the case. */
export function handoffBlock(m: CaseMemory): string {
  if (!m.handoffs?.length) return '';
  const lines = m.handoffs.map((h) => [
    `handoff #${h.handoff_id} from ${h.from ?? 'a colleague'} (${h.conversation ?? 'handoff'}):`,
    `  context: ${String(h.summary?.context ?? '').slice(0, 400)}`,
    `  decision: ${String(h.summary?.decision ?? '').slice(0, 300)}`,
    `  open asks: ${(h.summary?.open_asks ?? []).slice(0, 5).join(' | ').slice(0, 500)}`,
    `  deadline: ${h.summary?.deadline ?? 'not stated'}`,
    `  known: ${JSON.stringify(h.summary?.known ?? {}).slice(0, 500)}`,
    `  tried: ${JSON.stringify(h.summary?.tried ?? {}).slice(0, 500)}`,
    `  needed: ${JSON.stringify(h.summary?.needed ?? {}).slice(0, 400)}`,
    `  evidence: ${(h.summary?.evidence ?? []).slice(0, 8).join(', ')}`,
  ].join('\n'));
  return `\n\nHANDOFF NOTES ON THIS CASE (read these first; internal, never quoted to a customer). Answer every open ask before its deadline and cite the note you acted on as "handoff #<number>":\n${lines.join('\n')}`;
}

/**
 * A DETERMINISTIC path closes the judgement its recall opened (28 Sep 2026). think() closes its own; before
 * this, every other path left its judgement at 'recalled' forever (9 of 9 on production). `followed` is the
 * recalled cases the decision actually used ([] = decided without a precedent); fn_judgement_decided refuses
 * a case that was not recalled. Recording never fails the decision.
 */
export async function decideJudgement(admin: Rpc, m: CaseMemory, decision: string, followed: number[]): Promise<void> {
  if (m.judgement_id == null) return;
  try {
    await admin.rpc('fn_judgement_decided', { p_id: m.judgement_id, p_status: 'answered', p_decision: decision.slice(0, 2000),
      p_confidence: null, p_model: 'deterministic', p_followed: followed });
  } catch (_e) { /* recording never fails the decision */ }
}

/** The block a model path puts in its system prompt: handoff notes first, then past cases. */
export function precedentBlock(m: CaseMemory): string {
  const notes = handoffBlock(m);
  if (!m.cases.length) return notes;
  const lines = m.cases.map((c) => [
    `#${c.case_id} [${c.seat}/${c.case_kind}${c.trade ? ', ' + c.trade : ''}] similarity ${c.similarity}, ${c.finalised ? 'FINALISED' : 'NOT finalised'}`,
    `  situation: ${c.situation.slice(0, 400)}`,
    c.decision ? `  decided: ${c.decision.slice(0, 300)}` : '',
    c.outcome ? `  outcome: ${c.outcome.slice(0, 300)}` : '',
    c.correction ? `  CORRECTED (${c.corrected_by}): ${c.correction.slice(0, 300)}` : '',
    c.lessons?.length ? `  lessons: ${c.lessons.slice(0, 3).join(' / ').slice(0, 400)}` : '',
  ].filter(Boolean).join('\n'));
  return notes + `\n\nPAST CASES LIKE THIS ONE (institutional memory; identities are masked and must stay masked):\n${lines.join('\n')}\n${m.rule ?? ''}`;
}

/** What goes into a log or a customer-safe answer: case numbers only, never the text. */
export const recallTrace = (m: CaseMemory) => ({
  available: m.available, reason: m.reason ?? null,
  cases: m.cases.map((c) => ({ case_id: c.case_id, similarity: c.similarity, finalised: c.finalised })),
  finalised_precedent: m.finalised_precedent,
  handoffs: (m.handoffs ?? []).map((h) => h.handoff_id),
});
