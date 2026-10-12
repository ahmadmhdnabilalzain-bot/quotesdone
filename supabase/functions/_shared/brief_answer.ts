// ONE MODEL CALL ANSWERS, STREAMED AS IT IS WRITTEN (customer_support, 12 Oct 2026; founder rulings 1195 and 1196).
// The model is given the company brief (company_brief.ts) as the cacheable half of its system prompt and answers from
// it and from its own expertise. Code writes no reply text. Around the model, code only:
//   1. CHECKS FIGURES: each finished sentence is checked before it is shown — every money or rate figure must be one the
//      brief states (moneyFiguresNotInBrief). A sentence that fails stops the stream, and the MODEL rewrites the whole
//      answer with the correction named; the rewrite is checked the same way (twice at most).
//   2. CLIMBS THE MODEL LADDER: the streamed call (the gateway's own ladder: gpt-6-luna, then gemini-3.8-flash behind it),
//      then the same class unstreamed, then a third call routed as a counterpart of the model that failed (the gateway's
//      review routing picks another family). No canned answer exists: if every model fails, the caller gets no text.
// prevented by: _shared/brief_answer.test.ts
import { withImages } from './chat_images.ts';
import { briefNumbers, moneyFiguresNotInBrief, policyProblems, revealFeeIncomplete, takeSentences } from './company_brief.ts';

export type Msg = { role: 'user' | 'assistant'; content: string };
export interface BriefCall {
  gateway: string; secret: string; fn: string; agent: string | null; taskClass: string;
  brief: string; sys: string; input: Msg[]; max: number;
  rateKey?: string; rateLimit?: number; subject?: Record<string, unknown>;
  check?: (text: string) => string[];   // more rules around the words (the reply guard); each problem is named to the model
  images?: string[];   // photos or drawings with the latest message (chat_images.acceptImages); the gateway routes to a vision model (ruling 1200)
}
export interface BriefAnswer { reply: string; model: string | null; attempts: string[]; rewrites: number; streamed: boolean; error?: string }
type Fetch = typeof fetch;

/** The latest user message carries the images as content parts; the rest of the conversation stays text. */
const withLastImages = (input: Msg[], images?: string[]) => !images?.length || !input.length ? input
  : [...input.slice(0, -1), { ...input[input.length - 1], content: withImages(input[input.length - 1].content, images) }];

const body = (c: BriefCall, extra: Record<string, unknown>) => JSON.stringify({
  __secret: c.secret, fn: c.fn, agent: c.agent, task_class: c.taskClass, sys_stable: c.brief, sys: c.sys, input: withLastImages(c.input, c.images),
  max: c.max, temperature: 0.3, cache_ttl_min: 0, try_faq: false, ...(c.subject ? { subject: c.subject } : {}),
  ...(c.rateKey ? { rate_key: c.rateKey, rate_limit: c.rateLimit, rate_window_s: 3600 } : {}), ...extra,
});

async function once(f: Fetch, c: BriefCall, extra: Record<string, unknown>): Promise<{ text: string; model: string | null; error?: string }> {
  try {
    const r = await f(c.gateway, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: body(c, extra) });
    const j = await r.json().catch(() => null) as { content?: string; model?: string; error?: string; outcome?: string; truncated?: boolean } | null;
    if (j?.truncated) return { text: '', model: j?.model ?? null, error: 'truncated at the output limit' };   // a cut-off answer is never used
    const text = typeof j?.content === 'string' ? j.content.trim() : '';
    return text ? { text, model: j?.model ?? null } : { text: '', model: null, error: String(j?.error || j?.outcome || ('HTTP ' + r.status)) };
  } catch (e) { return { text: '', model: null, error: String((e as Error)?.message || e) }; }
}

/** The streamed attempt. Emits each finished sentence that passes the figure check; stops at the first that does not. */
async function streamed(f: Fetch, c: BriefCall, known: Set<string>, emit: (t: string) => void):
  Promise<{ text: string; model: string | null; bad: string[]; error?: string }> {
  let r: Response;
  try { r = await f(c.gateway, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: body(c, { stream: true }) }); }
  catch (e) { return { text: '', model: null, bad: [], error: String((e as Error)?.message || e) }; }
  if (!(r.headers.get('content-type') || '').includes('event-stream') || !r.body) {
    const j = await r.json().catch(() => null) as { error?: string; outcome?: string } | null;
    return { text: '', model: null, bad: [], error: String(j?.error || j?.outcome || ('HTTP ' + r.status)) };
  }
  const model = r.headers.get('x-qd-model');
  const rd = r.body.getReader(); const dec = new TextDecoder();
  let sse = '', pending = '', shown = '', finish = '';
  const check = (s: string) => { const bad = problems(c, s, known); if (!bad.length) { shown += s; emit(s); } return bad; };
  for (;;) {
    const { done, value } = await rd.read();
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
  if (finish === 'length') return { text: (shown + pending).trim(), model, bad: ['it was cut off by the length limit; write the whole answer again, complete and shorter'] };
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
  const known = briefNumbers(c.brief);
  const attempts: string[] = [];
  let rewrites = 0;
  const s = await streamed(f, c, known, emit);
  attempts.push('stream:' + (s.error ? 'failed ' + s.error : s.bad.length ? 'figures ' + s.bad.join(',') : 'ok'));
  if (!s.error && !s.bad.length) return { reply: s.text, model: s.model, attempts, rewrites, streamed: true };
  // The gateway refused this sender's rate bucket: no other model is asked (that would spend past the limit); the caller
  // shows its rate-limit notice.
  if (s.error && /rate_limited/.test(s.error)) return { reply: '', model: null, attempts, rewrites, streamed: false, error: 'rate_limited' };
  // The figure check failed: the MODEL rewrites the whole answer with the correction named. Checked again, twice at most.
  let draft = s.text; let bad = s.bad; let model = s.model;
  if (!s.error) {
    for (let i = 0; i < 2 && bad.length; i++) {
      rewrites++;
      const fix = await once(f, { ...c, input: [...c.input, { role: 'assistant', content: draft },
        { role: 'user', content: `Your answer has these problems: ${bad.join('; ')}. Write the whole answer again, exact and direct, correcting them: use only figures the company brief states (where it gives none, explain without a number) and follow every rule in your instructions.` }] }, {});
      attempts.push('rewrite:' + (fix.error ? 'failed ' + fix.error : 'ok'));
      if (!fix.text) break;
      draft = fix.text; model = fix.model; bad = [...problems(c, draft, known), ...revealFeeIncomplete(draft)];
      if (!bad.length) return { reply: draft, model, attempts, rewrites, streamed: false };
    }
  }
  // The streamed call failed (or its rewrites did): the same class unstreamed (gpt-6-luna, then gemini behind it), then a
  // third family through the gateway's counterpart routing. Each answer is figure-checked.
  for (const extra of [{}, { counterpart_model: model || 'openai/gpt-6-luna' }]) {
    const a = await once(f, c, extra);
    attempts.push((('counterpart_model' in extra) ? 'third:' : 'retry:') + (a.error ? 'failed ' + a.error : 'ok'));
    if (a.text && ![...problems(c, a.text, known), ...revealFeeIncomplete(a.text)].length) return { reply: a.text, model: a.model, attempts, rewrites, streamed: false };
  }
  return { reply: '', model: null, attempts, rewrites, streamed: false, error: 'no model produced an answer that passes the figure check' };
}
