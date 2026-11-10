// think/deps.ts — the live dependencies of think(), and a step under a caller's clock (moved whole from _shared/think.ts).
import { HOLD_PROBE_MODEL } from '../llm_hold.ts';
import type { Admin, EmbedSpace, Phase, ThinkDeps } from './types.ts';
import { readPage, webSearch } from './research.ts';


// ── the live dependencies ────────────────────────────────────────────────────────────────────────
/** A step under a CALLER'S clock (sales_engineer, 27 Oct 2026; inquiry_intake/turn_clock.ts measured why): the same deps,
 *  with every model call cut at `deadline` (epoch ms). None starts with under `minMs` left and none may run past it. A
 *  call that cannot run returns no content with error 'turn_deadline', which think() treats as a model that did not
 *  answer and never retries (SLOW_MODEL_ERROR): the decision is held, nothing is chosen or filled. A per-call timeout is
 *  not a turn budget; this is. prevented by: _shared/think_deadline.test.ts */
export const MIN_STEP_MS = 5_000;
// THE ANSWER KEEPS ITS OWN TIME (it_engineer, 10 Nov 2026). Measured on production (llm_attempt, 2-10 Nov): the held
// replay's answer step (internal_judgement, gpt-6-luna-pro, fn resilience_ping) failed 119 of 317 times. Every failed
// call ended 84-88 s (p10-p90) after the row's plan call started - the 90 s REPLAY_BUDGET_MS - because the plan (~20 s)
// and the sequential retrieval of 5-6 plan steps (two remote embeds and one RPC each: 43 s median on the failed rows,
// 18.5 s on the answered ones) spent the budget first, and the answer then started with about 13-47 s left (p10-p90) while
// an answered call takes p50 22.5 s, p90 31.7 s, p95 34.7 s. The gateway cut it at its wall, mid-reasoning, and the
// row was held with nothing to show for a paid call. With `answerReserveMs`, the work BEFORE the answer (the plan,
// research reads, embeddings, web search and page reads) must end that long before `deadline`; past that line it is
// not started (a planner that does not run answers from the one-step plan, a step that is not embedded is recorded
// 'turn_deadline' and reads as thin), so the answer always starts with at least the reserve. 0 = no reserve, the
// behaviour every other caller (the intake turn, the routine judgements, reasoned decisions) keeps.
// prevented by: _shared/think_answer_reserve.test.ts
const BEFORE_THE_ANSWER: ReadonlySet<Phase> = new Set<Phase>(['decompose', 'research']);
export function withDeadline(deps: ThinkDeps, deadline: number, minMs = MIN_STEP_MS, now: () => number = Date.now, answerReserveMs = 0): ThinkDeps {
  const line = deadline - Math.max(0, answerReserveMs);
  const pastLine = () => answerReserveMs > 0 && now() >= line;
  const skipped = new Set<string>();
  const why = () => 'turn_deadline: past the ' + answerReserveMs + ' ms kept for the answer';
  return {
    ...deps,
    llm: async (phase, system, input, o) => {
      const end = BEFORE_THE_ANSWER.has(phase) ? line : deadline;
      const left = end - now();
      if (left < minMs) return { content: null, model: null, error: 'turn_deadline: ' + Math.max(0, left) + ' ms left' + (end === deadline ? '' : ' before the ' + answerReserveMs + ' ms kept for the answer') };
      return await deps.llm(phase, system, input, { ...o, timeoutMs: Math.min(o.timeoutMs ?? left, left) });
    },
    ...(answerReserveMs > 0 ? {
      embed: (t: string, sp?: EmbedSpace) => { if (pastLine()) { skipped.add((sp ?? 'gte') + '\u0001' + t); return Promise.resolve(null); } return deps.embed(t, sp); },
      embedFailure: (t: string, sp: EmbedSpace) => skipped.has(sp + '\u0001' + t) ? why() : (deps.embedFailure?.(t, sp) ?? null),
      ...(deps.search ? { search: (q: string) => pastLine() ? Promise.resolve([]) : deps.search!(q) } : {}),
      ...(deps.read ? { read: (u: string) => pastLine() ? Promise.resolve(null) : deps.read!(u) } : {}),
    } : {}),
  };
}

// THE HELD REPLAY NEVER RUNS GTE-SMALL IN ITS OWN WORKER (it_engineer, 27 Oct 2026). Measured on production: every
// detached itlater run that replayed three or more held questions was killed by the edge runtime at its 2 s CPU cap
// (function_logs "CPU Time exceeded", shutdown reason CPUTime, 2,000-2,160 ms; 10 runs on 26-27 Oct, e.g. 01:17:52,
// 01:47:34 and 02:17:25 UTC), while the same run with no held row used 49-194 ms. The worker died with the model's
// answer in flight, fn_reason_held_resolve never ran, the claim had already counted a try, and after three claims the
// sweep closed the row 'failed' with no result: marketing.ceo_revision 28986 (the November month plan) and its three
// siblings 28985/28987/28988, and the it_engineer.postmortem rows the same day. The cause is what each row does in the
// worker: on the multilingual space every English plan step and the question are ALSO embedded with gte-small for the
// fused ranking, and defaultDeps ran that in-process. Replayed locally with the four real requests, think() spends
// 13 ms of JavaScript CPU for all four rows and asks for 24 gte-small runs; one embedding in embed_ml's own worker costs
// a median 324 ms CPU (p90 415 ms, 21,140 runs on 27 Oct). So `gte: 'remote'` sends gte-small to embed_ml - the same
// model, the same 384-dimension space, its own worker per call (meaning_embed.ts made the same move on 29 Sep) - and
// the heartbeat's deps (heartbeatDeps) use it. Other callers keep the in-worker session: their latency, not a batch.
// prevented by: _shared/held_replay_keeps_gte_out_of_the_worker.test.ts
export type GtePlacement = 'worker' | 'remote';
// cacheTtlMin (public_site, 3 Nov 2026): measured 809 calls on 73 distinct prompts in 7 days with 0 cache hits, because
// every think() call opted out of the gateway cache. A caller whose identical question gets an identical answer passes a
// TTL; the memo replays only the byte-identical prompt (cacheExact), never a similar one.
export function defaultDeps(admin: Admin, fn: string, o: { gte?: GtePlacement; embedTimeoutMs?: number; cacheTtlMin?: number } = {}): ThinkDeps {
  // 8 s covers embed_ml's cold start (1.2-2.6 s); a visitor waiting on a page (public_site) gets a shorter clock, and a
  // timeout is the same null an embed failure is: the caller goes on without the vector (it_engineer, review of #1786).
  const embedMs = o.embedTimeoutMs ?? 8000;
  // why each remote embed returned null, per space and text, for the step detail (embedFailure); cleared on success
  const embedFails = new Map<string, string>();
  const noteFail = (sp: EmbedSpace, t: string) => (why: string) => { embedFails.set(sp + '\u0001' + t, why); };
  const settle = (sp: EmbedSpace, t: string, v: number[] | null) => { if (v) embedFails.delete(sp + '\u0001' + t); return v; };
  const memoMin = o.cacheTtlMin ?? 0;
  return {
    gate: async () => (await admin.rpc('fn_kernel_paid_provider_gate', { p_model: HOLD_PROBE_MODEL })).data,
    llm: async (phase, system, input, o) => {
      const { makeLlmRich } = await import('../llm.ts');
      // A declared internal duty (think: req.internalDuty for an internal audience) tells ai_gateway so (internal_duty).
      const call = makeLlmRich([], { fn, taskClass: o.taskClass, agent: o.seat, max: o.max ?? 900, timeoutMs: o.timeoutMs ?? 45_000, cacheTtlMin: memoMin, ...(memoMin > 0 ? { cacheExact: true } : {}), ...(o.internal === true ? { internalDuty: true } : {}), json: true, temperature: o.temperature ?? (phase === 'verify' ? 0 : 0.2), ...(o.rateKey ? { rateKey: o.rateKey } : {}) });
      // A photo or drawing the person sent rides as image parts; the gateway routes it to a vision-capable model.
      const last = o.images?.length ? { role: 'user', content: [{ type: 'text', text: input }, ...o.images.map((url) => ({ type: 'image_url', image_url: { url } }))] } : { role: 'user', content: input };
      // history (chat_history.ts): the conversation so far as real turns before this one, cached by the gateway
      const content = o.history?.length ? [...o.history, last] : o.images?.length ? [last] : input;
      // sysStable: the byte-stable prefix (the company brief) the gateway marks cacheable; `system` follows it.
      const r = await call(system, content as never, o.max ?? 900, o.sysStable ?? '', { ...(o.counterpartModel ? { counterpartModel: o.counterpartModel } : {}), ...(o.subject ? { subject: o.subject } : {}), ...(o.sysShared ? { sysShared: o.sysShared } : {}), ...(o.cacheTtl ? { cacheTtl: o.cacheTtl } : {}), ...(o.history?.length ? { cacheHistory: true } : {}), ...(o.effort ? { effort: o.effort } : {}), ...(o.signal ? { signal: o.signal } : {}) });
      return { content: r.content, model: r.model ?? null, error: r.error, used_llm: r.used_llm };
    },
    embed: async (t, space) => {
      // The model runs in embed_ml, never in this worker (ml_embed_client.ts); 8 s covers its cold start (1.2-2.6 s).
      if (space === 'ml') { const { embedQueryMlRemote } = await import('../ml_embed_client.ts'); return settle('ml', t, await embedQueryMlRemote(admin, t, fn, embedMs, noteFail('ml', t))); }
      const { embedLine } = await import('../gte_embed.ts');
      // Outside the edge runtime (the seat exam on a machine) there is no Supabase.ai: the same gte-small answers from
      // embed_ml instead of null, so a run off the edge retrieves exactly as the edge does (ml_embed_client.embedGteRemote).
      // deno-lint-ignore no-explicit-any
      if (o.gte === 'remote' || !(globalThis as any).Supabase?.ai) { const { embedGteRemote } = await import('../ml_embed_client.ts'); return settle('gte', t, await embedGteRemote(admin, t, fn, embedMs, noteFail('gte', t))); }
      return await embedLine(t);
    },
    embedFailure: (t, sp) => embedFails.get(sp + '\u0001' + t) ?? null,
    space: async () => { const { readSpace } = await import('../ml_embed_client.ts'); return await readSpace(admin); },
    rpc: async (f, args) => { const r = await admin.rpc(f, args); return { data: r.data, error: r.error }; },
    search: (q) => webSearch(admin, q),
    read: readPage,
  };
}

/** The deps of the resilience_ping heartbeat's batch work (held replay, routine judgements): gte-small in embed_ml. */
export function heartbeatDeps(admin: Admin): ThinkDeps {
  return defaultDeps(admin, 'resilience_ping', { gte: 'remote' });
}
