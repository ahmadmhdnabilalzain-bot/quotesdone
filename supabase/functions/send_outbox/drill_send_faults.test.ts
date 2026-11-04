// deno test supabase/functions/send_outbox/drill_send_faults.test.ts
// FAILURE-INJECTION DRILLS FOR THE OUTBOX SENDER (it_engineer, 3 Nov 2026; docs/release/qualification_matrix.md §5.1
// D3 "Resend 5xx / timeout", D6 "M365 down", D10 "connection exhaustion / no lost writes", and F09.03). customer_support
// is the only seat that sends a notification; this file proves what that sender does when what it depends on breaks.
//
// WHAT IS DRILLED. The REAL send_outbox handler (index.ts, through its Deno.serve and observe() wrapper) runs against a
// stateful fake of the four things it talks to, each of which can be told to fail:
//   the database  PostgREST + fn_notifications_claim, modelled on scripts/sql/a_queued_notification_is_claimed_before_
//                 it_is_sent.sql (claim -> 'sending', not_before honoured, a claim older than 5 minutes requeued);
//   Resend        POST /emails, deduplicating on Idempotency-Key the way Resend documents it (a repeat of an accepted
//                 key returns the first answer and delivers nothing new);
//   Graph         login.microsoftonline.com token + graph.microsoft.com sendMail; Graph has NO idempotency, so every
//                 accepted POST is one more email in a supplier's inbox;
//   the clock     "time passes" between ticks by moving the fake database's now() forward.
// Each drill counts EMAILS DELIVERED (what a person would receive), not requests, so "never sent twice" is measured
// where it matters.
//
// DEMO SAFETY. No drill can reach a real network or a real person: fetch is replaced before the module loads, any host
// that is not one of the stubs is refused (and counted: every drill asserts zero), and the suite grants --allow-net to
// 127.0.0.1 only, which drill DEMO.2 asserts from Deno's own permission state. An @example.invalid recipient never
// reaches a provider at all (index.ts RESERVED_TEST_DOMAIN skips it; DEMO.1), so the send-path drills use an address on
// our own domain, which only the stubs ever see.
//
// THE KNOWN-BAD CONTROLS. D3.0 and D6.0 are healthy sends recorded 'sent' exactly once with the provider's id: a green
// below cannot come from a harness that sees nothing, because these prove the stubs see the send. Every refusal drill
// also asserts the request DID reach the stubbed provider, so a refusal that was never exercised cannot pass as handled.
//
// WHAT THESE DRILLS FOUND (before/after: /tmp/claude-0/drills/outbox/before.txt, after.txt), fixed in index.ts:
//   1. A transient refusal (5xx, 429) was requeued with no later attempt time: the next 2-minute poll retried it, so a
//      Resend outage of about four minutes dead-lettered every message in the queue (3 attempts, 2 minutes apart).
//   2. A permanent refusal (422 invalid recipient) was retried twice more before it failed.
//   3. A Resend POST that timed out was never retried, although it carries an Idempotency-Key that makes the retry safe:
//      a message Resend never received was lost (sent-unconfirmed) instead of "exactly once after recovery".
//   4. A Graph sendMail that was ACCEPTED and whose 'sent' write then failed went back on the queue (the finally's
//      release, or the claim's 5-minute expiry) and was sent AGAIN on the next tick: two emails to one supplier.
import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';

// ------------------------------------------------------------------------------------------------ the fake world
// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;
type Fault = 'ok' | 'hang' | 'accept_then_hang' | Response | 'throw';
type World = {
  notifications: Row[];
  suppressions: { email: string; reason: string }[];
  secrets: Record<string, string>;
  skewMs: number;                                   // the database's now() runs this far ahead: time between ticks
  runs: Row[];                                      // agent_runs inserts (logRun + observe)
  findingsFiled: Row[]; findingsClosed: Row[];      // fn_it_engineer_finding_upsert / _close
  resendPosts: { key: string | null; to: string }[]; resendDelivered: { key: string | null; id: string; to: string }[];
  resendCache: Map<string, { status: number; body: string }>;
  graphPosts: number; graphDelivered: string[];     // MIME of each accepted sendMail
  tokenPosts: number;
  realNetwork: string[];                            // any host that is not a stub: must stay empty
  resend: (n: number) => Fault;                     // n = 1-based POST number to Resend in this test
  graph: (n: number) => Fault;
  token: (n: number) => Fault;
  claim: (n: number) => Fault;                      // fn_notifications_claim
  // A database write to fail: return a Response (e.g. 500) to refuse it; undefined lets it through.
  write: (method: string, table: string, params: URLSearchParams, body: Row | null) => Response | undefined;
};
const J = (o: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json', ...headers } });
const SECRET = 'drill-internal-secret-0123456789abcdef';
const TO = 'outbox-drill@quotesdone.com';          // our own domain; only the stubs below ever see it
const BASE_SECRETS: Record<string, string> = {
  email_enabled: 'true', resend_api_key: 're_drill_0123456789abcdef', supplier_emails_enabled: 'true',
  unsubscribe_signing_key: 'drill-unsub-key-0123456789abcdef', daily_send_cap: '80',
};
const M365_ON = { invite_m365_enabled: 'true', invite_m365_mailbox: 'supplier@quotesdone.com' };
let W: World;
let nextId = 9_000_000;
function fresh(secrets: Record<string, string> = {}): World {
  W = {
    notifications: [], suppressions: [], secrets: { ...BASE_SECRETS, ...secrets }, skewMs: 0, runs: [], findingsFiled: [], findingsClosed: [],
    resendPosts: [], resendDelivered: [], resendCache: new Map(), graphPosts: 0, graphDelivered: [], tokenPosts: 0, realNetwork: [],
    resend: () => 'ok', graph: () => 'ok', token: () => 'ok', claim: () => 'ok', write: () => undefined,
  };
  return W;
}
const dbNow = () => Date.now() + W.skewMs;
function queue(over: Row = {}): Row {
  const r: Row = { id: ++nextId, channel: 'email', status: 'queued', type: 'quote_received', to_role: 'customer', to_email: TO, lang: 'en',
    subject: 'Your quote is ready', body: 'A supplier has sent a quote for your request.', attempts: 0, created_at: new Date().toISOString(),
    not_before: null, claimed_at: null, last_error: null, provider_message_id: null, sent_at: null, kind: null, lead_id: null, ...over };
  W.notifications.push(r);
  return r;
}
const invite = (over: Row = {}) => queue({ type: 'supplier_invite', to_role: 'supplier', subject: 'A question about your work in the UAE',
  body: 'Dear Drill Trading,\n\nWe are building our supplier list.', ...over });

// A request that never answers: it rejects only when timedFetch's deadline aborts it, exactly as a hung provider does.
const hang = (signal: AbortSignal | null | undefined) => new Promise<Response>((_, rej) => {
  if (!signal) return;                             // no deadline: would hang for ever (no drill reaches this)
  if (signal.aborted) return rej(signal.reason);
  signal.addEventListener('abort', () => rej(signal.reason));
});

// PostgREST filters: eq, neq, in, gte, lte, gt, lt, like, is; "counts->>signal" reads into jsonb.
function val(row: Row, key: string) { const [c, j] = key.split('->>'); return j ? row[c]?.[j] : row[c]; }
function rowMatches(row: Row, params: URLSearchParams): boolean {
  for (const [k, raw] of params) {
    if (['select', 'order', 'limit', 'offset', 'columns', 'or'].includes(k)) continue;
    const dot = raw.indexOf('.'); const op = raw.slice(0, dot); const v = raw.slice(dot + 1); const x = val(row, k);
    if (op === 'eq' && String(x) !== v) return false;
    if (op === 'neq' && String(x) === v) return false;
    if (op === 'in' && !v.replace(/^\(|\)$/g, '').split(',').map((s) => s.replace(/^"|"$/g, '')).includes(String(x))) return false;
    if (op === 'is' && !(v === 'null' ? x == null : String(x) === v)) return false;
    if (op === 'like' && !(x != null && new RegExp('^' + v.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$').test(String(x)))) return false;
    if (['gte', 'lte', 'gt', 'lt'].includes(op)) {
      if (x == null) return false;
      const a = Date.parse(String(x)), b = Date.parse(v);
      const [l, r] = Number.isFinite(a) && Number.isFinite(b) ? [a, b] : [Number(x), Number(v)];
      if (op === 'gte' && !(l >= r)) return false; if (op === 'lte' && !(l <= r)) return false;
      if (op === 'gt' && !(l > r)) return false; if (op === 'lt' && !(l < r)) return false;
    }
  }
  return true;
}

// fn_notifications_claim, as scripts/sql/a_queued_notification_is_claimed_before_it_is_sent.sql writes it.
function claim(limit: number): Row[] {
  const now = dbNow();
  for (const n of W.notifications) {
    if (n.status === 'sending' && (n.claimed_at == null || Date.parse(n.claimed_at) < now - 5 * 60_000)) {
      n.last_error = n.claimed_at == null ? 'status was sending with no claimed_at, which is not a claim; requeued'
                                          : 'a send claim expired after 5 minutes without an outcome; requeued';
      n.status = 'queued'; n.claimed_at = null;
    }
  }
  const due = W.notifications
    .filter((c) => (c.status === 'queued' || c.status === 'pending' || c.status == null) && (c.channel == null || !['sms', 'whatsapp'].includes(c.channel)) &&
      (c.not_before == null || Date.parse(c.not_before) <= now))
    .sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at)).slice(0, Math.max(1, Math.min(limit || 25, 200)));
  for (const c of due) { c.status = 'sending'; c.claimed_at = new Date(now).toISOString(); }
  return due.map((c) => ({ ...c }));
}

let claimCalls = 0;
async function answer(req: Request, u: URL): Promise<Response> {
  const host = u.hostname;
  if (host === 'api.resend.com' && u.pathname === '/emails' && req.method === 'POST') {
    const key = req.headers.get('idempotency-key');
    const mail = JSON.parse(await req.text());
    W.resendPosts.push({ key, to: String(mail.to) });
    // Resend's documented dedupe: an accepted key answers with its first response and sends nothing new.
    const cached = key ? W.resendCache.get(key) : undefined;
    if (cached) return new Response(cached.body, { status: cached.status, headers: { 'content-type': 'application/json' } });
    const f = W.resend(W.resendPosts.length);
    const accept = () => {
      const id = 're_drill_' + (W.resendDelivered.length + 1);
      W.resendDelivered.push({ key, id, to: String(mail.to) });
      const body = JSON.stringify({ id });
      if (key) W.resendCache.set(key, { status: 200, body });
      return new Response(body, { status: 200, headers: { 'content-type': 'application/json' } });
    };
    if (f === 'ok') return accept();
    if (f === 'hang') return hang(req.signal);
    if (f === 'accept_then_hang') { accept(); return hang(req.signal); }
    if (f === 'throw') throw new TypeError('error sending request: connection reset');
    return f.clone();
  }
  if (host === 'api.resend.com') return J({ data: [] });   // a GET /domains if the invitation lane is ever switched on
  if (host === 'login.microsoftonline.com') {
    W.tokenPosts++;
    const f = W.token(W.tokenPosts);
    if (f === 'ok') return J({ access_token: 'drill-token-' + W.tokenPosts, token_type: 'Bearer', expires_in: 3599 });
    if (f === 'hang' || f === 'accept_then_hang') return hang(req.signal);
    if (f === 'throw') throw new TypeError('error sending request: dns error');
    return f.clone();
  }
  if (host === 'graph.microsoft.com') {
    W.graphPosts++;
    const mime = await req.text();
    const f = W.graph(W.graphPosts);
    if (f === 'ok') { W.graphDelivered.push(mime); return new Response(null, { status: 202 }); }
    if (f === 'hang') return hang(req.signal);
    if (f === 'accept_then_hang') { W.graphDelivered.push(mime); return hang(req.signal); }
    if (f === 'throw') throw new TypeError('error sending request: connection reset');
    return f.clone();
  }
  if (host !== 'db.invalid') { W.realNetwork.push(req.url); throw new Error('drill: a real network call was refused: ' + host); }

  // ---- the database
  const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1];
  const body: Row | null = req.method === 'GET' || req.method === 'HEAD' ? null : await req.json().catch(() => null);
  if (rpc === 'fn_internal_auth') return J(body?.p_secret === SECRET ? { ok: true, context: 'drill', credential_id: 1, legacy: false } : { ok: false });
  if (rpc === 'fn_notifications_claim') {
    const f = W.claim(++claimCalls);
    if (f === 'throw') throw new TypeError('error sending request: connection refused');
    if (f instanceof Response) return f.clone();
    return J(claim(Number(body?.p_limit)));
  }
  if (rpc === 'fn_it_engineer_finding_upsert') { W.findingsFiled.push(body || {}); return J(1); }
  if (rpc === 'fn_it_engineer_finding_close') { W.findingsClosed.push(body || {}); return J(true); }
  if (rpc) return J(null);
  const table = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1] ?? '';
  const injected = W.write(req.method, table, u.searchParams, body);
  if (injected) return injected.clone();
  const wantsObject = (req.headers.get('accept') || '').includes('vnd.pgrst.object');
  const list = (rows: Row[]) => (wantsObject ? (rows.length ? J(rows[0]) : J({ code: 'PGRST116', message: 'no rows' }, 406)) : J(rows));
  if (table === 'app_secrets') {
    const keyIn = u.searchParams.get('key') || '';
    const keys = keyIn.startsWith('in.') ? keyIn.slice(3).replace(/^\(|\)$/g, '').split(',') : [keyIn.replace(/^eq\./, '')];
    return list(keys.filter((k) => k in W.secrets).map((k) => ({ key: k, value: W.secrets[k] })));
  }
  if (table === 'notifications') {
    if (req.method === 'HEAD' || req.method === 'GET') {
      const rows = W.notifications.filter((r) => rowMatches(r, u.searchParams));
      return req.method === 'HEAD' ? new Response(null, { status: 200, headers: { 'content-range': '*/' + rows.length } }) : list(rows.map((r) => ({ ...r })));
    }
    if (req.method === 'PATCH') { for (const r of W.notifications.filter((r) => rowMatches(r, u.searchParams))) Object.assign(r, body); return new Response(null, { status: 204 }); }
  }
  if (table === 'email_suppressions') return list(W.suppressions.filter((s) => rowMatches(s, u.searchParams)));
  if (table === 'agent_runs' && req.method === 'POST') { for (const r of (Array.isArray(body) ? body : [body])) W.runs.push(r || {}); return new Response(null, { status: 201 }); }
  if (req.method === 'GET') return list([]);
  if (req.method === 'HEAD') return new Response(null, { status: 200, headers: { 'content-range': '*/0' } });
  return new Response(null, { status: req.method === 'POST' ? 201 : 204 });
}

// ------------------------------------------------------------------------------------------------ install + load
// Deno.env, fetch, Deno.serve and the deadline are replaced BEFORE index.ts is imported: supabase-js captures fetch
// when the module creates its client. timedFetch's own deadline (15 s to Resend and Graph, 10 s to the token) is cut to
// 60 ms so a hung provider is drilled through the real AbortSignal path in milliseconds.
const ENV: Record<string, string> = { SUPABASE_URL: 'https://db.invalid', SUPABASE_SERVICE_ROLE_KEY: 'stub-service-role',
  MS_TENANT_ID: 'drill-tenant', MS_CLIENT_ID: 'drill-client-id', MS_CLIENT_SECRET: 'drill-client-secret-value' };
(Deno.env as unknown as { get: (k: string) => string | undefined }).get = (k) => ENV[k];
globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
  const req = input instanceof Request ? input : new Request(String(input), init);
  return await answer(req, new URL(req.url));
}) as typeof fetch;
const realTimeout = AbortSignal.timeout.bind(AbortSignal);
(AbortSignal as unknown as { timeout: (ms: number) => AbortSignal }).timeout = (ms: number) => realTimeout(Math.min(ms, 60));
let handler: ((req: Request) => Promise<Response>) | undefined;
(Deno as unknown as { serve: unknown }).serve = (a: unknown, b?: unknown) => {
  handler = (typeof a === 'function' ? a : b) as typeof handler;
  return { finished: Promise.resolve(), shutdown: () => Promise.resolve(), ref() {}, unref() {} };
};
await import('./index.ts');
if (!handler) throw new Error('send_outbox did not call Deno.serve');

/** One run of send_outbox, as email_cron / the 2-minute poll calls it. */
async function tick(): Promise<Row> {
  const res = await handler!(new Request('https://fn.invalid/send_outbox', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ __secret: SECRET }) }));
  const json = await res.json();
  await new Promise((r) => setTimeout(r, 90));     // the deadlines and observe()'s background write settle
  return json;
}
/** Time passes: the database's now() moves on, so a row whose not_before was set is due. */
const advance = (minutes: number) => { W.skewMs += minutes * 60_000; };
const row = (id: number) => W.notifications.find((r) => r.id === id)!;
const laterThan = (iso: string | null, ms: number) => iso != null && Date.parse(iso) >= Date.now() + ms - 2_000;
const runNote = (status: string) => W.runs.filter((r) => r.agent === 'send_outbox' && r.status === status).map((r) => String(r.note)).join(' | ');
const sendMails = () => W.resendDelivered.length + W.graphDelivered.length;
const opts = { sanitizeOps: false, sanitizeResources: false };   // a provider aborted by its deadline leaves its timer behind

// ------------------------------------------------------------------------------------------------ D3: Resend
Deno.test({ name: 'D3.0 positive control: a healthy send reaches Resend once, with its Idempotency-Key, and is recorded sent with the provider id', ...opts, fn: async () => {
  fresh(); const n = queue();
  const out = await tick();
  assertEquals(out.sent, 1, JSON.stringify(out));
  assertEquals(W.resendPosts.length, 1); assertEquals(W.resendDelivered.length, 1);
  assertEquals(W.resendPosts[0].key, 'qd-notif-' + n.id, 'the Idempotency-Key is the notification id');
  assertEquals(row(n.id).status, 'sent'); assertEquals(row(n.id).provider_message_id, 're_drill_1');
  assert(W.runs.some((r) => r.agent === 'send_outbox' && r.status === 'ok' && r.counts?.sent === 1), 'the run is logged ok with sent 1');
  advance(60); await tick();
  assertEquals(W.resendPosts.length, 1, 'a sent row is never claimed again');
  assertEquals(W.realNetwork, []);
} });

for (const status of [500, 502, 503]) {
  Deno.test({ name: `D3.1 Resend ${status}: retried later with the reason on the row, then delivered exactly once after recovery`, ...opts, fn: async () => {
    fresh(); const n = queue();
    W.resend = (k) => (k === 1 ? J({ name: 'application_error', message: 'drill: injected ' + status }, status) : 'ok');
    await tick();
    const r = row(n.id);
    assertEquals(W.resendPosts.length, 1, 'the refusal was exercised against the stub');
    assertEquals(r.status, 'queued', 'a transient refusal goes back on the queue');
    assertEquals(r.attempts, 1);
    assert(String(r.last_error).includes('HTTP ' + status) && /injected/.test(r.last_error), 'the reason names the HTTP status and the provider\'s answer: ' + r.last_error);
    assert(laterThan(r.not_before, 60_000), 'a later attempt time is set, so the next 2-minute poll does not burn an attempt: not_before=' + r.not_before);
    assert(/will retry/.test(runNote('error')), 'agent_runs carries the error for the watchers: ' + runNote('error'));
    await tick();                                   // the next poll, before not_before: nothing sent
    assertEquals(W.resendPosts.length, 1, 'the row was retried before its attempt time');
    advance(30); await tick();
    assertEquals(row(n.id).status, 'sent'); assertEquals(W.resendDelivered.length, 1, 'exactly one email after recovery');
    advance(60); await tick();
    assertEquals(W.resendDelivered.length, 1); assertEquals(new Set(W.resendPosts.map((p) => p.key)).size, 1);
  } });
}

Deno.test({ name: 'D3.2 Resend 429 with Retry-After: queued, not before the provider said, with the reason', ...opts, fn: async () => {
  fresh(); const n = queue();
  W.resend = (k) => (k === 1 ? J({ name: 'rate_limit_exceeded', message: 'Too many requests' }, 429, { 'retry-after': '900' }) : 'ok');
  await tick();
  const r = row(n.id);
  assertEquals(r.status, 'queued'); assertEquals(r.attempts, 1);
  assert(/HTTP 429/.test(r.last_error) && /Too many requests/.test(r.last_error), r.last_error);
  assert(laterThan(r.not_before, 900_000), 'Retry-After (900 s) is honoured: not_before=' + r.not_before);
  advance(16); await tick();
  assertEquals(row(n.id).status, 'sent'); assertEquals(W.resendDelivered.length, 1);
} });

Deno.test({ name: 'D3.3 Resend down for good: three attempts, then failed (dead-lettered, logged), and never a fourth', ...opts, fn: async () => {
  fresh(); const n = queue();
  W.resend = () => J({ name: 'application_error', message: 'drill: still down' }, 503);
  for (let i = 0; i < 3; i++) { await tick(); advance(90); }
  const r = row(n.id);
  assertEquals(W.resendPosts.length, 3, 'three attempts');
  assertEquals(r.status, 'failed'); assertEquals(r.attempts, 3);
  assert(/still down/.test(r.last_error), r.last_error);
  assert(/dead-lettered after 3 attempts/.test(runNote('error')), 'the dead letter is logged as an error: ' + runNote('error'));
  W.resend = () => 'ok';
  advance(600); await tick();
  assertEquals(W.resendPosts.length, 3, 'the ceiling holds after the provider recovers'); assertEquals(sendMails(), 0);
} });

Deno.test({ name: 'D3.4 Resend 422 invalid recipient: a permanent refusal fails at once with the reason, never retried', ...opts, fn: async () => {
  fresh(); const n = queue();
  W.resend = () => J({ statusCode: 422, name: 'validation_error', message: 'Invalid `to` field.' }, 422);
  await tick();
  const r = row(n.id);
  assertEquals(W.resendPosts.length, 1);
  assertEquals(r.status, 'failed', 'a 422 cannot succeed on a retry');
  assert(/HTTP 422/.test(r.last_error) && /Invalid `to` field/.test(r.last_error), r.last_error);
  assert(runNote('error').length > 0, 'the failure is logged for the watchers');
  advance(600); await tick(); advance(600); await tick();
  assertEquals(W.resendPosts.length, 1, 'a permanent refusal is not retried');
} });

Deno.test({ name: 'D3.5 Resend never answers (timeout, nothing accepted): retried under the same Idempotency-Key, delivered exactly once after recovery', ...opts, fn: async () => {
  fresh(); const n = queue();
  W.resend = (k) => (k === 1 ? 'hang' : 'ok');
  const out = await tick();
  assertEquals(W.resendPosts.length, 1); assertEquals(W.resendDelivered.length, 0, 'the hung POST delivered nothing');
  const r = row(n.id);
  assert(/did not return/.test(r.last_error), 'the reason says the POST did not return: ' + r.last_error + ' ' + JSON.stringify(out));
  advance(30); await tick();
  assertEquals(W.resendDelivered.length, 1, 'the message Resend never received is delivered after recovery, not lost');
  assertEquals(row(n.id).status, 'sent'); assertEquals(row(n.id).provider_message_id, 're_drill_1');
  assertEquals(new Set(W.resendPosts.map((p) => p.key)), new Set(['qd-notif-' + n.id]), 'every attempt carried the one key');
} });

Deno.test({ name: 'D3.6 Resend accepts but the answer never comes back: one email, never two', ...opts, fn: async () => {
  fresh(); const n = queue();
  W.resend = (k) => (k === 1 ? 'accept_then_hang' : 'ok');
  await tick();
  assertEquals(W.resendDelivered.length, 1, 'Resend accepted the first POST');
  for (let i = 0; i < 4; i++) { advance(30); await tick(); }
  assertEquals(W.resendDelivered.length, 1, 'a retry after an unheard acceptance must not deliver a second email');
  assert(W.resendPosts.every((p) => p.key === 'qd-notif-' + n.id), 'every POST carried the Idempotency-Key');
  const r = row(n.id);
  assertEquals(r.status, 'sent');
  assert(r.provider_message_id === 're_drill_1' || (r.provider_message_id == null && /did not return/.test(r.last_error)),
    'sent with the provider id, or visibly sent-unconfirmed: ' + JSON.stringify({ id: r.provider_message_id, e: r.last_error }));
} });

Deno.test({ name: 'D3.7 Resend hangs on every attempt: at most three POSTs, then sent-unconfirmed with the reason, never a fourth', ...opts, fn: async () => {
  fresh(); const n = queue();
  W.resend = () => 'hang';
  for (let i = 0; i < 5; i++) { await tick(); advance(30); }
  const r = row(n.id);
  assert(W.resendPosts.length >= 1 && W.resendPosts.length <= 3, 'attempts: ' + W.resendPosts.length);
  assertEquals(r.status, 'sent'); assertEquals(r.provider_message_id, null);
  assert(/did not return/.test(r.last_error) && /NOT be sent again/.test(r.last_error), r.last_error);
  const before = W.resendPosts.length; W.resend = () => 'ok'; advance(600); await tick();
  assertEquals(W.resendPosts.length, before, 'a sent-unconfirmed row is never sent again');
} });

Deno.test({ name: 'D3.8 two overlapping runs (cron + resilience tick): one claim, one POST, one email', ...opts, fn: async () => {
  fresh(); const n = queue();
  await Promise.all([tick(), tick()]);
  assertEquals(W.resendPosts.length, 1, 'a row is sent only by the run that claimed it');
  assertEquals(W.resendDelivered.length, 1); assertEquals(row(n.id).status, 'sent');
} });

// ------------------------------------------------------------------------------------------------ D3: demo safety
Deno.test({ name: 'D3 DEMO.1 an @example.invalid recipient never reaches a provider, on either lane: skipped with its reason', ...opts, fn: async () => {
  fresh(M365_ON);
  const a = queue({ to_email: 'zz-demo-buyer@example.invalid' });
  const b = invite({ to_email: 'ZZ-Demo-Supplier@Example.Invalid' });
  await tick();
  assertEquals(W.resendPosts.length, 0); assertEquals(W.graphPosts, 0); assertEquals(sendMails(), 0);
  for (const id of [a.id, b.id]) { assertEquals(row(id).status, 'skipped'); assert(/RFC 2606/.test(row(id).last_error), row(id).last_error); }
} });

Deno.test({ name: 'D3 DEMO.2 the drill cannot reach a real network: no stub-less host was asked, and Deno grants no net beyond 127.0.0.1', ...opts, fn: async () => {
  for (const host of ['api.resend.com', 'graph.microsoft.com', 'login.microsoftonline.com']) {
    const { state } = await Deno.permissions.query({ name: 'net', host });
    assertFalse(state === 'granted', host + ' is reachable from this test process');
  }
  fresh(); queue(); await tick();
  assertEquals(W.realNetwork, []);
} });

// ------------------------------------------------------------------------------------------------ D10: the database
Deno.test({ name: 'D10.1 the claim RPC answers 500: nothing sent, the failure logged, the row untouched; the next tick sends it once', ...opts, fn: async () => {
  fresh(); const n = queue();
  W.claim = (k) => (k === 1 ? J({ code: '57014', message: 'canceling statement due to statement timeout' }, 500) : 'ok');
  claimCalls = 0;
  const out = await tick();
  assertEquals(out.ok, false); assertEquals(W.resendPosts.length, 0);
  assert(/could not claim the outbox queue/.test(runNote('error')) && /statement timeout/.test(runNote('error')), runNote('error'));
  assertEquals(row(n.id).status, 'queued'); assertEquals(row(n.id).attempts, 0, 'a database fault is not the message\'s attempt');
  await tick();
  assertEquals(row(n.id).status, 'sent'); assertEquals(W.resendDelivered.length, 1);
} });

Deno.test({ name: 'D10.2 the database connection drops during the claim: nothing sent, logged; recovers on the next tick', ...opts, fn: async () => {
  fresh(); const n = queue();
  claimCalls = 0; W.claim = (k) => (k === 1 ? 'throw' : 'ok');
  await tick();
  assertEquals(W.resendPosts.length, 0); assert(/could not claim/.test(runNote('error')), runNote('error'));
  await tick();
  assertEquals(row(n.id).status, 'sent'); assertEquals(W.resendDelivered.length, 1);
} });

Deno.test({ name: 'D10.3 Resend accepted but the "sent" write failed: the retry is absorbed by the Idempotency-Key, one email', ...opts, fn: async () => {
  fresh(); const n = queue();
  let failed = 0;
  W.write = (m, t, _p, b) => (m === 'PATCH' && t === 'notifications' && b?.status === 'sent' && failed++ === 0 ? J({ code: '57014', message: 'statement timeout' }, 500) : undefined);
  await tick();
  assertEquals(W.resendDelivered.length, 1);
  for (let i = 0; i < 3; i++) { advance(30); await tick(); }
  assertEquals(W.resendDelivered.length, 1, 'one email, whatever the bookkeeping did');
  assertEquals(row(n.id).status, 'sent', 'the row ends sent');
  assert(W.resendPosts.length <= 2 && W.resendPosts.every((p) => p.key === 'qd-notif-' + n.id), JSON.stringify(W.resendPosts));
} });

// ------------------------------------------------------------------------------------------------ D6: Microsoft 365
Deno.test({ name: 'D6.0 positive control: a lane invitation is sent once through Graph, recorded sent with its m365: id, and never through Resend', ...opts, fn: async () => {
  fresh(M365_ON); const n = invite();
  const out = await tick();
  assertEquals(W.tokenPosts, 1); assertEquals(W.graphPosts, 1); assertEquals(W.graphDelivered.length, 1, JSON.stringify(out));
  assertEquals(W.resendPosts.length, 0);
  assertEquals(row(n.id).status, 'sent'); assert(String(row(n.id).provider_message_id).startsWith('m365:<qd-notif-' + n.id + '.'), row(n.id).provider_message_id);
  assertEquals(W.findingsClosed.length, 1, 'a 2xx sendMail closes the refusal finding');
  advance(60); await tick();
  assertEquals(W.graphPosts, 1);
} });

const graphRefusals: [string, () => Response][] = [
  ['401 token expired', () => J({ error: { code: 'InvalidAuthenticationToken', message: 'Lifetime validation failed, the token is expired.' } }, 401)],
  ['403 forbidden', () => J({ error: { code: 'ErrorAccessDenied', message: 'Access is denied.' } }, 403)],
  ['429 with Retry-After', () => J({ error: { code: 'ApplicationThrottled', message: 'Application is over its MailboxConcurrency limit.' } }, 429, { 'retry-after': '120' })],
  ['503 unavailable', () => J({ error: { code: 'ServiceUnavailable', message: 'Service Unavailable' } }, 503)],
];
for (const [label, refusal] of graphRefusals) {
  Deno.test({ name: `D6.1 Graph sendMail ${label}: held with the reason and one it_engineer finding, never via Resend; a new token sends it once`, ...opts, fn: async () => {
    fresh(M365_ON); const n = invite();
    W.graph = (k) => (k === 1 ? refusal() : 'ok');
    await tick();
    const r = row(n.id);
    assertEquals(W.graphPosts, 1, 'the refusal was exercised'); assertEquals(W.graphDelivered.length, 0); assertEquals(W.resendPosts.length, 0, 'never diverted to Resend');
    assertEquals(r.status, 'queued');
    assert(r.last_error.includes(label.slice(0, 3)) && /never sent through Resend/.test(r.last_error), r.last_error);
    assert(laterThan(r.not_before, 120_000), 'held past any Retry-After: ' + r.not_before);
    assertEquals(W.findingsFiled.map((f) => f.p_issue_key), ['invite_m365_lane_refused'], 'one finding for the it_engineer seat');
    assertFalse(JSON.stringify(W.findingsFiled).includes('drill-client-secret-value'), 'no secret in the finding');
    await tick();
    assertEquals(W.graphPosts, 1, 'not retried before its hold ends');
    advance(31); await tick();
    // tick 1 asked for a token; tick 2 claimed nothing (the row was held) and asked for none; tick 3 asked afresh.
    assertEquals(W.tokenPosts, 2, 'every run that carries a lane row asks for a fresh token: an expired one recovers with no manual step');
    assertEquals(W.graphDelivered.length, 1, 'delivered once after recovery'); assertEquals(row(n.id).status, 'sent');
    assertEquals(W.findingsClosed.length, 1, 'the finding closes on the first accepted send');
    advance(60); await tick(); assertEquals(W.graphDelivered.length, 1);
  } });
}

for (const [label, fault] of [['refused (401 invalid_client)', () => J({ error: 'invalid_client', error_description: 'AADSTS7000215: Invalid client secret provided.' }, 401)], ['timed out', () => 'hang' as const]] as const) {
  Deno.test({ name: `D6.2 the Microsoft token endpoint ${label}: held, one finding, no sendMail and no Resend; recovers by itself`, ...opts, fn: async () => {
    fresh(M365_ON); const n = invite();
    W.token = (k) => (k === 1 ? fault() : 'ok');
    await tick();
    assertEquals(W.tokenPosts, 1); assertEquals(W.graphPosts, 0); assertEquals(W.resendPosts.length, 0);
    assertEquals(row(n.id).status, 'queued'); assert(/never sent through Resend/.test(row(n.id).last_error), row(n.id).last_error);
    assertEquals(W.findingsFiled.length, 1);
    assertFalse(JSON.stringify(W.findingsFiled).includes('drill-client-secret-value'));
    advance(31); await tick();
    assertEquals(W.graphDelivered.length, 1); assertEquals(row(n.id).status, 'sent');
  } });
}

Deno.test({ name: 'D6.3 Graph sendMail times out: sent-unconfirmed with the reason, never posted to Graph again (Graph has no idempotency)', ...opts, fn: async () => {
  fresh(M365_ON); const n = invite();
  W.graph = (k) => (k === 1 ? 'accept_then_hang' : 'ok');
  await tick();
  const r = row(n.id);
  assertEquals(r.status, 'sent'); assertEquals(r.provider_message_id, null);
  assert(/did not return/.test(r.last_error) && /will NOT be sent again/.test(r.last_error), r.last_error);
  for (let i = 0; i < 3; i++) { advance(60); await tick(); }
  assertEquals(W.graphPosts, 1); assertEquals(W.graphDelivered.length, 1, 'one email'); assertEquals(W.resendPosts.length, 0);
} });

Deno.test({ name: 'D6.4 / D10.4 Graph accepted but the "sent" write failed: the next tick must not send it again', ...opts, fn: async () => {
  fresh(M365_ON); const n = invite();
  let failed = 0;
  W.write = (m, t, _p, b) => (m === 'PATCH' && t === 'notifications' && b?.status === 'sent' && failed++ === 0 ? J({ code: '57014', message: 'statement timeout' }, 500) : undefined);
  await tick();
  assertEquals(W.graphDelivered.length, 1, 'Graph accepted the first sendMail');
  for (let i = 0; i < 3; i++) { advance(31); await tick(); }
  assertEquals(W.graphDelivered.length, 1, 'DUPLICATE: the supplier received ' + W.graphDelivered.length + ' copies');
  assertEquals(W.resendPosts.length, 0);
  const r = row(n.id);
  assertEquals(r.status, 'sent', 'the row ends sent, visibly');
  assert(r.last_error && /not sent again/i.test(r.last_error), 'the row says why it was not sent again: ' + r.last_error);
} });

Deno.test({ name: 'D6.5 / D10.5 Graph accepted, then the database went away (the "sent" write AND the release failed): the 5-minute claim expiry must not resend it', ...opts, fn: async () => {
  fresh(M365_ON); const n = invite();
  let down = true;
  // After the accepted sendMail every write to notifications fails for the rest of the run.
  W.write = (m, t) => (down && W.graphDelivered.length > 0 && m === 'PATCH' && t === 'notifications' ? J({ message: 'connection terminated' }, 503) : undefined);
  await tick();
  assertEquals(W.graphDelivered.length, 1);
  assertEquals(row(n.id).status, 'sending', 'the row is left claimed: nothing could be written');
  down = false;
  advance(6); await tick();                         // the claim has expired and fn_notifications_claim requeues it
  advance(31); await tick();
  assertEquals(W.graphDelivered.length, 1, 'DUPLICATE: the supplier received ' + W.graphDelivered.length + ' copies');
  assertEquals(row(n.id).status, 'sent');
} });

Deno.test({ name: 'D6.6 a mailbox reply Graph refuses goes through Resend in the same run, once; a later Graph recovery does not send it again', ...opts, fn: async () => {
  fresh(M365_ON);
  const n = queue({ type: 'inbound_reply', to_role: 'supplier', kind: 'supplier_mailbox_reply', subject: 'Re: your question', body: 'Hello,\n\nThank you.\n\nThe QuotesDone Team', in_reply_to: '<drill@mail.example>' });
  W.graph = () => J({ error: { code: 'ServiceUnavailable', message: 'down' } }, 503);
  W.resend = (k) => (k === 1 ? J({ message: 'drill: also down' }, 503) : 'ok');
  await tick();
  assertEquals(W.graphPosts, 1); assertEquals(W.resendPosts.length, 1, 'the refused reply fell through to Resend');
  assertEquals(row(n.id).status, 'queued'); assertEquals(sendMails(), 0);
  W.graph = () => 'ok';
  advance(31); await tick();
  assertEquals(sendMails(), 1, 'delivered once after recovery, by whichever lane');
  assertEquals(row(n.id).status, 'sent'); assert(row(n.id).provider_message_id, 'a confirmed send keeps its provider id: ' + JSON.stringify(row(n.id)));
  advance(60); await tick(); assertEquals(sendMails(), 1);
} });

Deno.test({ name: 'D6.7 a bounce recorded by resend_webhook / the mailbox reader stops the next send on both lanes, whatever the case', ...opts, fn: async () => {
  fresh(M365_ON);
  W.suppressions.push({ email: TO, reason: 'hard_bounce:permanent' });
  const a = invite({ to_email: 'Outbox-Drill@QuotesDone.com' });
  const b = queue({ to_email: TO.toUpperCase() });
  await tick();
  assertEquals(W.graphPosts, 0); assertEquals(W.resendPosts.length, 0);
  assertEquals(row(a.id).status, 'suppressed'); assertEquals(row(b.id).status, 'suppressed');
} });
