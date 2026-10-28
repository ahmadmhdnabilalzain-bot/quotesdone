// deno test supabase/functions/send_outbox/m365_lane.test.ts
// The Microsoft 365 lane (m365_lane.ts), every branch offline: OFF makes no call; ON carries the three invitation
// types to a supplier and nothing else; missing secrets, a refused token or a refused send HOLD the row with one
// it_engineer finding that never carries a secret; the shared invite cap and the 150/day ceiling hold; the MIME
// carries List-Unsubscribe as a real header; the plain invitation passes every copy rule.
import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import {
  M365_HARD_CEILING, M365_ID_PREFIX, M365_OFF, M365_REFUSED_ISSUE, M365_SEED_KIND, graphSend, holdForM365, m365Body, m365Carries,
  companyName, m365CopyLint, m365InvitationText, m365Mime, m365Subject, messageIdFor, resolveM365, scrub, switchOn, type Fetch, type M365, STOP_LINE,
  M365_INBOX_AGENT, M365_INBOX_PROOF_MAX_AGE_MS, m365ReplyTo, withPlacementRef, campaignMail,
  M365_PACE_MS, M365_PER_RUN, paceM365, qpEncode,
} from './m365_lane.ts';
import { resendPayload } from './payload.ts';
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

// VARIANT A, 27 Oct 2026 (it_engineer; the founder delegated the choice: "approved. dont ask me"), word for word.
const APPROVED = `Hi Sigma Ceramics team,

I'm Ahmad, founder of QuotesDone in Dubai. QuotesDone is a platform where companies in the UAE post requests for quotation, and each request goes only to suppliers who work in that exact trade.

We are putting together our list of tiling suppliers now, before buyers start sending requests. Would your company like to receive tiling requests when they come in?

Best regards,
Ahmad Alzain
Founder, QuotesDone
QuotesDone Technologies · Dubai, UAE

If this isn't relevant, reply "stop" and we won't contact you again.`;

/** RFC 2045 quoted-printable decode of a MIME text part, for the assertions below. */
function qpDecode(s: string): string {
  const joined = s.replace(/=\r\n/g, '');
  const bytes: number[] = [];
  for (let i = 0; i < joined.length; i++) {
    if (joined[i] === '=' && /^[0-9A-F]{2}$/.test(joined.slice(i + 1, i + 3))) { bytes.push(parseInt(joined.slice(i + 1, i + 3), 16)); i += 2; }
    else bytes.push(joined.charCodeAt(i));
  }
  return new TextDecoder().decode(Uint8Array.from(bytes));
}

Deno.test('the invitation is variant A, word for word, and passes every rule', () => {
  const who = { company: 'Sigma Ceramics', trade: 'tiling' };
  assertEquals(m365InvitationText(who), APPROVED);
  assertEquals(m365Subject(who), 'A question about your tiling work');
  assertEquals(m365Subject({ company: 'Sigma Ceramics' }), 'A question for Sigma Ceramics');
  for (const l of m365CopyLint({ subject: m365Subject(who), body: APPROVED })) assert(l.ok, `${l.rule}: ${l.detail}`);
  // neutral variant: no company, no trade
  const neutral = m365InvitationText();
  assert(neutral.startsWith('Hello,\n\n') && neutral.includes('We are putting together our list of suppliers now, before buyers start sending requests.'));
  assert(neutral.includes('Would your company like to receive the requests that match your trade when they come in?'));
  for (const l of m365CopyLint({ subject: m365Subject({}), body: neutral })) assert(l.ok, `${l.rule}: ${l.detail}`);
});

// GlockApps 2026-10-27-09:33:53:634t: the offer-list text went to Junk at 18 of 18 Microsoft seeds. Variant A carries
// none of its offer phrases, is short, and its last paragraph before the signature is one question to answer by reply.
Deno.test('variant A: no offer phrase, no domain written out, short, and the message asks one question before the signature', () => {
  for (const who of [{ company: 'Sigma Ceramics', trade: 'tiling' }, {}, { company: 'Sigma Ceramics' }]) {
    const t = m365InvitationText(who); const s = m365Subject(who);
    assertFalse(/\b(free|join|register|registration|commission|opportunity|offer|exclusive|invitation|onboarding|1,000)\b|what you get|quotesdone\.com/i.test(t + ' ' + s), t);
    assertFalse(/^\s*[–•*-]\s/m.test(t), 'a bullet list came back');
    const words = t.split(/\s+/).filter(Boolean).length;
    assert(words <= 110, `variant A grew to ${words} words`);
    const paras = t.split('\n\n');
    const ask = paras[paras.indexOf(paras.find((p) => p.startsWith('Best regards'))!) - 1];
    assert(ask.trimEnd().endsWith('?') && (ask.match(/\?/g) || []).length === 1, 'the paragraph before the signature is no longer one question');
  }
});

Deno.test('the invitation, its nudge and a stored body that still carries a link all send the same no-link text', () => {
  const who = { company: 'Sigma Ceramics', trade: 'tiling' };
  for (const type of ['supplier_invite', 'supplier_invite_nudge', 'supplier_invite_seed']) {
    for (const stored of ['Dear X,\n\nRegister: ' + LINK + '\n\nThanks.', 'Reminder ' + LINK, 'Hi {{company}} team,\n\nno link here']) {
      const body = m365Body(type, stored, null, who);
      assertEquals(body, APPROVED, `${type} did not send the approved text`);
      assertFalse(/https?:\/\/|www\./.test(body), 'a link reached the body');
    }
  }
});

Deno.test('copy rules bite: any link, HTML, a dated offer, a capped quote count, the word AI, Arabic, Al Furjan or a permit, a missing stop line', () => {
  const bad = (body: string, subject = 'x') => m365CopyLint({ subject, body }).filter((l) => !l.ok).map((l) => l.rule);
  const t = m365InvitationText({ company: 'Sigma Ceramics', trade: 'tiling' });
  for (const link of ['https://quotesdone.com', 'http://x.co', 'www.quotesdone.com', 'quotesdone.com/en/portal', LINK]) {
    assert(bad(t.replace('founder of QuotesDone in Dubai', 'founder of QuotesDone in Dubai, see ' + link)).some((r) => r.includes('no link')), link);
  }
  assert(bad(t, 'see https://quotesdone.com').some((r) => r.includes('no link')), 'a link in the subject');
  assert(bad(t.replace('Hi Sigma', '<b>Hi</b> Sigma')).some((r) => r.includes('HTML')));
  assert(bad(t.replace('when they come in?', 'when they come in, from December 2026?')).some((r) => r.includes('date')));
  assert(bad(t.replace('each request goes only to suppliers', 'each request goes to up to ' + 'three suppliers')).some((r) => r.includes('any number may quote')));
  assert(bad(t.replace('founder of QuotesDone', 'founder of QuotesDone AI')).length);
  assert(bad(t.replace('Hi Sigma', 'مرحبا Sigma')).length);
  assert(bad(t.replace('Technologies · Dubai', 'Technologies · Al Furjan, Dubai')).some((r) => r.includes('street address')));
  assert(bad(t.replace('Dubai, UAE', 'Dubai, UAE · TDRA NOL-26-100000665')).some((r) => r.includes('permit')));
  assert(bad(t.replace(STOP_LINE, 'Thanks.')).some((r) => r.includes('stop')));
});

const unb64 = (s: string) => new TextDecoder().decode(Uint8Array.from(atob(s), (c) => c.charCodeAt(0)));
/** Header and body of a MIME message: split at the FIRST blank line (a quoted-printable body has blank lines of its own). */
const splitMime = (raw: string): [string, string] => { const i = raw.indexOf('\r\n\r\n'); return [raw.slice(0, i), raw.slice(i + 4)]; };

Deno.test('MIME: List-Unsubscribe is a real header, plain text only, body carries the unsubscribe line', () => {
  const now = new Date(Date.UTC(2026, 9, 5, 8));
  const mid = messageIdFor(42, now);
  const unsub = 'https://quotesdone.com/u/unsubscribe?e=zz&t=1';
  const raw = unb64(m365Mime({ from: 'QuotesDone <supplier@quotesdone.com>', to: 'zz-demo@example.invalid', reply: 'suppliers@mail.quotesdone.com',
    subject: 'Your company page', text: m365InvitationText(), unsub, unsubMailto: 'unsubscribe@mail.quotesdone.com', messageId: mid, now }));
  const [head, bodyB64] = splitMime(raw);
  assert(head.includes(`List-Unsubscribe: <${unsub}>, <mailto:unsubscribe@mail.quotesdone.com?subject=unsubscribe>`));
  assert(head.includes('List-Unsubscribe-Post: List-Unsubscribe=One-Click'));
  assert(head.includes('Content-Type: text/plain; charset=utf-8') && !/text\/html/.test(raw));
  assert(head.includes('Content-Transfer-Encoding: quoted-printable') && !head.includes('Content-Transfer-Encoding: base64'), 'the text part is base64 again');
  assert(head.includes('Message-ID: <qd-notif-42.') && head.includes('Reply-To: suppliers@mail.quotesdone.com'));
  // quoted-printable: the English words are readable on the wire, every line is at most 76 characters
  assert(bodyB64.includes('I\'m Ahmad, founder of QuotesDone in Dubai.'), 'the text part is not readable quoted-printable');
  for (const l of bodyB64.split('\r\n')) assert(l.length <= 76, `a ${l.length}-character line`);
  const text = qpDecode(bodyB64).replace(/\r\n/g, '\n');
  assertEquals(text, m365InvitationText(), 'quoted-printable did not round-trip the text');
  assert(text.trimEnd().endsWith(STOP_LINE) && text.includes('Would your company like'));
  assertEquals((text.match(/https?:\/\/|www\./g) || []).length, 0, '27 Oct 2026: no URL in the body; unsubscribe is in the header');
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
  const row = 'Hi ZZ DEMO Supplier team,\n\nRegister.\n\nThanks.\n\n' + ID;
  const seed = m365Body('supplier_invite_seed', row, M365_SEED_KIND);
  assert(seed.endsWith('\n\n' + ID), 'the seed ends with its ID line');
  assertEquals(seed, m365InvitationText() + '\n\n' + ID);
  for (const l of m365CopyLint({ subject: 'A question about your work in the UAE', body: seed, seed: true })) assert(l.ok, `${l.rule}: ${l.detail}`);
  // the same body is NOT exempt when it is not linted as a seed: the year in the ID is a date
  assert(m365CopyLint({ subject: 'x', body: seed }).some((l) => !l.ok && l.rule.includes('date')));
  // a real invitation or nudge with an id: line never carries it
  assertFalse(m365Body('supplier_invite', row).includes(ID), 'a real invite drops it');
  assertFalse(m365Body('supplier_invite', row, 'supplier_invite').includes(ID));
  assertFalse(m365Body('supplier_invite_nudge', 'Reminder\n\n' + ID, 'supplier_invite_nudge').includes(ID), 'a nudge is not given the marker');
  // the marker is the only exemption: a date elsewhere in a seed still fails, and so do the content rules
  const dated = seed.replace('when they come in?', 'when they come in, from December 2026?');
  assert(m365CopyLint({ subject: 'x', body: dated, seed: true }).some((l) => !l.ok && l.rule.includes('date')));
  assert(m365CopyLint({ subject: 'x', body: seed.replace('founder of QuotesDone', 'founder of QuotesDone AI'), seed: true }).some((l) => !l.ok));
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
  // 27 Oct 2026: the MIME text is the built body itself (no second signature or opt-out appended), and every lane row,
  // the nudge included, takes the one subject function; only withPlacementRef can add a token, and only to a seed.
  assert(/subject: mSubject, text: mBody, unsub/.test(src), 'the lane MIME no longer sends the built body as is');
  const lane = Deno.readTextFileSync(new URL('./m365_lane.ts', import.meta.url));
  assert(/const subject = withPlacementRef\(m365Subject\(/.test(lane), 'the campaign subject is no longer m365Subject + withPlacementRef for every row');
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

// ledger 1113 (19 Oct 2026): a personal note to the company and its trade; no promotional word in the subject or opening.
Deno.test('the invitation names the company and its trade, and the subject carries no promotional word', () => {
  assertEquals(companyName('TAAZ BUILDING EQUIPMENTS TRADING &#038; RENTAL LLC'), 'Taaz Building Equipments Trading & Rental LLC');
  assertEquals(companyName('Trident Fire | Trident Guard Fire Fighting LLC'), 'Trident Fire');
  assertEquals(companyName('ZZ DEMO Supplier'), '');
  const who = { company: 'Sigma Ceramics Building Materials Trading LLC', trade: 'building_materials' };
  const subject = m365Subject(who);
  assertEquals(subject, 'A question about your building materials work');
  assertEquals(m365Subject({}), 'A question about your work in the UAE');
  const body = m365InvitationText(who);
  assert(body.startsWith('Hi Sigma Ceramics Building Materials Trading LLC team,') && body.includes('We are putting together our list of building materials suppliers now'));
  const opening = subject + ' ' + body.split('\n\n').slice(0, 2).join(' ');
  assertFalse(/\b(free|commission|invitation|invite|exclusive|AI)\b/i.test(opening), opening);
  for (const l of m365CopyLint({ subject, body })) assert(l.ok, `${l.rule}: ${l.detail}`);
  assertEquals(m365Body('supplier_invite', 'Dear X,\n\n' + LINK, undefined, who), body);
});

// Release review of #1524: the body lost its unsubscribe URL, so prove the two opt-outs that remain.
Deno.test('opt-out: one-click List-Unsubscribe with -Post in the MIME, and a "stop" reply is an unsubscribe request', async () => {
  const { isUnsubscribeRequest } = await import('../_shared/unsubscribe_mailbox.ts');
  const unsub = 'https://quotesdone.com/u/unsubscribe?e=zz&t=1';
  const head = unb64(m365Mime({ from: 'Ahmad Alzain at QuotesDone <supplier@quotesdone.com>', to: 'zz-demo@example.invalid', reply: '',
    subject: 's', text: m365InvitationText(), unsub, unsubMailto: 'unsubscribe@mail.quotesdone.com', messageId: '<m@q>', now: new Date() })).split('\r\n\r\n')[0];
  assert(head.includes(`List-Unsubscribe: <${unsub}>, <mailto:unsubscribe@mail.quotesdone.com?subject=unsubscribe>`));
  assert(head.includes('List-Unsubscribe-Post: List-Unsubscribe=One-Click'));
  // a reply to the M365 mailbox reaches resend_inbound through _shared/m365_reply_inbox.ts; its first line decides
  for (const text of ['stop', 'Stop.', 'STOP\n\nOn Mon, Ahmad wrote:\n> Hi team']) {
    assert(isUnsubscribeRequest({ to: 'supplier@quotesdone.com', subject: 'Re: Quote requests for X', text }), text);
  }
  assertFalse(isUnsubscribeRequest({ to: 'supplier@quotesdone.com', subject: 'Re: x', text: 'We cover tiling. Please stop by.' }));
  const sent = m365InvitationText();
  assert(sent.trimEnd().endsWith(STOP_LINE) && sent.includes('QuotesDone Technologies · Dubai, UAE'), 'the legal identity line is in the signature');
  assert(isUnsubscribeRequest({ to: 'supplier@quotesdone.com', subject: 'Re: Quote requests for X', text: 'stop\n\n> ' + sent.split('\n').join('\n> ') }),
    'a "stop" reply quoting the new email is still an unsubscribe');
});

Deno.test('the morning placement seed keeps its (ref QD…) token on the rebuilt subject; nothing else gains one', () => {
  const row = { type: 'supplier_invite_seed', subject: 'Invitation: become a founding supplier on QuotesDone (free, no commission) (ref QD8F6C46AE93)' };
  const subject = withPlacementRef(m365Subject({}), row);
  assertEquals(subject, 'A question about your work in the UAE (ref QD8F6C46AE93)');
  // the reader (_shared/inbox_placement.ts) matches the token in the subject that actually leaves, i.e. the MIME's
  const now = new Date('2026-10-27T04:30:00Z');
  const mime = atob(m365Mime({ from: 'QuotesDone <supplier@quotesdone.com>', to: 'management@quotesdone.com', reply: '', subject, text: 'x',
    unsub: '', unsubMailto: 'supplier@quotesdone.com', messageId: messageIdFor(1, now), now }));
  assert(mime.includes('Subject: A question about your work in the UAE (ref QD8F6C46AE93)'), 'the token is in the sent Subject header');
  // and the copy rules still pass, so the seed is not held for its token
  const body = m365Body('supplier_invite_seed', 'Hi ZZ DEMO Supplier team,\n\nI\'m Ahmad, founder of QuotesDone.', 'supplier_invite_seed');
  assertEquals(body, m365InvitationText(), 'the seed sends the same email a supplier gets (neutral variant for the ZZ DEMO name)');
  assertEquals(m365CopyLint({ subject, body }).filter((l) => !l.ok), []);
  assertEquals(withPlacementRef('X', { type: 'supplier_invite', subject: 'Y (ref QD8F6C46AE93)' }), 'X', 'a real invitation never carries a token');
  assertEquals(withPlacementRef('X', { type: 'supplier_invite_nudge', subject: 'Y (ref QD8F6C46AE93)' }), 'X', 'a nudge never carries a token');
  assertEquals(withPlacementRef('X', { type: 'supplier_invite_seed', subject: 'no token' }), 'X');
  assertEquals(withPlacementRef('X (ref QD8F6C46AE93)', row), 'X (ref QD8F6C46AE93)', 'never doubled');
});

// 27 Oct 2026 (coordinator, follow-up to #1614): a lane switch can never send the old email. Both routes build the
// supplier campaign email with campaignMail; the Resend fallback sends it as plain text with no HTML frame.
Deno.test('both routes send the identical approved body and subject: Microsoft 365 MIME and the Resend fallback payload', () => {
  const who = { company: 'Sigma Ceramics', trade: 'tiling' };
  const unsub = 'https://quotesdone.com/u/unsubscribe?e=zz&t=1';
  const OLD = 'Dear {{company}},\n\nRegister here: ' + LINK + '\n\nWe look forward to welcoming you.';
  const rows = [
    { type: 'supplier_invite', subject: 'Invitation: become a founding supplier', body: OLD, kind: null },
    { type: 'supplier_invite_nudge', subject: 'Reminder', body: 'Reminder ' + LINK, kind: null },
    { type: 'supplier_invite_seed', subject: 'Invitation (ref QD8F6C46AE93)', body: 'Hi ZZ DEMO Supplier team,\n\nx', kind: 'supplier_invite_seed' },
  ];
  for (const row of rows) {
    const c = campaignMail(row, row.type === 'supplier_invite_seed' ? {} : who);
    assertEquals(c.bad, [], `${row.type} fails a copy rule`);
    // route 1: the Microsoft 365 MIME, as index.ts builds it
    const raw = unb64(m365Mime({ from: 'Ahmad Alzain at QuotesDone <supplier@quotesdone.com>', to: 'zz-demo@example.invalid', reply: '', subject: c.subject,
      text: c.text, unsub, unsubMailto: 'unsubscribe@mail.quotesdone.com', messageId: '<m@q>', now: new Date('2026-10-27T04:30:00Z') }));
    const [head, qp] = splitMime(raw);
    const m365Text = qpDecode(qp).replace(/\r\n/g, '\n');
    // route 2: the Resend fallback payload, as index.ts builds it for a campaign row
    const mail = resendPayload({ from: 'QuotesDone <invite@hello.quotesdone.com>', to: 'zz-demo@example.invalid', reply: 'suppliers@mail.quotesdone.com',
      subject: c.subject, html: '', text: c.text, unsub, unsubMailto: 'unsubscribe@mail.quotesdone.com' });
    assertEquals(mail.text, m365Text, `${row.type}: the two routes send different bodies`);
    assert(head.includes('Subject: ' + c.subject) && mail.subject === c.subject, `${row.type}: the two routes send different subjects`);
    assertFalse('html' in mail, 'the fallback sends no HTML frame (no logo or unsubscribe link, no Al Furjan footer)');
    assertFalse(/https?:\/\/|www\.|al furjan|NOL-|which trades does your company cover/i.test(mail.text), 'an old-email trace reached the fallback');
    assert(mail.text.trimEnd().endsWith(STOP_LINE));
    assertEquals(mail.headers?.['List-Unsubscribe-Post'], 'List-Unsubscribe=One-Click');
  }
  assertEquals(campaignMail(rows[0], who).text, APPROVED, 'the invitation on either route is variant A word for word');
  assert(campaignMail(rows[2]).subject.endsWith('(ref QD8F6C46AE93)') && !campaignMail({ ...rows[0], subject: 'x (ref QD8F6C46AE93)' }, who).subject.includes('ref QD'));
});

Deno.test('wiring: index.ts builds the campaign email with campaignMail on BOTH routes, and the fallback sends it text-only', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assert(/const \{ subject: mSubject, text: mBody, bad \} = await campaignFor\(n\);/.test(src), 'the Microsoft 365 lane no longer uses campaignMail');
  assert(/const camp = supplierSide && isLaneType\(n\.type\) \? await campaignFor\(n\) : null;/.test(src), 'the Resend fallback no longer uses campaignMail');
  assert(/camp\s*\? resendPayload\(\{ from, to: n\.to_email, reply, subject: camp\.subject, html: '', text: camp\.text, unsub,/.test(src), 'the fallback no longer sends the campaign text without HTML');
  assert(/return campaignMail\(n, /.test(src));
});

// 27 Oct 2026 (review of #1614): the copy rules read OUR copy, not the supplier's registered name. Measured that day,
// 11 of 17,401 eligible leads were held for their own names; each is replayed here and must now pass and be sent.
Deno.test('a supplier\'s own name never holds its email: dates, month-like words and "AI" in a name pass; a web address in a name gives "Hello,"', () => {
  const HELD_27_OCT = [
    ['Eastlake Dec.Design & Fitout LLC', 'interior_fitout'], ['ROYAL TALENT INTERIOR DEC CO LLC', 'interior_fitout'],
    ['2003 ALUMINIUM WORKS & CARPENTRY LLC', 'aluminium'], ['WELCOME ARTS 2000', 'signage'], ['PETRO SEP MEMBRANE TECHNOLOGIES INC', 'chemicals'],
    ['QARYAT AL FAAN AL KASHMIRI NOV &#038; CARPETS', 'flooring'], ['CHINA 2008 BUILDING MATERIAL LLC', 'building_materials'],
    ['AI TRADING EST', 'steel'], ['AL FAYAD CARPETS &#038; NOV TRADING', 'flooring'], ['JAN DE NUL DREDGING LTD', undefined],
  ] as const;
  for (const [company, trade] of HELD_27_OCT) {
    const c = campaignMail({ type: 'supplier_invite', body: '' }, { company, trade });
    assertEquals(c.bad, [], `${company} is still held`);
    assert(c.text.startsWith(`Hi ${companyName(company)} team,`), `${company}: not greeted by name`);
  }
  const web = campaignMail({ type: 'supplier_invite', body: '' }, { company: 'www.khaazay.com online division of Al Twat Trading LLC', trade: 'building_materials' });
  assertEquals(web.bad, []); assert(web.text.startsWith('Hello,\n\n') && !/khaazay/.test(web.text + web.subject), 'a web address in a name reached the email');
  assertEquals(companyName('Acme.ae Trading'), '');
  // the masking is only of the name: our own copy is still held for the same faults
  const t = campaignMail({ type: 'supplier_invite', body: '' }, { company: 'AI TRADING EST', trade: 'steel' }).text;
  assert(m365CopyLint({ subject: 'x', body: t.replace('when they come in?', 'when they come in, from December 2026?') }).some((l) => !l.ok && l.rule.includes('date')));
});

// PACING (27 Oct 2026): the 27 Oct seeds left in bursts of 20 a run, about 4 s apart. The lane now stops at M365_PER_RUN.
Deno.test('pacing: at most M365_PER_RUN lane sends a run; the rest are re-queued for a later run, not dropped or diverted', () => {
  assertEquals(M365_PER_RUN, 5);
  for (let i = 0; i < M365_PER_RUN; i++) assertFalse(paceM365(i), `send ${i + 1} of the run was held`);
  assert(paceM365(M365_PER_RUN) && paceM365(M365_PER_RUN + 30));
  assert(M365_PACE_MS >= 5 * 60_000, 'a paced row would come back in the same burst');
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const pace = src.indexOf('if (paceM365(m365SentRun))'); const send = src.indexOf('await campaignFor(n);');
  assert(pace > 0 && pace < send, 'index.ts no longer checks pacing before building and sending the lane row');
  assert(/paceM365\(m365SentRun\)\) \{\s*await admin\.from\('notifications'\)\.update\(\{ status: 'queued', claimed_at: null, not_before: new Date\(Date\.now\(\) \+ M365_PACE_MS\)/.test(src),
    'a paced row is no longer put back in the queue with not_before');
  assert(/sent\+\+; m365SentToday\+\+; m365SentRun\+\+;/.test(src), 'a lane send no longer counts toward the run');
});

Deno.test('quoted-printable: "=", UTF-8, a trailing space and long lines are encoded per RFC 2045, and it round-trips', () => {
  const sample = 'a=b · c – d \nx\t\n' + 'y'.repeat(200) + '\n' + '–'.repeat(40);
  const qp = qpEncode(sample);
  for (const l of qp.split('\r\n')) assert(l.length <= 76, `a ${l.length}-character line`);
  assert(qp.startsWith('a=3Db =C2=B7 c =E2=80=93 d=20\r\n'), qp.slice(0, 40));
  assert(qp.includes('x=09\r\n'), 'a trailing tab is not encoded');
  assertFalse(/=[0-9A-F]?\r\n[0-9A-F]/.test(qp.replace(/=\r\n/g, '')), 'an =XX was split');
  assertEquals(qpDecode(qp), sample.replace(/\n/g, '\r\n'));
});

// sales_engineer, 28 Oct 2026: the greeting reads a company name, not a page title. Every leads.company_name behind
// notifications 116649-116668 (read-only join, 28 Oct 2026), with the greeting each must render. The first four were
// real rendered failures; the other sixteen already read well and must keep doing so.
Deno.test('the greeting reads a company name, not a scraped page title (notifications 116649-116668)', () => {
  const CASES: ReadonlyArray<readonly [string, string]> = [
    ['Speed Blast Trading L.L.C &#8211; Top notch Industrial Equipments Suppliers in Dubai, UAE', 'Speed Blast Trading L.L.C'],
    ['CERAMIC MEGA BUILDING MATERIALS TR LLC (Manufacturer and wholesaler of any kind of porcelain tile.)', 'Ceramic Mega Building Materials TR LLC'],
    ['NRA INTERNATIONAL', 'NRA International'],
    ['OFFSHORE MIDDLE EAST MARINE EQUIPMENT TRADING L L C', 'Offshore Middle East Marine Equipment Trading LLC'],
    ['Zoom Building Materials Trading | Construction Materials Supplier in Abu Dhabi, UAE', 'Zoom Building Materials Trading'],
    ['Mohd Al Qama - Authorized Dealer of RAK Ceramics', 'Mohd Al Qama'],
    ['Al Sarai Ceramic - KOHLER SHARJAH', 'Al Sarai Ceramic'],
    ['RAK TILE LLC - Interlocking Paver Blocks Manufacturer- Marble & Granites- Ras Al Khaimah- UAE', 'RAK Tile LLC'],
    ['BLUE PEARL MARINE SERVICES FZC', 'Blue Pearl Marine Services FZC'],
    ['SEASWIFT SUBSEA ENGINEERING LLC', 'Seaswift Subsea Engineering LLC'],
    ['TOTAL SOLUTIONS', 'Total Solutions'],
    ['ARABIAN AURORA DETERGENTS TRADING L.L.C', 'Arabian Aurora Detergents Trading L.L.C'],
    ['Infinite Global Fze', 'Infinite Global FZE'],
    ['Mohammed Zafar Steel Workshop LLC', 'Mohammed Zafar Steel Workshop LLC'],
    ['NEELKAMAL PLASTIC FACTORY', 'Neelkamal Plastic Factory'],
    ['Zainab Building Materials Company LLC', 'Zainab Building Materials Company LLC'],
    ['Buildline Building Materials Trading LLC', 'Buildline Building Materials Trading LLC'],
    ['Fujairah General Trading Enterprises', 'Fujairah General Trading Enterprises'],
    ['SENSI Trading LLC', 'SENSI Trading LLC'],
    ['Volark Tiles', 'Volark Tiles'],
  ];
  for (const [raw, want] of CASES) {
    assertEquals(companyName(raw), want, raw);
    assert(m365InvitationText({ company: raw }).startsWith(`Hi ${want} team,\n`), raw);
  }
  // every entity form decodes before the cut, hex and double-encoded included
  assertEquals(companyName('Acme Trading &#x2014; Best Prices'), 'Acme Trading');
  assertEquals(companyName('Acme Trading &amp;#8211; Best Prices'), 'Acme Trading');
  assertEquals(companyName('Acme Trading LLC, Sharjah'), 'Acme Trading LLC');
  assertEquals(companyName('Acme Trading, LLC'), 'Acme Trading, LLC');
  // still a title after every cut: the neutral greeting, never a sentence addressed as a company
  const title = 'Leading Supplier of Industrial Valves Pumps and Fittings for Oil Gas and Marine Projects';
  assertEquals(companyName(title), '');
  assert(m365InvitationText({ company: title }).startsWith('Hello,\n'));
  assertEquals(companyName('We supply the best tiles'), '');
});
