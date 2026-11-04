// FAILURE-INJECTION DRILLS ON THE WHATSAPP INBOUND HANDLER (release qualification matrix §5.1, lines D1, D2 and D10).
// Seat accountable: it_engineer (3 Nov 2026); the channel is customer_support's. This drives the REAL wa_inbound handler
// through its signed Twilio FORM path (HMAC-SHA1 over url + sorted params, as the_whole_exchange.test.ts does), from the
// reserved fixture block (+971 50 000 00xx), with an in-memory wa_messages / wa_inbound_seen, the REAL model path
// (model_says.ts -> ai_reply.ts -> llm.ts) and a stubbed ai_gateway that is made to fail:
//   D1  the model provider is DOWN: 503 circuit_open, 500 with no body, fetch throws, every route open-circuit (the
//       gateway's own envelope). Also the model is UP but answers in an unexpected format: not JSON, JSON without
//       "answer", a truncated object, an HTML error page (in the envelope, and as the raw body), empty completions.
//   D2  the model is SLOW: each call takes its whole allowance and is aborted (client_timeout), or answers after 20 s.
//       A fake clock (Date) moves by what each call would have taken, so the file runs in seconds, not minutes.
//   D10 the database is failing on the hot path: wa_messages insert 500 / statement timeout / connection reset,
//       wa_inbound_seen insert slow or 500, the history read failing.
// For every fault it asserts the degraded behaviour is SAFE and VISIBLE: the message is answered or held with a reason
// (a stored row, fn_reason_hold, the outage notice); no code-written text goes out while a model is UP (ruling 1339,
// _shared/openrouter_down.ts modelOrOutage); nothing is sent twice (a Twilio redelivery, a re-ask after recovery); the
// seat gets the record (fn_reason_hold for customer_support, agent_runs error, an it_engineer finding); recovery needs no
// manual step (_shared/reask.ts delivers the real answer once when the model is back). Suppliers are answered in English.
// What it does NOT prove: what the SQL routines (fn_reason_hold, fn_reask_due, fn_reask_record's 'sending' claim) do on
// the database; they are stubbed here with the contract reask.ts documents, and proved by their own SQL probes.
// Known-bad / positive controls: a real-looking number (+971 50 123 4567) with the stubbed Twilio shows exactly ONE
// Messages.json POST for an outage notice and ONE for a model reply, and ZERO when the model is up but unusable, so a
// "nothing was sent" can never come from a harness that sees no sends; the outage drill asserts the held notice IS
// seen, so the "no code text while the model is up" detector is proved able to see it.
// prevented by: this file (wa_inbound/drill_inbound_faults.test.ts)
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { invokeRequest, loadFunction, REAL_LOOKING, type Stub } from '../_shared/twilio_free_harness.ts';
import { FIXTURE_CAPTURE_NOTE } from '../_shared/demo_identity.ts';

const fn = () => loadFunction('wa_inbound', () => import('./index.ts'));
const TOKEN = 'stub-secret-value-0123456789abcdef';   // every unlisted app_secrets key reads as this (the Twilio auth token too)
const URL_SIGNED = 'https://db.invalid/functions/v1/wa_inbound';
const MARK = 'ZZ DEMO model';                           // every word the stubbed model writes carries this
const HELD_EN = 'Thank you, we have received your message. Our team will reply to you here shortly.';
const HELD_AR = 'شكرًا لكم، وصلتنا رسالتكم، وسيرد عليكم فريقنا هنا قريبًا.';
const ARABIC = /[؀-ۿ]/;
const EDGE_WALL_MS = 150_000;                           // the edge worker's background limit (model_says.ts)

// ---- the scaled clock (D2): Date runs CLOCK_SCALE times faster than the wall, so a 25 s model call takes 0.5 s ----------
// Concurrent calls overlap exactly as they do in production (each sleeps its own scaled time). The cost: the handler's own
// real work (tens of ms a turn) also counts CLOCK_SCALE times over, so the measured turn is a little LONGER than it would be.
const RealDate = Date;
const CLOCK_SCALE = 50;
let clockBase = 0;
const fakeNow = () => clockBase ? clockBase + (RealDate.now() - clockBase) * CLOCK_SCALE : RealDate.now();
class FakeDate extends RealDate {
  // deno-lint-ignore no-explicit-any
  constructor(...a: any[]) { super(...((a.length === 0 ? [fakeNow()] : a) as [number])); }
  static override now() { return fakeNow(); }
}
function useScaledClock(): () => void {
  clockBase = RealDate.now();
  (globalThis as unknown as { Date: unknown }).Date = FakeDate;
  return () => { (globalThis as unknown as { Date: unknown }).Date = RealDate; clockBase = 0; };
}
/** Wait `ms` on the scaled clock, or until the caller aborts the request (a discarded speculative draft). */
function takes(ms: number, signal: AbortSignal): Promise<'done' | 'aborted'> {
  return new Promise((res) => {
    const t = setTimeout(() => res('done'), ms / CLOCK_SCALE);
    signal.addEventListener('abort', () => { clearTimeout(t); res('aborted'); }, { once: true });
  });
}
const ABORT = () => new DOMException('The signal has been aborted', 'AbortError');

async function sign(params: Record<string, string>, token = TOKEN): Promise<string> {
  const data = URL_SIGNED + Object.keys(params).sort().map((k) => k + params[k]).join('');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(token), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data)));
  return btoa(String.fromCharCode(...mac));
}

type Row = Record<string, unknown>;
type Fault = (body: Row, req: Request) => Response | undefined | Promise<Response | undefined>;
type World = {
  msgs: Row[]; seen: Set<string>; gateway: Row[]; rpcs: { fn: string; args: Row }[]; runs: Row[]; nextId: number; audience: Row;
  /** wa_messages writes the database refused: what the handler tried to store (the reply it composed rides on it) */
  refused: Row[];
  /** the gateway's fault, per call; undefined = answer normally */
  gw?: Fault;
  /** this many conversation reply drafts are written in Arabic first (a supplier must still get English) */
  arabicDrafts?: number;
  db?: { seen?: () => Promise<Response>; msgInsert?: () => Promise<Response>; history?: () => Promise<Response> };
  /** the re-ask queue (fn_reask_due / fn_reask_record), as reask.ts documents the contract */
  reask: { row: Row; status: string }[];
};
const SUPPLIER = { audience: 'supplier', name: 'ZZ DEMO Drill Glass LLC', claimed: true, approved: true };
const world = (audience: Row = SUPPLIER): World =>
  ({ msgs: [], seen: new Set(), gateway: [], rpcs: [], runs: [], nextId: 1, audience, refused: [], reask: [] });
const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });

const READING = { answer: 'a question about the service', reasoning: [], cited: [], asked_back: null, decision: { choice: 'none' }, needs_a_person: 'no_person', menu_meaning: 'other' };
let drafts = 0;
function stubFor(w: World): Stub {
  return {
    rpc: {
      fn_internal_auth: { ok: true, context: 'test', credential_id: 1, legacy: false },
      fn_wa_lead_id: w.audience.audience === 'supplier' ? 77 : null,
      fn_wa_route: { ok: true, needs_model: true, needs_a_person: false, deterministic_intent: null, deterministic_reply: '', fact_pack: { known: false } },
      // the reply drafted beside the classification (production has the dry route): it is adopted when the reading says none
      fn_wa_route_dry: { ok: true, needs_model: true, needs_a_person: false, deterministic_intent: null, deterministic_reply: '', fact_pack: { known: false } },
    },
    secrets: { wa_autoreply_enabled: 'true', twilio_wa_from: 'whatsapp:+14155550100' },
    handle: async (req: Request, u: URL) => {
      const q = (k: string) => (u.searchParams.get(k) || '').replace(/^(eq|lt|gte|lte)\./, '');
      if (u.pathname === '/functions/v1/ai_gateway') {
        const body = JSON.parse(await req.clone().text()); w.gateway.push(body);
        const bad = await w.gw?.(body, req); if (bad) return bad;
        if (body.fn === 'supplier_directive') return J({ ok: true, content: '{"change":false}', model: 'stub/model' });
        // a well-formed reading: no intent row fits, no person needed, not a menu choice
        if (body.task_class !== 'conversation_reply') return J({ ok: true, content: JSON.stringify(READING), model: 'stub/model' });
        const n = ++drafts;
        const text = (w.arabicDrafts ?? 0) > 0 && w.arabicDrafts!-- > 0
          ? 'شكرا لرسالتك ' + MARK + ' ' + n + '.' : MARK + ' reply ' + n + ': your account is set up and requests arrive by email and WhatsApp.';
        return J({ ok: true, content: JSON.stringify({ answer: text, escalate: false }), model: 'stub/model' });
      }
      const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/);
      if (rpc) {
        const args = JSON.parse((await req.clone().text()) || '{}'); w.rpcs.push({ fn: rpc[1], args });
        if (rpc[1] === 'fn_identify_contact') return J(w.audience);
        if (rpc[1] === 'fn_reason_hold') {
          if (args.p_surface === 'wa_inbound.unwritten_reply' && !w.reask.some((r) => r.row.dedupe === args.p_dedupe_key)) {
            w.reask.push({ status: 'pending', row: { id: 900 + w.reask.length, seat: args.p_seat, surface: args.p_surface, attempts: 0, request: args.p_request, subject: args.p_subject, dedupe: args.p_dedupe_key } });
          }
          return J(900 + w.reask.length - 1);
        }
        if (rpc[1] === 'fn_reask_due') return J(w.reask.filter((r) => r.status === 'pending').map((r) => r.row));
        if (rpc[1] === 'fn_reask_record') {
          const r = w.reask.find((x) => x.row.id === args.p_id);
          const o = args.p_outcome as Row;
          if (r && o.delivered === true) r.status = 'delivered';
          return J({ status: r?.status ?? 'missing' });
        }
        return undefined;
      }
      if (u.pathname === '/rest/v1/agent_runs' && req.method === 'POST') { w.runs.push(JSON.parse(await req.clone().text())); return J([], 201); }
      if (u.pathname === '/rest/v1/review_route') return J([{ decision_type: 'person', meaning: 'an explicit request to speak to a person' }]);
      if (u.pathname === '/rest/v1/wa_inbound_seen' && req.method === 'POST') {
        if (w.db?.seen) return await w.db.seen();
        const sid = JSON.parse(await req.clone().text()).message_sid;
        if (w.seen.has(sid)) return J({ code: '23505', message: 'duplicate key value violates unique constraint "wa_inbound_seen_pkey"' }, 409);
        w.seen.add(sid); return J([], 201);
      }
      if (u.pathname === '/rest/v1/wa_messages') {
        if (req.method === 'POST') {
          const row = { id: w.nextId++, ...JSON.parse(await req.clone().text()) };
          if (w.db?.msgInsert) { w.refused.push(row); return await w.db.msgInsert(); }
          w.msgs.push(row);
          return J((req.headers.get('accept') || '').includes('vnd.pgrst.object') ? row : [row], 201);
        }
        if (req.method === 'PATCH') {
          const id = Number(q('id')); const row = w.msgs.find((m) => m.id === id);
          const stage = u.searchParams.get('meta->>stage');
          if (row && stage && (row.meta as Row | undefined)?.stage !== stage.replace(/^eq\./, '')) return J([], 200);
          if (row) Object.assign(row, JSON.parse(await req.clone().text()));
          return J(row ? [row] : [], 200);
        }
        if (req.method === 'GET') {
          const sid = u.searchParams.get('meta->>message_sid');
          if (sid) return J(w.msgs.filter((m) => (m.meta as Row | undefined)?.message_sid === sid.replace(/^eq\./, '')).map((m) => ({ id: m.id })));
          if (w.db?.history) return await w.db.history();
          const from = q('wa_from'), before = q('created_at');
          return J(w.msgs.filter((m) => (!from || m.wa_from === from) && (!before || String(m.created_at) < before))
            .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at))));
        }
      }
      return undefined;
    },
  };
}

let seq = 0;
const newSid = () => 'SM' + 'd1'.padEnd(8, '0') + (++seq).toString(16).padStart(24, '0');
async function inbound(w: World, from: string, body: string, sid = newSid()) {
  const pending: Promise<unknown>[] = [];
  (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
  const params: Record<string, string> = { From: from, To: 'whatsapp:+14155550100', Body: body, MessageSid: sid, NumMedia: '0', ProfileName: 'ZZ DEMO' };
  const req = new Request(URL_SIGNED, { method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': await sign(params) },
    body: new URLSearchParams(params).toString() });
  const g0 = w.gateway.length, r0 = w.rpcs.length, t0 = Date.now();
  const r = await invokeRequest(await fn(), stubFor(w), req, async () => { await Promise.all(pending); });
  return { ...r, sid, gw: w.gateway.slice(g0), rpcs: w.rpcs.slice(r0), ms: Date.now() - t0 };
}
/** Run `work` with this world's stub installed (the harness exposes the stub only through an invoke). */
async function withStub<T>(w: World, work: () => Promise<T>): Promise<T> {
  let out!: T;
  (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (_p: Promise<unknown>) => {} };
  await invokeRequest(await fn(), stubFor(w), new Request(URL_SIGNED, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: '' }),
    async () => { out = await work(); });
  return out;
}

// ---- what went out, and what it was --------------------------------------------------------------------------------
/** Every text handed to the sender for this number: a stored or refused row whose reply was sent or captured (fixture). */
const outgoing = (w: World, from: string) => [...w.msgs, ...w.refused]
  .filter((m) => m.wa_from === from && String(m.reply || '').trim() && (m.sent === true || (m.meta as Row | undefined)?.send_error === FIXTURE_CAPTURE_NOTE))
  .map((m) => String(m.reply));
const isNotice = (t: string) => t === HELD_EN || t === HELD_AR;
const holds = (w: World) => w.rpcs.filter((c) => c.fn === 'fn_reason_hold' && c.args.p_surface === 'wa_inbound.unwritten_reply');
const replyCalls = (gw: Row[]) => gw.filter((g) => g.task_class === 'conversation_reply' && g.fn === 'wa_inbound');
const errRuns = (w: World) => w.runs.filter((r) => r.agent === 'wa_inbound' && r.status === 'error');

/** The model's reply path asked again by the re-ask tick (_shared/reask.ts), through the real aiReply + llm.ts. */
async function reaskTick(w: World, deliveries: { phone: string; text: string }[], claimed: Set<number>) {
  const { reaskDue } = await import('../_shared/reask.ts');
  const { aiReply } = await import('../_shared/ai_reply.ts');
  const { defaultDeps } = await import('../_shared/think.ts');
  return await withStub(w, async () => {
    const admin = createClient('https://db.invalid', 'stub-service-role');
    return await reaskDue(admin, { io: {
      write: (r) => aiReply(defaultDeps(admin, 'sales_engineer'), r),
      lookup: () => Promise.resolve({ data: [], error: null }),
      gate: () => Promise.resolve([]),
      // fn_reask_record phase 'sending' is a compare-and-set in SQL: the first run to mark the row owns its send
      sending: (id) => { if (claimed.has(id)) return Promise.resolve(false); claimed.add(id); return Promise.resolve(true); },
      whatsapp: (phone, _q, text) => { deliveries.push({ phone, text }); return Promise.resolve({ delivered: true, via: 'whatsapp_text' }); },
      quoteReview: () => Promise.resolve({ ok: false }), portal: () => Promise.resolve({ ok: false }), intake: () => Promise.resolve({ ok: false }),
    } });
  });
}

// ---- the faults ----------------------------------------------------------------------------------------------------
const DOWN: Record<string, Fault> = {
  '503 circuit_open': () => J({ ok: false, used_llm: false, outcome: 'circuit_open', error: 'provider circuit open' }, 503),
  '500 with no body': () => new Response(null, { status: 500 }),
  'fetch throws (network error)': () => { throw new TypeError('error sending request for url (https://db.invalid/functions/v1/ai_gateway): connection refused'); },
  '503 every route open-circuit': () => J({ ok: false, used_llm: false, outcome: 'circuit_open', error: 'every model route for this task class is open-circuit', routes: [], cost_usd: 0 }, 503),
};
/** The gateway answered (the model is UP), but the reply completion is unusable. */
const reply200 = (content: unknown, extra: Row = {}): Fault => (b) => b.task_class === 'conversation_reply' ? J({ ok: true, content, model: 'stub/model', ...extra }) : undefined;
const UNUSABLE: Record<string, Fault> = {
  'content is not JSON': reply200('sure, let me look into that for you'),
  'JSON without answer or reply': reply200('{"lang":"en","escalate":false}'),
  'a truncated object': reply200('{"answer":"Your account is set up and requests will', { finish_reason: 'length', truncated: true }),
  'an HTML error page as the content': reply200('<html><head><title>502 Bad Gateway</title></head><body><center>nginx</center></body></html>'),
  'an HTML error page as the raw 200 body': (b) => b.task_class === 'conversation_reply' ? new Response('<html><body><h1>Service Temporarily Unavailable</h1></body></html>', { status: 200, headers: { 'content-type': 'text/html' } }) : undefined,
  "an empty completion ('')": reply200(''),
  'a null completion': reply200(null),
  "an empty completion cut at the token cap ('' , finish_reason length)": reply200('', { finish_reason: 'length', truncated: true }),
  // what ai_gateway itself answers when the provider's 2xx carried no text (ai_gateway/index.ts, 'empty_completion' 502)
  "the gateway's 502 empty_completion envelope": (b) => b.task_class === 'conversation_reply' ? J({ ok: false, error: 'empty_completion', detail: 'the provider answered HTTP 200 with no content', ladder: [], caps: [] }, 502) : undefined,
};

// =====================================================================================================================
// D1 — the model provider is DOWN
// =====================================================================================================================
for (const [name, fault] of Object.entries(DOWN)) {
  Deno.test('D1 model provider down (' + name + '): held with the outage notice once, filed for customer_support, no other text', async () => {
    const A = 'whatsapp:+971500000061';
    const w = world(); w.gw = fault;
    const r = await inbound(w, A, 'ZZ DEMO When do I start receiving jobs?');
    assertEquals(r.status, 200);
    assertEquals(r.twilio.length, 0, 'a fixture is captured, never handed to Twilio');
    const out = outgoing(w, A);
    assertEquals(out, [HELD_EN], 'exactly one text went out, and it is the outage notice (code text is allowed only because the model is down)');
    const h = holds(w);
    assertEquals(h.length, 1, 'the turn is filed once for the re-ask');
    assertEquals(h[0].args.p_seat, 'customer_support');
    assertEquals(h[0].args.p_reason, 'no_model_answer');
    assert((h[0].args.p_request as Row).reask, 'the turn rides as data for the re-ask');
    const row = w.msgs.find((m) => m.wa_from === A && m.reply);
    assert(row, 'the turn is stored');
    assertEquals((row!.meta as Row).held_notice, true);
    assertEquals(String(row!.inbound), 'ZZ DEMO When do I start receiving jobs?', 'their words are on the row');
    assert(errRuns(w).some((x) => (x.counts as Row).llm_failed === true), 'agent_runs records the failed turn as an error (the failed-run watch sees it)');
    assert(replyCalls(r.gw).length >= 1 && replyCalls(r.gw).length <= 4, 'the reply was asked, and bounded (MAX_CALLS): ' + replyCalls(r.gw).length);
  });
}

Deno.test('D1 model down, a supplier writing Arabic: the outage notice is in English, and a Twilio redelivery sends nothing more', async () => {
  const A = 'whatsapp:+971500000062';
  const w = world(); w.gw = DOWN['503 circuit_open'];
  const r = await inbound(w, A, 'ZZ DEMO متى أبدأ باستلام الطلبات؟');
  await inbound(w, A, 'ZZ DEMO متى أبدأ باستلام الطلبات؟', r.sid);   // Twilio redelivers the same MessageSid
  assertEquals(outgoing(w, A), [HELD_EN], 'one notice, in English (a supplier is always answered in English)');
  assertEquals(holds(w).length, 1, 'filed once');
  assert(w.runs.some((x) => (x.counts as Row | undefined)?.duplicate === 1), 'the redelivery is recorded as a duplicate');
});

Deno.test('D1 recovery: down -> held + notice; re-ask while down sends nothing; model back -> the real answer once, in English; redeliveries and a second tick send nothing; the next turn is answered by the model', async () => {
  const A = 'whatsapp:+971500000063';
  const w = world(); w.gw = DOWN['500 with no body'];
  const first = await inbound(w, A, 'ZZ DEMO متى أبدأ باستلام الطلبات؟');
  assertEquals(outgoing(w, A), [HELD_EN]);
  assertEquals(w.reask.length, 1, 'one turn waits in the re-ask queue');
  const delivered: { phone: string; text: string }[] = []; const claimed = new Set<number>();
  // still down: the re-ask sends nothing and consumes no attempt (the row stays pending)
  const t1 = await reaskTick(w, delivered, claimed) as Row;
  assertEquals(delivered.length, 0, 'an outage at the re-ask sends nothing');
  assertEquals(((t1.rows as Row[])[0]).outage, true);
  assertEquals(w.reask[0].status, 'pending');
  assertEquals(claimed.size, 0, 'an outage never marks the row sending');
  // the model is back; its first draft is Arabic, which a supplier must never get
  w.gw = undefined; w.arabicDrafts = 1;
  const [a, b] = await Promise.all([reaskTick(w, delivered, claimed), reaskTick(w, delivered, claimed)]);   // two ticks race for the row
  assertEquals(delivered.length, 1, 'exactly one answer is delivered: ' + JSON.stringify([a, b]));
  assertEquals(delivered[0].phone, A);
  assert(delivered[0].text.includes(MARK), 'it is the model\'s answer: ' + delivered[0].text);
  assert(!ARABIC.test(delivered[0].text), 'in English: ' + delivered[0].text);
  assertEquals(w.reask[0].status, 'delivered');
  await reaskTick(w, delivered, claimed);
  assertEquals(delivered.length, 1, 'a later tick sends nothing (the row is delivered)');
  // Twilio redelivers the original message after recovery: nothing more
  await inbound(w, A, 'ZZ DEMO متى أبدأ باستلام الطلبات؟', first.sid);
  assertEquals(outgoing(w, A), [HELD_EN], 'the redelivery after recovery sends nothing');
  // the next message is answered by the model, in English, with no notice
  w.gateway.length = 0;
  await inbound(w, A, 'ZZ DEMO وماذا عن الشارقة؟');
  const out = outgoing(w, A);
  assertEquals(out.length, 2, 'one reply per inbound: ' + JSON.stringify(out));
  assert(out[1].includes(MARK) && !ARABIC.test(out[1]), 'the next turn is the model\'s, in English: ' + out[1]);
  assertEquals(holds(w).length, 1, 'nothing else was held');
});

// =====================================================================================================================
// D1 — the model is UP but its completion is unusable: no code-written text may go out (ruling 1339)
// =====================================================================================================================
for (const [name, fault] of Object.entries(UNUSABLE)) {
  Deno.test('D1 model up, unexpected format (' + name + '): no text at all goes out, the turn is held for the re-ask with a reason', async () => {
    const A = 'whatsapp:+971500000064';
    const w = world(); w.gw = fault;
    const r = await inbound(w, A, 'ZZ DEMO Do you cover Sharjah?');
    assertEquals(r.status, 200);
    assertEquals(outgoing(w, A), [], 'nothing is sent: the model is up, so neither the notice nor any code text may go (1339)');
    const h = holds(w);
    assertEquals(h.length, 1, 'held once for the re-ask');
    assertEquals(h[0].args.p_seat, 'customer_support');
    assert(['guard_refused', 'no_usable_answer_in_budget'].includes(String(h[0].args.p_reason)), 'a reason that is not an outage: ' + h[0].args.p_reason);
    const row = w.msgs.find((m) => m.wa_from === A && m.inbound);
    assert(row, 'the message is stored');
    assertEquals(String(row!.reply), '', 'the row says no reply went');
    assertEquals((row!.meta as Row).held_notice, false);
    assert(String((row!.meta as Row).send_error || '').includes('model_up_no_safe_reply'), 'the row names why nothing went: ' + (row!.meta as Row).send_error);
    assert(errRuns(w).some((x) => (x.counts as Row).llm_failed === true), 'agent_runs records it as an error');
    assert(replyCalls(r.gw).length >= 1 && replyCalls(r.gw).length <= 4, 'bounded calls: ' + replyCalls(r.gw).length);
  });
}

Deno.test('D1 model up but every call (classification too) answers an empty completion: nothing is sent, the turn is held', async () => {
  const A = 'whatsapp:+971500000065';
  const w = world({ audience: 'unknown' }); w.gw = () => J({ ok: true, content: '', model: 'stub/model', finish_reason: 'length' });
  await inbound(w, A, 'ZZ DEMO who are you?');
  assertEquals(outgoing(w, A), []);
  assertEquals(holds(w).length, 1);
});

Deno.test('D1 known-bad / positive control: a real-looking number shows ONE Twilio send for the outage notice, ONE for a model reply, ZERO when the model is up but unusable', async () => {
  const R = 'whatsapp:' + REAL_LOOKING;
  const posts = (r: { twilio: { method: string; url: string; body: string }[] }) => r.twilio.filter((c) => c.method === 'POST' && /\/Messages\.json$/.test(c.url));
  const down = world(); down.gw = DOWN['503 circuit_open'];
  const d = posts(await inbound(down, R, 'ZZ DEMO When do I start receiving jobs?'));
  assertEquals(d.length, 1, 'the harness sees the outage notice reach (stubbed) Twilio');
  assert(new URLSearchParams(d[0].body).get('Body') === HELD_EN, 'and it is the notice');
  const up = world();
  const u = posts(await inbound(up, R, 'ZZ DEMO When do I start receiving jobs?'));
  assertEquals(u.length, 1, 'the harness sees a model reply reach (stubbed) Twilio');
  assert(String(new URLSearchParams(u[0].body).get('Body')).includes(MARK));
  const bad = world(); bad.gw = UNUSABLE['a truncated object'];
  assertEquals(posts(await inbound(bad, R, 'ZZ DEMO When do I start receiving jobs?')).length, 0, 'and nothing when the model is up but unusable');
});

// =====================================================================================================================
// D2 — the model is SLOW
// =====================================================================================================================
Deno.test('D2 model slow (every call runs out its allowance and is aborted): the turn clock holds, the outage notice goes once, filed, inside the edge wall', async () => {
  const restore = useScaledClock();
  try {
    const A = 'whatsapp:+971500000066';
    const w = world();
    const at: { what: string; start: number; end: number }[] = [];
    w.gw = async (b, req) => {
      const start = Date.now();
      // it takes the whole allowance the client gave it (llm.ts declares client_timeout_ms = its own abort point) ...
      await takes(Number(b.client_timeout_ms ?? 40_000), req.signal);
      at.push({ what: String(b.fn) + ':' + String(b.task_class), start, end: Date.now() });
      throw ABORT();   // ... and the client's abort fires
    };
    const real0 = RealDate.now();
    const r = await inbound(w, A, 'ZZ DEMO When do I start receiving jobs?');
    const realMs = RealDate.now() - real0;
    assertEquals(outgoing(w, A), [HELD_EN], 'one outage notice (a timeout is an outage, openrouter_down.ts)');
    assertEquals(holds(w).length, 1);
    assertEquals(holds(w)[0].args.p_reason, 'no_model_answer');
    assert(r.ms < EDGE_WALL_MS, 'the turn ended inside the 150 s edge wall on the turn\'s clock: ' + r.ms + ' ms');
    const t0 = Math.min(...at.map((x) => x.start));
    const replies = at.filter((x) => x.what === 'wa_inbound:conversation_reply');
    assert(replies.length >= 1, 'the reply was asked: ' + JSON.stringify(at));
    // no reply call STARTS with under MIN_CALL_MS (8 s) of the 90 s budget left (3 s send margin): 79 s after arrival
    assert(replies.every((x) => x.start - t0 <= 90_000 - 3_000 - 8_000 + 2_000), 'no reply call starts past the budget: ' + JSON.stringify(at.map((x) => [x.what, x.start - t0, x.end - t0])));
    assert(realMs < 15_000, 'the drill itself is fast: ' + realMs + ' ms real');
    console.log('D2 measured (scaled clock x' + CLOCK_SCALE + '): turn ' + r.ms + ' ms from arrival to the end of the turn; calls [what, start, end] ms: ' + JSON.stringify(at.map((x) => [x.what, x.start - t0, x.end - t0])) + '; real ' + realMs + ' ms');
  } finally { restore(); }
});

Deno.test('D2 model slow but answering (20 s a call): the model\'s reply goes out, once, no notice, nothing held', async () => {
  const restore = useScaledClock();
  try {
    const A = 'whatsapp:+971500000067';
    const w = world();
    w.gw = async (_b, req) => { if (await takes(20_000, req.signal) === 'aborted') throw ABORT(); return undefined; };
    const r = await inbound(w, A, 'ZZ DEMO When do I start receiving jobs?');
    const out = outgoing(w, A);
    assertEquals(out.length, 1, JSON.stringify(out) + ' ' + JSON.stringify(w.msgs.map((m) => (m.meta as Row).reply_attempts)));
    assert(!isNotice(out[0]) && out[0].includes(MARK), 'the model\'s words, not the notice: ' + out[0] + ' ' + JSON.stringify(w.msgs.map((m) => [(m.meta as Row).reply_attempts, (m.meta as Row).timings])));
    assertEquals(holds(w).length, 0);
    console.log('D2 measured (scaled clock x' + CLOCK_SCALE + '): a 20 s-per-call model answered; turn ' + r.ms + ' ms; timings ' + JSON.stringify((w.msgs.find((m) => m.wa_from === A)?.meta as Row)?.timings));
  } finally { restore(); }
});

// =====================================================================================================================
// D10 — the database on the hot path
// =====================================================================================================================
const PG = {
  '500': () => Promise.resolve(J({ code: 'XX000', message: 'internal error' }, 500)),
  'statement timeout': async () => { await new Promise((r) => setTimeout(r, 300)); return J({ code: '57014', message: 'canceling statement due to statement timeout' }, 500); },
  'connection reset': () => Promise.reject(new TypeError('connection reset by peer')),
};
for (const [name, fail] of Object.entries(PG)) {
  Deno.test('D10 wa_messages insert fails (' + name + '): the message is still answered by the model, once, and the lost row is an agent_runs error', async () => {
    const A = 'whatsapp:+971500000068';
    const w = world(); w.db = { msgInsert: fail };
    await inbound(w, A, 'ZZ DEMO When do I start receiving jobs?');
    const out = outgoing(w, A);
    assertEquals(out.length, 1, 'one reply was handed to the sender: ' + JSON.stringify(out));
    assert(out[0].includes(MARK), 'the model\'s: ' + out[0]);
    assert(errRuns(w).some((x) => (x.counts as Row | undefined)?.arrival_saved === 0), 'the arrival row that could not be stored is an error run');
    assert(errRuns(w).some((x) => (x.counts as Row | undefined)?.row_saved === false), 'and so is the turn row: ' + JSON.stringify(errRuns(w).map((x) => x.counts)));
  });
}

Deno.test('D10 wa_messages insert fails AND the model is down: the turn is still held with a reason (fn_reason_hold) and the notice goes once', async () => {
  const A = 'whatsapp:+971500000069';
  const w = world(); w.db = { msgInsert: PG['500'] }; w.gw = DOWN['503 circuit_open'];
  await inbound(w, A, 'ZZ DEMO When do I start receiving jobs?');
  assertEquals(outgoing(w, A), [HELD_EN]);
  assertEquals(holds(w).length, 1, 'the queue holds the turn even though wa_messages has no row');
  assert(String((holds(w)[0].args.p_request as Row).question).includes('When do I start receiving jobs?'), 'with their words');
});

Deno.test('D10 wa_inbound_seen insert is slow (800 ms): answered once, as normal', async () => {
  const A = 'whatsapp:+971500000070';
  const w = world();
  w.db = { seen: async () => { await new Promise((r) => setTimeout(r, 800)); return J([], 201); } };
  await inbound(w, A, 'ZZ DEMO When do I start receiving jobs?');
  const out = outgoing(w, A);
  assertEquals(out.length, 1);
  assert(out[0].includes(MARK));
});

for (const [name, fail] of Object.entries(PG)) {
  Deno.test('D10 wa_inbound_seen insert fails (' + name + '): the message is NOT dropped as a duplicate; it is answered once, a redelivery is still one reply, and IT gets a finding', async () => {
    const A = 'whatsapp:+971500000071';
    const w = world(); w.db = { seen: fail };
    const r = await inbound(w, A, 'ZZ DEMO When do I start receiving jobs?');
    const out = outgoing(w, A);
    assertEquals(out.length, 1, 'the message was answered, not swallowed as a redelivery: ' + JSON.stringify(out) + ' runs=' + JSON.stringify(w.runs.map((x) => [x.status, x.counts])));
    assert(out[0].includes(MARK));
    const finding = w.rpcs.find((c) => c.fn === 'fn_it_engineer_finding_upsert' && /seen/.test(String(c.args.p_issue_key)));
    assert(finding, 'it_engineer gets a finding: ' + w.rpcs.map((c) => c.fn).join(', '));
    assertEquals(finding!.args.p_raised_by, 'customer_support');
    assert(!w.runs.some((x) => (x.counts as Row | undefined)?.duplicate === 1), 'a message that was never seen is not logged as a duplicate');
    await inbound(w, A, 'ZZ DEMO When do I start receiving jobs?', r.sid);   // Twilio redelivers while the table still fails
    assertEquals(outgoing(w, A).length, 1, 'still one reply for that MessageSid (the arrival row is the second guard)');
    assert(w.runs.some((x) => (x.counts as Row | undefined)?.duplicate === 1), 'and the redelivery is recorded as one');
  });
}

// WAS AN OPEN DEFECT, FIXED 3 Nov 2026: _shared/wa_history.ts waConversation returned [] on any error (supabase-js returns
// it, it is not thrown), so the model answered with no memory of the conversation and nothing recorded it. It now reports
// the failed read to the caller, and wa_inbound raises itFinding('wa_inbound:history_unavailable'). Red before the fix.
Deno.test({ name: 'D10 history read fails: the turn records that the model was shown no history (an it_engineer finding)', fn: async () => {
  const A = 'whatsapp:+971500000072';
  const w = world(); w.db = { history: PG['500'] };
  await inbound(w, A, 'ZZ DEMO and what did I say I supply?');
  const row = w.msgs.find((m) => m.wa_from === A && m.reply);
  const seen = (row?.meta as Row | undefined)?.history_unavailable === true
    || w.rpcs.some((c) => c.fn === 'fn_it_engineer_finding_upsert' && /history/.test(String(c.args.p_issue_key)));
  assert(seen, 'a failed history read is recorded on the turn or as a finding');
} });

Deno.test('D10 history read fails: the message is still answered by the model, once (safe; the visibility is the test above)', async () => {
  const A = 'whatsapp:+971500000073';
  const w = world(); w.db = { history: PG['500'] };
  await inbound(w, A, 'ZZ DEMO and what did I say I supply?');
  const out = outgoing(w, A);
  assertEquals(out.length, 1);
  assert(out[0].includes(MARK));
});
