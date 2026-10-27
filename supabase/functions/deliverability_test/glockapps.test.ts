// The GlockApps module against the API's own documented examples (27 Oct 2026; it_engineer).
//
// fixtures/swagger_examples.json is the Swagger 2.0 spec's example responses, verbatim (its _source says where from).
// fixtures/scenario_*.json are built from those same shapes, field for field, for the cases the examples do not show:
// Outlook, Hotmail and Office 365 seeds, a Gmail Promotions tab, a seed not yet received, and EOP SCL 5
// (scripts that built them: the fixtures carry ZZ seed addresses on the providers' real domains, never a real person).
//
//   deno test --no-lock --allow-read=. supabase/functions/deliverability_test/glockapps.test.ts
import { assert, assertEquals, assertMatch, assertRejects } from 'jsr:@std/assert@1';
import * as G from './glockapps.ts';
import { seedMarker } from '../send_outbox/m365_lane.ts';
import SW from './fixtures/swagger_examples.json' with { type: 'json' };
import PROVIDERS from './fixtures/scenario_providers.json' with { type: 'json' };
import CREATE from './fixtures/scenario_create.json' with { type: 'json' };
import FAIL from './fixtures/scenario_report_fail.json' with { type: 'json' };
import PASS from './fixtures/scenario_report_pass.json' with { type: 'json' };
import RUNNING from './fixtures/scenario_report_running.json' with { type: 'json' };

Deno.test('the routes, host and header are the documented ones', async () => {
  assertEquals(SW.host + SW.basePath.replace(/\/$/, ''), G.GLOCKAPPS_BASE.replace('https://', ''));
  assertEquals((SW.securityDefinitions as any).ApiKeyAuth, { type: 'apiKey', name: 'x-api-key', in: 'header' });
  const calls: { url: string; init: RequestInit }[] = [];
  const fake: G.Fetch = (url, init = {}) => { calls.push({ url, init }); return Promise.resolve(new Response('{}', { status: 200 })); };
  const ga = G.glockapps('KEY123', fake);
  await ga.projects(); await ga.providers('165'); await ga.createManualTest('165', { note: 'n' });
  await ga.seedAccounts('165', 'T1'); await ga.testReport('165', 'T 1'); await ga.deleteTest('165', 'T1'); await ga.balance();
  assertEquals(calls.map((c) => `${c.init.method} ${c.url}`), [
    'GET https://api.glockapps.com/gateway/spamtest-v2/api/projects?limit=50',
    'GET https://api.glockapps.com/gateway/spamtest-v2/api/projects/165/providers',
    'POST https://api.glockapps.com/gateway/spamtest-v2/api/projects/165/manualTest',
    'GET https://api.glockapps.com/gateway/spamtest-v2/api/projects/165/tests/T1/seedAccounts',
    'GET https://api.glockapps.com/gateway/spamtest-v2/api/projects/165/tests?testId=T%201',
    'DELETE https://api.glockapps.com/gateway/spamtest-v2/api/projects/165/tests?ids=T1',
    'GET https://api.glockapps.com/gateway/app/v3/u/account/balance',
  ]);
  for (const c of calls) assertEquals((c.init.headers as Record<string, string>)['x-api-key'], 'KEY123');
  assertEquals(JSON.parse(String(calls[2].init.body)), { note: 'n', testType: 'ManualTest' });
});

Deno.test('an HTTP refusal names the route and never carries the key', async () => {
  const fake: G.Fetch = () => Promise.resolve(new Response('bad key SECRETKEY99', { status: 401 }));
  const e = await assertRejects(() => G.glockapps('SECRETKEY99', fake).projects(), G.GlockAppsError);
  assertEquals(e.status, 401);
  assert(!e.message.includes('SECRETKEY99'), e.message);
  assertMatch(e.message, /GET \/projects answered HTTP 401/);
});

Deno.test('the marker is "id:<testId>" with no space, exactly what the M365 lane keeps', () => {
  // the documented example: insertInBody "id: 2023-09-24-11:09:04:723t"
  const m = G.markerFor(SW.manualTest);
  assertEquals(m, 'id:2023-09-24-11:09:04:723t');
  assertEquals(seedMarker('Hello\n\n' + m), m);
  assertEquals(G.markerFor(SW.seedAccounts.result as any), 'id:2023-08-27-10:00:00:095t');
  assertEquals(G.markerFor({ testId: 'abc def' }), '');          // the lane would drop it
  assertEquals(G.markerFor({ testId: 'X1', insertInBody: 'id: X2' }), '');   // disagreeing id and body
});

Deno.test('the seed directory reads every documented seed account', () => {
  const d = G.seedDirectory(SW.providers);
  assertEquals(d.byEmail.get('exosf@glockeasymail.com')?.provider, 'Exchange (Office365)');
  assertEquals(d.groupName.get('5'), 'Gmail (non-interactive)');
  assertEquals(G.providerGroupIds(SW.providers).sort(), ['17', '2', '3', '34', '35', '39', '4', '5', '53'].sort());
});

Deno.test('project choice: the configured one when the account has it, else the first listed', () => {
  assertEquals(G.pickProject(SW.projects), '165');
  assertEquals(G.pickProject(SW.projects, '81'), '81');
  assertEquals(G.pickProject(SW.projects, '999'), '165');
  assertEquals(G.pickProject({ results: [] }), '');
});

Deno.test('seed addresses: only what GlockApps returned, never a party we hold', () => {
  const r = G.seedAddresses([' A@Outlook.com ', 'a@outlook.com', 'not-an-address', 'lead@company.ae', 'b@hotmail.com'], new Set(['lead@company.ae']));
  assertEquals(r.send, ['a@outlook.com', 'b@hotmail.com']);
  assertEquals(r.refused.map((x) => x.email), ['not-an-address', 'lead@company.ae']);
});

Deno.test('iType buckets: Inbox, Spam, X (filter seed), not received = missing, any other label = tabs', () => {
  assertEquals(['Inbox', 'Spam', 'X', '', 'Promotions', 'Social', 'NotDelivered'].map((t) => G.bucketOf(t)),
    ['inbox', 'spam', 'filter', 'missing', 'tabs', 'tabs', 'missing']);
  assertEquals(G.bucketOf('Inbox', false), 'missing');
});

Deno.test('the documented example report: per provider counts agree with its own stats', () => {
  const dir = G.seedDirectory(SW.providers);
  const rows = G.placement(SW.testReport, [], dir);
  const sum = rows.reduce((a, r) => ({ inbox: a.inbox + r.inbox, spam: a.spam + r.spam }), { inbox: 0, spam: 0 });
  assertEquals(sum, { inbox: SW.testReport.result.stats.inbox, spam: SW.testReport.result.stats.spam });   // 11 and 2
  const o2 = rows.find((r) => r.provider === 'o2.pl')!;
  assertEquals([o2.seeds, o2.inbox, o2.spam], [3, 1, 2]);
  assertEquals(G.outlookOf(rows).seeds, 0);
  assertEquals(G.verdictOf(G.outlookOf(rows), G.completion(SW.testReport, new Date('2023-07-26T18:16:11Z'), new Date('2023-07-26T19:00:00Z'))), 'incomplete');
});

Deno.test('filters: SpamAssassin rules, Barracuda, Google and authentication from the documented example', () => {
  const f = G.filtersOf(SW.testReport) as any;
  assertEquals(f.spamassassin.score, 2);
  assert(f.spamassassin.rules.some((r: any) => r.tag === 'PYZOR_CHECK' && r.score === 2));
  assertEquals(f.barracuda.score, 1.39);
  assertEquals(f.google, { spam: false, phishy: false, finished: true });
  assertEquals(f.authentication.spf, 'pass');
  assertEquals(f.authentication.dkim, 'pass');
  assertEquals(f.glockapps_stats.inboxRate, 84.6);
});

Deno.test('FAIL scenario: Outlook, Hotmail and Office 365 together 2 of 13 inbox; Gmail tabs counted; EOP SCL 5 read', () => {
  const dir = G.seedDirectory(PROVIDERS);
  const rows = G.placement(FAIL, CREATE.emails, dir);
  const o = G.outlookOf(rows);
  assertEquals(o, { seeds: 13, inbox: 2, spam: 10, tabs: 0, missing: 1, inbox_pct: 15.4 });
  const gmail = rows.find((r) => r.provider.startsWith('Gmail'))!;
  assertEquals([gmail.inbox, gmail.tabs, gmail.raw_itypes.Promotions], [1, 3, 3]);
  assert(!rows.some((r) => r.provider === 'Custom'), 'the SpamAssassin filter seed is not a mailbox');
  for (const r of rows) assertEquals(r.seeds, r.inbox + r.spam + r.tabs + r.missing);
  const f = G.filtersOf(FAIL) as any;
  assertEquals([f.microsoft_eop.scl, f.microsoft_eop.sfv], [5, 'SPM']);
  const c = G.completion(FAIL, new Date('2026-10-28T08:00:00Z'), new Date('2026-10-28T09:00:00Z'));
  assertEquals(G.verdictOf(o, c), 'fail');
  const text = G.summaryText({ testId: CREATE.testId, createdAt: '2026-10-28T08:00:00Z', from: 'supplier@quotesdone.com', seedsSent: 20, rows, outlook: o, filters: f, verdict: 'fail' });
  assertMatch(text, /Outlook \/ Microsoft .*inbox 2, spam 10, tabs\/promotions 0, missing 1 \(of 13; 15\.4% inbox\), against the 80% bar/);
  assertMatch(text, /Microsoft EOP SCL 5/);
  assertMatch(text, /^FAIL: .*stay held/m);
});

Deno.test('PASS scenario: 11 of 13 = 84.6% passes; the summary says resuming is the founder\'s and nothing was switched on', () => {
  const rows = G.placement(PASS, CREATE.emails, G.seedDirectory(PROVIDERS));
  const o = G.outlookOf(rows);
  assertEquals([o.inbox, o.seeds, o.inbox_pct], [11, 13, 84.6]);
  const v = G.verdictOf(o, G.completion(PASS, new Date('2026-10-28T08:00:00Z'), new Date('2026-10-28T09:00:00Z')));
  assertEquals(v, 'pass');
  const text = G.summaryText({ testId: CREATE.testId, createdAt: 'x', from: 'supplier@quotesdone.com', seedsSent: 20, rows, outlook: o, filters: G.filtersOf(PASS), verdict: v });
  assertMatch(text, /^PASS: .*founder's confirmation.*Nothing was switched on\./m);
});

Deno.test('79.9% is a fail, 80.0% a pass: the bar is inclusive and only "Inbox" counts', () => {
  const c = { complete: true, gaveUp: false };
  assertEquals(G.verdictOf({ seeds: 1000, inbox: 799, spam: 201, tabs: 0, missing: 0, inbox_pct: 79.9 }, c), 'fail');
  assertEquals(G.verdictOf({ seeds: 10, inbox: 8, spam: 0, tabs: 2, missing: 0, inbox_pct: 80 }, c), 'pass');
});

Deno.test('RUNNING: an unfinished report stays pending; past 48 hours it is incomplete, never a pass', () => {
  const rows = G.placement(RUNNING, CREATE.emails, G.seedDirectory(PROVIDERS));
  const o = G.outlookOf(rows);
  assertEquals(o.missing, 13 - 5);   // the five received are Outlook seeds; the rest not yet
  const created = new Date('2026-10-28T08:00:00Z');
  assertEquals(G.verdictOf(o, G.completion(RUNNING, created, new Date('2026-10-28T09:00:00Z'))), 'pending');
  assertEquals(G.verdictOf(o, G.completion(RUNNING, created, new Date('2026-10-30T08:00:01Z'))), 'incomplete');
});

Deno.test('the seed body is the live copy with the marker as its own last line', () => {
  const body = G.seedBody('Dear {{company}},\n\nJoin at {{link}}', 'https://quotesdone.com', 'id:T-1_x:2');
  assert(body.startsWith('Dear ZZ DEMO Supplier,'));
  assertEquals(seedMarker(body), 'id:T-1_x:2');
});
