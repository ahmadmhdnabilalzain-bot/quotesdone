// Ruling 1635: every conversation is a case; a reply works from the case summary; a summary records only what we said.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { caseBlock, caseMemoryFor, CASE_TURNS, checkSummary, chooseCase, namedCase, renderSummary, summariseExchange, type OpenCase } from './support_case_memory.ts';
import { aiReply } from './ai_reply.ts';
import type { LlmReply, ThinkDeps } from './think.ts';

const windows: OpenCase = { case_ref: 'QD-C1001', title: 'Windows quote', summary_text: 'ASKED: a quote for 14 aluminium windows', summary_version: 2 };
const invoice: OpenCase = { case_ref: 'QD-C1002', title: 'Reveal invoice', summary_text: 'ASKED: a copy of the reveal invoice', summary_version: 1 };

// deno-lint-ignore no-explicit-any
const deps = (o: { rpc?: (fn: string, a: any) => any; answer?: string; content?: string } = {}) => {
  const calls: { fn?: string; system?: string; o?: Record<string, unknown>; input?: string }[] = [];
  const d = {
    rpc: (fn: string, a: Record<string, unknown>) => { calls.push({ fn }); return Promise.resolve(o.rpc?.(fn, a) ?? { data: null, error: null }); },
    llm: (_p: string, system: string, input: string, opts: Record<string, unknown>) => {
      calls.push({ system, o: opts, input });
      return Promise.resolve({ content: o.content ?? JSON.stringify({ answer: 'x', decision: { choice: o.answer ?? 'new' } }), model: 'openai/gpt-6-luna-pro' } as LlmReply);
    },
    embed: () => Promise.resolve(null),
  } as unknown as ThinkDeps;
  return { d, calls };
};

Deno.test('the decision: no open case opens a new one, a named case number continues it, both without a model', async () => {
  const a = deps();
  assertEquals(await chooseCase(a.d, { message: 'hi', cases: [], audience: 'customer' }), { choice: 'new', by: 'code' });
  assertEquals(await chooseCase(a.d, { message: 'about qd-c1002 please', cases: [windows, invoice], audience: 'customer' }), { choice: 'continue', case_ref: 'QD-C1002', by: 'code' });
  assertEquals(a.calls.filter((c) => c.o).length, 0, 'no model call');
  assertEquals(namedCase('QD-C9999', [windows]), null, 'a number that is not theirs is not followed');
});

Deno.test('the decision is given ONLY the open cases (number, title, summary), at medium effort, and an unknown answer is never followed', async () => {
  const a = deps({ answer: 'continue:QD-C1002' });
  assertEquals(await chooseCase(a.d, { message: 'can you resend it?', cases: [windows, invoice], audience: 'customer' }), { choice: 'continue', case_ref: 'QD-C1002', by: 'model' });
  const call = a.calls.find((c) => c.o)!;
  assertEquals(call.o!.effort, 'medium');
  assert(call.system!.includes('QD-C1001') && call.system!.includes('a copy of the reveal invoice'));
  const b = deps({ answer: 'continue:QD-C7777' });
  assertEquals((await chooseCase(b.d, { message: 'x', cases: [windows], audience: 'customer' })).choice, 'continue', 'unknown: the newest open case, as fn_support_touch did');
  const c = deps({ answer: 'new' });
  assertEquals(await chooseCase(c.d, { message: 'a new job: painting', cases: [windows], audience: 'customer' }), { choice: 'new', by: 'model' });
});

Deno.test('code checks the summary: a promise or a date our reply never stated is dropped; an earlier promise is kept', () => {
  const s = checkSummary({ asked: 'a quote for 14 windows', said_or_did: 'asked for the sizes',
    promised: [{ what: 'send the quotes as they arrive', by: 'Thursday' }, { what: 'give a 10% discount', by: null }, 'call them tomorrow'],
    open: ['the sizes'] }, { ourReply: 'Thank you. We will send the quotes as they arrive, usually within 3-5 working days.', previousText: 'WE PROMISED:\n- call them tomorrow' });
  assert(s);
  assertEquals(s!.promised.map((p) => p.what), ['send the quotes as they arrive', 'call them tomorrow'], 'the invented discount is dropped');
  assertEquals(s!.promised[0].by, null, 'Thursday was never said');
  assertEquals(checkSummary({ asked: 1 }, { ourReply: '' }), null);
  const text = renderSummary(s!);
  assert(text.startsWith('ASKED: a quote for 14 windows') && text.includes('WE PROMISED:') && text.includes('STILL OPEN:\n- the sizes'));
});

Deno.test('the summary step writes through the versioned writer, with the version it read', async () => {
  let wrote: Record<string, unknown> | null = null;
  const a = deps({ content: JSON.stringify({ title: 'Windows quote', asked: 'a quote', said_or_did: 'asked sizes', promised: [], open: ['sizes'] }),
    rpc: (fn, args) => { if (fn === 'fn_support_case_summary_write') { wrote = args; return { data: { ok: true }, error: null }; } } });
  const r = await summariseExchange(a.d, { memory: { ref: 'QD-C1001', summaryText: '', version: 2, profile: 7 }, theirMessage: 'hi', ourReply: 'What sizes?' });
  assertEquals(r.ok, true);
  assertEquals(wrote!.p_expected_version, 2);
  assertEquals(a.calls.find((c) => c.o)!.o!.taskClass, 'case_summary');
  const bad = deps({ content: 'not json' });
  assertEquals((await summariseExchange(bad.d, { memory: { ref: 'x', summaryText: '', version: 0, profile: 1 }, theirMessage: 'a', ourReply: 'b' })).ok, false);
});

Deno.test('before the SQL is applied (or a read fails) there is no case memory, and the reply reads the whole chat as before', async () => {
  const a = deps({ rpc: (fn) => fn === 'fn_support_open_cases' ? { data: null, error: { message: 'function does not exist' } } : null });
  assertEquals(await caseMemoryFor(a.d, { message: 'hi', channel: 'whatsapp', audience: 'customer', phone: '+971500000001' }), null);
  const b = deps({ rpc: (fn) => fn === 'fn_support_open_cases' ? { data: { profile: 7, cases: [windows] }, error: null }
    : fn === 'fn_support_case_route' ? { data: { ok: true, case_ref: 'QD-C1001' }, error: null } : null });
  assertEquals(await caseMemoryFor(b.d, { message: 'about QD-C1001', channel: 'whatsapp', audience: 'customer', phone: '+971500000001' }),
    { ref: 'QD-C1001', summaryText: windows.summary_text!, version: 2, profile: 7 });
});

Deno.test('the reply works from the case: its summary inside the cached system prompt, and only the last turns of the chat', async () => {
  const conversation = Array.from({ length: 20 }, (_, i) => ({ role: i % 2 ? 'seat' as const : 'customer' as const, text: 'turn ' + i }));
  const seen: { system: string; o: Record<string, unknown> }[] = [];
  const d = {
    rpc: (fn: string) => Promise.resolve({ data: fn === 'fn_company_context' ? { block: 'REVEAL FEE: 3%.' } : fn === 'fn_ai_route' ? { model: 'openai/gpt-6-luna-pro' } : null, error: null }),
    llm: (_p: string, system: string, _i: string, o: Record<string, unknown>) => { seen.push({ system, o }); return Promise.resolve({ content: JSON.stringify({ answer: 'We will send them as they arrive.', escalate: false }), model: 'openai/gpt-6-luna-pro' } as LlmReply); },
  } as unknown as ThinkDeps;
  await aiReply(d, { seat: 'customer_support', channel: 'WhatsApp', audience: 'customer', lang: 'en', message: 'any news?', conversation,
    caseMemory: { ref: 'QD-C1001', summaryText: windows.summary_text! } } as never);
  assert(seen[0].system.includes(caseBlock({ ref: 'QD-C1001', summaryText: windows.summary_text! })), 'the case block is in the system prompt');
  assertEquals((seen[0].o.history as unknown[]).length, CASE_TURNS, 'the last turns only, not all 20');
  seen.length = 0;
  await aiReply(d, { seat: 'customer_support', channel: 'WhatsApp', audience: 'customer', lang: 'en', message: 'any news?', conversation } as never);
  assertEquals((seen[0].o.history as unknown[]).length, 20, 'no case summary: the whole conversation, as before');
});

// it_engineer, 11 Nov 2026: a returning person, a different matter? After a long gap and an unsure router, ASK (outcome 'confirm').
// Known-bad control: without the gap test an unsure router after 30 days continues the old case silently (the first assert fails).
Deno.test("confirm: after 7+ quiet days an unsure router asks one question naming the case; a recent case, or a sure router, does not", async () => {
  const now = Date.parse('2026-11-11T10:00:00Z');
  const old: OpenCase = { ...windows, title: 'Aluminium windows', last_activity_at: '2026-10-12T09:00:00Z' };
  const recent: OpenCase = { ...windows, last_activity_at: '2026-11-09T09:00:00Z' };
  assertEquals(await chooseCase(deps({ answer: 'unsure' }).d, { message: 'hi, any update?', cases: [old], audience: 'customer', now }),
    { choice: 'confirm', case_ref: 'QD-C1001', by: 'model', days: 30 });
  assertEquals((await chooseCase(deps({ answer: 'unsure' }).d, { message: 'hi', cases: [recent], audience: 'customer', now })).choice, 'continue');
  assertEquals((await chooseCase(deps({ answer: 'continue:QD-C1001' }).d, { message: 'the windows again', cases: [old], audience: 'customer', now })).choice, 'continue', 'sure: no question');
  assertEquals((await chooseCase(deps({ answer: 'new' }).d, { message: 'a new job', cases: [old], audience: 'customer', now })).choice, 'new');
  assertEquals((await chooseCase(deps({ answer: 'unsure' }).d, { message: 'about QD-C1001', cases: [old], audience: 'customer', now })).choice, 'continue', 'a named case is never asked about');
  const asked = deps({ answer: 'unsure' });
  await chooseCase(asked.d, { message: 'x', cases: [old], audience: 'customer', now });
  assert(asked.calls.find((c) => c.o)!.system!.includes('unsure'), 'the decision offers "unsure"');
});

Deno.test('confirm reaches the reply: filed on the case it asks about, and the prompt asks the one question instead of answering from it', async () => {
  const old: OpenCase = { ...windows, title: 'Aluminium windows', summary_text: '', last_activity_at: '2026-10-01T09:00:00Z' };
  const routed: Record<string, unknown>[] = [];
  const d = deps({ answer: 'unsure', rpc: (fn, a) => fn === 'fn_support_open_cases' ? { data: { profile: 7, cases: [old] }, error: null }
    : fn === 'fn_support_case_route' ? (routed.push(a), { data: { case_ref: 'QD-C1001' }, error: null }) : null }).d;
  const mem = await caseMemoryFor(d, { message: 'hello again', channel: 'whatsapp', audience: 'customer', phone: '+971500000061' });
  assertEquals(routed[0].p_choice, 'continue');
  assert(mem?.confirm && mem.summaryText, 'a case with no summary yet is still named by its title');
  const block = caseBlock(mem!);
  assert(block.includes('ask ONE short question') && block.includes('Aluminium windows') && block.includes('QD-C1001'), block);
  assert(!caseBlock({ ref: 'QD-C1001', summaryText: 'ASKED: x' }).includes('ask ONE short question'), 'a plain continue is unchanged');
});
