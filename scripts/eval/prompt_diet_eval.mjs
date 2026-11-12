#!/usr/bin/env node
// THE PROMPT DIET EVAL, PREPARED FOR THE PAID ROUND (it_engineer, 11 Nov 2026; founder rulings 1619 and 1618;
// report docs/reports/2026-11-11-prompt-diet.md). Every content-removing switch in supabase/functions/_shared/prompt_diet.ts
// stays OFF until this passes; the cheaper reviewer and fallback (Claude Haiku 5.5) are not routed to until it passes either.
//
//   node scripts/eval/prompt_diet_eval.mjs plan                       expected cost per part and the pass rules (no network)
//   node scripts/eval/prompt_diet_eval.mjs sample [--out <file>]      READ-ONLY production sample, anonymised, written OUTSIDE the repo
//   node scripts/eval/prompt_diet_eval.mjs run --cases <file> --paid [--cap 1.45] [--parts P1,P3,P5] [--out <dir>] [--answers <file outside the repo>]
//                                                                     [--effort policy|model-default]  policy = the effort ai_gateway sends for the class
//                                                                     [--carry <file outside the repo>]  P1 saves the answers P3/P5 read; P3/P5 alone load them
//                                                                     [--control]  P1 with both arms on the SAME prompt: the measurement's own noise, never a verdict
//                                                                     [--parts J1|J5 --rejudge <an earlier run's --answers file> --carry <its carry file>]  re-judge, ask nothing again
//                                                                     the paid round: scripts/eval/prompt_diet/replay.ts (Deno)
//
// WHAT IS REPLAYED. P1/P3/P5: recorded internal duty questions (reasoning_held_question.request, internal surfaces only:
// postmortems, knowledge refreshes, competitor changes, CEO reviews; never a document, a customer or a supplier surface).
// No demo/fixture rows exist on those surfaces (measured 11 Nov: 0 of the 282 rows on the 15 largest internal surfaces), so recorded rows are used, anonymised here:
// e-mails, phone numbers and the request's subject/dedupe ids are replaced before anything leaves this machine. P2: the
// public news headlines marketing judged (titles and links of public feeds). P4: eval C's 60 constructed drafts (ZZ DEMO).
import { spawnSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = resolve(fileURLToPath(new URL('../..', import.meta.url)));

// USD per million tokens, model_registry as read 10-11 Nov 2026 (Haiku 5.5: the price the pending registry row carries).
export const PRICE = {
  'openai/gpt-6-luna-pro': { in: 0.10, out: 0.50 },
  'qwen/qwen3.8-flash': { in: 0.15, out: 0.47 },
  'anthropic/claude-sonnet-5.5': { in: 2.00, out: 10.00 },
  'anthropic/claude-haiku-5.5': { in: 0.10, out: 0.50 },
};
const usd = (m, inTok, outTok) => (inTok * PRICE[m].in + outTok * PRICE[m].out) / 1e6;
const L = 'openai/gpt-6-luna-pro', Q = 'qwen/qwen3.8-flash', S = 'anthropic/claude-sonnet-5.5', H = 'anthropic/claude-haiku-5.5';

// Token sizes per call, MEASURED (ai_cost_log, 7 days to 10 Nov 23:51 UTC, production, e2e_run_tag null) unless marked:
//   internal plan (routine_employee_reasoning, resilience_ping) 39.4k in / 1.9k out; internal answer (internal_judgement,
//   resilience_ping) 61.0k / 1.8k; trend plan (marketing routine_employee_reasoning) 34.5k / 1.8k; trend answer
//   (marketing internal_judgement) 74.1k / 2.3k. ESTIMATED: the NEW internal answer 39k (sources ~55% of the call, 4 of 12
//   rows kept); the NEW trend answer 30k (settled facts + prompt + headline); a review 40k all sources / 20k cited (Qwen);
//   a judge 35k; eval C drafts 1.3k in / 0.2k out; the Sonnet/Haiku fallback answer 24k in (the NEW payload in Anthropic
//   tokens, ~1/1.6 of Luna Pro's count) / 1.8k out.
export const PARTS = (n = { p1: 16, p2: 16, p3: 6, p4: 60, p5: 3 }) => [
  { part: 'P1', what: 'retrieval_keeps_the_top_rows_above_a_floor (internal_judgement, Luna Pro, OLD vs NEW)', n: n.p1,
    each: usd(L, 39_400, 1_900) + usd(L, 61_000, 1_800) + usd(L, 39_000, 1_800) + usd(Q, 35_000, 300) },
  { part: 'P2', what: 'a_trend_relevance_choice_plans_and_retrieves_nothing (Luna Pro, OLD vs NEW)', n: n.p2,
    each: usd(L, 34_500, 1_800) + usd(L, 74_100, 2_300) + usd(L, 30_000, 2_300) + usd(Q, 35_000, 300) },
  { part: 'P3', what: 'the_reviewer_reads_the_cited_sources_only (Qwen 3.8 Flash, the live reviewer route)', n: n.p3,
    each: 2 * (usd(Q, 40_000, 500) + usd(Q, 20_000, 500)) },
  { part: 'P4', what: 'reviewer side by side: Haiku 5.5 vs Sonnet 5.5 on eval C\'s 60 drafts', n: n.p4,
    each: usd(S, 1_300, 200) + usd(H, 1_300, 200) },
  { part: 'P5', what: 'fallback side by side: Haiku 5.5 vs Sonnet 5.5 on P1\'s NEW answer prompt (internal classes only)', n: n.p5,
    each: usd(S, 24_000, 1_800) + usd(H, 24_000, 1_800) + usd(Q, 35_000, 300) },
];
export const CAP_USD = 1.50;
export function plan(n) {
  const parts = PARTS(n).map((p) => ({ ...p, usd: Math.round(p.n * p.each * 1e4) / 1e4 }));
  return { parts, total: Math.round(parts.reduce((s, p) => s + p.usd, 0) * 1e4) / 1e4 };
}
export const PASS_RULES = [
  'P1, P2, P5: the judge (Qwen 3.8 Flash, never the author\'s family) rates NEW equivalent-or-better than OLD on >= 95% of cases (with 16 cases: all 16; with 3: all 3), and NEW has ZERO rule violations (judge-listed, plus code\'s figure check: no figure NEW states that its sources and the settled facts do not print, where OLD\'s were all grounded). P2 also needs the same relevant/not-relevant choice.',
  'P3: the reviewer\'s verdict with the cited sources only equals its verdict with every source on >= 95% of answers, and it misses NO seeded wrong figure that the all-sources reviewer caught.',
  'P4: Haiku 5.5 flags >= 28 of 30 seeded defects and <= 3 of 30 clean drafts with 0 unread answers (eval C\'s bar), and is no more than 1 below Sonnet 5.5 on either count.',
  'Any part that does not pass leaves its switch OFF (or its model unrouted); a part stopped by the cap is not a pass.',
];

// ── anonymisation: what leaves this machine carries no real person's address or number ─────────────────────────────────
const EMAIL = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;
const PHONE = /(?:\+|00)?\d[\d\s().-]{7,}\d/g;
// A DATE IS NOT A PHONE NUMBER (it_engineer, final audit, 11 Nov 2026). Measured on the first sample (20 questions): the phone
// pattern made 752 replacements and every one was an ISO date or the seconds of a timestamp ("starts_on": "+971500000000",
// "created_at": "+971500000000T03:37:+971500000000+00:00"); the sample held no phone number at all. The duties replayed reason
// about dates (a weekly verdict, a forecast, a recovery date), so both arms answered a question production never asked.
// An ISO date (20YY-MM-DD) and the timestamp that follows it are set aside first and put back after; every other run of
// eight or more digits is still replaced.
const ISO_WHEN = /(?<![\d-])20\d{2}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}(?::?\d{2})?)?)?(?![\d-])/g;
export function anonymiseText(s) {
  const kept = [];
  const held = String(s ?? '').replace(ISO_WHEN, (w) => { kept.push(w); return '\uE000' + (kept.length - 1) + '\uE001'; });
  return held.replace(EMAIL, (e) => /@example\.invalid$/i.test(e) ? e : 'someone@example.invalid')
    .replace(PHONE, (p) => p.replace(/\D/g, '').length >= 8 ? '+971500000000' : p)
    .replace(/\uE000(\d+)\uE001/g, (_m, i) => kept[Number(i)]);
}
export function anonymiseRequest(req) {
  const walk = (v) => typeof v === 'string' ? anonymiseText(v) : Array.isArray(v) ? v.map(walk)
    : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, walk(x)])) : v;
  const { subject: _s, dedupeKey: _d, ...rest } = req ?? {};
  return { ...walk(rest), subject: { fixture: true } };
}
export const SURFACES = ['it_engineer.postmortem', 'ceo.knowledge_refresh', 'marketing.competitor_change', 'ceo.management_review', 'ceo.target_forecast',
  'ceo.experiment_approval', 'ceo.experiment_verdict', 'sales_engineer.root_cause', 'it_engineer.ceo_revision', 'accountant.knowledge_refresh'];

const argv = process.argv.slice(2);
const opt = (k, d = null) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] ?? d : d; };
const mode = argv[0] ?? 'plan';
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);

function printPlan() {
  const p = plan();
  console.log('PROMPT DIET EVAL: expected cost (no cache reads assumed; OpenAI prefix caching will lower P1/P2)');
  for (const x of p.parts) console.log(`  ${x.part}  ${String(x.n).padStart(3)} x USD ${x.each.toFixed(4)} = USD ${x.usd.toFixed(4)}  ${x.what}`);
  console.log(`  TOTAL USD ${p.total.toFixed(4)} (cap USD ${CAP_USD.toFixed(2)}; the run's hard stop defaults to USD 1.45)`);
  console.log('PASS RULES:'); for (const r of PASS_RULES) console.log('  - ' + r);
  return p;
}

if (isMain && mode === 'plan') {
  const p = printPlan();
  process.exit(p.total <= CAP_USD ? 0 : 1);
}
if (isMain && mode === 'sample') {
  // refused before anything is read (it used to read production first and refuse after)
  const out = resolve(opt('--out', join(tmpdir(), 'prompt_diet_cases.json')));
  if (out.startsWith(REPO + '/')) { console.error('REFUSED: the cases file holds recorded text; write it outside the repository'); process.exit(2); }
  const { sql } = await import('../lib/db.mjs');
  const per = Number(opt('--per-surface', '2')), trends = Number(opt('--trends', '16'));
  const list = SURFACES.map((s) => `'${s}'`).join(',');
  const internal = await sql(`select surface, request from (select surface, request, row_number() over (partition by surface order by coalesce(reasoned_at, created_at) desc) rn
      from public.reasoning_held_question where status in ('applied','reasoned') and request->'context'->>'audience' in ('internal','founder')
       and surface in (${list})) x where rn <= ${per} order by rn, surface`, { readOnly: true });
  // HALF THE HEADLINES ARE ONES PRODUCTION JUDGED RELEVANT (it_engineer, final audit, 11 Nov 2026). The newest 16 were all
  // "Google Trends UAE daily searches" terms ("uganda", "copa del rey"): that feed was judged relevant 5 times in 211 over 14
  // days, while the four construction feeds were judged relevant 78 times in 250. A sample with no relevant headline cannot
  // show whether the choice without a plan still keeps one. So: the newest judged headlines, half relevant and half not, taken
  // in turn from every feed. was_relevant (production's own choice) stays in the cases file and is never sent to a model.
  const half = Math.ceil(trends / 2);
  const heads = await sql(`select id, title, url, source, relevant from (
      select x.*, row_number() over (partition by x.relevant order by x.rn_src, x.judged_at desc, x.id desc) pick from (
        select t.id, t.title, t.url, t.relevant, t.judged_at, s.name as source,
               row_number() over (partition by t.source_id, t.relevant order by t.judged_at desc, t.id desc) rn_src
          from public.marketing_trend t join public.marketing_trend_source s on s.id = t.source_id
         where t.judged_at is not null and t.relevant is not null) x) y
      where pick <= ${half} order by pick, relevant desc limit ${trends}`, { readOnly: true });
  const cases = { internal: internal.map((r) => anonymiseRequest(r.request)), trends: heads.map((h) => ({ id: Number(h.id), title: anonymiseText(h.title), url: String(h.url), source: String(h.source), was_relevant: h.relevant === true })) };
  writeFileSync(out, JSON.stringify(cases, null, 1));
  console.log(`sampled ${cases.internal.length} internal questions (${per} per surface, ${SURFACES.length} surfaces) and ${cases.trends.length} headlines -> ${out}`);
}
if (isMain && mode === 'run') {
  if (!argv.includes('--paid')) { console.error('REFUSED: this spends money on OpenRouter. Re-run with --paid in the paid round.'); process.exit(2); }
  const cases = opt('--cases'); if (!cases) { console.error('--cases <file> (from: sample)'); process.exit(2); }
  const cap = Number(opt('--cap', '1.45'));
  if (!(cap > 0 && cap <= CAP_USD)) { console.error(`REFUSED: --cap must be in (0, ${CAP_USD}]`); process.exit(2); }
  printPlan();
  const n = PARTS().reduce((o, p) => ({ ...o, ['--' + p.part.toLowerCase()]: String(p.n) }), {});
  const r = spawnSync('deno', ['run', '-A', '--node-modules-dir=none', join(REPO, 'scripts/eval/prompt_diet/replay.ts'), '--cases', cases, '--cap', String(cap),
    ...Object.entries(n).flat(),
    ...(opt('--parts') ? ['--parts', opt('--parts')] : []), ...(opt('--answers') ? ['--answers', resolve(opt('--answers'))] : []), ...(opt('--effort') ? ['--effort', opt('--effort')] : []), ...(opt('--carry') ? ['--carry', resolve(opt('--carry'))] : []), ...(opt('--rejudge') ? ['--rejudge', resolve(opt('--rejudge'))] : []), ...(argv.includes('--control') ? ['--control'] : []), '--out', opt('--out', 'docs/reports/prompt-diet-2026-11-11')], { stdio: 'inherit', cwd: REPO, env: { ...process.env, DENO_NO_PACKAGE_JSON: '1' } });
  process.exit(r.status ?? 1);
}
