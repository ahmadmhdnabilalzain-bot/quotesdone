// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/job_question.test.ts
//
// A JOB QUESTION FROM ANY CHANNEL IS READ BY THE SALES ENGINEER FIRST (16 Nov 2026, SUPPLIER hole 5; agent SUPPLIER_W2). Before:
// only the portal wrote rfq_clarification, the customer was e-mailed at once with no first look and no reminder, and nobody else saw
// an answer. Stub model, stub tables, ZZ DEMO values.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { chaseCustomer, factsOf, FIRST_ANSWER_SYS, firstAnswer, readFirstAnswer, seAnswerMail } from './job_question.ts';

type Row = Record<string, unknown>;
function world(over: Partial<Record<string, Row | Row[]>> = {}) {
  const t: Record<string, Row | Row[]> = {
    rfq_clarification: { id: 9, inquiry_id: 'i-1', supplier_id: 7, question: 'Is the old tile to be removed?', asked_at: '2026-11-16T08:00:00Z', answered_at: null, se_read_at: null, customer_chased_at: null },
    inquiries: { id: 'i-1', category: 'tiling', emirate: 'Dubai', status: 'sent', customer_id: 'c-1', spec: { scope_detail: 'remove existing floor tiles and lay 60x60 porcelain', area: '40 m2' }, project_id: null, brief_source: null },
    customers: { email: 'zz-demo-c@example.invalid', full_name: 'ZZ DEMO Customer', locale: 'en' },
    ...over,
  };
  const updates: { table: string; set: Row }[] = [];
  const queued: Row[] = [];
  // deno-lint-ignore no-explicit-any
  const from = (table: string): any => {
    let pendingSet: Row | null = null;
    const c: Record<string, unknown> = {};
    const self = () => c;
    Object.assign(c, {
      select: self, eq: self, is: self, not: self, in: self, limit: self, order: self, gte: self,
      update: (set: Row) => { pendingSet = set; updates.push({ table, set }); return c; },
      insert: (rows: Row | Row[]) => { if (table === 'notifications' || table === 'notification_requests') queued.push(...(Array.isArray(rows) ? rows : [rows])); return { select: () => ({ single: () => Promise.resolve({ data: { id: 1 }, error: null }) }), then: (f: (v: unknown) => unknown) => Promise.resolve({ error: null }).then(f) }; },
      maybeSingle: () => Promise.resolve({ data: Array.isArray(t[table]) ? (t[table] as Row[])[0] ?? null : t[table] ?? null, error: null }),
      single: () => Promise.resolve({ data: t[table] ?? null, error: null }),
      then: (f: (v: unknown) => unknown) => Promise.resolve(pendingSet ? { data: [{ id: 9 }], error: null } : { data: Array.isArray(t[table]) ? t[table] : t[table] ? [t[table]] : [], error: null }).then(f),
    });
    return c;
  };
  const rpc = (fn: string) => Promise.resolve({ data: fn === 'fn_quote_labels_record' ? null : null, error: null });
  return { from, rpc, updates, queued, storage: { from: () => ({}) } };
}

Deno.test('the reader is told to answer only from the request and to name nobody; the facts are the scope as suppliers see it', () => {
  assertMatch(FIRST_ANSWER_SYS, /using ONLY those facts/);
  assertMatch(FIRST_ANSWER_SYS, /Never name the customer, the site address, another supplier or any price/);
  const f = factsOf({ id: 'i-1', category: 'tiling', emirate: 'Dubai', spec: { scope_detail: 'remove existing tiles' }, status: 'sent', customer_id: 'c' }, [{ question: 'Q1', answer: 'A1' }]);
  assertMatch(f, /remove existing tiles/);
  assertMatch(f, /Q: Q1 A: A1/);
});

Deno.test('EN: the scope answers "is the old tile removed?": answered by the sales engineer for every bidder, the customer not asked', async () => {
  const w = world();
  const out = await firstAnswer(w, () => Promise.resolve('{"verdict":"answered","answer":"The request states that the existing floor tiles are to be removed."}'), 9);
  assertEquals(out.verdict, 'answered');
  const set = w.updates.find((u) => u.table === 'rfq_clarification')!.set;
  assertEquals([set.answered_by, set.se_verdict], ['sales_engineer', 'answered']);
  assertMatch(String(set.answer), /existing floor tiles are to be removed/);
  assert(!w.queued.some((r) => r.to_role === 'customer'), 'the customer is not bothered with what the request already says');
});

Deno.test('AR question, facts silent: "هل يوجد مصعد للمواد؟" goes to the customer once, by the letter, and is marked read', async () => {
  const w = world({ rfq_clarification: { id: 9, inquiry_id: 'i-1', supplier_id: 7, question: 'هل يوجد مصعد للمواد؟', answered_at: null, se_read_at: null } });
  const out = await firstAnswer(w, () => Promise.resolve('{"verdict":"ask_customer","answer":null}'), 9);
  assertEquals(out.verdict, 'ask_customer');
  const set = w.updates.find((u) => u.table === 'rfq_clarification' && u.set.se_read_at)!.set;
  assertEquals(set.se_verdict, 'ask_customer');
});

Deno.test('the model unavailable: the question still reaches the customer (never lost), recorded as unreadable', async () => {
  const w = world();
  const out = await firstAnswer(w, () => Promise.resolve(null), 9);
  assertEquals(out.verdict, 'unreadable');
  assert(w.updates.some((u) => u.table === 'rfq_clarification' && u.set.se_verdict === 'unreadable'));
});

Deno.test('a question already answered or already read is not read twice', async () => {
  const w = world({ rfq_clarification: { id: 9, inquiry_id: 'i-1', supplier_id: 7, question: 'x', answered_at: '2026-11-16', se_read_at: null } });
  assertEquals((await firstAnswer(w, () => Promise.resolve('{"verdict":"answered","answer":"y"}'), 9)).verdict, 'gone');
  assertEquals(w.updates.length, 0);
});

Deno.test('the reminder goes once: chaseCustomer marks customer_chased_at before it writes, and an answered question is never chased', async () => {
  const w = world();
  await chaseCustomer(w, 9);
  assert(w.updates.some((u) => u.table === 'rfq_clarification' && u.set.customer_chased_at));
  const done = world({ rfq_clarification: { id: 9, inquiry_id: 'i-1', supplier_id: 7, question: 'x', answered_at: '2026-11-16', customer_chased_at: null } });
  assertEquals(await chaseCustomer(done, 9), false);
});

Deno.test('a reading with an unparseable answer is unreadable; an "answered" with no text is asking the customer', async () => {
  assertEquals(await readFirstAnswer(() => Promise.resolve('no json'), 'q', 'f'), null);
  assertEquals((await readFirstAnswer(() => Promise.resolve('{"verdict":"answered","answer":""}'), 'q', 'f'))?.verdict, 'ask_customer');
  assertMatch(seAnswerMail({ category: 'tiling', emirate: 'Dubai' }, 'Q?', 'A.').body, /Our sales engineer answered from the request's own details/);
});

Deno.test('a CUSTOMER\'s question about one quote (asked_by customer) is never answered to every bidder nor put back to him (review customerw2)', async () => {
  const w = world({ rfq_clarification: { id: 9, inquiry_id: 'i-1', supplier_id: 7, question: 'Does your price include the valves?', asked_by: 'customer', answered_at: null, se_read_at: null, customer_chased_at: null } });
  let asked = false;
  const out = await firstAnswer(w, () => { asked = true; return Promise.resolve('{"verdict":"answered","answer":"Yes."}'); }, 9);
  assertEquals(out.verdict, 'gone');
  assert(!asked, 'the model is not even asked');
  assertEquals(await chaseCustomer(w, 9), false);
  assertEquals([w.updates.length, w.queued.length], [0, 0], 'nothing written, nobody told');
});
