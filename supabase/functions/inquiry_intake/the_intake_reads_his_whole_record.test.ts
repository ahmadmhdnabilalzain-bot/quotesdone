// The intake chat reads the customer's whole record, as every other door does, and writes its exchange onto his case
// (16 Nov 2026, founder ledgers 1711-1713; WHO_KNOWS_WHAT item 1). Stubbed database and model: no network, no paid call.
// Each test fails if the behaviour it names is removed from inquiry_intake/customer_record.ts or its wiring in handle.ts.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { CASE_READ_MS } from '../_shared/case_context.ts';
import type { LlmReply, ThinkDeps } from '../_shared/think.ts';
import { readCustomerRecord, recordBlock, recordIntakeExchange } from './customer_record.ts';

const CUST = '0d6c3a52-1b7e-4f00-9c1a-1234567890ab';
const REQUEST_1 = { id: 'aaaa1111-0000-0000-0000-000000000000', ref: 'RFQ-1042', category: 'aluminium', emirate: 'Dubai', status: 'sent',
  status_meaning: 'sent to suppliers, waiting for quotes', quotes_received: 0, quotes_wanted: 3, late: true, quotes_due_by: '2026-11-14T08:00:00Z',
  revealed_quotes: [{ supplier: 'Gulf Glass LLC', amount_aed: 9000 }], chase: { state: 'pending' } };
const PROMISE = { case_ref: 'QD-S-WA0001', what: 'update him on the window quotes', due_at: '2026-11-15T14:00:00Z', owner_seat: 'customer_support', overdue: true };
const CASE = { case_ref: 'QD-S-WA0001', title: 'No quotes on RFQ-1042', summary_text: 'ASKED: why no quotes arrived on RFQ-1042\nWE PROMISED:\n- update him on the window quotes',
  summary_version: 2, last_activity_at: new Date().toISOString() };

type Call = { fn: string; args: Record<string, unknown> };
function deps(o: { delayMs?: number; hang?: boolean; fail?: boolean; empty?: boolean } = {}) {
  const calls: Call[] = [];
  const d = {
    rpc: async (fn: string, args: Record<string, unknown>) => {
      calls.push({ fn, args });
      if (o.hang) return await new Promise(() => {});
      if (o.delayMs) await new Promise((r) => setTimeout(r, o.delayMs));
      if (o.fail) throw new Error('connection reset');
      if (fn === 'fn_customer_inquiry_facts') return { data: o.empty ? [] : [REQUEST_1], error: null };
      if (fn === 'fn_person_open_promises') return { data: o.empty ? [] : [PROMISE], error: null };
      if (fn === 'fn_support_open_cases') return { data: { profile: 77, cases: o.empty ? [] : [CASE] }, error: null };
      if (fn === 'fn_support_case_route') return { data: { ok: true, case_ref: CASE.case_ref }, error: null };
      if (fn === 'fn_support_case_summary_write') return { data: { ok: true, version: Number(args.p_expected_version) + 1 }, error: null };
      return { data: null, error: null };
    },
    llm: () => Promise.resolve({ content: JSON.stringify({ title: 'Windows', asked: 'a new request for doors', said_or_did: 'asked the sizes', promised: [], open: ['sizes'] }), model: 'stub' } as LlmReply),
    embed: () => Promise.resolve(null),
  } as unknown as ThinkDeps;
  return { d, calls };
}
const read = (d: ThinkDeps, extra: Partial<Parameters<typeof readCustomerRecord>[1]> = {}) => readCustomerRecord(d, { customerId: CUST,
  email: 'buyer@example.ae', message: 'I also need 3 doors', past: [{ role: 'user', text: 'hello' }, { role: 'assistant', text: 'What do you need?' }],
  lang: 'en', dedupeKey: 'case_match:intake:i1:t2', ...extra });

Deno.test('the prompt gets his earlier requests, his open promises and his case, read as the other doors read them', async () => {
  const f = deps();
  const rec = await read(f.d);
  assertEquals(f.calls.map((c) => c.fn).sort(), ['fn_customer_inquiry_facts', 'fn_escalation_case_facts', 'fn_person_open_promises', 'fn_support_open_cases']);   // + the escalation clock's facts (case_context.ts)
  assertEquals(f.calls.find((c) => c.fn === 'fn_customer_inquiry_facts')?.args, { p_customer: CUST, p_limit: 10 });
  assertEquals(f.calls.find((c) => c.fn === 'fn_person_open_promises')?.args, { p_party_kind: 'customer', p_party_id: CUST, p_email: 'buyer@example.ae', p_phone: null, p_limit: 10 });
  assertEquals(f.calls.find((c) => c.fn === 'fn_support_open_cases')?.args, { p_party_kind: 'customer', p_party_id: CUST, p_email: 'buyer@example.ae', p_phone: null });
  const b = recordBlock(rec);
  assertMatch(b, /RFQ-1042 aluminium, Dubai: sent to suppliers, waiting for quotes; quotes received 0\. LATE: quotes were due by 2026-11-14 08:00 UTC/);
  assertMatch(b, /He already asked us to chase it/);
  assertMatch(b, /update him on the window quotes \(due 2026-11-15 14:00 UTC, customer_support, case QD-S-WA0001\) OVERDUE/);
  assertMatch(b, /THIS CASE \(QD-S-WA0001\)[\s\S]*why no quotes arrived on RFQ-1042/);
  // the rules that keep the record from becoming this request's answers, and from a promise we cannot keep
  assertMatch(b, /never fill its checklist, brief\.details, already_provided or asked_keys from an earlier request/);
  assertMatch(b, /never promise him a time for quotes on this request/);
  assertEquals(/Gulf Glass|9000/.test(b), false, 'no supplier or amount reaches the intake prompt');
});

Deno.test('a first-time customer\'s prompt is unchanged: nothing on record, no block', async () => {
  assertEquals(recordBlock(await read(deps({ empty: true }).d)), '');
  assertEquals(recordBlock(null), '');
  const none = deps();
  assertEquals(recordBlock(await read(none.d, { customerId: null, email: 'no-address' })), '');
  assertEquals(none.calls.length, 0, 'no identity: nothing is read');
});

Deno.test('LATENCY: the turn never waits more than CASE_READ_MS for the record, and a failed read is simply absent', async () => {
  const t0 = performance.now();
  const hung = await read(deps({ hang: true }).d);
  const waited = performance.now() - t0;
  console.log(`record read, database hanging: settled after ${waited.toFixed(0)} ms (bound CASE_READ_MS = ${CASE_READ_MS} ms)`);
  assert(waited < CASE_READ_MS + 250, 'waited ' + waited.toFixed(0) + ' ms');
  assertEquals(recordBlock(hung), '', 'a late read adds nothing to the prompt');
  const failed = await read(deps({ fail: true }).d);
  assertEquals([failed.requests, failed.promises, failed.kase?.memory ?? null], [[], [], null]);
});

Deno.test('LATENCY: started beside the turn\'s own reads, the record adds nothing to the turn', async () => {
  // The intake starts the record before the trade's checklist, questions, specialist, field knowledge (up to 3 s) and state,
  // and reads it only when the prompt is built. Fakes: each record read answers in 120 ms; the turn's own reads take 300 ms.
  const turnsOwnReads = () => new Promise((r) => setTimeout(r, 300));
  const base0 = performance.now(); await turnsOwnReads(); const base = performance.now() - base0;
  const t0 = performance.now();
  const recordP = read(deps({ delayMs: 120 }).d);
  await turnsOwnReads();
  const rec = await recordP;
  const total = performance.now() - t0;
  console.log(`turn's own reads ${base.toFixed(0)} ms; with the record started beside them ${total.toFixed(0)} ms: added ${(total - base).toFixed(0)} ms (record took ${rec.ms} ms)`);
  assert(total - base < 40, 'the record added ' + (total - base).toFixed(0) + ' ms');
  assert(recordBlock(rec).includes('RFQ-1042'), 'and it arrived in time for the prompt');
});

Deno.test('the exchange the intake really gave is written onto his case, after the reply and never awaited', async () => {
  const f = deps();
  const rec = await read(f.d);
  const before = f.calls.length;
  const work = recordIntakeExchange(f.d, rec, { theirMessage: 'I also need 3 doors', ourReply: 'Noted. How wide is each door?', intakeId: 'i1', turnId: 't2' });
  assert(work, 'an identified customer\'s exchange is recorded');
  const r = await work;
  assertEquals(r.ok, true, JSON.stringify(r));
  const after = f.calls.slice(before).map((c) => c.fn);
  assert(after.includes('fn_support_case_route') && after.includes('fn_support_case_summary_write'), after.join(','));
  const route = f.calls.find((c) => c.fn === 'fn_support_case_route')!;
  assertEquals(route.args.p_channel, 'portal');
  assertEquals(recordIntakeExchange(f.d, null, { theirMessage: 'x', ourReply: 'y', intakeId: 'i1', turnId: null }), null, 'no record, nothing written');
});

Deno.test('handle.ts: the record starts before the trade reads, is read at the prompt, and the exchange is never awaited', async () => {
  const src = await Deno.readTextFile(new URL('./handle.ts', import.meta.url));
  const at = (s: string) => { const i = src.indexOf(s); assert(i >= 0, 'missing: ' + s); return i; };
  assert(at('const recordP = readCustomerRecord(') < at('const specsP = '), 'started before the checklist read');
  assert(at('const recordP = readCustomerRecord(') < at('const st = await stateP;'), 'started before the state is awaited');
  assert(at('record = await recordP;') > at('const st = await stateP;'), 'read only when the prompt is built');
  assertMatch(src, /const turnContext = \[[\s\S]{0,600}recordBlock\(record\),/);
  assertEquals(/await\s+(recordExchange|recordIntakeExchange)\(/.test(src), false, 'the case write is never awaited by the turn');
  assert(at('recordExchange(heldMsg);') > 0 && at("recordExchange(String(out.assistant_message || ''));") > at('const { error: saveErr }'), 'recorded after the saved reply');
  // never-ask-twice and asked_keys are untouched (the rules are in intake_prompt.ts since 19 Nov 2026)
  const prompt = await Deno.readTextFile(new URL('./intake_prompt.ts', import.meta.url));
  assertMatch(prompt, /a customer asked twice for the same thing abandons the request/);
  assertMatch(prompt, /In "asked_keys" put the key of each spec your assistant_message asks\./);
});
