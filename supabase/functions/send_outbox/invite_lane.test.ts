// deno test supabase/functions/send_outbox/invite_lane.test.ts
// The invitation lane (invite_lane.ts): OFF is byte-identical to the mail before the lane existed; ON moves the
// invitation and its seed only; a sign-up code or a notice never takes the lane; an unverified domain HOLDS the
// lane's invitations (never sent from the main sender) with one it_engineer finding, while other mail still sends.
// Every Resend answer is replayed offline.
import { assert, assertEquals, assertNotEquals } from 'jsr:@std/assert@1';
import { HOLD_UNVERIFIED_MS, INVITE_LANE_TYPES, LANE_OFF, LANE_UNVERIFIED_ISSUE, heldUntil, holdFor, isLaneType, laneDomain, resolveLane, senderFor, type Fetch, type Lane } from './invite_lane.ts';
import { resendPayload } from './payload.ts';

const FROM_SUP = 'QuotesDone <info@quotesdone.com>';   // app_secrets.email_from_supplier, measured 24 Sep 2026
const FROM_INFO = 'QuotesDone <info@quotesdone.com>';  // app_secrets.email_from_info
const LANE_FROM = 'QuotesDone <invite@hello.quotesdone.com>';
const ON: Lane = { active: true, refused: false, from: LANE_FROM, domain: 'hello.quotesdone.com', why: 'verified' };

// Every notification type send_outbox is known to carry that is NOT an invitation, including the sign-up code
// shape and the supplier notices (quote, reveal, licence) — none may ever leave on the lane.
const NEVER = ['login_otp', 'otp', 'signup_code', 'email_code', 'customer_notice', 'quote_received', 'supplier_reveal',
  'supplier_licence_expiry', 'supplier_document_request', 'supplier_invite_reminder', 'supplier_invites_daily', 'supplier_invited',
  'founder_brief', 'accountant_report', 'supplier_invitex', '', null, undefined];

// The expression send_outbox used for the From before this file existed, kept here verbatim as the reference.
const before = (supplierSide: boolean) => supplierSide ? FROM_SUP : FROM_INFO;

const build = (from: string, supplierSide: boolean) => JSON.stringify(resendPayload({
  from, to: 'zz-demo@example.invalid', reply: supplierSide ? 'suppliers@mail.quotesdone.com' : 'info@quotesdone.com',
  subject: 'ZZ DEMO', html: '<meta charset="utf-8"><p>x</p>', text: 'x',
  unsub: supplierSide ? 'https://quotesdone.com/u/unsubscribe?e=zz&t=1' : '', unsubMailto: 'unsubscribe@mail.quotesdone.com' }));

Deno.test('flag OFF: every row, every side, the payload is byte-identical to the pre-lane mail', () => {
  for (const type of [...INVITE_LANE_TYPES, ...NEVER]) for (const side of [true, false]) {
    const from = senderFor({ type, supplierSide: side, fromSup: FROM_SUP, fromInfo: FROM_INFO, lane: LANE_OFF });
    assertEquals(from, before(side));
    assertEquals(build(from, side), build(before(side), side), `payload changed with the lane off for ${type}`);
    assertEquals(holdFor({ lane: LANE_OFF, type, supplierSide: side, laneSentToday: 10_000, laneCap: 0 }), null, `held with the lane off: ${type}`);
  }
});

Deno.test('flag ON: supplier_invite and supplier_invite_seed to a supplier take the lane; nothing else does', () => {
  for (const type of INVITE_LANE_TYPES) assertEquals(senderFor({ type, supplierSide: true, fromSup: FROM_SUP, fromInfo: FROM_INFO, lane: ON }), LANE_FROM);
  assertEquals([...INVITE_LANE_TYPES].sort(), ['supplier_invite', 'supplier_invite_seed']);
  for (const type of NEVER) for (const side of [true, false]) {
    assertEquals(senderFor({ type, supplierSide: side, fromSup: FROM_SUP, fromInfo: FROM_INFO, lane: ON }), before(side), `${type} took the lane`);
  }
  // A customer-side seed (the frame test) is not a supplier invitation and keeps the customer sender.
  assertEquals(senderFor({ type: 'supplier_invite_seed', supplierSide: false, fromSup: FROM_SUP, fromInfo: FROM_INFO, lane: ON }), FROM_INFO);
  assert(!isLaneType('supplier_invite_x') && !isLaneType('SUPPLIER_INVITE'), 'exact match only');
});

Deno.test('the lane\'s domain is read from its From', () => {
  assertEquals(laneDomain(LANE_FROM), 'hello.quotesdone.com');
  assertEquals(laneDomain('invite@Hello.QuotesDone.com'), 'hello.quotesdone.com');
  assertEquals(laneDomain('QuotesDone'), null);
});

type Call = { url: string; init?: RequestInit };
function fake(body: unknown, status = 200) {
  const calls: Call[] = [];
  const fetchFn: Fetch = (url, init) => { calls.push({ url, init }); return Promise.resolve(new Response(JSON.stringify(body), { status })); };
  return { calls, fetchFn };
}
function findings() { const list: Record<string, unknown>[] = []; return { list, fileFinding: (a: Record<string, unknown>) => { list.push(a); return Promise.resolve(); } }; }
const DOMAINS = (status: string, sending = 'enabled') => ({ data: [
  { name: 'quotesdone.com', status: 'verified', capabilities: { sending: 'enabled' } },
  { name: 'hello.quotesdone.com', status, capabilities: { sending } }] });

Deno.test('flag OFF asks nothing: no Resend call, no finding', async () => {
  for (const enabled of ['false', '', undefined, 'TRUE-ish']) {
    const f = fake(DOMAINS('verified')); const g = findings();
    const lane = await resolveLane({ enabled, from: LANE_FROM, apiKey: 'k', needed: true, fetchFn: f.fetchFn, fileFinding: g.fileFinding });
    assertEquals(lane.active, false); assertEquals(f.calls.length, 0); assertEquals(g.list.length, 0);
  }
});

Deno.test('flag ON with no invitation in the batch: no Resend call', async () => {
  const f = fake(DOMAINS('verified')); const g = findings();
  const lane = await resolveLane({ enabled: 'true', from: LANE_FROM, apiKey: 'k', needed: false, fetchFn: f.fetchFn, fileFinding: g.fileFinding });
  assertEquals(lane.active, false); assertEquals(f.calls.length, 0);
});

Deno.test('flag ON and verified: the lane is active, after one read-only GET /domains', async () => {
  const f = fake(DOMAINS('verified')); const g = findings();
  const lane = await resolveLane({ enabled: 'true', from: LANE_FROM, apiKey: 'k', needed: true, fetchFn: f.fetchFn, fileFinding: g.fileFinding });
  assertEquals(lane, ON);
  assertEquals(f.calls.length, 1);
  assertEquals(f.calls[0].url, 'https://api.resend.com/domains');
  assertEquals(f.calls[0].init?.method, 'GET');
  assertEquals(g.list.length, 0);
});

Deno.test('unverified domain HOLDS the lane\'s invitations: never the main sender, one it_engineer finding', async () => {
  const cases: Array<[unknown, number]> = [
    [DOMAINS('pending'), 200], [DOMAINS('not_started'), 200], [DOMAINS('failed'), 200], [DOMAINS('temporary_failure'), 200],
    [DOMAINS('verified', 'disabled'), 200], [{ data: [{ name: 'quotesdone.com', status: 'verified' }] }, 200], [{ message: 'no' }, 401], [{}, 500],
  ];
  for (const [body, status] of cases) {
    const f = fake(body, status); const g = findings();
    const lane = await resolveLane({ enabled: 'true', from: LANE_FROM, apiKey: 'k', needed: true, fetchFn: f.fetchFn, fileFinding: g.fileFinding });
    assertEquals(lane.active, false, JSON.stringify(body));
    assertEquals(lane.refused, true, JSON.stringify(body));
    for (const type of INVITE_LANE_TYPES) assertEquals(holdFor({ lane, type, supplierSide: true, laneSentToday: 0, laneCap: 30 }), 'unverified');
    assertEquals(g.list.length, 1);
    assertEquals(g.list[0].p_issue_key, LANE_UNVERIFIED_ISSUE);
    assertEquals(g.list[0].p_raised_by, 'it_engineer');
    assertNotEquals(String(lane.why), '');
  }
});

// The decision send_outbox's loop makes for each row, reduced to: held, or sent with this From.
function decide(lane: Lane, rows: Array<{ type: string; to_role: string }>, laneCap = 30) {
  let laneSentToday = 0;
  return rows.map((r) => {
    const supplierSide = r.to_role === 'supplier';
    const hold = holdFor({ lane, type: r.type, supplierSide, laneSentToday, laneCap });
    if (hold) return { type: r.type, held: hold };
    const from = senderFor({ type: r.type, supplierSide, fromSup: FROM_SUP, fromInfo: FROM_INFO, lane });
    if (lane.active && r.type === 'supplier_invite' && from === lane.from) laneSentToday++;
    return { type: r.type, from };
  });
}

Deno.test('Resend 5xx with the flag on: invitations are held while an OTP and a notice in the same batch still send', async () => {
  const g = findings();
  const lane = await resolveLane({ enabled: 'true', from: LANE_FROM, apiKey: 'k', needed: true, fetchFn: fake({ message: 'upstream' }, 503).fetchFn, fileFinding: g.fileFinding });
  const out = decide(lane, [
    { type: 'supplier_invite', to_role: 'supplier' }, { type: 'login_otp', to_role: 'customer' },
    { type: 'supplier_invite_seed', to_role: 'supplier' }, { type: 'quote_received', to_role: 'supplier' },
  ]);
  assertEquals(out, [
    { type: 'supplier_invite', held: 'unverified' }, { type: 'login_otp', from: FROM_INFO },
    { type: 'supplier_invite_seed', held: 'unverified' }, { type: 'quote_received', from: FROM_SUP },
  ]);
  assertEquals(g.list.length, 1);
});

Deno.test('a held backlog cannot blow the day\'s cap: at most invite_daily_cap lane invitations leave per day', () => {
  const out = decide(ON, Array.from({ length: 90 }, () => ({ type: 'supplier_invite', to_role: 'supplier' })), 30);
  assertEquals(out.filter((o) => 'from' in o).length, 30);
  assertEquals(out.filter((o) => 'held' in o && o.held === 'cap').length, 60);
  const now = new Date('2026-09-24T09:15:00Z');
  assertEquals(heldUntil('cap', now).toISOString(), '2026-09-25T06:00:00.000Z');
  assertEquals(heldUntil('unverified', now).getTime() - now.getTime(), HOLD_UNVERIFIED_MS);
});

Deno.test('Resend unreachable or the finding path broken: still refused, still OFF, never a throw', async () => {
  const lane = await resolveLane({ enabled: 'true', from: LANE_FROM, apiKey: 'k', needed: true,
    fetchFn: () => Promise.reject(new Error('timeout')), fileFinding: () => Promise.reject(new Error('rpc down')) });
  assertEquals(lane.active, false);
  const bad = findings();
  const lane2 = await resolveLane({ enabled: 'true', from: 'QuotesDone', apiKey: 'k', needed: true, fetchFn: fake(DOMAINS('verified')).fetchFn, fileFinding: bad.fileFinding });
  assertEquals(lane2.active, false); assertEquals(bad.list.length, 1);
});
