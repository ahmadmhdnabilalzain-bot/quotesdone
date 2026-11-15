// deno test --allow-all supabase/functions/resend_inbound/m365_stop_reply.test.ts
// A "stop" reply to the Microsoft 365 invitation mailbox suppresses its sender (19 Oct 2026, marketing +
// it_engineer, release review of #1524: the invitation's body link is gone, so "reply stop" is a stated opt-out).
// The WHOLE path, offline: a Graph Inbox listing holds one fixture reply -> _shared/m365_reply_inbox.ts's own
// pollReplyInbox hands it over, Svix-signed, -> resend_inbound's own handler -> a POST to email_suppressions.
// Every database call is a stub (nothing touches production); no value is real: example.invalid, ZZ DEMO.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { pollReplyInbox, pollTenantMailboxes } from '../_shared/m365_reply_inbox.ts';

const SIGNING = 'whsec_' + btoa(String.fromCharCode(...new Uint8Array(32).map((_, i) => i + 7)));
const TOKEN = 'zz-demo-inbound-token';
const SECRETS: Record<string, string> = {
  resend_inbound_token: TOKEN, resend_inbound_signing_secret: SIGNING,
  admin_emails: 'management@example.invalid', expense_forwarders: 'founder@example.invalid',
};
Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
Deno.env.set('RESEND_INBOUND_NO_SERVE', '1');

const SUPPLIER = 'owner@zz-demo-tiling.example';
// EOP's own verdict comes first in Graph's header list; the sender's internal one sits below it.
const EOP = 'spf=pass (sender IP is 192.0.2.1) smtp.mailfrom=zz-demo-tiling.example; dkim=pass (signature was verified) ' +
  'header.d=zz-demo-tiling.example;dmarc=pass action=none header.from=zz-demo-tiling.example;compauth=pass reason=100';
const STATE = { invited: 1, ar: EOP };
const suppressions: Array<Record<string, unknown>> = [];
const review: string[] = [];

const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json' } });
globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init); const u = new URL(req.url);
  const body = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text();
  if (u.hostname !== 'stub.invalid') return json({ error: 'not found' }, 404);
  if (u.pathname === '/rest/v1/email_suppressions' && req.method === 'POST') { suppressions.push(...[JSON.parse(body)].flat()); return json([{}], 201); }
  if (u.pathname === '/rest/v1/inbound_messages' && req.method === 'POST') {
    const r = [JSON.parse(body)].flat()[0]; if (r.needs_review) review.push(String(r.body).slice(0, 160)); return json([{ id: 1 }], 201);
  }
  if (u.pathname === '/rest/v1/inbound_messages' && req.method === 'GET') return json([]);
  if (u.pathname === '/rest/v1/notifications' && req.method === 'HEAD') {
    return new Response(null, { status: 200, headers: { 'Content-Range': '*/' + STATE.invited } });
  }
  if (u.pathname.startsWith('/rest/v1/rpc/')) return json({ ok: true });
  const one = (req.headers.get('Accept') || '').includes('vnd.pgrst.object');
  if (u.pathname === '/rest/v1/app_secrets') {
    const v = SECRETS[(u.searchParams.get('key') || '').replace(/^eq\./, '')];
    if (v === undefined) return one ? json({ message: 'none' }, 406) : json([]);
    return one ? json({ value: v }) : json([{ value: v }]);
  }
  return one ? json({ id: 1 }) : json([{ id: 1 }]);
}) as typeof fetch;
// The webhook records a delivery and the queue's reader reads it after the answer (15 Nov 2026, lib/queue.ts); this test reads
// it at once through the same two halves the reader is built from: the signature check, then pipeline.ts.
const { authenticate } = await import('./steps/authenticate.ts');
const { readDelivery } = await import('./pipeline.ts');
const handler = async (req: Request) => { const a = await authenticate({ req }); return a instanceof Response ? a : await readDelivery(a); };

/** Microsoft's side: the token, one Inbox page holding the fixture reply, the mark-as-read; the handover reaches the real handler. */
function graph(text: string) {
  return async (url: string, init?: RequestInit): Promise<Response> => {
    if (url.startsWith('https://login.microsoftonline.com/')) return json({ access_token: 'zz-demo-graph-token' });
    if (url.includes('/mailFolders/inbox/messages')) {
      return json({ value: [{
        id: 'AAMkZZDEMO' + text.length, internetMessageId: '<zz-demo@example.invalid>', subject: 'Re: Flooring quote requests for ZZ Demo Tiling',
        receivedDateTime: new Date().toISOString(), hasAttachments: false, from: { emailAddress: { address: SUPPLIER } },
        body: { contentType: 'text', content: text },
        internetMessageHeaders: [
          { name: 'Authentication-Results', value: STATE.ar },
          { name: 'Authentication-Results', value: 'dkim=none (message not signed) header.d=none;dmarc=none action=none header.from=zz-demo-tiling.example' },
        ],
      }] });
    }
    if (url.startsWith('http://inbound.invalid/')) return await handler(new Request(url, init));
    if (init?.method === 'PATCH') return new Response(null, { status: 200 });
    return json({ error: 'unexpected ' + url }, 500);
  };
}
const SECRET_ENV: Record<string, string> = { MS_TENANT_ID: 'zz', MS_CLIENT_ID: 'zz', MS_CLIENT_SECRET: 'zz-demo-secret' };
const tick = (text: string) => pollReplyInbox({
  fetchFn: graph(text), env: (k) => SECRET_ENV[k], mailbox: 'supplier@quotesdone.com', inboundToken: TOKEN, signingSecret: SIGNING,
  inboundUrl: 'http://inbound.invalid/functions/v1/resend_inbound', onFile: () => Promise.resolve(new Set<string>()),
  fileFinding: () => Promise.resolve(null), record: () => Promise.resolve(null),
});

Deno.test('a "stop" reply to the M365 mailbox is handed to resend_inbound and writes an email_suppressions row', async () => {
  suppressions.length = 0; review.length = 0;
  const r = await tick('Stop\n\nOn Mon, Ahmad Alzain wrote:\n> Hi ZZ Demo Tiling team,');
  assertEquals(r.handed, 1, JSON.stringify(r));
  assertEquals(suppressions.length, 1, 'no suppression written; review: ' + review.join(' | '));
  assertEquals(suppressions[0].email, SUPPLIER);
  assertEquals(suppressions[0].reason, 'unsubscribe');
});

Deno.test('a known supplier\'s reply to our inbound_reply, landing in management@: threaded, linked by sender, nothing marked', async () => {
  const rows: Array<Record<string, unknown>> = [];
  const real = globalThis.fetch;
  globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
    const req = new Request(input, init); const u = new URL(req.url);
    if (u.pathname === '/rest/v1/inbound_messages' && req.method === 'POST') { rows.push(...[JSON.parse(await req.clone().text())].flat()); return json([{ id: 1 }], 201); }
    if (u.pathname === '/rest/v1/leads' && req.method === 'GET') return (req.headers.get('Accept') || '').includes('vnd.pgrst.object') ? json({ id: 19398, company_name: 'ZZ DEMO' }) : json([{ id: 19398, company_name: 'ZZ DEMO' }]);
    return await real(input, init);
  }) as typeof fetch;
  const marks: string[] = [];
  const fresh = (url: string, init?: RequestInit): Promise<Response> => {
    if (init?.method === 'PATCH') marks.push(url);
    // info@ is always asked for now (ledger 1446); in this test it has no mailbox, so the reply is read from management@ only
    if (/\/users\/info(@|%40)quotesdone\.com\//i.test(url)) return Promise.resolve(json({ error: { code: 'MailboxNotEnabledForRESTAPI' } }, 404));
    if (url.includes('/mailFolders/junkemail/') || url.includes('/mailFolders?') || url.includes('/users?')) return Promise.resolve(json({ value: url.includes('/users?') ? [{ mail: 'management@quotesdone.com' }] : [] }));
    if (url.includes('/messages/') && !url.startsWith('http://inbound.invalid/')) return Promise.resolve(json({ id: 'AAMkFRESH', internetMessageId: '<zz-demo-reply@example.invalid>', subject: 'Re: Your message', from: { emailAddress: { address: SUPPLIER } }, body: { contentType: 'text', content: 'We would like to register our subsidiary M/s ZZ DEMO FZE LLC' },
      internetMessageHeaders: [{ name: 'In-Reply-To', value: '<qd-notif-117599.1700000000000@quotesdone.com>' }, { name: 'References', value: '<qd-notif-117599.1700000000000@quotesdone.com>' }] }));
    return graph('We wish to register our subsidiary.')(url, init);
  };
  try {
    const r = await pollTenantMailboxes({
      fetchFn: fresh, env: (k) => SECRET_ENV[k], inviteMailbox: 'supplier@quotesdone.com', listedMailboxes: undefined, inboundToken: TOKEN, signingSecret: SIGNING,
      inboundUrl: 'http://inbound.invalid/functions/v1/resend_inbound', onFile: () => Promise.resolve(new Set<string>()),
      strangersFrom: undefined, financialDomains: undefined, sender: () => Promise.resolve('known'), record: () => Promise.resolve(null),
    });
    assertEquals(r.handed, 1, JSON.stringify(r));
    assertEquals(marks, []);
    assertEquals(rows.length, 1);
    assertEquals(rows[0].to_email, 'management@quotesdone.com');
    assertEquals(rows[0].lead_id, 19398);
    const raw = rows[0].raw as Record<string, unknown>;
    assertEquals(raw.in_reply_to, '<qd-notif-117599.1700000000000@quotesdone.com>');
    assertEquals(raw.message_id, '<zz-demo-reply@example.invalid>', 'fn_inbox_send threads the answer on this');
    assertEquals(rows[0].needs_review, true, 'email_triage selects needs_review');
    assertEquals(rows[0].owner_role, undefined, 'email_triage selects owner_role null');
  } finally { globalThis.fetch = real; }
});

Deno.test('an invoice from a stranger to management@: never the expense path, recorded once, never handed twice', async () => {
  const rows: Array<Record<string, unknown>> = []; const touched: string[] = [];
  const real = globalThis.fetch;
  globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
    const req = new Request(input, init); const u = new URL(req.url);
    if (req.method !== 'GET') touched.push(u.pathname);
    if (u.pathname === '/rest/v1/inbound_messages' && req.method === 'POST') { rows.push(...[JSON.parse(await req.clone().text())].flat()); return json([{ id: 2 }], 201); }
    if (u.pathname === '/rest/v1/leads' && req.method === 'GET') return (req.headers.get('Accept') || '').includes('vnd.pgrst.object') ? json({ message: 'none' }, 406) : json([]);
    return await real(input, init);
  }) as typeof fetch;
  const bill = { id: 'AAMkINVOICE', internetMessageId: '<inv@x.invalid>', subject: 'Invoice 12 AED 500', receivedDateTime: new Date().toISOString(), hasAttachments: true, from: { emailAddress: { address: 'someone@zz-vendor.example.invalid' } } };
  const fetchFn = (url: string, init?: RequestInit): Promise<Response> => {
    if (url.startsWith('https://login.')) return Promise.resolve(json({ access_token: 'g' }));
    if (url.includes('/users?')) return Promise.resolve(json({ value: [{ mail: 'management@quotesdone.com' }] }));
    if (url.includes('/mailFolders?') || url.includes('/mailFolders/junkemail/')) return Promise.resolve(json({ value: [] }));
    if (url.includes('/mailFolders/inbox/')) return Promise.resolve(json({ value: [bill] }));
    if (url.includes('/attachments')) return Promise.resolve(json({ value: [] }));
    if (url.startsWith('http://inbound.invalid/')) return handler(new Request(url, init));
    return Promise.resolve(json({ ...bill, body: { contentType: 'text', content: 'Please pay AED 500.' }, internetMessageHeaders: [] }));
  };
  const once = () => pollTenantMailboxes({
    fetchFn, env: (k) => SECRET_ENV[k], inviteMailbox: 'supplier@quotesdone.com', listedMailboxes: undefined, inboundToken: TOKEN, signingSecret: SIGNING,
    inboundUrl: 'http://inbound.invalid/functions/v1/resend_inbound', strangersFrom: '2026-01-01T00:00:00Z', financialDomains: undefined,
    onFile: (ids) => Promise.resolve(new Set(ids.filter((i) => rows.some((r) => r.provider_email_id === i)))),
    sender: () => Promise.resolve(null), record: () => Promise.resolve(null),
  });
  try {
    assertEquals((await once()).handed, 1);
    assertEquals(rows.length, 1); assertEquals(rows[0].provider_email_id, 'm365:AAMkINVOICE');
    for (const bad of ['fn_receipt_hand_to_bookkeeper', 'expense_entries', 'expenses']) assert(!touched.some((p) => p.endsWith(bad)), bad + ' was touched');
    assertEquals((await once()).handed, 0, 'handed a second time');
    assertEquals(rows.length, 1);
  } finally { globalThis.fetch = real; }
});

Deno.test('fails closed: no EOP pass, an SES-shaped header, never invited, or not a stop: nothing is suppressed', async () => {
  const cases: Array<[string, number, string]> = [
    ['spf=fail smtp.mailfrom=zz-demo-tiling.example;dmarc=fail action=quarantine header.from=zz-demo-tiling.example', 1, 'stop'],
    ['amazonses.com; dmarc=pass header.from=zz-demo-tiling.example', 1, 'stop'],
    [EOP, 0, 'stop'],
    [EOP, 1, 'We cover tiling. Please stop by our showroom.'],
  ];
  for (const [ar, invited, text] of cases) {
    suppressions.length = 0; STATE.ar = ar; STATE.invited = invited;
    const r = await tick(text);
    assert(r.handed === 1, JSON.stringify(r));
    assertEquals(suppressions.length, 0, `suppressed with ar=${ar} invited=${invited} text=${text}`);
  }
  STATE.ar = EOP; STATE.invited = 1;
});
