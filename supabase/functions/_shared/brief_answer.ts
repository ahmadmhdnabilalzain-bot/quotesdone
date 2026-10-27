// ONE MODEL CALL ANSWERS, STREAMED AS IT IS WRITTEN (customer_support, 12 Oct 2026; founder rulings 1195 and 1196).
// The model is given the company brief (company_brief.ts) as the cacheable half of its system prompt and answers from
// it and from its own expertise. Code writes no reply text. Around the model, code only:
//   1. CHECKS FIGURES: each finished sentence is checked before it is shown — every money or rate figure must be one the
//      brief states (moneyFiguresNotInBrief). A sentence that fails stops the stream, and the MODEL rewrites the whole
//      answer with the correction named; the rewrite is checked the same way (twice at most).
//   2. CLIMBS THE MODEL LADDER: the streamed call (the gateway's own ladder: claude-sonnet-5.5, then gemini-3.8-flash behind
//      it; founder ruling 1219, 13 Oct 2026),
//      then the same class unstreamed, then a third call routed as a counterpart of the model that failed (the gateway's
//      review routing picks another family). No canned answer exists: if every model fails, the caller gets no text.
//   3. KEEPS THE TURN'S CLOCK (customer_support / it_engineer, 27 Oct 2026). A caller that passes `deadline` gets every call
//      bounded: each one is given min(PER_CALL_MS, time left), the gateway is told the same (client_timeout_ms, so it never
//      bills an answer we stopped waiting for), and no call starts with under MIN_CALL_MS left. Without a deadline nothing
//      changes. Measured before it: the ladder above had no bound at all (stream + two rewrites + retry + third, each as long
//      as the gateway's 55 s wall), and the portal turn it now serves took 58-150 s; one hit the 150 s edge wall as a 504.
//   4. SAYS WHETHER OPENROUTER WAS DOWN (founder_instruction 1339, 27 Oct 2026, verbatim: "the engineer and customer support
//      never replies without llm unless the server of open router is down"). `outage` is true ONLY when no call reached a
//      model and every failure was a provider failure by openrouter_down.ts (network error, 5xx, timeout or deadline, an
//      open circuit or the founder's hold, no credential). A draft the checks refused, a 4xx or the rate limit is the model
//      UP: its own passing sentences are kept (ai_reply.salvage, the same as aiReply), and when none pass the model is
//      asked once more. Code adds no words. Measured before: this returned reply '' with no outage field both when every
//      call failed AND when every draft was refused, so the portal could not tell "OpenRouter is down" from "the model
//      answered and we dropped it", and showed its own fixed line for both.
// prevented by: _shared/brief_answer.test.ts
import { withImages } from './chat_images.ts';
import { briefNumbers, figureSource, moneyFiguresNotInBrief, policyProblems, revealFeeIncomplete, splitBrief, takeSentences } from './company_brief.ts';
import { isOpenRouterDown } from './openrouter_down.ts';
import { salvage } from './ai_reply.ts';

export type Msg = { role: 'user' | 'assistant'; content: string };
export interface BriefCall {
  gateway: string; secret: string; fn: string; agent: string | null; taskClass: string;
  brief: string; sys: string; input: Msg[]; max: number;
  rateKey?: string; rateLimit?: number; subject?: Record<string, unknown>;
  check?: (text: string) => string[];   // more rules around the words (the reply guard); each problem is named to the model
  images?: string[];   // photos or drawings with the latest message (chat_images.acceptImages); the gateway routes to a vision model (ruling 1200)
  deadline?: number;   // epoch ms by which the answer must be settled; no call starts after it (3. above)
}
/** The longest one call may take inside a deadline: a streamed Sonnet 5.5 answer of 900-1,200 tokens is written in 10-25 s. */
export const PER_CALL_MS = 40_000;
/** No call starts with less than this left: a call cut at 5 s has paid for its prompt and written nothing usable. */
export const MIN_CALL_MS = 8_000;
/** What the streamed first call keeps back for the next rung: one minimum call plus slack, so the reserve is never a
 *  few milliseconds short of MIN_CALL_MS by the time the stream has been cut (measured in brief_answer.test.ts). */
export const RESERVE_MS = MIN_CALL_MS + 2_000;
/** outage: no call reached a model, and every failure was a provider failure (openrouter_down.ts). Only then may a caller
 *  show its own fixed line (founder_instruction 1339); with the model up and nothing sendable, the caller shows nothing. */
/** problems: why the last draft was refused when no reply passed (the asynchronous re-ask names them; _shared/reask.ts). */
export interface BriefAnswer { reply: string; model: string | null; attempts: string[]; rewrites: number; streamed: boolean; error?: string; outage?: boolean; problems?: string[] }
/** One call's outcome, as the outage rule reads it: `answered` when a model replied even though nothing usable came back
 *  (cut off at the output limit); `http` is the gateway's status (a 5xx is an outage whatever its error text says). */
type Call = { text: string; model: string | null; error?: string; http?: number; answered?: boolean };
type Fetch = typeof fetch;

/** The latest user message carries the images as content parts; the rest of the conversation stays text. */
const withLastImages = (input: Msg[], images?: string[]) => !images?.length || !input.length ? input
  : [...input.slice(0, -1), { ...input[input.length - 1], content: withImages(input[input.length - 1].content, images) }];

const body = (c: BriefCall, extra: Record<string, unknown>) => JSON.stringify({
  __secret: c.secret, fn: c.fn, agent: c.agent, task_class: c.taskClass,
  // one cached prefix for every language and channel: the knowledge block (sys_shared), then the caller's stable half,
  // both on the 1-hour cache tier (ai_gateway/system_message.ts); the language rules ride in sys, after them
  sys_shared: splitBrief(c.brief).shared, sys_stable: splitBrief(c.brief).stable, cache_ttl: '1h', sys: c.sys, input: withLastImages(c.input, c.images), ...(c.input.length > 1 ? { cache_history: true } : {}),   // the earlier turns are the third cached block (chat_history.ts)
  max: c.max, temperature: 0.3, cache_ttl_min: 0, try_faq: false, ...(c.subject ? { subject: c.subject } : {}),
  ...(c.rateKey ? { rate_key: c.rateKey, rate_limit: c.rateLimit, rate_window_s: 3600 } : {}), ...extra,
});

/** This call's share of the turn: null when no deadline was given, 0 when there is no time left to start one.
 *  `reserve`: time kept back for the next rung when there is enough for both (the streamed first call keeps RESERVE_MS
 *  back, so a stream that hangs still leaves another model room to answer); with too little for both, this call gets all. */
export function callBudget(deadline: number | undefined, now = Date.now(), reserve = 0): number | null {
  if (deadline == null) return null;
  const left = deadline - now;
  if (left < MIN_CALL_MS) return 0;
  return Math.min(PER_CALL_MS, left - reserve >= MIN_CALL_MS ? left - reserve : left);
}
const NO_TIME = 'deadline: no time left for another call';
/** The request for one call: the gateway is told how long we wait, and the fetch stops waiting then. */
const init = (c: BriefCall, extra: Record<string, unknown>, ms: number | null): RequestInit => ({
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: body(c, ms ? { ...extra, client_timeout_ms: ms } : extra), ...(ms ? { signal: AbortSignal.timeout(ms) } : {}),
});

async function once(f: Fetch, c: BriefCall, extra: Record<string, unknown>): Promise<Call> {
  const ms = callBudget(c.deadline);
  if (ms === 0) return { text: '', model: null, error: NO_TIME };
  try {
    const r = await f(c.gateway, init(c, extra, ms));
    const j = await r.json().catch(() => null) as { content?: string; model?: string; error?: string; outcome?: string; truncated?: boolean } | null;
    if (j?.truncated) return { text: '', model: j?.model ?? null, error: 'truncated at the output limit', http: r.status, answered: true };   // a cut-off answer is never used
    const text = typeof j?.content === 'string' ? j.content.trim() : '';
    return text ? { text, model: j?.model ?? null } : { text: '', model: null, error: String(j?.error || j?.outcome || ('HTTP ' + r.status)), http: r.status };
  } catch (e) { return { text: '', model: null, error: String((e as Error)?.message || e) }; }
}

/** The streamed attempt. Emits each finished sentence that passes the figure check; stops at the first that does not. */
async function streamed(f: Fetch, c: BriefCall, known: Set<string>, emit: (t: string) => void):
  Promise<Call & { bad: string[] }> {
  const ms = callBudget(c.deadline, Date.now(), RESERVE_MS);
  if (ms === 0) return { text: '', model: null, bad: [], error: NO_TIME };
  let r: Response;
  try { r = await f(c.gateway, init(c, { stream: true }, ms)); }
  catch (e) { return { text: '', model: null, bad: [], error: String((e as Error)?.message || e) }; }
  if (!(r.headers.get('content-type') || '').includes('event-stream') || !r.body) {
    const j = await r.json().catch(() => null) as { error?: string; outcome?: string } | null;
    return { text: '', model: null, bad: [], error: String(j?.error || j?.outcome || ('HTTP ' + r.status)), http: r.status };
  }
  const model = r.headers.get('x-qd-model');
  const rd = r.body.getReader(); const dec = new TextDecoder();
  let sse = '', pending = '', shown = '', finish = '';
  const check = (s: string) => { const bad = problems(c, s, known); if (!bad.length) { shown += s; emit(s); } return bad; };
  for (;;) {
    // a stream the turn's clock cut (AbortSignal) is a failed attempt, never a finished answer: the ladder decides next
    let chunk: ReadableStreamReadResult<Uint8Array>;
    try { chunk = await rd.read(); } catch (e) { return { text: '', model, bad: [], error: 'stream cut: ' + String((e as Error)?.message || e).slice(0, 120) }; }
    const { done, value } = chunk;
    if (done) break;
    sse += dec.decode(value, { stream: true });
    let k: number;
    while ((k = sse.indexOf('\n')) >= 0) {
      const line = sse.slice(0, k).trim(); sse = sse.slice(k + 1);
      if (!line.startsWith('data:')) continue;
      const data = line.slice(5).trim();
      if (data === '[DONE]') continue;
      let delta = '';
      try { const j = JSON.parse(data); delta = String(j?.choices?.[0]?.delta?.content ?? ''); finish = String(j?.choices?.[0]?.finish_reason ?? '') || finish; } catch (_e) { delta = ''; }
      if (!delta) continue;
      pending += delta;
      const { done: sentences, rest } = takeSentences(pending);
      pending = rest;
      for (const s of sentences) {
        const bad = check(s);
        if (bad.length) { try { await rd.cancel(); } catch (_e) { /* stop paying for the rest */ } return { text: shown + s, model, bad }; }
      }
    }
  }
  // A CUT-OFF ANSWER IS NEVER SHOWN AS FINISHED (live photo test, 13 Oct 2026: an Arabic reply ended mid-sentence at the
  // output limit). The unfinished tail is held back, and the model writes the whole answer again, shorter.
  if (finish === 'length') return { text: (shown + pending).trim(), model, bad: ['it was cut off by the length limit; write the whole answer again, complete and shorter'], answered: true };
  if (pending.trim()) { const bad = check(pending); if (bad.length) return { text: shown + pending, model, bad }; }
  // the whole reply: a stated reveal fee must also say no card fee and no VAT (checked once the reply is complete)
  const whole = revealFeeIncomplete(shown);
  if (shown.trim() && whole.length) return { text: shown.trim(), model, bad: whole };
  return shown.trim() ? { text: shown.trim(), model, bad: [] } : { text: '', model, bad: [], error: 'empty stream' };
}

/** What is wrong with a text: money/rate figures the brief does not state, then the caller's own rules. */
function problems(c: BriefCall, text: string, known: Set<string>): string[] {
  return [...moneyFiguresNotInBrief(text, known).map((n) => 'the figure ' + n + ' (the brief states no such fee, price or rate)'), ...policyProblems(text), ...(c.check?.(text) ?? [])];
}

export async function answerFromBrief(c: BriefCall, emit: (t: string) => void, f: Fetch = fetch): Promise<BriefAnswer> {
  const known = briefNumbers(figureSource(c.brief));
  const attempts: string[] = [];
  let rewrites = 0;
  // WAS THE MODEL UP? (4. above) Every call is seen once. A draft is a whole answer the model wrote and a check refused; a
  // cut-off answer (`answered`) is the model up but never a draft, because its unfinished tail is not an answer.
  let answered = false; const failures: Call[] = [];
  let lastDraft = ''; let lastBad: string[] = []; let lastModel: string | null = null;
  const seen = (r: Call, bad: string[] = []) => {
    if (r.answered) { answered = true; return; }
    if (r.text) { answered = true; lastDraft = r.text; lastBad = bad; lastModel = r.model; return; }
    failures.push(r);
  };
  const whole = (t: string) => [...problems(c, t, known), ...revealFeeIncomplete(t)];
  const s = await streamed(f, c, known, emit);
  seen(s, s.bad);
  attempts.push('stream:' + (s.error ? 'failed ' + s.error : s.bad.length ? 'figures ' + s.bad.join(',') : 'ok'));
  if (!s.error && !s.bad.length) return { reply: s.text, model: s.model, attempts, rewrites, streamed: true, outage: false };
  // The gateway refused this sender's rate bucket: no other model is asked (that would spend past the limit); the caller
  // shows its rate-limit notice. The rate limit is not an outage (openrouter_down.ts).
  if (s.error && /rate_limited/.test(s.error)) return { reply: '', model: null, attempts, rewrites, streamed: false, error: 'rate_limited', outage: false };
  // The figure check failed: the MODEL rewrites the whole answer with the correction named. Checked again, twice at most.
  let draft = s.text; let bad = s.bad; let model = s.model;
  const correction = (d: string, b: string[]): Msg[] => [...c.input, { role: 'assistant', content: d },
    { role: 'user', content: `Your answer has these problems: ${b.join('; ')}. Write the whole answer again, exact and direct, correcting them: use only figures the company brief states (where it gives none, explain without a number) and follow every rule in your instructions.` }];
  if (!s.error) {
    for (let i = 0; i < 2 && bad.length; i++) {
      rewrites++;
      const fix = await once(f, { ...c, input: correction(draft, bad) }, {});
      attempts.push('rewrite:' + (fix.error ? 'failed ' + fix.error : 'ok'));
      if (!fix.text) { seen(fix); break; }
      draft = fix.text; model = fix.model; bad = whole(draft);
      seen(fix, bad);
      if (!bad.length) return { reply: draft, model, attempts, rewrites, streamed: false, outage: false };
    }
  }
  // The streamed call failed (or its rewrites did): the same class unstreamed (sonnet-5.5, then gemini behind it), then a
  // third family through the gateway's counterpart routing. Each answer is figure-checked.
  for (const extra of [{}, { counterpart_model: model || 'anthropic/claude-sonnet-5.5' }]) {
    const a = await once(f, c, extra);
    attempts.push((('counterpart_model' in extra) ? 'third:' : 'retry:') + (a.error ? 'failed ' + a.error : 'ok'));
    const aBad = a.text ? whole(a.text) : [];
    seen(a, aBad);
    if (a.text && !aBad.length) return { reply: a.text, model: a.model, attempts, rewrites, streamed: false, outage: false };
  }
  // THE MODEL WAS UP AND NO WHOLE ANSWER PASSED (1339). Its own sentences that pass every check are kept, the rest dropped
  // (ai_reply.salvage: code removes words, it never adds any). None pass: the model is asked once more, with the problems
  // named; that answer is checked the same way. Nothing passes: no text, and not an outage.
  const keep = (t: string) => salvage(t, (x) => problems(c, x, known), whole);
  if (lastDraft) {
    const kept = keep(lastDraft);
    if (kept) { attempts.push('salvaged: the passing sentences of the last draft'); return { reply: kept, model: lastModel, attempts, rewrites, streamed: false, outage: false }; }
  }
  if (answered) {
    const again = await once(f, lastDraft ? { ...c, input: correction(lastDraft, lastBad.length ? lastBad : whole(lastDraft)) } : c, {});
    attempts.push('again:' + (again.error ? 'failed ' + again.error : 'ok'));
    if (again.text) {
      if (!whole(again.text).length) return { reply: again.text, model: again.model, attempts, rewrites, streamed: false, outage: false };
      const kept = keep(again.text);
      if (kept) { attempts.push('salvaged: the passing sentences of the last draft'); return { reply: kept, model: again.model, attempts, rewrites, streamed: false, outage: false }; }
    }
  }
  const outage = !answered && failures.length > 0 && failures.every((x) => isOpenRouterDown(x.error, x.http));
  return { reply: '', model: null, attempts, rewrites, streamed: false, outage,
    problems: lastBad.length ? lastBad : (lastDraft ? whole(lastDraft) : []),
    error: outage ? 'openrouter_down' : 'no model produced an answer that passes the figure check' };
}
