// A MAIL HELD BY A MODEL ERROR IS READ AGAIN (customer_support, 19 Nov 2026; inbound_messages 2169). Pure rules first, then the
// REAL email_triage handler through the supplier-mailbox harness (in-memory rows, stubbed ai_gateway; nothing leaves the process):
//   1. a 502 gateway_deadline is not a reading: no decision, the mail stays untriaged with its attempt counted and a next_at;
//   2. a run before next_at does not read it again; a run after it does, and the model's reading then decides (answered here);
//   3. after MAX_MODEL_ATTEMPTS failures it is held as 'unclear' saying why, owned by customer_support, with its SLA;
//   4. a deliberate hold (circuit open) is unchanged: held at once (supplier_mailbox_reading.test.ts keeps those cases);
//   5. a reading that finishes after another run took the mail is not recorded (the 12 Nov overwrite).
import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { afterFailure, exhaustedWhy, isTransientModelError, MAX_MODEL_ATTEMPTS, RETRY_AFTER_MIN, retryNotDue, retryOf, SLA_HOURS } from './model_retry.ts';
import { ANSWERABLE } from './supplier_mailbox_reading.ts';

Deno.test('transient: 5xx, the gateway deadline, a timeout, a network error; never a hold, a 4xx or an empty completion', () => {
  for (const e of ['gateway_http_502:gateway_deadline', 'gateway_http_503', 'gateway_http_546:wall', 'client_timeout_30000ms', 'client_error: connection reset', 'deadline: 25000 ms'])
    assert(isTransientModelError(e), e);
  for (const e of ['gateway_http_503:circuit_open:every model route is open-circuit', 'founder_hold', 'model_hold', 'no_paid_ai', 'gateway_forbidden',
    'credential_check_unavailable', 'gateway_http_400:timeout in prompt', 'gateway_http_502:empty_completion', '', null, undefined])
    assertFalse(isTransientModelError(e), String(e));
});

Deno.test('backoff: 5, 15, 45 minutes, then the attempts are spent and the SLA is 24 h from receipt', () => {
  const t0 = Date.parse('2026-11-16T05:46:58Z');
  let raw: Record<string, unknown> = {};
  for (let i = 1; i < MAX_MODEL_ATTEMPTS; i++) {
    const f = afterFailure(raw, 'gateway_http_502:gateway_deadline', { now: t0, receivedAt: '2026-11-12T06:30:33Z' });
    assert(f.defer); assertEquals(f.retry.attempts, i);
    assertEquals(Date.parse(f.retry.next_at!) - t0, RETRY_AFTER_MIN[i - 1] * 60_000);
    assert(retryNotDue({ model_retry: f.retry }, t0)); assertFalse(retryNotDue({ model_retry: f.retry }, Date.parse(f.retry.next_at!)));
    raw = { other: 'kept', model_retry: f.retry };
  }
  const last = afterFailure(raw, 'gateway_http_502:gateway_deadline', { now: t0, receivedAt: '2026-11-12T06:30:33Z' });
  assertFalse(last.defer);
  assertEquals([last.retry.attempts, last.retry.next_at], [MAX_MODEL_ATTEMPTS, null]);
  assertEquals(last.retry.sla_due_at, new Date(Date.parse('2026-11-12T06:30:33Z') + SLA_HOURS * 3_600_000).toISOString());
  assertFalse(retryNotDue({ model_retry: last.retry }, t0), 'a spent retry never hides the mail');
  assert(exhaustedWhy(last.retry).includes('the CEO seat is told'));
  assertEquals(retryOf({}), null); assertEquals(retryOf({ model_retry: { attempts: 0 } }), null);
});

// ── the real handler ─────────────────────────────────────────────────────────────────────────────────────────────────
const fn = () => loadFunction('email_triage', () => import('./index.ts'));
const SECRET = 'stub-internal-credential-0123456789';
const BOX = 'supplier@quotesdone.com';
type Row = Record<string, any>;
type World = { inbound: Row[]; notifications: Row[]; decisions: Row[]; runs: Row[]; gw: Row[]; reading: 'deadline' | 'down' | 'answer' | 'unclear';
  /** fired as the reading call is answered: another run claiming the mail meanwhile */
  duringReading?: () => void;
  /** the attempt-count write fails (review of #2089) */
  failRetryWrite?: boolean };

const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
const one = (req: Request, rows: Row[]) => (req.headers.get('accept') || '').includes('vnd.pgrst.object') ? J(rows[0] ?? null) : J(rows);
function cond(r: Row, col: string, expr: string): boolean {
  const neg = expr.startsWith('not.'); const e = neg ? expr.slice(4) : expr;
  const dot = e.indexOf('.'); const op = e.slice(0, dot), v = e.slice(dot + 1).replace(/^"(.*)"$/, '$1');
  // a jsonb path (raw->model_retry->>next_at) as PostgREST reads it
  const x = col.includes('->') ? col.split(/->>?/).reduce((o: any, k) => (o == null ? null : o[k]), r) : r[col];
  const ok = op === 'eq' ? String(x) === v : op === 'neq' ? x != null && String(x) !== v : op === 'is' ? (v === 'null' ? x == null : String(x) === v)
    : op === 'gte' ? x != null && String(x) >= v : op === 'lte' ? x != null && String(x) <= v : op === 'lt' ? x != null && String(x) < v
    : op === 'ilike' ? x != null && new RegExp('^' + v.replace(/\\(.)/g, '$1').split(/[*%]/).map((s) => s.replace(/[.+?^${}()|[\]\\]/g, '\\$&')).join('.*') + '$', 'i').test(String(x))
    : (() => { throw new Error('fake: ' + op); })();
  return neg ? !ok : ok;
}
function matches(r: Row, u: URL): boolean {
  for (const [k, v] of u.searchParams) {
    if (['select', 'order', 'limit', 'offset', 'on_conflict', 'columns'].includes(k)) continue;
    if (k === 'or') { if (!v.replace(/^\(|\)$/g, '').split(',').some((p) => { const i = p.indexOf('.'); return cond(r, p.slice(0, i), p.slice(i + 1)); })) return false; }
    else if (!cond(r, k, v)) return false;
  }
  return true;
}
function gateway(w: World, b: Row): Response {
  w.gw.push(b);
  const ok = (c: unknown) => J({ ok: true, used_llm: true, content: typeof c === 'string' ? c : JSON.stringify(c), model: 'stub/model', finish_reason: 'stop' });
  const sys = String(b.sys ?? '');
  if (sys.startsWith('You read one e-mail that arrived at ')) {
    w.duringReading?.();
    if (w.reading === 'deadline') return J({ ok: false, used_llm: true, outcome: 'gateway_deadline', error: 'the provider did not answer in time' }, 502);
    if (w.reading === 'down') return J({ ok: false, used_llm: false, outcome: 'circuit_open', error: 'every model route is open-circuit' }, 503);
    if (w.reading === 'unclear') return ok({ reading: 'unclear', why: 'stub: cannot tell', quote: '' });
    return ok({ reading: 'supplier_account_question', why: 'stub: a person at the supplier asks about the invitation', quote: 'Could you tell us more?' });
  }
  if (sys.startsWith('You decide whether the latest e-mail')) return J({ ok: false, used_llm: false, outcome: 'circuit_open', error: 'open-circuit' }, 503);
  if (sys.startsWith('You are the inbox assistant')) return ok({ category: 'supplier_question', summary: 'stub', reply: 'stub draft' });
  const tc = String(b.task_class ?? '');
  if (tc === 'conversation_reply') return ok({ answer: 'We match suppliers to customer requests in the UAE; registering is free.' });
  if (tc === 'routine_employee_reasoning') return ok({ steps: [{ id: 's1', goal: 'answer', query: 'what is it', needs_knowledge: false }], facts: [] });
  if (tc === 'knowledge_validation') return ok({ verdict: 'agree', problems: [] });
  return ok({ answer: 'We match suppliers to customer requests in the UAE; registering is free.', reasoning: ['they ask'], decision: { choice: 'no_person' }, confidence: 0.9 });
}
function stubFor(w: World): Stub {
  return {
    secrets: { admin_emails: 'founder-test@founder-test.invalid', founder_email: 'founder-test@founder-test.invalid' },
    handle: async (req, u) => {
      const text = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.clone().text();
      const body = text ? JSON.parse(text) : null;
      if (u.pathname === '/functions/v1/ai_gateway') return gateway(w, body);
      if (u.pathname === '/functions/v1/send_outbox') return J({ ok: true });
      const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1];
      if (rpc) {
        switch (rpc) {
          case 'fn_internal_auth': return J({ ok: true, context: 'test', credential_id: 1, legacy: false });
          case 'fn_mail_sender_known': return J('supplier');
          case 'fn_is_founder_own_inbox': return J(false);
          case 'fn_kernel_paid_provider_gate': return J({ allowed: true, rule: 'open' });
          case 'fn_mailbox_reply_rules': return J({ supplier_mailbox: true, hard_rule: null, reading: null });
          case 'fn_mailbox_reply_decide': {
            const reading = body.p_reading ?? 'unclear';
            const d = { inbound_message_id: body.p_inbound_id, reading, method: body.p_method, why: body.p_why, may_reply: ANSWERABLE.has(reading), decided_at: new Date().toISOString() };
            w.decisions = w.decisions.filter((x) => x.inbound_message_id !== d.inbound_message_id).concat(d);
            return J({ reading, hard_rule: null, may_reply: d.may_reply });
          }
          case 'fn_inbox_send': {
            const m = w.inbound.find((r) => r.id === body.p_id)!;
            if (!w.decisions.find((x) => x.inbound_message_id === m.id)?.may_reply) return J({ error: 'refused: this mail was read as unclear' });
            w.notifications.push({ id: w.notifications.length + 1, type: 'inbound_reply', channel: 'email', to_email: m.from_email, body: body.p_body, created_at: new Date().toISOString() });
            m.replied_at = new Date().toISOString(); m.needs_review = false; return J({ ok: true });
          }
          case 'fn_supplier_whatsapp_offer_state': return J({ state: 'not_a_lead' });
          default: return J(null);
        }
      }
      if (u.pathname === '/rest/v1/inbound_messages') {
        if (req.method === 'GET') return one(req, w.inbound.filter((r) => matches(r, u)).map((r) => ({ ...r })));
        if (req.method === 'PATCH') {
          if (w.failRetryWrite && body?.raw?.model_retry && !body.triaged_at) return J({ message: 'stub: statement timeout' }, 500);
          const hit = w.inbound.filter((r) => matches(r, u)); hit.forEach((r) => Object.assign(r, body));
          return (req.headers.get('prefer') || '').includes('return=representation') ? one(req, hit) : new Response(null, { status: 204 });
        }
      }
      if (u.pathname === '/rest/v1/mailbox_reply_decision' && req.method === 'GET') return one(req, w.decisions.filter((r) => matches(r, u)));
      if (u.pathname === '/rest/v1/notifications') {
        if (req.method === 'HEAD') return new Response(null, { status: 200, headers: { 'content-range': '*/0' } });
        if (req.method === 'GET') return one(req, w.notifications.filter((r) => matches(r, u)));
      }
      if (u.pathname === '/rest/v1/agent_runs') {
        if (req.method === 'POST') { const r = { id: w.runs.length + 1, ...body }; w.runs.push(r); return one(req, [r]); }
        if (req.method === 'GET') return one(req, []);
        if (req.method === 'PATCH') w.runs.filter((r) => matches(r, u)).forEach((r) => Object.assign(r, body));
        return new Response(null, { status: 204 });
      }
      return undefined;
    },
  };
}
const world = (reading: World['reading']): World => ({ inbound: [], notifications: [], decisions: [], runs: [], gw: [], reading });
let seq = 9700;
function mail(w: World): Row {
  const m = { id: ++seq, to_email: BOX, from_email: 'zz-demo-supplier-' + seq + '@example.invalid', subject: 'ZZ DEMO Re: A question about your work in the UAE',
    body: 'Thank you for reaching out. Could you tell us more about how this works?', owner_role: null, raw: { message_id: '<zz-' + seq + '@example.invalid>' },
    lead_id: null, provider_email_id: 'm365:zz-' + seq, needs_review: true, triaged_at: null, replied_at: null, ai_category: null, created_at: new Date().toISOString() };
  w.inbound.push(m); return m;
}
const tick = async (w: World) => await invoke(await fn(), stubFor(w), { __secret: SECRET });
const readings = (w: World) => w.gw.filter((b) => String(b.sys ?? '').startsWith('You read one e-mail')).length;
const runCounts = (w: World) => (w.runs.filter((r) => r.agent === 'email_triage').at(-1)?.counts ?? {}) as Record<string, number>;
/** Move the retry clock as if next_at had passed. */
const due = (m: Row) => { m.raw = { ...m.raw, model_retry: { ...m.raw.model_retry, next_at: new Date(Date.now() - 1000).toISOString() } }; };

Deno.test('a 502 gateway_deadline is read again with backoff and then the model decides: the supplier is answered (inbound 2169)', async () => {
  const w = world('deadline');
  const m = mail(w);
  await tick(w);
  assertEquals(w.decisions.length, 0, 'a provider failure records no reading');
  assertEquals([m.triaged_at, m.owner_role, m.ai_category], [null, null, null], 'left untriaged and unowned, so a later run reads it');
  assertEquals(m.raw.model_retry.attempts, 1);
  assert(Date.parse(m.raw.model_retry.next_at) > Date.now(), 'its next attempt is in the future');
  assertEquals(m.raw.message_id, '<zz-' + m.id + '@example.invalid>', 'the rest of raw is kept');
  assertEquals(runCounts(w).model_retry_deferred, 1);

  await tick(w);
  assertEquals(readings(w), 1, 'a run before next_at does not pay for the reading again');

  due(m); w.reading = 'answer';
  await tick(w);
  assertEquals(readings(w), 2);
  assertEquals(w.decisions[0].reading, 'supplier_account_question', 'the model reading decides');
  assertEquals(w.notifications.filter((n) => n.to_email === m.from_email).length, 1, 'answered once, in the thread, by the normal pipeline');
  assert(m.replied_at);
});

Deno.test('after the attempts are spent it is held as unclear, saying why, owned by customer_support with its SLA', async () => {
  const w = world('deadline');
  const m = mail(w);
  for (let i = 0; i < MAX_MODEL_ATTEMPTS; i++) { await tick(w); if (i < MAX_MODEL_ATTEMPTS - 1) { assertEquals(m.triaged_at, null); due(m); } }
  assertEquals(readings(w), MAX_MODEL_ATTEMPTS);
  const d = w.decisions.find((x) => x.inbound_message_id === m.id)!;
  assertEquals([d.reading, d.method], ['unclear', 'no_model']);
  assert(String(d.why).includes('failed ' + MAX_MODEL_ATTEMPTS + ' readings'), d.why);
  assert(m.triaged_at, 'now held');
  assertEquals([m.owner_role, m.needs_review], ['customer_support', true], 'the owning seat holds it, for review');
  assert(m.raw.model_retry.exhausted_at && m.raw.model_retry.sla_due_at, 'the attempts and the SLA are on the row');
  assertEquals(w.notifications.length, 0, 'nothing sent unread');
  await tick(w);
  assertEquals(readings(w), MAX_MODEL_ATTEMPTS, 'a held mail is not read again by triage');
});

Deno.test('a deliberate hold (circuit open) is unchanged: held at once, never retried', async () => {
  const w = world('down');
  const m = mail(w);
  await tick(w);
  assertEquals(w.decisions[0]?.reading, 'unclear');
  assertEquals(m.raw.model_retry, undefined);
  assert(m.triaged_at);
});

Deno.test('a reading that finishes after another run took the mail is not recorded (the 12 Nov overwrite of 2169)', async () => {
  const w = world('unclear');
  const m = mail(w);
  // the faster run: read answerable, claimed, and is answering it
  w.decisions.push({ inbound_message_id: m.id, reading: 'supplier_account_question', method: 'model', may_reply: true, decided_at: new Date(Date.now() - 60_000).toISOString() });
  w.duringReading = () => { m.triaged_at = new Date().toISOString(); };
  await tick(w);
  assertEquals(w.decisions.find((x) => x.inbound_message_id === m.id)!.reading, 'supplier_account_question', 'the answerable reading stands');
  assertEquals(runCounts(w).taken_by_another_run, 1);

  // the same race before the claim: the other run recorded its reading after this one began
  const w2 = world('unclear');
  const m2 = mail(w2);
  w2.duringReading = () => { w2.decisions.push({ inbound_message_id: m2.id, reading: 'customer', method: 'model', may_reply: true, decided_at: new Date(Date.now() + 5).toISOString() }); };
  await tick(w2);
  assertEquals(w2.decisions.find((x) => x.inbound_message_id === m2.id)!.reading, 'customer', 'not overwritten by the slower reading');
  assertEquals(m2.triaged_at, null, 'and this run does not claim it');
});

Deno.test('an attempt count that cannot be recorded does not mean a reading on every tick: the mail is held, saying why', async () => {
  const w = world('deadline');
  w.failRetryWrite = true;
  const m = mail(w);
  await tick(w);
  assertEquals(readings(w), 1);
  const d = w.decisions.find((x) => x.inbound_message_id === m.id)!;
  assertEquals([d.reading, d.method], ['unclear', 'no_model']);
  assert(String(d.why).includes('could not be recorded'), d.why);
  assert(m.triaged_at); assertEquals([m.owner_role, m.needs_review], ['customer_support', true]);
  assertEquals(runCounts(w).model_retry_unrecorded, 1);
  await tick(w);
  assertEquals(readings(w), 1, 'bounded: not read again');
});

Deno.test('mail not yet due is excluded in the query: 25 deferred mails never hold a new one back', async () => {
  const w = world('deadline');
  const later = new Date(Date.now() + 40 * 60_000).toISOString();
  const waiting = Array.from({ length: 25 }, () => { const x = mail(w); x.created_at = '2026-11-20T00:00:00.000Z';
    x.raw = { ...x.raw, model_retry: { attempts: 2, first_at: x.created_at, last_at: x.created_at, last_error: 'gateway_http_502', next_at: later } }; return x; });
  const fresh = mail(w); w.reading = 'answer';
  await tick(w);
  assertEquals(readings(w), 1, 'only the due mail is read');
  assert(fresh.replied_at, 'the new mail is answered in the same tick');
  assert(waiting.every((x) => x.triaged_at === null && x.raw.model_retry.attempts === 2), 'the waiting mail is untouched');
});
