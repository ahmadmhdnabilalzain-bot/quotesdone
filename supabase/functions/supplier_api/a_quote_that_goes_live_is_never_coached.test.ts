// A QUOTE THAT GOES LIVE IS NEVER COACHED (sales_engineer, 12 Nov 2026; final audit customer_journey B3, fix group Q1,
// ledger 1642). acceptLive called fn_quote_coach after the quote reached the customer whenever the structured score said
// "not submittable", so 8 of 8 suppliers were told "your quote needs a few more details before we can send it" in the
// same second the customer received it. Only a draft the accept rule refused is coached.
// Also (M8, integration finding 4): the customer's new_quote notice names its quote, so the duplicate guard can tell two
// suppliers' quotes apart. The service-role client is replaced by a recorder, so nothing reaches a database.
//   deno test --node-modules-dir=none supabase/functions/supplier_api/a_quote_that_goes_live_is_never_coached.test.ts
import { assertEquals } from 'jsr:@std/assert@1';

Deno.env.set('SUPABASE_URL', 'http://zz-demo.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-not-a-key');
const ctx = await import('./context.ts');
const { acceptLive } = await import('./lib/quote_acceptance.ts');

type World = { score: { submittable: boolean; score: number }; requireStructured: boolean; items: unknown[] };
function record(world: World) {
  const rpcs: { fn: string; args: Record<string, unknown> }[] = [];
  const status: Record<string, string> = {};
  // deno-lint-ignore no-explicit-any
  const a = ctx.admin as any;
  a.rpc = (fn: string, args: Record<string, unknown>) => {
    rpcs.push({ fn, args });
    if (fn === 'fn_quote_structured_score') return Promise.resolve({ data: world.score, error: null });
    if (fn === 'fn_customer_support_takes_delivery') return Promise.resolve({ data: [{ handoff_id: 1, notification_id: 1, error: null }], error: null });
    return Promise.resolve({ data: { ok: true }, error: null });
  };
  a.from = (table: string) => {
    let op = 'select'; let patch: Record<string, unknown> | null = null;
    const answer = () => {
      if (op === 'update' && table === 'quotes' && patch?.status) status.q = String(patch.status);
      if (op !== 'select') return { data: null, error: null };
      if (table === 'quotes') return { data: { lead_time: '2 weeks', validity: '30 days', warranty: '2 years', status: status.q ?? 'draft' }, error: null };
      if (table === 'quote_items') return { data: world.items, error: null };
      if (table === 'app_secrets') return { data: { value: world.requireStructured ? 'true' : 'false' }, error: null };
      if (table === 'quote_quality_hold') return { data: null, error: null };
      if (table === 'inquiries') return { data: { customer_id: 'c-zz', summary: 'ZZ DEMO wall panels' }, error: null };
      if (table === 'customers') return { data: { email: 'zz-demo-customer@example.invalid' }, error: null };
      return { data: null, error: null };
    };
    // deno-lint-ignore no-explicit-any
    const b: any = {
      select: () => b, eq: () => b, in: () => b, is: () => b, order: () => b, limit: () => b,
      update: (p: Record<string, unknown>) => { op = 'update'; patch = p; return b; },
      maybeSingle: () => Promise.resolve(answer()),
      then: (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve(answer()).then(res, rej),
    };
    return b;
  };
  return { rpcs, status };
}
const QID = 'aaaaaaaa-0000-4000-8000-0000000000c9';
const INQ = 'aaaaaaaa-0000-4000-8000-000000000001';
const LINES = [{ unit_price: 380, amount: 12920 }];

Deno.test('a quote the accept rule passes goes to the customer and the supplier is not coached, even when the score says "not submittable"', async () => {
  const r = record({ score: { submittable: false, score: 55 }, requireStructured: true, items: LINES });
  const out = await acceptLive(QID, INQ, true);
  assertEquals(out.accepted, true);
  assertEquals(r.status.q, 'submitted');
  assertEquals(r.rpcs.filter((x) => x.fn === 'fn_quote_coach').length, 0, 'the live quote was coached');
  assertEquals(out.coaching, null);
});

Deno.test('a quote the accept rule refuses stays a draft and is coached, once per refusal', async () => {
  const r = record({ score: { submittable: false, score: 30 }, requireStructured: true, items: [] });
  const out = await acceptLive(QID, INQ, true);
  assertEquals(out.accepted, false);
  assertEquals(r.status.q, 'draft');
  assertEquals(r.rpcs.filter((x) => x.fn === 'fn_quote_coach').map((x) => x.args), [{ p_quote: QID }]);
  assertEquals(r.rpcs.filter((x) => x.fn === 'fn_customer_support_takes_delivery').length, 0, 'the customer was told of a quote they cannot see');
});

Deno.test('the customer\'s new_quote notice names its quote, so two suppliers\' quotes are two events', async () => {
  const r = record({ score: { submittable: true, score: 80 }, requireStructured: true, items: LINES });
  await acceptLive(QID, INQ, true);
  const sent = r.rpcs.filter((x) => x.fn === 'fn_customer_support_takes_delivery').map((x) => (x.args.p_rows as Record<string, unknown>[])[0]);
  assertEquals(sent.length, 1);
  assertEquals([sent[0].type, sent[0].inquiry_id, sent[0].quote_id], ['new_quote', INQ, QID]);
});
