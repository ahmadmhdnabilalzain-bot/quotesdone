// THE WHATSAPP REPLY'S HOT PATH, MEASURED WITH STUBBED MODEL TIMES (it_engineer, 10 Nov 2026; channels audit R4/R5).
// Seat: customer_support (WhatsApp). Target: a reply under 10 s live WITHOUT a more expensive model.
//
// Drives the REAL wa_inbound handler (signed Twilio form path, reserved fixture numbers, nothing leaves the process). Every model
// call is the stubbed ai_gateway with a fixed delay per kind: the classification CLASSIFY_MS, a conversation reply REPLY_MS, the
// welcome line WELCOME_MS. The handler's wall time is then the sum of the model calls that ran IN SERIES on its hot path, plus
// the in-process database stubs (a few ms). What was measured on main (the PR body and the report carry the red run):
//   typed question, first draft prose (4 of 7 real turns): classification -> reply -> re-ask for the object  = C + 2R
//   "hi":                                                   classification -> the welcome line              = C + W
// and on this branch:
//   typed question: the reply starts beside the classification and its prose is taken with the classification's
//                   needs-a-person reading (ai_reply.ts escalateReading; speculation.ts adopts on the same facts)  = max(C, R)
//   "hi":           the welcome line is drafted beside the classification (classification.ts)                   = max(C, W)
// Live, with the stubbed times replaced by the measured ones (classification ~8-12 s lean in ap-southeast-1, a reply ~8-12 s,
// a re-ask 8-14 s), that is ~25-35 s -> ~9-13 s for a typed question and ~20-30 s -> ~9-12 s for a "hi" (the report says how).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invokeRequest, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('wa_inbound', () => import('./index.ts'));
const TOKEN = 'stub-secret-value-0123456789abcdef';
const URL_SIGNED = 'https://db.invalid/functions/v1/wa_inbound';
const CLASSIFY_MS = 600, REPLY_MS = 1000, WELCOME_MS = 500;   // long enough that harness overhead under a full suite stays small

async function sign(params: Record<string, string>): Promise<string> {
  const data = URL_SIGNED + Object.keys(params).sort().map((k) => k + params[k]).join('');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(TOKEN), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  return btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data)))));
}

type Call = { kind: 'classify' | 'reply' | 'welcome'; start: number; end: number };
type World = { msgs: Record<string, unknown>[]; nextId: number; calls: Call[]; t0: number; classify: Record<string, unknown>; prose: string };
const ROUTE = { ok: true, needs_model: true, needs_a_person: false, deterministic_intent: null, deterministic_reply: '', fact_pack: { known: false } };

function stub(w: World): Stub {
  return {
    rows: { wa_reply_intent: [{ intent_key: 'how_it_works', label: 'how QuotesDone works' }] },
    rpc: { fn_internal_auth: { ok: true, context: 'test', credential_id: 1, legacy: false }, fn_wa_lead_id: null, fn_wa_route: ROUTE, fn_wa_route_dry: ROUTE },
    secrets: { wa_autoreply_enabled: 'true', twilio_wa_from: 'whatsapp:+14155550100' },
    handle: async (req, u) => {
      const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
      const q = (k: string) => (u.searchParams.get(k) || '').replace(/^(eq|lt|gte|lte)\./, '');
      if (u.pathname === '/functions/v1/ai_gateway') {
        const body = JSON.parse(await req.clone().text());
        const text = JSON.stringify(body);
        const kind: Call['kind'] = body.task_class === 'conversation_reply' || /conversation_reply|inquiry_qualification/.test(String(body.task_class))
          ? (/Greet them/.test(text) ? 'welcome' : 'reply') : 'classify';
        const c: Call = { kind, start: Date.now() - w.t0, end: 0 }; w.calls.push(c);
        await new Promise((r) => setTimeout(r, kind === 'classify' ? CLASSIFY_MS : kind === 'welcome' ? WELCOME_MS : REPLY_MS));
        c.end = Date.now() - w.t0;
        if (kind === 'classify') return J({ ok: true, content: JSON.stringify(w.classify), model: 'stub/model' });
        if (kind === 'welcome') return J({ ok: true, content: JSON.stringify({ answer: 'Hello, and welcome.', escalate: false }), model: 'stub/model' });
        // a reply: the first draft of each message is finished prose (no JSON object), as 4 of 7 real first drafts were
        const prior = w.calls.filter((x) => x.kind === 'reply').length;
        return J({ ok: true, content: prior === 1 ? w.prose : JSON.stringify({ answer: w.prose, escalate: false }), model: 'stub/model' });
      }
      const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/);
      if (rpc && rpc[1] === 'fn_identify_contact') return J({ audience: 'customer', name: 'ZZ DEMO Customer', claimed: true });
      if (u.pathname === '/rest/v1/wa_messages') {
        if (req.method === 'POST') {
          const row = { id: w.nextId++, ...JSON.parse(await req.clone().text()) }; w.msgs.push(row);
          return J((req.headers.get('accept') || '').includes('vnd.pgrst.object') ? row : [row], 201);
        }
        if (req.method === 'PATCH') {
          const row = w.msgs.find((m) => m.id === Number(q('id'))); if (row) Object.assign(row, JSON.parse(await req.clone().text()));
          return J(row ? [row] : [], 200);
        }
        if (req.method === 'GET') return J([]);
      }
      return undefined;
    },
  };
}

let seq = 0;
async function turn(w: World, from: string, body: string): Promise<number> {
  const pending: Promise<unknown>[] = [];
  (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
  const params: Record<string, string> = { From: from, To: 'whatsapp:+14155550100', Body: body, MessageSid: 'SML' + (++seq).toString(16).padStart(31, '0'), NumMedia: '0', ProfileName: 'ZZ DEMO' };
  const req = new Request(URL_SIGNED, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': await sign(params) },
    body: new URLSearchParams(params).toString() });
  w.t0 = Date.now();
  await invokeRequest(await fn(), stub(w), req, async () => { await Promise.all(pending); });
  return Date.now() - w.t0;
}
const classified = (choice: string, menu: string) => ({ answer: 'read', reasoning: [], cited: [], asked_back: null, decision: { choice }, needs_a_person: 'no_person', menu_meaning: menu });
const world = (classify: Record<string, unknown>): World => ({ msgs: [], nextId: 1, calls: [], t0: 0, classify,
  prose: 'Yes, we cover glass balustrades across the UAE, so you can send your request here at any time.' });

Deno.test('a typed question whose first draft is prose: the reply runs beside the classification and the prose is the reply (max(C, R), was C + 2R)', async () => {
  // an intent other than 'none' whose route gives the same facts: the reply did not depend on the route (it was discarded on main)
  const w = world(classified('intent:how_it_works', 'other'));
  const ms = await turn(w, 'whatsapp:+971500000071', 'ZZ DEMO Do you cover glass balustrades?');
  const replies = w.calls.filter((c) => c.kind === 'reply');
  assertEquals(replies.length, 1, 'one reply call: the prose draft is the reply, no re-ask: ' + JSON.stringify(w.calls));
  const cls = w.calls.find((c) => c.kind === 'classify')!;
  assert(replies[0].start < cls.end, 'the reply started before the classification answered: ' + JSON.stringify(w.calls));
  const row = w.msgs.find((m) => String(m.reply || '').includes('glass balustrades'));
  assert(row, 'the prose answer is the stored reply');
  assert(ms < CLASSIFY_MS + 2 * REPLY_MS - REPLY_MS / 2, `hot path ${ms} ms: must be well under the main path C + 2R = ${CLASSIFY_MS + 2 * REPLY_MS} ms`);
  console.log(`typed question: ${ms} ms (stub C=${CLASSIFY_MS} R=${REPLY_MS}; main path C+2R=${CLASSIFY_MS + 2 * REPLY_MS})`);
});

Deno.test('"hi": the welcome line is drafted beside the classification (max(C, W), was C + W)', async () => {
  const w = world(classified('none', 'greeting'));
  const ms = await turn(w, 'whatsapp:+971500000072', 'hi');
  const welcome = w.calls.filter((c) => c.kind === 'welcome');
  const cls = w.calls.find((c) => c.kind === 'classify')!;
  assertEquals(welcome.length, 1, 'one welcome line, the drafted one: ' + JSON.stringify(w.calls));
  assert(welcome[0].start < cls.end, 'the welcome line started before the classification answered: ' + JSON.stringify(w.calls));
  assert(w.msgs.some((m) => (m.meta as Record<string, unknown>)?.route === 'menu_welcome' && /Hello, and welcome/.test(String(m.reply))), 'the welcome went out with the drafted line');
  assert(ms < CLASSIFY_MS + WELCOME_MS - WELCOME_MS / 2, `hot path ${ms} ms: must be under the main path C + W = ${CLASSIFY_MS + WELCOME_MS} ms`);
  console.log(`"hi": ${ms} ms (stub C=${CLASSIFY_MS} W=${WELCOME_MS}; main path C+W=${CLASSIFY_MS + WELCOME_MS})`);
});

Deno.test('known-bad control: a person-needed reading is never answered by the draft composed for no person', async () => {
  const w = world({ ...classified('none', 'other'), needs_a_person: 'needs_a_person' });
  await turn(w, 'whatsapp:+971500000073', 'ZZ DEMO I want to complain about a supplier');
  assert(w.calls.filter((c) => c.kind === 'reply').length >= 2, 'the reply was asked again on the person route: ' + JSON.stringify(w.calls));
  const row = w.msgs.find((m) => m.reply && (m.meta as Record<string, unknown>)?.timings);
  assertEquals(((row?.meta as Record<string, Record<string, unknown>>)?.timings)?.speculative, 0, 'the draft composed for no person was not adopted');
});
