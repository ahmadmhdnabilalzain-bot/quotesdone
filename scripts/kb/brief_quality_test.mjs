#!/usr/bin/env node
// The cached-brief quality test (founder ruling 1198, 12 Oct 2026): 30 questions (15 EN / 15 AR) answered
// with the compiled brief as the cached system block on each candidate model, then judged BLIND by
// gemini-3.8-flash. The only model spend this work is allowed: it runs inside a rehearsal_window row
// (run_tag qd_run:<tag>, models_allowed, cap_usd) and stops itself before the cap.
//
//   node scripts/kb/brief_quality_test.mjs --out <dir> [--tag briefqa1012] [--cap 3]
//
// Costs are OpenRouter's own usage.cost per call (usage accounting), split into cache write / read
// tokens as the provider reports them -- never a price-table estimate.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { sql } from '../lib/db.mjs';
import { compileBrief } from './compile_brief.mjs';

const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const OUT = arg('--out'); if (!OUT) throw new Error('--out <dir> is required (use the session scratchpad)');
const TAG = arg('--tag', 'briefqa' + new Date().toISOString().slice(5, 10).replace('-', ''));
const CAP = Number(arg('--cap', 3));
const MODELS = (arg('--models', 'openai/gpt-6-luna,anthropic/claude-haiku-5.5,anthropic/claude-sonnet-5.5,anthropic/claude-opus-5.5')).split(',');
const JUDGE = arg('--judge', 'google/gemini-3.8-flash'); // a model never judges itself: pass --judge when gemini is a candidate
const MAX = Number(arg('--max', 2000)); // 900 truncated Sonnet 18/30 and Opus 10/30 on 12 Oct
const JUDGE_FULL = process.argv.includes('--judge-full'); // judge sees the digests too, not only company.md
mkdirSync(OUT, { recursive: true });

const questions = JSON.parse(readFileSync(new URL('./brief_quality_questions.json', import.meta.url), 'utf8'));
const brief = compileBrief();
const PREAMBLE = `You are QuotesDone's customer-facing assistant (website chat, WhatsApp and the portals). ` +
  `Below is everything you know about the company and UAE trade regulations. Reason from it like a senior ` +
  `human colleague: give one direct, exact answer in the language the person writes in (Arabic in, Arabic out). ` +
  `Never invent figures, dates, clauses, approvals or supplier identities. If the brief does not cover it, say ` +
  `so plainly and give your best general expert guidance labelled as such. Keep replies chat-length.\n\n`;
const SYSTEM = PREAMBLE + brief.text;
// A candidate written "model+deep" runs that model with one added instruction (coordinator, 13 Oct: Luna and Haiku
// scored low on helpfulness with ~200-token answers; does asking for depth close the gap?).
const DEEP = 'Give a complete, expert, well-structured answer (not a short one), then ask the one or two follow-up questions that matter.\n\n';
const modelOf = (c) => c.replace(/\+deep$/, '');
const systemOf = (c) => (c.endsWith('+deep') ? DEEP : '') + SYSTEM;

let spent = 0;
const key = (await sql(`select value from public.app_secrets where key = 'openrouter_api_key'`))[0]?.value;
if (!key) throw new Error('openrouter_api_key missing');

async function call(model, system, user, { cache, max = MAX }) {
  if (spent >= CAP - 0.15) throw new Error(`spend ceiling: USD ${spent.toFixed(4)} of ${CAP}`);
  const sys = cache ? [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }] : system;
  const t0 = Date.now();
  const r = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: { authorization: `Bearer ${key}`, 'content-type': 'application/json', 'x-title': `QuotesDone qd_run:${TAG}` },
    body: JSON.stringify({ model, max_tokens: max, usage: { include: true },
      messages: [{ role: 'system', content: sys }, { role: 'user', content: user }] }),
  });
  const j = await r.json();
  if (!r.ok || !j.choices) throw new Error(`${model} HTTP ${r.status}: ${JSON.stringify(j).slice(0, 300)}`);
  const u = j.usage || {};
  spent += Number(u.cost || 0);
  return { text: j.choices[0].message.content || '', finish: j.choices[0].finish_reason, ms: Date.now() - t0, cost: Number(u.cost || 0),
    prompt: u.prompt_tokens, completion: u.completion_tokens,
    cached_read: u.prompt_tokens_details?.cached_tokens ?? 0,
    cache_write: u.prompt_tokens_details?.cache_write_tokens ?? u.cache_creation_input_tokens ?? 0 };
}

await sql(`insert into public.rehearsal_window (run_tag, opened_by, note, models_allowed, cap_usd, expires_at)
  values ('qd_run:${TAG}', 'scripts/kb/brief_quality_test.mjs', 'cached-brief quality test, ledger 1198; models: ${MODELS.join(' ')}; judge ${JUDGE}', true, ${CAP}, now() + interval '2 hours')`);
const JUDGE_ONLY = process.argv.includes('--judge-only'); // re-judge saved answers without buying them again
const answers = JUDGE_ONLY ? JSON.parse(readFileSync(join(OUT, 'answers.json'), 'utf8')) : {};
try {
  for (const m of JUDGE_ONLY ? [] : MODELS) {
    const cache = modelOf(m).startsWith('anthropic/') || modelOf(m).startsWith('google/'); // explicit cache_control; OpenAI caches the stable prefix by itself
    answers[m] = {};
    // first call alone writes the cache; the rest read it (3 lanes, inside the 5-minute TTL)
    answers[m][questions[0].id] = await call(modelOf(m), systemOf(m), questions[0].q, { cache });
    for (let i = 1; i < questions.length; i += 3) {
      const batch = questions.slice(i, i + 3);
      const res = await Promise.all(batch.map((q) => call(modelOf(m), systemOf(m), q.q, { cache }).catch((e) => ({ error: String(e), cost: 0 }))));
      batch.forEach((q, k) => { answers[m][q.id] = res[k]; });
    }
    writeFileSync(join(OUT, 'answers.json'), JSON.stringify(answers, null, 1)); // saved per model: a key-limit stop keeps what was bought
    console.log(`${m}: USD ${Object.values(answers[m]).reduce((s, a) => s + a.cost, 0).toFixed(4)} (running ${spent.toFixed(4)})`);
  }
  writeFileSync(join(OUT, 'answers.json'), JSON.stringify(answers, null, 1));

  // ---- blind judging: labels shuffled per question, the judge sees the brief as ground truth ----
  const JSYS = `You are a strict evaluator of customer-service answers for QuotesDone, a UAE quotation marketplace. ` +
    `The company brief below is the ground truth. For each candidate answer give a score 0-10 for: accuracy ` +
    `(no claim contradicting or going beyond the brief, no invented figures), helpfulness (directly answers, ` +
    `expert quality, actionable), language (same language as the question, natural, professional), and an overall ` +
    `0-10. Use the answer letters as keys. Reply ONLY with JSON: {"scores":{"A":{"accuracy":n,"helpfulness":n,"language":n,"overall":n,"note":"<=20 words"},"B":{...}}}\n\n` +
    // ponytail: the judge gets company.md only (~4.6k tokens). The first judged run used the full 29k brief and cost
    // USD 0.84; regulation answers are judged on general expertise. Pass the digests too if the cap allows.
    (JUDGE_FULL ? brief.text : readFileSync(new URL('../../knowledge/brief/company.md', import.meta.url), 'utf8'));
  const judged = {};
  for (let i = 0; i < questions.length; i += 3) {
    await Promise.all(questions.slice(i, i + 3).map(async (q) => {
      const order = [...MODELS].sort(() => Math.random() - 0.5);
      const labels = order.map((_, k) => String.fromCharCode(65 + k));
      const body = `QUESTION:\n${q.q}\n\n` + order.map((m, k) => `=== Answer ${labels[k]} ===\n${answers[m][q.id]?.text || '(no answer)'}`).join('\n\n');
      let r, parsed = null, cost = 0;
      for (let t = 0; t < 2 && !parsed; t++) { // one retry: a judge reply that is not JSON is re-asked, never scored
        r = await call(JUDGE, JSYS, body, { cache: true, max: 2500 }); cost += r.cost;
        try { parsed = JSON.parse(r.text.match(/\{[\s\S]*\}/)[0]); } catch { parsed = null; }
      }
      parsed ??= { scores: {} }; r.cost = cost;
      const sc = parsed.scores ?? parsed; // tolerate {A:..} or {scores:{'Answer A':..}}
      const pick = (l) => sc[l] ?? sc['Answer ' + l] ?? sc['answer_' + l.toLowerCase()] ?? null;
      judged[q.id] = { cost: r.cost, raw: r.text, by_model: Object.fromEntries(order.map((mm, k) => [mm, pick(labels[k])])) };
    }));
  }
  writeFileSync(join(OUT, 'judged.json'), JSON.stringify(judged, null, 1));

  // ---- table ----
  const rows = MODELS.map((m) => {
    const a = Object.values(answers[m]); const s = Object.values(judged).map((j) => j.by_model[m]).filter(Boolean);
    const avg = (k, f = () => true) => { const v = Object.entries(judged).filter(([id]) => f(id)).map(([, j]) => j.by_model[m]?.[k]).filter((x) => typeof x === 'number'); return v.length ? (v.reduce((x, y) => x + y, 0) / v.length) : NaN; };
    const cost = a.reduce((x, y) => x + y.cost, 0);
    const warm = a.slice(1).filter((x) => !x.error); // steady state: every reply after the cache write
    const perWarm = warm.reduce((x, y) => x + y.cost, 0) / warm.length;
    return { model: m, overall: avg('overall'), accuracy: avg('accuracy'), helpfulness: avg('helpfulness'), language: avg('language'),
      en: avg('overall', (id) => id.startsWith('en')), ar: avg('overall', (id) => id.startsWith('ar')),
      errors: a.filter((x) => x.error).length, usd_total: cost, usd_per_1000_warm: perWarm * 1000,
      cache_write_tokens: a.reduce((x, y) => x + (y.cache_write || 0), 0), cache_read_tokens: a.reduce((x, y) => x + (y.cached_read || 0), 0),
      prompt_tokens: a.reduce((x, y) => x + (y.prompt || 0), 0), first_call_usd: a[0].cost,
      avg_out_tokens: Math.round(a.reduce((x, y) => x + (y.completion || 0), 0) / a.length),
      median_ms: a.map((x) => x.ms || 0).sort((x, y) => x - y)[15], scored: s.length };
  });
  const judgeCost = Object.values(judged).reduce((x, y) => x + y.cost, 0);
  writeFileSync(join(OUT, 'summary.json'), JSON.stringify({ tag: TAG, brief_sha: brief.sha, brief_tokens_approx: brief.approxTokens, rows, judge: JUDGE, judge_usd: judgeCost, total_usd: spent }, null, 1));
  console.table(rows.map((r) => ({ ...r, overall: r.overall.toFixed(2), usd_total: r.usd_total.toFixed(4), usd_per_1000_warm: r.usd_per_1000_warm.toFixed(2) })));
  console.log(`judge USD ${judgeCost.toFixed(4)}; TOTAL USD ${spent.toFixed(4)} of cap ${CAP}`);
} finally {
  await sql(`update public.rehearsal_window set ended_at = now(), note = note || ' | spent USD ${spent.toFixed(4)}' where run_tag = 'qd_run:${TAG}' and ended_at is null`);
}
