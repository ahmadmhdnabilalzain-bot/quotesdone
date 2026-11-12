// The hourly duties tick STORES its readings for the pg_cron job and never decides them over the API (it_engineer,
// 12 Nov 2026; final audit F1). On main the tick called fn_it_duties over PostgREST with its 8 s limit: from 11 Nov
// 00:45Z every call timed out (62 times), nothing was recorded as a run, and the readings were taken again every tick.
// Drives the real itDutiesTick with the database and every provider stubbed (nothing leaves this process).
//   deno test --allow-env --no-lock supabase/functions/resilience_ping/ticks/it_engineer/duties.test.ts
const assert = (c: unknown, m: string) => { if (!c) throw new Error(m); };
const assertEquals = (a: unknown, b: unknown, m = '') => {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${m}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`);
};
const assertMatch = (s: string, re: RegExp) => { if (!re.test(s)) throw new Error(`${s} does not match ${re}`); };
Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');

let answers: Record<string, unknown> = {};
const rpcs: string[] = [];
globalThis.fetch = ((input: Request | URL | string, init?: RequestInit): Promise<Response> => {
  const req = new Request(input, init); const u = new URL(req.url);
  const json = (o: unknown, s = 200) => Promise.resolve(new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } }));
  if (u.pathname.startsWith('/rest/v1/rpc/')) {
    const fn = u.pathname.slice('/rest/v1/rpc/'.length); rpcs.push(fn);
    return json(fn in answers ? answers[fn] : {});
  }
  if (u.pathname === '/rest/v1/app_secrets') return json({ value: '' });
  return json({}, 503);   // GitHub, Vercel, Stripe, the sites: unavailable, so the readings say so
}) as typeof fetch;

const { itDutiesTick } = await import('./duties.ts');

Deno.test('a due tick stores the readings for the cron job and does not run fn_it_duties over the API', async () => {
  rpcs.length = 0;
  answers = { fn_it_duties_unfinished: null, fn_it_duties_due: true, fn_it_duties_readings_store: { stored: 4242 } };
  const out = await itDutiesTick() as Record<string, unknown>;
  assert(rpcs.includes('fn_it_duties_readings_store'), `stored: ${rpcs.join(', ')}`);
  assert(!rpcs.includes('fn_it_duties'), 'fn_it_duties is the cron job\'s, never this 8 s call');
  assert(rpcs.includes('fn_it_expiry_measured'), 'the expiries still go from the same readings');
  assertEquals(out.ok, undefined);
  assertEquals(out.stored, 4242);
});

Deno.test('readings nothing finished fail the step on every tick, due or not, until a later run finishes', async () => {
  answers = { fn_it_duties_unfinished: { readings_run: 77, taken_at: '2026-11-12T01:00:00Z', status: 'error' }, fn_it_duties_due: false };
  const quiet = await itDutiesTick() as Record<string, unknown>;
  assertEquals(quiet.ok, false, 'a tick that is not due still reports the unfinished hour');
  assertMatch(String(quiet.error), /did not finish on the readings stored at 2026-11-12T01:00:00Z/);
  answers = { ...answers, fn_it_duties_due: true, fn_it_duties_readings_store: { stored: 78 } };
  const due = await itDutiesTick() as Record<string, unknown>;
  assertEquals(due.ok, false, 'and so does the tick that stores the next readings');
  assertEquals(due.stored, 78);
  answers = { fn_it_duties_unfinished: null, fn_it_duties_due: false };
  assertEquals(await itDutiesTick(), { due: false }, 'once a later run finished, the step passes');
});
