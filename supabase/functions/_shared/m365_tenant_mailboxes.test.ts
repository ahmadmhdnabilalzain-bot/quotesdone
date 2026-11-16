// deno test supabase/functions/_shared/m365_tenant_mailboxes.test.ts
// Every mailbox of the tenant is read (2 Nov 2026, m365_reply_inbox.ts): supplier@'s Junk and pollTenantMailboxes, offline.
// Controls: the founder's mail is never handed, nothing outside supplier@ is ever marked, moved, deleted or replied to,
// random junk stays where it is, a failure elsewhere cannot touch supplier@'s proof, one busy mailbox cannot take the tick.
import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { isCustomerCorrespondence, noAutoReply } from './customer_mail.ts';
import { DEFAULT_MAILBOXES, MAILBOX_HAND_CAP, TENANT_HAND_CAP, folderHands, inboundOnFile, pollReplyInbox, pollTenantMailboxes, type OnFileDb, type SenderKind, type TenantDeps } from './m365_reply_inbox.ts';

const ENV: Record<string, string> = { MS_TENANT_ID: 't', MS_CLIENT_ID: 'c', MS_CLIENT_SECRET: 'zz-demo-secret' };
const SIGNING = 'whsec_' + btoa('zz-demo-signing-key-0123456789abcdef');
const INBOUND = 'https://zz-demo.example.invalid/functions/v1/resend_inbound';
const MS = 'MicrosoftExchange329e71ec88ae4615bbc36ab6ce41109e@NETORGFT20811795.onmicrosoft.com';
const SUPPLIER = 'info@zz-demo-supplier.example.invalid';
const STRANGER = 'someone@zz-demo-stranger.example.invalid';
const FOUNDER = 'owner@zz-demo-founder.example.invalid';
const kinds: Record<string, SenderKind> = { [SUPPLIER]: 'known', [FOUNDER]: 'founder' };

type Row = [string, string, Record<string, unknown>?];
type Box = { inbox?: Row[]; junk?: Row[]; filed?: Row[]; status?: number };
const env = (id: string, from: string) => ({ id, subject: 'Hello', receivedDateTime: '2026-11-01T10:00:00Z', from: { emailAddress: { address: from } } });

const CUTOFF = '2026-10-01T00:00:00Z';
function harness(boxes: Record<string, Box>, o: { users?: string[] | number; listed?: string; onFile?: string[]; handStatus?: number; now?: () => number; strangersFrom?: string | null; financial?: string; attachments?: unknown[]; messages?: string[] } = {}) {
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
      if (url.includes('/attachments')) return json({ value: o.attachments || [] });
      if (url.includes('/mailFolders?')) return json({ value: [{ id: 'SENT', displayName: 'Sent Items' }, { id: 'FILED', displayName: 'info quotesdone' }] });
      if (url.includes('/mailFolders/SENT/')) throw new Error('a system folder was swept');
      if (url.includes('/mailFolders/')) {
        const list = url.includes('/mailFolders/junkemail/') ? b.junk : url.includes('/mailFolders/FILED/') ? b.filed : b.inbox;
        return json({ value: (list || []).map(([id, from, extra]) => ({ ...env(id, from), ...(extra || {}) })) });
      }
      const id = decodeURIComponent(url.split('/messages/')[1].split('?')[0]);
      return json({ ...env(id, 'x'), internetMessageId: `<${id}@x>`, body: { contentType: 'text', content: 'Please register our subsidiary.' }, internetMessageHeaders: [] });
    },
    env: (k) => ENV[k], inviteMailbox: 'supplier@quotesdone.com', listedMailboxes: o.listed,
    strangersFrom: o.strangersFrom === null ? undefined : (o.strangersFrom ?? CUTOFF), financialDomains: o.financial,
    messageOnFile: (ids) => Promise.resolve(new Set(ids.filter((i) => (o.messages || []).includes(i)))),
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

Deno.test('Junk in another mailbox: only a known sender; a stranger and a delivery report are not handed', async () => {
  const h = harness({ 'info@quotesdone.com': { junk: [['J1', STRANGER], ['J2', MS], ['J3', SUPPLIER], ['J4', 'postmaster@zz-demo.example.invalid']] } }, { users: ['info@quotesdone.com'] });
  const r = await pollTenantMailboxes(h.deps);
  assertEquals(h.hands().map((d) => d.email_id), ['m365:J3']);
  assertEquals(h.writes(), []); assertEquals(r.handed, 1);
  assertEquals(folderHands('junkemail', STRANGER, null), false);
  assertEquals(folderHands('inbox', STRANGER, null), true);
  assertEquals(folderHands('junkemail', FOUNDER, 'founder'), false);
});

const ONE = { users: ['management@quotesdone.com'] };
const box1 = (inbox: Row[]) => ({ 'management@quotesdone.com': { inbox } });

Deno.test('known-bad control: an old stranger is not handed, a stranger after the cutoff is; a known sender and a reply in our thread keep the lookback', async () => {
  const old = harness(box1([['OLD', STRANGER, { receivedDateTime: '2026-09-20T00:00:00Z' }]]), ONE);
  assertEquals((await pollTenantMailboxes(old.deps)).skipped, 1); assertEquals(old.hands(), []);
  const none = harness(box1([['NEW', STRANGER]]), { ...ONE, strangersFrom: null });
  assertEquals((await pollTenantMailboxes(none.deps)).skipped, 1, 'no cutoff stored: no stranger');
  const bad = harness(box1([['NEW', STRANGER]]), { ...ONE, strangersFrom: 'not a date' });
  assertEquals((await pollTenantMailboxes(bad.deps)).handed, 0);
  const fresh = harness(box1([['NEW', STRANGER]]), ONE);
  assertEquals((await pollTenantMailboxes(fresh.deps)).handed, 1);
  const known = harness(box1([['K', SUPPLIER, { receivedDateTime: '2026-09-20T00:00:00Z' }]]), { ...ONE, strangersFrom: null });
  assertEquals((await pollTenantMailboxes(known.deps)).handed, 1);
  const hdr = (v: string) => ({ receivedDateTime: '2026-09-20T00:00:00Z', internetMessageHeaders: [{ name: 'In-Reply-To', value: v }] });
  const ours = harness(box1([['T', STRANGER, hdr('<qd-notif-1.2@quotesdone.com>')]]), { ...ONE, strangersFrom: null });
  assertEquals((await pollTenantMailboxes(ours.deps)).handed, 1);
  const thread = harness(box1([['T', STRANGER, hdr('<their-first@x.invalid>')]]), { ...ONE, strangersFrom: null, messages: ['<their-first@x.invalid>'] });
  assertEquals((await pollTenantMailboxes(thread.deps)).handed, 1);
  const elsewhere = harness(box1([['T', STRANGER, hdr('<other@x.invalid>')]]), { ...ONE, strangersFrom: null });
  assertEquals((await pollTenantMailboxes(elsewhere.deps)).handed, 0);
});

Deno.test('known-bad control: a Mashreq alert, machine senders, a listed domain and a DMARC report are counted only; no body is read', async () => {
  const senders = ['alerts@mashreqbank.com', 'x@mail.mashreq.com', 'alert@zz.example.invalid', 'no-reply@zz.example.invalid', 'dmarc@zz.example.invalid', 'report@zz.example.invalid', 'billing@zz.example.invalid', 'statement@zz.example.invalid', 'a@zz-bank.example.invalid', MS];
  const h = harness(box1(senders.map((s, i): Row => ['M' + i, s])), { ...ONE, financial: 'zz-bank.example.invalid' });
  const r = await pollTenantMailboxes(h.deps);
  assertEquals(r.skipped, senders.length); assertEquals(h.hands(), []);
  assertFalse(h.calls.some((c) => /\/messages\/M\d+\?/.test(c.url)), 'a body was read');
  const d = harness(box1([['D', STRANGER, { hasAttachments: true }]]), { ...ONE, attachments: [{ name: 'google.com!quotesdone.com!1700000000!1700086400.xml.gz', contentType: 'application/gzip', size: 900 }] });
  assertEquals((await pollTenantMailboxes(d.deps)).skipped, 1); assertEquals(d.hands(), []);
  const bank = harness(box1([['B', 'info@mashreq.com']]), { ...ONE });
  kinds['info@mashreq.com'] = 'known';
  assertEquals((await pollTenantMailboxes(bank.deps)).handed, 0, 'a financial domain is refused even when known');
  delete kinds['info@mashreq.com'];
});

Deno.test('one message, one answer: the same internetMessageId across mailboxes, or already on file, is handed once', async () => {
  const same = { internetMessageId: '<same@x.invalid>' };
  const h = harness({ 'a@quotesdone.com': { inbox: [['A', STRANGER, same]] }, 'b@quotesdone.com': { inbox: [['B', STRANGER, same]] } }, { users: ['a@quotesdone.com', 'b@quotesdone.com'] });
  const r = await pollTenantMailboxes(h.deps);
  assertEquals(r.handed, 1); assertEquals(r.same_message, 1);
  const f = harness(box1([['C', STRANGER, same]]), { ...ONE, messages: ['<same@x.invalid>'] });
  assertEquals((await pollTenantMailboxes(f.deps)).same_message, 1);
});

// 15 Nov 2026 (review of the inbound queue): resend_inbound now only QUEUES a hand-over (public.inbound_mail_queue) and reads it
// later, so supplier@'s copy is not yet in inbound_messages when the tenant sweep, run right after it, looks for its Message-ID.
// The lookups the tick wires in (inboundOnFile, integrations.ts) read the queue too. The tables here are in memory.
type Tables = { inbound_messages?: Array<{ provider_email_id: string; raw?: { message_id?: string } }>; inbound_mail_queue?: Array<{ provider_email_id: string; message_id: string | null }>; fail?: string };
const memDb = (t: Tables): OnFileDb => ({
  from: (table) => ({ select: (cols) => ({ in: (col, ids) => {
    if (t.fail === table) return Promise.resolve({ data: null, error: { message: 'permission denied' } });
    // deno-lint-ignore no-explicit-any
    const rows: any[] = (t as any)[table] || [];
    const val = (r: { raw?: { message_id?: string } } & Record<string, unknown>) => col === 'raw->>message_id' ? r.raw?.message_id : r[col];
    const alias = cols.includes(':') ? cols.split(':')[0] : cols;
    return Promise.resolve({ data: rows.filter((r) => ids.includes(String(val(r)))).map((r) => ({ [alias]: val(r) })), error: null });
  } }) }),
});

Deno.test('one message, one answer, while supplier@\'s copy is only queued: the tenant sweep reads the queue too', async () => {
  const same = { internetMessageId: '<queued@x.invalid>' };
  // supplier@'s copy was handed this tick and is waiting in the queue; inbound_messages does not have it yet
  const queued: Tables = { inbound_messages: [], inbound_mail_queue: [{ provider_email_id: 'm365:SUPPLIER-COPY', message_id: '<queued@x.invalid>' }] };
  const h = harness(box1([['MGMT-COPY', STRANGER, same]]), ONE);
  Object.assign(h.deps, inboundOnFile(memDb(queued)));
  const r = await pollTenantMailboxes(h.deps);
  assertEquals([r.handed, r.same_message], [0, 1], JSON.stringify(r));
  assertEquals(h.hands().length, 0, 'the tenant copy was not handed a second time');
  // known-bad control: the lookup the tick used before (inbound_messages only) hands it again
  const before = harness(box1([['MGMT-COPY', STRANGER, same]]), ONE);
  Object.assign(before.deps, inboundOnFile(memDb({ inbound_messages: [], inbound_mail_queue: [] })));
  assertEquals((await pollTenantMailboxes(before.deps)).handed, 1);
});

Deno.test('inboundOnFile: a Graph id or a Message-ID is on file when read OR queued; a table it cannot read is an error, not "new"', async () => {
  const db = memDb({ inbound_messages: [{ provider_email_id: 'm365:READ', raw: { message_id: '<read@x>' } }],
    inbound_mail_queue: [{ provider_email_id: 'm365:QUEUED', message_id: '<queued@x>' }, { provider_email_id: 'zz-resend-1', message_id: null }] });
  const f = inboundOnFile(db);
  assertEquals([...await f.onFile(['m365:READ', 'm365:QUEUED', 'm365:NEW'])].sort(), ['m365:QUEUED', 'm365:READ']);
  assertEquals([...await f.messageOnFile(['<read@x>', '<queued@x>', '<new@x>'])].sort(), ['<queued@x>', '<read@x>']);
  assertEquals((await f.messageOnFile([])).size, 0);
  let threw = '';
  try { await inboundOnFile(memDb({ fail: 'inbound_mail_queue' })).messageOnFile(['<a@x>']); } catch (e) { threw = String((e as Error).message); }
  assert(threw.startsWith('inbound_mail_queue: '), threw);
});

Deno.test('oversized attachments are not fetched, the message still is; the tick stops when its time is up', async () => {
  const h = harness(box1([['BIG', STRANGER, { hasAttachments: true }]]), { ...ONE, attachments: [{ name: 'a.pdf', contentType: 'application/pdf', size: 20 * 1024 * 1024 }] });
  const r = await pollTenantMailboxes(h.deps);
  assertEquals(r.handed, 1); assertEquals(r.attachments_dropped, 1);
  assertFalse(h.calls.some((c) => c.url.endsWith('/attachments')), 'the bytes were fetched');
  let t = 0;
  const slow = harness({ 'a@quotesdone.com': { inbox: [['A', STRANGER]] }, 'b@quotesdone.com': {} }, { users: ['a@quotesdone.com', 'b@quotesdone.com'], now: () => (t += 16_000) });
  assert(((await pollTenantMailboxes(slow.deps)).out_of_time as number) >= 1);
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
  // a@ plus the two named mailboxes (management@, info@), which are always asked for and have no box in this harness
  assertEquals(r.no_mailbox, 3); assertEquals(r.refused, 1); assertEquals(r.mailboxes, 1); assertEquals(r.handed, 1);
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

Deno.test('known-bad control: Graph lists only management@, yet info@ is still asked for; an alias answers 404 and the note names it', async () => {
  const asked = harness({ 'management@quotesdone.com': { inbox: [['S1', SUPPLIER]] }, 'info@quotesdone.com': { inbox: [['S2', SUPPLIER]] } }, { users: ['management@quotesdone.com'] });
  const r = await pollTenantMailboxes(asked.deps);
  assertEquals(r.source, 'graph'); assertEquals(r.mailboxes, 2);
  assertEquals(asked.hands().map((d) => d.to).sort(), ['info@quotesdone.com', 'management@quotesdone.com']);
  const alias = harness({ 'management@quotesdone.com': { inbox: [['S1', SUPPLIER]] } }, { users: ['management@quotesdone.com'] });
  const a = await pollTenantMailboxes(alias.deps);
  assertEquals(a.no_mailbox, 1); assertEquals(a.handed, 1);
  assert(alias.runs[0].note.includes('no mailbox: info@quotesdone.com'), alias.runs[0].note);
  assertEquals(alias.writes(), []);
});

// A REPLY TO A SIGN-IN CODE OR A KYC MAIL REACHES THE SEATS (16 Nov 2026, it_engineer; ledger 1446, 1453, 1543). Both mails
// leave from and reply to info@quotesdone.com (login_otp, kyc). The person replying is usually a sign-up that is not yet a
// customer or a lead, and the In-Reply-To names the Message-ID Resend gave the code mail, not one of ours. MEASURED 16 Nov:
// every tenant tick read info@ and skipped 134-136 such mails, inbound_messages held 0 rows for info@ in 60 days, because
// app_secrets.m365_tenant_strangers_from was never set. The canon now sets it at apply
// (scripts/sql/a_stranger_writing_to_info_or_management_reaches_the_seats.sql); this pins both halves.
Deno.test('a reply to a sign-in code in info@ reaches resend_inbound addressed to info@, and triage answers it; the canon sets the switch', async () => {
  // 1. the decision has a home: a file in scripts/sql sets the switch (fails before that file exists)
  const setters: string[] = [];
  for (const e of Deno.readDirSync('scripts/sql')) {
    if (!e.isFile || !e.name.endsWith('.sql') || e.name.endsWith('_probe.sql')) continue;
    const t = Deno.readTextFileSync('scripts/sql/' + e.name);
    if (/insert\s+into\s+public\.app_secrets[\s\S]{0,80}'m365_tenant_strangers_from'/i.test(t)) setters.push(e.name);
  }
  assertEquals(setters, ['a_stranger_writing_to_info_or_management_reaches_the_seats.sql'], 'one file in the SQL canon sets the stranger switch');
  // 2. with the switch, the sign-in reply is handed, addressed to info@; a bank and a no-reply sender are not
  const SIGNUP = 'new.signup@zz-demo-customer.example.invalid';
  const reply = { subject: 'Re: Your QuotesDone sign-in code', internetMessageHeaders: [{ name: 'In-Reply-To', value: '<0100019a-zz-demo@email.amazonses.com>' }] };
  const box = { 'info@quotesdone.com': { inbox: [['R1', SIGNUP, reply], ['B1', 'alerts@mashreqbank.com'], ['N1', 'no-reply@zz-demo-vendor.example.invalid']] as Row[] } };
  const on = harness(box, { users: ['info@quotesdone.com'] });
  const r = await pollTenantMailboxes(on.deps);
  assertEquals(on.hands().map((d) => [d.email_id, d.to]), [['m365:R1', 'info@quotesdone.com']]);
  assertEquals(r.handed, 1); assertEquals(on.writes(), [], 'nothing in info@ is marked, moved or answered from here');
  // 3. ...and email_triage treats it as a customer's mail it answers (not internal, not a machine, not a founder address)
  const row = { from_email: SIGNUP, to_email: 'info@quotesdone.com', subject: reply.subject, body: 'I did not get the code, can you help?', raw: {} };
  assert(isCustomerCorrespondence(row)); assertEquals(noAutoReply(row, []), null);
  // known-bad control: the state measured on production (no switch) hands nothing; nor does a reply older than the switch
  const off = harness(box, { users: ['info@quotesdone.com'], strangersFrom: null });
  assertEquals((await pollTenantMailboxes(off.deps)).handed, 0); assertEquals(off.hands(), []);
  const late = harness(box, { users: ['info@quotesdone.com'], strangersFrom: '2026-11-02T00:00:00Z' });
  assertEquals((await pollTenantMailboxes(late.deps)).handed, 0, 'mail received before the switch is never answered');
});
