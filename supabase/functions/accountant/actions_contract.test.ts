// accountant — the contract of the door, pinned offline (9 Nov 2026), written BEFORE the 1,715-line index.ts was
// split into modules so the split could be proved against it: 48/48 on the single file, 48/48 on the split one.
//
// What it pins, driving the REAL handler (Deno.serve is captured on import) over a stubbed fetch that answers as
// PostgREST, GoTrue, Storage, Stripe and Resend would. Nothing reaches a real host: every URL that is not
// stub.invalid is answered 503 here, and the tests that care assert it was never asked.
//   1. The door: OPTIONS, and every way a caller is refused (no credential, a wrong one, a valid credential of
//      another seat — refused even beside a founder session — a signed-in non-admin, an unreadable body).
//   2. Every action the handler recognises is dispatched to its own handler: each one answers with its own status
//      and shape and reaches its own first table or routine. The list is checked against the source, so an action
//      added without a line here fails this file.
//   3. An unknown action answers exactly as before (400, the same body, the same advertised list).
//   4. Money: execute_refunds reaches Stripe only past every guard it has today (the CEO's breaker, the CEO
//      decision on the row, the refund window, the one decision for a 'requested' row, the fraud screen, the
//      payer's mode), in that order; the incident fixes only past their reservation; refund_request never.
// Every identity below is fictional: ZZ DEMO, example.invalid, sk_test_zz.
//   DENO_NO_PACKAGE_JSON=1 deno test --no-lock --node-modules-dir=none --allow-read=. --allow-env supabase/functions/accountant/
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

const ACC = 'zz-demo-accountant-credential';      // fn_internal_auth answers context fn.accountant
const OTHER = 'zz-demo-other-seat-credential';    // a valid credential of a different context
// Session tokens shaped as Supabase issues them (10 Nov 2026, security audit item 1): the founder's door now reads the
// `aal` claim through _shared/admin_session.ts, so a founder session must be aal2 to be the founder, and one that
// passed only the e-mail code (aal1) is refused 403 two_step_required. Unsigned: the stubbed GoTrue below vouches.
const zzJwt = (sub: string, aal: string) => [{ alg: 'ES256' }, { sub, aal, exp: 4102444800 }].map((o) => btoa(JSON.stringify(o)).replace(/=+$/, '')).join('.') + '.zz-demo-sig';
const FOUNDER_JWT = zzJwt('zz-u-founder', 'aal2'), FOUNDER_AAL1_JWT = zzJwt('zz-u-founder', 'aal1'), STRANGER_JWT = zzJwt('zz-u-stranger', 'aal2');
const FOUNDER = 'founder@example.invalid';
Deno.env.set('SUPABASE_URL', 'http://stub.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-service-key');

type Call = { i: number; method: string; host: string; path: string; search: string; body: string; headers: Headers };
type Reply = { status: number; body: unknown };
const reply = (status: number, body: unknown): Reply => ({ status, body });
const pgError = (message: string) => reply(400, { message, code: 'P0001', details: null, hint: null });
const isReply = (x: unknown): x is Reply => !!x && typeof x === 'object' && 'status' in x && 'body' in x && Object.keys(x).length === 2;
type World = {
  secrets: Record<string, string>;
  rpc: Record<string, (args: Record<string, unknown>, c: Call) => unknown>;
  table: Record<string, (c: Call) => unknown>;
  external: (c: Call) => unknown;
  internalAuth: (secret: string) => unknown;
};
const fresh = (): World => ({
  secrets: { admin_emails: FOUNDER },
  rpc: {}, table: {},
  external: () => reply(503, { error: { message: 'offline: the contract test reaches no real host' } }),
  internalAuth: (s) => s === ACC ? { ok: true, context: 'fn.accountant', credential_id: 1, legacy: false }
    : s === OTHER ? { ok: true, context: 'fn.someone_else', credential_id: 2, legacy: false } : { ok: false },
});
let world = fresh();
let calls: Call[] = [];

function route(c: Call): Reply {
  if (c.host !== 'stub.invalid') { const r = world.external(c); return isReply(r) ? r : reply(200, r); }
  if (c.path === '/auth/v1/user') {
    const jwt = (c.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
    if (jwt === FOUNDER_JWT || jwt === FOUNDER_AAL1_JWT) return reply(200, { id: 'zz-u-founder', aud: 'authenticated', email: FOUNDER, factors: [{ factor_type: 'totp', status: 'verified' }] });
    if (jwt === STRANGER_JWT) return reply(200, { id: 'zz-u-stranger', aud: 'authenticated', email: 'stranger@example.invalid' });
    return reply(401, { code: 401, msg: 'invalid JWT' });
  }
  if (c.path.startsWith('/rest/v1/rpc/')) {
    const fn = c.path.slice('/rest/v1/rpc/'.length);
    const args = c.body ? JSON.parse(c.body) : {};
    const r = fn === 'fn_internal_auth' ? world.internalAuth(String(args.p_secret)) : world.rpc[fn] ? world.rpc[fn](args, c) : null;
    return isReply(r) ? r : reply(200, r);
  }
  if (c.path === '/rest/v1/app_secrets') {
    const key = /key=eq\.([^&]+)/.exec(c.search)?.[1] ?? '';
    return reply(200, key in world.secrets ? [{ value: world.secrets[key] }] : []);
  }
  if (c.path.startsWith('/rest/v1/')) {
    const t = c.path.slice('/rest/v1/'.length);
    const r = world.table[t] ? world.table[t](c) : [];
    return isReply(r) ? r : reply(200, r);
  }
  if (c.path.startsWith('/storage/v1/')) return reply(400, { statusCode: '400', error: 'stub', message: 'no storage offline' });
  return reply(503, { error: 'offline' });
}

globalThis.fetch = (async (input: Request | URL | string, init?: RequestInit) => {
  const req = new Request(input, init);
  const u = new URL(req.url);
  const body = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.text();
  const c: Call = { i: calls.length, method: req.method, host: u.host, path: u.pathname, search: decodeURIComponent(u.search), body, headers: req.headers };
  calls.push(c);
  const r = route(c);
  return new Response(req.method === 'HEAD' ? null : JSON.stringify(r.body), {
    status: r.status, headers: { 'Content-Type': 'application/json', 'Content-Range': '*/0' },
  });
}) as typeof fetch;

let handler!: (req: Request) => Promise<Response>;
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (h: (req: Request) => Promise<Response>) => { handler = h; return {}; };
await import('./index.ts');

const send = (body: unknown, headers: Record<string, string> = {}, method = 'POST') =>
  handler(new Request('https://x.invalid/accountant', { method, headers: { 'content-type': 'application/json', ...headers },
    body: method === 'POST' ? (typeof body === 'string' ? body : JSON.stringify(body)) : undefined }));
const asSeat = (action: string, extra: Record<string, unknown> = {}) => send({ __secret: ACC, action, ...extra });
// deno-lint-ignore no-explicit-any
const read = async (r: Response): Promise<{ status: number; j: any }> => ({ status: r.status, j: JSON.parse(await r.text()) });
const begin = (w: Partial<World> = {}) => { world = { ...fresh(), ...w }; calls = []; };
// The handler's background writes (observe's run log) and timedFetch's timers outlive a response by design.
const t = (name: string, fn: () => Promise<void>) => Deno.test({ name, fn, sanitizeOps: false, sanitizeResources: false });
// What the action itself asked the database, without the door's own reads and the run log.
const DOOR = new Set(['/rest/v1/rpc/fn_internal_auth', '/rest/v1/app_secrets', '/rest/v1/agent_runs', '/auth/v1/user', '/rest/v1/rpc/fn_e2e_run_tag_open']);
const own = () => calls.filter((c) => c.host === 'stub.invalid' && !DOOR.has(c.path));
const stripeCalls = () => calls.filter((c) => c.host === 'api.stripe.com');
const external = () => calls.filter((c) => c.host !== 'stub.invalid');

// ── 1. THE DOOR ─────────────────────────────────────────────────────────────────────────────────────────────────────
t('OPTIONS answers ok with the CORS headers, before anything is read', async () => {
  begin();
  const r = await send(undefined, {}, 'OPTIONS');
  assertEquals(r.status, 200);
  assertEquals(await r.text(), 'ok');
  assertEquals(r.headers.get('access-control-allow-origin'), '*');
  assertEquals(r.headers.get('access-control-allow-headers'), 'authorization, content-type, apikey');
  assertEquals(r.headers.get('access-control-allow-methods'), 'POST, OPTIONS');
  assertEquals(calls.filter((c) => c.path.startsWith('/rest/v1/rpc/fn_internal_auth')).length, 0);
});

t('refused: no credential and no session', async () => {
  begin();
  const r = await read(await send({ action: 'health' }));
  assertEquals(r, { status: 401, j: { error: 'unauthorized' } });
  assertEquals(own().length, 0, 'nothing of the action ran');
});

t('refused: an unreadable body is an empty body, so no credential', async () => {
  begin();
  assertEquals(await read(await send('{not json')), { status: 401, j: { error: 'unauthorized' } });
});

t('refused: a wrong credential with no session', async () => {
  begin();
  assertEquals(await read(await send({ __secret: 'zz-wrong', action: 'health' })), { status: 401, j: { error: 'unauthorized' } });
});

t('refused: a VALID credential of another seat, even beside a founder session (no fallback to the session)', async () => {
  begin();
  const r = await read(await send({ __secret: OTHER, action: 'health' }, { Authorization: 'Bearer ' + FOUNDER_JWT }));
  assertEquals(r, { status: 401, j: { error: 'unauthorized' } });
  assertEquals(calls.filter((c) => c.path === '/rest/v1/app_secrets' && c.search.includes('admin_emails')).length, 0, 'the admin list is never read');
});

t('refused: a signed-in identity that is not on admin_emails, and a session the auth server rejects', async () => {
  begin();
  assertEquals(await read(await send({ action: 'health' }, { Authorization: 'Bearer ' + STRANGER_JWT })), { status: 401, j: { error: 'unauthorized' } });
  begin();
  assertEquals(await read(await send({ action: 'health' }, { Authorization: 'Bearer zz-forged' })), { status: 401, j: { error: 'unauthorized' } });
});

t('refused: the credential verifier unreachable is a refusal, not a pass', async () => {
  begin({ internalAuth: () => pgError('verifier down') });
  assertEquals(await read(await send({ __secret: ACC, action: 'health' })), { status: 401, j: { error: 'unauthorized' } });
});

t('the door is checked before the action: an unknown action from nobody is 401, not 400', async () => {
  begin();
  assertEquals((await send({ action: 'zz_nope' })).status, 401);
});

t('refused: a founder session that passed only the e-mail code (aal1) is 403 two_step_required, naming the step', async () => {
  begin();
  const r = await read(await send({ action: 'ledger' }, { Authorization: 'Bearer ' + FOUNDER_AAL1_JWT }));
  assertEquals([r.status, r.j.error, r.j.step], [403, 'two_step_required', 'challenge']);
});

t('admitted: the seat credential is the accountant; a wrong credential beside a founder session is the founder', async () => {
  begin();
  assertEquals((await read(await asSeat('health'))).j.caller, 'accountant');
  begin();
  const f = await read(await send({ __secret: 'zz-wrong', action: 'health' }, { Authorization: 'Bearer ' + FOUNDER_JWT }));
  assertEquals([f.status, f.j.caller], [200, 'founder']);
  begin();
  const g = await read(await send({ action: 'ledger' }, { Authorization: 'bearer ' + FOUNDER_JWT }));
  assertEquals([g.status, g.j.caller], [200, 'founder']);
});

// ── 2. EVERY ACTION IS DISPATCHED TO ITS OWN HANDLER ────────────────────────────────────────────────────────────────
// action -> the body sent, the status, fields and exact top-level keys it answers with (null: it answers JSON null, the
// routine's own answer under the stub), and a table or routine only its own handler asks
// ('' = it answers before asking the database anything).
type Case = { body?: Record<string, unknown>; status: number; has: Record<string, unknown>; keys: string | null; first: string };
const CASES: Record<string, Case> = {
  health: { status: 200, has: { ok: true, seat: 'accountant', caller: 'accountant', seated: false }, keys: 'caller grants ledger_state model_calls_available model_hold ok owns_functions reports_to seat seated', first: 'GET /rest/v1/org_agents' },
  document: { status: 400, has: { ok: false, error: 'entry_id is required' }, keys: 'error ok', first: '' },
  documents: { status: 200, has: { ok: true, seat: 'accountant', coverage: null, entries: [] }, keys: 'basis coverage entries ok seat', first: 'POST /rest/v1/rpc/fn_expense_document_coverage' },
  refund_document: { status: 400, has: { ok: false, error: 'refund_id is required' }, keys: 'error ok', first: '' },
  refund_documents: { status: 200, has: { ok: true, seat: 'accountant', coverage: null, refunds: [] }, keys: 'basis coverage ok refunds seat', first: 'POST /rest/v1/rpc/fn_refund_document_coverage' },
  revenue_document: { status: 400, has: { ok: false, error: 'transaction_id is required' }, keys: 'error ok', first: '' },
  revenue_documents: { status: 200, has: { ok: true, seat: 'accountant', coverage: null, sales: [] }, keys: 'basis coverage ok sales seat', first: 'POST /rest/v1/rpc/fn_revenue_document_coverage' },
  grants: { status: 200, has: { ok: true, grants: [] }, keys: 'grants ok', first: 'GET /rest/v1/ceo_standing_grant' },
  ledger: { status: 200, has: { ok: true, seat: 'accountant', caller: 'accountant', unreadable: [] }, keys: 'basis books caller note ok seat unreadable', first: 'HEAD /rest/v1/gl_accounts' },
  refund_request: { status: 400, has: { error: 'amount_aed_required' }, keys: 'error note', first: '' },
  assist: { status: 400, has: { error: 'question_required' }, keys: 'error', first: '' },
  execute_refunds: { status: 200, has: { ok: true, seat: 'accountant', paused: false, results: [] }, keys: 'ok paused results seat', first: 'POST /rest/v1/rpc/fn_refunds_paused' },
  handoffs: { status: 200, has: { ok: true, seat: 'accountant', open: [] }, keys: 'ok open seat', first: 'GET /rest/v1/agent_actions' },
  complete_handoff: { body: { id: 5 }, status: 404, has: { error: 'not_this_seats_handoff' }, keys: 'error', first: 'GET /rest/v1/agent_actions' },
  expense_sweep: { status: 503, has: { ok: false, error: 'resend_api_key_unavailable' }, keys: 'error ok', first: '' },
  spend_report: { status: 200, has: { ok: true, seat: 'accountant', caller: 'accountant', delivery: null, delivery_armed: false }, keys: 'caller delivery delivery_armed links note ok pdf pdf_error report seat', first: 'POST /rest/v1/rpc/fn_accountant_spend_report' },
  duties: { status: 200, has: { ok: true, seat: 'accountant', skipped: 'the duties ran within the last 55 minutes' }, keys: 'ok seat skipped', first: 'POST /rest/v1/rpc/fn_accountant_duties_due' },
  reveal_reconcile: { status: 200, has: { ok: true, seat: 'accountant', outcomes: {}, result: null }, keys: 'ok outcomes result seat', first: 'POST /rest/v1/rpc/fn_accountant_reveal_reconcile_record' },
  bank_statement: { status: 400, has: { ok: false, error: 'source_ref is required' }, keys: 'error ok', first: '' },
  filing_outcome: { status: 200, has: {}, keys: null, first: 'POST /rest/v1/rpc/fn_accountant_record_filing_outcome' },
  court_step: { status: 200, has: {}, keys: null, first: 'POST /rest/v1/rpc/fn_accountant_record_court_step' },
  charge_resolve: { status: 200, has: {}, keys: null, first: 'POST /rest/v1/rpc/fn_accountant_charge_audit_resolve' },
};

t('the actions pinned here are exactly the actions the source matches on', () => {
  const src = functionSource('accountant');
  const matched = new Set([...src.matchAll(/action === '([a-z_]+)'/g)].map((m) => m[1]));
  assertEquals([...matched].sort(), Object.keys(CASES).sort());
  return Promise.resolve();
});

for (const [action, k] of Object.entries(CASES)) {
  t(`dispatch: ${action} reaches its own handler`, async () => {
    begin();
    const r = await read(await asSeat(action, k.body ?? {}));
    assert(r.j === null || r.j.error !== 'unknown_action', action + ' fell through to unknown_action');
    assertEquals(r.status, k.status, action + ': ' + JSON.stringify(r.j).slice(0, 300));
    assertEquals(r.j === null ? null : Object.keys(r.j).sort().join(' '), k.keys, action + ': the answer has another shape');
    for (const [key, v] of Object.entries(k.has)) assertEquals(r.j?.[key], v, action + '.' + key);
    const asked = own().map((c) => c.method + ' ' + c.path);
    if (k.first) assert(asked.includes(k.first), action + ' never asked ' + k.first + ': ' + JSON.stringify(asked));
    else assertEquals(asked, [], action + ' answers before asking the database anything');
    assertEquals(external().map((c) => c.host + c.path), [], action + ' reached an outside host');
  });
}

t('dispatch: the action name is trimmed before it is matched', async () => {
  begin();
  const r = await read(await asSeat('  health  '));
  assertEquals([r.status, r.j.seat], [200, 'accountant']);
});

t('dispatch: grants with a class asks fn_agent_may_act for this seat, and a refusal is a 400 carrying it', async () => {
  begin({ ...fresh(), rpc: { fn_agent_may_act: (a) => ({ may_act: false, reason: 'zz', route: 'ceo_case_decision', echo: a }) } });
  const r = await read(await asSeat('grants', { action_class: 'refund', amount_aed: 5 }));
  assertEquals(r.status, 200);
  assertEquals(r.j.action_class, 'refund');
  assertEquals(r.j.echo, { p_grantee_role_id: 'accountant', p_action_class: 'refund', p_amount_aed: 5 });
  begin({ ...fresh(), rpc: { fn_agent_may_act: () => pgError('zz refused') } });
  assertEquals(await read(await asSeat('grants', { action_class: 'refund' })), { status: 400, j: { ok: false, refused: 'zz refused' } });
});

// ── 3. AN UNKNOWN ACTION ────────────────────────────────────────────────────────────────────────────────────────────
const ADVERTISED = ['health', 'grants', 'ledger', 'refund_request', 'expense_sweep', 'spend_report', 'assist', 'document', 'documents',
  'refund_document', 'refund_documents', 'revenue_document', 'revenue_documents', 'execute_refunds', 'handoffs', 'complete_handoff',
  'duties', 'bank_statement', 'filing_outcome', 'court_step', 'charge_resolve'];
t('unknown action: 400 with the action named and the same advertised list (reveal_reconcile is not on it, as before)', async () => {
  begin();
  assertEquals(await read(await asSeat('zz_nope')), { status: 400, j: { error: 'unknown_action', action: 'zz_nope', actions: ADVERTISED } });
  begin();
  assertEquals(await read(await send({ __secret: ACC })), { status: 400, j: { error: 'unknown_action', action: '', actions: ADVERTISED } });
  assertEquals(own().length, 0, 'an unknown action reads nothing');
});

// ── 4. MONEY: NOTHING REACHES STRIPE PAST A GUARD ───────────────────────────────────────────────────────────────────
const ROW = { id: 7, transaction_id: 'zz-tx-1', customer_id: 'zz-c-1', supplier_lead_id: 'zz-s-1', amount_fils: 1234,
  stripe_payment_intent: 'pi_zz_1', refund_decision_id: 99, status: 'approved' };
type Money = { paused?: unknown; rows?: Record<string, unknown>[]; deadline?: string | null; email?: string | null;
  decide?: unknown; screen?: unknown; fixes?: Record<string, unknown>[]; topup?: unknown; retryRow?: unknown };
function money(m: Money = {}) {
  const w = fresh();
  w.secrets = { ...w.secrets, stripe_secret_key: 'sk_live_zz', stripe_secret_key_test: 'sk_test_zz' };
  w.rpc = {
    fn_refunds_paused: () => m.paused ?? false,
    fn_refund_decide: () => m.decide ?? { ok: true },
    fn_accountant_money_screen: () => m.screen ?? { hold: false },
    fn_refund_settle: () => ({ ok: true }),
    fn_accountant_reserves_topup: () => m.topup ?? { ok: false, reason: 'zz not reserved' },
    fn_accountant_incident_fix_failed: () => ({ ok: true }),
    fn_seat_handoff_complete: () => ({ ok: true }),
  };
  w.table = {
    refunds: (c) => c.method === 'GET' ? (m.rows ?? [ROW]) : (c.method === 'PATCH' && c.search.includes('status=eq.failed') ? (m.retryRow ?? []) : []),
    transactions: () => [{ refund_deadline: m.deadline === undefined ? '2026-01-01T00:00:00Z' : m.deadline, customer_id: 'zz-c-1' }],
    customers: () => m.email === null ? [] : [{ email: m.email ?? 'buyer@example.invalid' }],
    agent_actions: () => m.fixes ?? [],
  };
  w.external = (c) => {
    if (c.host !== 'api.stripe.com') return reply(503, {});
    if (c.method === 'GET' && c.path.startsWith('/v1/payment_intents/')) return { id: c.path.split('/').pop(), livemode: false };
    if (c.method === 'POST' && c.path === '/v1/refunds') return { id: 're_zz_new', status: 'succeeded', amount: Number(new URLSearchParams(c.body).get('amount')) };
    if (c.method === 'POST' && /\/v1\/refunds\/[^/]+\/cancel$/.test(c.path)) return { id: c.path.split('/')[3], status: 'canceled' };
    return reply(404, { error: { message: 'zz no such object' } });
  };
  begin(w);
}
const posted = () => stripeCalls().filter((c) => c.method === 'POST');
const rpcAt = (fn: string) => calls.findIndex((c) => c.path === '/rest/v1/rpc/' + fn);

t('execute_refunds: a CEO-approved row past every guard is sent once, at its amount, under the transaction key, with the payer-mode key', async () => {
  money();
  const r = await read(await asSeat('execute_refunds'));
  assertEquals(r.status, 200);
  assertEquals(r.j.results, [{ refund_id: 7, stripe_refund_id: 're_zz_new', status: 'succeeded', mode: 'test' }]);
  const q = calls.find((c) => c.method === 'GET' && c.path === '/rest/v1/refunds')!;
  for (const g of ['refund_decision_id=not.is.null', 'status=in.(requested,approved)', 'stripe_refund_id=is.null', 'limit=20']) assert(q.search.includes(g), 'the approved-refund read lost its guard ' + g + ': ' + q.search);
  const sent = posted();
  assertEquals(sent.length, 1);
  const form = new URLSearchParams(sent[0].body);
  assertEquals([form.get('payment_intent'), form.get('amount'), form.get('metadata[approved_by]')], ['pi_zz_1', '1234', 'ceo']);
  assertEquals(sent[0].headers.get('idempotency-key'), 'qd_refund_zz-tx-1');
  assertEquals(sent[0].headers.get('authorization'), 'Bearer sk_test_zz', 'a demo payer is refunded with the test key');
  // the order: the window, then the screen, then Stripe, then the record
  const tx = calls.findIndex((c) => c.path === '/rest/v1/transactions');
  assert(tx >= 0 && tx < rpcAt('fn_accountant_money_screen') && rpcAt('fn_accountant_money_screen') < sent[0].i && sent[0].i < rpcAt('fn_refund_settle'));
  assertEquals(rpcAt('fn_refund_decide'), -1, 'an approved row is not decided again');
});

t('execute_refunds: the CEO breaker on sends nothing and reads no refund', async () => {
  money({ paused: true });
  const r = await read(await asSeat('execute_refunds'));
  assertEquals([r.status, r.j.paused, r.j.results], [200, true, []]);
  assertEquals(stripeCalls().length, 0);
  assertEquals(calls.filter((c) => c.path === '/rest/v1/refunds').length, 0);
});

t('execute_refunds: before the refund window opens, nothing is sent', async () => {
  money({ deadline: '2999-01-01T00:00:00Z' });
  const r = await read(await asSeat('execute_refunds'));
  assertEquals(r.j.results, [{ refund_id: 7, error: 'refund_window_not_yet_open', decision_after: '2999-01-01T00:00:00Z' }]);
  assertEquals(stripeCalls().length, 0);
});

t('execute_refunds: an overcharge return waits for no refund window and is sent under its own key; the fee case keeps the transaction key', async () => {
  money({ deadline: '2999-01-01T00:00:00Z', rows: [{ ...ROW, id: 41, amount_fils: 3877, reason_code: 'overcharge_return' }] });
  const r = await read(await asSeat('execute_refunds'));
  assertEquals(r.j.results, [{ refund_id: 41, stripe_refund_id: 're_zz_new', status: 'succeeded', mode: 'test' }]);
  assertEquals(posted().length, 1);
  assertEquals(posted()[0].headers.get('idempotency-key'), 'qd_refund_zz-tx-1_over41');
  assertEquals(new URLSearchParams(posted()[0].body).get('amount'), '3877');
  assert(calls.find((c) => c.method === 'GET' && c.path === '/rest/v1/refunds')!.search.includes('reason_code'), 'the read must carry reason_code');
  // the fee case on the same sale, before its window: still held; after it: the transaction key
  money({ deadline: '2999-01-01T00:00:00Z', rows: [{ ...ROW, reason_code: 'supplier_unresponsive' }] });
  assertEquals((await read(await asSeat('execute_refunds'))).j.results[0].error, 'refund_window_not_yet_open');
  assertEquals(stripeCalls().length, 0);
  money({ rows: [{ ...ROW, reason_code: 'supplier_unresponsive' }] });
  await asSeat('execute_refunds');
  assertEquals(posted()[0].headers.get('idempotency-key'), 'qd_refund_zz-tx-1');
});

t("execute_refunds: a 'requested' row is decided first; a refused decision sends nothing", async () => {
  money({ rows: [{ ...ROW, status: 'requested' }], decide: { ok: false, reason: 'zz second seat says no' } });
  const r = await read(await asSeat('execute_refunds'));
  assertEquals(r.j.results, [{ refund_id: 7, error: 'not_approved', decide: { ok: false, reason: 'zz second seat says no' } }]);
  assertEquals(stripeCalls().length, 0);
  money({ rows: [{ ...ROW, status: 'requested' }], decide: pgError('zz decide raised') });
  assertEquals((await read(await asSeat('execute_refunds'))).j.results[0].error, 'not_approved');
  assertEquals(stripeCalls().length, 0);
  money({ rows: [{ ...ROW, status: 'requested' }] });
  await asSeat('execute_refunds');
  const d = calls.find((c) => c.path === '/rest/v1/rpc/fn_refund_decide')!;
  assertEquals(JSON.parse(d.body), { p_refund_id: 7, p_approve: true, p_decided_by: 'ceo' });
  assertEquals(posted().length, 1);
  assert(d.i < posted()[0].i, 'decided before Stripe, never after');
});

t('execute_refunds: a fraud hold, or a screen that cannot answer, sends nothing', async () => {
  money({ screen: { hold: true, hold_id: 'zz-h' } });
  assertEquals((await read(await asSeat('execute_refunds'))).j.results, [{ refund_id: 7, held: 'fraud_review', hold_id: 'zz-h' }]);
  assertEquals(stripeCalls().length, 0);
  money({ screen: pgError('zz screen down') });
  assertEquals((await read(await asSeat('execute_refunds'))).j.results, [{ refund_id: 7, error: 'money_screen_failed: zz screen down' }]);
  assertEquals(stripeCalls().length, 0);
  const s = calls.find((c) => c.path === '/rest/v1/rpc/fn_accountant_money_screen')!;
  assertEquals(JSON.parse(s.body), { p_move: 'refund', p_ref: '7', p_customer: 'zz-c-1', p_supplier: 'zz-s-1' });
});

t('execute_refunds: a payer whose mode cannot be known sends nothing', async () => {
  money({ email: null });
  assertEquals((await read(await asSeat('execute_refunds'))).j.results, [{ refund_id: 7, error: 'payer_unknown: the Stripe mode of this payment cannot be known, nothing sent' }]);
  assertEquals(stripeCalls().length, 0);
});

t('execute_refunds: a named refund narrows the read to it and never picks up incident fixes', async () => {
  money({ rows: [] });
  await asSeat('execute_refunds', { refund_id: 7 });
  const q = calls.find((c) => c.method === 'GET' && c.path === '/rest/v1/refunds')!;
  assert(q.search.includes('id=eq.7'), q.search);
  assertEquals(calls.filter((c) => c.path === '/rest/v1/agent_actions').length, 0);
});

const FIX = (detail: Record<string, unknown>) => ({ id: 55, detail: { type: 'incident.fix', payment_ref: 'pi_zz_9', transaction_id: 'zz-tx-9', ...detail } });
t('incident fix refund_difference: nothing is sent until the top-up is reserved; reserved, it is sent at the reserved amount', async () => {
  money({ rows: [], fixes: [FIX({ fix: 'refund_difference', amount_fils: 300 })] });
  const r = await read(await asSeat('execute_refunds'));
  assertEquals(r.j.results, [{ fix: 55, error: 'zz not reserved' }]);
  assertEquals(stripeCalls().length, 0);
  const f = calls.find((c) => c.path === '/rest/v1/agent_actions')!;
  for (const g of ['kind=eq.handoff', 'agent=eq.accountant', 'status=eq.pending', 'detail->>type=eq.incident.fix']) assert(f.search.includes(g), f.search);
  assert(rpcAt('fn_accountant_incident_fix_failed') >= 0);
  money({ rows: [], fixes: [FIX({ fix: 'refund_difference', amount_fils: 300 })], topup: { ok: true, refund_id: 81, amount_fils: 300 } });
  const ok = await read(await asSeat('execute_refunds'));
  assertEquals(ok.j.results, [{ fix: 55, stripe_refund_id: 're_zz_new' }]);
  assertEquals(posted().length, 1);
  assertEquals(new URLSearchParams(posted()[0].body).get('amount'), '300');
  assertEquals(posted()[0].headers.get('idempotency-key'), 'qd_refund_zz-tx-9_topup81');
  assert(rpcAt('fn_accountant_reserves_topup') < posted()[0].i, 'reserved before Stripe');
});

t('incident fix retry_refund: only a failed refund that could be moved to processing is retried', async () => {
  money({ rows: [], fixes: [FIX({ fix: 'retry_refund', refund_id: 40 })] });
  const r = await read(await asSeat('execute_refunds'));
  assertEquals(r.j.results, [{ fix: 55, error: 'refund #40 is not a failed refund that can be retried' }]);
  assertEquals(stripeCalls().length, 0);
  money({ rows: [], fixes: [FIX({ fix: 'retry_refund', refund_id: 40 })], retryRow: [{ amount_fils: 500 }] });
  await asSeat('execute_refunds');
  assertEquals(posted().length, 1);
  assertEquals(posted()[0].headers.get('idempotency-key'), 'qd_refund_zz-tx-9_retry55');
});

t('incident fix cancel_duplicate: the first refund is kept, only the duplicates are cancelled', async () => {
  money({ rows: [], fixes: [FIX({ fix: 'cancel_duplicate', refund_ids: ['re_keep', 're_dup1', 're_dup2'] })] });
  const r = await read(await asSeat('execute_refunds'));
  assertEquals(r.j.results, [{ fix: 55, cancelled: 2, of: 2 }]);
  assertEquals(posted().map((c) => c.path), ['/v1/refunds/re_dup1/cancel', '/v1/refunds/re_dup2/cancel']);
});

t('a handler that throws is a 500 with the message and an error run, and a row with no transaction id throws BEFORE Stripe', async () => {
  money({ rows: [{ ...ROW, transaction_id: '' }] });
  const r = await read(await asSeat('execute_refunds'));
  assertEquals(r, { status: 500, j: { error: 'a refund idempotency key needs the transaction id' } });
  assertEquals(stripeCalls().filter((c) => c.path === '/v1/refunds').length, 0);
  const logged = calls.filter((c) => c.method === 'POST' && c.path === '/rest/v1/agent_runs').map((c) => JSON.parse(c.body));
  assert(logged.some((x) => x.agent === 'accountant' && x.status === 'error' && x.counts?.action === 'error'), JSON.stringify(logged));
});

t('incident fix with an unknown payer sends nothing', async () => {
  money({ rows: [], email: null, fixes: [FIX({ fix: 'cancel_duplicate', refund_ids: ['re_keep', 're_dup1'] })] });
  const w = world;
  w.table.transactions = () => [];
  w.table.refunds = () => [];
  const r = await read(await asSeat('execute_refunds'));
  assertEquals(r.j.results, [{ fix: 55, error: 'payer_unknown' }]);
  assertEquals(stripeCalls().length, 0);
});

t('refund_request never reaches Stripe: a refusal opens a CEO decision; a permit still executes nothing', async () => {
  money();
  world.rpc.fn_agent_may_act = () => ({ may_act: false, reason: 'ceiling 0', route: 'ceo_case_decision' });
  world.rpc.fn_ceo_request_decision = () => ({ ok: true, report: { report_id: 3 } });
  const r = await read(await asSeat('refund_request', { amount_aed: 50, transaction_id: 'zz-tx-1', recommendation: 'refund' }));
  assertEquals([r.status, r.j.routed_to_ceo, r.j.grant_refusal], [200, true, { may_act: false, reason: 'ceiling 0', route: 'ceo_case_decision' }]);
  const d = JSON.parse(calls.find((c) => c.path === '/rest/v1/rpc/fn_ceo_request_decision')!.body);
  assertEquals([d.p_idempotency_key, d.p_recommendation, d.p_case_id], ['accountant-refund-zz-tx-1', 'refund', null]);
  assertEquals(external().length, 0);
  world.rpc.fn_ceo_request_decision = () => ({ ok: false, reason: 'zz no evidence' });
  calls = [];
  const no = await read(await asSeat('refund_request', { amount_aed: 50 }));
  assertEquals([no.status, no.j.refused_by, no.j.reason], [400, 'fn_ceo_request_decision', 'zz no evidence']);
  world.rpc.fn_agent_may_act = () => ({ may_act: true, grant: 'zz' });
  calls = [];
  const yes = await read(await asSeat('refund_request', { amount_aed: 50 }));
  assertEquals([yes.status, yes.j.routed_to_ceo, yes.j.may_act], [200, false, true]);
  assertEquals(rpcAt('fn_ceo_request_decision'), -1);
  assertEquals(external().length, 0);
  world.rpc.fn_agent_may_act = () => pgError('zz grant check down');
  assertEquals(await read(await asSeat('refund_request', { amount_aed: 50 })), { status: 503, j: { ok: false, error: 'grant_check_failed', detail: 'zz grant check down' } });
});
