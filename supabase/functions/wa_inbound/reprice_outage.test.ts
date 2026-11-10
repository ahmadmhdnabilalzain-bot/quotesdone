// A WhatsApp re-price the model could not read is SAID and READ ONCE MORE (customer_support, 10 Nov 2026; supplier
// follow-up #1909 item 2). On origin/main a failed directive reading answered null, supplier_directive.ts took it for
// "not a change", and the message fell through: the price never moved and nobody told the supplier. Drives the real
// supplierDirective() with a stubbed database and Twilio (nothing leaves this process) from the fixture block.
//   deno test --allow-all supabase/functions/wa_inbound/reprice_outage.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
const rpcs: { fn: string; args: Record<string, unknown> }[] = [];
globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init); const u = new URL(req.url);
  const body = req.method === 'GET' ? '' : await req.text();
  const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
  if (u.pathname.startsWith('/rest/v1/rpc/')) { rpcs.push({ fn: u.pathname.slice('/rest/v1/rpc/'.length), args: JSON.parse(body || '{}') }); return json(u.pathname.endsWith('fn_reason_hold') ? 4242 : {}); }
  if (u.pathname === '/rest/v1/app_secrets') return (req.headers.get('Accept') || '').includes('vnd.pgrst.object') ? json({ value: u.searchParams.get('key') === 'eq.wa_autoreply_enabled' ? 'true' : 'zz' }) : json([]);
  return json({ sid: 'SMzz', status: 'queued' }, 201);
}) as typeof fetch;

const { repriceOutagePlan, outageNotice, REPRICE_SURFACE } = await import('./reprice_outage.ts');
const { amountsInOwnWords } = await import('./directive_gate.ts');
const { supplierDirective } = await import('./supplier_directive.ts');

const FROM = 'whatsapp:+971500000042';   // the reserved fixture block
const turn = (body: string, reading: unknown) => {
  const rows: Record<string, unknown>[] = []; const runs: unknown[] = [];
  const t = { From: FROM, Body: body, Profile: 'ZZ DEMO Supplier', MessageSid: 'SMzzreprice01', audience: 'supplier', internalCaller: false,
    directiveRead: () => Promise.resolve(reading), receivedAt: Date.now(),
    logRun: (s: string, c: unknown, n: string) => { runs.push({ s, c, n }); return Promise.resolve(); },
    waInsert: (_at: number, row: Record<string, unknown>) => { rows.push(row); return Promise.resolve(); },
    sayFor: () => () => Promise.resolve(''), heldTurn: () => Promise.resolve({ notice: '', sent: false, err: null }) };
  return { t, rows, runs };
};

Deno.test('the amounts a message states are the only ones a replay may choose', () => {
  assertEquals(amountsInOwnWords('Please change my quote to AED 72,556 instead of 65960'), ['72556', '65960']);
  assertEquals(amountsInOwnWords('make it cheaper please'), []);
  const p = repriceOutagePlan({ outage: true, why: 'gateway 503' }, FROM, 'change my price to 72,556', 'SM1')!;
  assertEquals(p.hold.p_surface, REPRICE_SURFACE);
  assertEquals(p.hold.p_dedupe_key, 'wa_reprice:SM1');
  assertEquals((p.hold.p_request.decision.options as { id: string }[]).map((o) => o.id), ['no_change', 'amount:72556']);
  assertEquals(repriceOutagePlan({ change: false }, FROM, 'change my price to 72,556', 'SM1'), null, 'a reading is not an outage');
  assertEquals(repriceOutagePlan({ outage: true, why: 'x' }, FROM, 'is my quote received?', 'SM1'), null, 'no amount: not a re-price');
  assertMatch(outageNotice(['72556']), /AED 72,556/);
  assert(!/[؀-ۿ]/.test(outageNotice(['1'])), 'suppliers: English');
});

Deno.test('under a model outage a re-price is told, filed once for a replay, and nothing is applied', async () => {
  rpcs.length = 0;
  const { t, rows, runs } = turn('Please change my quotation price to AED 72,556', { outage: true, why: 'gateway model_hold' });
  const res = await supplierDirective(t as never);
  assert(res instanceof Response, 'the turn is answered here, not dropped into the ordinary path');
  assertEquals(rpcs.filter((r) => r.fn === 'fn_supplier_apply_change').length, 0, 'no amount is applied on a guess');
  const hold = rpcs.filter((r) => r.fn === 'fn_reason_hold');
  assertEquals(hold.length, 1);
  assertEquals([hold[0].args.p_surface, hold[0].args.p_dedupe_key], [REPRICE_SURFACE, 'wa_reprice:SMzzreprice01']);
  assertEquals(rows.length, 1);
  assertMatch(String(rows[0].reply), /nothing has changed/); assertMatch(String(rows[0].reply), /quotesdone\.com\/portal/);
  assertEquals((rows[0].meta as Record<string, unknown>).route, 'supplier_directive_outage');
  assertEquals((runs[0] as { s: string }).s, 'error');
});

Deno.test('a reading that says "not a change" still falls through to the ordinary answer', async () => {
  rpcs.length = 0;
  const { t } = turn('Please change my quotation price to AED 72,556', { change: false });
  assertEquals(await supplierDirective(t as never), undefined);
  assertEquals(rpcs.length, 0);
});

Deno.test('the replay finds its apply routine by the surface name, and it applies only an option the held row offered', async () => {
  const sql = await Deno.readTextFile(new URL('../../../scripts/sql/a_whatsapp_reprice_the_model_could_not_read_is_said_and_read_once_more.sql', import.meta.url));
  const name = 'fn_reason_apply_' + REPRICE_SURFACE.replace('.', '__');
  assert(name.length <= 63, 'fn_reason_held_resolve skips a name longer than 63');
  assertMatch(sql, new RegExp('create or replace function public\\.' + name + '\\(p_id bigint, p_result jsonb\\)'));
  assertMatch(sql, /CHOICE_NOT_AN_OPTION/);
  assertMatch(sql, /fn_supplier_apply_change\(p_phone => v_phone, p_field => 'quote_price', p_value => substr\(v_choice, 8\)/);
  assertEquals('amount:'.length + 1, 8, 'substr(v_choice, 8) is the number after "amount:"');
});
