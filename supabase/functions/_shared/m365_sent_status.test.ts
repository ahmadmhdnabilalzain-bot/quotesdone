// deno test supabase/functions/_shared/m365_sent_status.test.ts
// The Sent Items read-back (m365_sent_status.ts), offline: a send Graph has in Sent Items is recorded 'sent' at Graph's
// sentDateTime; one it does not have, or an HTTP error, is a failed try with its reason; nothing is asked when nothing is
// claimed; a refused token counts a failed try on every claimed row; the Message-ID is an exact OData literal.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { measureNdrHeaders, pollM365SentStatus, sentItemsUrl, type Claimed, type SentDeps } from './m365_sent_status.ts';

const ENV: Record<string, string> = { MS_TENANT_ID: 't', MS_CLIENT_ID: 'zz-demo-client', MS_CLIENT_SECRET: 'zz-demo-secret-0123456789' };
const MID = '<qd-notif-117569.1793340128035@quotesdone.com>';
type Rec = { id: number; found: boolean; sentAt: string | null; http: number | null; code: string | null };

function harness(rows: Claimed[], graph: (url: string) => { status: number; body?: unknown }, env = ENV) {
  const urls: string[] = [], recs: Rec[] = [];
  const deps: SentDeps = {
    fetchFn: (url) => {
      urls.push(url);
      if (url.includes('login.microsoftonline.com')) return Promise.resolve(new Response(JSON.stringify({ access_token: 'tok' }), { status: 200 }));
      const a = graph(url);
      return Promise.resolve(new Response(a.body === undefined ? null : JSON.stringify(a.body), { status: a.status }));
    },
    env: (k) => env[k], mailbox: 'supplier@quotesdone.com',
    claim: () => Promise.resolve(rows),
    record: (id, found, sentAt, http, code) => { recs.push({ id, found, sentAt, http, code }); return Promise.resolve(); },
  };
  return { deps, urls, recs };
}

Deno.test('a send in Sent Items is recorded sent at Graph\'s sentDateTime; the query names its exact Message-ID', async () => {
  const h = harness([{ notification_id: 117569, message_id: MID }],
    () => ({ status: 200, body: { value: [{ id: 'x', internetMessageId: MID, sentDateTime: '2026-10-30T06:02:08Z' }] } }));
  const out = await pollM365SentStatus(h.deps);
  assertEquals(h.recs, [{ id: 117569, found: true, sentAt: '2026-10-30T06:02:08Z', http: 200, code: null }]);
  assertEquals(out.sent, 1);
  const q = new URL(h.urls.find((u) => u.includes('/mailFolders/sentitems/'))!);
  assertEquals(q.searchParams.get('$filter'), `internetMessageId eq '${MID}'`);
});

Deno.test('a send Graph does not have, or cannot answer for, is a failed try with its reason, never sent', async () => {
  const rows = [{ notification_id: 1, message_id: MID }, { notification_id: 2, message_id: '<qd-notif-2.1@quotesdone.com>' },
                { notification_id: 3, message_id: '<qd-notif-3.1@quotesdone.com>' }];
  const h = harness(rows, (url) => url.includes('qd-notif-117569') ? { status: 200, body: { value: [] } }
    : url.includes('qd-notif-2.') ? { status: 403, body: { error: { code: 'ErrorAccessDenied' } } }
    : { status: 200, body: { value: [{ internetMessageId: '<someone-else@x>', sentDateTime: '2026-10-30T06:00:00Z' }] } });
  await pollM365SentStatus(h.deps);
  assertEquals(h.recs.map((r) => [r.id, r.found, r.code]), [[1, false, 'm365:not_in_sent_items'], [2, false, 'http:403'], [3, false, 'm365:not_in_sent_items']]);
});

Deno.test('nothing claimed asks Graph nothing; missing secrets claim nothing', async () => {
  const h = harness([], () => ({ status: 500 }));
  assertEquals((await pollM365SentStatus(h.deps)).claimed, 0);
  assertEquals(h.urls.length, 0);
  let claimed = false;
  const g = harness([{ notification_id: 1, message_id: MID }], () => ({ status: 500 }), { MS_TENANT_ID: 't' });
  g.deps.claim = () => { claimed = true; return Promise.resolve([]); };
  const out = await pollM365SentStatus(g.deps);
  assert(!claimed && out.held === 'edge secrets not set');
});

// Review of #1792: an outage is not an answer about a send. A refused token records nothing; a 429/5xx or a timeout is
// handed over with its HTTP status, which fn_m365_sent_status_record does not count as a try (the probe proves that half).
Deno.test('a refused token records nothing, and the secret is never in the answer', async () => {
  const h = harness([{ notification_id: 7, message_id: MID }], () => ({ status: 200 }));
  h.deps.fetchFn = () => Promise.resolve(new Response(JSON.stringify({ error: 'invalid_client zz-demo-secret-0123456789' }), { status: 401 }));
  const out = await pollM365SentStatus(h.deps);
  assertEquals(h.recs, []);
  assert(out.ok === false && !String(out.why).includes(ENV.MS_CLIENT_SECRET));
});

Deno.test('a 429, a 503 and a timeout go over with no 200, so none of them can be counted as "not in Sent Items"', async () => {
  const rows = [1, 2, 3].map((i) => ({ notification_id: i, message_id: `<qd-notif-${i}.1@quotesdone.com>` }));
  const h = harness(rows, (url) => ({ status: url.includes('qd-notif-1.') ? 429 : 503 }));
  const real = h.deps.fetchFn;
  h.deps.fetchFn = (u, i) => u.includes('qd-notif-3.') ? Promise.reject(new Error('timed out')) : real(u, i);
  await pollM365SentStatus(h.deps);
  assertEquals(h.recs.map((r) => [r.id, r.http, r.code]), [[1, 429, 'http:429'], [2, 503, 'http:503'], [3, null, 'm365:no_answer']]);
});

// Review of #1792: the 6 tenant reports of 29-30 Oct were stored without headers; each is read again from Graph by its id.
Deno.test('a stored report is read again: the tenant\'s Internal stamp is recorded true, Anonymous or gone false, an outage nothing', async () => {
  const SYS = 'microsoftexchange329e71ec88ae4615bbc36ab6ce41109e@zz-demo.onmicrosoft.com';
  const msg = (authAs: string) => ({ status: 200, body: { from: { emailAddress: { address: SYS } }, internetMessageHeaders: [
    { name: 'X-MS-Exchange-Organization-AuthAs', value: authAs },
    { name: 'Authentication-Results', value: 'dmarc=fail header.from=zz-demo.onmicrosoft.com;compauth=fail reason=000' }] } });
  const h = harness([], (url) => url.includes('/messages/g1?') ? msg('Internal') : url.includes('/messages/g2?') ? msg('Anonymous')
    : url.includes('/messages/g3?') ? { status: 404 } : { status: 503 });
  const stamped: Array<[number, boolean]> = [];
  h.deps.headersDue = () => Promise.resolve([1, 2, 3, 4].map((i) => ({ inbound_id: i, graph_id: 'g' + i })));
  h.deps.headersRecord = (id, s) => { stamped.push([id, s]); return Promise.resolve(); };
  const out = await pollM365SentStatus(h.deps);
  assertEquals(stamped, [[1, true], [2, false], [3, false]]);
  assertEquals(out.reports_stamped, 1);
  assert(h.urls.filter((u) => u.includes('/messages/g')).every((u) => u.includes('internetMessageHeaders')));
});

Deno.test('the read-only measurement reports which stamp headers Graph returns, and writes nothing', async () => {
  const SYS = 'microsoftexchange329e71ec88ae4615bbc36ab6ce41109e@zz-demo.onmicrosoft.com';
  const h = harness([], (url) => {
    const f = new URL(url).searchParams.get('$filter') || '';
    if (f.includes('ndr-a')) return { status: 200, body: { value: [{ id: 'g1', from: { emailAddress: { address: SYS } }, internetMessageHeaders: [{ name: 'X-MS-Exchange-Message-Is-Ndr', value: '' }] }] } };
    if (f.includes('ndr-b')) return { status: 200, body: { value: [] } };
    return { status: 503 };
  });
  const methods: string[] = [];
  const fetchFn = h.deps.fetchFn;
  const out = await measureNdrHeaders({ env: h.deps.env, mailbox: 'supplier@quotesdone.com', messageIds: ['<ndr-a@x>', '<ndr-b@x>', '<ndr-c@x>'],
    fetchFn: (u, i) => { methods.push(String(i?.method || 'GET')); return fetchFn(u, i); } });
  const r = out.readings as Array<Record<string, unknown>>;
  assertEquals([r[0].recognised, r[0].is_ndr, r[0].auth_as, r[1].found, r[2].http], ['is_ndr', true, null, false, 503]);
  assertEquals(out.writes, 0);
  assert(methods.slice(1).every((m) => m === 'GET'), 'the measurement only reads');
});

Deno.test('a quote in a Message-ID is doubled, so the filter cannot be broken out of', () => {
  assertEquals(new URL(sentItemsUrl('supplier@quotesdone.com', "<a'b@x>")).searchParams.get('$filter'), "internetMessageId eq '<a''b@x>'");
});
