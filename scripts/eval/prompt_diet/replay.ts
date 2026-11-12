// THE PROMPT DIET'S PAID ROUND: OLD vs NEW prompt on the SAME model, and the cheaper reviewer and fallback side by side
// (it_engineer, 11 Nov 2026; founder rulings 1619 and 1618; report docs/reports/2026-11-11-prompt-diet.md). Started only by
// scripts/eval/prompt_diet_eval.mjs run (which prints the expected cost and the pass rules first); NEVER run in an offline pass.
//
// FIVE PARTS (cases from `prompt_diet_eval.mjs sample`: anonymised, recorded internal duty questions and public headlines):
//   P1 retrieval_keeps_the_top_rows_above_a_floor  internal_judgement on Luna Pro. Arm OLD runs think() as production does;
//      arm NEW reuses OLD's plan (the decompose answer is replayed, not asked again) and the SAME retrieved rows (every
//      read is memoised per case), so the cut is the only difference. Judge: Qwen 3.8 Flash (not the author's family).
//   P2 a_trend_relevance_choice_plans_and_retrieves_nothing  marketing.trend_relevance on Luna Pro, OLD with its plan and
//      retrieval, NEW with neither. The choice must agree; the judge compares the one-line reasons.
//   P3 the_reviewer_reads_the_cited_sources_only  the live reviewer route (Qwen 3.8 Flash) reads P1's OLD answer twice: every
//      source vs the cited ones; and once more each with a seeded wrong figure. Verdicts must agree; no seeded defect missed.
//   P4 the reviewer side by side: Claude Haiku 5.5 vs Claude Sonnet 5.5 on eval C's 60 drafts (labels known by construction).
//   P5 the fallback side by side: Haiku 5.5 vs Sonnet 5.5 re-answering P1's NEW payload (internal classes only: ledger 1217
//      keeps customer chat off the small Claude model). Judge: Qwen 3.8 Flash.
//
// SAFETY. Every model call goes to OpenRouter directly (Haiku 5.5 is not routable until its pending registry row is applied)
// and is written to ai_cost_log under this run's tag with OpenRouter's reported cost, inside a rehearsal window whose cap
// is this run's cap; guardSpend stops the run before any call that would reach it. Retrieval reads production read-only
// routines; every routine that WRITES (case recall's judgement row, holds, decisions, knowledge proposals) is answered by a
// stub here and never called. Nothing is sent to a person. The cases file holds anonymised text only and stays outside the
// repository.
//
//
// NINE THINGS THE HARNESS GOT WRONG, EACH MEASURED IN THE PAID ROUND BEFORE IT WAS CHANGED (it_engineer, final audit, 11 Nov 2026):
//   1. Every sampled question carries subject {fixture: true} (the sampler's anonymiser sets it) and think() holds a fixture
//      'fixture_no_spend' outside a PROVEN open rehearsal window (think/routing.ts fixtureInOpenWindow). The replay proved no
//      run and stubbed fn_e2e_run_tag_open as a write, so 16 of 16 P1 cases were held with 0 model calls (replayed offline
//      with a stub model) and P3 and P5 would have had no answer to read. think() now runs inside E2E_RUN for this run's own
//      tag and the window read is a real read: a fixture reasons only while this run's window is open, as in production.
//   2. Every call was booked as knowledge_validation with counterpart Luna Pro, the AUTHOR calls included. knowledge_validation
//      is a review class (model_policy.reviews_class), so trg_ai_cost_log_review_family would have written SAME_FAMILY_REVIEW on
//      every Luna Pro plan and answer row, and scripts/checks/no_review_class_can_route_to_its_authors_family.test.mjs fails
//      on any such row for 30 days (0 rows before this run). A call is now booked under the class of the step it is: the plan
//      routine_employee_reasoning, the answer internal_judgement, a review or a judge knowledge_validation naming its author.
//   3. fn_ai_cost_log_e2e_run_tag sets a cost row's tag to NULL once the run's window is closed or past expires_at, and the
//      spend guard reads spend BY TAG: a run that outlived its window (110 minutes; five parts in one run is about 90) would
//      have spent unseen and untagged. Before every call the window is read; after every call the row must still carry the tag.
//   4. The result file held verdicts and no answer, so a person could not read OLD against NEW. --answers <file> (outside the
//      repository) writes each case's question, both answers and the judge's reading.
//   5. Found while the first paid parts ran: since ruling 1630 (11 Nov, _shared/effort_policy.ts) ai_gateway sends every call
//      the effort of its class, 'high' for internal_judgement, routine_employee_reasoning and knowledge_validation
//      (production, 11 Nov 20:00 UTC on: the internal answer wrote 6,257 output tokens in 53.6 s against about 2,500 in 25 s
//      before). This replay named no effort, so both arms ran at the model's own default: not the call production makes.
//      --effort policy (the default now) sends effortFor(class), as the gateway does; --effort model-default is the first
//      runs' behaviour, kept so they can be reproduced. Every result file states which it ran with.
//   6. The judge is this eval's instrument, not a production call, and at the class's 'high' effort it never answered: Qwen
//      3.8 Flash wrote its whole budget (900 + 8,000 headroom = 8,900 tokens) as reasoning and returned no verdict, 3 of 3 P1
//      judge calls in the first policy-effort runs (124-126 s each); at the model's default it was empty on 2 of 16 P2 pairs.
//      The judge now names its own effort (medium, then low on the one retry) with a 6,000-token answer budget. The review
//      INSIDE think() is production's call and keeps the class's effort and budget: when it returns nothing, that is what
//      production's reviewer does too, and the result file counts it (reviews_not_run).
//   7. The judge was not shown what the answers were written from. It read the question, the settled facts and the sources
//      the OLD answer cited; it never read the request's CONTEXT (the case a duty question comes with: the experiment, the
//      forecast, the competitor's page) and, in P5, never the sources the two models were given. So it listed as a
//      violation any figure an answer took from its own case (P5: "states exact competitor prices not supported by
//      sources", printed in the page text the judge was not given), and it never saw the decision, only the prose. The
//      judge now reads the context, the decision beside the answer, and in P5 the very sources both models read. Parts J1
//      and J5 re-judge the pairs an earlier run wrote (--rejudge <its answers file> --carry <its carry file>) without
//      asking for the answers again; an old model that returned no answer where the new one answered is scored by code.
//   8. One provider error failed a whole part. The first P1 case's judge call came back with no body after 50 s and the case
//      was scored "worse" with the violation 'unread judge answer': the cut was failed by the transport, not by an answer.
//      A judge call writes nothing, so an unread one is asked once more. A call that throws (a timeout) no longer ends the
//      run: it is booked with the estimate as its cost (OpenRouter may have billed it and never told us) and reads as a
//      model that did not answer. --carry <file> (outside the repository) keeps the answers P3 and P5 read, so they can run
//      later, under their own cap and window, without paying for P1 again.
//   9. Nothing measured how often the SAME prompt answers differently. Each arm is asked once, at temperature 0.2 and with
//      reasoning, and the pass rule needs every pair equal. In the first seven P1 pairs the two arms chose differently in 4 of
//      5 decisions while NEW had been given every row OLD cited in the two it lost. --control runs P1 with the NEW arm on the
//      SAME prompt as OLD (no cut), so the judge's "worse" and the changed choices of an unchanged prompt can be counted: the
//      noise the rule has to be read against. A control run is never a verdict on the switch.
//      Also: a run that stops mid-part now keeps the rows it finished (results.P1 was only written after the last case).
//
//   deno run -A --node-modules-dir=none scripts/eval/prompt_diet/replay.ts --cases <file> --cap 1.45 [--out <dir>] [--parts P1,P2,P3,P4,P5,J1,J5]
//     [--effort policy|model-default] [--answers <file>] [--carry <file>] [--rejudge <file>] [--control]
import { arg, CapReached, closeWindow, connect, guardSpend, newTag, openWindow, spentUsd, writeJson, type Ctx } from '../model_routing/harness.ts';
import { CASES_C } from '../model_routing/cases_c.ts';
import { defaultDeps, figuresGrounded, settledFacts, think, VERIFY_PROMPT, type ThinkDeps, type ThinkRequest } from '../../../supabase/functions/_shared/think.ts';
import { shapeRequest } from '../../../supabase/functions/_shared/request_shape.ts';
import { judgeTrend } from '../../../supabase/functions/marketing/duties/trends_geo.ts';
import type { DietOverrides } from '../../../supabase/functions/_shared/prompt_diet.ts';
import { E2E_RUN } from '../../../supabase/functions/_shared/e2e_run.ts';
import { effortFor } from '../../../supabase/functions/_shared/effort_policy.ts';

export const LUNA = 'openai/gpt-6-luna-pro', QWEN = 'qwen/qwen3.8-flash', SONNET = 'anthropic/claude-sonnet-5.5', HAIKU = 'anthropic/claude-haiku-5.5';
const CAP = Number(arg('--cap') ?? '1.45');
if (!(CAP > 0 && CAP <= 1.5)) throw new Error('the cap is at most USD 1.50 (the paid round\'s budget)');
const OUT = arg('--out') ?? 'docs/reports/prompt-diet-2026-11-11';
// P4's drafts: eval C's fixed set (labels known by construction); --p4 is accepted for symmetry and must be 60.
if ((arg('--p4') ?? '60') !== '60') throw new Error('P4 runs eval C\'s whole set of 60 drafts');
const PARTS = new Set((arg('--parts') ?? 'P1,P2,P3,P4,P5').split(','));
const EFFORT = (arg('--effort') ?? 'policy') as 'policy' | 'model-default';
if (EFFORT !== 'policy' && EFFORT !== 'model-default') throw new Error('--effort is policy (as ai_gateway sends it) or model-default');
const CARRY = arg('--carry');
if (CARRY && CARRY.startsWith(Deno.cwd() + '/')) throw new Error('--carry holds recorded text; write it outside the repository');
const ANSWERS = arg('--answers');
if (ANSWERS && ANSWERS.startsWith(Deno.cwd() + '/')) throw new Error('--answers holds recorded text; write it outside the repository');
const answersLog: Record<string, unknown>[] = [];
const casesFile = arg('--cases');
if (!casesFile) throw new Error('--cases <file> (made by: node scripts/eval/prompt_diet_eval.mjs sample)');
type Cases = { internal: ThinkRequest[]; trends: { id: number; title: string; url: string; source: string }[] };
const CASES = JSON.parse(await Deno.readTextFile(casesFile)) as Cases;

const { admin, secret } = await connect();
const tag = newTag('evaldiet');
const c: Ctx = { admin, tag, secret, capUsd: CAP };
const key = String((await admin.from('app_secrets').select('value').eq('key', 'openrouter_api_key').maybeSingle()).data?.value ?? '');
if (!key) throw new Error('openrouter_api_key could not be read');

// ── one door to a model: OpenRouter, shaped as the gateway shapes it, booked in ai_cost_log under the run tag ─────────
const EST: Record<string, number> = { [LUNA]: 0.012, [QWEN]: 0.008, [SONNET]: 0.08, [HAIKU]: 0.006 };
const REVIEW = 'knowledge_validation', ANSWER = 'internal_judgement';
/** The window this run's cost rows are tagged in must be open, or the next row loses its tag and the spend guard goes blind. */
async function guardWindow(why: string): Promise<void> {
  const { data, error } = await admin.rpc('fn_e2e_run_tag_open', { p_tag: tag });
  if (error || data !== true) throw new CapReached(`the rehearsal window qd_run:${tag} is not open (${error?.message ?? 'closed or expired'}); ${why} is not asked`);
}
/** cls: the class of the step this call IS (the row is booked under it). author: the model whose work a review or judge reads; null for an author's own call. */
async function ask(model: string, system: string, input: string, max: number, why: string, cls: string = REVIEW, author: string | null = LUNA, callerEffort: string | null = null, instrument: 'low' | 'medium' | null = null): Promise<{ content: string; model: string | null; error?: string }> {
  if (cls === REVIEW && !author) throw new Error('a review call names the model whose work it reads');
  await guardWindow(why);
  await guardSpend(c, EST[model] ?? 0.05, why);
  const t0 = Date.now();
  let res: Response;
  try { res = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', signal: AbortSignal.timeout(240_000),
    headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json', 'X-Title': 'QuotesDone prompt diet eval' },
    body: JSON.stringify({ model, ...shapeRequest({ model, maxTokens: max, temperature: 0.2, responseFormat: { type: 'json_object' }, ...(instrument ? { effort: instrument } : EFFORT === 'policy' ? { effort: effortFor(cls, callerEffort) } : {}),
      supported: new Set(['reasoning', 'response_format', 'structured_outputs', 'tools']) }), usage: { include: true },
      messages: [{ role: 'system', content: system }, { role: 'user', content: input }] }) }); }
  catch (e) {
    // no answer and no usage: the estimate is booked as cost_aed (spentUsd reads it when no reported cost exists), so the cap counts it
    const { error } = await admin.from('ai_cost_log').insert({ fn: 'resilience_ping', agent_key: 'it_engineer', seat: 'it_engineer', task_class: cls, model_used: model,
      model_selected_because: 'prompt diet eval (rulings 1619, 1618): NO ANSWER (' + String((e as Error)?.name ?? e) + '), cost unknown, the estimate is booked: ' + why, tier: 'eval',
      prompt_tokens: 0, output_tokens: 0, cached: false, ok: false, cost_aed: (EST[model] ?? 0.05) * 3.6725, e2e_run_tag: tag, counterpart_model: cls === REVIEW ? author : null, latency_ms: Date.now() - t0 });
    if (error) throw new Error('the cost row could not be written, the run stops: ' + error.message);
    return { content: '', model: null, error: 'no answer: ' + String((e as Error)?.message ?? e).slice(0, 120) };
  }
  const j = await res.json().catch(() => null) as { choices?: { message?: { content?: string } }[]; usage?: { prompt_tokens?: number; completion_tokens?: number; cost?: number; prompt_tokens_details?: { cached_tokens?: number } }; model?: string; id?: string; error?: { message?: string } } | null;
  const content = String(j?.choices?.[0]?.message?.content ?? '');
  const { data: booked, error } = await admin.from('ai_cost_log').insert({ fn: 'resilience_ping', agent_key: 'it_engineer', seat: 'it_engineer', task_class: cls,
    model_used: j?.model ?? model, model_selected_because: 'prompt diet eval (rulings 1619, 1618): ' + why, tier: 'eval',
    prompt_tokens: j?.usage?.prompt_tokens ?? 0, output_tokens: j?.usage?.completion_tokens ?? 0, cached: false, ok: res.ok && !!content,
    cached_in_tokens: j?.usage?.prompt_tokens_details?.cached_tokens ?? 0, cost_usd_reported: Number(j?.usage?.cost ?? 0), e2e_run_tag: tag,
    counterpart_model: cls === REVIEW ? author : null, latency_ms: Date.now() - t0, generation_id: j?.id ?? null }).select('e2e_run_tag,review_violation').single();
  if (error) throw new Error('the cost row could not be written, the run stops: ' + error.message);
  if (booked?.e2e_run_tag !== tag) throw new Error('the cost row lost its run tag (the window closed during the call), the run stops: its spend is no longer seen by the cap');
  if (booked?.review_violation) throw new Error('the cost row was flagged ' + booked.review_violation + ', the run stops');
  return { content, model: j?.model ?? null, ...(res.ok && content ? {} : { error: 'HTTP ' + res.status + ' ' + String(j?.error?.message ?? 'empty').slice(0, 120) }) };
}
const parse = <T>(s: string): T | null => { try { return JSON.parse(s.slice(s.indexOf('{'), s.lastIndexOf('}') + 1)) as T; } catch { return null; } };

// ── think() with the production prompt, a fixed model, read-only retrieval, and the writes stubbed ─────────────────────
const READ_ONLY = new Set(['fn_reason_retrieve', 'fn_reason_retrieve_ml', 'fn_kernel_paid_provider_gate', 'fn_ml_read_space', 'fn_e2e_run_tag_open']);
/** think() as this run: the sampled questions are fixtures, and a fixture reasons only for a proven tag whose window is open. */
const inRun = <T>(f: () => Promise<T>): Promise<T> => E2E_RUN.run({ tag, secret }, f);
function replayDeps(diet: DietOverrides, memo: Map<string, unknown>, plan?: string): ThinkDeps & { plan?: string } {
  const live = defaultDeps(admin, 'resilience_ping', { gte: 'remote' });
  const out: ThinkDeps & { plan?: string } = {
    gate: () => Promise.resolve({ allowed: true } as never),
    embed: (t, sp) => { const k = 'embed\u0001' + sp + '\u0001' + t; if (!memo.has(k)) memo.set(k, live.embed(t, sp)); return memo.get(k) as Promise<number[] | null>; },
    space: () => { if (!memo.has('space')) memo.set('space', live.space!()); return memo.get('space') as Promise<'gte' | 'ml'>; },
    rpc: (fn, args) => {
      if (!READ_ONLY.has(fn)) return Promise.resolve({ data: fn.startsWith('fn_case_recall') ? { cases: [], judgement_id: null } : null, error: null });
      const k = fn + '\u0001' + JSON.stringify(args); if (!memo.has(k)) memo.set(k, live.rpc(fn, args)); return memo.get(k) as never;
    },
    diet: () => Promise.resolve(diet),
    llm: async (phase, system, input, o) => {
      if (phase === 'decompose' && plan !== undefined) return { content: plan, model: LUNA };
      const sys = (o.sysShared ?? '') + (o.sysStable ?? '') + system;    // the gateway's own order (system_message.ts)
      const model = phase === 'verify' ? QWEN : LUNA;
      const r = await ask(model, sys, input, o.max ?? 2000, `${phase} ${o.taskClass}`, phase === 'verify' ? REVIEW : o.taskClass, phase === 'verify' ? (o.counterpartModel ?? LUNA) : null, o.effort ?? null);
      if (phase === 'decompose') out.plan = r.content;
      return { content: r.content || null, model: r.model, ...(r.error ? { error: r.error } : {}) };
    },
  };
  return out;
}

const JUDGE_SYS = (facts: string) => facts + `\n\nYou are an independent judge from another model family. Two answers, A and B, were written to the same QUESTION from
the same SETTLED FACTS above and the same CONTEXT (the case the question came with) and SOURCES below. Decide whether they are equivalent
for the person who asked (the same decision and the same facts that matter; wording does not matter), and list each answer's RULE
VIOLATIONS: a figure, limit, owner or date that neither the settled facts, the context nor the sources state; a contradiction of a settled fact or a founder ruling; a deferral ("I will check") or "not on record"
for something the facts state. Return ONE JSON object: {"verdict":"equivalent"|"A_better"|"B_better","a_violations":["..."],"b_violations":["..."],"why":"<one line>"}`;
async function judge(facts: string, question: string, sources: unknown[], oldAns: string, newAns: string, what: string, authors: string = LUNA, context: unknown = null) {
  const flip = Math.random() < 0.5; const [A, B] = flip ? [newAns, oldAns] : [oldAns, newAns];
  type Verdict = { verdict?: string; a_violations?: string[]; b_violations?: string[]; why?: string };
  let r = await ask(QWEN, JUDGE_SYS(facts), JSON.stringify({ question, ...(context ? { context } : {}), sources, A, B }), 6000, 'judge ' + what, REVIEW, authors, null, 'medium');
  let v = parse<Verdict>(r.content);
  if (!v?.verdict) { r = await ask(QWEN, JUDGE_SYS(facts), JSON.stringify({ question, ...(context ? { context } : {}), sources, A, B }), 6000, 'judge again ' + what, REVIEW, authors, null, 'low'); v = parse<Verdict>(r.content); }
  if (!v?.verdict) return { read: false, newNotWorse: false, newViolations: ['unread judge answer'], why: r.error ?? 'unparseable' };
  const newWorse = flip ? v.verdict === 'B_better' : v.verdict === 'A_better';
  const verdict = v.verdict === 'equivalent' ? 'equivalent' : newWorse ? 'old_better' : 'new_better';
  return { read: true, verdict, newNotWorse: !newWorse, newViolations: (flip ? v.a_violations : v.b_violations) ?? [], oldViolations: (flip ? v.b_violations : v.a_violations) ?? [], why: v.why ?? '' };
}

/** What the judge compares: the prose AND the decision (a duty's choice and fields are the answer that is acted on). */
const said = (r: { answer?: unknown; decision?: unknown }) => String(r.answer ?? '') + (r.decision ? '\nDECISION: ' + JSON.stringify(r.decision) : '');
const REJUDGE = arg('--rejudge');
const CONTROL = Deno.args.includes('--control');
const results: Record<string, unknown> = {}; let stopped = '';
await openWindow(admin, tag, CAP, 110, 'prompt diet eval (rulings 1619/1618): old vs new prompt on the same model, Haiku vs Sonnet');
console.log(`prompt diet eval: run tag qd_run:${tag}, cap USD ${CAP}, parts ${[...PARTS].join(',')}, effort ${EFFORT}`);
const p1Answers: { req: ThinkRequest; answer: string; cited: string[]; sources: { id: string; title: string; excerpt: string }[]; newPayload: string; newSys: string; facts: string }[] = [];
try {
  const carried = !PARTS.has('P1') && CARRY ? JSON.parse(await Deno.readTextFile(CARRY).catch(() => 'null')) as typeof p1Answers | null : null;
  if (carried) { p1Answers.push(...carried); console.log(`P1 is not run again: ${carried.length} answers carried from an earlier run of it`); }
  else if (PARTS.has('P1') || PARTS.has('P3') || PARTS.has('P5')) {
    // deno-lint-ignore no-explicit-any
    const rows: Record<string, any>[] = [];
    // written after EVERY case, so a run that is stopped keeps the cases it finished
    const sum = () => { const n = rows.length, ok = rows.filter((r) => r.newNotWorse).length, viol = rows.filter((r) => r.newViolations.length || r.ungrounded).length;
    results.P1 = { ...(CONTROL ? { control: 'both arms on the SAME prompt (no cut): this is the noise of the measurement, not a verdict on the switch' } : {}), switch: 'retrieval_keeps_the_top_rows_above_a_floor', cases: n, not_worse: ok, violations: viol, judge_unread: rows.filter((r) => r.read === false).length,
      reviews_not_run: rows.reduce((k, r) => k + (r.review.old === 'not_run' ? 1 : 0) + (r.review.new === 'not_run' ? 1 : 0), 0), pass: n > 0 && ok / n >= 0.95 && viol === 0, rows }; };
    for (const req0 of CASES.internal.slice(0, Number(arg('--p1') ?? '16'))) {
      const req: ThinkRequest = { ...req0, research: false, queueWhenHeld: false };
      const memo = new Map<string, unknown>();
      const oldD = replayDeps({}, memo); const calls: { phase: string; input: string }[] = [];
      const oldR = await inRun(() => think({ ...oldD, llm: async (p, s, i, o) => { calls.push({ phase: p, input: i }); return await oldD.llm(p, s, i, o); } }, req));
      const newD = replayDeps(CONTROL ? {} : { retrieval_keeps_the_top_rows_above_a_floor: true }, memo, oldD.plan ?? '');
      const newCalls: { phase: string; input: string; sys: string }[] = [];
      const newR = await inRun(() => think({ ...newD, llm: async (p, s, i, o) => { newCalls.push({ phase: p, input: i, sys: (o.sysShared ?? '') + (o.sysStable ?? '') + s }); return await newD.llm(p, s, i, o); } }, req));
      const facts = settledFacts(req.context?.audience, req.seat);
      const srcs = (JSON.parse(calls.find((x) => x.phase === 'synthesise')?.input ?? '{}').sources ?? []) as { id: string; title: string; excerpt: string }[];
      const cited = [...new Set([...(oldR.sources ?? []).map((s) => s.id), ...(newR.sources ?? []).map((s) => s.id)])];
      const j = oldR.status === 'answered' && newR.status === 'answered'
        ? await judge(facts, req.question, srcs.filter((s) => cited.includes(s.id)), said(oldR), said(newR), 'P1 ' + req.surface, LUNA, req.context ?? null)
        : { read: true, newNotWorse: newR.status === 'answered' || oldR.status !== 'answered', newViolations: newR.status === 'answered' ? [] : ['NEW arm: ' + newR.status + ' ' + (newR.reason ?? '')], why: 'status ' + oldR.status + ' vs ' + newR.status };
      // code's own check, on top of the judge: a figure in NEW's answer that NEW's sources and the settled facts do not print
      const newSrcs = (JSON.parse(newCalls.find((x) => x.phase === 'synthesise')?.input ?? '{}').sources ?? []) as { title: string; excerpt: string }[];
      const ungrounded = newR.status === 'answered' && /\d/.test(String(newR.answer)) && !figuresGrounded(String(newR.answer), [facts, ...newSrcs.map((s) => s.title + '\n' + s.excerpt)]) && figuresGrounded(String(oldR.answer), [facts, ...srcs.map((s) => s.title + '\n' + s.excerpt)]);
      const tokOld = (calls.find((x) => x.phase === 'synthesise')?.input ?? '').length, tokNew = (newCalls.find((x) => x.phase === 'synthesise')?.input ?? '').length;
      rows.push({ surface: req.surface, old: oldR.status, new: newR.status, ...j, ungrounded, payload_chars: { old: tokOld, new: tokNew }, source_rows: { old: srcs.length, new: newSrcs.length },
        calls: { old: calls.map((x) => x.phase), new: newCalls.map((x) => x.phase) }, review: { old: oldR.verified?.status ?? null, new: newR.verified?.status ?? null } });
      const say = (r: typeof oldR) => ({ status: r.status, reason: r.reason ?? null, answer: r.answer, decision: r.decision, cited: (r.sources ?? []).map((s) => s.id), verified: r.verified, confidence: r.confidence });
      answersLog.push({ part: 'P1', surface: req.surface, question: req.question, old: say(oldR), new: say(newR), judge: j, ungrounded, old_source_ids: srcs.map((s) => s.id), new_source_ids: (newSrcs as { id?: string }[]).map((s) => s.id) });
      if (oldR.status === 'answered') p1Answers.push({ req, answer: String(oldR.answer), cited: (oldR.sources ?? []).map((s) => s.id), sources: srcs, newPayload: newCalls.find((x) => x.phase === 'synthesise')?.input ?? '', newSys: newCalls.find((x) => x.phase === 'synthesise')?.sys ?? '', facts });
      if (CARRY) await writeJson(CARRY, p1Answers);
      sum();
      console.log(`P1 ${req.surface.padEnd(32)} ${oldR.status}/${newR.status} ${j.newNotWorse ? 'not worse' : 'WORSE'} viol=${j.newViolations.length} chars ${tokOld}->${tokNew}`);
    }
    sum();
  }
  if (PARTS.has('P2')) {
    const rows = [];
    for (const t of CASES.trends.slice(0, Number(arg('--p2') ?? '16'))) {
      const memo = new Map<string, unknown>();
      const a = await inRun(() => judgeTrend(replayDeps({}, memo), t)), b = await inRun(() => judgeTrend(replayDeps({}, memo), t, { plansNothing: true }));
      const same = !!a && !!b && a.relevant === b.relevant;
      const j = a && b ? await judge(settledFacts('internal', 'marketing'), t.title, [], `${a.relevant ? 'relevant' : 'not relevant'}: ${a.why}`, `${b.relevant ? 'relevant' : 'not relevant'}: ${b.why}`, 'P2') : { read: false, newNotWorse: false, newViolations: ['an arm was held'], why: '' };
      rows.push({ id: t.id, old: a?.relevant ?? null, new: b?.relevant ?? null, same, ...j });
      answersLog.push({ part: 'P2', id: t.id, source: t.source, title: t.title, production_said: (t as { was_relevant?: boolean | null }).was_relevant ?? null, old: a, new: b, same, judge: j });
      console.log(`P2 ${String(t.id).padEnd(8)} ${a?.relevant}/${b?.relevant} ${j.newNotWorse ? 'not worse' : 'WORSE'}`);
    }
    const n = rows.length, ok = rows.filter((r) => r.same && r.newNotWorse).length, viol = rows.filter((r) => r.newViolations.length).length;
    results.P2 = { switch: 'a_trend_relevance_choice_plans_and_retrieves_nothing', cases: n, agree_and_not_worse: ok, violations: viol, pass: n > 0 && ok / n >= 0.95 && viol === 0, rows };
  }
  if (PARTS.has('P3')) {
    const rows = [];
    const seed = (t: string) => t.replace(/\d[\d,.]*/, (m) => String(Number(m.replace(/,/g, '')) * 10 || 7));
    const verify = async (x: typeof p1Answers[number], answer: string, sources: unknown[], what: string) => {
      const r = await ask(QWEN, x.facts + VERIFY_PROMPT, JSON.stringify({ question: x.req.question, answer, decision: null, sources }), 600, what);
      return parse<{ verdict?: string }>(r.content)?.verdict ?? null;
    };
    for (const x of p1Answers.slice(0, Number(arg('--p3') ?? '6'))) {
      const citedSrc = x.sources.filter((s) => x.cited.includes(s.id)); const mine = citedSrc.length ? citedSrc : x.sources;
      const real = [await verify(x, x.answer, x.sources, 'P3 all'), await verify(x, x.answer, mine, 'P3 cited')];
      const bad = seed(x.answer); const seeded = bad !== x.answer ? [await verify(x, bad, x.sources, 'P3 seeded all'), await verify(x, bad, mine, 'P3 seeded cited')] : [null, null];
      rows.push({ surface: x.req.surface, real, seeded, agree: real[0] === real[1], missed: seeded[0] === 'disagree' && seeded[1] !== 'disagree', sources: { all: x.sources.length, cited: citedSrc.length } });
      answersLog.push({ part: 'P3', surface: x.req.surface, answer: x.answer, seeded_answer: bad !== x.answer ? bad : null, real, seeded, sources: { all: x.sources.length, cited: citedSrc.length } });
    }
    const n = rows.length;
    results.P3 = { switch: 'the_reviewer_reads_the_cited_sources_only', cases: n, verdicts_agree: rows.filter((r) => r.agree).length, seeded_missed_by_cut: rows.filter((r) => r.missed).length,
      pass: n > 0 && rows.filter((r) => r.agree).length / n >= 0.95 && rows.every((r) => !r.missed), rows };
  }
  if (PARTS.has('P4')) {
    const SYS = 'You are QuotesDone\'s independent reviewer. Check the DRAFT against the FACTS: every figure is one the FACTS state; no card fee, no VAT on the reveal fee, no refund promised; the REPLY LANGUAGE; no other party\'s identity; no deferral. Return ONE JSON object: {"ok": <true when it breaks none>, "problems": ["..."]}';
    const score = async (model: string) => {
      let caught = 0, falseFlags = 0, unread = 0; const missed: string[] = [], flaggedClean: string[] = [];
      for (const k of CASES_C) {
        const r = await ask(model, SYS, `REPLY LANGUAGE: ${k.lang === 'ar' ? 'Arabic' : 'English'}\nAUDIENCE: ${k.audience}\n\nFACTS:\n${k.facts}\n\nDRAFT:\n${k.draft}`, 600, 'P4 reviewer ' + model);
        const v = parse<{ ok?: boolean }>(r.content); if (typeof v?.ok !== 'boolean') { unread++; continue; }
        if (k.defect && !v.ok) caught++; if (!k.defect && !v.ok) { falseFlags++; flaggedClean.push(k.id); }
        if (k.defect && v.ok) missed.push(k.id + ':' + k.defect);
      }
      return { caught, falseFlags, unread, missed, flaggedClean };
    };
    // Haiku first: it is 20 times cheaper, so a cap that stops the Sonnet side still leaves Haiku's own counts measured.
    const h = await score(HAIKU), s = await score(SONNET);
    results.P4 = { what: 'reviewer: Haiku 5.5 vs Sonnet 5.5 on eval C drafts', sonnet: s, haiku: h,
      pass: h.caught >= 28 && h.falseFlags <= 3 && h.unread === 0 && h.caught >= s.caught - 1 && h.falseFlags <= s.falseFlags + 1 };
  }
  if (PARTS.has('P5')) {
    const rows = [];
    for (const x of p1Answers.filter((y) => y.newPayload && y.newSys).slice(0, Number(arg('--p5') ?? '3'))) {
      const sys = x.newSys;   // the NEW arm's own answer prompt: settled facts, rulings, the JSON shape, exactly as sent
      const s = await ask(SONNET, sys, x.newPayload, 2000, 'P5 fallback sonnet', ANSWER, null), h = await ask(HAIKU, sys, x.newPayload, 2000, 'P5 fallback haiku', ANSWER, null);
      const sa = parse<{ answer?: string }>(s.content)?.answer ?? '', ha = parse<{ answer?: string }>(h.content)?.answer ?? '';
      const j = sa && ha ? await judge(x.facts, x.req.question, (JSON.parse(x.newPayload).sources ?? []) as unknown[], sa, ha, 'P5', `${SONNET},${HAIKU}`, x.req.context ?? null) : { read: false, newNotWorse: false, newViolations: ['unread answer'], why: '' };
      rows.push({ surface: x.req.surface, ...j });
      // an answer that could not be read keeps what the model actually wrote, so a person can see why
      answersLog.push({ part: 'P5', surface: x.req.surface, question: x.req.question, sonnet: sa || s.error, haiku: ha || h.error, judge: j,
        ...(sa ? {} : { sonnet_wrote: s.content.slice(0, 6000) }), ...(ha ? {} : { haiku_wrote: h.content.slice(0, 6000) }), sonnet_whole_reply_chars: s.content.length, haiku_whole_reply_chars: h.content.length });
    }
    const n = rows.length, ok = rows.filter((r) => r.newNotWorse).length;
    results.P5 = { what: 'fallback: Haiku 5.5 (new) vs Sonnet 5.5 (old) on internal answers', cases: n, not_worse: ok, violations: rows.filter((r) => r.newViolations.length).length,
      pass: n > 0 && ok / n >= 0.95 && rows.every((r) => !r.newViolations.length), rows };
  }
  if (REJUDGE && (PARTS.has('J1') || PARTS.has('J5'))) {
    type Said = { status?: string; answer?: string; decision?: unknown; cited?: string[] };
    const earlier = JSON.parse(await Deno.readTextFile(REJUDGE)) as { part: string; surface: string; question: string; old?: Said; new?: Said; ungrounded?: boolean; judge?: { verdict?: string }; sonnet?: string; haiku?: string }[];
    const used = new Set<number>();
    const carriedFor = (surface: string, question: string) => { const i = p1Answers.findIndex((x, k) => !used.has(k) && x.req.surface === surface && x.req.question === question); if (i >= 0) used.add(i); return i >= 0 ? p1Answers[i] : null; };
    if (PARTS.has('J1')) {
      const rows = [];
      for (const e of earlier.filter((x) => x.part === 'P1')) {
        const x = carriedFor(e.surface, e.question);
        if (!x || e.old?.status !== 'answered' || e.new?.status !== 'answered') { rows.push({ surface: e.surface, old: e.old?.status, new: e.new?.status, read: true, newNotWorse: e.new?.status === 'answered' || e.old?.status !== 'answered', newViolations: e.new?.status === 'answered' ? [] : ['NEW arm: ' + e.new?.status], ungrounded: !!e.ungrounded, why: x ? 'status' : 'no carried sources for this case' }); continue; }
        const cited = new Set([...(e.old.cited ?? []), ...(e.new.cited ?? [])]);
        const j = await judge(x.facts, e.question, x.sources.filter((q) => cited.has(q.id)), said(e.old), said(e.new), 'J1 ' + e.surface, LUNA, x.req.context ?? null);
        const sameChoice = (e.old.decision as { choice?: string } | null)?.choice === (e.new.decision as { choice?: string } | null)?.choice;
        rows.push({ surface: e.surface, old: 'answered', new: 'answered', ...j, ungrounded: !!e.ungrounded, same_choice: sameChoice, first_judge: e.judge?.verdict ?? null });
        console.log(`J1 ${e.surface.padEnd(32)} ${j.newNotWorse ? 'not worse' : 'WORSE'} viol=${j.newViolations.length} first=${e.judge?.verdict ?? 'unread'}`);
      }
      const n = rows.length, ok = rows.filter((r) => r.newNotWorse).length, viol = rows.filter((r) => r.newViolations.length || r.ungrounded).length;
      results.J1 = { what: 'P1 pairs re-judged with the case context and the decision in view; the answers are the earlier run\'s', from: REJUDGE.replace(/^.*\//, ''), cases: n, not_worse: ok, violations: viol, pass: n > 0 && ok / n >= 0.95 && viol === 0, rows };
    }
    if (PARTS.has('J5')) {
      const rows = [];
      for (const e of earlier.filter((x) => x.part === 'P5')) {
        const x = carriedFor(e.surface, e.question);
        const sa = typeof e.sonnet === 'string' ? e.sonnet : '', ha = typeof e.haiku === 'string' ? e.haiku : '';
        const j = !x ? { read: false, newNotWorse: false, newViolations: ['no carried sources for this case'], why: '' }
          : sa && ha ? await judge(x.facts, e.question, (JSON.parse(x.newPayload).sources ?? []) as unknown[], sa, ha, 'J5 ' + e.surface, `${SONNET},${HAIKU}`, x.req.context ?? null)
          : ha ? { read: true, verdict: 'new_better', scored_by: 'code', newNotWorse: true, newViolations: [], oldViolations: ['the old model returned no answer field'], why: 'the old model returned no answer; the new model answered' }
          : { read: false, newNotWorse: false, newViolations: ['unread answer'], why: '' };
        rows.push({ surface: e.surface, ...j });
        console.log(`J5 ${e.surface.padEnd(32)} ${j.newNotWorse ? 'not worse' : 'WORSE'} viol=${j.newViolations.length}`);
      }
      const n = rows.length, ok = rows.filter((r) => r.newNotWorse).length;
      results.J5 = { what: 'P5 pairs re-judged with the case context and the sources both models read', from: REJUDGE.replace(/^.*\//, ''), cases: n, not_worse: ok, violations: rows.filter((r) => r.newViolations.length).length,
        pass: n > 0 && ok / n >= 0.95 && rows.every((r) => !r.newViolations.length), rows };
    }
  }
} catch (e) {
  stopped = e instanceof CapReached ? e.message : 'error: ' + String((e as Error)?.message ?? e);
} finally {
  await closeWindow(admin, tag).catch(() => {});
}
const spend = Number((await spentUsd(admin, tag)).toFixed(4));
if (ANSWERS) await writeJson(ANSWERS, answersLog);
await writeJson(`${OUT}/prompt_diet_eval.json`, { at: new Date().toISOString(), run_tag: 'qd_run:' + tag, effort: EFFORT, cap_usd: CAP, spend_usd: spend, stopped: stopped || null, results });
console.log(JSON.stringify({ run_tag: 'qd_run:' + tag, spend_usd: spend, stopped: stopped || null,
  pass: Object.fromEntries(Object.entries(results).map(([k, v]) => [k, (v as { pass?: boolean }).pass ?? false])) }, null, 1));
Deno.exit(stopped ? 2 : 0);
