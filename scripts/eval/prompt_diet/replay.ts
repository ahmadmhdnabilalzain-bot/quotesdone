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
//   deno run -A --node-modules-dir=none scripts/eval/prompt_diet/replay.ts --cases <file> --cap 1.45 [--out <dir>] [--parts P1,P2,P3,P4,P5]
import { arg, CapReached, closeWindow, connect, guardSpend, newTag, openWindow, spentUsd, writeJson, type Ctx } from '../model_routing/harness.ts';
import { CASES_C } from '../model_routing/cases_c.ts';
import { defaultDeps, figuresGrounded, settledFacts, think, VERIFY_PROMPT, type ThinkDeps, type ThinkRequest } from '../../../supabase/functions/_shared/think.ts';
import { shapeRequest } from '../../../supabase/functions/_shared/request_shape.ts';
import { judgeTrend } from '../../../supabase/functions/marketing/duties/trends_geo.ts';
import type { DietOverrides } from '../../../supabase/functions/_shared/prompt_diet.ts';

export const LUNA = 'openai/gpt-6-luna-pro', QWEN = 'qwen/qwen3.8-flash', SONNET = 'anthropic/claude-sonnet-5.5', HAIKU = 'anthropic/claude-haiku-5.5';
const CAP = Number(arg('--cap') ?? '1.45');
if (!(CAP > 0 && CAP <= 1.5)) throw new Error('the cap is at most USD 1.50 (the paid round\'s budget)');
const OUT = arg('--out') ?? 'docs/reports/prompt-diet-2026-11-11';
// P4's drafts: eval C's fixed set (labels known by construction); --p4 is accepted for symmetry and must be 60.
if ((arg('--p4') ?? '60') !== '60') throw new Error('P4 runs eval C\'s whole set of 60 drafts');
const PARTS = new Set((arg('--parts') ?? 'P1,P2,P3,P4,P5').split(','));
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
async function ask(model: string, system: string, input: string, max: number, why: string): Promise<{ content: string; model: string | null; error?: string }> {
  await guardSpend(c, EST[model] ?? 0.05, why);
  const t0 = Date.now();
  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', { method: 'POST', signal: AbortSignal.timeout(120_000),
    headers: { Authorization: 'Bearer ' + key, 'Content-Type': 'application/json', 'X-Title': 'QuotesDone prompt diet eval' },
    body: JSON.stringify({ model, ...shapeRequest({ model, maxTokens: max, temperature: 0.2, responseFormat: { type: 'json_object' },
      supported: new Set(['reasoning', 'response_format', 'structured_outputs', 'tools']) }), usage: { include: true },
      messages: [{ role: 'system', content: system }, { role: 'user', content: input }] }) });
  const j = await res.json().catch(() => null) as { choices?: { message?: { content?: string } }[]; usage?: { prompt_tokens?: number; completion_tokens?: number; cost?: number; prompt_tokens_details?: { cached_tokens?: number } }; model?: string; id?: string; error?: { message?: string } } | null;
  const content = String(j?.choices?.[0]?.message?.content ?? '');
  const { error } = await admin.from('ai_cost_log').insert({ fn: 'resilience_ping', agent_key: 'it_engineer', seat: 'it_engineer', task_class: 'knowledge_validation',
    model_used: j?.model ?? model, model_selected_because: 'prompt diet eval (rulings 1619, 1618): ' + why, tier: 'eval',
    prompt_tokens: j?.usage?.prompt_tokens ?? 0, output_tokens: j?.usage?.completion_tokens ?? 0, cached: false, ok: res.ok && !!content,
    cached_in_tokens: j?.usage?.prompt_tokens_details?.cached_tokens ?? 0, cost_usd_reported: Number(j?.usage?.cost ?? 0), e2e_run_tag: tag,
    counterpart_model: LUNA, latency_ms: Date.now() - t0, generation_id: j?.id ?? null });
  if (error) throw new Error('the cost row could not be written, the run stops: ' + error.message);
  return { content, model: j?.model ?? null, ...(res.ok && content ? {} : { error: 'HTTP ' + res.status + ' ' + String(j?.error?.message ?? 'empty').slice(0, 120) }) };
}
const parse = <T>(s: string): T | null => { try { return JSON.parse(s.slice(s.indexOf('{'), s.lastIndexOf('}') + 1)) as T; } catch { return null; } };

// ── think() with the production prompt, a fixed model, read-only retrieval, and the writes stubbed ─────────────────────
const READ_ONLY = new Set(['fn_reason_retrieve', 'fn_reason_retrieve_ml', 'fn_kernel_paid_provider_gate', 'fn_ml_read_space']);
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
      const r = await ask(model, sys, input, o.max ?? 2000, `${phase} ${o.taskClass}`);
      if (phase === 'decompose') out.plan = r.content;
      return { content: r.content || null, model: r.model, ...(r.error ? { error: r.error } : {}) };
    },
  };
  return out;
}

const JUDGE_SYS = (facts: string) => facts + `\n\nYou are an independent judge from another model family. Two answers, A and B, were written to the same QUESTION from
the same SETTLED FACTS and SOURCES above or below. Decide whether they are equivalent for the person who asked (the same decision and the
same facts that matter; wording does not matter), and list each answer's RULE VIOLATIONS: a figure, limit, owner or date that neither the
settled facts nor the sources state; a contradiction of a settled fact or a founder ruling; a deferral ("I will check") or "not on record"
for something the facts state. Return ONE JSON object: {"verdict":"equivalent"|"A_better"|"B_better","a_violations":["..."],"b_violations":["..."],"why":"<one line>"}`;
async function judge(facts: string, question: string, sources: unknown[], oldAns: string, newAns: string, what: string) {
  const flip = Math.random() < 0.5; const [A, B] = flip ? [newAns, oldAns] : [oldAns, newAns];
  const r = await ask(QWEN, JUDGE_SYS(facts), JSON.stringify({ question, sources, A, B }), 900, 'judge ' + what);
  const v = parse<{ verdict?: string; a_violations?: string[]; b_violations?: string[]; why?: string }>(r.content);
  if (!v?.verdict) return { read: false, newNotWorse: false, newViolations: ['unread judge answer'], why: r.error ?? 'unparseable' };
  const newWorse = flip ? v.verdict === 'B_better' : v.verdict === 'A_better';
  return { read: true, newNotWorse: !newWorse, newViolations: (flip ? v.a_violations : v.b_violations) ?? [], oldViolations: (flip ? v.b_violations : v.a_violations) ?? [], why: v.why ?? '' };
}

const results: Record<string, unknown> = {}; let stopped = '';
await openWindow(admin, tag, CAP, 110, 'prompt diet eval (rulings 1619/1618): old vs new prompt on the same model, Haiku vs Sonnet');
console.log(`prompt diet eval: run tag qd_run:${tag}, cap USD ${CAP}, parts ${[...PARTS].join(',')}`);
const p1Answers: { req: ThinkRequest; answer: string; cited: string[]; sources: { id: string; title: string; excerpt: string }[]; newPayload: string; newSys: string; facts: string }[] = [];
try {
  if (PARTS.has('P1') || PARTS.has('P3') || PARTS.has('P5')) {
    const rows = [];
    for (const req0 of CASES.internal.slice(0, Number(arg('--p1') ?? '16'))) {
      const req: ThinkRequest = { ...req0, research: false, queueWhenHeld: false };
      const memo = new Map<string, unknown>();
      const oldD = replayDeps({}, memo); const calls: { phase: string; input: string }[] = [];
      const oldR = await think({ ...oldD, llm: async (p, s, i, o) => { calls.push({ phase: p, input: i }); return await oldD.llm(p, s, i, o); } }, req);
      const newD = replayDeps({ retrieval_keeps_the_top_rows_above_a_floor: true }, memo, oldD.plan ?? '');
      const newCalls: { phase: string; input: string; sys: string }[] = [];
      const newR = await think({ ...newD, llm: async (p, s, i, o) => { newCalls.push({ phase: p, input: i, sys: (o.sysShared ?? '') + (o.sysStable ?? '') + s }); return await newD.llm(p, s, i, o); } }, req);
      const facts = settledFacts(req.context?.audience, req.seat);
      const srcs = (JSON.parse(calls.find((x) => x.phase === 'synthesise')?.input ?? '{}').sources ?? []) as { id: string; title: string; excerpt: string }[];
      const cited = [...new Set([...(oldR.sources ?? []).map((s) => s.id), ...(newR.sources ?? []).map((s) => s.id)])];
      const j = oldR.status === 'answered' && newR.status === 'answered'
        ? await judge(facts, req.question, srcs.filter((s) => cited.includes(s.id)), String(oldR.answer), String(newR.answer), 'P1 ' + req.surface)
        : { read: true, newNotWorse: newR.status === 'answered' || oldR.status !== 'answered', newViolations: newR.status === 'answered' ? [] : ['NEW arm: ' + newR.status + ' ' + (newR.reason ?? '')], why: 'status ' + oldR.status + ' vs ' + newR.status };
      // code's own check, on top of the judge: a figure in NEW's answer that NEW's sources and the settled facts do not print
      const newSrcs = (JSON.parse(newCalls.find((x) => x.phase === 'synthesise')?.input ?? '{}').sources ?? []) as { title: string; excerpt: string }[];
      const ungrounded = newR.status === 'answered' && /\d/.test(String(newR.answer)) && !figuresGrounded(String(newR.answer), [facts, ...newSrcs.map((s) => s.title + '\n' + s.excerpt)]) && figuresGrounded(String(oldR.answer), [facts, ...srcs.map((s) => s.title + '\n' + s.excerpt)]);
      const tokOld = (calls.find((x) => x.phase === 'synthesise')?.input ?? '').length, tokNew = (newCalls.find((x) => x.phase === 'synthesise')?.input ?? '').length;
      rows.push({ surface: req.surface, old: oldR.status, new: newR.status, ...j, ungrounded, payload_chars: { old: tokOld, new: tokNew } });
      if (oldR.status === 'answered') p1Answers.push({ req, answer: String(oldR.answer), cited: (oldR.sources ?? []).map((s) => s.id), sources: srcs, newPayload: newCalls.find((x) => x.phase === 'synthesise')?.input ?? '', newSys: newCalls.find((x) => x.phase === 'synthesise')?.sys ?? '', facts });
      console.log(`P1 ${req.surface.padEnd(32)} ${oldR.status}/${newR.status} ${j.newNotWorse ? 'not worse' : 'WORSE'} viol=${j.newViolations.length} chars ${tokOld}->${tokNew}`);
    }
    const n = rows.length, ok = rows.filter((r) => r.newNotWorse).length, viol = rows.filter((r) => r.newViolations.length || r.ungrounded).length;
    results.P1 = { switch: 'retrieval_keeps_the_top_rows_above_a_floor', cases: n, not_worse: ok, violations: viol, pass: n > 0 && ok / n >= 0.95 && viol === 0, rows };
  }
  if (PARTS.has('P2')) {
    const rows = [];
    for (const t of CASES.trends.slice(0, Number(arg('--p2') ?? '16'))) {
      const memo = new Map<string, unknown>();
      const a = await judgeTrend(replayDeps({}, memo), t), b = await judgeTrend(replayDeps({}, memo), t, { plansNothing: true });
      const same = !!a && !!b && a.relevant === b.relevant;
      const j = a && b ? await judge(settledFacts('internal', 'marketing'), t.title, [], `${a.relevant ? 'relevant' : 'not relevant'}: ${a.why}`, `${b.relevant ? 'relevant' : 'not relevant'}: ${b.why}`, 'P2') : { read: false, newNotWorse: false, newViolations: ['an arm was held'], why: '' };
      rows.push({ id: t.id, old: a?.relevant ?? null, new: b?.relevant ?? null, same, ...j });
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
      rows.push({ surface: x.req.surface, real, seeded, agree: real[0] === real[1], missed: seeded[0] === 'disagree' && seeded[1] !== 'disagree' });
    }
    const n = rows.length;
    results.P3 = { switch: 'the_reviewer_reads_the_cited_sources_only', cases: n, verdicts_agree: rows.filter((r) => r.agree).length, seeded_missed_by_cut: rows.filter((r) => r.missed).length,
      pass: n > 0 && rows.filter((r) => r.agree).length / n >= 0.95 && rows.every((r) => !r.missed), rows };
  }
  if (PARTS.has('P4')) {
    const SYS = 'You are QuotesDone\'s independent reviewer. Check the DRAFT against the FACTS: every figure is one the FACTS state; no card fee, no VAT on the reveal fee, no refund promised; the REPLY LANGUAGE; no other party\'s identity; no deferral. Return ONE JSON object: {"ok": <true when it breaks none>, "problems": ["..."]}';
    const score = async (model: string) => {
      let caught = 0, falseFlags = 0, unread = 0;
      for (const k of CASES_C) {
        const r = await ask(model, SYS, `REPLY LANGUAGE: ${k.lang === 'ar' ? 'Arabic' : 'English'}\nAUDIENCE: ${k.audience}\n\nFACTS:\n${k.facts}\n\nDRAFT:\n${k.draft}`, 600, 'P4 reviewer ' + model);
        const v = parse<{ ok?: boolean }>(r.content); if (typeof v?.ok !== 'boolean') { unread++; continue; }
        if (k.defect && !v.ok) caught++; if (!k.defect && !v.ok) falseFlags++;
      }
      return { caught, falseFlags, unread };
    };
    const s = await score(SONNET), h = await score(HAIKU);
    results.P4 = { what: 'reviewer: Haiku 5.5 vs Sonnet 5.5 on eval C drafts', sonnet: s, haiku: h,
      pass: h.caught >= 28 && h.falseFlags <= 3 && h.unread === 0 && h.caught >= s.caught - 1 && h.falseFlags <= s.falseFlags + 1 };
  }
  if (PARTS.has('P5')) {
    const rows = [];
    for (const x of p1Answers.filter((y) => y.newPayload && y.newSys).slice(0, Number(arg('--p5') ?? '3'))) {
      const sys = x.newSys;   // the NEW arm's own answer prompt: settled facts, rulings, the JSON shape, exactly as sent
      const s = await ask(SONNET, sys, x.newPayload, 2000, 'P5 fallback sonnet'), h = await ask(HAIKU, sys, x.newPayload, 2000, 'P5 fallback haiku');
      const sa = parse<{ answer?: string }>(s.content)?.answer ?? '', ha = parse<{ answer?: string }>(h.content)?.answer ?? '';
      const j = sa && ha ? await judge(x.facts, x.req.question, x.sources.filter((q) => x.cited.includes(q.id)), sa, ha, 'P5') : { read: false, newNotWorse: false, newViolations: ['unread answer'], why: '' };
      rows.push({ surface: x.req.surface, ...j });
    }
    const n = rows.length, ok = rows.filter((r) => r.newNotWorse).length;
    results.P5 = { what: 'fallback: Haiku 5.5 (new) vs Sonnet 5.5 (old) on internal answers', cases: n, not_worse: ok, violations: rows.filter((r) => r.newViolations.length).length,
      pass: n > 0 && ok / n >= 0.95 && rows.every((r) => !r.newViolations.length), rows };
  }
} catch (e) {
  stopped = e instanceof CapReached ? e.message : 'error: ' + String((e as Error)?.message ?? e);
} finally {
  await closeWindow(admin, tag).catch(() => {});
}
const spend = Number((await spentUsd(admin, tag)).toFixed(4));
await writeJson(`${OUT}/prompt_diet_eval.json`, { at: new Date().toISOString(), run_tag: 'qd_run:' + tag, cap_usd: CAP, spend_usd: spend, stopped: stopped || null, results });
console.log(JSON.stringify({ run_tag: 'qd_run:' + tag, spend_usd: spend, stopped: stopped || null,
  pass: Object.fromEntries(Object.entries(results).map(([k, v]) => [k, (v as { pass?: boolean }).pass ?? false])) }, null, 1));
Deno.exit(stopped ? 2 : 0);
