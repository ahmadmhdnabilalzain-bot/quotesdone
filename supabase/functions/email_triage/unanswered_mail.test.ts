// AN UNANSWERED MAIL IS HANDED OVER AS A MAIL, NOT AS A REVIEW (customer_support, 19 Nov 2026; inbound 2169, handoff 393159).
// The pure payload, then the REAL email_triage handler: an answer fn_inbox_send refuses is handed to customer_support as
// mail.unanswered with the mail's facts (never review.requested to the CEO), and an answer that later goes completes it.
import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { unansweredMailHandoff, UNANSWERED_KIND } from './unanswered_mail.ts';

const MAIL = { id: 2169, from_email: 'support@homeboxstores.example.invalid', to_email: 'supplier@quotesdone.com', subject: 'Re: A question about your work in the UAE',
  body: 'ZZ DEMO Thank you, could you tell us more?', created_at: '2026-11-12T06:30:33Z' };

Deno.test('the payload is the mail: id, sender, owner seat, how long it waited, the draft, why no answer went; never a review', () => {
  const h = unansweredMailHandoff(MAIL, { error: 'fn_inbox_send: refused: this mail was read as unclear', draft: 'Dear HomeBox, ...', now: Date.parse('2026-11-12T06:32:57Z') });
  assertEquals([h.p_from, h.p_to, h.p_type, h.p_subject_table, h.p_subject_id], ['customer_support', 'customer_support', UNANSWERED_KIND, 'inbound_messages', '2169']);
  const p = h.p_payload;
  assertEquals([p.inbound_message_id, p.from_email, p.owner_seat, p.received_at, p.waited_hours, p.draft], [2169, MAIL.from_email, 'customer_support', MAIL.created_at, 0, 'Dear HomeBox, ...']);
  for (const s of ['#2169', MAIL.from_email, 'Owner: customer_support', 'read as unclear', 'A draft exists', 'unanswered for 0 h']) assert(p.what.includes(s), s + ' in ' + p.what);
  assertFalse(/review|decision/i.test(p.what + p.ask), 'nothing in it asks the CEO to review a decision');
  const later = unansweredMailHandoff(MAIL, { error: 'x', now: Date.parse('2026-11-19T06:30:33Z') });
  assertEquals([later.p_payload.waited_hours, later.p_payload.draft], [168, null]);
  assert(later.p_payload.what.includes('No draft exists'));
});

// ── the real handler ─────────────────────────────────────────────────────────────────────────────────────────────────
const fn = () => loadFunction('email_triage', () => import('./index.ts'));
const SECRET = 'stub-internal-credential-0123456789';
type Row = Record<string, any>;
type World = { inbound: Row[]; notifications: Row[]; runs: Row[]; handoffs: Row[]; actions: Row[]; completed: Row[]; refuse: boolean };
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
const one = (req: Request, rows: Row[]) => (req.headers.get('accept') || '').includes('vnd.pgrst.object') ? J(rows[0] ?? null) : J(rows);
function cond(r: Row, col: string, expr: string): boolean {
  const neg = expr.startsWith('not.'); const e = neg ? expr.slice(4) : expr;
  const dot = e.indexOf('.'); const op = e.slice(0, dot), v = e.slice(dot + 1); const x = r[col];
  const ok = op === 'eq' ? String(x) === v : op === 'neq' ? x != null && String(x) !== v : op === 'is' ? (v === 'null' ? x == null : String(x) === v)
    : op === 'gte' ? x != null && String(x) >= v : op === 'lte' ? x != null && String(x) <= v
    : op === 'lt' ? x != null && String(x) < v
    : op === 'in' ? v.replace(/^\(|\)$/g, '').split(',').includes(String(x))
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
function gateway(b: Row): Response {
  const ok = (c: unknown) => J({ ok: true, used_llm: true, content: typeof c === 'string' ? c : JSON.stringify(c), model: 'stub/model', finish_reason: 'stop' });
  const sys = String(b.sys ?? '');
  if (sys.startsWith('You read one e-mail that arrived at ')) return ok({ reading: 'supplier_account_question', why: 'stub: a person asks', quote: '' });
  if (sys.startsWith('You decide whether the latest e-mail')) return J({ ok: false, used_llm: false, outcome: 'circuit_open', error: 'open-circuit' }, 503);
  if (sys.startsWith('You are the inbox assistant')) return ok({ category: 'supplier_question', summary: 'stub', reply: 'ZZ DEMO stub draft' });
  const tc = String(b.task_class ?? '');
  if (tc === 'routine_employee_reasoning') return ok({ steps: [{ id: 's1', goal: 'answer', query: 'q', needs_knowledge: false }], facts: [] });
  if (tc === 'knowledge_validation') return ok({ verdict: 'agree', problems: [] });
  return ok({ answer: 'We match suppliers to customer requests in the UAE; registering is free.', reasoning: ['they ask'], decision: { choice: 'no_person' }, confidence: 0.9 });
}
function stubFor(w: World): Stub {
  return {
    secrets: { admin_emails: 'founder-test@founder-test.invalid', founder_email: 'founder-test@founder-test.invalid' },
    handle: async (req, u) => {
      const text = req.method === 'GET' || req.method === 'HEAD' ? '' : await req.clone().text();
      const body = text ? JSON.parse(text) : null;
      if (u.pathname === '/functions/v1/ai_gateway') return gateway(body);
      if (u.pathname === '/functions/v1/send_outbox') return J({ ok: true });
      const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1];
      if (rpc) {
        switch (rpc) {
          case 'fn_internal_auth': return J({ ok: true, context: 'test', credential_id: 1, legacy: false });
          case 'fn_mail_sender_known': return J('supplier');
          case 'fn_is_founder_own_inbox': return J(false);
          case 'fn_kernel_paid_provider_gate': return J({ allowed: true, rule: 'open' });
          case 'fn_mailbox_reply_rules': return J({ supplier_mailbox: true, hard_rule: null, reading: null });
          case 'fn_mailbox_reply_decide': return J({ reading: body.p_reading, hard_rule: null, may_reply: true });
          case 'fn_inbox_send': {
            if (w.refuse) return J({ error: 'refused: this mail was read as unclear, which is not answered automatically' });
            const m = w.inbound.find((r) => r.id === body.p_id)!;
            w.notifications.push({ id: w.notifications.length + 1, type: 'inbound_reply', channel: 'email', to_email: m.from_email, body: body.p_body, created_at: new Date().toISOString() });
            m.replied_at = new Date().toISOString(); return J({ ok: true });
          }
          case 'fn_seat_handoff': {
            w.handoffs.push(body);
            const id = 500 + w.actions.length;
            w.actions.push({ id, kind: 'handoff', status: 'pending', agent: body.p_to, target_id: body.p_type + ':' + body.p_subject_id, detail: body.p_payload });
            return J(id);
          }
          case 'fn_seat_handoff_complete': { w.completed.push(body); const a = w.actions.find((x) => x.id === body.p_id); if (a) a.status = 'done'; return J(null); }
          case 'fn_supplier_whatsapp_offer_state': return J({ state: 'not_a_lead' });
          default: return J(null);
        }
      }
      if (u.pathname === '/rest/v1/inbound_messages') {
        if (req.method === 'GET') return one(req, w.inbound.filter((r) => matches(r, u)).map((r) => ({ ...r })));
        if (req.method === 'PATCH') {
          const hit = w.inbound.filter((r) => matches(r, u)); hit.forEach((r) => Object.assign(r, body));
          return (req.headers.get('prefer') || '').includes('return=representation') ? one(req, hit) : new Response(null, { status: 204 });
        }
      }
      if (u.pathname === '/rest/v1/agent_actions' && req.method === 'GET') return one(req, w.actions.filter((r) => matches(r, u)));
      if (u.pathname === '/rest/v1/mailbox_reply_decision' && req.method === 'GET') return one(req, []);
      if (u.pathname === '/rest/v1/notifications') {
        if (req.method === 'HEAD') return new Response(null, { status: 200, headers: { 'content-range': '*/0' } });
        if (req.method === 'GET') return one(req, w.notifications.filter((r) => matches(r, u)));
      }
      if (u.pathname === '/rest/v1/agent_runs') {
        if (req.method === 'POST') { const r = { id: w.runs.length + 1, ...body }; w.runs.push(r); return one(req, [r]); }
        if (req.method === 'GET') return one(req, []);
        return new Response(null, { status: 204 });
      }
      return undefined;
    },
  };
}
const tick = async (w: World) => await invoke(await fn(), stubFor(w), { __secret: SECRET });

Deno.test('a refused answer is handed to customer_support as mail.unanswered with the facts, and closes when an answer goes', async () => {
  const w: World = { inbound: [], notifications: [], runs: [], handoffs: [], actions: [], completed: [], refuse: true };
  const m = { id: 99169, to_email: 'supplier@quotesdone.com', from_email: 'zz-demo-homebox@example.invalid', subject: 'ZZ DEMO Re: A question about your work in the UAE',
    body: 'ZZ DEMO Thank you, could you tell us more?', owner_role: null, raw: { message_id: '<zz-99169@example.invalid>' }, lead_id: null, provider_email_id: 'm365:zz-99169',
    needs_review: true, triaged_at: null, replied_at: null, ai_category: null, created_at: new Date(Date.now() - 3 * 3_600_000).toISOString() } as Row;
  w.inbound.push(m);
  await tick(w);
  assertEquals(w.notifications.length, 0, 'nothing went');
  assertFalse(w.handoffs.some((h) => h.p_type === 'review.requested'), 'never a review of a decision');
  assertFalse(w.handoffs.some((h) => h.p_to === 'ceo'), 'the owning seat first; the CEO only past its clock, through the overdue question');
  const h = w.handoffs.find((x) => x.p_type === UNANSWERED_KIND)!;
  assert(h, JSON.stringify(w.handoffs));
  assertEquals([h.p_from, h.p_to, h.p_subject_id], ['customer_support', 'customer_support', String(m.id)]);
  assertEquals([h.p_payload.inbound_message_id, h.p_payload.from_email, h.p_payload.owner_seat, h.p_payload.waited_hours], [m.id, m.from_email, 'customer_support', 3]);
  assertEquals(h.p_payload.draft, 'ZZ DEMO stub draft', 'the draft the triage wrote is carried');
  assert(String(h.p_payload.error).includes('read as unclear'));
  assertEquals(m.owner_role, 'customer_support');

  // the mail is put back (the drive or the CEO's order) and this time the answer goes: the hand-over is complete
  Object.assign(m, { triaged_at: null, owner_role: null, ai_category: null, needs_review: true }); w.refuse = false;
  await tick(w);
  assertEquals(w.notifications.length, 1);
  assertEquals(w.completed.map((c) => c.p_id), [w.actions[0].id]);
  assertEquals(w.actions[0].status, 'done');
});
