// THE PORTAL CHAT TURN'S CLOCK, RULES AND FACTS (customer_support owns the conversation, it_engineer the latency;
// 27 Oct 2026). The pure half of sales_engineer's `assist` action, kept apart so it is tested without a network.
//
// WHY A CLOCK. The edge runtime answers 504 when a function has sent nothing for 150 s, and the portal then prints its
// error line in the middle of a customer's conversation. Measured on production (ZZ DEMO wardrobe replay, 27 Oct
// 07:41-08:13Z): the old turn took 58-150 s and one hit the wall. The new turn is one streamed model call, so a normal
// answer starts in a few seconds; PORTAL_TURN_MS bounds the WORST case (the model ladder: stream, rewrites, retry,
// another family) so even a caller that does not stream gets its JSON well inside the wall.
// prevented by: sales_engineer/portal_turn.test.ts, _shared/brief_answer.test.ts
import { checkReadability, MAX_SENTENCE_WORDS } from '../_shared/readability.ts';

/** Every model call of one portal turn starts and ends inside this, counted from the request's arrival. Under half the
 *  150 s edge wall, so a non-streaming caller also has its answer (or its notice) long before a 504 could happen. */
export const PORTAL_TURN_MS = 70_000;

/** The portal's format, added to the shared conversation rules (ai_reply.aiSystem). */
export function portalRules(): string {
  return 'Plain text for the portal chat window: no markdown, no bullets, no headings, under about 120 words. The person is signed in to their own account: never tell them to log in or to sign up.';
}

/** A reply wrapped as data is refused sentence by sentence and rewritten by the model, never shown (27 Oct 2026: the first
 *  streamed portal turns read {"answer":"..."} because the shared rules asked for JSON; aiSystem's plainText now says
 *  otherwise, and this keeps a model that answers in JSON anyway off the customer's screen). */
export function wrappedReply(text: string): string[] {
  return /^\s*(```|\{\s*"|\[\s*\{)/.test(text) || /"answer"\s*:/.test(text)
    ? ['it wraps the reply in JSON or a code fence; write only the plain reply text'] : [];
}

/** THE PLAIN-LANGUAGE GATE, SENTENCE BY SENTENCE (founder ledger 1013 item 7; independent review of #1640, 27 Oct 2026).
 *  The old road ran readability.ts on every reply and had the model rewrite a failing one (8 of 14 turns measured); the
 *  one-call road dropped it. Each sentence is held to the two rules a sentence can break on its own: at most
 *  MAX_SENTENCE_WORDS words, and no jargon or internal identifier. A failing sentence is not shown; the model rewrites it
 *  (brief_answer.ts). The whole-reply rules (average length, language share) are scored after and recorded. */
export function plainLanguage(text: string, lang: 'en' | 'ar'): string[] {
  const out: string[] = [];
  for (const s of String(text || '').split(/(?<!\d)[.!?؟]+(?!\d)|\n+/)) {
    if (!/[\p{L}\p{N}]/u.test(s)) continue;
    for (const i of checkReadability(s, lang).issues) {
      if (i.startsWith('long_sentence')) out.push(`a sentence is longer than ${MAX_SENTENCE_WORDS} words; split it`);
      else if (i.startsWith('jargon')) out.push(`it uses ${i.replace('jargon:', 'jargon or an internal term: ')}; say it in plain words`);
    }
  }
  return [...new Set(out)];
}

/** One retrieved record, as fn_sales_assist returns it. */
export interface Record_ { title?: unknown; content?: unknown; corpus?: unknown; record_id?: unknown }

/** NOTHING INTERNAL OR UNVERIFIED REACHES A CUSTOMER (#1567/#1569, the founder's 7 Oct stating rule: a fact not read on a
 *  page actually opened is never stated to a customer or supplier; independent review of #1640, 27 Oct 2026).
 *  fn_sales_assist reads its corpora without the audience and eligibility rules fn_reason_retrieve applies to a customer
 *  audience, and a withheld record's text would ride in the facts AND make its figures "known" to the figure check
 *  (briefNumbers over the facts). One rule per corpus, each the estate's own (fn_reason_retrieve's customer branch for
 *  the audience, fn_knowledge_library_source_sql for "verified"). Measured on production 27 Oct 2026, of the rows
 *  fn_sales_assist can return:
 *   - sales_knowledge (6,536): 8 tagged audience:internal, 434 runtime_index_eligible = false.
 *   - ops_knowledge (9,107 readable of 9,143): 7,705 outside fn_reason_retrieve's customer scope (scope_type department,
 *     role, workflow or agent, or a dept_key), 6 'draft', 0 runtime-ineligible; 1,402 admitted. confidentiality is
 *     'internal' on all 9,143 rows, so it carries no signal and is not read (no reader in the estate reads it).
 *   - agent_knowledge (2,078 readable of 2,570): 1,969 are another key's notes (fn_reason_retrieve gives a customer
 *     only '_global'; this includes the 1,627 'cat:' rows, 287 of them author_verified), 1,796 unvalidated or
 *     unsourced; 1 admitted.
 *  Independent review, third round (27 Oct 2026), measured on production read-only the same day:
 *   - sales_knowledge: the customer branch of fn_reason_retrieve also withholds 'kind:company' and a source under
 *     internal:founder_instruction/ or internal:memory/ (INTERNAL_TO_CUSTOMER). 0 such rows are eligible today; the rule
 *     now matches so a future row cannot slip through.
 *   - support_knowledge (722, all readable by fn_sales_assist): 90 tagged audience:internal (88 sourced from founder
 *     instructions or memory, 30 kind:company), e.g. the activation and win-back playbook. Same rule.
 *   - kb_chunks: 53 rows of source_kind 'memory' are agent_memory notes (internal working notes, e.g. "KB submissions
 *     require Knowledge Curator review"). Withheld. The 1,317 'generated' rows are left as the estate's own rule
 *     (fn_knowledge_library_source_sql) marks every kb_chunks row verified; that is a policy question, not this code's.
 *   - company_faq (638 rows, all 'approved', the filter fn_sales_assist applies), category_specs (56) and
 *     category_quote_specs (141) carry customer-facing requirement facts and pass (PASS_THROUGH).
 *  A corpus with neither a rule nor a PASS_THROUGH entry is WITHHELD: a corpus fn_sales_assist starts returning later
 *  does not reach a customer until someone decides it may. */
export interface SafetyRule { table: string; key: string; select: string; safe: (row: Record<string, unknown>) => boolean }
const VERIFIED_AGENT_STATUS = new Set(['author_verified', 'source_verified', 'validated', 'reviewed', 'approved']);
/** fn_reason_retrieve's customer-branch exclusion (v_internal = false), for the stores that carry tags and source_ids. */
export function internalToCustomer(f: Record<string, unknown>): boolean {
  const tags = (f.tags as string[] | null) ?? [];
  const src = (f.source_ids as string[] | null) ?? [];
  return tags.includes('audience:internal') || tags.includes('kind:company')
    || src.some((x) => String(x).startsWith('internal:founder_instruction/') || String(x).startsWith('internal:memory/'));
}
/** Corpora fn_sales_assist returns whose rows are customer-facing as filtered there (measured 27 Oct 2026, above). */
export const PASS_THROUGH = new Set(['company_faq', 'category_specs', 'category_quote_specs']);
export const CUSTOMER_SAFE: Record<string, SafetyRule> = {
  sales_knowledge: { table: 'sales_knowledge', key: 'record_id', select: 'record_id, tags, source_ids, runtime_index_eligible',
    safe: (f) => !internalToCustomer(f) && f.runtime_index_eligible === true },
  support_knowledge: { table: 'support_knowledge', key: 'record_id', select: 'record_id, tags, source_ids, runtime_index_eligible',
    safe: (f) => !internalToCustomer(f) && f.runtime_index_eligible === true },
  kb_chunks: { table: 'kb_chunks', key: 'id', select: 'id, source_kind',
    safe: (f) => typeof f.source_kind === 'string' && f.source_kind !== 'memory' },
  ops_knowledge: { table: 'ops_knowledge', key: 'record_id', select: 'record_id, scope_type, dept_key, runtime_eligible, supersession_state, validation_status',
    safe: (f) => f.runtime_eligible === true && f.supersession_state === 'current' && f.dept_key == null
      && ['company', 'external_source', 'category'].includes(String(f.scope_type)) && typeof f.validation_status === 'string' && f.validation_status !== 'draft' },
  agent_knowledge: { table: 'agent_knowledge', key: 'id', select: 'id, agent_key, validation_status',
    safe: (f) => f.agent_key === '_global' && VERIFIED_AGENT_STATUS.has(String(f.validation_status)) },
};

/** Reads one corpus's flag rows for the given ids (the caller's database client; a fake in the tests). */
export type FlagLookup = (rule: SafetyRule, ids: string[]) => Promise<{ data: Record<string, unknown>[] | null; error: unknown }>;

/** The records a customer prompt may carry. FAILS CLOSED: a record is kept only when its row was read back and passes
 *  its corpus's rule; a lookup that errors or throws withholds every record of that corpus, and a row that was not
 *  returned is withheld too. */
export async function customerSafe<T extends Record_>(records: T[], lookup: FlagLookup): Promise<T[]> {
  const keep = new Set<string>();
  await Promise.all(Object.entries(CUSTOMER_SAFE).map(async ([corpus, rule]) => {
    const ids = [...new Set(records.filter((x) => x.corpus === corpus).map((x) => String(x.record_id ?? '')))];
    if (!ids.length) return;
    try {
      const { data, error } = await lookup(rule, ids);
      if (error || !Array.isArray(data)) return;
      for (const f of data) if (rule.safe(f)) keep.add(corpus + ':' + String(f[rule.key]));
    } catch { /* withheld: nothing unread reaches a customer */ }
  }));
  return records.filter((x) => PASS_THROUGH.has(String(x.corpus)) || keep.has(String(x.corpus) + ':' + String(x.record_id ?? '')));
}

/** At most this many retrieved records, each at most RECORD_CHARS, ride with the message. The old turn sent the plan's
 *  per-step retrieval as well (up to 36 sources of 2,400 characters); the answer prompt reached 62k tokens. */
export const MAX_RECORDS = 5;
export const RECORD_CHARS = 1200;
export const FACTS_CHARS = 6000;

/** The facts block for this turn: the customer's own quotes first, then this seat's retrieved records. '' when neither. */
export function portalFacts(o: { facts?: string | null; passages?: Record_[] | null }): string {
  const recs = (o.passages ?? [])
    .map((x) => [String(x.title ?? '').trim(), String(x.content ?? '').trim()].filter(Boolean).join('\n').slice(0, RECORD_CHARS))
    .filter(Boolean).slice(0, MAX_RECORDS);
  const parts = [
    o.facts && o.facts.trim() ? o.facts.trim() : '',
    recs.length ? "THE SALES ENGINEER'S RECORDS FOR THIS QUESTION (use what answers it; ignore the rest):\n" + recs.map((r, i) => `[${i + 1}] ${r}`).join('\n\n') : '',
  ].filter(Boolean);
  return parts.length ? ("THIS CONVERSATION'S FACTS:\n" + parts.join('\n\n')).slice(0, FACTS_CHARS) : '';
}
