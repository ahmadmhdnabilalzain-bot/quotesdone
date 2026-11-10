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
  checkWhole?: (text: string) => string[];   // rules for the finished answer only, never one streamed sentence (the reply's language: a published contact line or an English spec inside an Arabic reply is one sentence in the other script)
  images?: string[];   // photos or drawings with the latest message (chat_images.acceptImages); the gateway routes to a vision model (ruling 1200)
  deadline?: number;   // epoch ms by which the answer must be settled; no call starts after it (3. above)
  // 5. DROPS WHAT NOBODY ASKED FOR (customer_support, 27 Oct 2026; sales_engineer/portal_conversation.ts). A fresh filter per
  // answer, called on each sentence in order: a sentence it names a reason for is never shown and never fails the answer
  // (a re-asked question, an unasked fee line); the rest of the answer stands. An answer with nothing left is rewritten.
  // BriefAnswer.dropped lists each as "<reason> | <the sentence>", so a false drop can be audited from agent_runs.
  // per sentence: null keep, a reason drop, or { text, why } keep only that part of it; end(): a whole-answer problem.
  // The filter only removes the model's words or keeps one clause of them: it never adds any (founder_instruction 1339).
  drop?: () => ((sentence: string) => string | null | { text: string; why: string }) & { end?: () => string | null };
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
export interface BriefAnswer { reply: string; model: string | null; attempts: string[]; rewrites: number; streamed: boolean; error?: string; outage?: boolean; dropped?: string[]; problems?: string[] }
/** One call's outcome, as the outage rule reads it: `answered` when a model replied even though nothing usable came back
 *  (cut off at the output limit); `http` is the gateway's status (a 5xx is an outage whatever its error text says). */
// route: the first model of the gateway's own ladder, as a failed call reports it (ai_gateway handle.ts: 502 {ladder}); the
// third rung's "another family" is measured against it when no model answered (10 Nov 2026, ruling 1571).
type Call = { text: string; model: string | null; error?: string; http?: number; answered?: boolean; route?: string | null };
const ladderHead = (j: { ladder?: unknown } | null): string | null => {
  const m = Array.isArray(j?.ladder) ? String(j!.ladder[0] ?? '') : '';
  return /^[a-z0-9-]+\/[a-z0-9.:-]+$/i.test(m) ? m : null;
};
type Fetch = typeof fetch;
const NOTHING_LEFT = 'everything it said was dropped (a question already asked or answered, or a line they did not ask for); answer their message and ask only what is still missing';
/** A whole answer with the caller's dropped sentences taken out; `why` collects the reasons. Unchanged without a filter. */
function stripped(c: BriefCall, text: string, why: string[]): { text: string; end: string | null } {
  if (!c.drop || !text) return { text, end: null };
  const f = c.drop();
  const { done, rest } = takeSentences(text + '\n');
  const kept: string[] = [];
  for (const s of [...done, rest]) {
    if (!s.trim()) continue;
    const r = f(s);
    if (typeof r === 'string') why.push(r + ' | ' + s.trim().slice(0, 160));
    else if (r) { why.push(r.why + ' | ' + s.trim().slice(0, 160)); kept.push(r.text); }
    else kept.push(s.trim());
  }
  return { text: kept.join(' ').trim(), end: f.end?.() ?? null };
}

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
    const j = await r.json().catch(() => null) as { content?: string; model?: string; error?: string; outcome?: string; truncated?: boolean; ladder?: unknown } | null;
    if (j?.truncated) return { text: '', model: j?.model ?? null, error: 'truncated at the output limit', http: r.status, answered: true };   // a cut-off answer is never used
    const text = typeof j?.content === 'string' ? j.content.trim() : '';
    return text ? { text, model: j?.model ?? null } : { text: '', model: null, error: String(j?.error || j?.outcome || ('HTTP ' + r.status)), http: r.status, route: ladderHead(j) };
  } catch (e) { return { text: '', model: null, error: String((e as Error)?.message || e) }; }
}

/** The streamed attempt. Emits each finished sentence that passes the figure check; stops at the first that does not. */
async function streamed(f: Fetch, c: BriefCall, known: Set<string>, emit: (t: string) => void, dropped: string[]):
  Promise<Call & { bad: string[]; kept?: string }> {
  const ms = callBudget(c.deadline, Date.now(), RESERVE_MS);
  if (ms === 0) return { text: '', model: null, bad: [], error: NO_TIME };
  let r: Response;
  try { r = await f(c.gateway, init(c, { stream: true }, ms)); }
  catch (e) { return { text: '', model: null, bad: [], error: String((e as Error)?.message || e) }; }
  if (!(r.headers.get('content-type') || '').includes('event-stream') || !r.body) {
    const j = await r.json().catch(() => null) as { error?: string; outcome?: string; ladder?: unknown } | null;
    return { text: '', model: null, bad: [], error: String(j?.error || j?.outcome || ('HTTP ' + r.status)), http: r.status, route: ladderHead(j) };
  }
  const model = r.headers.get('x-qd-model');
  const rd = r.body.getReader(); const dec = new TextDecoder();
  let sse = '', pending = '', shown = '', raw = '', finish = '';
  const dropOf = c.drop?.();
  const check = (s0: string) => {
    raw += s0;
    let s = s0;
    const d = dropOf?.(s0);
    if (typeof d === 'string') { dropped.push(d + ' | ' + s0.trim().slice(0, 160)); return []; }   // never shown, never a failure (5. above)
    if (d) { dropped.push(d.why + ' | ' + s0.trim().slice(0, 160)); s = d.text + (s0.match(/\s*$/)?.[0] || ' '); }
    const bad = problems(c, s, known); if (!bad.length) { shown += s; emit(s); } return bad;
  };
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
  const whole = [...revealFeeIncomplete(shown), ...(c.checkWhole?.(shown.trim()) ?? [])];
  if (shown.trim() && whole.length) return { text: shown.trim(), model, bad: whole };
  if (!shown.trim() && raw.trim()) return { text: raw.trim(), model, bad: [NOTHING_LEFT] };
  const end = dropOf?.end?.();
  if (end) return { text: raw.trim(), model, bad: [end], kept: shown.trim() };   // fails the caller's shape as a whole: rewritten
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
  const whole = (t: string) => [...problems(c, t, known), ...revealFeeIncomplete(t), ...(c.checkWhole?.(t) ?? [])];
  const dropped: string[] = [];
  const s = await streamed(f, c, known, emit, dropped);
  seen(s, s.bad);
  attempts.push('stream:' + (s.error ? 'failed ' + s.error : s.bad.length ? 'figures ' + s.bad.join(',') : 'ok'));
  if (!s.error && !s.bad.length) return { reply: s.text, model: s.model, attempts, rewrites, streamed: true, outage: false, dropped };
  // The gateway refused this sender's rate bucket: no other model is asked (that would spend past the limit); the caller
  // shows its rate-limit notice. The rate limit is not an outage (openrouter_down.ts).
  if (s.error && /rate_limited/.test(s.error)) return { reply: '', model: null, attempts, rewrites, streamed: false, error: 'rate_limited', outage: false, dropped };
  // A whole answer's problems once the filtered sentences are out (5. above); an answer with nothing left is a problem of
  // its own. An answer that failed ONLY the caller's whole-answer shape (end()) is kept: if no rung does better, it is sent
  // (a reply without a question still answers them, in the model's own words).
  let shapeOnly: { reply: string; model: string | null } | null = s.kept ? { reply: s.kept, model: s.model } : null;
  // THE SAME REFUSAL ON A LATER RUNG (review of #1729, 1 Nov 2026): the stream got through but a rewrite or a retry was
  // refused for this sender's rate bucket. No further model is asked; a passing draft already written is still sent
  // (salvage below), and with none the result is 'rate_limited' rather than "no model produced an answer", so the
  // caller shows its rate-limit notice and files no knowledge gap for a question no model was allowed to finish.
  let limited = false;
  const refused = (r: { error?: string }) => !!r.error && /rate_limited/.test(r.error) && (limited = true);
  const judge = (text: string, m: string | null): { text: string; bad: string[] } => {
    const { text: t, end } = stripped(c, text, dropped);
    if (!t) return { text: t, bad: [NOTHING_LEFT] };
    const bad = whole(t);
    if (end && !bad.length) shapeOnly = { reply: t, model: m };
    return { text: t, bad: end ? [end, ...bad] : bad };
  };
  // The figure check failed: the MODEL rewrites the whole answer with the correction named. Checked again, twice at most.
  let draft = s.text; let bad = s.bad; let model = s.model;
  const correction = (d: string, b: string[]): Msg[] => [...c.input, { role: 'assistant', content: d },
    { role: 'user', content: `Your answer has these problems: ${b.join('; ')}. Write the whole answer again, exact and direct, correcting them: use only figures the company brief states (where it gives none, explain without a number) and follow every rule in your instructions.` }];
  if (!s.error) {
    for (let i = 0; i < 2 && bad.length; i++) {
      rewrites++;
      const fix = await once(f, { ...c, input: correction(draft, bad) }, {});
      attempts.push('rewrite:' + (fix.error ? 'failed ' + fix.error : 'ok'));
      if (refused(fix)) break;
      if (!fix.text) { seen(fix); break; }
      const j = judge(fix.text, fix.model); model = fix.model; bad = j.bad; draft = bad.length ? fix.text : j.text;
      seen(fix, bad);
      if (!bad.length) return { reply: draft, model, attempts, rewrites, streamed: false, outage: false, dropped };
    }
  }
  // The streamed call failed (or its rewrites did): the same class unstreamed (the route's own ladder), then ANOTHER FAMILY
  // through the gateway's counterpart routing. Each answer is figure-checked. THE COUNTERPART FOLLOWS THE ROUTE (10 Nov 2026,
  // ruling 1571): the model that answered, else the head of the ladder a failed call reported, never a model named here (it
  // was 'anthropic/claude-sonnet-5.5', which would send a Luna Pro class's third call back to Luna Pro's family). Neither
  // known (every call threw): a plain third ask on the route. Prevented by: brief_answer.test.ts.
  let routeSeen: string | null = s.route ?? null;
  for (const step of ['retry', 'third'] as const) {
    if (limited) break;
    const cp = step === 'third' ? (model || routeSeen) : null;
    const extra = cp ? { counterpart_model: cp } : {};
    const a = await once(f, c, extra);
    routeSeen ??= a.route ?? null;
    attempts.push((step === 'third' ? 'third:' : 'retry:') + (a.error ? 'failed ' + a.error : 'ok'));
    if (refused(a)) break;
    const j = a.text ? judge(a.text, a.model) : null;
    seen(a, j?.bad ?? []);
    if (j && !j.bad.length) return { reply: j.text, model: a.model, attempts, rewrites, streamed: false, outage: false, dropped };
  }
  if (shapeOnly) { attempts.push('kept: an answer whose only fault was its shape'); return { ...shapeOnly, attempts, rewrites, streamed: false, outage: false, dropped }; }
  // THE MODEL WAS UP AND NO WHOLE ANSWER PASSED (1339). Its own sentences that pass every check are kept, the rest dropped
  // (ai_reply.salvage: code removes words, it never adds any). None pass: the model is asked once more, with the problems
  // named; that answer is checked the same way. Nothing passes: no text, and not an outage.
  // salvaged sentences pass the caller's filter too: a re-ask or an unasked line is never salvaged back in
  const keep = (t: string) => { const st = stripped(c, t, []).text; return st ? salvage(st, (x) => problems(c, x, known), whole) : ''; };
  if (lastDraft) {
    const kept = keep(lastDraft);
    if (kept) { attempts.push('salvaged: the passing sentences of the last draft'); return { reply: kept, model: lastModel, attempts, rewrites, streamed: false, outage: false, dropped }; }
  }
  if (answered && !limited) {
    const again = await once(f, lastDraft ? { ...c, input: correction(lastDraft, lastBad.length ? lastBad : whole(lastDraft)) } : c, {});
    attempts.push('again:' + (again.error ? 'failed ' + again.error : 'ok'));
    refused(again);
    if (again.text) {
      const j = judge(again.text, again.model);
      if (!j.bad.length) return { reply: j.text, model: again.model, attempts, rewrites, streamed: false, outage: false, dropped };
      const kept = keep(again.text);
      if (kept) { attempts.push('salvaged: the passing sentences of the last draft'); return { reply: kept, model: again.model, attempts, rewrites, streamed: false, outage: false, dropped }; }
    }
  }
  if (limited) return { reply: '', model: null, attempts, rewrites, streamed: false, error: 'rate_limited', outage: false, dropped };
  const outage = !answered && failures.length > 0 && failures.every((x) => isOpenRouterDown(x.error, x.http));
  return { reply: '', model: null, attempts, rewrites, streamed: false, outage, dropped,
    problems: lastBad.length ? lastBad : (lastDraft ? whole(lastDraft) : []),
    error: outage ? 'openrouter_down' : 'no model produced an answer that passes the figure check' };
}
