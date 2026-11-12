// The case model on every channel (ruling 1635): one person, one set of cases, whichever door they write through.
// Each test fails if the behaviour it names is removed from _shared/case_context.ts.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { CASE_READ_MS, hasIdentity, loadCaseContext, recordCaseExchange } from './case_context.ts';
import { CASE_TURNS, type OpenCase } from './support_case_memory.ts';
import type { LlmReply, ThinkDeps } from './think.ts';

const windows: OpenCase = { case_ref: 'QD-C1001', title: 'Windows quote', summary_text: 'ASKED: a quote for 14 aluminium windows\nWE PROMISED:\n- send the quotes as they arrive', summary_version: 3 };
const fresh: OpenCase = { case_ref: 'QD-C1003', title: null, summary_text: null, summary_version: 0 };

type Call = { fn: string; args: Record<string, unknown> } | { llm: true; o: Record<string, unknown>; input: string };
function deps(o: { cases?: OpenCase[]; delayMs?: number; content?: string; route?: string } = {}) {
  const calls: Call[] = [];
  const d = {
    rpc: async (fn: string, args: Record<string, unknown>) => {
      calls.push({ fn, args });
      if (o.delayMs) await new Promise((r) => setTimeout(r, o.delayMs));
      if (fn === 'fn_support_open_cases') return { data: { profile: 41, cases: o.cases ?? [windows] }, error: null };
      if (fn === 'fn_support_case_route') return { data: { ok: true, case_ref: o.route ?? (o.cases ?? [windows])[0]?.case_ref ?? 'QD-C2000' }, error: null };
      if (fn === 'fn_support_case_summary_write') return { data: { ok: true, version: Number(args.p_expected_version) + 1 }, error: null };
      return { data: null, error: null };
    },
    llm: (_p: string, _s: string, input: string, opts: Record<string, unknown>) => {
      calls.push({ llm: true, o: opts, input });
      return Promise.resolve({ content: o.content ?? JSON.stringify({ title: 'Windows quote', asked: 'a quote for windows', said_or_did: 'asked for sizes', promised: [], open: ['sizes'] }), model: 'm' } as LlmReply);
    },
    embed: () => Promise.resolve(null),
  } as unknown as ThinkDeps;
  return { d, calls, rpcs: () => calls.filter((c): c is { fn: string; args: Record<string, unknown> } => 'fn' in c) };
}
const history = Array.from({ length: 14 }, (_, i) => ({ role: i % 2 ? 'assistant' as const : 'user' as const, content: 'turn ' + i }));

Deno.test('an anonymous visitor has no case: nothing is read, and the reply gets its sys and history untouched', async () => {
  const a = deps();
  const k = await loadCaseContext(a.d, { channel: 'widget', seat: 'customer_support', audience: 'visitor', message: 'how does it work?', sys: 'SYS', past: history });
  assertEquals(a.calls.length, 0, 'no read without an identity');
  assertEquals([k.memory, k.withCase, k.sys, k.past.length, k.reply, k.context], [null, false, 'SYS', 14, {}, {}]);
  assertEquals(recordCaseExchange(a.d, k, { theirMessage: 'x', ourReply: 'y' }), null, 'and nothing is summarised');
  assert(!hasIdentity({ phone: '123' }) && hasIdentity({ phone: '+971 50 000 0001' }) && hasIdentity({ email: 'a@b.ae' }) && hasIdentity({ partyId: '7' }));
});

Deno.test('the widget (signed-in customer): the person is resolved by id and e-mail, and a case with a summary replaces the transcript', async () => {
  const a = deps();
  const k = await loadCaseContext(a.d, { channel: 'widget', seat: 'customer_support', audience: 'customer', message: 'any news on QD-C1001?',
    partyId: 'c0ffee00-0000-4000-8000-000000000001', email: 'zz@example.invalid', sys: 'SYS', past: history });
  const open = a.rpcs().find((c) => c.fn === 'fn_support_open_cases')!.args;
  assertEquals([open.p_party_kind, open.p_party_id, open.p_email], ['customer', 'c0ffee00-0000-4000-8000-000000000001', 'zz@example.invalid']);
  // 12 Nov 2026 (final audit W3): nothing is decided or routed before the reply; the channel reaches the route after it
  assertEquals(a.rpcs().map((c) => c.fn), ['fn_support_open_cases'], 'one read before the reply, no route, no model');
  assertEquals(k.memory?.ref, 'QD-C1001');
  assert(k.withCase && k.sys.startsWith('SYS\n\nTHIS CASE (QD-C1001)') && k.sys.includes('send the quotes as they arrive'), 'the summary rides in sys');
  assertEquals(k.past, history.slice(-CASE_TURNS), 'only the last turns, verbatim');
  assertEquals(k.reply.caseMemory?.ref, 'QD-C1001');
  assertEquals(k.context.case?.case_ref, 'QD-C1001');
  await recordCaseExchange(a.d, k, { theirMessage: 'any news on QD-C1001?', ourReply: 'Two quotes are in.' });
  assertEquals(a.rpcs().find((c) => c.fn === 'fn_support_case_route')!.args.p_channel, 'widget');
});

Deno.test('the supplier portal: the supplier is resolved by its lead id; the portal channel is recorded on the case', async () => {
  const a = deps();
  const k = await loadCaseContext(a.d, { channel: 'portal', seat: 'sales_engineer', audience: 'supplier', message: 'job 164941: is my quote complete?', partyId: '30296', email: 'sales@zz-demo.example.invalid' });
  const open = a.rpcs().find((c) => c.fn === 'fn_support_open_cases')!.args;
  assertEquals([open.p_party_kind, open.p_party_id], ['supplier', '30296']);
  await recordCaseExchange(a.d, k, { theirMessage: 'job 164941: is my quote complete?', ourReply: 'It is missing the warranty.' });
  assertEquals(a.rpcs().find((c) => c.fn === 'fn_support_case_route')!.args.p_channel, 'portal');
});

Deno.test('e-mail: the sender is resolved by address alone; a new case (no summary yet) leaves the reply as it was, but is still summarised after', async () => {
  const a = deps({ cases: [], route: 'QD-C2000' });
  const k = await loadCaseContext(a.d, { channel: 'email', seat: 'customer_support', audience: 'customer', message: 'Hello, I need a quote for painting', email: 'owner@zz-demo.example.invalid', sys: 'SYS', past: history });
  const open = a.rpcs().find((c) => c.fn === 'fn_support_open_cases')!.args;
  assertEquals([open.p_party_kind, open.p_party_id, open.p_email], ['customer', null, 'owner@zz-demo.example.invalid']);
  // 12 Nov 2026: no open case yet, so the reply reads none; the new case is opened by code AFTER the reply
  assertEquals([k.memory, k.withCase, k.sys, k.past.length, k.reply], [null, false, 'SYS', 14, {}]);
  const done = await recordCaseExchange(a.d, k, { theirMessage: 'Hello, I need a quote for painting', ourReply: 'Thank you. Which rooms, and what area?' });
  assertEquals(done?.ok, true);
  assertEquals(a.rpcs().find((c) => c.fn === 'fn_support_case_route')!.args.p_choice, 'new', 'no open case: a new one, decided by code');
  const w = a.rpcs().find((c) => c.fn === 'fn_support_case_summary_write')!.args;
  assertEquals([w.p_case_ref, w.p_expected_version, w.p_written_by], ['QD-C2000', 0, 'customer_support']);
});

Deno.test('one person, two doors: the widget and the e-mail of the same customer continue the SAME open case', async () => {
  // the person behind both is one support_customer_profile (fn_support_profile_resolve matches the e-mail to the customer row);
  // what this module must do is hand the resolver the identity each door has, and follow the case it routes to
  const widget = deps(); const mail = deps();
  const w = await loadCaseContext(widget.d, { channel: 'widget', seat: 'customer_support', audience: 'customer', message: 'about QD-C1001', partyId: 'c0ffee00-0000-4000-8000-000000000001', email: 'zz@example.invalid' });
  const m = await loadCaseContext(mail.d, { channel: 'email', seat: 'customer_support', audience: 'customer', message: 'Re: QD-C1001 windows', email: 'zz@example.invalid' });
  assertEquals([w.memory?.ref, m.memory?.ref, w.memory?.profile, m.memory?.profile], ['QD-C1001', 'QD-C1001', 41, 41]);
});

Deno.test('a slow case read never holds the turn: past CASE_READ_MS the reply goes ahead without it', async () => {
  const a = deps({ delayMs: 200 });
  const t0 = Date.now();
  const k = await loadCaseContext(a.d, { channel: 'portal', seat: 'sales_engineer', audience: 'customer', message: 'hi', partyId: 'x', sys: 'SYS', past: history, readMs: 50 });
  assert(Date.now() - t0 < 180, 'returned at the bound');
  assertEquals([k.memory, k.sys, k.past.length], [null, 'SYS', 14]);
  assert(CASE_READ_MS <= 1_500, 'one database read; the bound is not a model\'s');
});

// Final audit 12 Nov 2026 (W3 / integration F2): the portal, the widget and e-mail awaited the same read-and-decide as WhatsApp.
// A decision slower than the bound left the turn with no case, and recordCaseExchange then wrote nothing: no summary, ever.
// Now the read is one call and the decision runs after the reply, however long it takes. Fails on main (no summary written).
Deno.test('a same-matter decision slower than the read bound no longer costs the summary', async () => {
  const slow = deps({ cases: [windows, fresh] });
  const llm = slow.d.llm;
  (slow.d as unknown as { llm: unknown }).llm = async (...a: Parameters<typeof llm>) => { await new Promise((r) => setTimeout(r, 120)); return await llm(...a); };
  const k = await loadCaseContext(slow.d, { channel: 'portal', seat: 'sales_engineer', audience: 'customer', message: 'and the paint?', partyId: 'c', sys: 'SYS', past: history, readMs: 60 });
  assertEquals(k.memory?.ref, 'QD-C1001', 'the reply still has its case (the read is not a model call)');
  const done = await recordCaseExchange(slow.d, k, { theirMessage: 'and the paint?', ourReply: 'We can add painting to the same request.' });
  assertEquals(done?.ok, true);
  assert(slow.rpcs().some((c) => c.fn === 'fn_support_case_summary_write'), 'the summary was written');
});

Deno.test('a read that fails is the pass-through, never an error', async () => {
  const d = { rpc: () => Promise.reject(new Error('down')), llm: () => Promise.reject(new Error('down')), embed: () => Promise.resolve(null) } as unknown as ThinkDeps;
  const k = await loadCaseContext(d, { channel: 'email', seat: 'customer_support', audience: 'customer', message: 'hi', email: 'a@zz.example.invalid', sys: 'S', past: [] });
  assertEquals([k.memory, k.sys], [null, 'S']);
});

Deno.test('after the reply: the seat that answered is the writer (it owns the promises), and nothing is written without a reply', async () => {
  const a = deps({ cases: [fresh] });
  const k = await loadCaseContext(a.d, { channel: 'portal', seat: 'sales_engineer', audience: 'customer', message: 'about QD-C1003', partyId: 'c' });
  assertEquals(recordCaseExchange(a.d, k, { theirMessage: 'about QD-C1003', ourReply: '   ' }), null);
  assertEquals((await recordCaseExchange(a.d, k, { theirMessage: 'about QD-C1003', ourReply: 'We will send the quotes by Thursday.' }))?.ok, true);
  assertEquals(a.rpcs().find((c) => c.fn === 'fn_support_case_summary_write')!.args.p_written_by, 'sales_engineer');
});
