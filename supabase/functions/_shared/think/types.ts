// think/types.ts — the shapes think() takes and returns (moved whole from _shared/think.ts, 9 Nov 2026).
import type { GateAnswer } from '../llm_hold.ts';

export const SEATS = ['customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing', 'ceo'] as const;
export type Seat = typeof SEATS[number];
export type Phase = 'decompose' | 'synthesise' | 'verify' | 'research';

export interface Turn { role: 'customer' | 'supplier' | 'visitor' | 'founder' | 'seat'; text: string }
export interface ThinkContext {
  audience: 'customer' | 'supplier' | 'visitor' | 'founder' | 'internal';   // required: names which brief rides (settledFacts)
  language?: 'en' | 'ar';
  conversation?: Turn[];
  profile?: Record<string, unknown>;   // the asker's own row(s): emirate, trade, company ... never another person's
  case?: Record<string, unknown>;      // the inquiry / quote / command this is about
  trade?: string | null;
  area?: string | null;                // the seat's own area when the caller knows it (an 'area:<area>' tag); never guessed
}
export interface DecisionSpec {
  name: string;
  options?: { id: string; meaning: string }[];          // pick exactly one
  fields?: { key: string; question: string }[];          // fill from the conversation, with the words that say so
}
export interface ThinkRequest {
  seat: Seat;
  surface: string;          // the decision point, e.g. 'wa_inbound.needs_a_person' (decision_points.json)
  question: string;
  context: ThinkContext;
  decision?: DecisionSpec;  // absent: answer the question; present: decide
  stakes?: 'normal' | 'high';
  research?: boolean;       // default: true when answering, false when deciding
  subject?: Record<string, unknown>;   // what a replay acts on (a command id, a phone, a message id)
  dedupeKey?: string;       // one held row per inbound message
  queueWhenHeld?: boolean;  // default true
  // LEAN (customer_support, 2 Nov 2026): a decision among given options reads the message, the recent turns, who is asking and the
  // options; it needs no company brief. Measured on the real exchange: the brief made WhatsApp's one classification call ~150k
  // tokens and 17-24 s. Lean sends no settled facts to the decide/verify calls; the reply step is a different request and keeps them.
  lean?: boolean;
  // An ANSWER that also names which seat owns the matter (support_reply.ts, founder_instruction 781). Unlike
  // `decision`, the answer stays the reply; the chosen id comes back as result.route (null if not one of these).
  route?: { id: string; meaning: string }[];
  // A caller that answers a customer or visitor (support_reply.ts only) may accept a short, clear refusal of a
  // manipulation or an out-of-scope ask as the answer. Off for every other caller: their drafts keep the evasion check.
  allowDecline?: boolean;
  // A caller that has ALREADY narrowed the knowledge for this exact message (the website widget: its own corpus search
  // is the topic) may hand over the plan instead of asking a model for one. The decompose call is skipped; retrieval,
  // synthesis and the validator run as always. Such a caller should also ask for stakes 'high', because without the
  // planner nobody judges the stakes, and the independent check then runs on every answer (12 Oct 2026). A decision
  // whose options are the whole of what it needs (priceQuestion: a trade from a given list) passes { steps: [] }.
  plan?: { steps: { id: string; goal: string; query: string; needs_knowledge?: boolean }[] };
  // A caller's last-mile rewrite (support_reply.ts: the plain-language gate). Runs on the draft BEFORE the independent
  // check, so the checked text is the text sent; null keeps the draft. Only when the check runs.
  polish?: (answer: string) => Promise<string | null>;
  // One more choice made IN the answering call, so it costs no chain of its own (the widget: which published trade, if
  // any, they ask the price of). Comes back as result.extra (null if not one of the ids).
  ask?: { key: string; options: { id: string; meaning: string }[] };
  // MORE CHOICES IN THE SAME CALL AS A DECISION (customer_support, 19 Oct 2026): WhatsApp reads what a message asks,
  // whether it needs a person and what it means to the menu in ONE model call instead of three. Each comes back in
  // result.also[key], null when the model did not name one of that key's ids. The main decision is validated as always.
  also?: { key: string; options: { id: string; meaning: string }[] }[];
  // Output ceilings for a caller whose reply is short (the widget: ~70 words). With a verify ceiling the reviewer is
  // also told to return the strict JSON verdict only. A truncated output is a failed pass, never a fragment sent.
  maxTokens?: { synthesise?: number; verify?: number };
  // A READER OF THE PERSON'S OWN TEXT (18 Oct 2026, measured: 10 runs of one ZZ DEMO photographed quotation through the
  // deployed readers). Two rules built for answers dropped WHOLE readings that were right:
  //   - a question asked back ("what sheen?", "confirm the payment terms") refused the draft; the rewrite asked again and
  //     the reading was held (validity, delivery and warranty asked again though the photo stated them);
  //   - ONE field whose evidence was short ("2 coats", 7 characters; "Jotun", 5) or whose value was a paraphrase ("VAT
  //     excluded" for "Prices exclude VAT") refused every other, correct field with it.
  // A reader answers what the text states; what it does not state is asked by the caller's own flow. So for a reader the
  // question is discarded, and the evidence guard runs PER FIELD: a field that fails is dropped (and asked), the proven
  // ones are kept. The guard is unchanged in kind: the value must sit inside evidence copied verbatim from the person's
  // own words; the minimum quote is READER_MIN_EVIDENCE characters instead of 8.
  reader?: boolean;
  // The reasoning effort asked of the model for the answer or decision (a choice among a few options needs little).
  effort?: 'low' | 'medium' | 'high';
  // Sampling temperature for every call of this run (absent: 0.2, and 0 for the independent check). The quote hold
  // gate's readers pass 0 (sales_engineer, 2 Nov 2026): the same quotation must read the same way every time.
  temperature?: number;
  // A ROUTINE SCHEDULED DUTY RUNS ON THE SEAT'S EASY ROUTE (it_engineer, 3 Nov 2026; ruling 1056: the CEO has Opus for
  // HARD tasks only). Every internal_judgement step of this run is asked as routine_employee_reasoning, which fn_ai_route
  // gives every seat on its cheap model. Set by replayHeld for EASY_DUTY_SURFACES; a caller may set it for its own duty.
  easy?: boolean;
  // AN INTERNAL DUTY (it_engineer, 3 Nov 2026): the seat's own scheduled work. A model it PAID for an empty answer is not
  // asked again (the CEO's Opus replays, 3 Nov: every second attempt empty at 35-38 s, paid twice). DECLARED, never inferred
  // from the audience: an internal-audience judgement about a real supplier or visitor (a held supplier-profile read, a
  // routing decision) is not a duty and keeps every retry. Set by replayHeld for INTERNAL_DUTY_SURFACE only.
  internalDuty?: boolean;
}
export interface Step { id: string; kind: string; goal: string; status: 'done' | 'held' | 'skipped' | 'failed' | 'refused'; detail?: unknown }
export interface Fact { name: string; why: string; changes_answer: boolean; value: string | null; from: string | null }
export interface Source { id: string; kind: string; title: string; excerpt: string; citation: string | null; url?: string | null; similarity?: number | null; trust: 'reviewed' | 'pending_review' | 'web' | 'case_memory' | 'given' }
export interface ThinkResult {
  status: 'answered' | 'held';
  answer: string;
  decision?: { choice: string | null; fields: Record<string, { value: string; evidence: string }> } | null;
  steps: Step[];
  context_used: Record<string, unknown>;
  missing_context: Fact[];
  sources: Source[];
  confidence: number;
  asked_back?: string | null;
  verified?: { status: 'agreed' | 'disagreed' | 'not_run' | 'not_needed'; by: string | null; notes: string } | null;
  model?: string | null;
  held_id?: number | null;
  reason?: string;
  route?: string | null;
  extra?: string | null;
  also?: Record<string, string | null>;
}

export interface LlmReply { content: string | null; model?: string | null; error?: string | null; used_llm?: boolean }
// deno-lint-ignore no-explicit-any
type RpcResult = { data: any; error: { message: string } | null };
export type EmbedSpace = 'gte' | 'ml';
export interface ThinkDeps {
  gate(): Promise<GateAnswer>;
  // subject: what the question is about, forwarded to ai_gateway so its fixture check (fn_ai_subject_is_fixture)
  // can answer our own test traffic with the no-cost stub (704, 28 Sep 2026).
  llm(phase: Phase, system: string, input: string, o: { taskClass: string; seat: Seat; counterpartModel?: string | null; max?: number; subject?: Record<string, unknown> | null; rateKey?: string; images?: string[]; sysStable?: string; sysShared?: string; cacheTtl?: '1h'; timeoutMs?: number; history?: { role: 'user' | 'assistant'; content: string }[]; effort?: 'low' | 'medium' | 'high'; temperature?: number; signal?: AbortSignal; internal?: boolean }): Promise<LlmReply>;
  // space 'gte' (gte-small, English-only, the default) or 'ml' (multilingual-e5-small, _shared/ml_embed.ts).
  embed(text: string, space?: EmbedSpace): Promise<number[] | null>;
  /** Why the last embed of this text in this space returned null, when the embedder said (ml_embed_client's `why`). */
  embedFailure?(text: string, space: EmbedSpace): string | null;
  /** Which space retrieval reads (fn_ml_read_space). Absent = 'gte', the path every test and caller had. */
  space?(): Promise<EmbedSpace>;
  rpc(fn: string, args: Record<string, unknown>): Promise<RpcResult>;
  search?(query: string): Promise<{ url: string; title: string }[]>;
  read?(url: string): Promise<string | null>;
}
// deno-lint-ignore no-explicit-any
type Admin = any;
export type { Admin };
