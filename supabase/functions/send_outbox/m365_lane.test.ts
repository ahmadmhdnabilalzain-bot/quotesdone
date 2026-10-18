// deno test supabase/functions/send_outbox/m365_lane.test.ts
// The Microsoft 365 lane (m365_lane.ts), every branch offline: OFF makes no call; ON carries the three invitation
// types to a supplier and nothing else; missing secrets, a refused token or a refused send HOLD the row with one
// it_engineer finding that never carries a secret; the shared invite cap and the 150/day ceiling hold; the MIME
// carries List-Unsubscribe as a real header; the plain invitation passes every copy rule.
import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import {
  M365_HARD_CEILING, M365_ID_PREFIX, M365_OFF, M365_REFUSED_ISSUE, M365_SEED_KIND, graphSend, holdForM365, m365Body, m365Carries,
  m365CopyLint, m365InvitationText, m365Mime, m365Text, messageIdFor, resolveM365, scrub, switchOn, type Fetch, type M365,
  M365_INBOX_AGENT, M365_INBOX_PROOF_MAX_AGE_MS, m365ReplyTo,
} from './m365_lane.ts';
import { INVITE_LANE_TYPES } from './invite_lane.ts';

const SECRET = 'zz-demo-client-secret-value-1234567890';
const ENV: Record<string, string> = { MS_TENANT_ID: '00000000-0000-0000-0000-0000000000aa', MS_CLIENT_ID: 'zz-demo-client-id', MS_CLIENT_SECRET: SECRET };
const env = (e: Record<string, string>) => (k: string) => e[k];
const LINK = 'https://quotesdone.com/en/portal?t=00000000-0000-0000-0000-000000000000';
const ON: M365 = { active: true, refused: false, mailbox: 'supplier@quotesdone.com', token: 'tok', why: 'token issued' };

type Call = { url: string; init?: RequestInit };
function fake(...answers: Array<{ status: number; body?: unknown } | Error>) {
  const calls: Call[] = [];
  const fetchFn: Fetch = (url, init) => {
    calls.push({ url, init });
    const a = answers[Math.min(calls.length - 1, answers.length - 1)];
    if (a instanceof Error) return Promise.reject(a);
    return Promise.resolve(new Response(a.body === undefined ? null : JSON.stringify(a.body), { status: a.status }));
  };
  return { calls, fetchFn };
}
function findings() { const list: Record<string, unknown>[] = []; return { list, fileFinding: (a: Record<string, unknown>) => { list.push(a); return Promise.resolve(); } }; }

const NEVER = ['login_otp', 'otp', 'signup_code', 'customer_notice', 'quote_received', 'supplier_reveal', 'supplier_invite_reminder', 'supplier_invitex', '', null];

Deno.test('carries: OFF carries nothing but a marked seed; ON carries the three invitation types to a supplier only', () => {
  for (const type of [...INVITE_LANE_TYPES, ...NEVER]) for (const side of [true, false]) {
    assertFalse(m365Carries({ enabled: false, type, kind: null, supplierSide: side }), `carried with the switch off: ${type}`);
  }
  assert(m365Carries({ enabled: false, type: 'supplier_invite_seed', kind: M365_SEED_KIND, supplierSide: true }), 'a --lane=m365 seed is carried');
  assertFalse(m365Carries({ enabled: false, type: 'supplier_invite', kind: M365_SEED_KIND, supplierSide: true }), 'the seed kind does not move a real invitation');
  for (const type of INVITE_LANE_TYPES) assert(m365Carries({ enabled: true, type, kind: null, supplierSide: true }));
  for (const type of NEVER) for (const side of [true, false]) assertFalse(m365Carries({ enabled: true, type, kind: null, supplierSide: side }), `${type} took the lane`);
  for (const type of INVITE_LANE_TYPES) assertFalse(m365Carries({ enabled: true, type, kind: M365_SEED_KIND, supplierSide: false }), 'never to a customer');
  assert(switchOn(' TRUE ') && !switchOn('false') && !switchOn(undefined) && !switchOn('yes'));
});

Deno.test('not needed: no call, no finding', async () => {
  const f = fake({ status: 200, body: { access_token: 'x' } }); const g = findings();
  const m = await resolveM365({ needed: false, mailbox: 'supplier@quotesdone.com', env: env(ENV), fetchFn: f.fetchFn, fileFinding: g.fileFinding });
  assertEquals(m, M365_OFF); assertEquals(f.calls.length, 0); assertEquals(g.list.length, 0);
});

Deno.test('missing secrets: refused, no call, one finding naming the missing names and no value', async () => {
  for (const drop of ['MS_TENANT_ID', 'MS_CLIENT_ID', 'MS_CLIENT_SECRET']) {
    const e = { ...ENV }; delete e[drop];
    const f = fake({ status: 200, body: { access_token: 'x' } }); const g = findings();
    const m = await resolveM365({ needed: true, mailbox: 'supplier@quotesdone.com', env: env(e), fetchFn: f.fetchFn, fileFinding: g.fileFinding });
    assert(m.refused && !m.active); assertEquals(f.calls.length, 0); assertEquals(g.list.length, 1);
    assertEquals(g.list[0].p_issue_key, M365_REFUSED_ISSUE); assertEquals(g.list[0].p_raised_by, 'it_engineer');
    assert(m.why.includes(drop)); assertFalse(JSON.stringify(g.list).includes(SECRET));
  }
});

Deno.test('a mailbox that is not an address is refused before any call', async () => {
  const f = fake({ status: 200, body: { access_token: 'x' } }); const g = findings();
  const m = await resolveM365({ needed: true, mailbox: 'supplier', env: env(ENV), fetchFn: f.fetchFn, fileFinding: g.fileFinding });
  assert(m.refused); assertEquals(f.calls.length, 0); assertEquals(g.list.length, 1);
});

Deno.test('token issued: client-credentials POST to the tenant with the Graph default scope', async () => {
  const f = fake({ status: 200, body: { access_token: 'tok-1' } }); const g = findings();
  const m = await resolveM365({ needed: true, mailbox: 'Supplier@QuotesDone.com', env: env(ENV), fetchFn: f.fetchFn, fileFinding: g.fileFinding });
  assert(m.active && !m.refused); assertEquals(m.token, 'tok-1'); assertEquals(m.mailbox, 'supplier@quotesdone.com'); assertEquals(g.list.length, 0);
  assertEquals(f.calls[0].url, `https://login.microsoftonline.com/${ENV.MS_TENANT_ID}/oauth2/v2.0/token`);
  const form = new URLSearchParams(String(f.calls[0].init?.body));
  assertEquals(form.get('grant_type'), 'client_credentials'); assertEquals(form.get('scope'), 'https://graph.microsoft.com/.default');
  assertEquals(form.get('client_secret'), SECRET);
});

Deno.test('token refused / no answer / no token in a 200: refused with one finding, no secret anywhere', async () => {
  for (const ans of [{ status: 401, body: { error: 'invalid_client', error_description: 'bad secret ' + SECRET } }, new Error('timeout ' + SECRET), { status: 200, body: {} }]) {
    const f = fake(ans as never); const g = findings();
    const m = await resolveM365({ needed: true, mailbox: 'supplier@quotesdone.com', env: env(ENV), fetchFn: f.fetchFn, fileFinding: g.fileFinding });
    assert(m.refused && !m.active && !m.token); assertEquals(g.list.length, 1);
    assertFalse(m.why.includes(SECRET)); assertFalse(JSON.stringify(g.list).includes(SECRET));
  }
  assertEquals(scrub('x ' + SECRET + ' y', [SECRET]), 'x [redacted] y');
});

Deno.test('a finding that cannot be written does not stop the hold', async () => {
  const f = fake({ status: 500 });
  const m = await resolveM365({ needed: true, mailbox: 'supplier@quotesdone.com', env: env(ENV), fetchFn: f.fetchFn, fileFinding: () => Promise.reject(new Error('db down')) });
  assert(m.refused);
});

Deno.test('hold: refused -> unverified; shared invite cap and the 150 ceiling -> cap; seeds ignore the invite cap but not the ceiling', () => {
  const refused: M365 = { ...ON, active: false, refused: true };
  assertEquals(holdForM365({ m365: refused, type: 'supplier_invite', cappedSentToday: 0, inviteCap: 30, m365SentToday: 0 }), 'unverified');
  assertEquals(holdForM365({ m365: M365_OFF, type: 'supplier_invite_seed', cappedSentToday: 0, inviteCap: 30, m365SentToday: 0 }), 'unverified');
  assertEquals(holdForM365({ m365: ON, type: 'supplier_invite', cappedSentToday: 29, inviteCap: 30, m365SentToday: 29 }), null);
  assertEquals(holdForM365({ m365: ON, type: 'supplier_invite', cappedSentToday: 30, inviteCap: 30, m365SentToday: 0 }), 'cap');
  assertEquals(holdForM365({ m365: ON, type: 'supplier_invite_nudge', cappedSentToday: 30, inviteCap: 30, m365SentToday: 0 }), 'cap');
  assertEquals(holdForM365({ m365: ON, type: 'supplier_invite', cappedSentToday: 150, inviteCap: 500, m365SentToday: 0 }), 'cap', 'invite_daily_cap above 150 is clipped');
  assertEquals(holdForM365({ m365: ON, type: 'supplier_invite_seed', cappedSentToday: 999, inviteCap: 30, m365SentToday: 0 }), null);
  assertEquals(holdForM365({ m365: ON, type: 'supplier_invite_seed', cappedSentToday: 0, inviteCap: 30, m365SentToday: M365_HARD_CEILING }), 'cap');
});

Deno.test('the plain invitation: one link, English, no AI, ends with one question, 1,000 with no date, top 3 only as the report', () => {
  const body = m365InvitationText(LINK);
  const lint = m365CopyLint({ subject: 'Your company page on QuotesDone', body });
  for (const l of lint) assert(l.ok, `${l.rule}: ${l.detail}`);
  assert(body.includes('free permanently for the first 1,000 supplier registrations') && body.includes('Any number of suppliers') && body.includes('top three quotes'));
  assertEquals(m365Body('supplier_invite', 'Dear ZZ DEMO Supplier,\n\nRegister: ' + LINK + '\n\nThanks.'), body, 'an invitation with one portal link gets the plain variant');
  assert(m365Body('supplier_invite_nudge', 'Reminder ' + LINK).endsWith('?'), 'a nudge keeps its own body and gets the question');
});

Deno.test('copy rules bite: two links, HTML, a dated offer, a capped quote count, the word AI, Arabic', () => {
  const bad = (body: string, subject = 'x') => m365CopyLint({ subject, body }).filter((l) => !l.ok).map((l) => l.rule);
  assert(bad(m365InvitationText(LINK) + '\n\nhttps://quotesdone.com').length);
  assert(bad(m365InvitationText(LINK).replace('Hello,', '<b>Hello</b>,')).some((r) => r.includes('HTML')));
  assert(bad(m365InvitationText(LINK).replace('1,000 supplier registrations', '1,000 supplier registrations until December 2026')).some((r) => r.includes('date')));
  assert(bad(m365InvitationText(LINK).replace('Any number of suppliers', 'Up to ' + 'three suppliers')).some((r) => r.includes('any number may quote')));
  assert(bad(m365InvitationText(LINK).replace('marketplace', 'AI marketplace')).length);
  assert(bad(m365InvitationText(LINK).replace('Hello', 'مرحبا')).length);
});

const unb64 = (s: string) => new TextDecoder().decode(Uint8Array.from(atob(s), (c) => c.charCodeAt(0)));

Deno.test('MIME: List-Unsubscribe is a real header, plain text only, body carries the unsubscribe line', () => {
  const now = new Date(Date.UTC(2026, 9, 5, 8));
  const mid = messageIdFor(42, now);
  const unsub = 'https://quotesdone.com/u/unsubscribe?e=zz&t=1';
  const raw = unb64(m365Mime({ from: 'QuotesDone <supplier@quotesdone.com>', to: 'zz-demo@example.invalid', reply: 'suppliers@mail.quotesdone.com',
    subject: 'Your company page', text: m365Text(m365InvitationText(LINK), unsub), unsub, unsubMailto: 'unsubscribe@mail.quotesdone.com', messageId: mid, now }));
  const [head, bodyB64] = raw.split('\r\n\r\n');
  assert(head.includes(`List-Unsubscribe: <${unsub}>, <mailto:unsubscribe@mail.quotesdone.com?subject=unsubscribe>`));
  assert(head.includes('List-Unsubscribe-Post: List-Unsubscribe=One-Click'));
  assert(head.includes('Content-Type: text/plain; charset=utf-8') && !/text\/html/.test(raw));
  assert(head.includes('Message-ID: <qd-notif-42.') && head.includes('Reply-To: suppliers@mail.quotesdone.com'));
  const text = unb64(bodyB64.replace(/\r\n/g, ''));
  assert(text.includes(LINK) && text.includes('Unsubscribe: ' + unsub));
  // a header injection through the subject is flattened
  const inj = unb64(m365Mime({ from: 'a@b.co', to: 'c@d.co', reply: 'e@f.co', subject: 'x\r\nBcc: evil@x.co', text: 't', unsub: '', unsubMailto: '', messageId: mid, now }));
  assertFalse(/\r\nBcc:/.test(inj));
});

Deno.test('graphSend: 202 records m365:<Message-ID>; a refusal is returned, not thrown; no answer throws', async () => {
  const ok = fake({ status: 202 });
  const r = await graphSend(ok.fetchFn, ON, 'TUlNRQ==', '<id@quotesdone.com>');
  assertEquals(r, { ok: true, providerId: M365_ID_PREFIX + '<id@quotesdone.com>' });
  assertEquals(ok.calls[0].url, 'https://graph.microsoft.com/v1.0/users/supplier%40quotesdone.com/sendMail');
  assertEquals((ok.calls[0].init?.headers as Record<string, string>)['Content-Type'], 'text/plain');
  const no = fake({ status: 403, body: { error: { code: 'ErrorAccessDenied', message: 'Access is denied.' } } });
  const r2 = await graphSend(no.fetchFn, ON, 'x', '<id@q>');
  assert(!r2.ok && r2.refused && r2.status.includes('403') && r2.status.includes('ErrorAccessDenied'));
  let threw = false; try { await graphSend(fake(new Error('timeout')).fetchFn, ON, 'x', '<id@q>'); } catch { threw = true; }
  assert(threw);
});

// 5 Oct 2026: m365Body rebuilt the seed text from the link alone and dropped GlockApps' inbox-test ID; 0 of 80 matched.
Deno.test('a placement seed keeps its trailing inbox-test ID; a real invitation never carries one', () => {
  const ID = 'id:2026-10-05-18:36:55:550t';
  const row = 'Dear ZZ DEMO Supplier,\n\nRegister: ' + LINK + '\n\nThanks.\n\n' + ID;
  const seed = m365Body('supplier_invite_seed', row, M365_SEED_KIND);
  assert(seed.endsWith('\n\n' + ID), 'the seed ends with its ID line');
  assertEquals(seed, m365InvitationText(LINK) + '\n\n' + ID);
  for (const l of m365CopyLint({ subject: 'Your company page on QuotesDone', body: seed, seed: true })) assert(l.ok, `${l.rule}: ${l.detail}`);
  // the same body is NOT exempt when it is not linted as a seed: the year in the ID is a date
  assert(m365CopyLint({ subject: 'x', body: seed }).some((l) => !l.ok && l.rule.includes('date')));
  // a real invitation or nudge with an id: line never carries it
  assertFalse(m365Body('supplier_invite', row).includes(ID), 'a real invite drops it');
  assertFalse(m365Body('supplier_invite', row, 'supplier_invite').includes(ID));
  assert(m365Body('supplier_invite_nudge', 'Reminder ' + LINK + '\n\n' + ID, 'supplier_invite_nudge').endsWith('?'), 'a nudge is not given the marker');
  // the marker is the only exemption: a date elsewhere in a seed still fails, and so do the content rules
  const dated = seed.replace('1,000 supplier registrations', '1,000 supplier registrations until December 2026');
  assert(m365CopyLint({ subject: 'x', body: dated, seed: true }).some((l) => !l.ok && l.rule.includes('date')));
  assert(m365CopyLint({ subject: 'x', body: seed.replace('marketplace', 'AI marketplace'), seed: true }).some((l) => !l.ok));
  // a line that is not exactly the marker shape is not carried
  assertFalse(m365Body('supplier_invite_seed', row.replace(ID, 'id: 2026 bad'), M365_SEED_KIND).includes('id:'));
});

Deno.test('Reply-To (6 Oct 2026): dropped only while the reply reader is proven within two hours; the MIME then carries none', () => {
  const now = new Date('2026-10-06T12:00:00Z');
  const fb = 'suppliers@mail.quotesdone.com';
  assertEquals(m365ReplyTo({ proofAt: null, now, fallback: fb }), fb, 'never proven: the old Reply-To stays');
  assertEquals(m365ReplyTo({ proofAt: 'not a date', now, fallback: fb }), fb);
  assertEquals(m365ReplyTo({ proofAt: '2026-10-06T11:50:00Z', now, fallback: fb }), '', 'proven 10 minutes ago: no Reply-To');
  assertEquals(m365ReplyTo({ proofAt: new Date(now.getTime() - M365_INBOX_PROOF_MAX_AGE_MS - 1).toISOString(), now, fallback: fb }), fb, 'a stale proof is no proof');
  assertEquals(m365ReplyTo({ proofAt: '2026-10-07T12:00:00Z', now, fallback: fb }), fb, 'a proof from the future is no proof');
  const mime = (reply: string) => unb64(m365Mime({ from: 'QuotesDone <supplier@quotesdone.com>', to: 'zz-demo@example.invalid', reply, subject: 's', text: 't', unsub: '', unsubMailto: '', messageId: '<m@q>', now })).split('\r\n\r\n')[0];
  assertFalse(/Reply-To:/i.test(mime('')), 'an empty reply writes no Reply-To header');
  assert(mime(fb).includes('Reply-To: ' + fb));
  assertEquals(M365_INBOX_AGENT, 'resend_inbound');
});

Deno.test('wiring: send_outbox passes the lane Reply-To through m365ReplyTo, reading the proof under the reader\'s label', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assert(/m365Mime\(\{[^}]*reply: m365ReplyTo\(\{ proofAt: m365ProofAt, now, fallback: reply \}\)/.test(src), 'the lane MIME no longer asks m365ReplyTo');
  assert(src.includes(".eq('agent', M365_INBOX_AGENT).eq('counts->>m365_inbox', '1')"), 'the proof read no longer selects the reader rows');
});

Deno.test('the refusal finding closes on a 2xx sendMail, never on a token alone (review of #1473)', async () => {
  const closed: [string, string][] = []; const closeFinding = async (k: string, n: string) => { closed.push([k, n]); };
  const g = findings();
  // token succeeds, send refused: the finding stays open
  const tok = await resolveM365({ needed: true, mailbox: 'supplier@quotesdone.com', env: env(ENV), fetchFn: fake({ status: 200, body: { access_token: 't' } }).fetchFn, fileFinding: g.fileFinding });
  assert(tok.active); assertEquals(closed.length, 0, 'a token alone never closes it');
  const refused = await graphSend(fake({ status: 403, body: { error: { code: 'ErrorAccessDenied', message: 'no' } } }).fetchFn, tok, 'x', '<id@q>', closeFinding);
  assertFalse(refused.ok); assertEquals(closed.length, 0, 'a refused send leaves the finding open');
  // the first successful send closes it
  const sent = await graphSend(fake({ status: 202 }).fetchFn, tok, 'x', '<id@q>', closeFinding);
  assert(sent.ok); assertEquals(closed.length, 1); assertEquals(closed[0][0], M365_REFUSED_ISSUE);
  // a close that throws never turns a sent message into a failure
  const still = await graphSend(fake({ status: 202 }).fetchFn, tok, 'x', '<id@q>', async () => { throw new Error('rpc down'); });
  assert(still.ok);
});
