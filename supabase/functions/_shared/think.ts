// think — the one reasoning engine every seat uses before it answers or decides. Seat: it_engineer
// (shared platform). 23 Sep 2026, founder_instruction 886-903.
//
// THE FOUNDER'S RULINGS THIS FILE CARRIES, in his order:
//   * NO WORD MATCHING. A decision about what a message MEANS is made by reasoning, never by a keyword
//     list, a regex or an ilike. A guard on our OWN outgoing text, and parsing a format, may stay.
//   * THE ANSWER STANDARD (903). Any question from a customer or a supplier about any category, detail
//     or spec (food & beverage excepted) is answered. "No", "I need to check and get back to you" or any
//     excuse is not an answer. Published prices may be used; unpublished prices are learned over time.
//   * THE REASONING WORKFLOW (903), for every seat. His example: "I want to build a pool at my villa —
//     what depth, what's legal?" → which emirate / area? → which authorities and standards govern it
//     (Dubai Municipality, the community developer's rules) → are limits area-specific or emirate-wide?
//     → then answer. Asking for a genuinely missing fact that changes the answer is part of reasoning,
//     not an excuse — but the reply still gives everything that can already be said ("In Dubai it is X,
//     in Abu Dhabi Y — which emirate is your villa in?").
//
// THE STEPS (each one recorded in `steps`, so the trail is what the answer stands on):
//   a. DECOMPOSE — a model plans the steps and names the facts that decide the answer (jurisdiction,
//      area / free zone, customer or supplier, trade, use, quantity ...), marking which of them CHANGE
//      the answer and filling each it can from what it was given.
//   b. RESOLVE CONTEXT — the conversation, the profile and the case it was handed, plus case memory
//      (public.fn_case_recall, the sibling case-memory PR #879) recalled by meaning.
//   c. RETRIEVE PER STEP — gte-small (free, in-region) and public.fn_reason_retrieve: nearest rows by
//      vector distance across the seat's knowledge, the trade packs, the authority rules, the FAQ and
//      reviewed research. No lexical gate decides what is relevant.
//   d. RESEARCH — when a step's best match is below the corroboration floor, the authoritative web is
//      searched and read (founder's standing permission to scrape); what is found is cited and written
//      back as a PENDING knowledge item (fn_reason_propose_knowledge), so the next question is answered
//      from knowledge.
//   e. SYNTHESISE — the answer, the reasoning trail, the cited sources, a confidence, and a question
//      back only for a missing fact that changes the answer, alongside everything already sayable.
//   f. VERIFY — on high stakes (a legal or regulatory limit, money, safety) a model of ANOTHER family
//      checks it, routed by public.fn_ai_route_review (#877) through ai_gateway's counterpart_model.
//
// THE VALIDATOR refuses a draft that says it cannot answer, will get back, or defers without content,
// that asks back without a decision-changing missing fact, that cites a source it was not given, or
// that picks a decision option that does not exist — and forces another pass. It reads OUR draft, so
// its phrase list is a guard on outgoing text, which the founder's ruling permits.
//
// UNDER THE MODEL HOLD there is no reasoning to do, and a keyword answer is forbidden. think() returns
// {status:'held'} and files the question in the owning seat's queue (public.reasoning_held_question)
// with its plan, so it is reasoned the moment the hold lifts (replayHeld, run by resilience_ping). A
// model that fails or keeps evading is queued the same way: nothing is ever answered by a word list.
//
// llm.ts is imported lazily (defaultDeps) because it opens a client at load; think() itself takes its
// model, embedder and database as `deps`, so think.test.ts runs every path with a mocked model.
//
// SPLIT, 9 Nov 2026 (it_engineer): this file is the barrel. The code lives in _shared/think/, one subject a module, moved whole:
//   types.ts (the shapes), tunables.ts (the measured numbers), routing.ts (model class, duty and fixture rules), figures.ts,
//   research.ts (authoritative web), validator.ts (the guard on our draft), settled.ts (settled facts per audience),
//   prompts.ts, reader.ts, engine.ts (think), deps.ts (live dependencies), replay.ts (held questions). Importers keep
//   importing './think.ts'. A check that reads this as text reads sharedModuleSource('think') (scripts/lib/function_sources.mjs).
export type {
  Seat, Phase, Turn, ThinkContext, DecisionSpec, ThinkRequest, Step, Fact, Source, ThinkResult, LlmReply, EmbedSpace, ThinkDeps,
} from './think/types.ts';
export type { Figure } from './think/figures.ts';
export type { Draft } from './think/validator.ts';
export type { GtePlacement } from './think/deps.ts';
export type { StoredThinkRequest, HeldRow } from './think/replay.ts';
export { SEATS } from './think/types.ts';
export {
  CORROBORATION_FLOOR, CORROBORATION_FLOOR_ML, MAX_STEPS, MAX_SYNTH_PASSES, MAX_RESEARCH_PAGES, TRANSIENT_MODEL_ERROR, SLOW_MODEL_ERROR,
  EXCERPT_MAX, BRIEF_SOURCE_ID, SYNTH_MAX, LEAN_DECIDE_MAX, DECOMPOSE_TIMEOUT_MS,
} from './think/tunables.ts';
export { INTERNAL_DUTY_SURFACE, easyClass, EASY_DUTY_SURFACE, planTimedOut, isFixtureRequest, fixtureInOpenWindow, taskClassFor } from './think/routing.ts';
export { figuresOf, figuresGrounded } from './think/figures.ts';
export { AUTHORITY_HOSTS, authoritative, webSearch, readPage, htmlText } from './think/research.ts';
export {
  EVASION, substanceWords, READER_MIN_EVIDENCE, keepProvenFields, refuse, citable, groundDraft, valueInEvidence, parseJson,
} from './think/validator.ts';
export { EXTERNAL_AUDIENCES, SETTLED_HEADER, INTERNAL_AUDIENCES, audienceOf, settledFacts } from './think/settled.ts';
export { ENTRY_KINDS, decomposePrompt, synthesisPrompt, VERIFY_PROMPT, RESEARCH_PROMPT } from './think/prompts.ts';
export { SYNTH_FOR_READERS, readerOfTheirOwnText } from './think/reader.ts';
export { think } from './think/engine.ts';
export { MIN_STEP_MS, withDeadline, defaultDeps, heartbeatDeps } from './think/deps.ts';
export {
  REPLAY_MAX_ROWS, REPLAY_BUDGET_MS, REPLAY_ROW_MS, REPLAY_CLAIM, REPLAY_RESERVE_MS, REPLAY_STALE_MS, REPLAY_ANSWER_RESERVE_MS, replayHeld,
} from './think/replay.ts';
