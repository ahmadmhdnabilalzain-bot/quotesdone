// think/tunables.ts — the numbers think() runs on, each with its measurement (moved whole from _shared/think.ts).

// ── tunables, each with its measurement ──────────────────────────────────────────────────────────
// 0.84: the corroboration floor case memory measured for gte-small (paraphrases 0.847-0.924,
// unrelated 0.760-0.816; scripts/sql/every_seat_remembers_its_cases_and_recalls_them_by_meaning.sql).
// A step whose best knowledge is below it is not answered from knowledge alone; it is researched.
export const CORROBORATION_FLOOR = 0.84;
// The same bar in the multilingual space, where similarities sit on a different scale: the multilingual cosine
// below which the SAME share of English eval questions' best row falls as falls below 0.84 under gte-small.
// Measured by scripts/eval/multilingual_recall_eval.mjs on 23 Sep 2026: 0.833 in both runs (1,094 English
// questions; with and without kb_chunks in the pool). The bar is moved to its equivalent, not lowered.
export const CORROBORATION_FLOOR_ML = 0.833;
// The routines each space reads. A vector is only ever put to the routine of its own space.
const ROUTINES = {
  gte: { retrieve: 'fn_reason_retrieve', recall: 'fn_case_recall', floor: CORROBORATION_FLOOR },
  ml: { retrieve: 'fn_reason_retrieve_ml', recall: 'fn_case_recall_ml', floor: CORROBORATION_FLOOR_ML },
} as const;
export const MAX_STEPS = 5;
export const MAX_SYNTH_PASSES = 3;         // the first draft + two forced re-passes
export const MAX_RESEARCH_PAGES = 3;
/** A gateway answer that says the PROVIDER failed, not the request: gateway_http_5xx (502, 503, 546) or its deadline. */
export const TRANSIENT_MODEL_ERROR = /gateway_http_5\d\d/i;
/** A deadline or timeout is never retried: a plan that ran its 75 s and was retried would pass the 150 s edge wall before
 *  synthesis began (release review of #1584); a timed-out plan already falls back to the one-step plan (#1564). */
export const SLOW_MODEL_ERROR = /deadline|timed? ?out|timeout/i;
/** A source's excerpt as the seat reads it. The routines cut a seat-pack row at 2,400 characters and every other row at
 *  1,200 (a_seats_own_entry_reaches_the_answer_whole.sql); this side cut everything to 1,200 again until 19 Oct 2026. */
export const EXCERPT_MAX = 2400;
/** The settled facts (company brief, rulings, the seat's card) are a source the answer may cite, by this id. */
export const BRIEF_SOURCE_ID = 'brief';
// 900 cut answers mid-JSON: measured on the seat exam (19 Oct 2026), 21 of 67 internal_judgement replies from
// gpt-6-luna stopped at exactly 900 output tokens, and 13 drafts across five seats were held as 'the reply is not one
// JSON object'. Every class think() writes in allows at least 2,000 (model_policy: internal_judgement and
// routine_employee_reasoning 2,000; the audience classes and ceo__internal_judgement 4,000).
export const SYNTH_MAX = 2000;
// A LEAN CHOICE WRITES LITTLE (customer_support, 2 Nov 2026). Its caller reads decision.choice (and `also`) and nothing else, yet the
// model wrote a two-or-three sentence "answer" and a reasoning trail first: decode time is most of the ~15 s classification.
// Lean decisions are told to keep every other field minimal, and are capped at this many tokens (the JSON itself is ~100).
export const LEAN_DECIDE_MAX = 500;
const LEAN_DECIDE_NOTE = `
This choice is read by a program: only "decision" (and any "Also" keys) is used. Keep "answer" to at most eight words, "reasoning" [], "cited" [], "asked_back" null, and write nothing outside the JSON object.`;
// The planner runs on a reasoning model whose hidden tokens count against the clock: on the seat exam (19 Oct 2026)
// 41 of 432 plans (routine_employee_reasoning on gpt-6-luna-pro) hit the gateway's 47 s wall and the question was held
// (25 of 67 for ceo); the slowest plan that finished took 47.3 s.
export const DECOMPOSE_TIMEOUT_MS = 75_000;
export { ROUTINES, LEAN_DECIDE_NOTE };
