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
// BACKGROUND WORK KEEPS HIGH, WITH A LIMIT THAT FITS IT (it_engineer, 12 Nov 2026; founder ledger 1642: "background work stays
// high with a limit that fits it"; final audit 2026-11-12 section 3, E6). A call that names no timeout had think/deps.ts's
// 45 s (a 47 s gateway wall), measured for medium. Since the 11 Nov raise to high, on production (ai_cost_log, 11 Nov 20:00
// to 12 Nov): internal_judgement on gpt-6-luna-pro p50 36.4 s, p90 78.9 s, p95 83.5 s, max 104.9 s (n 89 answered), and
// marketing's lost 4 of 4 at 46.7-47.2 s (143 of 143 answered 5-11 Nov, max 41.2 s); the independent reviewer
// (knowledge_validation on qwen/qwen3.8-flash) p50 53.1 s, p90 93.5 s, p95 114.6 s (n 90). An internal audience's call
// (audience 'internal': no person waits on it) gets INTERNAL_CALL_TIMEOUT_MS unless it names its own: over the answer's p95 and the reviewer's
// p90. A caller's own clock still cuts it (withDeadline: the held replay's REPLAY_BUDGET_MS).
// prevented by: _shared/a_background_judgement_has_the_time_high_effort_takes.test.ts
export const INTERNAL_CALL_TIMEOUT_MS = 100_000;
// AND THE RUN HAS ONE DEADLINE (review of 12 Nov 2026). 100 s a call is not a run limit: plan (p95 39 s) + answer (to 105 s) +
// review (p50 54.9 s, p95 142.1 s, max 173.5 s, n 104) passes the 150 s edge wall, and a worker killed there records nothing.
// An internal run ends INTERNAL_RUN_DEADLINE_MS after it starts unless its caller names an earlier deadlineAt; each call gets
// what is left (withDeadline) and none starts with under MIN_STEP_MS. What is cut is recorded and said: an answer cut is the
// ordinary hold (the judgement row, the held reason 'turn_deadline: ...'); a review cut leaves the answer verified 'not_run'
// with that reason in its notes and confidence capped at 0.6 (engine.ts), never a silent kill. The review is NOT moved to a
// step of its own: no queue holds a review apart from its question (a held replay re-asks the whole question under its 90 s
// REPLAY_BUDGET_MS), so a separate review step needs a table, its policy and a consumer (an apply), outside this fix. The loss
// is bounded: measured, the reviewer's p50 (54.9 s) fits what an answer at its p50 (36.6 s) leaves of 130 s, its p95 does not.
export const INTERNAL_RUN_DEADLINE_MS = 130_000;
export { ROUTINES, LEAN_DECIDE_NOTE };
