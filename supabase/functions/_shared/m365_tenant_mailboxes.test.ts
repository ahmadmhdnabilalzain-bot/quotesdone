// deno test supabase/functions/_shared/m365_tenant_mailboxes.test.ts
// Every mailbox of the tenant is read (2 Nov 2026, m365_reply_inbox.ts): supplier@'s Junk and pollTenantMailboxes, offline.
// Controls: the founder's mail is never handed, nothing outside supplier@ is ever marked, moved, deleted or replied to,
// random junk stays where it is, a failure elsewhere cannot touch supplier@'s proof, one busy mailbox cannot take the tick.
import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { DEFAULT_MAILBOXES, MAILBOX_HAND_CAP, TENANT_HAND_CAP, folderHands, pollReplyInbox, pollTenantMailboxes, type SenderKind, type TenantDeps } from './m365_reply_inbox.ts';

const ENV: Record<string, string> = { MS_TENANT_ID: 't', MS_CLIENT_ID: 'c', MS_CLIENT_SECRET: 'zz-demo-secret' };
const SIGNING = 'whsec_' + btoa('zz-demo-signing-key-0123456789abcdef');
const INBOUND = 'https://zz-demo.example.invalid/functions/v1/resend_inbound';
const MS = 'MicrosoftExchange329e71ec88ae4615bbc36ab6ce41109e@NETORGFT20811795.onmicrosoft.com';
const SUPPLIER = 'info@zz-demo-supplier.example.invalid';
const STRANGER = 'someone@zz-demo-stranger.example.invalid';
const FOUNDER = 'owner@zz-demo-founder.example.invalid';
const kinds: Record<string, SenderKind> = { [SUPPLIER]: 'known', [FOUNDER]: 'founder' };

type Box = { inbox?: Array<[string, string]>; junk?: Array<[string, string]>; filed?: Array<[string, string]>; status?: number };
const env = (id: string, from: string) => ({ id, subject: 'Hello', receivedDateTime: '2026-11-01T10:00:00Z', from: { emailAddress: { address: from } } });

function harness(boxes: Record<string, Box>, o: { users?: string[] | number; listed?: string; onFile?: string[]; handStatus?: number; now?: () => number } = {}) {
  const calls: Array<{ url: string; method: string; body?: string }> = [];
  const runs: Array<{ status: string; counts: Record<string, unknown>; note: string }> = [];
  const json = (b: unknown, s = 200) => Promise.resolve(new Response(JSON.stringify(b), { status: s }));
  const deps: TenantDeps = {
    fetchFn: (url, init) => {
      const method = init?.method || 'GET';
      calls.push({ url, method, body: init?.body ? String(init.body) : undefined });
      if (url.startsWith('https://login.microsoftonline.com/')) return json({ access_token: 'g' });
      if (url.includes('/users?')) return typeof o.users === 'number' ? json({ error: { code: 'x' } }, o.users) : json({ value: (o.users || []).map((mail) => ({ mail })) });
      if (url.startsWith(INBOUND)) return json({ ok: true }, o.handStatus ?? 200);
      if (method === 'PATCH') return json({});
      const box = decodeURIComponent(url.split('/users/')[1].split('/')[0]);
      const b = boxes[box] || { status: 404 };
      if (b.status) return json({ error: { code: 'x' } }, b.status);
      if (url.includes('/mailFolders?')) return json({ value: [{ id: 'SENT', displayName: 'Sent Items' }, { id: 'FILED', displayName: 'info quotesdone' }] });
      if (url.includes('/mailFolders/SENT/')) throw new Error('a system folder was swept');
      if (url.includes('/mailFolders/')) {
        const list = url.includes('/mailFolders/junkemail/') ? b.junk : url.includes('/mailFolders/FILED/') ? b.filed : b.inbox;
        return json({ value: (list || []).map(([id, from]) => env(id, from)) });
      }
      const id = decodeURIComponent(url.split('/messages/')[1].split('?')[0]);
      return json({ ...env(id, 'x'), internetMessageId: `<${id}@x>`, body: { contentType: 'text', content: 'Please register our subsidiary.' }, internetMessageHeaders: [] });
    },
    env: (k) => ENV[k], inviteMailbox: 'supplier@quotesdone.com', listedMailboxes: o.listed,
    inboundToken: 'zz', signingSecret: SIGNING, inboundUrl: INBOUND,
    onFile: (ids) => Promise.resolve(new Set(ids.filter((i) => (o.onFile || []).includes(i)))),
    sender: (a) => Promise.resolve(kinds[a] ?? null),
    record: (status, counts, note) => { runs.push({ status, counts, note }); return Promise.resolve(); },
    now: o.now,
  };
  const hands = () => calls.filter((c) => c.url.startsWith(INBOUND)).map((c) => JSON.parse(String(c.body)).data);
  const writes = () => calls.filter((c) => c.method !== 'GET' && !c.url.startsWith(INBOUND) && !c.url.startsWith('https://login.'));
  return { deps, calls, runs, hands, writes };
}

Deno.test('every real mail in management@ is handed, addressed to that mailbox, and NOTHING there is marked or changed', async () => {
  const h = harness({ 'management@quotesdone.com': { inbox: [['S1', SUPPLIER], ['X1', STRANGER]] } }, { users: ['management@quotesdone.com'] });
  const r = await pollTenantMailboxes(h.deps);
  assertEquals(r.handed, 2); assertEquals(r.source, 'graph');
  assertEquals(h.hands().map((d) => d.to), ['management@quotesdone.com', 'management@quotesdone.com']);
  assertEquals(h.hands()[0].email_id, 'm365:X1', 'oldest first');
  assertEquals(h.hands()[0].text, 'Please register our subsidiary.', 'the body is read for the hand-off');
  assertEquals(h.writes(), [], 'known-bad control: a PATCH, DELETE, move or send in a person\'s mailbox');
});

Deno.test('control: the founder\'s mail and our own domain are not handed, read in full, or marked', async () => {
  const h = harness({ 'management@quotesdone.com': { inbox: [['F1', FOUNDER], ['O1', 'noreply@mail.quotesdone.com'], ['O2', 'someone@quotesdone.ae']] } }, { users: ['management@quotesdone.com'] });
  const r = await pollTenantMailboxes(h.deps);
  assertEquals(r.handed, 0); assertEquals(r.not_handed, 3);
  assertEquals(h.hands(), []); assertEquals(h.writes(), []);
  assertFalse(h.calls.some((c) => c.url.includes('/messages/F1')), 'his message body was fetched');
});

Deno.test('idempotent: a message already on file is not handed again; mail not handed never stops an older one being found', async () => {
  const h = harness({ 'management@quotesdone.com': { inbox: [['F1', FOUNDER], ['S1', SUPPLIER]] } }, { users: ['management@quotesdone.com'], onFile: ['m365:S1'] });
  assertEquals((await pollTenantMailboxes(h.deps)).handed, 0);
  assertEquals(h.hands(), []);
});

Deno.test('a filed folder is read under the Inbox rules, unmarked; a system folder is not', async () => {
  const h = harness({ 'management@quotesdone.com': { filed: [['F9', SUPPLIER], ['F8', FOUNDER]] } }, { users: ['management@quotesdone.com'] });
  const r = await pollTenantMailboxes(h.deps);
  assertEquals(h.hands().map((d) => d.email_id), ['m365:F9']);
  assertEquals(h.writes(), []); assertEquals(r.list_failed, 0);
});

Deno.test('Junk in any mailbox: a delivery report and a known sender are handed, a stranger never', async () => {
  const h = harness({ 'info@quotesdone.com': { junk: [['J1', STRANGER], ['J2', MS], ['J3', SUPPLIER], ['J4', 'postmaster@zz-demo.example.invalid']] } }, { users: ['info@quotesdone.com'] });
  const r = await pollTenantMailboxes(h.deps);
  assertEquals(h.hands().map((d) => d.email_id).sort(), ['m365:J2', 'm365:J3', 'm365:J4']);
  assertEquals(r.not_handed, 1); assertEquals(h.writes(), []);
  assertEquals(folderHands('junkemail', STRANGER, null), false);
  assertEquals(folderHands('inbox', STRANGER, null), true);
  assertEquals(folderHands('junkemail', FOUNDER, 'founder'), false);
});

Deno.test('Graph refuses the /users list: app_secrets, then the two named mailboxes; expenses@ and supplier@ are never swept', async () => {
  const listed = harness({ 'sales@quotesdone.com': { inbox: [['A', STRANGER]] } }, { users: 403, listed: 'sales@quotesdone.com, expenses@quotesdone.com, supplier@quotesdone.com, x@elsewhere.example.invalid' });
  const a = await pollTenantMailboxes(listed.deps);
  assertEquals(a.source, 'app_secrets'); assertEquals(a.handed, 1); assertEquals(a.mailboxes, 1);
  for (const bad of ['expenses%40', 'supplier%40', 'elsewhere']) assertFalse(listed.calls.some((c) => c.url.includes(bad)), bad);
  const none = harness(Object.fromEntries(DEFAULT_MAILBOXES.map((m) => [m, {}])), { users: 403 });
  const b = await pollTenantMailboxes(none.deps);
  assertEquals(b.source, 'default'); assertEquals(b.mailboxes, DEFAULT_MAILBOXES.length);
});

Deno.test('an account with no mailbox is skipped; a refused mailbox does not stop the next', async () => {
  const h = harness({ 'a@quotesdone.com': { status: 404 }, 'b@quotesdone.com': { status: 403 }, 'c@quotesdone.com': { inbox: [['C', STRANGER]] } },
    { users: ['a@quotesdone.com', 'b@quotesdone.com', 'c@quotesdone.com', 'nobody@zz-other.example.invalid'] });
  const r = await pollTenantMailboxes(h.deps);
  assertEquals(r.no_mailbox, 1); assertEquals(r.refused, 1); assertEquals(r.mailboxes, 1); assertEquals(r.handed, 1);
  assertEquals(h.runs[0].status, 'ok');
});

Deno.test('a busy mailbox takes at most its cap, and the tick has a ceiling', async () => {
  const many = (p: string, n: number) => Array.from({ length: n }, (_, i): [string, string] => [p + i, STRANGER]);
  const boxes = Object.fromEntries(Array.from({ length: 5 }, (_, i) => [`m${i}@quotesdone.com`, { inbox: many('B' + i, 20) }]));
  const h = harness(boxes, { users: Object.keys(boxes), now: () => 0 });
  const r = await pollTenantMailboxes(h.deps);
  const per: Record<string, number> = {};
  for (const d of h.hands()) per[d.to] = (per[d.to] || 0) + 1;
  assert(Object.values(per).every((n) => n <= MAILBOX_HAND_CAP), JSON.stringify(per));
  assertEquals(r.handed, TENANT_HAND_CAP);
  assert((r.deferred as number) > 0);
});

Deno.test('the tenant row can never be, or withdraw, the supplier@ proof', async () => {
  const h = harness({ 'management@quotesdone.com': { inbox: [['S1', SUPPLIER]] } }, { users: ['management@quotesdone.com'], handStatus: 500 });
  const r = await pollTenantMailboxes(h.deps);
  assertEquals(r.hand_failed, 1); assertEquals(h.runs[0].status, 'error');
  assertEquals(h.runs[0].counts.m365_tenant, 1);
  assertFalse('m365_inbox' in h.runs[0].counts, 'send_outbox selects counts.m365_inbox = 1');
  assertFalse(JSON.stringify(r).includes('management@'), 'resilience_ping is public: the answer names no mailbox');
  assert(h.runs[0].note.includes('none') || h.runs[0].note.includes('management@'));
});

Deno.test('supplier@ Junk: reports and known senders handed and marked; random junk untouched; a Junk failure keeps the proof', async () => {
  const run = async (junkStatus: number | null) => {
    const handed: string[] = []; const patched: string[] = []; const runs: string[] = [];
    const json = (b: unknown, s = 200) => Promise.resolve(new Response(JSON.stringify(b), { status: s }));
    const r = await pollReplyInbox({
      fetchFn: (url, init) => {
        if (url.startsWith('https://login.')) return json({ access_token: 'g' });
        if (url.includes('/mailFolders/inbox/')) return json({ value: [] });
        if (url.includes('/mailFolders/junkemail/')) return junkStatus ? json({}, junkStatus) : json({ value: [env('J1', MS), env('J2', STRANGER), env('J3', SUPPLIER)] });
        if (url.startsWith(INBOUND)) { handed.push(JSON.parse(String(init?.body)).data.email_id); return json({ ok: true }); }
        if (init?.method === 'PATCH') { patched.push(url); return json({}); }
        return json({ ...env(url.split('/messages/')[1].split('?')[0], 'x'), body: { contentType: 'text', content: 'x' } });
      },
      env: (k) => ENV[k], mailbox: 'supplier@quotesdone.com', inboundToken: 'zz', signingSecret: SIGNING, inboundUrl: INBOUND,
      onFile: () => Promise.resolve(new Set<string>()), fileFinding: () => Promise.resolve(),
      record: (s) => { runs.push(s); return Promise.resolve(); }, sender: (a) => Promise.resolve(kinds[a] ?? null),
    });
    return { r, handed, patched, runs };
  };
  const ok = await run(null);
  assertEquals(ok.handed.sort(), ['m365:J1', 'm365:J3']);
  assertEquals(ok.patched.length, 2); assertFalse(ok.patched.some((u) => u.includes('J2')));
  assertEquals(ok.r.junk_not_handed, 1); assertEquals(ok.runs, ['ok']);
  const failed = await run(503);
  assertEquals(failed.runs, ['ok'], 'a Junk failure withdrew the proof'); assertEquals(failed.r.junk_failed, 1);
});
