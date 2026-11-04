// DRILL D5 — Twilio's WhatsApp Messages API refuses, and what the queue does about it.
// Seat accountable: it_engineer (docs/release/qualification_matrix.md §5.1, D5). WhatsApp itself is customer_support's.
//
// What it drills: the REAL send_whatsapp handler, loaded through _shared/twilio_free_harness.ts with fetch and env stubbed,
// draining an in-memory notifications queue through its real door (fn_notifications_claim). The rows go to a REAL-LOOKING
// number (+971 50 123 45xx, outside the reserved fixture block), because a fixture number is captured before Twilio and
// would prove nothing here; the harness answers twilio.com itself, so nothing leaves this process. Twilio is made to
// answer 500, 503 (with and without its JSON error), 429, 401 (bad credentials), 400 with 63016 (outside the 24-hour
// window), 63003 (not on WhatsApp) and 21610 (the recipient replied STOP), and a timeout after which Twilio had in fact
// accepted the message.
// Expected (matrix D5): an SMS twin where the module offers one, exactly one per notice; a founder alert goes to email
// (fn_wa_founder_alert_fallback), never to SMS; nothing is sent twice, across runs; every refusal leaves the row with
// a reason customer_support can read and a send_whatsapp agent_runs line; a recipient who opted out is not followed to
// another channel.
// Known-bad controls: a healthy send is recorded exactly once with its SID and no twin (so a green cannot come from a
// harness that sees nothing), and the fixture number of the same row makes zero Twilio requests.
// The two stubbed database routines (fn_wa_sms_twin, fn_wa_founder_alert_fallback) mirror their SQL
// (scripts/sql/a_whatsapp_notice_goes_by_sms_when_whatsapp_is_down.sql and the v7 header in index.ts), including the
// one-twin-per-notice rule, so the count of twins here is the count the database would hold.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { FIXTURE, REAL_LOOKING, invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('send_whatsapp', () => import('./index.ts'));
const SECRET = 'stub-internal-credential-0123456789';
const FOUNDER_PHONE = '+971501234568';
const SIDS = JSON.stringify({ customer_new_quote: { en: 'HXdrill000000000000000000000000001' }, founder_alert: { en: 'HXdrill000000000000000000000000003' } });

type Row = Record<string, any>;
type World = {
  notifications: Row[]; runs: Row[]; twins: { of: number; body: string; reason: string }[]; fallbacks: { id: number; reason: string }[];
  /** what Twilio's Messages.json answers, per call (the n-th POST since the world began) */
  twilio: (n: number) => Response | 'timeout_after_accepting' | 'timeout';
  posts: number; accepted: number; nextId: number;
};

// ── a small PostgREST stand-in over one table: the filters send_whatsapp uses, nothing more ──────────────────────
function cond(r: Row, col: string, expr: string): boolean {
  const neg = expr.startsWith('not.');
  const e = neg ? expr.slice(4) : expr;
  const dot = e.indexOf('.');
  const op = e.slice(0, dot), v = e.slice(dot + 1);
  const x = r[col];
  let ok: boolean;
  if (op === 'eq') ok = String(x) === v;
  else if (op === 'neq') ok = String(x) !== v;
  else if (op === 'is') ok = v === 'null' ? x == null : String(x) === v;
  else if (op === 'gte') ok = x != null && String(x) >= v;
  else if (op === 'lt') ok = x != null && String(x) < v;
  else if (op === 'in') ok = v.replace(/^\(|\)$/g, '').split(',').map((s) => s.replace(/^"|"$/g, '')).includes(String(x));
  else if (op === 'ilike') ok = x != null && new RegExp('^' + v.split('*').map((s) => s.replace(/[.+?^${}()|[\]\\%]/g, '\\$&')).join('.*') + '$', 'i').test(String(x));
  else throw new Error('drill fake: unknown operator ' + op);
  return neg ? !ok : ok;
}
function matches(r: Row, u: URL): boolean {
  for (const [k, v] of u.searchParams) {
    if (['select', 'order', 'limit', 'offset', 'on_conflict', 'columns'].includes(k) || k.includes('->')) continue;
    if (k === 'or') {
      const parts = v.replace(/^\(|\)$/g, '').split(',');
      if (!parts.some((p) => { const i = p.indexOf('.'); return cond(r, p.slice(0, i), p.slice(i + 1)); })) return false;
    } else if (!cond(r, k, v)) return false;
  }
  return true;
}
const J = (o: unknown, s = 200, h: Record<string, string> = {}) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json', ...h } });
const twilioError = (status: number, code: number | null, message: string) =>
  code === null ? new Response('<html>' + message + '</html>', { status, headers: { 'content-type': 'text/html' } })
    : J({ code, message, more_info: 'https://www.twilio.com/docs/errors/' + code, status }, status);

function world(rows: Row[], twilio: World['twilio']): World {
  return { notifications: rows, runs: [], twins: [], fallbacks: [], twilio, posts: 0, accepted: 0, nextId: 1000 };
}
let seq = 0;
const now = () => new Date().toISOString();
function notice(over: Row = {}): Row {
  return { id: ++seq, channel: 'whatsapp', status: 'queued', type: 'new_quote', to_phone: REAL_LOOKING, to_role: 'customer', lang: 'en',
    subject: 'ZZ DEMO a new quote for your inquiry', body: 'ZZ DEMO a new quote is ready for you', created_at: now(), attempts: 0,
    last_error: null, provider_message_id: null, provider_error_code: null, sent_at: null, claimed_at: null, ...over };
}
const founderAlert = (over: Row = {}) => notice({ type: 'founder_alert', to_role: 'founder', to_phone: FOUNDER_PHONE,
  subject: 'QuotesDone [critical]: ZZ DEMO drill', body: 'QuotesDone [critical]: ZZ DEMO drill\nthe drill detail', ...over });

function stubFor(w: World): Stub {
  const t = w.notifications;
  return {
    rpc: { fn_internal_auth: { ok: true, context: 'test', credential_id: 1, legacy: false } },
    secrets: { wa_templates_ready: 'true', wa_template_sids: SIDS, wa_daily_cap: '40', wa_per_recipient_24h: '1', wa_stale_hours: '24', twilio_wa_from: '14155550100' },
    twilio: (req, u) => {
      if (!u.pathname.endsWith('/Messages.json') || req.method !== 'POST') return undefined;
      const a = w.twilio(++w.posts);
      if (a === 'timeout_after_accepting') { w.accepted++; throw new DOMException('Signal timed out.', 'TimeoutError'); }
      if (a === 'timeout') throw new DOMException('Signal timed out.', 'TimeoutError');
      if (a.ok) w.accepted++;
      return a;
    },
    handle: async (req, u) => {
      const body = req.method === 'GET' || req.method === 'HEAD' ? null : JSON.parse((await req.clone().text()) || 'null');
      const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1];
      if (rpc === 'fn_notifications_claim') {
        const got = t.filter((r) => r.channel === body.p_channel && r.status === 'queued' && r.to_phone).slice(0, body.p_limit);
        got.forEach((r) => { r.status = 'sending'; r.claimed_at = now(); });
        return J(got.map((r) => ({ ...r })));
      }
      if (rpc === 'fn_wa_sms_twin') {   // public.fn_wa_sms_twin: ONE twin per notice, the mark stamped once
        const n = t.find((r) => r.id === body.p_notification_id);
        if (!n || n.channel !== 'whatsapp') return J({ ok: false, outcome: 'not_a_whatsapp_notice' });
        if (!w.twins.some((x) => x.of === n.id)) {
          w.twins.push({ of: n.id, body: body.p_body, reason: body.p_reason });
          t.push({ id: ++w.nextId, channel: 'sms', status: 'queued', type: n.type, to_phone: n.to_phone, failover_of: n.id, body: body.p_body, created_at: now() });
        }
        const mark = 'sms failover: ' + String(body.p_reason || 'WhatsApp unavailable').slice(0, 300);
        if (!String(n.last_error || '').includes('sms failover:')) {
          if (['queued', 'sending'].includes(n.status)) { n.status = 'skipped'; n.last_error = mark; }
          else n.last_error = (n.last_error ? n.last_error + '; ' : '') + mark;
        }
        return J({ ok: true, outcome: 'sms_twin' });
      }
      if (rpc === 'fn_wa_founder_alert_fallback') {   // confirms or queues the email twin, then retires the row with its reason
        const n = t.find((r) => r.id === body.p_notification_id);
        if (!n || !['founder', 'admin', 'owner'].includes(n.to_role)) return J(null);
        if (!['queued', 'sending'].includes(n.status)) return J({ ok: false, outcome: 'already_handled' });
        w.fallbacks.push({ id: n.id, reason: body.p_reason });
        n.status = 'skipped'; n.last_error = 'founder fallback: emailed; ' + body.p_reason;
        return J({ ok: true, outcome: 'emailed' });
      }
      if (u.pathname === '/rest/v1/notifications') {
        if (req.method === 'HEAD') return new Response(null, { status: 200, headers: { 'content-range': '*/' + t.filter((r) => matches(r, u)).length } });
        if (req.method === 'GET') return J(t.filter((r) => matches(r, u)).slice(0, Number(u.searchParams.get('limit') || 1000)).map((r) => ({ ...r })));
        if (req.method === 'PATCH') { const hit = t.filter((r) => matches(r, u)); hit.forEach((r) => Object.assign(r, body)); return J(hit, 200); }
      }
      if (u.pathname === '/rest/v1/messaging_template' && req.method === 'GET')
        return J({ sid: u.searchParams.get('sid')?.replace(/^eq\./, ''), status: 'approved', last_checked_at: now(), approved_at: now(), rejection_reason: null });
      if (u.pathname === '/rest/v1/it_engineer_finding') return J([]);
      if (u.pathname === '/rest/v1/agent_runs') {
        if (req.method === 'POST') { for (const r of [].concat(body)) w.runs.push(r); return J([], 201); }
        return J([]);
      }
      return undefined;
    },
  };
}
const drain = async (w: World) => await invoke(await fn(), stubFor(w), { __secret: SECRET });
const own = (w: World) => w.runs.filter((r) => r.agent === 'send_whatsapp');
const row = (w: World, id: number) => w.notifications.find((r) => r.id === id)!;

// ── positive controls ──────────────────────────────────────────────────────────────────────────────────────────
Deno.test('D5 control: a healthy send reaches (stubbed) Twilio once, is recorded sent with its SID, and is not sent again', async () => {
  const n = notice();
  const w = world([n], () => J({ sid: 'SMdrill0001', status: 'queued' }, 201));
  const r = await drain(w);
  assertEquals(r.status, 200);
  assertEquals(w.posts, 1, 'exactly one Messages.json POST');
  assertEquals(row(w, n.id).status, 'sent');
  assertEquals(row(w, n.id).provider_message_id, 'SMdrill0001', 'the SID is the proof it was accepted');
  assertEquals(w.twins.length, 0, 'no SMS twin for a delivered notice');
  await drain(w);
  assertEquals(w.posts, 1, 'a second run sends nothing more');
});

Deno.test('D5 control: the same notice to a fixture number makes zero Twilio requests', async () => {
  const n = notice({ to_phone: FIXTURE });
  const w = world([n], () => J({ sid: 'SMdrill0002' }, 201));
  const r = await drain(w);
  assertEquals(r.twilio.length, 0);
  assertEquals(row(w, n.id).status, 'suppressed');
});

// ── Twilio refuses: one SMS twin, a reason on the row, a run line, and never a second WhatsApp ─────────────────────
const REFUSALS: [string, Response][] = [
  ['500 (Twilio 20500)', twilioError(500, 20500, 'Internal Server Error')],
  ['503 (Twilio 20503)', twilioError(503, 20503, 'Service Unavailable')],
  ['429 (Twilio 20429, too many requests)', twilioError(429, 20429, 'Too Many Requests')],
  ['401 (Twilio 20003, bad credentials)', twilioError(401, 20003, 'Authenticate')],
  ['400 63016 (outside the 24-hour window)', twilioError(400, 63016, 'Failed to send freeform message because you are outside the allowed window.')],
  ['400 63003 (the number is not on WhatsApp)', twilioError(400, 63003, 'Channel could not find To address')],
];
for (const [label, res] of REFUSALS) {
  Deno.test('D5 Twilio answers ' + label + ': the customer notice fails with its reason and goes once by SMS, never twice', async () => {
    const n = notice();
    const w = world([n], () => res.clone());
    await drain(w);
    assertEquals(w.posts, 1);
    const after = row(w, n.id);
    assertEquals(after.status, 'failed', 'a refused send is failed, not left looking queued or sent');
    assert(String(after.last_error).length > 10 && !/^sms failover:/.test(String(after.last_error)), 'the row keeps Twilio\'s reason: ' + after.last_error);
    assertEquals(w.twins.length, 1, 'exactly one SMS twin');
    assertEquals(w.twins[0].of, n.id);
    assert(own(w).some((x) => x.status === 'error' && /Twilio rejected/.test(String(x.note))), 'a send_whatsapp error line names the refusal');
    // the next two ticks: no second WhatsApp, no second twin (the failed-row scan reads the mark)
    await drain(w); await drain(w);
    assertEquals(w.posts, 1, 'nothing sent twice on WhatsApp');
    assertEquals(w.twins.length, 1, 'nothing sent twice by SMS');
  });

  Deno.test('D5 Twilio answers ' + label + ' to a FOUNDER alert: it goes to email with the reason, never to SMS, never twice', async () => {
    const n = founderAlert();
    const w = world([n], () => res.clone());
    await drain(w);
    assertEquals(w.posts, 1);
    assertEquals(w.fallbacks.length, 1, 'fn_wa_founder_alert_fallback carried it to email');
    assert(/Twilio/.test(w.fallbacks[0].reason), 'with the refusal as its reason: ' + w.fallbacks[0].reason);
    assertEquals(row(w, n.id).status, 'skipped');
    assertEquals(w.twins.length, 0, 'the founder has his own email fallback, not an SMS twin');
    assert(own(w).some((x) => (x.counts as Row)?.signal === 'founder_fallback_to_email'), 'the fallback is logged at error for the seat');
    await drain(w);
    assertEquals(w.posts, 1); assertEquals(w.fallbacks.length, 1);
  });
}

// 21610: Twilio's "Attempt to send to unsubscribed recipient" — the person replied STOP. The refusal is final, and
// following them to SMS with the same notice overrides the one thing they asked for.
Deno.test('D5 Twilio answers 400 21610 (the recipient opted out): failed with the reason, and NOT followed to SMS, now or on a later tick', async () => {
  const n = notice();
  const w = world([n], () => twilioError(400, 21610, 'Attempt to send to unsubscribed recipient'));
  await drain(w);
  assertEquals(w.posts, 1);
  assertEquals(row(w, n.id).status, 'failed');
  assert(/21610|opted out|unsubscribed/i.test(String(row(w, n.id).last_error)), 'the reason says they opted out: ' + row(w, n.id).last_error);
  assertEquals(w.twins.length, 0, 'no SMS to a person who said STOP');
  await drain(w);
  assertEquals(w.twins.length, 0, 'and the failed-row scan does not twin it on the next tick either');
  assertEquals(w.posts, 1);
});

// A 503 with no Twilio error object (an edge page, not Twilio's JSON) is UNKNOWN: retried, bounded, then failed + twin.
Deno.test('D5 Twilio answers 503 with no error code: retried on later ticks up to the cap, with the true reason, then failed and twinned once', async () => {
  const n = notice();
  const w = world([n], () => twilioError(503, null, 'Service Unavailable'));
  await drain(w);
  assertEquals(row(w, n.id).status, 'queued', 'released for the next tick, not dropped');
  assertEquals(row(w, n.id).attempts, 1);
  assert(/no Twilio error code, retry 1\//.test(String(row(w, n.id).last_error)), String(row(w, n.id).last_error));
  const lines = own(w).map((x) => String(x.note)).join(' | ');
  assert(!/template is missing or still awaiting Meta approval/.test(lines), 'the run line must not blame a template for a Twilio 503: ' + lines);
  for (let i = 0; i < 6; i++) await drain(w);
  assertEquals(w.posts, 5, 'UNKNOWN_RETRY_CAP (5) sends in all, then it stops');
  assertEquals(row(w, n.id).status, 'failed');
  assertEquals(w.twins.length, 1);
});

// ── the timeout: Twilio accepted it, the answer never came back ─────────────────────────────────────────────────
Deno.test('D5 Twilio times out AFTER accepting: the row is sent-unconfirmed with the reason and the next ticks never send it again', async () => {
  const n = notice();
  const w = world([n], (k) => k === 1 ? 'timeout_after_accepting' : J({ sid: 'SMdrill-dup' }, 201));
  const r = await drain(w);
  assertEquals(r.status, 200, 'a timeout does not throw out of the drain');
  assertEquals(row(w, n.id).status, 'sent');
  assertEquals(row(w, n.id).provider_message_id, null, 'no SID: unconfirmed, which the delivery watch reads as such');
  assert(/did not return/.test(String(row(w, n.id).last_error)) && /will NOT be sent again/.test(String(row(w, n.id).last_error)), String(row(w, n.id).last_error));
  assertEquals(r.json?.unconfirmed, 1);
  await drain(w); await drain(w);
  assertEquals(w.posts, 1, 'one POST in all');
  assertEquals(w.accepted, 1, 'the person got the message once');
  assertEquals(w.twins.length, 0, 'and no SMS copy of a message that may have arrived');
});

// A founder alert whose send timed out is NOT handed to the email fallback: the fallback retires the row as 'skipped',
// which would overwrite "may have arrived" with "was not sent". It stays sent-unconfirmed, the state the delivery watch
// (fn_customer_support_delivery_watch) escalates, and fn_notify_founder's own email twin is unaffected.
Deno.test('D5 Twilio times out on a FOUNDER alert: sent-unconfirmed, never re-sent on WhatsApp, never mislabelled as not sent', async () => {
  const n = founderAlert();
  const w = world([n], () => 'timeout');
  await drain(w); await drain(w);
  assertEquals(w.posts, 1);
  assertEquals(row(w, n.id).status, 'sent');
  assertEquals(row(w, n.id).provider_message_id, null);
  assertEquals(w.fallbacks.length, 0);
  assertEquals(w.twins.length, 0);
});

Deno.test('D5 a timeout on one row does not stop the queue: the next row is still sent once', async () => {
  const a = notice(), b = notice({ to_phone: '+971501234569' });
  const w = world([a, b], (k) => k === 1 ? 'timeout' : J({ sid: 'SMdrill-b' }, 201));
  await drain(w);
  assertEquals(row(w, a.id).status, 'sent');
  assertEquals(row(w, b.id).status, 'sent');
  assertEquals(row(w, b.id).provider_message_id, 'SMdrill-b');
  assertEquals(w.posts, 2);
});
