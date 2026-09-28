// widgetReplyEffects() with stubbed RPCs, and site_assistant's composed-reply exit going through it (review of #1043).
import { assert, assertEquals } from 'jsr:@std/assert';
import { widgetReplyEffects, type WidgetReplyEffectsInput } from './widget_reply_effects.ts';

function stub() {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const rpc = (fn: string, args: Record<string, unknown>) => {
    calls.push({ fn, args });
    if (fn === 'fn_support_knowledge_gap') return Promise.resolve({ data: { ok: true, task_id: 42, reply_en: 'recorded', reply_ar: 'سُجّل' }, error: null });
    return Promise.resolve({ data: { ok: true }, error: null });
  };
  return { rpc, calls };
}
const base: WidgetReplyEffectsInput = {
  message: 'can I speak to someone about your insurance policy for crane hire?', live: false, grounded: false, answered: true,
  refusal: 'reasoned_without_company_knowledge', ip: '203.0.113.9', path: '/', askedForAPerson: () => Promise.resolve(true),
};

Deno.test('a composed reply with no company knowledge behind it files the gap, and a person ask reaches the CEO', async () => {
  const s = stub();
  const e = await widgetReplyEffects(s.rpc, base);
  assertEquals(await e.person, true);
  assertEquals(e.gapTaskId, 42);
  const gap = s.calls.find((c) => c.fn === 'fn_support_knowledge_gap');
  assert(gap, 'the knowledge gap was not recorded');
  assertEquals(gap.args.p_refusal, 'reasoned_without_company_knowledge');
  const ceo = s.calls.find((c) => c.fn === 'fn_support_report_to_ceo');
  assert(ceo, 'the visitor asked for a person and the CEO was not told');
  assertEquals(ceo.args.p_source_agent, 'customer_support');
});

Deno.test('a grounded reply files no gap; no person asked, no report; a signed-in person files no gap', async () => {
  for (const o of [{ grounded: true }, { live: true }]) {
    const s = stub();
    const e = await widgetReplyEffects(s.rpc, { ...base, ...o, askedForAPerson: () => Promise.resolve(false) });
    assertEquals(await e.person, false);
    assertEquals(e.gapTaskId, null);
    assertEquals(s.calls.length, 0, JSON.stringify(s.calls));
  }
});

Deno.test('the person decision failing never fails the reply', async () => {
  const s = stub();
  const e = await widgetReplyEffects(s.rpc, { ...base, grounded: true, askedForAPerson: () => Promise.reject(new Error('gateway down')) });
  assertEquals(await e.person, false);
});

// THE WIRING. site_assistant has two exits that answer a visitor: the composed reply (781) and the canned road.
// Each must pass through widgetReplyEffects before it returns, or the two side effects above are skipped again.
Deno.test('site_assistant: the composed reply and the canned road both file the side effects before returning', async () => {
  const src = await Deno.readTextFile(new URL('../site_assistant/index.ts', import.meta.url));
  const call = /await widgetReplyEffects\(/g;
  const start = src.indexOf("sr.path === 'reasoned'");
  assert(start > 0, 'the composed-reply branch was not found');
  const reasonedExit = src.indexOf('return J(', start);
  assert(call.test(src.slice(start, reasonedExit)), 'the composed reply returns without filing the gap or the person report');
  const lastExit = src.lastIndexOf('return J({ reply');
  call.lastIndex = 0;
  assert(call.test(src.slice(reasonedExit, lastExit)), 'the canned road returns without filing the gap or the person report');
});
