// think/engine.ts — think(): decompose, resolve, retrieve, research, synthesise, verify (moved whole from _shared/think.ts).
import { heldFromGate, type GateAnswer } from '../llm_hold.ts';
import { openJudgementWithoutRecall, recallCases } from '../case_recall.ts';
import { poolSubject, seatPool } from '../seat_pool.ts';
import { e2eRunTag } from '../e2e_run.ts';
import { gteReads } from '../ml_embed_recipe.ts';
import type { EmbedSpace, Fact, Source, Step, ThinkContext, ThinkDeps, ThinkRequest, ThinkResult } from './types.ts';
import {
  DECOMPOSE_TIMEOUT_MS, EXCERPT_MAX, INTERNAL_CALL_TIMEOUT_MS, INTERNAL_RUN_DEADLINE_MS, LEAN_DECIDE_MAX, LEAN_DECIDE_NOTE, MAX_RESEARCH_PAGES, MAX_STEPS, MAX_SYNTH_PASSES, ROUTINES, SLOW_MODEL_ERROR,
  SYNTH_MAX, TRANSIENT_MODEL_ERROR,
} from './tunables.ts';
import { withDeadline } from './deps.ts';
import { easyClass, fixtureInOpenWindow, isFixtureRequest, planTimedOut, taskClassFor } from './routing.ts';
import { figuresGrounded } from './figures.ts';
import { authoritative } from './research.ts';
import { citable, groundDraft, keepProvenFields, parseJson, READER_MIN_EVIDENCE, refuse, type Draft } from './validator.ts';
import { audienceOf, EXTERNAL_AUDIENCES, INTERNAL_AUDIENCES, settledFacts } from './settled.ts';
import { decomposePrompt, RESEARCH_PROMPT, synthesisPrompt, VERIFY_PROMPT } from './prompts.ts';
import { keepTopRows, placeRetryNote, reviewSources } from './diet.ts';
import { dietOn, dietSetting, type DietOverrides } from '../prompt_diet.ts';


const vec = (v: number[]) => '[' + v.join(',') + ']';
const textOf = (c?: ThinkContext) => (c?.conversation ?? []).map((t) => t.text).join('\n');

// ── the engine ───────────────────────────────────────────────────────────────────────────────────
export async function think(deps: ThinkDeps, req: ThinkRequest): Promise<ThinkResult> {
  const steps: Step[] = [];
  const ctx = req.context ?? {};
  const audience = audienceOf(ctx.audience);
  const deciding = !!req.decision;
  let judgementId: number | null = null;
  // The judgement row (opened by the recall in step b) is closed with what was decided, or with 'held'.
  // `followed`: the recalled cases the answer cited (source ids 'case#<id>'), so the trace says which memory was
  // USED, not only which was recalled (a_decision_names_the_recalled_case_it_followed.sql). Null when held.
  const settle = async (status: 'answered' | 'held', o: { decision?: string | null; confidence?: number; model?: string | null; reason?: string; followed?: number[] | null }) => {
    if (judgementId == null) return;
    try { await deps.rpc('fn_judgement_decided', { p_id: judgementId, p_status: status, p_decision: (o.decision ?? o.reason ?? '').slice(0, 2000) || null, p_confidence: o.confidence ?? null, p_model: o.model ?? null, p_followed: o.followed ?? null }); } catch (_e) { /* recording never fails the answer */ }
  };
  const base = {
    context_used: { audience, language: ctx.language ?? 'en', profile: ctx.profile ?? null, case: ctx.case ?? null, trade: ctx.trade ?? null },
    missing_context: [] as Fact[], sources: [] as Source[],
  };

  const hold = async (reason: string, plan: Record<string, unknown>): Promise<ThinkResult> => {
    let held_id: number | null = null;
    if (isFixtureRequest(req)) steps.push({ id: 'queue', kind: 'hold', goal: 'a fixture question is never queued', status: 'skipped', detail: 'subject.fixture' });
    else if (req.queueWhenHeld !== false) {
      const { data, error } = await deps.rpc('fn_reason_hold', {
        p_seat: req.seat, p_surface: req.surface, p_question: req.question.slice(0, 8000),
        p_request: JSON.parse(JSON.stringify({ ...req, question: req.question.slice(0, 8000) })),
        p_plan: { ...plan, steps_done: steps }, p_subject: req.subject ?? null, p_reason: reason, p_dedupe_key: req.dedupeKey ?? null,
      });
      held_id = error ? null : Number(data) || null;
      steps.push({ id: 'queue', kind: 'hold', goal: `filed in the ${req.seat} seat's queue`, status: error ? 'failed' : 'done', detail: error?.message ?? { held_id } });
    }
    await settle('held', { reason });
    return { status: 'held', answer: '', decision: null, steps, ...base, confidence: 0, asked_back: null, verified: null, model: null, held_id, reason };
  };

  // A decision with nothing to choose between is not guessed at: it is held with its reason.
  if (req.decision && req.decision.options && !req.decision.options.length) {
    steps.push({ id: 'options', kind: 'hold', goal: 'a decision needs options', status: 'failed', detail: 'no options were given' });
    return await hold('no_options', {});
  }
  // OUR OWN TEST TRAFFIC NEVER REACHES A MODEL (704, 28 Sep 2026, it_engineer). A caller that knows its subject is a
  // fixture already kept it out of the queue; the model was still called, and would be paid the day the hold lifts
  // (measured: 26 line_specs.assess and 1 postmortem fixture rows in 4 days, each a full think() run). Every other
  // call carries its subject, so the gateway's own fixture check can stub what this flag does not know about.
  // ...EXCEPT inside a proven, open sandbox window (it_engineer, 7 Oct 2026; spend_guards.rehearsalLetsFixtureThrough).
  if (isFixtureRequest(req) && !(await fixtureInOpenWindow(deps))) {
    steps.push({ id: 'fixture', kind: 'hold', goal: 'our own test traffic is never sent to a paid model', status: 'skipped', detail: 'subject.fixture' });
    return await hold('fixture_no_spend', {});
  }
  // internal: a DECLARED internal duty asked for an internal audience (defaultDeps tells ai_gateway, which then never
  // re-asks the same model after a paid empty answer); anything else - every customer's, supplier's or visitor's case - is not.
  const internalDuty = req.internalDuty === true && INTERNAL_AUDIENCES.has(audience);
  // An internal audience's call that names no timeout gets the background limit (tunables.ts INTERNAL_CALL_TIMEOUT_MS). Not the
  // founder's: he may be waiting on the answer in his channel.
  const backgroundMs = audience === 'internal' ? INTERNAL_CALL_TIMEOUT_MS : null;
  // ...and the whole run ends by one deadline (tunables.ts INTERNAL_RUN_DEADLINE_MS, or the caller's deadlineAt).
  if (audience === 'internal' || req.deadlineAt) deps = withDeadline(deps, req.deadlineAt ?? Date.now() + INTERNAL_RUN_DEADLINE_MS);
  { const base = deps; deps = { ...base, llm: (p, s, i, o) => base.llm(p, s, i, { ...o, taskClass: easyClass(o.taskClass, req.easy), subject: req.subject ?? null, internal: internalDuty, ...(req.temperature != null ? { temperature: req.temperature } : {}), ...(o.timeoutMs == null && backgroundMs ? { timeoutMs: backgroundMs } : {}) }) }; }
  // A PROVIDER BLIP IS RETRIED ONCE (ceo, ledger 1003 stage 2, 19 Oct 2026). Measured on the real-model seat exam: 27 of
  // 633 questions were held for one 502/503/546 or a gateway deadline on the plan or the answer, not for anything the
  // model said. A model call writes nothing, so one more try is safe; a hold, an open circuit or a refusal is not retried.
  { const base = deps; deps = { ...base, llm: async (p, s, i, o) => {
    const r = await base.llm(p, s, i, o);
    const e = String(r.error ?? '');
    // ...but never for our own work (an internal duty or a test run) after a model was PAID for an empty answer (it_engineer,
    // 3 Nov 2026): asking again bought the same nothing twice (the CEO's Opus replays, 3 Nov). A customer's, supplier's or
    // visitor's turn keeps its second chance.
    const ownWork = internalDuty || !!e2eRunTag();
    if (r.content || p === 'verify' || !TRANSIENT_MODEL_ERROR.test(e) || SLOW_MODEL_ERROR.test(e) || /circuit_open|open-circuit|founder_hold/.test(e) || (ownWork && /empty_completion/.test(e))) return r;
    steps.push({ id: p + '.retry', kind: p, goal: 'one retry after a provider error', status: 'done', detail: r.error });
    return await base.llm(p, s, i, o);
  } }; }
  // 0. The hold. The gate is asked, not a row count (llm_hold.ts).
  let gate: GateAnswer = null;
  try { gate = await deps.gate(); } catch (_e) { gate = null; }
  if (heldFromGate(gate)) {
    steps.push({ id: 'gate', kind: 'hold', goal: 'can a model reason now?', status: 'held', detail: gate });
    return await hold('model_hold', { pending: ['decompose', 'resolve', 'retrieve', deciding ? 'decide' : 'synthesise', 'verify'] });
  }

  // The prompt-diet switches for this run (_shared/prompt_diet.ts), read once; unreadable = the defaults.
  const diet: DietOverrides = deps.diet ? await deps.diet().catch(() => ({})) : {};
  const answerClass = taskClassFor('synthesise', audience, deciding, ctx.language ?? 'en');
  const notesAfter = dietOn(diet, 'retry_notes_ride_after_the_payload', answerClass);
  const topRows = dietOn(diet, 'retrieval_keeps_the_top_rows_above_a_floor', answerClass) ? dietSetting(diet, 'retrieval_keeps_the_top_rows_above_a_floor') : null;

  // a. DECOMPOSE
  const facts0 = req.lean === true && deciding ? '' : settledFacts(audience, req.seat);
  const d0 = req.plan ? { content: JSON.stringify({ steps: req.plan.steps, facts: [] }), error: null }
    : await deps.llm('decompose', decomposePrompt(req.seat, req.decision),
      JSON.stringify({ question: req.question, context: ctx, decision: req.decision ?? null }),
      { taskClass: taskClassFor('decompose', audience, deciding), seat: req.seat, max: 900, timeoutMs: DECOMPOSE_TIMEOUT_MS, sysStable: facts0 });
  type Plan = { steps?: { id?: string; goal?: string; query?: string; needs_knowledge?: boolean }[]; facts?: Partial<Fact>[]; high_stakes?: boolean; trade?: string | null; kind?: string | null };
  let plan = parseJson<Plan>(d0.content);
  // A PLAN CUT OFF AT THE OUTPUT CAP IS STILL A MODEL THAT ANSWERED (customer_support, 12 Oct 2026). Measured on
  // production (ai_cost_log 17:30Z, 17:38Z): an Arabic portal question with the customer's profile made the planner
  // write 900 tokens, the gateway's cap; the JSON was truncated and the whole reply fell to "could not read your
  // account". The plan only narrows retrieval, so a model that wrote one still answers, from one step on the question.
  // ...AND A PLANNER THAT TIMED OUT (exam run b2f80d4d: 3 of 30 decompose calls hit the 45 s wall on GPT-6 Luna Pro and
  // the seat answered nothing). Only a hold or an open circuit stops the answer; a slow plan never does.
  if ((!plan || !Array.isArray(plan.steps)) && (String(d0.content ?? '').trim() || (d0.error && !/circuit_open|open-circuit|founder_hold/.test(String(d0.error))))) {
    plan = { steps: [{ id: 's1', goal: 'answer the question', query: req.question.slice(0, 500), needs_knowledge: true }], facts: [], high_stakes: true };   // an unplanned answer is always cross-checked
    // The cause is kept (it_engineer, 18 Nov 2026): a planner that timed out read 'unparseable plan' here, so the held replay
    // could not count the timeout it had billed (replay.ts timedOutAtGateway). A reply that was cut keeps the old words.
    steps.push({ id: 'decompose', kind: 'decompose', goal: 'plan the reasoning', status: 'failed', detail: d0.error && !String(d0.content ?? '').trim() ? `${d0.error}; one-step plan used` : 'unparseable plan; one-step plan used' });
  }
  // A PLANNER THAT RAN OUT OF TIME IS NOT A REASON TO HOLD THE ANSWER (ceo, 19 Oct 2026, ledger 1003 stage 2). Measured
  // on the seat exam (ai_cost_log fn knowledge_exam, 05:00-08:00Z): the ceo seat's plans on gpt-6-luna-pro ran p90 77 s,
  // max 79 s, and 17 of 108 hit the gateway wall even at 75 s, so 16 questions were held unanswered while every other
  // seat planned in under 47 s. The plan only narrows retrieval: on a deadline or a provider 5xx the seat answers from a
  // one-step plan on the question, cross-checked as an unplanned answer always is. A hold or an open circuit still holds.
  if ((!plan || !Array.isArray(plan.steps)) && planTimedOut(d0.error)) {
    plan = { steps: [{ id: 's1', goal: 'answer the question', query: req.question.slice(0, 500), needs_knowledge: true }], facts: [], high_stakes: true };
    steps.push({ id: 'decompose', kind: 'decompose', goal: 'plan the reasoning', status: 'failed', detail: `${d0.error}; one-step plan used` });
  }
  if (!plan || !Array.isArray(plan.steps)) {
    steps.push({ id: 'decompose', kind: 'decompose', goal: 'plan the reasoning', status: 'failed', detail: d0.error ?? 'no plan' });
    return await hold(/circuit_open|open-circuit|founder_hold/.test(String(d0.error ?? '')) ? 'model_hold' : 'model_failed: decompose', {});
  }
  const planSteps = plan.steps.slice(0, MAX_STEPS).map((s, i) => ({ id: String(s.id || 's' + (i + 1)), goal: String(s.goal || ''), query: String(s.query || s.goal || req.question), needs: s.needs_knowledge !== false }));
  // UNDERSTAND THE QUESTION FIRST: the caller's trade wins, else the planner's reading of the question. Either is only
  // a proposal: retrieval resolves it exactly or ignores it. The words are read by the model, never matched.
  const str = (x: unknown) => (typeof x === 'string' && x.trim() ? x.trim().toLowerCase() : null);
  const trade = str(ctx.trade) ?? str(plan.trade);
  const kind = trade ? str(plan.kind) : null;
  steps.push({ id: 'decompose', kind: 'decompose', goal: 'plan the reasoning', status: 'done', detail: { steps: planSteps.map((s) => s.goal), trade, kind } });

  // b. RESOLVE CONTEXT — what the planner filled from what it was given, and case memory by meaning.
  const facts: Fact[] = (plan.facts ?? []).map((f) => ({
    name: String(f.name || ''), why: String(f.why || ''), changes_answer: f.changes_answer === true,
    value: f.value == null || String(f.value).trim() === '' || String(f.value) === 'null' ? null : String(f.value), from: f.from ? String(f.from) : null,
  })).filter((f) => f.name);
  const sources: Source[] = [];
  // The space is asked once per run. If the multilingual embedder cannot answer, this run falls back to
  // gte-small and the gte routines: a slower-to-improve answer, never a vector put to the wrong space.
  // A LEAN CHOICE AMONG FIXED OPTIONS FOR AN EXTERNAL AUDIENCE RECALLS NOTHING (it_engineer, 10 Nov 2026; WhatsApp latency R4/R5).
  // Such a request hands over an empty plan (nothing is retrieved) and another party's case never reaches an external prompt
  // (below), so the recall's embedding, space read, recall and handoff reads were round trips ahead of the one model call that
  // could change nothing it decides: WhatsApp's classification (whatsappReadings) and its needs-a-person reading. The learning
  // loop's judgement row is still opened, its recall trace saying why. Prevented by: think_lean_decision_recalls_nothing.test.ts.
  const noRecall = req.lean === true && deciding && EXTERNAL_AUDIENCES.has(audience) && !!req.plan && planSteps.length === 0;
  let space: EmbedSpace = noRecall ? 'gte' : deps.space ? await deps.space().catch(() => 'gte' as EmbedSpace) : 'gte';
  // One embedding per text per run (12 Oct 2026): a plan step whose query IS the question re-embedded it remotely,
  // 1-3 s each on the widget path (measured per stage).
  const memo = new Map<string, Promise<number[] | null>>();
  const emb = (t: string, sp: EmbedSpace) => { const k = sp + '\u0001' + t; if (!memo.has(k)) memo.set(k, deps.embed(t, sp)); return memo.get(k)!; };
  const embedIn = async (t: string): Promise<{ v: number[] | null; r: typeof ROUTINES[EmbedSpace] }> => {
    if (space === 'ml') {
      const v = await emb(t, 'ml');
      if (v) return { v, r: ROUTINES.ml };
      space = 'gte';
    }
    return { v: await emb(t, 'gte'), r: ROUTINES.gte };
  };
  // A caller's plan is known now: its step queries are embedded (remotely, in embed_ml — no work in this worker) while
  // the question is, not after the recall (12 Oct 2026: 1.7-8 s of embedding in a row on the widget, measured per stage).
  if (req.plan && space === 'ml') for (const s of req.plan.steps) emb(s.query, 'ml').catch(() => null);
  // THE SHARED POOL (ceo, 13 Nov 2026, founder ledger 1688): what every other seat did on this subject and in the company
  // today, from ONE routine (_shared/seat_pool.ts). Read beside the recall, so it adds no wait; a lean choice among fixed
  // options reads no case text and no pool. Empty on any failure: the answer never waits on it.
  const poolP = req.lean === true ? Promise.resolve({ block: '', chars: 0 })
    : seatPool(deps, req.seat, poolSubject(req.subject, ctx.case, ctx.profile), audience);
  const q0 = noRecall ? { v: null, r: ROUTINES.gte } : await embedIn(req.question);
  const qVec = q0.v;
  // Recall goes through the ONE shared recall (case_recall.ts), which also opens this judgement's row in
  // public.seat_judgement carrying what was recalled — the recall record the outcome is later written onto.
  const memory = noRecall
    ? await openJudgementWithoutRecall(deps, { seat: req.seat, path: req.surface, situation: req.question, subject: req.subject ?? null,
        reason: 'not_recalled: a lean choice among fixed options for an external audience reads no case text' })
    : await recallCases(deps, { seat: req.seat, path: req.surface, situation: req.question, trade: ctx.trade ?? null, k: 3, ...(q0.r === ROUTINES.ml ? { embeddingMl: qVec } : { embedding: qVec }), subject: req.subject ?? null });
  judgementId = memory.judgement_id ?? null;
  // ANOTHER PARTY'S CASE NEVER REACHES AN EXTERNAL PROMPT (18 Oct 2026, sandbox run d6cf4793 turn 16). A case's
  // situation is the raw record it was opened from: a quote case carries another customer's inquiry id, amount and
  // scope. In a customer's portal reply it was read back as "the quote record refers to 40 aluminium windows".
  // The recall still runs and is recorded on the judgement; only an internal audience reads the case text.
  if (!EXTERNAL_AUDIENCES.has(audience)) for (const c of memory.cases) sources.push({ id: 'case#' + c.case_id, kind: 'case_memory', title: `${c.seat}/${c.case_kind} ${c.finalised ? 'FINALISED' : 'not finalised'}`, excerpt: [c.situation, c.decision && 'decided: ' + c.decision, c.outcome && 'outcome: ' + c.outcome, c.correction && 'CORRECTED: ' + c.correction].filter(Boolean).join(' | ').slice(0, 900), citation: null, similarity: c.similarity ?? null, trust: 'case_memory' });
  steps.push({ id: 'resolve', kind: 'resolve', goal: 'fill the deciding facts from the conversation, profile, case and case memory', status: 'done', detail: { known: facts.filter((f) => f.value).map((f) => f.name), missing: facts.filter((f) => !f.value).map((f) => f.name), recalled: memory.cases.length, recall: memory.available ? 'ok' : memory.reason, judgement_id: judgementId, space: q0.r === ROUTINES.ml ? 'ml' : 'gte' } });

  // c. RETRIEVE PER STEP, d. RESEARCH where knowledge is thin
  const thin: typeof planSteps = [];
  // THE QUESTION AS ASKED IS RETRIEVED TOO (ceo, ledger 1003 stage 2, 19 Oct 2026). The planner's queries are its
  // paraphrase of the question; when they drift, the pack entry the question itself lands on is never fetched. One more
  // call on the question's own vector (already embedded for the recall above). It never triggers research: thin is what
  // the PLAN could not find. A caller that hands over its own plan (the widget, a reader) keeps exactly its plan.
  const asked = !req.plan && !planSteps.some((s) => s.query === req.question) ? [{ id: 'q', goal: 'the question as asked', query: req.question, needs: true }] : [];
  for (const s of [...planSteps, ...asked]) {
    if (!s.needs) { steps.push({ id: s.id, kind: 'retrieve', goal: s.goal, status: 'skipped' }); continue; }
    const { v, r: rt } = await embedIn(s.query);
    // The reason rides in the detail (27 Oct 2026: five rows read 'embedding_unavailable' and nothing said why).
    if (!v) { const why = deps.embedFailure?.(s.query, 'gte') ?? deps.embedFailure?.(s.query, 'ml') ?? null; steps.push({ id: s.id, kind: 'retrieve', goal: s.goal, status: 'failed', detail: why ? 'embedding_unavailable: ' + why : 'embedding_unavailable' }); thin.push(s); continue; }
    // The multilingual search fuses both spaces (fn_reason_retrieve_ml), so it takes the gte-small vector too;
    // without one it ranks by the multilingual space alone. An Arabic question gets none: gte-small is English-only
    // and its vector for Arabic text pulled the fused ranking down (gteReads, _shared/ml_embed_recipe.ts).
    const vg = rt === ROUTINES.ml && gteReads(s.query) ? await deps.embed(s.query, 'gte') : null;
    // The right area first (knowledge_lookup_goes_to_the_trade_first.sql): the routine resolves the trade and the
    // area exactly and ranks only that trade's entries / that area's rows plus the seat's general ones. Each is sent
    // only when known, so a call without them is the call it always was.
    // p_audience (a_seats_own_pack_fills_half_of_every_retrieval.sql): the routine returns the company's own facts
    // (rows tagged audience:internal) and reserves the seat's own rows ONLY for an audience named internal or founder.
    // The resolved audience is sent (audienceOf): a missing or unknown one is 'visitor' here exactly as everywhere else.
    const area = { ...(trade ? { p_trade: trade } : {}), ...(kind ? { p_kind: kind } : {}), ...(ctx.area ? { p_area: ctx.area } : {}), p_audience: audience };
    const { data, error } = await deps.rpc(rt.retrieve, rt === ROUTINES.ml
      ? { p_seat: req.seat, p_embedding: vec(v), p_embedding_gte: vg ? vec(vg) : null, p_k: 6, ...area }
      : { p_seat: req.seat, p_embedding: vec(v), p_k: 6, ...area });
    const rows = !error && Array.isArray(data) ? data : [];
    // prompt diet (content, OFF by default): only the step's top rows near its best similarity reach the prompt (think/diet.ts)
    const sent = topRows ? keepTopRows(rows, topRows) : rows;
    for (const r of sent) {
      const id = `${r.source}:${r.id}`;
      if (!sources.some((x) => x.id === id)) sources.push({ id, kind: String(r.source), title: String(r.title ?? ''), excerpt: String(r.excerpt ?? '').slice(0, EXCERPT_MAX), citation: r.citation ?? null, similarity: Number(r.similarity), trust: r.trust === 'pending_review' ? 'pending_review' : 'reviewed' });
    }
    // best is over every row the routine returned, so what counts as thin (and goes to research) is unchanged by the cut
    const best = rows.reduce((m: number, r: { similarity?: number }) => Math.max(m, Number(r.similarity) || 0), 0);
    steps.push({ id: s.id, kind: 'retrieve', goal: s.goal, status: error ? 'failed' : 'done', detail: { rows: rows.length, ...(topRows ? { kept: sent.length } : {}), best: Math.round(best * 1000) / 1000, space: rt.retrieve === ROUTINES.ml.retrieve ? 'ml' : 'gte', error: error?.message } });
    if (best < rt.floor && s.id !== 'q') thin.push(s);
  }
  const doResearch = (req.research ?? !deciding) && thin.length > 0 && deps.search && deps.read;
  const researched: Source[] = [];
  if (doResearch) {
    for (const s of thin.slice(0, 2)) {
      const hits = (await deps.search!(s.query).catch(() => [])).filter((h) => authoritative(h.url)).slice(0, MAX_RESEARCH_PAGES);
      const pages: { url: string; title: string; text: string }[] = [];
      for (const h of hits) { const t = await deps.read!(h.url).catch(() => null); if (t) pages.push({ url: h.url, title: h.title, text: t.slice(0, 6000) }); }
      if (!pages.length) { steps.push({ id: s.id + ':research', kind: 'research', goal: s.goal, status: 'skipped', detail: { hits: hits.length, reason: 'no authoritative page read' } }); continue; }
      const r = await deps.llm('research', RESEARCH_PROMPT, JSON.stringify({ question: s.query, pages }), { taskClass: taskClassFor('research', audience, deciding), seat: req.seat, max: 900 });
      const found = parseJson<{ findings?: { statement?: string; url?: string }[] }>(r.content)?.findings ?? [];
      const valid = found.filter((f) => f.statement && f.url && pages.some((p) => p.url === f.url));
      valid.forEach((f, i) => researched.push({ id: `web:${s.id}.${i + 1}`, kind: 'web', title: pages.find((p) => p.url === f.url)!.title, excerpt: String(f.statement).slice(0, 900), citation: f.url!, url: f.url!, similarity: null, trust: 'web' }));
      steps.push({ id: s.id + ':research', kind: 'research', goal: s.goal, status: 'done', detail: { pages: pages.map((p) => p.url), findings: valid.length } });
    }
    sources.push(...researched);
  }

  // e. SYNTHESISE, with the validator forcing re-passes
  const missing = facts.filter((f) => !f.value);
  const sourceIds = new Set(sources.map((s) => s.id));
  const synthSys = synthesisPrompt(req.seat, audience, ctx.language ?? 'en', req.decision, req.route, req.allowDecline === true)
    + (req.ask && !deciding ? `
Also set "${req.ask.key}" in the same JSON object to exactly one of: ${req.ask.options.map((o) => `${o.id} (${o.meaning})`).join('; ')}.` : '')
    + (req.also ?? []).map((a) => `
Also set "${a.key}" in the same JSON object to exactly one of: ${a.options.map((o) => `${o.id} (${o.meaning})`).join('; ')}.`).join('')
    + (req.lean === true && deciding ? LEAN_DECIDE_NOTE : '');
  const synthMax = req.lean === true && deciding ? LEAN_DECIDE_MAX : req.maxTokens?.synthesise ?? SYNTH_MAX;
  // a re-asked question is written by another family than the one that failed it (types.ts otherFamilyThan)
  const synthRoute = req.otherFamilyThan ? { counterpartModel: req.otherFamilyThan } : {};
  const pool = await poolP;
  if (pool.chars) steps.push({ id: 'pool', kind: 'resolve', goal: 'read what the other seats did on this subject and in the company today', status: 'done', detail: { chars: pool.chars } });
  const payload = { question: req.question, context: ctx, plan: planSteps, facts_known: facts.filter((f) => f.value), facts_missing: missing, sources, ...(pool.block ? { shared_pool: pool.block } : {}) };
  let draft: Draft | null = null; let model: string | null = null; let refusal: string | null = null;
  for (let pass = 1; pass <= (deciding ? 2 : MAX_SYNTH_PASSES); pass++) {
    // prompt diet (structural, ON): the re-pass note ends the input, so the system prompt and the payload stay a cached prefix
    const at = placeRetryNote(notesAfter, synthSys, JSON.stringify(payload), refusal ? `\n\nYOUR PREVIOUS DRAFT WAS REFUSED: ${refusal}. Write it again, correctly.` : '');
    const r = await deps.llm('synthesise', at.system,
      at.input, { taskClass: taskClassFor('synthesise', audience, deciding, ctx.language ?? 'en'), seat: req.seat, max: synthMax, sysStable: facts0, ...synthRoute, ...(req.effort ? { effort: req.effort } : {}) });
    draft = parseJson<Draft>(r.content); model = r.model ?? model;
    if (req.reader && draft && typeof draft === 'object') {
      draft.asked_back = null;
      const dropped = keepProvenFields(draft, req.decision, textOf(ctx) + '\n' + req.question);
      if (dropped.length) steps.push({ id: 'synthesise.' + pass + '.fields', kind: 'synthesise', goal: 'keep only the fields the person\'s own words prove', status: 'done', detail: { dropped } });
    }
    if (!r.content) { steps.push({ id: 'synthesise.' + pass, kind: 'synthesise', goal: 'write the answer', status: 'failed', detail: r.error }); refusal = 'no reply'; break; }
    groundDraft(draft, missing);
    refusal = refuse(draft, { allowDecline: req.allowDecline === true, missing, sourceIds: citable(sourceIds, facts0, draft), decision: req.decision, conversationText: textOf(ctx) + '\n' + req.question, requireTrail: true, ...(req.reader ? { minEvidence: READER_MIN_EVIDENCE } : {}) });
    steps.push({ id: 'synthesise.' + pass, kind: 'synthesise', goal: 'write the answer', status: refusal ? 'refused' : 'done', detail: refusal ?? undefined });
    if (!refusal) break;
  }
  if (refusal || !draft) return await hold('model_failed: ' + (refusal ?? 'no draft'), { plan: planSteps, facts, sources: sources.map((s) => s.id) });

  // f. VERIFY — high stakes, by a model of another family (#877)
  let verified: ThinkResult['verified'] = { status: 'not_needed', by: null, notes: '' };
  let confidence = Math.max(0, Math.min(1, Number(draft.confidence) || 0));
  if (req.stakes === 'high' || (!deciding && plan.high_stakes === true)) {
    // The caller's rewrite runs BEFORE the check, one after the other, so the text the reviewer reads is the text
    // that goes out (12 Oct 2026: a rewrite after the check sent unchecked words; beside it, it killed the worker).
    if (!deciding && req.polish) {
      const p = await req.polish(String(draft.answer ?? '')).catch(() => null);
      if (p) { draft = { ...draft, answer: p }; steps.push({ id: 'polish', kind: 'synthesise', goal: "the caller's rewrite, before the check", status: 'done' }); }
    }
    // CODE FIRST (it_engineer, 3 Nov 2026). Measured: 52 knowledge_validation calls a week on Sonnet, 23-48k mostly
    // uncached prompt tokens each, for an ~18-token verdict. What the check looks for is a limit, a sum or a safety
    // statement the sources do not support; a figure is the part code can prove. When every figure the answer states,
    // with the word that follows it, is printed in the sources or the settled facts, code agrees and no model is asked.
    // An answer with no figure, or with one the sources do not print, still goes to the independent model. So does every
    // answer a customer, supplier or visitor reads (their text is checked whole, review of #1330), and every request whose
    // caller DEMANDED the check (stakes 'high'): code decides only the seat's own answers the planner judged high-stakes.
    if (INTERNAL_AUDIENCES.has(audience) && req.stakes !== 'high' && figuresGrounded(String(draft.answer ?? ''), [facts0, ...sources.map((s) => s.title + '\n' + s.excerpt)])) {
      verified = { status: 'agreed', by: 'code', notes: 'every figure in the answer is printed in the sources or the settled facts' };
      steps.push({ id: 'verify', kind: 'verify', goal: 'independent check of a high-stakes answer', status: 'done', detail: verified });
    } else {
    // prompt diet (content, OFF by default): the reviewer may be sent only the sources the answer cites (think/diet.ts)
    const reviewed = reviewSources(dietOn(diet, 'the_reviewer_reads_the_cited_sources_only', taskClassFor('verify', audience, deciding)), sources, draft.cited);
    const v = await deps.llm('verify', VERIFY_PROMPT + (req.maxTokens?.verify ? '\nReturn ONLY that JSON object, no other text: "problems" is [] when you agree, else at most two short items.' : ''), JSON.stringify({ question: req.question, answer: draft.answer, decision: draft.decision ?? null, sources: reviewed }),
      { taskClass: taskClassFor('verify', audience, deciding), seat: req.seat, counterpartModel: model, max: req.maxTokens?.verify ?? 600, sysStable: facts0 });
    const vj = parseJson<{ verdict?: string; problems?: string[] }>(v.content);
    if (!vj || !v.content) {
      verified = { status: 'not_run', by: v.model ?? null, notes: String(v.error ?? 'no independent reviewer answered') };
      confidence = Math.min(confidence, 0.6);
    } else if (vj.verdict === 'agree') {
      verified = { status: 'agreed', by: v.model ?? null, notes: '' };
    } else {
      // One corrective pass with the reviewer's problems; the second reading is final and marked.
      const at = placeRetryNote(notesAfter, synthSys, JSON.stringify(payload), `\n\nAN INDEPENDENT REVIEWER FOUND PROBLEMS: ${(vj.problems ?? []).join(' | ')}. Correct them.`);
      const r = await deps.llm('synthesise', at.system,
        at.input, { taskClass: taskClassFor('synthesise', audience, deciding, ctx.language ?? 'en'), seat: req.seat, max: synthMax, sysStable: facts0, ...synthRoute, ...(req.effort ? { effort: req.effort } : {}) });
      const fixed = parseJson<Draft>(r.content);
      if (req.reader && fixed && typeof fixed === 'object') { fixed.asked_back = null; keepProvenFields(fixed, req.decision, textOf(ctx) + '\n' + req.question); }
      if (fixed) groundDraft(fixed, missing);
      if (fixed && !refuse(fixed, { allowDecline: req.allowDecline === true, missing, sourceIds: citable(sourceIds, facts0, fixed), decision: req.decision, conversationText: textOf(ctx) + '\n' + req.question, requireTrail: true, ...(req.reader ? { minEvidence: READER_MIN_EVIDENCE } : {}) })) { draft = fixed; model = r.model ?? model; }
      verified = { status: 'disagreed', by: v.model ?? null, notes: (vj.problems ?? []).join(' | ').slice(0, 1000) };
      confidence = Math.min(confidence, 0.5);
    }
    steps.push({ id: 'verify', kind: 'verify', goal: 'independent check of a high-stakes answer', status: 'done', detail: verified });
    }
  }

  // Research that was cited goes back as pending knowledge, so the next question is answered from knowledge.
  const citedWeb = researched.filter((s) => (draft!.cited ?? []).includes(s.id));
  for (const s of citedWeb) {
    const e = await deps.embed(s.excerpt);
    // An outside party's message is never stored as the question: the row is retrievable by every seat and its question is
    // printed as a source title in other people's replies (18 Oct 2026, run d6cf4793 review). The plan step's research
    // query — written by the planner, about the subject, not the person — is stored instead.
    const asked = EXTERNAL_AUDIENCES.has(audience) ? (planSteps.find((p) => s.id.startsWith('web:' + p.id + '.'))?.query ?? s.title) : req.question;
    await deps.rpc('fn_reason_propose_knowledge', { p_seat: req.seat, p_question: asked.slice(0, 2000), p_finding: s.excerpt, p_sources: [{ url: s.url, title: s.title }], p_embedding: e ? vec(e) : null });
  }

  const fields: Record<string, { value: string; evidence: string }> = {};
  for (const [k, f] of Object.entries(draft.decision?.fields ?? {})) fields[k] = { value: String(f?.value ?? ''), evidence: String(f?.evidence ?? '') };
  await settle('answered', { decision: deciding ? (draft.decision?.choice ? String(draft.decision.choice) : JSON.stringify(fields)) : String(draft.answer), confidence, model,
    followed: (draft.cited ?? []).filter((id) => /^case#\d+$/.test(String(id))).map((id) => Number(String(id).slice(5))) });
  return {
    status: 'answered', answer: String(draft.answer).trim(),
    decision: deciding ? { choice: draft.decision?.choice ? String(draft.decision.choice) : null, fields } : null,
    steps, context_used: { ...base.context_used, facts_known: facts.filter((f) => f.value) },
    missing_context: missing, sources: sources.filter((s) => (draft!.cited ?? []).includes(s.id)),
    confidence, asked_back: draft.asked_back ? String(draft.asked_back) : null, verified, model,
    route: req.route?.some((o) => o.id === String(draft!.route ?? '')) ? String(draft!.route) : null,
    also: req.also ? Object.fromEntries(req.also.map((a) => { const v = String((draft as unknown as Record<string, unknown>)[a.key] ?? ''); return [a.key, a.options.some((o) => o.id === v) ? v : null]; })) : undefined,
    extra: req.ask?.options.some((o) => o.id === String((draft as unknown as Record<string, unknown>)[req.ask!.key] ?? '')) ? String((draft as unknown as Record<string, unknown>)[req.ask.key]) : null,
  };
}
