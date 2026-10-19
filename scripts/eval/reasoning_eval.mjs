// REASONING EVALUATION HARNESS — runs the question bank through think() and scores it.
// Seat: it_engineer (shared platform). 23 Sep 2026, founder_instruction 886-903.
//
//   node scripts/eval/reasoning_eval.mjs            # MOCK: a scripted model, no network, no cost (CI)
//   node scripts/eval/reasoning_eval.mjs --live     # the real engine through ai_gateway; refuses under the hold
//   node scripts/eval/reasoning_eval.mjs --seat=marketing --limit=20 --json
//
// THE SCORES, per case and per seat:
//   answered   — status 'answered' and the answer passes the evasion validator (903: no "I'll get back to you")
//   sources    — when the bank names the knowledge a correct answer rests on (expect.entry_ids), one of them is cited
//   steps      — the trail has a finished decompose step and at least one retrieval (or a reasoned skip)
//   asked_back — a question back ONLY when the case says a decision-changing fact is missing, and always then
//   decision   — for a decision point, the choice the bank expects
//
// WHAT MOCK MODE PROVES AND WHAT IT DOES NOT. Under the founder's model hold no real model may be called, so
// CI runs think() against a scripted model: every case goes through the real engine — plan, retrieval, the
// validator, the verify routing, the held queue — and a second, ADVERSARIAL pass feeds each answer case an
// evasive draft and a needless question back, which the engine must refuse (a harness that cannot fail is
// not a harness). It does NOT measure the quality of a real model's reasoning; that is --live, the moment the
// hold lifts, and its score is the one reported as "the reasoning score".
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const args = Object.fromEntries(process.argv.slice(2).map((a) => { const [k, v] = a.replace(/^--/, '').split('='); return [k, v ?? true]; }));
const BANK = JSON.parse(readFileSync(join(REPO, 'scripts/eval/reasoning_bank.json'), 'utf8')).cases
  .filter((c) => !args.seat || c.seat === args.seat).slice(0, args.limit ? Number(args.limit) : undefined);
// Node 24 strips TypeScript types natively; think.ts uses only erasable syntax and loads Deno-only modules lazily.
const { think, refuse } = await import(pathToFileURL(join(REPO, 'supabase/functions/_shared/think.ts')).href);
const { SITE_OPTIONS } = await import(pathToFileURL(join(REPO, 'supabase/functions/_shared/reasoned_channels.ts')).href);

const NEEDS_PERSON = [
  { id: 'needs_a_person', meaning: 'they ask for a human, or complain, dispute, demand a refund, accuse, or threaten legal action' },
  { id: 'no_person', meaning: 'anything else, including a question that merely mentions law or refunds as a topic' },
];
const CEO_INTENTS = ['build', 'fix', 'remove', 'measure', 'decide', 'stop', 'inform', 'ask'].map((id) => ({ id, meaning: id }));
function requestOf(c) {
  const base = { seat: c.seat, surface: c.surface ?? 'eval.answer', question: c.q, context: { audience: c.audience ?? 'internal', trade: c.trade ?? null }, queueWhenHeld: false };
  if (c.kind !== 'decision') return { ...base, stakes: c.expect?.stakes === 'high' ? 'high' : 'normal' };
  // A case may carry its own options (a quote's fields, retrieved passages); the widget route uses the widget's.
  const options = c.options ?? (c.surface === 'ceo.command_intent' ? CEO_INTENTS : c.surface === 'shared.route_question' ? SITE_OPTIONS : NEEDS_PERSON);
  return { ...base, decision: { name: c.surface, options } };
}

// ── the scripted model (MOCK) ─────────────────────────────────────────────────────────────────────
function mockDeps(c, mode) {
  const expected = c.expect?.entry_ids ?? [];
  const missing = (c.expect?.decision_changing ?? []).map((name) => ({ name, why: 'changes which rule applies', changes_answer: true, value: null, from: null }));
  const say = 'The governing authority is named, the limits for each emirate are given, and the reasoning is shown step by step with the sources cited, so the person has everything that can be said now.';
  let synthCalls = 0;
  return {
    gate: async () => ({ allowed: false, rule: 'route_not_registered' }),
    embed: async () => [0.1, 0.2],
    rpc: async (fn) => {
      if (fn === 'fn_reason_retrieve') return { data: expected.map((id) => ({ source: 'sales_knowledge', id, title: id, excerpt: 'pack entry ' + id, similarity: 0.9 })), error: null };
      if (fn === 'fn_case_recall') return { data: { cases: [] }, error: null };
      return { data: null, error: null };
    },
    llm: async (phase) => {
      if (phase === 'decompose') return { content: JSON.stringify({ steps: [{ id: 's1', goal: 'find the governing rule', query: c.q, needs_knowledge: c.kind !== 'decision' }], facts: missing, high_stakes: c.expect?.stakes === 'high' }), model: 'mock/author' };
      if (phase === 'verify') return { content: JSON.stringify({ verdict: 'agree', problems: [] }), model: 'mock/other-family' };
      synthCalls++;
      const cited = expected.slice(0, 1).map((id) => 'sales_knowledge:' + id);
      if (mode === 'evasive') return { content: JSON.stringify({ answer: 'I need to check and get back to you.', cited: [] }), model: 'mock/author' };
      if (mode === 'needless_ask' && !missing.length && c.kind !== 'decision') return { content: JSON.stringify({ answer: say, reasoning: ['s1: found'], cited, confidence: 0.7, asked_back: 'Could you tell me more?' }), model: 'mock/author' };
      const ask = missing.length ? `Which ${missing.map((m) => m.name).join(' and ')} is it?` : null;
      const decision = c.kind === 'decision' ? { choice: c.expect.choice } : undefined;
      return { content: JSON.stringify({ answer: say + (ask ? ' ' + ask : ''), reasoning: ['s1: the governing rule was found'], cited, confidence: 0.8, asked_back: ask, decision }), model: 'mock/author' };
    },
  };
}

// ── the real engine (LIVE) ───────────────────────────────────────────────────────────────────────
async function liveDeps() {
  const url = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE_KEY, secret = process.env.QD_AI_GATEWAY_SECRET;
  if (!url || !key || !secret) throw new Error('--live needs SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY and QD_AI_GATEWAY_SECRET');
  const H = { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' };
  const rpc = async (fn, a) => { const r = await fetch(`${url}/rest/v1/rpc/${fn}`, { method: 'POST', headers: H, body: JSON.stringify(a), signal: AbortSignal.timeout(30_000) }); const j = await r.json().catch(() => null); return r.ok ? { data: j, error: null } : { data: null, error: { message: j?.message ?? String(r.status) } }; };
  const gw = async (body) => (await fetch(`${url}/functions/v1/ai_gateway`, { method: 'POST', headers: H, body: JSON.stringify({ __secret: secret, fn: 'reasoning_eval', ...body }), signal: AbortSignal.timeout(90_000) })).json();
  return {
    gate: async () => (await rpc('fn_kernel_paid_provider_gate', { p_model: 'hold-probe/not-a-model' })).data,
    // the gateway's embed answer is the vector as a string, '[0.1,...]' (_shared/embed_answer.ts)
    embed: async (text) => { const e = (await gw({ action: 'embed', text }))?.embedding; return typeof e === 'string' ? JSON.parse(e) : null; },
    rpc,
    llm: async (_phase, sys, input, o) => { const j = await gw({ task_class: o.taskClass, agent: o.seat, sys, input: [{ role: 'user', content: input }], max: o.max ?? 900, cache_ttl_min: 0, ...(o.counterpartModel ? { counterpart_model: o.counterpartModel } : {}) }); return { content: typeof j?.content === 'string' ? j.content : null, model: j?.model ?? null, error: j?.error ?? null }; },
  };
}

// ── scoring ──────────────────────────────────────────────────────────────────────────────────────
export function score(c, r) {
  const s = {};
  s.answered = r.status === 'answered' && refuse({ answer: r.answer }, { missing: [], sourceIds: new Set(), conversationText: '' }) === null;
  s.steps = r.steps.some((x) => x.kind === 'decompose' && x.status === 'done') && r.steps.some((x) => x.kind === 'retrieve');
  if (c.expect?.entry_ids?.length) s.sources = r.sources.some((x) => c.expect.entry_ids.some((id) => x.id.endsWith(':' + id) || x.citation === id));
  if (c.kind !== 'decision') s.asked_back = (c.expect?.asked_back === true) === !!r.asked_back;
  if (c.kind === 'decision') s.decision = r.decision?.choice === c.expect.choice;
  s.pass = Object.values(s).every(Boolean);
  return s;
}

async function run(mode) {
  const live = mode === 'live';
  const deps = live ? await liveDeps() : null;
  if (live) {
    const g = await deps.gate();
    if (['founder_hold', 'no_paid_ai_switch', 'empty_route_state'].includes(g?.rule)) { console.log(`HELD: the gate refuses (${g.rule}); no live score is possible and none is invented.`); process.exit(0); }
  }
  const rows = [];
  for (const c of BANK) {
    const r = await think(live ? deps : mockDeps(c, mode), requestOf(c));
    rows.push({ id: c.id, seat: c.seat, kind: c.kind, ...score(c, r), status: r.status, askedBack: !!r.asked_back });
  }
  return rows;
}
function summary(rows, label) {
  const by = {};
  for (const r of rows) { const b = (by[r.seat] ??= { n: 0, pass: 0, answered: 0 }); b.n++; b.pass += r.pass ? 1 : 0; b.answered += r.answered ? 1 : 0; }
  const n = rows.length, pass = rows.filter((r) => r.pass).length;
  console.log(`\n${label}: ${pass}/${n} pass`);
  for (const [seat, b] of Object.entries(by)) console.log(`  ${seat.padEnd(18)} ${b.pass}/${b.n} pass, ${b.answered}/${b.n} answered`);
  return { n, pass };
}

const main = async () => {
  if (args.live) {
    const rows = await run('live');
    const s = summary(rows, 'LIVE reasoning score');
    if (args.json) console.log(JSON.stringify(rows, null, 1));
    process.exit(s.pass === s.n ? 0 : 1);
  }
  const good = await run('mock');
  const g = summary(good, 'MOCK (scripted reasoner): the engine and the scorer on every case');
  const evasive = await run('evasive');
  const caught = evasive.filter((r) => r.kind === 'answer' && !r.answered).length, answerCases = evasive.filter((r) => r.kind === 'answer').length;
  console.log(`ADVERSARIAL: ${caught}/${answerCases} evasive drafts refused and never answered`);
  const needless = await run('needless_ask');
  // refused, scored as a failure, or (since 19 Oct 2026, think.groundDraft) removed while the answer stands: in every
  // case the needless question never reaches the person.
  const flagged = needless.filter((r) => r.kind === 'answer' && (!r.pass || !r.askedBack)).length;
  const needlessCases = BANK.filter((c) => c.kind === 'answer' && !(c.expect?.decision_changing ?? []).length).length;
  console.log(`ADVERSARIAL: ${flagged}/${needlessCases} needless questions back refused, scored as failures or removed`);
  if (args.json) console.log(JSON.stringify({ good, evasive, needless }, null, 1));
  const ok = g.pass === g.n && caught === answerCases && flagged === needlessCases;
  console.log(ok ? '\nHARNESS OK' : '\nHARNESS FAILED');
  process.exit(ok ? 0 : 1);
};
if (import.meta.url === pathToFileURL(process.argv[1]).href) await main();
