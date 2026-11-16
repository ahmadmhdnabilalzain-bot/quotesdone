// Ruling 1635: every conversation is a case; a reply works from the case summary; a summary records only what we said.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { caseBlock, CASE_TURNS, checkSummary, chooseCase, decideAfterReply, namedCase, readCase, renderSummary, settleExchange, summariseExchange, type OpenCase } from './support_case_memory.ts';
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

// 12 Nov 2026 (final audit W3): the read before the reply is ONE database call and no model (readCase replaced caseMemoryFor,
// which decided and routed before the reply and lost a 4 s race every time on production).
Deno.test('before the SQL is applied (or a read fails) there is no case memory, and the reply reads the whole chat as before', async () => {
  const a = deps({ rpc: (fn) => fn === 'fn_support_open_cases' ? { data: null, error: { message: 'function does not exist' } } : null });
  assertEquals(await readCase(a.d, { message: 'hi', audience: 'customer', phone: '+971500000001' }), null);
  const b = deps({ rpc: (fn) => fn === 'fn_support_open_cases' ? { data: { profile: 7, cases: [invoice, windows] }, error: null } : null });
  const r = await readCase(b.d, { message: 'about QD-C1001', audience: 'customer', phone: '+971500000001' });
  assertEquals(r?.memory, { ref: 'QD-C1001', summaryText: windows.summary_text!, version: 2, profile: 7 }, 'the case the message names');
  // review of 12 Nov 2026: two recorded matters and none named: no single case (the newest is not the matter the message is about)
  assertEquals((await readCase(b.d, { message: 'any news?', audience: 'customer', phone: '+971500000001' }))?.memory, null, 'not the wrong case');
  const one = deps({ rpc: (fn) => fn === 'fn_support_open_cases' ? { data: { profile: 7, cases: [{ ...invoice, summary_text: null, summary_version: 0 }, windows] }, error: null } : null });
  assertEquals((await readCase(one.d, { message: 'any news?', audience: 'customer', phone: '+971500000001' }))?.memory?.ref, 'QD-C1002', 'one recorded matter at most: the newest open case');
  assertEquals(b.calls.filter((c) => c.o).length, 0, 'no model before the reply');
  assertEquals(b.calls.map((c) => c.fn), ['fn_support_open_cases', 'fn_support_open_cases'], 'and nothing is routed before the reply');
});

Deno.test('after the reply: code decides where it can (no case, a named case, nothing recorded yet, the opening exchange); the model only past that', async () => {
  const now = Date.parse('2026-11-12T10:00:00Z');
  const blank: OpenCase = { case_ref: 'QD-C3000', title: null, summary_text: null, summary_version: 0, last_activity_at: '2026-11-12T09:59:00Z' };
  const opening: OpenCase = { case_ref: 'QD-C3001', title: 'Greeting', summary_text: 'ASKED: said hello', summary_version: 1, last_activity_at: '2026-11-12T09:58:00Z' };
  const m = deps({ answer: 'new' });
  assertEquals(await decideAfterReply(m.d, { message: 'hi', cases: [], audience: 'customer', now }), { choice: 'new', by: 'code' });
  assertEquals(await decideAfterReply(m.d, { message: 'a new job', cases: [blank], audience: 'customer', now }), { choice: 'continue', case_ref: 'QD-C3000', by: 'code' });
  assertEquals(await decideAfterReply(m.d, { message: 'I need 12 windows', cases: [opening], audience: 'customer', now }), { choice: 'continue', case_ref: 'QD-C3001', by: 'code' });
  assertEquals(m.calls.filter((c) => c.o).length, 0, 'none of those asked a model');
  assertEquals(await decideAfterReply(m.d, { message: 'a different job: painting', cases: [windows], audience: 'customer', now }), { choice: 'new', by: 'model' });
  const unsure = deps({ answer: 'unsure' });
  const old: OpenCase = { ...windows, last_activity_at: '2026-10-01T09:00:00Z' };
  assertEquals((await decideAfterReply(unsure.d, { message: 'hello again', cases: [old], audience: 'customer', now })).choice, 'continue', 'after the reply nobody is left to ask: continue');
});

Deno.test('the summary after the reply is retried: a stale version is read again and written on top; a failure after every try is raised', async () => {
  let version = 2;
  const writes: unknown[] = []; const findings: unknown[] = [];
  const a = deps({ content: JSON.stringify({ title: 'Windows quote', asked: 'a quote', said_or_did: 'asked sizes', promised: [], open: [] }),
    rpc: (fn, args) => {
      if (fn === 'fn_support_open_cases') return { data: { profile: 7, cases: [{ ...windows, summary_version: version }] }, error: null };
      if (fn === 'fn_support_case_route') return { data: { ok: true, case_ref: 'QD-C1001' }, error: null };
      if (fn === 'fn_support_case_summary_write') {
        writes.push(args.p_expected_version);
        if (writes.length === 1) { version = 3; return { data: { ok: false, reason: 'stale', version: 3 }, error: null }; }   // another exchange wrote first
        return { data: { ok: true, version: 4 }, error: null };
      }
      if (fn === 'fn_it_engineer_finding_upsert') { findings.push(args.p_issue_key); return { data: null, error: null }; }
    } });
  const r = await settleExchange(a.d, { channel: 'whatsapp', audience: 'customer', phone: '+971500000001', message: 'about QD-C1001: bronze', ourReply: 'Noted.' });
  assertEquals([r.ok, r.ref, r.tries], [true, 'QD-C1001', 2]);
  assertEquals(writes, [2, 3], 'the second try wrote on the version it read again');
  assertEquals(findings, []);
  const bad = deps({ content: 'not json', rpc: (fn, args) => fn === 'fn_support_open_cases' ? { data: { profile: 7, cases: [windows] }, error: null }
    : fn === 'fn_support_case_route' ? { data: { ok: true, case_ref: 'QD-C1001' }, error: null }
    : fn === 'fn_it_engineer_finding_upsert' ? (findings.push(args.p_issue_key), { data: null, error: null }) : null });
  const f = await settleExchange(bad.d, { channel: 'whatsapp', audience: 'customer', phone: '+971500000001', message: 'about QD-C1001', ourReply: 'Noted.' });
  assertEquals([f.ok, f.tries], [false, 3]);
  assertEquals(findings, ['support_case:summary_not_written']);
});

// Final audit 12 Nov 2026, integration F12 (proof p4 F-PROMISE): the check compared with the whole previous summary, whose ASKED
// line holds what the CUSTOMER said, so "you promised a refund of AED 500 by Friday" became our promise. Fails on main.
Deno.test('a promise the customer claimed is never recorded as ours; one our reply makes, or the summary already holds, is', () => {
  const previousText = ['ASKED: The customer says QuotesDone promised to refund AED 500 by Friday and wants it paid.', 'WE SAID OR DID: We said the team will look into the payment.',
    'WE PROMISED:\n- send the comparison report (by Thursday)', 'STILL OPEN:\n- nothing'].join('\n');
  const model = { asked: 'The refund', said_or_did: 'We acknowledged the message.', open: [],
    promised: [{ what: 'refund AED 500', by: 'Friday', kind: 'other' }, { what: 'send the comparison report', by: 'Thursday', kind: 'other' }, { what: 'reply here by 5 pm today', by: '5 pm today', kind: 'other' }] };
  const checked = checkSummary(model, { ourReply: 'Thank you. A member of the team will reply here by 5 pm today.', previous: null, previousText });
  assertEquals(checked?.promised.map((p) => [p.what, p.by]), [['send the comparison report', 'Thursday'], ['reply here by 5 pm today', '5 pm today']]);
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
  // 12 Nov 2026: the read before the reply names the quiet case by code (no model before the reply); the route is after it
  const mem = (await readCase(d, { message: 'hello again', audience: 'customer', phone: '+971500000061' }))?.memory;
  assertEquals(routed.length, 0, 'nothing is routed before the reply');
  assert(mem?.confirm && mem.summaryText, 'a case with no summary yet is still named by its title');
  const block = caseBlock(mem!);
  assert(block.includes('ask ONE short question') && block.includes('Aluminium windows') && block.includes('QD-C1001'), block);
  assert(!caseBlock({ ref: 'QD-C1001', summaryText: 'ASKED: x' }).includes('ask ONE short question'), 'a plain continue is unchanged');
});

// Review of 12 Nov 2026 (note 7): fn_support_touch now keeps a quiet case open on arrival and moves its last_activity_at to now,
// keeping the earlier time in prior_activity_at; the reply's question naming the quiet case reads that.
Deno.test('a returning person after 9 quiet days: the reply is handed the quiet case to ask about', async () => {
  const now = Date.parse('2026-11-12T10:00:00Z');
  const quiet: OpenCase = { ...windows, title: 'Aluminium windows', last_activity_at: '2026-11-12T09:59:59Z', prior_activity_at: '2026-11-03T09:00:00Z' };
  const d = deps({ rpc: (fn) => fn === 'fn_support_open_cases' ? { data: { profile: 7, cases: [quiet] }, error: null } : null }).d;
  const mem = (await readCase(d, { message: 'hello again', audience: 'customer', phone: '+971500000061', now }))?.memory;
  assertEquals(mem?.confirm?.days, 9);
  const active = deps({ rpc: (fn) => fn === 'fn_support_open_cases' ? { data: { profile: 7, cases: [{ ...quiet, prior_activity_at: '2026-11-12T09:58:00Z' }] }, error: null } : null }).d;
  assertEquals((await readCase(active, { message: 'and the colour?', audience: 'customer', phone: '+971500000061', now }))?.memory?.confirm, undefined);
});

// Re-check of 12 Nov 2026, R8: the ledger filled with boilerplate, each due in 48 hours. A condition, an event we do not control,
// or an answer given at once is not a dated promise. Fails on dc9a17b75 (all five recorded).
Deno.test('a conditional, event-bound or immediate sentence is never recorded as a promise; a real one is', () => {
  const reply = 'I will answer it straight away. We will let you know the moment it opens. Reply REGISTER and I will send him the link. ننبهكم فور وصول كل عرض. We will send you the comparison report by Thursday.';
  const s = checkSummary({ asked: 'x', said_or_did: 'y', open: [], promised: [
    { what: 'answer it straight away', by: null }, { what: 'let you know the moment it opens', by: null },
    { what: 'reply REGISTER and I will send him the link', by: null }, { what: 'ننبهكم فور وصول كل عرض', by: null },
    { what: 'send you the comparison report', by: 'Thursday' }] }, { ourReply: reply });
  assertEquals(s?.promised.map((p) => p.what), ['send you the comparison report']);
});

// Re-check R6: the summary slowed as the case grew (6.5 s to 43.1 s). It reads the previous summary and this exchange only.
Deno.test('the summary after a reply reads the previous summary, this exchange and the one before it, bounded', async () => {
  let input = '';
  const a = deps({ content: JSON.stringify({ title: 't', asked: 'a', said_or_did: 's', promised: [], open: [] }),
    rpc: (fn) => fn === 'fn_support_open_cases' ? { data: { profile: 7, cases: [windows] }, error: null }
      : fn === 'fn_support_case_route' ? { data: { ok: true, case_ref: 'QD-C1001' }, error: null }
      : fn === 'fn_support_case_summary_write' ? { data: { ok: true }, error: null } : null });
  const llm = a.d.llm;
  (a.d as unknown as { llm: unknown }).llm = (p: never, sys: string, i: string, o: Record<string, unknown>) => { if (o.taskClass === 'case_summary') input = i; return llm(p, sys, i, o as never); };
  await settleExchange(a.d, { channel: 'whatsapp', audience: 'customer', phone: '+971500000001', message: 'about QD-C1001 ' + 'x'.repeat(5000), ourReply: 'y'.repeat(5000), recent: 'THEM: an old turn' });
  // review of branch B: the exchange BEFORE this one is read (so a lost summary is caught up), nothing older
  assert(input.includes('an old turn'), 'the previous exchange is read');
  assert(input.length < 2000 + 1500 + 1500 + 1000 + 300, 'bounded: ' + input.length);
  const { previousExchange } = await import('./support_case_memory.ts');
  assertEquals(previousExchange('THEM: one\nUS: r1\nTHEM: two\nUS: r2'), 'THEM: two\nUS: r2', 'only the last exchange');
});

// Re-check of 12 Nov 2026, R7: a case is a matter, not a question (3 cases for one supplier's general questions). The decision is
// told so. The effect on the model is a paid measurement (listed in the hand-back); this pins the instruction. Fails on dc9a17b75.
Deno.test('the same-matter decision is told that a further question about the same job or their own account is the same matter', async () => {
  const a = deps({ answer: 'continue:QD-C1001' });
  await chooseCase(a.d, { message: 'and how do I update my profile photos?', cases: [windows], audience: 'supplier' });
  assert(a.calls.find((c) => c.o)!.system!.includes('their own account, registration, fees or profile is NOT a new matter'));
});

// Review of branch B (12 Nov 2026), item 9: a promise with a date is kept whatever else it says (English and Arabic); one without a
// date that is conditional, event-bound or immediate is not. Fails on c4a467389 (the dated ones were dropped).
Deno.test('a promise with a date is kept even when it also says right away, if or once; undated boilerplate is not', () => {
  const reply = 'I will call the supplier right away and update you by 6 pm. I will check with the supplier and come back to you by Sunday if they agree. سنرسل لكم التقرير غدًا. I will answer it straight away. ننبهكم فور وصول كل عرض.';
  const s = checkSummary({ asked: 'x', said_or_did: 'y', open: [], promised: [
    { what: 'call the supplier right away and update you by 6 pm', by: null }, { what: 'come back to you by Sunday if they agree', by: null },
    { what: 'سنرسل لكم التقرير غدًا', by: null }, { what: 'answer it straight away', by: null }, { what: 'ننبهكم فور وصول كل عرض', by: null }] }, { ourReply: reply });
  assertEquals(s?.promised.map((p) => p.what), ['call the supplier right away and update you by 6 pm', 'come back to you by Sunday if they agree', 'سنرسل لكم التقرير غدًا']);
});

// 16 Nov 2026 (ledger 1711): the case block points at the request facts, the record of what he told the sales engineer.
Deno.test('the case block names the request facts as the record of what he asked', async () => {
  const { REQUEST_IS_THE_RECORD } = await import('./support_case_memory.ts');
  const b = caseBlock({ ref: 'QD-C1001', summaryText: 'ASKED: status' });
  assert(b.includes(REQUEST_IS_THE_RECORD) && b.includes('`asked`') && b.includes('`changes_he_sent_after`'));
  assert(b.indexOf(REQUEST_IS_THE_RECORD) < b.indexOf('ASKED: status'), 'the pointer comes before the summary');
});
