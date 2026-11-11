// A CODE CHECK MAKES ITS INDEPENDENT CALLS TOGETHER (11 Nov 2026, it_engineer; supplier registration certification).
//
// Measured on production for the 2,798 ms verify of 11:38:31Z (edge_logs, one request): twelve database and auth calls in a
// row, each waiting for the one before. On a warm minute a hop costs ~45 ms and the handler ~510 ms (p50); on a slow one a
// hop cost 130-470 ms and the handler 2,272 ms. These pin the shape that fixed it, and the security order it must keep:
//   * the reads after the code is proved (role, sanctions, auth user, language) leave in ONE wave;
//   * the leads/customers write runs beside the session's auth calls, not before them;
//   * the longest chain of calls that wait on each other is 6 for a returning account (was 10, 11 cold), 7 for a new one (was 11-12);
//   * the two limiters stay serial: a capped IP never spends an address's bucket (rl_check counts only what it admits);
//   * a sanctioned address still gets no auth user, no link and no session, and a failed sanctions read still refuses;
//   * a role conflict still writes nothing and creates nobody;
//   * x-qd-warm answers 204 with no call at all, and each verify row carries its per-stage ms.
// Every call the function makes is held for D ms by the stub, so "together" is measured, not inferred from the source.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, invokeRequest, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('login_otp', () => import('./index.ts'));
const D = 30;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
type Span = { what: string; start: number; end: number };
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
const b64 = (o: unknown) => btoa(JSON.stringify(o)).replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
const jwt = (sub: string) => `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub, role: 'authenticated', exp: 4102444800 })}.sig`;

/** A stub that holds every database and auth call for D ms and records when it started and ended. */
function world(opts: { uid?: string | null; sanctioned?: boolean | 'unreadable'; ipCapped?: boolean; leads?: unknown[]; customers?: unknown[] } = {}) {
  const spans: Span[] = [];
  const stub: Stub = {
    rows: { leads: opts.leads ?? [{ id: 7, claimed_by: 'x' }], customers: opts.customers ?? [], sanctions_ban: opts.sanctioned === true ? [{ lead_id: 9 }] : [] },
    rpc: { auth_uid_by_email: opts.uid === undefined ? 'uid-existing' : opts.uid, fn_login_otp_email_verify: 'ok', rl_check: true, fn_registered_locale: 'en' },
    handle: async (req, u) => {
      if (u.pathname === '/rest/v1/agent_runs' || u.pathname === '/auth/v1/user') return undefined;   // telemetry and observe's own lookup
      const body = req.method === 'GET' ? {} : await req.clone().json().catch(() => ({}));
      const what = req.method + ' ' + u.pathname + (u.pathname === '/rest/v1/rpc/rl_check' ? ' ' + String(body.p_key).split(':')[0] : '');
      const span = { what, start: performance.now(), end: 0 };
      spans.push(span);
      await sleep(D);
      span.end = performance.now();
      if (u.pathname === '/rest/v1/rpc/rl_check') return json(!(opts.ipCapped && String(body.p_key).startsWith('login_otp_verify_ip:')));
      if (u.pathname === '/rest/v1/sanctions_ban' && opts.sanctioned === 'unreadable') return json({ message: 'connection reset' }, 500);
      if (u.pathname === '/auth/v1/admin/generate_link') return json({ id: 'u1', email: body.email, hashed_token: 'th:' + body.email });
      if (u.pathname === '/auth/v1/verify') {
        const email = String(body.token_hash || '').slice(3);
        return json({ access_token: jwt('sub-' + email), refresh_token: 'rt', token_type: 'bearer', expires_in: 3600, expires_at: 4102444800, user: { id: 'sub-' + email, email, aud: 'authenticated' } });
      }
      return undefined;
    },
  };
  return { stub, spans };
}
const verify = (email: string, kind = 'supplier') => ({ action: 'verify', user_kind: kind, identifier: email, code: '123456' });
const find = (spans: Span[], what: string) => spans.filter((s) => s.what === what);
const overlap = (a: Span, b: Span) => a.start < b.end && b.start < a.end;
/** The longest chain of calls each of which started only after the one before it ended: the round trips a caller waits for. */
function chain(spans: Span[]): number {
  const s = [...spans].sort((a, b) => a.start - b.start);
  const depth: number[] = [];
  s.forEach((c, i) => { depth[i] = 1 + Math.max(0, ...s.slice(0, i).map((p, j) => (p.end <= c.start ? depth[j] : 0))); });
  return Math.max(0, ...depth);
}

Deno.test('verify: once the code is proved, the role, sanctions, auth-user and language reads leave in one wave', async () => {
  const { stub, spans } = world();
  const r = await invoke(await fn(), stub, verify('qd-speed-a@example.invalid'));
  assertEquals(r.status, 200, JSON.stringify(r.json));
  const wave = [...find(spans, 'GET /rest/v1/leads'), ...find(spans, 'GET /rest/v1/customers'), ...find(spans, 'GET /rest/v1/sanctions_ban'),
    ...find(spans, 'POST /rest/v1/rpc/auth_uid_by_email'), ...find(spans, 'POST /rest/v1/rpc/fn_registered_locale')];
  assertEquals(wave.length, 6, 'role x2, sanctions x2, auth user, language: ' + spans.map((s) => s.what).join(', '));
  for (const a of wave) for (const b of wave) assert(overlap(a, b), `${a.what} and ${b.what} ran one after the other`);
  const check = find(spans, 'POST /rest/v1/rpc/fn_login_otp_email_verify')[0];
  for (const a of wave) assert(a.start >= check.end, a.what + ' was read before the code was proved');
});

Deno.test('verify: the supplier\'s leads update runs beside the session\'s auth calls, and the answer still says has_company', async () => {
  const { stub, spans } = world();
  const r = await invoke(await fn(), stub, verify('qd-speed-b@example.invalid'));
  assertEquals(r.status, 200, JSON.stringify(r.json));
  assertEquals(r.json.has_company, false, 'the update touched no claimed lead in this stub');
  const patch = find(spans, 'PATCH /rest/v1/leads')[0], link = find(spans, 'POST /auth/v1/admin/generate_link')[0];
  assert(patch && link, spans.map((s) => s.what).join(', '));
  assert(overlap(patch, link), 'the session waited for the leads update (or the reverse)');
});

Deno.test('verify: a returning account waits on 6 round trips (was 10, 11 on a cold isolate), a new one on 7 (was 11-12)', async () => {
  for (const [uid, most] of [['uid-existing', 6], [null, 7]] as const) {
    const { stub, spans } = world({ uid });
    const r = await invoke(await fn(), stub, verify('qd-speed-c@example.invalid'));
    assertEquals(r.status, 200, JSON.stringify(r.json));
    if (uid === null) assertEquals(find(spans, 'POST /auth/v1/admin/users').length, 1, 'a new account is created once');
    const n = chain(spans);
    assert(n <= most, `${uid ? 'returning' : 'new'} account: ${n} calls in a row (at most ${most}): ` + spans.map((s) => s.what).join(' > '));
  }
});

Deno.test('verify: a customer sign-in has the same shape (customers write beside the session)', async () => {
  const { stub, spans } = world({ leads: [] });
  const r = await invoke(await fn(), stub, verify('qd-speed-d@example.invalid', 'customer'));
  assertEquals(r.status, 200, JSON.stringify(r.json));
  const write = find(spans, 'PATCH /rest/v1/customers')[0], link = find(spans, 'POST /auth/v1/admin/generate_link')[0];
  assert(write && link && overlap(write, link), spans.map((s) => s.what).join(', '));
  assert(chain(spans) <= 7, 'customer chain ' + chain(spans));
});

Deno.test('limiters stay serial: a capped IP never reaches the address\'s bucket, the code check or any read', async () => {
  const { stub, spans } = world({ ipCapped: true });
  const r = await invoke(await fn(), stub, verify('qd-speed-e@example.invalid'));
  assertEquals([r.status, r.json.code], [429, 'too_many_attempts']);
  assertEquals(find(spans, 'POST /rest/v1/rpc/rl_check login_otp_verify_email').length, 0, 'the address bucket was spent by a capped IP');
  assertEquals(find(spans, 'POST /rest/v1/rpc/fn_login_otp_email_verify').length, 0);
  assert(!spans.some((s) => /leads|customers|sanctions_ban|auth_uid_by_email|\/auth\//.test(s.what)), spans.map((s) => s.what).join(', '));
});

Deno.test('sanctioned: the reads ran together, and still no auth user, no link and no session', async () => {
  for (const uid of ['uid-existing', null]) {
    const { stub, spans } = world({ sanctioned: true, uid });
    const r = await invoke(await fn(), stub, verify('qd-speed-f@example.invalid'));
    assertEquals([r.status, r.json.code], [403, 'account_sanctioned'], JSON.stringify(r.json));
    assert(!spans.some((s) => s.what.includes('/auth/v1/')), 'a sanctioned party reached the auth server: ' + spans.map((s) => s.what).join(', '));
    assert(!('access_token' in r.json));
  }
});

Deno.test('sanctions unreadable: the sign-in is refused (fails closed), with no link and no session', async () => {
  const { stub, spans } = world({ sanctioned: 'unreadable' });
  const r = await invoke(await fn(), stub, verify('qd-speed-g@example.invalid'));
  assertEquals([r.status, r.json.code], [500, 'session_failed'], JSON.stringify(r.json));
  assert(!spans.some((s) => s.what.includes('/auth/v1/admin/generate_link') || s.what.includes('/auth/v1/verify')));
});

Deno.test('role conflict: nothing is written and nobody is created, though the reads ran together', async () => {
  const { stub, spans } = world({ leads: [{ id: 7, claimed_by: 'x' }] });
  const r = await invoke(await fn(), stub, verify('qd-speed-h@example.invalid', 'customer'));
  assertEquals([r.status, r.json.code], [409, 'role_conflict'], JSON.stringify(r.json));
  assert(!spans.some((s) => s.what.startsWith('PATCH') || s.what === 'POST /rest/v1/customers' || s.what.includes('/auth/v1/')), spans.map((s) => s.what).join(', '));
});

Deno.test('keep-warm: x-qd-warm answers 204 and makes no call, not even the run row', async () => {
  const { stub, spans } = world();
  const r = await invokeRequest(await fn(), stub, new Request('https://fn.invalid/', { method: 'GET', headers: { 'x-qd-warm': '1' } }));
  assertEquals(r.status, 204);
  assertEquals(r.calls.length, 0, r.calls.map((c) => c.url).join(', '));
  assertEquals(spans.length, 0);
});

Deno.test('the verify run row carries its action and the ms of each stage, and no address', async () => {
  const { stub } = world();
  const email = 'qd-speed-i@example.invalid';
  const r = await invoke(await fn(), stub, verify(email));
  assertEquals(r.status, 200);
  const row = r.calls.find((c) => c.url.includes('/rest/v1/agent_runs') && c.body.includes('"fn:login_otp"'));
  assert(row, 'no fn:login_otp run row');
  const counts = JSON.parse(row.body).counts;
  assertEquals(counts.action, 'verify');
  assertEquals(Object.keys(counts.steps).sort(), ['check', 'limit', 'reads', 'session']);
  for (const v of Object.values(counts.steps)) assert(typeof v === 'number' && v >= 0);
  assert(counts.steps.session >= D, 'the session stage measured nothing: ' + JSON.stringify(counts.steps));
  assert(!JSON.stringify(counts).includes(email), 'the run row carries the address');
  // An action the caller invented is not copied onto the row.
  const odd = await invoke(await fn(), stub, { action: '<script>', identifier: email });
  const oddRow = odd.calls.find((c) => c.url.includes('/rest/v1/agent_runs') && c.body.includes('"fn:login_otp"'));
  assert(oddRow && !('action' in JSON.parse(oddRow.body).counts), oddRow?.body);
});
