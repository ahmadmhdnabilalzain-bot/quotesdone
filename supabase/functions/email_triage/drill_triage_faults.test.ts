// DRILLS D1 / D2 / D10 — an inbound e-mail while the model is down, slow or talking nonsense, while the run is killed
// and retried, and while the database is slow on email_triage's own hot path.
// Seat accountable: it_engineer (docs/release/qualification_matrix.md §5.1). Inbound e-mail is customer_support's.
//
// What it drills: the REAL email_triage handler (and through it triage_llm.ts, run_guard.ts, _shared/think.ts,
// _shared/ai_reply.ts and _shared/llm.ts) loaded through _shared/twilio_free_harness.ts, with an in-memory
// inbound_messages / agent_runs / notifications and the stubbed ai_gateway. Nothing leaves the process. The sender is a
// known customer at a reserved .invalid domain that is NOT the @example.invalid fixture convention, because a fixture
// subject is never shown a model (think.ts isFixtureRequest) and would prove nothing about an outage.
//   D1  the model is DOWN: ai_gateway answers 503 circuit_open; the request throws a network error; the founder's hold
//       (fn_kernel_paid_provider_gate founder_hold). And the model is UP but useless: an empty completion, prose that is
//       not the JSON asked for.
//   D2  the model is SLOW (the client's own abort: client_timeout); the run is killed mid-message and the next run
//       retries it (run_guard.ts); two runs overlap on the same mail (resend_inbound's wake beside the 15-minute tick).
//   D10 the database times out reading the inbox (the selection is email_triage's only claim of a row) and writing the
//       classification.
// Expected: every mail is answered or held with a reason a seat owns (customer_support hands it to the ceo seat, and
// think() files the question in its queue); no code-written reply ever goes out (rulings 1195/1196 and 1339: with no
// model nothing is sent at all); nothing is replied twice by a retried or overlapping run; and when the model is back
// the held question is answered through the replay resilience_ping runs (think.replayHeld + reasoned_delivery), with
// no manual step.
// Known-bad controls: a healthy mail is answered exactly once, in its thread, and a second tick sends nothing; the
// in-memory fn_inbox_send mirrors scripts/sql/a_customer_email_is_answered_in_its_own_thread_within_the_minute.sql
// (it does NOT refuse a second send, so a double reply shows here as two notifications, as it would in production).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('email_triage', () => import('./index.ts'));
const SECRET = 'stub-internal-credential-0123456789';
const SENDER = 'zz-demo-drill-customer@customer-drill.invalid';
const ANSWER = 'You can post your job on QuotesDone and compare anonymised quotes from vetted suppliers before you choose one.';

type Row = Record<string, any>;
type Mode = 'up' | 'circuit_open' | 'network' | 'slow' | 'empty' | 'prose' | 'reasoning_refused';
type World = {
  inbound: Row[]; runs: Row[]; notifications: Row[]; actions: Row[]; handoffs: Row[]; held: Row[]; gw: Row[];
  mode: Mode; gate: unknown; failInboxRead?: boolean; failTriageWrite?: boolean; nextRun: number; nextHeld: number;
  /** fn_mail_sender_known's answer: 'customer' (the classification path) or null (an unknown sender, the judgement queue) */
  relation: string | null; judgements: Row[];
};

// ── a small PostgREST stand-in (the filters email_triage and run_guard use) ─────────────────────────────────────
function cond(r: Row, col: string, expr: string): boolean {
  const neg = expr.startsWith('not.');
  const e = neg ? expr.slice(4) : expr;
  const dot = e.indexOf('.');
  const op = e.slice(0, dot), v = e.slice(dot + 1);
  const x = r[col];
  let ok: boolean;
  if (op === 'eq') ok = String(x) === v;
  else if (op === 'neq') ok = x != null && String(x) !== v;
  else if (op === 'is') ok = v === 'null' ? x == null : String(x) === v;
  else if (op === 'gte') ok = x != null && String(x) >= v;
  else if (op === 'lt') ok = x != null && String(x) < v;
  else if (op === 'ilike') ok = x != null && new RegExp('^' + v.replace(/\\(.)/g, '$1').split(/[*%]/).map((s) => s.replace(/[.+?^${}()|[\]\\]/g, '\\$&')).join('.*') + '$', 'i').test(String(x));
  else throw new Error('drill fake: unknown operator ' + op);
  return neg ? !ok : ok;
}
function matches(r: Row, u: URL): boolean {
  for (const [k, v] of u.searchParams) {
    if (['select', 'order', 'limit', 'offset', 'on_conflict', 'columns'].includes(k) || k.includes('->')) continue;
    if (k === 'or') {
      if (!v.replace(/^\(|\)$/g, '').split(',').some((p) => { const i = p.indexOf('.'); return cond(r, p.slice(0, i), p.slice(i + 1)); })) return false;
    } else if (!cond(r, k, v)) return false;
  }
  return true;
}
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
const one = (req: Request, rows: Row[]) => (req.headers.get('accept') || '').includes('vnd.pgrst.object') ? J(rows[0] ?? null) : J(rows);
const PG_TIMEOUT = () => J({ code: '57014', message: 'canceling statement due to statement timeout', details: null, hint: null }, 500);

// ── the model, as ai_gateway would answer it ─────────────────────────────────────────────────────────────────────
function gateway(w: World, b: Row): Response {
  w.gw.push(b);
  const tc = String(b.task_class ?? '');
  const triage = String(b.sys ?? '').startsWith('You are the inbox assistant');
  if (w.mode === 'network') throw new TypeError('error sending request for url (https://db.invalid/functions/v1/ai_gateway): connection refused');
  if (w.mode === 'slow') throw new DOMException('The signal has been aborted', 'AbortError');
  if (w.mode === 'circuit_open') return J({ ok: false, used_llm: false, outcome: 'circuit_open', error: 'every model route is open-circuit' }, 503);
  if (w.mode === 'empty') return J({ ok: true, used_llm: true, content: '', model: 'stub/model', finish_reason: 'stop' });
  if (w.mode === 'prose') return J({ ok: true, used_llm: true, content: 'I am sorry, I cannot help with that request right now', model: 'stub/model' });
  const ok = (content: unknown) => J({ ok: true, used_llm: true, content: typeof content === 'string' ? content : JSON.stringify(content), model: 'stub/model', finish_reason: 'stop' });
  if (triage) return ok({ category: 'customer_question', summary: 'ZZ DEMO the customer asks how the platform works.', reply: 'ZZ DEMO draft for the Inbox' });
  if (tc === 'conversation_reply') return ok({ answer: ANSWER });
  // think(): the reasoning chain. 'reasoning_refused' = the model answers, but nothing think() can use (it holds).
  if (w.mode === 'reasoning_refused') return ok('not the object you asked for');
  if (tc === 'routine_employee_reasoning') return ok({ steps: [{ id: 's1', goal: 'answer the question', query: 'how does QuotesDone work', needs_knowledge: false }], facts: [] });
  if (tc === 'knowledge_validation') return ok({ verdict: 'agree', problems: [] });
  return ok({ answer: ANSWER, reasoning: ['the customer asks how the platform works', 'the brief describes posting a job and comparing quotes'], decision: { choice: 'no_person' }, confidence: 0.9 });
}

function stubFor(w: World): Stub {
  return {
    secrets: { admin_emails: 'founder-drill@founder-drill.invalid', founder_email: 'founder-drill@founder-drill.invalid' },
    handle: async (req, u) => {
      const text = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.clone().text();
      const body = text ? JSON.parse(text) : null;
      if (u.pathname === '/functions/v1/ai_gateway') return gateway(w, body);
      if (u.pathname === '/functions/v1/send_outbox') return J({ ok: true });
      const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1];
      if (rpc) {
        switch (rpc) {
          case 'fn_internal_auth': return J({ ok: true, context: 'test', credential_id: 1, legacy: false });
          case 'fn_mail_sender_known': return J(w.relation);
          case 'fn_routine_judgement_enqueue': {   // on conflict (kind, subject_key) the existing id, as the SQL does
            let g = w.judgements.find((x) => x.kind === body.p_kind && x.subject_key === body.p_subject_key);
            if (!g) { g = { id: 500 + w.judgements.length, kind: body.p_kind, subject_key: body.p_subject_key }; w.judgements.push(g); }
            return J(g.id);
          }
          case 'fn_is_founder_own_inbox': return J(false);
          case 'fn_kernel_paid_provider_gate': return J(w.gate);
          case 'fn_inbox_send': {   // the SQL, line for line: it does not look at replied_at
            const m = w.inbound.find((r) => r.id === body.p_id);
            if (!m) return J({ error: 'message not found' });
            if (!String(body.p_body || '').trim()) return J({ error: 'empty reply' });
            w.notifications.push({ id: w.notifications.length + 1, type: 'inbound_reply', channel: 'email', to_email: m.from_email, body: body.p_body, in_reply_to: m.raw?.message_id ?? null, created_at: new Date().toISOString() });
            m.replied_at = new Date().toISOString(); m.replied_by = body.p_by; m.needs_review = false;
            return J({ ok: true, to: m.from_email });
          }
          case 'fn_seat_handoff': w.handoffs.push(body); return J(w.handoffs.length);
          case 'fn_reason_hold': {   // upsert on dedupe_key, as the SQL does
            const old = body.p_dedupe_key ? w.held.find((h) => h.dedupe_key === body.p_dedupe_key) : null;
            if (old) { old.reason = body.p_reason; return J(old.id); }
            const h = { id: ++w.nextHeld, seat: body.p_seat, surface: body.p_surface, question: body.p_question, request: body.p_request, subject: body.p_subject,
              reason: body.p_reason, dedupe_key: body.p_dedupe_key, status: 'held', created_at: new Date().toISOString() };
            w.held.push(h); return J(h.id);
          }
          case 'fn_reason_held_due': { const due = w.held.filter((h) => h.status === 'held').slice(0, body.p_limit); due.forEach((h) => { h.status = 'claimed'; }); return J(due); }
          case 'fn_reason_held_resolve': { const h = w.held.find((x) => x.id === body.p_id); if (h) h.status = body.p_result?.status === 'answered' ? 'answered' : 'held'; return J({ status: h?.status, fanned: [] }); }
          case 'fn_reason_held_delivered': { const h = w.held.find((x) => x.id === body.p_id); if (h) h.delivery = body.p_delivery; return J(null); }
          default: return J(null);
        }
      }
      if (u.pathname === '/rest/v1/inbound_messages') {
        if (req.method === 'GET') {
          // the selection (needs_review + triaged_at is null) is the one place a row is taken for this run
          if (w.failInboxRead && u.searchParams.get('triaged_at') === 'is.null') return PG_TIMEOUT();
          return one(req, w.inbound.filter((r) => matches(r, u)).map((r) => ({ ...r })));
        }
        if (req.method === 'PATCH') {
          if (w.failTriageWrite && body && 'triaged_at' in body && body.triaged_at) return PG_TIMEOUT();
          const hit = w.inbound.filter((r) => matches(r, u)); hit.forEach((r) => Object.assign(r, body));
          return (req.headers.get('prefer') || '').includes('return=representation') ? one(req, hit) : new Response(null, { status: 204 });
        }
      }
      if (u.pathname === '/rest/v1/agent_runs') {
        if (req.method === 'POST') { const r = { id: ++w.nextRun, started_at: new Date().toISOString(), finished_at: null, status: null, counts: {}, note: null, ...body }; w.runs.push(r); return one(req, [r]); }
        if (req.method === 'GET') return one(req, w.runs.filter((r) => matches(r, u)));
        if (req.method === 'PATCH') { const hit = w.runs.filter((r) => matches(r, u)); hit.forEach((r) => Object.assign(r, body)); return new Response(null, { status: 204 }); }
      }
      if (u.pathname === '/rest/v1/notifications' && req.method === 'HEAD')
        return new Response(null, { status: 200, headers: { 'content-range': '*/' + w.notifications.filter((r) => matches(r, u)).length } });
      if (u.pathname === '/rest/v1/agent_actions' && req.method === 'POST') { w.actions.push(body); return J([], 201); }
      return undefined;
    },
  };
}

let mailSeq = 7000;
function world(mode: Mode = 'up', over: Partial<World> = {}): World {
  return { inbound: [], runs: [], notifications: [], actions: [], handoffs: [], held: [], gw: [], mode, gate: { allowed: false, rule: 'route_not_registered' }, nextRun: 0, nextHeld: 0, relation: 'customer', judgements: [], ...over };
}
function mail(w: World, over: Row = {}): Row {
  const m = { id: ++mailSeq, from_email: SENDER, to_email: 'info@quotesdone.com', subject: 'ZZ DEMO how does it work?', body: 'ZZ DEMO Hello, how does QuotesDone work for a villa fit-out?',
    owner_role: null, raw: { message_id: '<drill-' + mailSeq + '@customer-drill.invalid>' }, lead_id: null, provider_email_id: 'resend:drill-' + mailSeq,
    needs_review: true, triaged_at: null, replied_at: null, ai_category: null, created_at: new Date().toISOString(), ...over };
  w.inbound.push(m); return m;
}
const tick = async (w: World, body: Row = {}) => await invoke(await fn(), stubFor(w), { __secret: SECRET, ...body });
const replies = (w: World, m: Row) => w.notifications.filter((n) => n.type === 'inbound_reply' && n.to_email === m.from_email);
const ownRun = (w: World) => w.runs.filter((r) => r.agent === 'email_triage');
// the replay resilience_ping runs each tick (resilience_ping/index.ts: replayHeld + deliverReasoned + liveDeliveryIO),
// over the same stubbed database; `invoke` above left the harness pointed at this world's stub.
async function replay() {
  const { replayHeld, defaultDeps } = await import('../_shared/think.ts');
  const { deliverReasoned, liveDeliveryIO } = await import('../_shared/reasoned_delivery.ts');
  const admin = createClient('https://db.invalid', 'stub-service-role');
  return await replayHeld(admin, 2, defaultDeps(admin, 'resilience_ping'), (row, r) => deliverReasoned(row as never, r, liveDeliveryIO(admin)), { maxRows: 10, budgetMs: 90_000, rowMs: 1 });
}
/** Model down, the same expectations whatever the shape of the outage. */
function assertHeldNotDropped(w: World, m: Row, label: string) {
  assertEquals(replies(w, m).length, 0, label + ': with no model, NOTHING is sent: no code-written reply (rulings 1195/1196, 1339)');
  const row = w.inbound.find((r) => r.id === m.id)!;
  assertEquals(row.replied_at, null);
  const ho = w.handoffs.find((h) => h.p_subject_id === String(m.id));
  assert(ho, label + ': the mail is handed to a seat, not left triaged with no outcome');
  assertEquals(ho.p_from, 'customer_support');
  assert(String(ho.p_payload?.error || '').length > 0, label + ': the handoff carries the reason');
  assertEquals(row.owner_role, 'ceo', label + ': and the row says who owns it now');
  assert(w.held.some((h) => h.surface === 'email_triage.reply' && h.dedupe_key === 'email_reply:' + m.id), label + ': the question is filed in customer_support\'s held queue for the replay');
  assert(ownRun(w).some((r) => r.status === 'error' && Number(r.counts?.answer_failed) === 1), label + ': the run is closed at error with answer_failed 1');
}

// ── positive control ─────────────────────────────────────────────────────────────────────────────────────────────
Deno.test('D1 control: with the model up a mail is classified and answered exactly once in its thread; the next tick sends nothing', async () => {
  const w = world('up'); const m = mail(w);
  const r = await tick(w);
  assertEquals(r.status, 200, JSON.stringify(r.json));
  assertEquals(replies(w, m).length, 1, 'one reply');
  assert(replies(w, m)[0].body.includes(ANSWER), 'written by the (stubbed) model');
  assertEquals(replies(w, m)[0].in_reply_to, m.raw.message_id, 'threaded');
  const row = w.inbound.find((x) => x.id === m.id)!;
  assertEquals(row.ai_category, 'customer_question');
  assert(row.triaged_at && row.replied_at);
  assertEquals(w.handoffs.length, 0);
  assertEquals(ownRun(w)[0].status, 'ok');
  assert(w.gw.length > 0, 'the model was asked');
  await tick(w);
  assertEquals(replies(w, m).length, 1, 'a second tick does not answer it again');
});

// ── D1: the model is down ────────────────────────────────────────────────────────────────────────────────────────
for (const [label, mode, gate] of [
  ['ai_gateway answers 503 circuit_open', 'circuit_open', { allowed: false, rule: 'route_not_registered' }],
  ['the gateway request fails with a network error', 'network', { allowed: false, rule: 'route_not_registered' }],
  ['the founder\'s hold is on (gate founder_hold)', 'circuit_open', { allowed: false, rule: 'founder_hold' }],
] as [string, Mode, unknown][]) {
  Deno.test('D1 model DOWN, ' + label + ': nothing is sent, the mail is held with its reason and handed to a seat', async () => {
    const w = world(mode, { gate }); const m = mail(w);
    const r = await tick(w);
    assertEquals(r.status, 200);
    assertHeldNotDropped(w, m, label);
  });
}

Deno.test('D1 model DOWN then back: the held question is answered by the replay, once, with no manual step', async () => {
  const w = world('circuit_open'); const m = mail(w);
  await tick(w);
  assertEquals(replies(w, m).length, 0);
  w.mode = 'up';
  const out = await replay() as Row;
  assertEquals(replies(w, m).length, 1, 'the replay answered it in the thread: ' + JSON.stringify(out).slice(0, 600));
  assert(replies(w, m)[0].body.includes(ANSWER));
  await replay();
  assertEquals(replies(w, m).length, 1, 'a second replay tick sends nothing more');
  await tick(w);
  assertEquals(replies(w, m).length, 1, 'and email_triage does not pick it up again (it is owned and answered)');
});

// ── D1: the model is up and says nothing usable ──────────────────────────────────────────────────────────────────
for (const [label, mode] of [['an empty completion', 'empty'], ['prose instead of the JSON asked for', 'prose']] as [string, Mode][]) {
  Deno.test('D1 model UP but returns ' + label + ': no code-written reply, the mail is handed to a seat with the reason', async () => {
    const w = world(mode); const m = mail(w);
    await tick(w);
    assertEquals(replies(w, m).length, 0, 'the model is up: nothing code-written may go (ruling 1339), and nothing it wrote passed');
    const row = w.inbound.find((x) => x.id === m.id)!;
    const ho = w.handoffs.find((h) => h.p_subject_id === String(m.id));
    assert(ho && String(ho.p_payload?.error || '').length > 0, 'held with a reason');
    assertEquals(row.owner_role, 'ceo');
  });
}

// The model is up, think() cannot use what it says (it files the question in the held queue), and the direct reply
// answers the mail now. The replay must not then answer it a SECOND time.
Deno.test('D2 the reasoning is refused but the direct reply goes: the replay that follows does not reply a second time', async () => {
  const w = world('reasoning_refused'); const m = mail(w);
  await tick(w);
  assertEquals(replies(w, m).length, 1, 'answered now by the direct model reply');
  w.mode = 'up';
  await replay();
  assertEquals(replies(w, m).length, 1, 'nothing replied twice: held rows ' + JSON.stringify(w.held.map((h) => [h.surface, h.status, h.delivery])));
});

// ── D2: slow model, killed and retried runs, overlapping runs ────────────────────────────────────────────────────
Deno.test('D2 model SLOW (the client gives up: client_timeout): nothing is sent, the mail is held with its reason', async () => {
  const w = world('slow'); const m = mail(w);
  await tick(w);
  assertHeldNotDropped(w, m, 'slow');
  assert(w.handoffs.some((h) => /model|answer/i.test(String(h.p_payload?.error))), 'the reason names the failed answer');
});

Deno.test('D2 a run killed AFTER the reply went: the next run closes it and does not reply again', async () => {
  const w = world('up'); const m = mail(w);
  await tick(w);
  assertEquals(replies(w, m).length, 1);
  // the same run as the platform would leave it: open, started 20 minutes ago, its last beat on this message's answer
  const dead = { id: ++w.nextRun, agent: 'email_triage', started_at: new Date(Date.now() - 20 * 60_000).toISOString(), finished_at: null as string | null,
    status: null as string | null, note: 'in progress: message ' + m.id + ' (answer) @ ' + new Date(Date.now() - 19 * 60_000).toISOString() };
  w.runs.push(dead);
  await tick(w);
  assertEquals(replies(w, m).length, 1, 'not replied twice');
  assertEquals(dead.status, 'error', 'the dead run is closed');
  assert(dead.finished_at && /ended without finishing/.test(dead.note) && dead.note.includes('message ' + m.id), 'with its reason and last beat: ' + dead.note);
});

Deno.test('D2 a run killed BEFORE the reply went: the next run reopens the mail and answers it once, with no manual step', async () => {
  const w = world('up'); const m = mail(w, { triaged_at: new Date(Date.now() - 19 * 60_000).toISOString(), ai_category: 'customer_question' });
  w.runs.push({ id: ++w.nextRun, agent: 'email_triage', started_at: new Date(Date.now() - 20 * 60_000).toISOString(), finished_at: null,
    note: 'in progress: message ' + m.id + ' (answer) @ ' + new Date(Date.now() - 19 * 60_000).toISOString() });
  await tick(w);
  assertEquals(replies(w, m).length, 1, 'answered by the next run');
  await tick(w);
  assertEquals(replies(w, m).length, 1, 'and once only');
});

Deno.test('D2 two runs overlap on the same mail (the arrival wake beside the 15-minute tick): it is answered once', async () => {
  const w = world('up'); const m = mail(w);
  const handler = await fn();
  await Promise.all([invoke(handler, stubFor(w), { __secret: SECRET, message_id: m.id }), invoke(handler, stubFor(w), { __secret: SECRET })]);
  assertEquals(replies(w, m).length, 1, 'replied ' + replies(w, m).length + ' times');
});

Deno.test('D2 control: an UNKNOWN sender is queued for its judgement and answered once', async () => {
  const w = world('up', { relation: null }); const m = mail(w);
  await tick(w);
  assertEquals(replies(w, m).length, 1);
  assertEquals(w.inbound.find((x) => x.id === m.id)!.ai_category, 'routine_queued');
  await tick(w);
  assertEquals(replies(w, m).length, 1);
});

Deno.test('D2 two runs overlap on an UNKNOWN sender\'s mail (the judgement-queue path): it is answered once', async () => {
  const w = world('up', { relation: null }); const m = mail(w);
  const handler = await fn();
  await Promise.all([invoke(handler, stubFor(w), { __secret: SECRET, message_id: m.id }), invoke(handler, stubFor(w), { __secret: SECRET })]);
  assertEquals(replies(w, m).length, 1, 'replied ' + replies(w, m).length + ' times');
  assertEquals(w.judgements.length, 1, 'one judgement queued');
});

// ── D10: the database is slow on the hot path ────────────────────────────────────────────────────────────────────
Deno.test('D10 the inbox read times out: the run says so (not an ok run with nothing to do), and the next tick answers the mail', async () => {
  const w = world('up', { failInboxRead: true }); const m = mail(w);
  const r = await tick(w);
  assertEquals(replies(w, m).length, 0);
  const run = ownRun(w)[0];
  assert(run.status === 'error' && /inbox|inbound_messages|statement timeout/i.test(String(run.note)), 'the run is closed at error with the reason: ' + JSON.stringify({ status: run.status, note: run.note, http: r.status }));
  w.failInboxRead = false;
  await tick(w);
  assertEquals(replies(w, m).length, 1, 'recovered by the next tick, no manual step');
});

Deno.test('D10 the classification write times out: the batch stops with the reason, nothing is sent, and the next tick answers once', async () => {
  const w = world('up', { failTriageWrite: true }); const m = mail(w); const m2 = mail(w);
  const r = await tick(w);
  assertEquals(r.status, 500);
  assertEquals(replies(w, m).length + replies(w, m2).length, 0, 'nothing answered on a classification it could not record');
  assert(ownRun(w)[0].status === 'error' && /could not record the triage/.test(String(ownRun(w)[0].note)), String(ownRun(w)[0].note));
  assertEquals(w.inbound.find((x) => x.id === m.id)!.triaged_at, null, 'the row is still waiting, not marked done');
  w.failTriageWrite = false;
  await tick(w);
  assertEquals(w.notifications.filter((n) => n.type === 'inbound_reply').length, 2, 'both answered once by the next tick');
  await tick(w);
  assertEquals(w.notifications.filter((n) => n.type === 'inbound_reply').length, 2);
});
