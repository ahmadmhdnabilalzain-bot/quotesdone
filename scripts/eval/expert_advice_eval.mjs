#!/usr/bin/env node
// THE EXPERT-ADVICE EVAL (10 Nov 2026, sales_engineer; founder ledger 1572, 1579, 1586). Real models, capped, ZZ DEMO only.
// The bank and the code graders: scripts/eval/expert_advice_bank.mjs (27 openings across all twelve taxonomy groups x English,
// Egyptian, Levantine, Gulf and Arabizi = 135 conversations of three customer turns).
//
//   node scripts/eval/expert_advice_eval.mjs selftest                 # offline: every grader catches its bad conversation
//   QD_FIXTURES=1 node scripts/eval/expert_advice_eval.mjs run --cap 12 [--only mdf_partition,bus_rental] [--registers en,gulf]
//        [--local <url of inquiry_intake served from this branch>] [--out docs/reports/expert-advice-eval-2026-11/run.json]
//   QD_FIXTURES=1 node scripts/eval/expert_advice_eval.mjs judge --in <run.json> --cap 2
//
// WHAT RUNS. Each conversation is a fresh ZZ DEMO customer (@example.invalid, a fixture mobile; scripts/e2e/fixtures.mjs) talking
// to the request chat (inquiry_intake, the T3 interview class inquiry_qualification_conversation, on whatever model
// model_policy routes it to at run time; the report names it), inside a tagged rehearsal window whose cap is ALSO enforced here
// before every turn (the run's tagged ai_cost_log spend + the next turn's estimate). PRECONDITION: the phase-1/2 SQL is applied
// (public.inquiry_state with its phase-2 columns) and inquiry_intake is deployed from this branch, or --local serves it.
//
// CODE GRADES (expert_advice_bank.mjs graders, BAR): two or more options offered by turn 2 (inquiry_state.options_offered);
// a size, quantity or budget asked before it was given; the job placed in its taxonomy trade (trade_codes); service keys
// named (specs.service_keys or brief.service_keys); turn 3 never asks again what turn 2 gave; no price we made up; no company
// named. JUDGE GRADES (judge mode, a model of ANOTHER family than the interview's, knowledge_validation with counterpart_model,
// booked under wa_inbound's think entry as the routing evals do): the options are specific to the case described, not generic
// (0-2); the register held (the customer's dialect, or English); an expert score 0-10. PASS: every code bar, judge relevance
// mean >= 1.5, register held >= 90 %, expert mean >= 7.
//
// COST (stated before anyone runs it; prices from model_registry on 10 Nov 2026, Sonnet 5.5 at USD 2 / 10 per Mtok): one
// intake turn is ~9k prompt tokens (the taxonomy or the trade pack, the reference options, the state) + ~600 out, plus a voice
// call on some turns: ~USD 0.03. 135 conversations x 3 turns = 405 turns ~ USD 12; the judge ~USD 0.012 each ~ USD 1.6.
// About USD 13.6 for the whole bank on Sonnet; on Luna Pro (0.10 / 0.50) about USD 1. --registers en,gulf is 54 conversations
// (~USD 5); --only <id> for one opening across the five registers (~USD 0.45). The window CHECK maximum is USD 15.
import { writeFileSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { conversations, grade, graders, summarise, OPENINGS, GROUPS, REGISTERS } from './expert_advice_bank.mjs';

const arg = (k) => (process.argv.includes(k) ? process.argv[process.argv.indexOf(k) + 1] : null);
const MODE = process.argv[2];
const TURN_EST = 0.035;   // USD, one intake turn and its voice on Sonnet (the dearest arm)
const JUDGE_EST = 0.02;

if (MODE === 'selftest') {
  const c = conversations({ only: ['mdf_partition'], registers: ['en'] })[0];
  const good = { options_after_2: 3, trade_codes: ['wallpaper'], service_keys: ['wallpaper.wall_panels'], turns: [
    { reply: 'PVC panels are moisture-proof, a vinyl film keeps the shape, paint is simplest. What size is the partition?' },
    { reply: 'For a kids room the film is low-odour; I recommend it. What budget do you have in mind?' },
    { reply: 'Noted, about 3,000 AED. Which emirate is it in?' }] };
  const bad = { options_after_2: 0, trade_codes: ['flooring'], service_keys: [], turns: [
    { reply: 'Sure, we can help.' }, { reply: 'Great.' },
    { reply: 'ABC Decor LLC can do it for AED 4,500. What size is the partition?' }] };
  const g = grade(c, good), b = grade(c, bad);
  const fails = [];
  for (const k of Object.keys(graders)) { if (g[k] !== true) fails.push(`good conversation failed ${k}: ${g[k]}`); if (b[k] === true) fails.push(`bad conversation passed ${k}`); }
  const all = conversations();
  if (all.length !== OPENINGS.length * REGISTERS.length) fails.push('bank size');
  for (const gr of GROUPS) if (OPENINGS.filter((o) => o.group === gr).length < 2) fails.push('group with fewer than two openings: ' + gr);
  for (const cv of all) if (cv.turns.length !== 3 || cv.turns.some((t) => !t || t.length < 8)) fails.push('a short or missing turn: ' + cv.id);
  if (!summarise([{ grades: g }]).pass || summarise([{ grades: b }]).pass) fails.push('summarise');
  console.log(fails.length ? 'SELFTEST FAILED\n' + fails.join('\n') : `SELFTEST OK: ${all.length} conversations, ${OPENINGS.length} openings, ${GROUPS.length} groups, every grader catches its bad case`);
  process.exit(fails.length ? 1 : 0);
}

const { openRun, closeRun, makeDemoCustomer, call, read } = await import('../e2e/fixtures.mjs');
const run = await openRun({ label: 'expert-advice-' + MODE, capUsd: Number(arg('--cap') ?? (MODE === 'judge' ? 2 : 12)), minutes: 120 });
const CAP = Number(arg('--cap') ?? (MODE === 'judge' ? 2 : 12));
const tag = run.tag;
const spent = async () => Number((await read(`select coalesce(sum(coalesce(cost_usd_reported, cost_aed / 3.6725)), 0)::float8 s from public.ai_cost_log where e2e_run_tag = '${tag}'`))[0].s);
const idOf = (x) => String(x ?? '').replace(/[^0-9a-f-]/gi, '');

if (MODE === 'run') {
  const LOCAL = arg('--local');
  const OUT = arg('--out') ?? 'docs/reports/expert-advice-eval-2026-11/run.json';
  const list = conversations({ only: arg('--only')?.split(',') ?? null, registers: arg('--registers')?.split(',') ?? REGISTERS });
  const intake = async (jwt, body) => {
    if (!LOCAL) return call('inquiry_intake', jwt, body, 120_000);
    const { keys, internalCred } = await import('../lib/demo_factory.mjs');
    const { ANON } = await keys();
    const r = await fetch(LOCAL, { method: 'POST', signal: AbortSignal.timeout(120_000), headers: { apikey: ANON, Authorization: 'Bearer ' + jwt, 'Content-Type': 'application/json',
      'x-qd-e2e-run': tag, 'x-qd-e2e-secret': await internalCred() }, body: JSON.stringify(body) });
    const text = await r.text(); let json = null; try { json = JSON.parse(text); } catch { /* the body is the finding */ }
    return { status: r.status, json };
  };
  const results = []; let stopped = null;
  try {
    for (const c of list) {
      const cust = await makeDemoCustomer(run, { locale: c.lang });
      const r = { id: c.id, opening: c.opening, group: c.group, register: c.register, turns: [], options_after_2: 0, trade_codes: [], service_keys: [] };
      let intakeId = null;
      for (const [i, text] of c.turns.entries()) {
        const s = await spent();
        if (s + TURN_EST >= CAP) { stopped = `spend cap: USD ${s.toFixed(4)} spent + ${TURN_EST} would reach USD ${CAP}`; break; }
        const t0 = Date.now();
        const res = await intake(cust.jwt, { ...(intakeId ? { intake_id: intakeId } : {}), text, email: cust.email, lang: c.lang, turn_id: `${tag}-${c.id}-${i}` });
        const j = res.json || {};
        intakeId = j.intake_id || intakeId;
        r.turns.push({ n: i + 1, said: text, http: res.status, ms: Date.now() - t0, status: j.status ?? null, reply: String(j.assistant_message ?? ''), next: j.next_question?.text ?? null });
        const st = intakeId ? (await read(`select options_offered, trade_codes, specs, chosen_option, condition, budget from public.inquiry_state where conv_key = 'intake:${idOf(intakeId)}'`))[0] ?? null : null;
        if (i === 1) r.options_after_2 = Array.isArray(st?.options_offered) ? st.options_offered.length : 0;
        if (st) { r.trade_codes = st.trade_codes ?? []; r.state = st; }
      }
      const row = intakeId ? (await read(`select status, brief from public.inquiry_intake where id = '${idOf(intakeId)}'`))[0] ?? {} : {};
      r.service_keys = [...new Set([...String(r.state?.specs?.service_keys?.value ?? '').split(',').map((x) => x.trim()).filter(Boolean), ...(row.brief?.service_keys ?? [])])];
      r.models = (await read(`select distinct model_used from public.ai_cost_log where e2e_run_tag = '${tag}' and fn = 'inquiry_intake'`)).map((x) => x.model_used);
      r.grades = grade(c, r);
      results.push(r);
      console.log(`${c.id}: ${Object.entries(r.grades).filter(([, v]) => v !== true).map(([k, v]) => k + ' (' + v + ')').join('; ') || 'all code grades met'}`);
      if (stopped) break;
    }
  } finally { await closeRun(run).catch((e) => console.error('teardown: ' + e.message)); }
  const sum = { ...summarise(results), spend_usd: await spent().catch(() => null), cap_usd: CAP, run_tag: 'qd_run:' + tag, stopped,
    complete: !stopped && results.length === list.length };
  mkdirSync(dirname(OUT), { recursive: true });
  writeFileSync(OUT, JSON.stringify({ eval: 'expert_advice', at: new Date().toISOString(), summary: sum, results }, null, 1));
  console.log(JSON.stringify(sum, null, 1));
  process.exit(sum.pass && sum.complete ? 0 : 1);
}

if (MODE === 'judge') {
  const IN = arg('--in');
  if (!IN) throw new Error('--in <run.json> is required');
  const data = JSON.parse(readFileSync(IN, 'utf8'));
  const secret = (await read(`select value from public.app_secrets where key = 'cred_fn_ai'`))[0]?.value;
  if (!secret) throw new Error('cred_fn_ai could not be read');
  const SYS = `You judge a UAE procurement sales conversation by the standard of an experienced technical salesperson OF THE TRADE IT IS ABOUT
(founder ledger 1572/1586: every trade but food and beverage; diagnose what the customer describes, put two or three suitable options with the
reason and the trade-off, then qualify: sizes or quantities, budget, location rules). Return ONE JSON object:
{"relevance": <0 none, 1 generic, 2 specific to the case described>, "register_held": <true if every reply is in the customer's own language and
dialect register (English, or polite Egyptian / Levantine / Gulf Arabic mirroring theirs; Arabizi may be answered in Arabic script)>, "score": <0-10>,
"named_supplier_or_price": <true if any reply names a company or states a price the customer did not give>, "why": "<two sentences>"}`;
  const graded = []; let stopped = null;
  try {
    for (const r of data.results) {
      const s = await spent();
      if (s + JUDGE_EST >= CAP) { stopped = `spend cap: USD ${s.toFixed(4)} + ${JUDGE_EST}`; break; }
      const author = (r.models ?? []).find((m) => String(m).includes('/')) ?? 'anthropic/claude-sonnet-5.5';
      const transcript = r.turns.map((t) => `#${t.n} CUSTOMER: ${t.said}\n#${t.n} AGENT: ${t.reply}`).join('\n');
      const res = await call('ai_gateway', null, { __secret: secret, fn: 'wa_inbound', task_class: 'knowledge_validation', counterpart_model: author, seat: 'it_engineer',
        sys: SYS, input: JSON.stringify({ conversation: r.id, register: r.register, transcript }), max: 800, temperature: 0, subject: { fixture: true } }, 90_000);
      const txt = String(res.json?.content ?? '');
      let v = {}; try { v = JSON.parse(txt.slice(txt.indexOf('{'), txt.lastIndexOf('}') + 1)); } catch { v = { unread: txt.slice(0, 200) || res.text }; }
      graded.push({ id: r.id, author, judge: res.json?.model ?? null, ...v });
      console.log(r.id, res.json?.model ?? '-', JSON.stringify(v).slice(0, 160));
    }
  } finally { await closeRun(run).catch(() => {}); }
  const mean = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : NaN);
  const m = { judged: graded.length, relevance_mean: mean(graded.map((g) => Number(g.relevance)).filter((x) => !Number.isNaN(x))),
    register_held_pct: 100 * graded.filter((g) => g.register_held === true).length / Math.max(1, graded.length),
    score_mean: mean(graded.map((g) => Number(g.score)).filter((x) => !Number.isNaN(x))), named_supplier_or_price: graded.filter((g) => g.named_supplier_or_price === true).length,
    spend_usd: await spent().catch(() => null), run_tag: 'qd_run:' + tag, stopped };
  const pass = !stopped && m.judged === data.results.length && m.relevance_mean >= 1.5 && m.register_held_pct >= 90 && m.score_mean >= 7 && m.named_supplier_or_price === 0;
  writeFileSync(IN.replace(/\.json$/, '') + '_judged.json', JSON.stringify({ pass, metrics: m, graded }, null, 1));
  console.log(JSON.stringify({ pass, ...m }, null, 1));
  process.exit(pass ? 0 : 1);
}
console.error('usage: expert_advice_eval.mjs selftest | run [--cap 12] [--only ..] [--registers ..] [--local url] [--out f] | judge --in f [--cap 2]');
process.exit(2);
