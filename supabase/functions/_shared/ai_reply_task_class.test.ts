// aiReply follows the ROUTE, not a model named in code, and runs the class its caller names (it_engineer, 10 Nov 2026; ruling
// 1571, design docs/reports/2026-11-10-design-model-routing.md 5b). Stubbed gateway and database; no network, no paid call.
// Fails on the parent of this change: REPLY_MODEL was the constant 'anthropic/claude-sonnet-5.5', so with the class on Luna Pro
// the "other family" rung asked for a counterpart of Sonnet (Luna Pro's own family answered again), every call carried the
// 1-hour Anthropic cache write, and every reply ran conversation_reply whatever its task.
import { assert, assertEquals } from 'jsr:@std/assert';
import { aiReply, REPLY_CLASS, routePrimary } from './ai_reply.ts';
import type { LlmReply, ThinkDeps } from './think.ts';

const COMPANY = 'REVEAL FEE: the customer pays 3.00% of the selected quotation value. No card fee is added.';
const A = (answer: string) => JSON.stringify({ answer });
type Call = { o: Record<string, unknown> };
function stub(answers: (string | null)[], route: (args: Record<string, unknown>) => unknown) {
  const calls: Call[] = []; const routed: Record<string, unknown>[] = [];
  const deps = {
    gate: () => Promise.resolve(null), embed: () => Promise.resolve(null),
    llm: (_p: string, _s: string, _i: string, o: Record<string, unknown>) => {
      calls.push({ o }); const a = answers.shift();
      return Promise.resolve((a == null ? { content: null, error: 'gateway_http_503' } : { content: a, model: 'stub/answered' }) as LlmReply);
    },
    rpc: (fn: string, args: Record<string, unknown>) => {
      if (fn === 'fn_ai_route') { routed.push(args); return Promise.resolve({ data: route(args), error: null }); }
      return Promise.resolve({ data: fn === 'fn_company_context' ? { block: COMPANY } : null, error: null });
    },
  } as unknown as ThinkDeps;
  return { deps, calls, routed };
}
const req = { seat: 'customer_support' as const, channel: 'whatsapp', audience: 'customer' as const, lang: 'en' as const, message: 'Where is my request?' };
const OK = 'The reveal fee is 3%, with no card fee and no VAT.';

Deno.test('the class the caller names is the class every call runs; absent, conversation_reply', async () => {
  const s = stub([A(OK)], () => ({ model: 'openai/gpt-6-luna-pro' }));
  await aiReply(s.deps, { ...req, taskClass: 'status_reply' });
  assertEquals(s.calls[0].o.taskClass, 'status_reply');
  assertEquals(s.routed[0], { p_task_class: 'status_reply', p_agent_key: 'customer_support' }, 'the route is read for that class and seat');
  const d = stub([A(OK)], () => ({ model: 'openai/gpt-6-luna-pro' }));
  await aiReply(d.deps, req);
  assertEquals(d.calls[0].o.taskClass, REPLY_CLASS);
});

Deno.test('the other-family rung counters the route\'s primary, whichever model it is', async () => {
  for (const primary of ['openai/gpt-6-luna-pro', 'anthropic/claude-sonnet-5.5']) {
    const s = stub([null, A(OK)], () => ({ model: primary }));
    const r = await aiReply(s.deps, req);
    assertEquals(r.reply, OK);
    assertEquals(s.calls[0].o.counterpartModel, undefined, 'the first rung is the route itself');
    assertEquals(s.calls[1].o.counterpartModel, primary, `the second rung asks for another family than ${primary}`);
  }
});

Deno.test('a re-ask starts on another family than the route\'s primary; with no route read it asks the route', async () => {
  const s = stub([A(OK)], () => ({ model: 'openai/gpt-6-luna-pro' }));
  await aiReply(s.deps, { ...req, otherFamilyFirst: true });
  assertEquals(s.calls[0].o.counterpartModel, 'openai/gpt-6-luna-pro');
  const n = stub([A(OK)], () => null);
  const r = await aiReply(n.deps, { ...req, otherFamilyFirst: true });
  assertEquals(r.reply, OK);
  assertEquals(n.calls[0].o.counterpartModel, undefined, 'no primary known: no counterpart is invented');
});

Deno.test('the route unreadable: the second rung counters the model that answered the first', async () => {
  const s = stub([A('I will check and get back to you.'), A('I will check and get back to you.'), A('I will check and get back to you.'), A(OK)], () => { throw new Error('db down'); });
  const r = await aiReply(s.deps, req);
  assertEquals(r.reply, OK);
  assertEquals(s.calls.at(-1)!.o.counterpartModel, 'stub/answered');
});

Deno.test('the 1-hour cache write is asked only of an Anthropic primary', async () => {
  const lp = stub([A(OK)], () => ({ model: 'openai/gpt-6-luna-pro' }));
  await aiReply(lp.deps, req);
  assertEquals(lp.calls[0].o.cacheTtl, undefined);
  const son = stub([A(OK)], () => ({ model: 'anthropic/claude-sonnet-5.5' }));
  await aiReply(son.deps, req);
  assertEquals(son.calls[0].o.cacheTtl, '1h');
});

Deno.test('routePrimary takes only a model id from the route', async () => {
  const at = (data: unknown, error: unknown = null) => ({ rpc: () => Promise.resolve({ data, error }) }) as unknown as ThinkDeps;
  assertEquals(await routePrimary(at({ model: 'qwen/qwen3.8-flash' }), 'x', null), 'qwen/qwen3.8-flash');
  assertEquals(await routePrimary(at({ model: 'none' }), 'x', null), null, 'a deterministic route has no primary');
  assertEquals(await routePrimary(at({ model: 'openai/gpt-6-luna-pro' }, { message: 'boom' }), 'x', null), null);
  assertEquals(await routePrimary(at(null), 'x', null), null);
  assert(true);
});
