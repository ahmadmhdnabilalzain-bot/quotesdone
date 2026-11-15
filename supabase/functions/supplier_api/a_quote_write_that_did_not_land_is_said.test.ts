// A QUOTE WRITE THAT DID NOT LAND IS SAID, NEVER ANSWERED OK (15 Nov 2026, review 2 of the certificate branch, items A, B and C).
//  A. acceptLive: a failed `status = 'submitted'` write was ignored (a try/catch supabase-js never enters), so the supplier was told
//     "accepted" and the customer was told of a draft he could not see. Now: retried once on a blip, then QUOTE_NOT_SENT, no customer
//     notice, and an IT finding.
//  B. writeQuoteLines: the quote_items delete + insert errors were ignored; now both are read and a blip retries the pair.
//  C. acceptLive: a failed inquiries 'quoted' write files a finding; the quotation itself stands.
// The service-role client is replaced by a recorder, so nothing reaches a database; ZZ DEMO ids only.
//   deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-read=. supabase/functions/supplier_api/a_quote_write_that_did_not_land_is_said.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';

Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:9');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-not-a-key');
const waited: Promise<unknown>[] = [];
(globalThis as { EdgeRuntime?: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { waited.push(p); } };
const ctx = await import('./context.ts');
const { acceptLive, writeQuoteLines, QUOTE_NOT_SENT } = await import('./lib/quote_acceptance.ts');

const TIMEOUT = { code: '57014', message: 'canceling statement due to statement timeout' };
type Op = { table: string; op: string; patch?: unknown };
type Fail = (o: Op, n: number) => typeof TIMEOUT | null;
function record(fail: Fail) {
  const rpcs: { fn: string; args: Record<string, unknown> }[] = [];
  const ops: Op[] = [];
  const status: Record<string, string> = {};
  // deno-lint-ignore no-explicit-any
  const a = ctx.admin as any;
  a.rpc = (fn: string, args: Record<string, unknown>) => {
    rpcs.push({ fn, args });
    if (fn === 'fn_quote_structured_score') return Promise.resolve({ data: { submittable: true, score: 80 }, error: null });
    if (fn === 'fn_customer_support_takes_delivery') return Promise.resolve({ data: [{ handoff_id: 1, notification_id: 1, error: null }], error: null });
    return Promise.resolve({ data: { ok: true }, error: null });
  };
  a.from = (table: string) => {
    const o: Op = { table, op: 'select' };
    const answer = () => {
      if (o.op !== 'select') {
        ops.push(o);
        const n = ops.filter((x) => x.table === o.table && x.op === o.op).length;
        const err = fail(o, n);
        if (err) return { data: null, error: err };
        if (o.op === 'update' && table === 'quotes' && (o.patch as { status?: string })?.status) status.q = String((o.patch as { status: string }).status);
        return { data: null, error: null };
      }
      if (table === 'quotes') return { data: { lead_time: '2 weeks', validity: '30 days', warranty: '2 years', status: status.q ?? 'draft' }, error: null };
      if (table === 'quote_items') return { data: [{ unit_price: 380, amount: 12920 }], error: null };
      if (table === 'app_secrets') return { data: { value: 'true' }, error: null };
      if (table === 'inquiries') return { data: { customer_id: 'c-zz', summary: 'ZZ DEMO wall panels' }, error: null };
      if (table === 'customers') return { data: { email: 'zz-demo-customer@example.invalid' }, error: null };
      return { data: null, error: null };
    };
    // deno-lint-ignore no-explicit-any
    const b: any = {
      select: () => b, eq: () => b, in: () => b, is: () => b, order: () => b, limit: () => b,
      update: (p: unknown) => { o.op = 'update'; o.patch = p; return b; },
      delete: () => { o.op = 'delete'; return b; },
      insert: (p: unknown) => { o.op = 'insert'; o.patch = p; return b; },
      maybeSingle: () => Promise.resolve(answer()),
      then: (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve(answer()).then(res, rej),
    };
    return b;
  };
  return { rpcs, ops, status };
}
const QID = 'aaaaaaaa-0000-4000-8000-0000000000d1';
const INQ = 'aaaaaaaa-0000-4000-8000-000000000002';
const findings = (r: ReturnType<typeof record>) => r.rpcs.filter((x) => x.fn === 'fn_it_engineer_finding_upsert');
const told = (r: ReturnType<typeof record>) => r.rpcs.filter((x) => x.fn === 'fn_customer_support_takes_delivery');

Deno.test('A: a submitted write that never lands answers "not sent", tells no customer and tells the IT seat', async () => {
  waited.length = 0;
  const r = record((o) => (o.table === 'quotes' && (o.patch as { status?: string })?.status === 'submitted' ? TIMEOUT : null));
  const out = await acceptLive(QID, INQ, true);
  await Promise.all(waited);
  assertEquals(out.accepted, false, 'the supplier was told accepted');
  assertEquals((out as { code?: string }).code, 'quote_not_sent');
  assertEquals((out as { message?: string }).message, QUOTE_NOT_SENT.message);
  assertMatch(QUOTE_NOT_SENT.message, /NOT sent to the customer/);
  assertEquals(r.ops.filter((o) => o.table === 'quotes' && (o.patch as { status?: string })?.status === 'submitted').length, 2, 'one blip retry, then said');
  assertEquals(told(r).length, 0, 'the customer was told of a quote he cannot see');
  assertEquals(r.ops.filter((o) => o.table === 'inquiries').length, 0, 'the request was marked quoted for a quote that was not sent');
  const f = findings(r);
  assertEquals(f.map((x) => x.args.p_issue_key), ['quote_not_sent:submitted_write']);
  assertEquals((f[0].args.p_evidence as Record<string, unknown>).quote_id, QID);
});

Deno.test('A: a blip on the submitted write that clears on the retry still sends the quotation', async () => {
  let sends = 0;
  const r = record((o) => (o.table === 'quotes' && (o.patch as { status?: string })?.status === 'submitted' && ++sends === 1 ? TIMEOUT : null));
  const out = await acceptLive(QID, INQ, true);
  assertEquals(sends, 2, 'the blip was tried again');
  assertEquals(out.accepted, true);
  assertEquals(r.status.q, 'submitted');
  assertEquals(told(r).length, 1);
  assertEquals(findings(r).length, 0);
});

Deno.test('C: the request not marked quoted files a finding, and the quotation still stands', async () => {
  waited.length = 0;
  const r = record((o) => (o.table === 'inquiries' && o.op === 'update' ? TIMEOUT : null));
  const out = await acceptLive(QID, INQ, true);
  await Promise.all(waited);
  assertEquals(out.accepted, true, 'the quotation itself is live');
  assertEquals(r.status.q, 'submitted');
  assertEquals(told(r).length, 1, 'the customer is told of the live quotation');
  assertEquals(findings(r).map((x) => x.args.p_issue_key), ['inquiry_not_marked_quoted']);
});

Deno.test('B: quotation lines whose delete or insert fails are reported, never ok', async () => {
  const noWait = () => Promise.resolve();
  const rows = [{ quote_id: QID, line_no: 1, description: 'ZZ DEMO panel' }];
  let r = record((o) => (o.table === 'quote_items' && o.op === 'delete' ? TIMEOUT : null));
  let w = await writeQuoteLines(QID, rows, noWait);
  assertEquals(w.ok, false);
  assertEquals(r.ops.filter((o) => o.op === 'insert').length, 0, 'nothing inserted over lines that were not deleted');
  r = record((o) => (o.table === 'quote_items' && o.op === 'insert' ? TIMEOUT : null));
  w = await writeQuoteLines(QID, rows, noWait);
  assertEquals(w.ok, false);
  assert(!w.ok && /statement timeout/.test(w.reason));
});

Deno.test('B: a blip on the insert retries the PAIR, so a lost insert answer never doubles a line', async () => {
  const r = record((o, n) => (o.table === 'quote_items' && o.op === 'insert' && n === 1 ? TIMEOUT : null));
  const w = await writeQuoteLines(QID, [{ quote_id: QID, line_no: 1, description: 'ZZ DEMO panel' }], () => Promise.resolve());
  assertEquals(w.ok, true);
  assertEquals(r.ops.map((o) => o.op), ['delete', 'insert', 'delete', 'insert']);
});

Deno.test('B: submit_quote stops on lines that were not saved, before the gate, and answers quote_not_saved', () => {
  const src = Deno.readTextFileSync(new URL('./actions/quotes.ts', import.meta.url));
  const s = src.slice(src.indexOf("if (action === 'submit_quote')"));
  const write = s.indexOf('linesW = await writeQuoteLines(qid, clean);');
  const refuse = s.indexOf("return J({ ok: false, error: 'quote_not_saved', ...QUOTE_NOT_SAVED, quote_id: qid");
  const gate = s.indexOf('const gctx: Ctx =');
  assert(write > 0 && refuse > write && gate > refuse, 'the refusal sits between the line write and the gate');
  assert(!/catch \(_e\) \{ \/\* \*\/ \}\n\s*\/\/ Preflight \(dry_run\)/.test(s), 'the silent catch around the line write is gone');
  assert(s.includes("if (body.dry_run !== true && results.some((r) => r.not_sent)) return J({ ok: false, error: 'quote_not_sent'"), 'a not-sent option is said');
});
