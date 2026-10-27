// deliverability_test's actions with a fake database and a fake GlockApps answering the documented shapes
// (27 Oct 2026; it_engineer). No network, no database.
//
//   deno test --no-lock --allow-read=. supabase/functions/deliverability_test/handler.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { collect, create, handle, KEY_MISSING_ISSUE, report, REQUEST_KEY, type Db, type Deps, type SeedRow, type TestRow } from './handler.ts';
import { seedMarker, M365_SEED_KIND } from '../send_outbox/m365_lane.ts';
import type { Fetch } from './glockapps.ts';
import SW from './fixtures/swagger_examples.json' with { type: 'json' };
import PROVIDERS from './fixtures/scenario_providers.json' with { type: 'json' };
import CREATE from './fixtures/scenario_create.json' with { type: 'json' };
import FAIL from './fixtures/scenario_report_fail.json' with { type: 'json' };
import PASS from './fixtures/scenario_report_pass.json' with { type: 'json' };

const SECRETS: Record<string, string> = {
  invite_subject: 'Quote requests in the UAE', invite_body: 'Dear {{company}},\n\nJoin us at {{link}}\n\nreply stop',
  public_site_url: 'https://quotesdone.com', invite_m365_mailbox: 'supplier@quotesdone.com',
};

function fakeDb(init: { tests?: TestRow[]; known?: string[] } = {}) {
  const tests = new Map<string, any>((init.tests || []).map((t) => [t.test_id, { ...t }]));
  const log = { seeds: [] as SeedRow[], secretsCleared: 0, findings: [] as any[], closed: [] as string[], filed: [] as string[], providers: [] as any[] };
  const db: Db = {
    secret: (k) => Promise.resolve(SECRETS[k] ?? ''),
    clearRequest: () => { log.secretsCleared++; return Promise.resolve(); },
    openTest: () => Promise.resolve([...tests.values()].find((t) => ['seeds_queued', 'collecting'].includes(t.status)) ?? null),
    getTest: (id) => Promise.resolve(tests.get(id) ?? null),
    latestTest: () => Promise.resolve([...tests.values()].pop() ?? null),
    insertTest: (row) => { tests.set(String(row.test_id), { polls: 0, reported_at: null, summary: null, outlook: null, outlook_inbox_pct: null, ...row }); return Promise.resolve(); },
    updateTest: (id, patch) => { tests.set(id, { ...tests.get(id), ...patch }); return Promise.resolve(); },
    knownParties: (emails) => Promise.resolve(new Set(emails.filter((e) => (init.known || []).includes(e)))),
    queueSeeds: (rows) => { log.seeds.push(...rows); return Promise.resolve(rows.map((_, i) => 1000 + i)); },
    upsertProviders: (_id, rows) => { log.providers.push(...rows); return Promise.resolve(); },
    fileVerdict: (id) => { log.filed.push(id); tests.set(id, { ...tests.get(id), reported_at: 'now' }); return Promise.resolve({ filed: true }); },
    finding: (a) => { log.findings.push(a); return Promise.resolve(); },
    closeFinding: (k) => { log.closed.push(k); return Promise.resolve(); },
  };
  return { db, tests, log };
}

function fakeGlockApps(report: unknown = FAIL) {
  const calls: string[] = [];
  const fetchFn: Fetch = (url, init = {}) => {
    const m = String(init.method || 'GET'); calls.push(`${m} ${url.replace('https://api.glockapps.com/gateway', '')}`);
    const json = (o: unknown, s = 200) => Promise.resolve(new Response(JSON.stringify(o), { status: s }));
    if (url.endsWith('/account/balance')) return json({ testCredits: { balance: 2, planCredits: 3 } });
    if (url.includes('/projects?')) return json(SW.projects);
    if (url.endsWith('/providers')) return json(PROVIDERS);
    if (url.endsWith('/manualTest')) return json(CREATE, 201);
    if (url.includes('/tests?testId=')) return json(report);
    if (m === 'DELETE') return json({ status: 'success' });
    return json({}, 404);
  };
  return { fetchFn, calls };
}

const deps = (db: Db, fetchFn: Fetch, env: Record<string, string> = { GLOCKAPPS_API_KEY: 'k3y-for-tests' }, now = new Date('2026-10-28T09:00:00Z')): Deps => ({
  db, fetch: fetchFn, env: (k) => env[k], now: () => now, serviceKey: 'service-key-xyz', internalAuth: (s) => Promise.resolve(s === 'scoped-cred'),
});

Deno.test('create REFUSES when GLOCKAPPS_API_KEY is missing: no call to GlockApps, no seed, a clear status', async () => {
  const { db, log } = fakeDb();
  const g = fakeGlockApps();
  for (const env of [{}, { GLOCKAPPS_API_KEY: '   ' }] as Record<string, string>[]) {
    const out = await create(deps(db, g.fetchFn, env), { action: 'create' });
    assertEquals(out.http, 200);
    assertEquals(out.body.ok, false);
    assertEquals(out.body.status, 'key_missing');
    assertMatch(String(out.body.message), /GLOCKAPPS_API_KEY is not set\. Add it in Supabase dashboard > Edge Functions > Secrets/);
  }
  assertEquals(g.calls, []);
  assertEquals(log.seeds, []);
  assertEquals(log.secretsCleared, 0);
  assertEquals(log.findings.map((f) => f.p_issue_key), [KEY_MISSING_ISSUE, KEY_MISSING_ISSUE]);
  // collect without a key is the same clear answer, and files nothing
  const c = await collect(deps(db, g.fetchFn, {}), {});
  assertEquals([c.body.ok, c.body.status], [false, 'key_missing']);
});

Deno.test('create: one GlockApps test, every returned seed queued once over the M365 lane with the marker last', async () => {
  const lead = 'zzseed.yahoo.b@yahoo.com';
  const { db, log, tests } = fakeDb({ known: [lead] });
  const g = fakeGlockApps();
  const out = await create(deps(db, g.fetchFn), { action: 'create', reason: 'ZZ test' });
  assertEquals(out.http, 201, JSON.stringify(out.body));
  assertEquals(out.body.test_id, CREATE.testId);
  assertEquals(out.body.marker, 'id:' + CREATE.testId);
  assertEquals(g.calls.filter((c) => c.startsWith('POST')), ['POST /spamtest-v2/api/projects/165/manualTest']);
  const sent = log.seeds.map((s) => s.to_email);
  assertEquals(sent.length, CREATE.emails.length - 1);
  assert(!sent.includes(lead), 'an address we hold as a lead is never a seed');
  assertEquals(new Set(sent).size, sent.length);
  for (const s of log.seeds) {
    assertEquals([s.type, s.kind, s.to_role, s.lang, s.status, s.requested_by], ['supplier_invite_seed', M365_SEED_KIND, 'supplier', 'en', 'queued', 'it_engineer']);
    assertEquals(seedMarker(s.body), 'id:' + CREATE.testId);
    assertEquals(s.subject, SECRETS.invite_subject);
    assert(s.body.startsWith('Dear ZZ DEMO Supplier,'));
    assertEquals(s.dedupe_key, `glockapps:${CREATE.testId}:${s.to_email}`);
    assert(CREATE.emails.map((e) => e.toLowerCase()).includes(s.to_email), 'only addresses GlockApps returned');
  }
  const row = tests.get(CREATE.testId);
  assertEquals([row.status, row.verdict, row.project_id], ['seeds_queued', 'pending', '165']);
  assertEquals(row.notification_ids.length, sent.length);
  assertEquals(log.secretsCleared, 1);
  assertEquals(log.closed, [KEY_MISSING_ISSUE]);
});

Deno.test('create refuses a second test while one is open (no credit spent)', async () => {
  const { db } = fakeDb({ tests: [{ test_id: 'T-open-1', status: 'collecting', verdict: 'pending' } as TestRow] });
  const g = fakeGlockApps();
  const out = await create(deps(db, g.fetchFn), { action: 'create' });
  assertEquals([out.body.ok, out.body.status], [false, 'test_open']);
  assertEquals(g.calls, []);
});

Deno.test('create deletes the test (refund) when the marker would not survive the lane', async () => {
  const { db, log } = fakeDb();
  const g = fakeGlockApps();
  const bad: Fetch = (url, init) => url.endsWith('/manualTest')
    ? Promise.resolve(new Response(JSON.stringify({ ...CREATE, testId: 'bad id with spaces', insertInBody: 'id: bad id with spaces' }), { status: 201 }))
    : g.fetchFn(url, init);
  const out = await create(deps(db, bad), { action: 'create' });
  assertEquals([out.body.status, out.body.refunded], ['marker_unusable', true]);
  assert(g.calls.some((c) => c.startsWith('DELETE')));
  assertEquals(log.seeds, []);
});

const openRow = (): TestRow => ({
  test_id: CREATE.testId, project_id: '165', created_at: '2026-10-28T08:00:00Z', reason: 'r', marker: 'id:' + CREATE.testId,
  from_address: 'supplier@quotesdone.com', seeds: CREATE.emails.map((email) => ({ email, provider: '', provider_group_id: '' })),
  status: 'seeds_queued', verdict: 'pending', polls: 0, reported_at: null, summary: null, outlook: null, outlook_inbox_pct: null,
});

Deno.test('collect FAIL: per-provider rows stored, verdict fail, filed once', async () => {
  const { db, log, tests } = fakeDb({ tests: [openRow()] });
  const out = await collect(deps(db, fakeGlockApps(FAIL).fetchFn), {});
  assertEquals([out.body.ok, out.body.status, out.body.verdict], [true, 'decided', 'fail']);
  assertEquals((out.body.outlook as any).inbox_pct, 15.4);
  assert(log.providers.some((p) => p.provider === 'Outlook' && p.spam === 9));
  assertEquals(log.filed, [CREATE.testId]);
  const row = tests.get(CREATE.testId);
  assertEquals([row.status, row.verdict, row.polls], ['complete', 'fail', 1]);
  assertMatch(row.summary, /15\.4% inbox/);
  // report afterwards does not file again
  const r = await report(deps(db, fakeGlockApps().fetchFn), {});
  assertEquals([r.body.verdict, r.body.pass, r.body.bar_pct], ['fail', false, 80]);
  assertEquals(log.filed.length, 1);
});

Deno.test('collect PASS: verdict pass, and the only app_secrets write anywhere was none', async () => {
  const { db, log, tests } = fakeDb({ tests: [openRow()] });
  const out = await collect(deps(db, fakeGlockApps(PASS).fetchFn), {});
  assertEquals(out.body.verdict, 'pass');
  assertEquals(tests.get(CREATE.testId).outlook_inbox_pct, 84.6);
  assertEquals(log.secretsCleared, 0);
});

Deno.test('collect while GlockApps is still running keeps polling and files nothing', async () => {
  const running = { ...FAIL, result: { ...FAIL.result, finished: 'false' } };
  const { db, log, tests } = fakeDb({ tests: [openRow()] });
  const out = await collect(deps(db, fakeGlockApps(running).fetchFn), {});
  assertEquals([out.body.status, out.body.verdict], ['collecting', 'pending']);
  assertEquals(tests.get(CREATE.testId).status, 'collecting');
  assertEquals(log.filed, []);
});

Deno.test('the HTTP door: service role or the scoped credential only', async () => {
  const { db } = fakeDb();
  const d = deps(db, fakeGlockApps().fetchFn, {});
  const post = (headers: Record<string, string>, body: unknown) => new Request('https://x/functions/v1/deliverability_test', { method: 'POST', headers, body: JSON.stringify(body) });
  assertEquals((await handle(post({}, { action: 'report' }), d)).http, 403);
  assertEquals((await handle(post({ Authorization: 'Bearer anon-key' }, { action: 'report' }), d)).http, 403);
  assertEquals((await handle(post({}, { action: 'report', __secret: 'wrong' }), d)).http, 403);
  assertEquals((await handle(post({ Authorization: 'Bearer service-key-xyz' }, { action: 'create' }), d)).body.status, 'key_missing');
  assertEquals((await handle(post({}, { action: 'collect', __secret: 'scoped-cred' }), d)).body.status, 'key_missing');
  assertEquals((await handle(post({ apikey: 'service-key-xyz' }, { action: 'nope' }), d)).http, 400);
  assertEquals((await handle(new Request('https://x', { method: 'GET' }), d)).http, 405);
});

Deno.test('REQUEST_KEY is the one-shot request flag, not an invitation switch', () => {
  assertEquals(REQUEST_KEY, 'deliverability_test_request');
});
