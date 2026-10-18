// deno test supabase/functions/_shared/m365_reply_inbox.test.ts
// The Microsoft 365 reply reader (m365_reply_inbox.ts), every branch offline: no address / no secrets / no inbound
// credentials hold without a call; a refused token is an error with the secret scrubbed; 401/403 on the listing files
// ONE finding naming Mail.ReadWrite and admin consent and withdraws the proof; a new reply is handed to resend_inbound
// with a Svix signature resend_inbound's own check accepts, its threading headers intact, then marked read; a message
// already on file is never handed twice; a failed hand-off is an error and the message is left for the next tick;
// a failed mark is counted, not fatal; attachments travel inline; paging stops at a page with nothing new.
import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { M365_INBOUND_PREFIX, M365_INBOX_UNREADABLE, MAX_HAND, PROOF_LABEL, headersOf, inboundPayload, pollReplyInbox, svixHeaders, type GraphMessage, type InboxDeps } from './m365_reply_inbox.ts';
import { M365_INBOX_AGENT } from '../send_outbox/m365_lane.ts';

const SECRET = 'zz-demo-client-secret-value-1234567890';
const ENV: Record<string, string> = { MS_TENANT_ID: 't', MS_CLIENT_ID: 'zz-demo-client', MS_CLIENT_SECRET: SECRET };
const SIGNING = 'whsec_' + btoa('zz-demo-signing-key-0123456789abcdef');
const INBOUND = 'https://zz-demo.example.invalid/functions/v1/resend_inbound';

type Call = { url: string; init?: RequestInit };
type Route = (c: Call) => { status: number; body?: unknown } | Error;
function harness(route: Route, o: { onFile?: string[]; env?: Record<string, string>; mailbox?: string; token?: string } = {}) {
  const calls: Call[] = [], findings: Record<string, unknown>[] = [], runs: Array<{ status: string; counts: Record<string, unknown>; note: string }> = [];
  const deps: InboxDeps = {
    fetchFn: (url, init) => {
      const c = { url, init }; calls.push(c); const a = route(c);
      if (a instanceof Error) return Promise.reject(a);
      return Promise.resolve(new Response(a.body === undefined ? null : JSON.stringify(a.body), { status: a.status }));
    },
    env: (k) => (o.env ?? ENV)[k], mailbox: o.mailbox ?? 'supplier@quotesdone.com',
    inboundToken: o.token ?? 'zz-demo-inbound-token', signingSecret: SIGNING, inboundUrl: INBOUND,
    onFile: (ids) => Promise.resolve(new Set(ids.filter((i) => (o.onFile || []).includes(i)))),
    fileFinding: (a) => { findings.push(a); return Promise.resolve(); },
    record: (status, counts, note) => { runs.push({ status, counts, note }); return Promise.resolve(); },
  };
  return { deps, calls, findings, runs };
}
const msg = (id: string, extra: Partial<GraphMessage> = {}): GraphMessage => ({
  id, internetMessageId: `<${id}@supplier.example.invalid>`, subject: 'Re: Your company page', receivedDateTime: '2026-10-06T10:00:00Z',
  from: { emailAddress: { address: 'zz-demo-supplier@example.invalid' } }, body: { contentType: 'text', content: 'We cover MEP and fit-out. Regards' },
  internetMessageHeaders: [{ name: 'Message-ID', value: `<${id}@supplier.example.invalid>` }, { name: 'In-Reply-To', value: '<qd-notif-42.1759740000000@quotesdone.com>' },
    { name: 'References', value: '<qd-notif-42.1759740000000@quotesdone.com>' }, { name: 'Authentication-Results', value: 'spf=pass; dkim=pass; dmarc=pass' },
    { name: 'Authentication-Results', value: 'second copy, ignored' }], ...extra,
});
const TOKEN_OK = { status: 200, body: { access_token: 'graph-token' } };
const isToken = (c: Call) => c.url.startsWith('https://login.microsoftonline.com/');
const isList = (c: Call) => c.url.includes('/mailFolders/inbox/messages');
const isHand = (c: Call) => c.url.startsWith(INBOUND);
const isPatch = (c: Call) => c.init?.method === 'PATCH';

// resend_inbound's verifySvix, restated: base64 HMAC-SHA256(secret, "<id>.<ts>.<body>") in a "v1,<sig>" list.
async function svixValid(secret: string, body: string, h: Record<string, string>): Promise<boolean> {
  const key = await crypto.subtle.importKey('raw', Uint8Array.from(atob(secret.slice(6)), (c) => c.charCodeAt(0)), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(h['svix-id'] + '.' + h['svix-timestamp'] + '.' + body)));
  return h['svix-signature'].split(' ').some((p) => p.split(',')[1] === btoa(String.fromCharCode(...mac)));
}

Deno.test('the proof label is the one send_outbox reads', () => assertEquals(PROOF_LABEL, M365_INBOX_AGENT));

Deno.test('no mailbox, no secrets or no inbound credentials: held/error without a single call, proof withdrawn', async () => {
  for (const [o, status] of [[{ mailbox: 'not an address' }, 'held'], [{ env: {} }, 'held'], [{ token: '' }, 'error']] as const) {
    const h = harness(() => new Error('no call expected'), o);
    const r = await pollReplyInbox(h.deps);
    assertEquals(h.calls.length, 0);
    assertEquals(h.runs.length, 1); assertEquals(h.runs[0].status, status); assertEquals(h.runs[0].counts.m365_inbox, 1);
    assertFalse(r.readable as boolean);
  }
});

Deno.test('a refused token is an error and never carries the secret', async () => {
  const h = harness((c) => isToken(c) ? { status: 401, body: { error: 'invalid_client', error_description: SECRET } } : new Error('x'));
  const r = await pollReplyInbox(h.deps);
  assertEquals(h.runs[0].status, 'error'); assertFalse(r.ok as boolean);
  assertFalse(JSON.stringify([r, h.runs]).includes(SECRET));
});

Deno.test('403 on the listing: ONE finding naming Mail.ReadWrite + admin consent, held (not a step error), proof withdrawn', async () => {
  for (const status of [401, 403]) {
    const h = harness((c) => isToken(c) ? TOKEN_OK : { status, body: { error: { code: 'ErrorAccessDenied', message: 'Access is denied.' } } });
    const r = await pollReplyInbox(h.deps);
    assertEquals(h.findings.length, 1);
    assertEquals(h.findings[0].p_issue_key, M365_INBOX_UNREADABLE);
    assertEquals(h.findings[0].p_raised_by, 'it_engineer');
    const ev = JSON.stringify(h.findings[0]);
    assert(ev.includes('Mail.ReadWrite') && ev.includes('Grant admin consent') && ev.includes('ApplicationAccessPolicy'));
    assertFalse(ev.includes(SECRET) || ev.includes('graph-token'));
    assertEquals(h.runs[0].status, 'held'); assertEquals(r.ok, true); assertEquals(r.readable, false);
    assertEquals(h.calls.filter(isHand).length, 0);
  }
});

Deno.test('a 5xx or no answer on the listing is an error; nothing handed', async () => {
  for (const a of [{ status: 503 }, new Error('timeout')] as const) {
    const h = harness((c) => isToken(c) ? TOKEN_OK : a);
    const r = await pollReplyInbox(h.deps);
    assertEquals(h.runs[0].status, 'error'); assertFalse(r.ok as boolean); assertEquals(h.findings.length, 0);
  }
});

Deno.test('an empty Inbox is read: status ok IS the proof', async () => {
  const h = harness((c) => isToken(c) ? TOKEN_OK : { status: 200, body: { value: [] } });
  const r = await pollReplyInbox(h.deps);
  assertEquals(h.runs[0].status, 'ok'); assertEquals(r.readable, true);
  const list = h.calls.find(isList)!;
  assert(list.url.startsWith('https://graph.microsoft.com/v1.0/users/supplier%40quotesdone.com/mailFolders/inbox/messages?'));
  assert(String(new URL(list.url).searchParams.get('$filter')).startsWith('receivedDateTime ge '));
  assert(String((list.init?.headers as Record<string, string>).Prefer).includes('IdType="ImmutableId"'));
});

Deno.test('a new reply is handed to resend_inbound signed, threaded and inline, then marked read', async () => {
  const h = harness((c) => isToken(c) ? TOKEN_OK : isList(c) ? { status: 200, body: { value: [msg('AAMkNEW1')] } }
    : isHand(c) ? { status: 200, body: { ok: true } } : isPatch(c) ? { status: 200, body: {} } : new Error('unexpected ' + c.url));
  const r = await pollReplyInbox(h.deps);
  assertEquals(r.handed, 1); assertEquals(h.runs[0].status, 'ok');
  const hand = h.calls.find(isHand)!;
  assertEquals(hand.url, INBOUND + '?s=zz-demo-inbound-token');
  const body = String(hand.init?.body);
  assert(await svixValid(SIGNING, body, hand.init?.headers as Record<string, string>), 'resend_inbound would reject the signature');
  const p = JSON.parse(body);
  assertEquals(p.type, 'email.received');
  assertEquals(p.data.email_id, M365_INBOUND_PREFIX + 'AAMkNEW1');
  assertEquals(p.data.from, 'zz-demo-supplier@example.invalid');
  assertEquals(p.data.to, 'supplier@quotesdone.com');
  assertEquals(p.data.text, 'We cover MEP and fit-out. Regards');
  assertEquals(p.data.message_id, '<AAMkNEW1@supplier.example.invalid>');
  assertEquals(p.data.headers['in-reply-to'], '<qd-notif-42.1759740000000@quotesdone.com>');
  assertEquals(p.data.headers.references, '<qd-notif-42.1759740000000@quotesdone.com>');
  assertEquals(p.data.headers['authentication-results'], 'spf=pass; dkim=pass; dmarc=pass', 'the first copy of a repeated header is kept');
  const patch = h.calls.find(isPatch)!;
  assert(patch.url.endsWith('/messages/AAMkNEW1')); assertEquals(JSON.parse(String(patch.init?.body)), { isRead: true });
});

Deno.test('IDEMPOTENT: a message already in inbound_messages is never handed again; paging stops at a page with nothing new', async () => {
  const h = harness((c) => isToken(c) ? TOKEN_OK : isList(c) ? { status: 200, body: { value: [msg('OLD1'), msg('OLD2')], '@odata.nextLink': 'https://graph.microsoft.com/v1.0/next' } } : new Error('no hand-off expected'),
    { onFile: ['m365:OLD1', 'm365:OLD2'] });
  const r = await pollReplyInbox(h.deps);
  assertEquals(r.handed, 0); assertEquals(r.new, 0); assertEquals(h.calls.filter(isList).length + h.calls.filter((c) => c.url.endsWith('/next')).length, 1);
  assertEquals(h.runs[0].status, 'ok');
});

Deno.test('resend_inbound answering duplicate counts as handled and is still marked read', async () => {
  const h = harness((c) => isToken(c) ? TOKEN_OK : isList(c) ? { status: 200, body: { value: [msg('RACE1')] } }
    : isHand(c) ? { status: 200, body: { ok: true, duplicate: true } } : { status: 200, body: {} });
  const r = await pollReplyInbox(h.deps);
  assertEquals(r.duplicate, 1); assertEquals(r.handed, 0); assertEquals(h.calls.filter(isPatch).length, 1);
});

Deno.test('a failed hand-off is an error, the message is NOT marked read, and the proof is withdrawn', async () => {
  for (const a of [{ status: 500, body: { error: 'x' } }, new Error('no answer')] as const) {
    const h = harness((c) => isToken(c) ? TOKEN_OK : isList(c) ? { status: 200, body: { value: [msg('FAIL1')] } } : isHand(c) ? a : new Error('no mark expected'));
    const r = await pollReplyInbox(h.deps);
    assertEquals(r.hand_failed, 1); assertEquals(h.calls.filter(isPatch).length, 0); assertEquals(h.runs[0].status, 'error');
  }
});

Deno.test('a mark that fails (Mail.Read only) is counted, not fatal', async () => {
  const h = harness((c) => isToken(c) ? TOKEN_OK : isList(c) ? { status: 200, body: { value: [msg('M1')] } } : isHand(c) ? { status: 200, body: { ok: true } } : { status: 403 });
  const r = await pollReplyInbox(h.deps);
  assertEquals(r.handed, 1); assertEquals(r.mark_failed, 1); assertEquals(h.runs[0].status, 'ok');
});

Deno.test('attachments travel inline (file attachments only, at most six); oldest handed first; MAX_HAND defers the rest', async () => {
  const files = Array.from({ length: 8 }, (_, i) => ({ '@odata.type': '#microsoft.graph.fileAttachment', name: `f${i}.pdf`, contentType: 'application/pdf', contentBytes: btoa('pdf' + i) }));
  files.push({ '@odata.type': '#microsoft.graph.itemAttachment', name: 'x', contentType: 'message/rfc822', contentBytes: 'eA==' });
  const many = Array.from({ length: MAX_HAND + 2 }, (_, i) => msg('N' + (MAX_HAND + 1 - i), { hasAttachments: i === MAX_HAND + 1 }));   // newest first
  const order: string[] = [];
  const h = harness((c) => {
    if (isToken(c)) return TOKEN_OK;
    if (isList(c)) return { status: 200, body: { value: many } };
    if (c.url.endsWith('/attachments')) return { status: 200, body: { value: files } };
    if (isHand(c)) { order.push(JSON.parse(String(c.init?.body)).data.email_id); return { status: 200, body: { ok: true } }; }
    return { status: 200, body: {} };
  });
  const r = await pollReplyInbox(h.deps);
  assertEquals(r.handed, MAX_HAND); assertEquals(r.deferred, 2);
  assertEquals(order[0], 'm365:N0', 'the oldest goes first');
  const first = JSON.parse(String(h.calls.find(isHand)!.init?.body));
  assertEquals(first.data.attachments.length, 6);
  assertEquals(first.data.attachments[0], { filename: 'f0.pdf', content_type: 'application/pdf', content: btoa('pdf0') });
});

Deno.test('headersOf / inboundPayload / svixHeaders shapes', async () => {
  assertEquals(headersOf(undefined), {});
  assertEquals(headersOf([{ name: 'X-A', value: '1' }, { name: 'x-a', value: '2' }]), { 'x-a': '1' });
  const html = inboundPayload(msg('H', { body: { contentType: 'html', content: '<p>hi</p>' } }), 'supplier@quotesdone.com', []);
  assertEquals((html.data as Record<string, unknown>).html, '<p>hi</p>');
  const h = await svixHeaders(SIGNING, '{}', 'msg_x', Date.UTC(2026, 9, 6));
  assertEquals(h['svix-timestamp'], String(Date.UTC(2026, 9, 6) / 1000));
  assert(await svixValid(SIGNING, '{}', h)); assertFalse(await svixValid(SIGNING, '{ }', h));
});
