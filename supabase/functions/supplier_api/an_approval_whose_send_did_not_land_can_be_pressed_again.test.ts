// "APPROVE AND SEND" WHOSE SEND DID NOT LAND CAN BE PRESSED AGAIN (15 Nov 2026, third review of the certificate branch, item 1).
// The spec_approve path as the handler runs it: workflow.ts approve() over the real supabaseRepo, with supplier_api's own
// acceptForRelease (acceptLive) as `accept`, both on ONE in-memory database standing in for the service-role client.
// Before: approve() marked the hold released, the submitted write was cancelled, the quote stayed a draft, the supplier was still
// mailed "Your quote is approved", and a second press answered not_awaiting_approval. Now the hold is put back, nothing is mailed,
// and the second press sends the quotation and only then mails him.
// Incapable of reaching anything: no network, ZZ DEMO ids and @example.invalid addresses only.
//   deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY --allow-read=. supabase/functions/supplier_api/an_approval_whose_send_did_not_land_can_be_pressed_again.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';

Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:9');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-not-a-key');
const waited: Promise<unknown>[] = [];
(globalThis as { EdgeRuntime?: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { waited.push(p); } };
const ctxm = await import('./context.ts');
const { acceptForRelease } = await import('./lib/quote_acceptance.ts');
const { approve, supabaseRepo } = await import('../_shared/line_specs/workflow.ts');

type Row = Record<string, unknown>;
const QID = 'aaaaaaaa-0000-4000-8000-0000000000e1';
const INQ = 'aaaaaaaa-0000-4000-8000-0000000000e2';
const SUP = { id: 900003, email: 'zz-demo-approve@example.invalid', phone: '+971500000093', locale: 'en' as const };

// ONE in-memory database: tables of rows, the filters supabase-js builds, and the two RPCs this path calls.
function database() {
  const t: Record<string, Row[]> = {
    quotes: [{ id: QID, inquiry_id: INQ, supplier_id: SUP.id, status: 'draft', option_no: 1, submission_id: 's', quote_amount: 12000, price_ex_vat: 12000,
      lead_time: '21 days', validity: '30 days', payment_terms: '50% advance', warranty: '2 years on workmanship and hardware', scope: 'Supply and installation by our own team',
      terms_spec: { installation: { included: 'yes', detail: 'by our own team', source: 'supplier_portal' }, warranty: { period: '2 years', coverage: 'parts and labour', source: 'supplier_portal' } } }],
    quote_items: [{ quote_id: QID, line_no: 1, description: 'ZZ DEMO split AC unit', specification: 'Daikin FTKF50 1.5 TR inverter split, R32, wall mounted', qty: 1, unit: 'nos', unit_price: 12000, amount: 12000 }],
    quote_spec_hold: [{ id: 1, quote_id: QID, state: 'awaiting_approval', missing: [], supplier_values: [], regenerated: { lines: [], terms: {}, total: 12000 }, approved_at: null, approved_by: null, released_at: null }],
    inquiries: [{ id: INQ, customer_id: 'c-zz', summary: 'ZZ DEMO split AC', status: 'sent' }],
    customers: [{ id: 'c-zz', email: 'zz-demo-customer@example.invalid' }],
    app_secrets: [{ key: 'require_structured_quotes', value: 'true' }],
    quote_quality_hold: [], agent_runs: [], notifications: [],
  };
  const delivered: Row[] = []; const rpcs: string[] = [];
  let failSubmitted = true;
  const from = (table: string) => {
    const f: ((r: Row) => boolean)[] = []; let op = 'select'; let patch: Row = {}; let one = false;
    const rows = () => (t[table] ??= []).filter((r) => f.every((p) => p(r)));
    const run = () => {
      if (op === 'update') {
        if (table === 'quotes' && patch.status === 'submitted' && failSubmitted) return { data: null, error: { code: '57014', message: 'canceling statement due to statement timeout' } };
        const hit = rows(); for (const r of hit) Object.assign(r, patch); return { data: hit, error: null };
      }
      if (op === 'insert') { t[table].push(...([] as Row[]).concat(patch as unknown as Row[])); return { data: null, error: null }; }
      const hit = rows(); return { data: one ? (hit[0] ?? null) : hit, error: null };
    };
    // deno-lint-ignore no-explicit-any
    const b: any = {
      select: () => b, order: () => b, limit: () => b, gte: () => b,
      eq: (k: string, v: unknown) => { f.push((r) => String(r[k]) === String(v)); return b; },
      in: (k: string, v: unknown[]) => { f.push((r) => v.map(String).includes(String(r[k]))); return b; },
      is: (k: string, v: unknown) => { f.push((r) => (r[k] ?? null) === v); return b; },
      update: (p: Row) => { op = 'update'; patch = p; return b; }, insert: (p: Row) => { op = 'insert'; patch = p; return b; },
      maybeSingle: () => { one = true; return Promise.resolve(run()); }, single: () => { one = true; return Promise.resolve(run()); },
      then: (res: (v: unknown) => unknown, rej?: (e: unknown) => unknown) => Promise.resolve(run()).then(res, rej),
    };
    return b;
  };
  const rpc = (fn: string, args: Row) => {
    rpcs.push(fn);
    if (fn === 'fn_quote_structured_score') return Promise.resolve({ data: { submittable: true, score: 80 }, error: null });
    if (fn === 'fn_customer_support_takes_delivery') {
      const rs = (args.p_rows ?? args.p_row ?? []) as Row[]; for (const r of ([] as Row[]).concat(rs)) delivered.push(r);
      return Promise.resolve({ data: ([] as Row[]).concat(rs).map((_, i) => ({ handoff_id: i + 1, notification_id: delivered.length + i, error: null })), error: null });
    }
    return Promise.resolve({ data: { ok: true }, error: null });
  };
  return { t, from, rpc, delivered, rpcs, lockGone: () => { failSubmitted = false; } };
}

const ctx = { category: null, requirements: null, ref: 'ZZDEMO02', now: () => new Date('2026-11-16T10:00:00Z'), read: () => Promise.resolve(null) };

Deno.test('a failed submitted write puts the hold back with no notice; the second "Approve and send" sends it, and only then is he told', async () => {
  const db = database();
  Object.assign(ctxm.admin, { from: db.from, rpc: db.rpc });   // supplier_api's own client: acceptLive reads and writes here
  const repo = supabaseRepo(ctxm.admin);                       // the desk's repo, on the same client, as quotes.ts builds it
  const quiet = console.error; console.error = () => {};
  try {
    const first = await approve(repo, QID, SUP, SUP.email, true, ctx as never, acceptForRelease, async () => null);
    await Promise.all(waited);
    assertEquals(first, { ok: false, code: 'quote_not_sent' });
    const hold = db.t.quote_spec_hold[0];
    assertEquals([hold.state, hold.approved_at, hold.approved_by, hold.released_at], ['awaiting_approval', null, null, null], 'the hold is as the press found it');
    assertEquals(db.t.quotes[0].status, 'draft');
    assertEquals(db.delivered.map((r) => r.type), [], 'no "approved" notice and no new_quote before the quotation is really sent');
    assert(db.rpcs.includes('fn_it_engineer_finding_upsert'), 'the IT seat is told');

    db.lockGone();   // he presses "Approve and send" again, as told
    const again = await approve(repo, QID, SUP, SUP.email, true, ctx as never, acceptForRelease, async () => null);
    assert(again.ok, JSON.stringify(again));
    assertEquals((again as { live?: boolean }).live, true);
    assertEquals(db.t.quotes[0].status, 'submitted');
    assertEquals(db.t.quote_spec_hold[0].state, 'released');
    const types = db.delivered.map((r) => r.type);
    assert(types.includes('new_quote'), 'the customer is told once it is live: ' + types.join(','));
    assert(types.includes('quote_spec_released'), 'the supplier is told once it is sent: ' + types.join(','));
  } finally { console.error = quiet; }
});

Deno.test('spec_approve answers quote_not_sent as a 503 with the plain sentence, never a 409', () => {
  const src = Deno.readTextFileSync(new URL('./actions/quotes.ts', import.meta.url));
  assert(src.includes("if (!out.ok && out.code === 'quote_not_sent') return J({ ok: false, error: 'quote_not_sent', ...QUOTE_NOT_SENT_APPROVE }, 503);"));
  assert(src.indexOf("out.code === 'quote_not_sent'") < src.indexOf("if (!out.ok) return J({ ...out, error: out.code }, out.code === 'not_found' ? 404 : 409);"));
});
