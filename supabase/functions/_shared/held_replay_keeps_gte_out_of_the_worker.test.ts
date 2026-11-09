// THE HELD REPLAY NEVER RUNS GTE-SMALL IN ITS OWN WORKER (it_engineer, 27 Oct 2026).
//
// Replays the batch that killed production: four seat revisions for the CEO (marketing's November month plan among them)
// claimed in one tick, each planned in five English steps on the multilingual space. On production the detached itlater
// worker ran gte-small in-process for every step and the question (24 runs for the four rows) and the edge runtime
// stopped it at its 2 s CPU cap (shutdown reason CPUTime, 2,091-2,160 ms, 27 Oct 01:17:52, 01:47:34, 02:17:25 UTC)
// before fn_reason_held_resolve could record anything. After three claims the sweep closed each row 'failed' with no
// result, and the plan sat in ceo_reviewing. See the header above defaultDeps in think.ts for the measurements.
//
// The edge runtime is stubbed here: Supabase.ai.Session counts every in-process run. The heartbeat's deps must make
// none. Break it once to see: give heartbeatDeps the in-worker session (drop `{ gte: 'remote' }`) and the count is 24.
//   deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/_shared/held_replay_keeps_gte_out_of_the_worker.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { heartbeatDeps, replayHeld, type LlmReply, type Phase, type ThinkDeps } from './think.ts';

const J = (x: unknown) => JSON.stringify(x);

// The edge runtime's in-process gte-small, counted.
const inWorker = { sessions: 0, runs: 0 };
// deno-lint-ignore no-explicit-any
(globalThis as any).Supabase = { ai: { Session: class {
  constructor() { inWorker.sessions++; }
  run() { inWorker.runs++; return Promise.resolve(Array.from({ length: 384 }, () => 0.01)); }
} } };

// Four seat revisions, the shape fn_seat_revises_for_the_ceo files (surface <seat>.ceo_revision, a two-option decision).
const SEATS = ['sales_engineer', 'marketing', 'marketing', 'customer_support'];
const rows = SEATS.map((seat, i) => ({
  id: 9100 + i, seat, surface: seat + '.ceo_revision', subject: { handoff_id: 1000 + i }, created_at: new Date().toISOString(),
  request: {
    seat, surface: seat + '.ceo_revision', audience: 'internal',
    question: 'The CEO sent your submission back (round 2). Read each of the CEO\'s reasons. Produce a revised version that answers every one of them.',
    decision: { name: 'revision', options: [{ id: 'revised', meaning: 'the submission is revised' }, { id: 'defended', meaning: 'the submission stands' }] },
    context: { audience: 'internal', case: { path: 'marketing_month_plan', round: 2, ceo_reasons: 'the twelve ideas are word for word the round-1 plan' } },
  },
}));

// The plan the model wrote for 28986: five English steps, every one needing knowledge.
const PLAN = J({ steps: ['Verify pricing and promotional claims.', 'Define attribution and fallback wording.', 'Rebalance the actual idea list around supply.',
  'Confirm required compliance lines.', 'Check the resubmission against every CEO reason.'].map((goal, i) => ({ id: 's' + (i + 1), goal, query: goal, needs_knowledge: true })), facts: [] });
const DRAFT = J({ answer: 'Revised: every CEO reason is answered in the list.', decision: { choice: 'revised' }, cited: [], confidence: 0.7,
  revision: 'the revised plan', answers: 'each reason answered' });

function admin() {
  const rpcs: string[] = [];
  return {
    rpcs,
    rpc: (fn: string) => {
      rpcs.push(fn);
      if (fn === 'fn_kernel_paid_provider_gate') return Promise.resolve({ data: { allowed: true, rule: 'open' }, error: null });
      if (fn === 'fn_reason_held_due') return Promise.resolve({ data: rpcs.filter((f) => f === 'fn_reason_held_due').length === 1 ? rows : [], error: null });
      if (fn === 'fn_ml_read_space') return Promise.resolve({ data: 'ml', error: null });
      if (fn.startsWith('fn_reason_retrieve')) return Promise.resolve({ data: [{ source: 'kb_chunks', id: 1, title: 'pack', excerpt: 'a fact', citation: null, similarity: 0.9, trust: 'reviewed' }], error: null });
      if (fn.startsWith('fn_case_recall')) return Promise.resolve({ data: { cases: [] }, error: null });
      if (fn === 'fn_reason_held_resolve') return Promise.resolve({ data: { status: 'applied' }, error: null });
      return Promise.resolve({ data: 1, error: null });
    },
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve({ data: { value: 'test-credential' }, error: null }) }) }) }),
  };
}

// Only the model is replaced: everything else is the deps the heartbeat really runs on.
const model: ThinkDeps['llm'] = (phase: Phase) => Promise.resolve({ content: phase === 'decompose' ? PLAN : phase === 'verify' ? J({ verdict: 'agree', problems: [] }) : DRAFT, model: 'openai/gpt-6-luna-pro' } as LlmReply);

// Out of the test's sandbox (no --allow-net) the remote embedder answers null; stub fetch so a run that does have
// network access never leaves the process either.
const realFetch = globalThis.fetch;
const remote: string[] = [];
globalThis.fetch = ((u: string | URL | Request) => {
  remote.push(String(u));
  return Promise.resolve(new Response(J({ embedding: J(Array.from({ length: 384 }, () => 0.02)), space: 'gte' }), { status: 200 }));
}) as typeof fetch;

Deno.test('four seat revisions replayed in one tick run gte-small in embed_ml, never in the replay\'s own worker', async () => {
  try {
    const a = admin();
    inWorker.sessions = 0; inWorker.runs = 0;
    const out = await replayHeld(a, 5, { ...heartbeatDeps(a), llm: model }) as { replayed: number; rows: { status: string }[] };
    assertEquals(out.replayed, 4);
    assert(out.rows.every((r) => r.status === 'answered'), 'each revision is reasoned and resolved: ' + J(out.rows));
    assertEquals(a.rpcs.filter((f) => f === 'fn_reason_held_resolve').length, 4, 'every claimed row reaches fn_reason_held_resolve');
    assertEquals(inWorker.runs, 0, `the replay ran gte-small ${inWorker.runs} times inside its own worker; on 27 Oct 24 such runs in one tick hit the 2 s CPU cap`);
    assertEquals(inWorker.sessions, 0, 'the replay never loads the gte-small session in its own worker');
  } finally { globalThis.fetch = realFetch; }
});

Deno.test('the heartbeat\'s embedder asks embed_ml for gte-small, the same 384-dimension space', async () => {
  const a = admin();
  inWorker.runs = 0;
  await heartbeatDeps(a).embed('Rebalance the actual idea list around supply.', 'gte');
  await heartbeatDeps(a).embed('a research finding with no space named');
  assertEquals(inWorker.runs, 0);
});

// EVERY STEP OF THE HEARTBEAT HANDS ITS DEPS OVER AS heartbeatDeps (it_engineer, 27 Oct 2026).
// #1685 grepped resilience_ping for the literal defaultDeps call, and an independent review found what that misses: a deps-taking
// call given `undefined` (or nothing) falls back to whatever deps its callee defaults to. learningGroupTick and learningDistilTick
// called distilLessons that way, and distilLessons defaulted to defaultDeps - gte-small in this worker for up to 8 findings a tick.
// So the guard reads the shape instead of one spelling. It finds every exported _shared function that takes a ThinkDeps
// parameter, follows resilience_ping's imports (aliases and dynamic imports too), and requires that each such call hands
// heartbeatDeps(admin) at that parameter. A call that passes nothing, `undefined` or any other deps is named with its line.
// Break it once to see: put `undefined` back in learningGroupTick and this names line and callee.
type Taker = { file: string; name: string; index: number };
const SHARED = new URL('./', import.meta.url);

/** Arguments (or parameters) of the parenthesised list opening at `open`, split at depth 0; strings are skipped. */
function argsAt(src: string, open: number): { args: string[]; end: number } {
  const args: string[] = []; let depth = 0; let cur = ''; let q: string | null = null;
  for (let i = open; i < src.length; i++) {
    const c = src[i];
    if (q) { cur += c; if (c === '\\') { cur += src[++i] ?? ''; continue; } if (c === q) q = null; continue; }
    if (c === '\'' || c === '"' || c === '`') { q = c; cur += c; continue; }
    if (c === '(' || c === '{' || c === '[' || (c === '<' && depth > 0)) { if (depth++ > 0) cur += c; continue; }
    if (c === ')' || c === '}' || c === ']' || (c === '>' && depth > 1 && src[i - 1] !== '=')) {
      if (--depth === 0) { if (cur.trim()) args.push(cur.trim()); return { args, end: i }; }
      cur += c; continue;
    }
    if (c === ',' && depth === 1) { args.push(cur.trim()); cur = ''; continue; }
    cur += c;
  }
  return { args, end: src.length };
}
/** The source with // comments removed (not inside strings), so prose never counts as a call. */
function code(src: string): string {
  return src.split('\n').map((l) => {
    let q: string | null = null;
    for (let i = 0; i < l.length; i++) {
      const c = l[i];
      if (q) { if (c === '\\') i++; else if (c === q) q = null; continue; }
      if (c === '\'' || c === '"' || c === '`') q = c;
      else if (c === '/' && l[i + 1] === '/') return l.slice(0, i);
    }
    return l;
  }).join('\n');
}
async function depsTakers(): Promise<Map<string, Taker>> {
  const out = new Map<string, Taker>();
  const walk = async (dir: URL, rel: string) => {
    for await (const e of Deno.readDir(dir)) {
      if (e.isDirectory) { await walk(new URL(e.name + '/', dir), rel + e.name + '/'); continue; }
      if (!e.name.endsWith('.ts') || e.name.endsWith('.test.ts')) continue;
      const src = code(await Deno.readTextFile(new URL(e.name, dir)));
      for (const m of src.matchAll(/export\s+(?:async\s+)?function\s+(\w+)\s*(?:<[^(]*>)?\s*\(/g)) {
        const { args } = argsAt(src, m.index! + m[0].length - 1);
        const index = args.findIndex((p) => /^\w+\??\s*:\s*ThinkDeps\b/.test(p));
        if (index >= 0) out.set(rel + e.name + '::' + m[1], { file: rel + e.name, name: m[1], index });
      }
    }
  };
  await walk(SHARED, '');
  return out;
}
/** local name -> the _shared file and exported name it is bound to, from static and dynamic imports. */
function importsOf(src: string): Map<string, { file: string; name: string }> {
  const out = new Map<string, { file: string; name: string }>();
  const bind = (list: string, file: string, sep: RegExp) => {
    for (const part of list.split(',').map((x) => x.trim()).filter(Boolean)) {
      const [orig, local] = part.replace(/^type\s+/, '').split(sep).map((x) => x.trim());
      out.set(local || orig, { file, name: orig });
    }
  };
  // (?:\.\.\/)+ : the ticks moved into resilience_ping/ticks/ on 9 Nov 2026 import from ../../_shared/.
  for (const m of src.matchAll(/import\s*\{([^}]*)\}\s*from\s*'(?:\.\.\/)+_shared\/([^']+)'/g)) bind(m[1], m[2], /\s+as\s+/);
  for (const m of src.matchAll(/const\s*\{([^}]*)\}\s*=\s*await\s+import\(\s*'(?:\.\.\/)+_shared\/([^']+)'\s*\)/g)) bind(m[1], m[2], /\s*:\s*/);
  return out;
}

Deno.test('resilience_ping hands heartbeatDeps to every deps-taking call: never defaultDeps, never undefined, never left to a default', async () => {
  // The whole function, not index.ts alone: on 9 Nov 2026 its ticks moved into resilience_ping/ticks/*.ts and
  // shared.ts (a pure move). Every runtime .ts file in the folder, index.ts first, tests left out.
  const root = new URL('../resilience_ping/', import.meta.url);
  const files: string[] = [];
  const walkFn = async (dir: URL, rel: string) => {
    for await (const e of Deno.readDir(dir)) {
      if (e.isDirectory) await walkFn(new URL(e.name + '/', dir), rel + e.name + '/');
      else if (e.name.endsWith('.ts') && !/\.(test|check)\.ts$/.test(e.name)) files.push(rel + e.name);
    }
  };
  await walkFn(root, '');
  files.sort((a, b) => (a === 'index.ts' ? -1 : b === 'index.ts' ? 1 : a.localeCompare(b)));
  const raw = (await Promise.all(files.map((f) => Deno.readTextFile(new URL(f, root))))).join('\n');
  const src = code(raw);
  const lineOf = (i: number) => src.slice(0, i).split('\n').length;
  const inWorkerAt = [...src.matchAll(/\bdefaultDeps\s*\(/g)].map((m) => lineOf(m.index!));
  assertEquals(inWorkerAt, [], `resilience_ping calls defaultDeps (gte-small in its own worker) at line(s) ${inWorkerAt.join(', ')}; use heartbeatDeps(admin)`);
  const takers = await depsTakers();
  const bound = importsOf(src);
  const calls: string[] = []; const wrong: string[] = [];
  for (const [local, at] of bound) {
    const t = takers.get(at.file + '::' + at.name);
    if (!t) continue;
    for (const m of src.matchAll(new RegExp(`(?<![\\w.])${local}\\s*\\(`, 'g'))) {
      const { args } = argsAt(src, m.index! + m[0].length - 1);
      const given = args[t.index];
      calls.push(local);
      if (!given || !/^heartbeatDeps\(admin\)$/.test(given)) {
        wrong.push(`line ${lineOf(m.index!)}: ${local}(…) parameter ${t.index + 1} is ${given ?? 'not passed'} (${t.file} ${t.name} falls back to its own deps)`);
      }
    }
  }
  assertEquals(wrong, [], 'each deps-taking call in resilience_ping must pass heartbeatDeps(admin):\n' + wrong.join('\n'));
  // The scan must SEE the call sites it guards, or it passes over nothing.
  for (const must of ['replayHeld', 'drainRoutineJudgements', 'distilLessons', 'liveVoiceIO']) assert(calls.includes(must), `the guard found no ${must} call: ${J(calls)}`);
  assertEquals(calls.filter((c) => c === 'distilLessons').length, 2, 'the hourly group and the weekly distil both call distilLessons');
});

// PUBLIC_SITE TOO (it_engineer, 2 Nov 2026): 57 visitor POSTs in 24 h died at the 2 s CPU cap with gte-small in-process
// (a cold price_guidance embeds the question and 8 exemplars). Every deps it builds places gte-small in embed_ml.
Deno.test('public_site builds its think() deps with gte-small in embed_ml, never in the visitor\'s worker', async () => {
  const src = code(await Deno.readTextFile(new URL('../public_site/index.ts', import.meta.url)));
  const calls = [...src.matchAll(/\bdefaultDeps\s*\(([^)]*)\)/g)].map((m) => m[1]);
  assert(calls.length > 0, 'the guard found no defaultDeps call in public_site');
  const inWorker = calls.filter((a) => !/gte\s*:\s*'remote'/.test(a));
  assertEquals(inWorker, [], 'public_site builds deps without { gte: \'remote\' }: ' + J(inWorker));
});

// THE DEFAULT ITSELF: distilLessons with no deps (its only caller is the heartbeat) embeds through embed_ml.
Deno.test('distilLessons without deps embeds each finding outside the worker', async () => {
  const { distilLessons } = await import('./learning_loop.ts');
  const a = admin();
  const rpc = a.rpc;
  // fn_lesson_unembedded is asked for 8 at most: one learning tick makes at most 8 embed_ml calls.
  const findings = Array.from({ length: 8 }, (_, i) => ({ id: i + 1, finding: 'lesson finding ' + (i + 1) }));
  const stub = { ...a, rpc: (fn: string) => fn === 'fn_lesson_unembedded' ? Promise.resolve({ data: findings, error: null })
    : fn === 'fn_lesson_clusters' ? Promise.resolve({ data: [], error: null }) : rpc(fn) };
  inWorker.runs = 0; inWorker.sessions = 0;
  const out = await distilLessons(stub, undefined, 2, { reason: false }) as { ok: boolean };
  assert(out.ok, J(out));
  assertEquals(inWorker.runs, 0, `distilLessons' own default ran gte-small ${inWorker.runs} times in the heartbeat's worker`);
  // ONE AT A TIME (27 Oct 2026, 20:30Z): a concurrent burst of embed_ml calls from the replay, with ai_gateway calls, met a
  // gateway 503 with no worker and thrown fetches. The learning tick's embeds stay sequential: never more than one in flight.
  let inFlight = 0, peak = 0, asked = 0;
  const embed = async () => { asked++; peak = Math.max(peak, ++inFlight); await new Promise((r) => setTimeout(r, 2)); inFlight--; return Array.from({ length: 384 }, () => 0.03); };
  const seq = await distilLessons(stub, { ...heartbeatDeps(stub), embed }, 2, { reason: false }) as { embedded: number };
  assertEquals(asked, 8, 'one embed_ml call per unembedded finding, 8 at most a tick');
  assertEquals(seq.embedded, 8);
  assertEquals(peak, 1, `the learning tick had ${peak} embed_ml calls in flight at once`);
});

// THE HELD REPLAY'S SOCIAL COMMENT (reasoned_delivery.ts socialCommentClassified -> marketing_social_store.ts write). The live
// read space is ml (fn_ml_read_space, read 27 Oct 2026), but the recall fell back to in-process gte-small whenever the multilingual
// call came back empty. Here the remote embedder answers nothing (no network in the test), which is exactly that fallback.
Deno.test('the replayed social comment recalls without gte-small in the worker, even when the multilingual call fails', async () => {
  const { adminStore } = await import('./marketing_social_store.ts');
  const a = admin();
  inWorker.runs = 0; inWorker.sessions = 0;
  const deps = { ...heartbeatDeps(a), llm: model };
  const store = adminStore(a, (() => Promise.reject(new Error('no network'))) as never, () => Promise.resolve(null), undefined, deps);
  const ev = { platform: 'instagram', accountId: 'acc', commentId: 'c1', authorId: 'u1', handle: null, text: 'How do I post a request for kitchen cabinets?', at: new Date(), threadId: 'c1' };
  await store.write(ev as never, 'en', 'question', []).catch(() => '');
  assert(a.rpcs.includes('fn_ml_read_space') || a.rpcs.includes('fn_judgement_record'), 'the recall ran: ' + J(a.rpcs));
  assertEquals(inWorker.runs, 0, `the replayed comment's recall ran gte-small ${inWorker.runs} times in the replay's worker`);
  const delivery = await Deno.readTextFile(new URL('./reasoned_delivery.ts', import.meta.url));
  assert(/adminStore\([^;]*defaultDeps\(admin, 'marketing', \{ gte: 'remote' \}\)\)/.test(code(delivery)), 'the held replay hands the comment store deps with gte-small in embed_ml');
});
