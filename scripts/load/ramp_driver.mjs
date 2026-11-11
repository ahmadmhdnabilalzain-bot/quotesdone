#!/usr/bin/env node
// it_engineer — closed-loop load driver: virtual users ramped 10 -> 50 -> 100 -> 200 (founder ruling 1622, 10 Nov 2026:
// "scalable — e.g. 100 customers chatting at the same time must not crash the company"). Results:
// docs/reports/2026-11-11-load-test.md; plan and limits: docs/it/CAPACITY_PLAN_JANUARY_2027.md.
//
// k6 is not installed and nothing may be installed globally, so this is plain Node (global fetch = undici, keep-alive
// connection reuse). Each virtual user (VU) is one visitor: it makes a request, waits for the answer, thinks, and goes
// again, so the offered load is what N people do, not a fixed rate that queues up behind a slow server.
//
// THE MIXES, AND WHY EACH IS SAFE AGAINST PRODUCTION
//   embed      embed_ml action 'gte' (Supabase's own gte-small, free; QD_LOAD_EMBED_ACTION=query for the multilingual model), pinned to the database region exactly as the
//              gateway asks it (_shared/ml_embed_client.ts): the piece that answered 546 WORKER_LIMIT on 10 Nov. Needs
//              QD_LOAD_EMBED_SECRET (cred_fn_ai); writes nothing, calls no model.
//   website    GET the public pages exactly as a browser does (CDN-cached HTML) plus the page-load reads those pages make
//              to public_site (counters on the hero, worked_case on /how-it-works, guarantee_terms on /refund-policy,
//              trade_needs on /services/<slug>). Reads only: nothing is written but rl_hits rows the CDN-cached pages
//              never reach. No model, no person.
//   functions  the same public_site reads with no page between them: the edge function + database path without the CDN.
//   chat       site_assistant widget turns, ONLY for a proven load run (QD_LOAD_RUN_TAG + QD_LOAD_RUN_SECRET, the
//              internal secret) whose rehearsal_window is opened_by 'load_test' with models_allowed=false: the gateway
//              answers with the canned completion (_shared/load_stub.ts) and calls no provider. The driver refuses the
//              mix without the tag, and between stages reads ai_cost_log for the tag and aborts on any cost or any
//              model other than load_stub / none (level-0 FAQ). Each VU is a fresh widget conversation (random UUID) from
//              an address in 198.18.0.0/15 (RFC 2544, benchmarking), all of it keyed under 'load:<tag>:'.
// ABORT RULE: a stage whose error rate passes 2% (after 50 samples) stops the whole run at once. An error is a 5xx, a
// network failure or a timeout; a 429 is counted apart as "limited" (the first limit hit), and also counts toward abort.
//
//   node scripts/load/ramp_driver.mjs --mix=website                       # dry run: prints the plan, sends nothing
//   NODE_USE_ENV_PROXY=1 node scripts/load/ramp_driver.mjs --mix=website --run --stages=10,50,100,200 \
//     --stage-seconds=40 --out=<scratch>/website.json
import { randomUUID } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { busyRetryDelay } from '../../src/lib/busyRetry.ts';

export const SITE = 'https://quotesdone.com';
export const SUPA = 'https://htdblwldjkcgjvmqkbeh.supabase.co';
export const FN_QS = '?forceFunctionRegion=ap-southeast-1';     // what the site's fnUrl() adds (src/lib/supaEnv.ts)
export const ABORT_ERROR_RATE = 0.02;
export const ABORT_MIN_SAMPLES = 50;
const SERVICES = { 'false-ceiling': 'gypsum', 'pest-control': 'pest', movers: 'movers', flooring: 'flooring', 'ac-maintenance': 'hvac',
  solar: 'solar', electrical: 'electrical', plumbing: 'plumbing', painting: 'painting', cleaning: 'cleaning', waterproofing: 'waterproofing' };
// A PAGE A BROWSER LOADS, and the public_site reads that page makes (src/components/Hero.tsx, WorkedCase.tsx, SupplierNeeds.tsx,
// src/app/[locale]/refund-policy/page.tsx). Weights are a guess at a launch visitor's path, stated as such in the report.
export const PAGES = [
  { w: 30, path: '/', reads: [{ action: 'counters' }] },
  { w: 8, path: '/ar', reads: [{ action: 'counters' }] },
  { w: 12, path: '/how-it-works', reads: [{ action: 'worked_case' }] },
  { w: 10, path: '/faq', reads: [] },
  { w: 8, path: '/services', reads: [] },
  { w: 16, path: '/services/:slug', reads: [{ action: 'trade_needs' }] },
  { w: 5, path: '/blog', reads: [] },
  { w: 3, path: '/about', reads: [] },
  { w: 3, path: '/contact', reads: [] },
  { w: 3, path: '/refund-policy', reads: [{ action: 'guarantee_terms' }] },
  { w: 2, path: '/api/health', reads: [] },
];
export const CHAT_QUESTIONS = [
  'How does QuotesDone work?', 'Which trades do you cover?', 'How long does it take to get quotes?',
  'Do I need to sign up to post a job?', 'Are the suppliers verified?', 'Can I compare the quotes side by side?',
  'كيف تعمل المنصة؟', 'Do you cover Abu Dhabi and Sharjah?',
];
export const MIXES = {
  website: { think: [2000, 6000], production: true, chat: false },
  functions: { think: [1000, 3000], production: true, chat: false },
  chat: { think: [5000, 12000], production: true, chat: true, turns: 3 },
  embed: { think: [500, 1500], production: true, chat: false, embed: true },
};

export class Refused extends Error { constructor(why) { super('load driver refused — prevented by: ' + why); } }

/** Nothing runs without --run; the chat mix runs only as a proven load run. */
export function assertRunnable(mixName, env, argv) {
  const mix = MIXES[mixName];
  if (!mix) throw new Refused(`unknown mix "${mixName}" (one of ${Object.keys(MIXES).join(', ')})`);
  if (!argv.includes('--run')) return { mix, dry: true };
  if (mix.embed && !env.QD_LOAD_EMBED_SECRET) throw new Refused('the embed mix needs QD_LOAD_EMBED_SECRET (cred_fn_ai)');
  if (mix.chat) {
    if (!/^[a-z0-9]{4,16}$/.test(String(env.QD_LOAD_RUN_TAG || ''))) throw new Refused('the chat mix needs QD_LOAD_RUN_TAG (the load window\'s run tag)');
    if (!env.QD_LOAD_RUN_SECRET) throw new Refused('the chat mix needs QD_LOAD_RUN_SECRET (the internal secret that proves the tag)');
    if (!env.SUPABASE_ACCESS_TOKEN) throw new Refused('the chat mix needs SUPABASE_ACCESS_TOKEN to read ai_cost_log between stages');
    if (!env.QD_LOAD_GATEWAY_SECRET) throw new Refused('the chat mix needs QD_LOAD_GATEWAY_SECRET (cred_fn_ai) for the stub preflight');
  }
  return { mix, dry: false };
}

export function pct(sorted, p) { return sorted.length ? sorted[Math.min(sorted.length - 1, Math.ceil(p * sorted.length) - 1)] : null; }
export function classify(status, err) {
  if (err) return 'error';
  if (status === 429) return 'limited';
  if (status >= 500) return 'error';
  return 'ok';
}
export function summarise(samples) {
  const by = {};
  for (const s of samples) (by[s.name] ??= []).push(s);
  const row = (list) => {
    const ms = list.map((s) => s.ms).sort((a, b) => a - b);
    const n = list.length, errors = list.filter((s) => s.cls === 'error').length, limited = list.filter((s) => s.cls === 'limited').length, shed = list.filter((s) => s.cls === 'shed').length;
    const statuses = {}; for (const s of list) statuses[s.status ?? s.err ?? 'x'] = (statuses[s.status ?? s.err ?? 'x'] || 0) + 1;
    return { n, p50: pct(ms, 0.5), p95: pct(ms, 0.95), p99: pct(ms, 0.99), max: ms.at(-1) ?? null,
      errorRate: n ? errors / n : 0, limitedRate: n ? limited / n : 0, shed, statuses };
  };
  const out = { all: row(samples) };
  for (const [k, v] of Object.entries(by)) out[k] = row(v);
  return out;
}
/** The abort rule: a stage past 2% errors (5xx, network, timeout or 429) after 50 samples. */
export function shouldAbort(samples) {
  const turns = samples.filter((s) => s.cls !== 'shed');   // a shed attempt is retried: the visitor sees no error, and it is not a turn
  if (turns.length < ABORT_MIN_SAMPLES) return false;
  const bad = turns.filter((s) => s.cls !== 'ok').length;
  return bad / turns.length > ABORT_ERROR_RATE;
}
export function pickWeighted(list, rnd = Math.random) {
  const total = list.reduce((a, x) => a + x.w, 0);
  let r = rnd() * total;
  for (const x of list) { r -= x.w; if (r < 0) return x; }
  return list.at(-1);
}
export const vuAddress = (vu) => `198.18.${(vu >> 8) & 255}.${vu & 255}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const between = ([lo, hi]) => lo + Math.random() * (hi - lo);

async function timed(name, url, init, samples, timeoutMs = 30000) {
  const t0 = performance.now();
  let status = null, err = null, headers = null, text = '';
  try {
    const r = await fetch(url, { ...init, redirect: 'manual', signal: AbortSignal.timeout(timeoutMs) });
    status = r.status; headers = r.headers;
    text = await r.text();                       // the whole body: a page is not served until its bytes are
  } catch (e) { err = String(e?.name || e?.cause?.code || 'fetch_failed'); }
  const ms = performance.now() - t0;
  const s = { name, ms: Math.round(ms), status, err, cls: classify(status, err), t: Date.now(),
    cache: headers?.get('x-vercel-cache') ?? null, region: headers?.get('x-sb-edge-region') ?? null };
  samples.push(s);
  return { ...s, text };
}

function readBody(read, lang) {
  if (read.action === 'trade_needs') return { action: 'trade_needs', category: read.category, lang };
  return { action: read.action };
}

async function websiteVU(vu, mix, ctx) {
  const fnHeaders = { 'content-type': 'application/json', apikey: ctx.anon, authorization: 'Bearer ' + ctx.anon };
  while (!ctx.stop()) {
    const page = pickWeighted(PAGES);
    const slugs = Object.keys(SERVICES);
    const slug = slugs[Math.floor(Math.random() * slugs.length)];
    const path = page.path.replace(':slug', slug);
    const lang = path.startsWith('/ar') ? 'ar' : 'en';
    if (ctx.mixName === 'website') await timed('page ' + page.path, SITE + path, { headers: { 'user-agent': 'qd-load-driver/1 (it_engineer)' } }, ctx.samples);
    for (const read of page.reads) {
      if (ctx.stop()) break;
      const r = { ...read, category: SERVICES[slug] };
      await timed('public_site ' + read.action, SUPA + '/functions/v1/public_site' + FN_QS,
        { method: 'POST', headers: fnHeaders, body: JSON.stringify(readBody(r, lang)) }, ctx.samples);
    }
    await sleep(between(mix.think));
  }
}

async function chatVU(vu, mix, ctx) {
  const headers = { 'content-type': 'application/json', apikey: ctx.anon, authorization: 'Bearer ' + ctx.anon,
    'x-forwarded-for': vuAddress(vu), 'x-qd-e2e-run': ctx.env.QD_LOAD_RUN_TAG, 'x-qd-e2e-secret': ctx.env.QD_LOAD_RUN_SECRET };
  while (!ctx.stop()) {
    const conv = randomUUID();
    ctx.convs?.push(conv);
    const history = [];
    for (let t = 0; t < mix.turns && !ctx.stop(); t++) {
      const q = CHAT_QUESTIONS[(vu + t) % CHAT_QUESTIONS.length];
      history.push({ role: 'user', content: q });
      // THE WIDGET'S BUSY RETRY (src/lib/busyRetry.ts, 11 Nov 2026): a full worker answers { busy: true } at once and the widget
      // sends the message again after retry_after_ms. Each shed attempt is its own 'site_assistant shed' sample (class 'shed',
      // never an error and never in the abort rule, because the visitor saw no error); the turn is the attempt that answered.
      // A turn still busy after BUSY_TRIES is an error, as the widget then shows its error line.
      let r;
      for (let attempt = 0; ; attempt++) {
        r = await timed('site_assistant turn', SUPA + '/functions/v1/site_assistant' + FN_QS,
          { method: 'POST', headers, body: JSON.stringify({ message: q, conv, history, path: '/', lang: /[؀-ۿ]/.test(q) ? 'ar' : 'en' }) },
          ctx.samples, 60000);
        const busy = r.cls === 'ok' && /"busy":true/.test(r.text);
        if (!busy) break;
        const wait = busyRetryDelay(JSON.parse(r.text), attempt);
        const last = ctx.samples.at(-1);
        if (wait === null) { last.cls = 'error'; last.err = 'busy after ' + (attempt + 1) + ' tries'; break; }
        last.name = 'site_assistant shed'; last.cls = 'shed';
        await sleep(wait);
      }
      let reply = ''; try { reply = JSON.parse(r.text)?.reply ?? ''; } catch { reply = ''; }
      if (r.cls === 'ok' && /rate_limited/.test(r.text)) ctx.samples.at(-1).cls = 'limited';
      history.push({ role: 'assistant', content: String(reply).slice(0, 400) });
      await sleep(between(mix.think));
    }
  }
}

async function embedVU(vu, mix, ctx) {
  let k = 0;
  while (!ctx.stop()) {
    const text = CHAT_QUESTIONS[(vu + k++) % CHAT_QUESTIONS.length] + ' (' + vu + ')';
    const action = ctx.env.QD_LOAD_EMBED_ACTION === 'query' ? 'query' : 'gte';   // 'query' = the multilingual model the chat's recall uses
    await timed('embed_ml ' + action, SUPA + '/functions/v1/embed_ml' + FN_QS, { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ __secret: ctx.env.QD_LOAD_EMBED_SECRET, fn: 'load_probe', action, text }) }, ctx.samples, 15000);
    await sleep(between(mix.think));
  }
}

/** Management-API SQL, read-only: the chat mix's spend guard. */
export async function mgmtQuery(env, sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${env.SUPABASE_PROJECT_REF || 'htdblwldjkcgjvmqkbeh'}/database/query`, {
    method: 'POST', headers: { authorization: 'Bearer ' + env.SUPABASE_ACCESS_TOKEN, 'content-type': 'application/json' },
    body: JSON.stringify({ query: sql, read_only: true }), signal: AbortSignal.timeout(30000),
  });
  if (!r.ok) throw new Error('management query HTTP ' + r.status + ' ' + (await r.text()).slice(0, 200));
  return r.json();
}
/** The spend guard's verdict on ai_cost_log rows for the run tag. Pure, so the test can pin it. */
export function spendVerdict(rows) {
  const cost = rows.reduce((a, r) => a + Number(r.cost_aed || 0) + Number(r.cost_usd_reported || 0), 0);
  const paidModels = rows.filter((r) => !['load_stub', 'none'].includes(String(r.model_used))).map((r) => r.model_used);
  return { ok: cost === 0 && paidModels.length === 0, cost, paidModels, rows: rows.length };
}
/**
 * THE PREFLIGHT: is the DEPLOYED gateway the one with the load stub? One call to ai_gateway as fn 'load_probe' under the
 * run's proof. A gateway WITHOUT the stub treats 'load_probe' as our own work outside a paid window and answers the
 * no-cost fixture_no_spend 503 (spend_guards.ownWorkByName); one WITH it answers outcome 'load_stub'. Either way no
 * provider is called, and the chat mix runs only on the second answer (preflightVerdict).
 */
export function preflightVerdict(status, json) {
  if (status === 200 && json?.outcome === 'load_stub' && json?.cost_usd === 0) return { ok: true };
  return { ok: false, why: 'the deployed ai_gateway did not answer with the load stub (HTTP ' + status + ', outcome ' + (json?.outcome ?? json?.error ?? 'none') + '): deploy ai_gateway and site_assistant first' };
}
async function preflight(env, anon) {
  const r = await fetch(SUPA + '/functions/v1/ai_gateway' + FN_QS, { method: 'POST',
    headers: { 'content-type': 'application/json', apikey: anon, authorization: 'Bearer ' + anon, 'x-qd-e2e-run': env.QD_LOAD_RUN_TAG, 'x-qd-e2e-secret': env.QD_LOAD_RUN_SECRET },
    body: JSON.stringify({ __secret: env.QD_LOAD_GATEWAY_SECRET, fn: 'load_probe', task_class: 'conversation_reply', sys: 'ZZ DEMO load preflight', input: 'ZZ DEMO preflight', max: 50, client_timeout_ms: 30000 }),
    signal: AbortSignal.timeout(60000) });
  return preflightVerdict(r.status, await r.json().catch(() => null));
}
// WHAT THE GUARD READS (measured 11 Nov 2026). ai_cost_log.e2e_run_tag is NULL on every load-run row: the stamping
// trigger (fn_ai_cost_log_e2e_run_tag) keeps a tag only while fn_e2e_run_tag_open says so, and that needs models_allowed
// = true, which a load window never is. So the guard reads a SUPERSET instead: every row since the run started that the
// stub wrote ('LOAD TEST run <tag>' in model_selected_because) OR that any site_assistant or load_probe call wrote. Any
// paid model or any cost in that set aborts, whoever caused it; "0 AED" is therefore a bound on the run, not a guess.
async function spendGuard(env, sinceIso) {
  const tag = String(env.QD_LOAD_RUN_TAG).replace(/[^a-z0-9]/g, '');
  const since = new Date(sinceIso).toISOString();
  const rows = await mgmtQuery(env, `select model_used, cost_aed, cost_usd_reported from public.ai_cost_log where occurred_at >= '${since}'::timestamptz and (model_selected_because like '%LOAD TEST run ${tag}%' or fn in ('site_assistant','load_probe'))`);
  return spendVerdict(rows);
}

export async function run({ mixName, stages, stageSeconds, env, out }) {
  const mix = MIXES[mixName];
  const anon = env.QD_LOAD_ANON_KEY;
  if (!anon) throw new Refused('QD_LOAD_ANON_KEY (the site\'s publishable key) is not set');
  // The chat mix's two gates live HERE, not in main(), so every caller of run() (chat_load_run.mjs) passes them.
  if (mix.chat) {
    assertRunnable(mixName, env, ['--run']);
    const t0 = new Date().toISOString();
    const pre = await spendGuard(env, new Date(Date.now() - 3600_000).toISOString());
    if (!pre.ok) throw new Refused('the chat path already shows spend in the last hour: ' + JSON.stringify(pre));
    const pf = await preflight(env, anon);
    if (!pf.ok) throw new Refused(pf.why);
    const after = await spendGuard(env, t0);
    if (!after.ok) throw new Refused('the preflight itself spent: ' + JSON.stringify(after));
  }
  const result = { mix: mixName, startedAt: new Date().toISOString(), stages: [], aborted: null };
  for (const vus of stages) {
    const samples = [];
    const t0 = Date.now();
    let aborted = false;
    const ctx = { samples, anon, env, mixName, convs: result.convs ??= [], stop: () => aborted || Date.now() - t0 > stageSeconds * 1000 };
    const watcher = setInterval(() => { if (shouldAbort(samples)) aborted = true; }, 500);
    const body = mix.chat ? chatVU : mix.embed ? embedVU : websiteVU;
    // ramp inside the stage over 5 s, so 200 sockets do not open in the same millisecond
    await Promise.all(Array.from({ length: vus }, (_, i) => sleep((i / vus) * 5000).then(() => body(i, mix, ctx))));
    clearInterval(watcher);
    const s = { vus, seconds: Math.round((Date.now() - t0) / 1000), rps: +(samples.length / ((Date.now() - t0) / 1000)).toFixed(1), summary: summarise(samples),
      cache: samples.reduce((a, x) => { if (x.cache) a[x.cache] = (a[x.cache] || 0) + 1; return a; }, {}),
      regions: samples.reduce((a, x) => { if (x.region) a[x.region] = (a[x.region] || 0) + 1; return a; }, {}) };
    if (mix.chat) s.spend = await spendGuard(env, result.startedAt);
    result.stages.push(s);
    console.log(`stage ${vus} VUs: n=${s.summary.all.n} rps=${s.rps} p50=${s.summary.all.p50} p95=${s.summary.all.p95} p99=${s.summary.all.p99} err=${(s.summary.all.errorRate * 100).toFixed(2)}% limited=${(s.summary.all.limitedRate * 100).toFixed(2)}%${s.spend ? ' spend=' + JSON.stringify(s.spend) : ''}`);
    if (out) writeFileSync(out, JSON.stringify(result, null, 1));
    if (aborted || shouldAbort(samples)) { result.aborted = `stage ${vus}: error rate over ${ABORT_ERROR_RATE * 100}%`; break; }
    if (s.spend && !s.spend.ok) { result.aborted = `stage ${vus}: the run spent (${JSON.stringify(s.spend)})`; break; }
    await sleep(10000);                           // let the platform settle between stages
  }
  result.endedAt = new Date().toISOString();
  if (out) writeFileSync(out, JSON.stringify(result, null, 1));
  return result;
}

async function main(argv, env) {
  const arg = (k, d) => (argv.find((a) => a.startsWith(`--${k}=`)) || '').split('=').slice(1).join('=') || d;
  const mixName = arg('mix', 'website');
  const { dry } = assertRunnable(mixName, env, argv);
  const stages = arg('stages', '10,50,100,200').split(',').map(Number).filter((n) => n > 0 && n <= 500);
  const stageSeconds = Number(arg('stage-seconds', '40'));
  console.log(`load driver — mix ${mixName}, stages ${stages.join(' -> ')} VUs, ${stageSeconds}s each, think ${MIXES[mixName].think.join('-')} ms`);
  if (dry) { console.log('dry run — nothing sent. Add --run.'); return 0; }
  const r = await run({ mixName, stages, stageSeconds, env, out: arg('out', '') });
  if (r.aborted) console.log('ABORTED: ' + r.aborted);
  return r.aborted ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2), process.env).then((c) => process.exit(c), (e) => { console.error(e.message); process.exit(2); });
}
