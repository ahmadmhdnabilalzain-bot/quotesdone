// A WRONG DRAFT IS NEVER SENT (review of branch B, 12 Nov 2026; it_engineer's adversarial tests, kept as permanent tests by
// customer_support). The reply drafted beside the classification is composed on the dry route (no intent): when the real route did
// something (changed a request, asked to confirm a cancel, started a chase with a deadline), that draft says the wrong thing. It
// was adopted by a "no missing hard fact" check for a few hours (5400590a5, reverted): on c4a467389 each of these sent the draft.
// The rule under which adoption may come back is in speculation.ts. Drives the REAL handler; nothing leaves the process.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invokeRequest, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const fn = () => loadFunction('wa_inbound', () => import('./index.ts'));
const TOKEN = 'stub-secret-value-0123456789abcdef';
const URL_SIGNED = 'https://db.invalid/functions/v1/wa_inbound';
async function sign(params: Record<string, string>): Promise<string> {
  const data = URL_SIGNED + Object.keys(params).sort().map((k) => k + params[k]).join('');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(TOKEN), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  return btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data)))));
}
const TAX = [{ code: 'staff_transport', label: 'Staff transport', group_code: 'transport_mobility', authority_required: [] }];
type World = { msgs: Record<string, unknown>[]; nextId: number; gateway: Record<string, unknown>[]; rpcs: { fn: string; args: Record<string, unknown> }[];
  classify: Record<string, unknown>; draftProse: string; realProse: string; laneProse?: string; dry: Record<string, unknown>; route: Record<string, unknown>;
  audience: Record<string, unknown>; state?: Record<string, unknown> | null; tradeGate?: Record<string, unknown> };
// the fact pack as fn_wa_fact_pack builds it: one JSON line whose generated_at is now(), so the dry call (about 4.5 s) and the real
// call (about 14 s) never give the same text
const pack = (at: string, extra: Record<string, unknown> = {}) => ({ identity: { kind: 'customer', id: 'c-1', name: 'ZZ DEMO Customer',
  requests: [{ ref: 1043, category: 'Glass', emirate: 'Dubai', open: true, status_meaning: 'open, with suppliers', suppliers_received: 3, quotes_received: 0 }] },
  conversation: { state: 'new' }, history: [], ...extra, generated_at: at });
const UNMATCHED = 'I can help with your registration, your documents, your quotes, and any job by its number. I am not sure about that one, so let me check and someone will come back to you.';
const BASE = { ok: true, needs_model: true, needs_a_person: false, deterministic_intent: null, deterministic_reply: UNMATCHED };

function stub(w: World): Stub {
  return {
    rows: { wa_reply_intent: ['how_it_works', 'pricing', 'my_requests', 'change_request', 'cancel_request'].map((k) => ({ intent_key: k, label: k })) },
    rpc: { fn_internal_auth: { ok: true, context: 'test', credential_id: 1, legacy: false }, fn_wa_lead_id: null, fn_wa_route: w.route, fn_wa_route_dry: w.dry },
    secrets: { wa_autoreply_enabled: 'true', twilio_wa_from: 'whatsapp:+14155550100' },
    handle: async (req, u) => {
      const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
      const q = (k: string) => (u.searchParams.get(k) || '').replace(/^(eq|lt|gte|lte)\./, '');
      if (u.pathname === '/functions/v1/ai_gateway') {
        const body = JSON.parse(await req.clone().text()); w.gateway.push(body);
        const isReply = /conversation_reply|inquiry_qualification|status_reply/.test(String(body.task_class));
        await new Promise((r) => setTimeout(r, isReply ? 300 : 150));
        if (!isReply) return J({ ok: true, content: JSON.stringify(w.classify), model: 'stub/model' });
        const words = body.task_class === 'status_reply' && w.laneProse ? w.laneProse : String(body.rate_key || '').startsWith('wa-spec:') ? w.draftProse : w.realProse;
        return J({ ok: true, content: JSON.stringify({ answer: words, escalate: false }), model: 'stub/model' });
      }
      const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/);
      if (rpc) {
        const args = JSON.parse((await req.clone().text()) || '{}'); w.rpcs.push({ fn: rpc[1], args });
        if (rpc[1] === 'fn_identify_contact') return J(w.audience);
        if (rpc[1] === 'fn_trade_waitlist_join' && w.tradeGate) return J(w.tradeGate);
        return undefined;
      }
      if (u.pathname === '/rest/v1/inquiry_state' && req.method === 'GET') return J(w.state ? [w.state] : []);
      if (u.pathname === '/rest/v1/taxonomy_trade') return J(TAX);
      if (u.pathname === '/rest/v1/taxonomy_trade_service') return J([]);
      if (u.pathname === '/rest/v1/trade_spec_checklist') return J([]);
      if (u.pathname === '/rest/v1/sales_knowledge') return J([]);
      if (u.pathname === '/rest/v1/wa_messages') {
        if (req.method === 'POST') { const row = { id: w.nextId++, ...JSON.parse(await req.clone().text()) }; w.msgs.push(row);
          return J((req.headers.get('accept') || '').includes('vnd.pgrst.object') ? row : [row], 201); }
        if (req.method === 'PATCH') { const row = w.msgs.find((m) => m.id === Number(q('id'))); if (row) Object.assign(row, JSON.parse(await req.clone().text())); return J(row ? [row] : [], 200); }
        if (req.method === 'GET') return J([]);
      }
      return undefined;
    },
  };
}
let seq = 0;
async function turn(w: World, from: string, body: string) {
  const pending: Promise<unknown>[] = [];
  (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
  const params: Record<string, string> = { From: from, To: 'whatsapp:+14155550100', Body: body, MessageSid: 'SMR' + (++seq).toString(16).padStart(31, '0'), NumMedia: '0', ProfileName: 'ZZ DEMO' };
  const req = new Request(URL_SIGNED, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': await sign(params) }, body: new URLSearchParams(params).toString() });
  await invokeRequest(await fn(), stub(w), req, async () => { await Promise.all(pending); });
  const row = w.msgs.find((m) => m.reply && (m.meta as Record<string, unknown>)?.timings);
  return { reply: String(row?.reply ?? ''), timings: ((row?.meta as Record<string, Record<string, unknown>>)?.timings ?? {}) as Record<string, unknown> };
}
const classified = (choice: string) => ({ answer: 'read', reasoning: [], cited: [], asked_back: null, decision: { choice }, needs_a_person: 'no_person', menu_meaning: 'other' });
const world = (o: Partial<World>): World => ({ msgs: [], nextId: 1, gateway: [], rpcs: [], classify: classified('none'), draftProse: 'DRAFT', realProse: 'REAL',
  dry: { ...BASE, fact_pack: pack('2026-11-12T08:00:04.5Z') }, route: { ...BASE, fact_pack: pack('2026-11-12T08:00:14.1Z') },
  audience: { audience: 'customer', name: 'ZZ DEMO Customer', claimed: true }, ...o });

Deno.test('a change the database made is not answered by a draft that says it cannot be made', async () => {
  const w = world({ classify: classified('intent:change_request'),
    route: { ...BASE, deterministic_intent: 'change_request', fact_pack: pack('2026-11-12T08:00:14.1Z'),
      deterministic_reply: 'I have added your change to request 1043 and sent it to the 3 supplier(s) invited to quote. You can see it on the request in your account.' },
    draftProse: 'A request cannot be changed from WhatsApp. Please open request 1043 in your account and make the change there.',
    realProse: 'I have added your change to request 1043 and sent it to the 3 suppliers invited to quote.' });
  const r = await turn(w, 'whatsapp:+971500000081', 'ZZ DEMO for request 1043 the quantity is now 40 panels');
  assert(!r.reply.includes('cannot be changed'), 'THE DRAFT WAS SENT: it contradicts what the database did on this turn');
});

Deno.test('a cancel waiting for its confirmation is not answered by a draft that says it is cancelled', async () => {
  const w = world({ classify: classified('intent:cancel_request'),
    route: { ...BASE, deterministic_intent: 'cancel_request', fact_pack: pack('2026-11-12T08:00:14.1Z'),
      deterministic_reply: 'Please confirm: to cancel request 1043 (Glass, Dubai), reply yes 1043 within 30 minutes. Nothing is cancelled until you confirm, and a cancelled request cannot be reopened.' },
    draftProse: 'Your request 1043 has been cancelled and the suppliers will be told.',
    realProse: 'To cancel request 1043, please reply yes 1043 within 30 minutes. Nothing is cancelled until you confirm.' });
  const r = await turn(w, 'whatsapp:+971500000082', 'ZZ DEMO please cancel my request 1043');
  assert(!r.reply.includes('has been cancelled'), 'THE DRAFT WAS SENT: nothing is cancelled until they confirm');
});

Deno.test('a status lane that cannot answer is never replaced by a draft that drops the chase and its deadline', async () => {
  const det = 'Request 1043 (Glass, Dubai): open, with suppliers. Sent to 3 supplier(s); 0 quote(s) so far. It is past the time quotes were due (11 Nov 17:00 UAE time) with 0 of the 3 quotes we aim for, so I have asked our sales engineer to chase it: the 3 invited supplier(s) who have not quoted were reminded today. You will get a message here as soon as a new quote arrives, and an update by 13 Nov 17:00 (UAE time) either way.';
  const w = world({ classify: classified('intent:my_requests'),
    route: { ...BASE, deterministic_intent: 'my_requests', fact_pack: pack('2026-11-12T08:00:14.1Z'), deterministic_reply: det },
    laneProse: "I can't confirm when the quotes for Request 1043 will arrive.",
    draftProse: 'Quotes usually arrive within 3 to 5 working days, and we notify you as each one arrives.',
    realProse: 'Request 1043 is late: our sales engineer is chasing the 3 suppliers and you will have an update by 13 Nov 17:00 (UAE time).' });
  const r = await turn(w, 'whatsapp:+971500000083', 'ZZ DEMO when will I get my quotes for 1043?');
  assert(!r.reply.includes('3 to 5 working days'), 'THE DRAFT WAS SENT: the request is already late and a chase with a deadline was just started');
});

Deno.test('the turn\'s after-steps always run: the state reader reads the job, and a not-open trade joins the waiting list with the number', async () => {
  const sentence = 'We are onboarding verified suppliers for Staff transport right now, so requests in this trade are not open yet. Register here and we will let you know the moment it opens.';
  const w = world({ draftProse: sentence + ' How many passengers?', realProse: sentence + ' How many passengers?',
    state: { conv_key: 'wa:+971500000084', surface: 'whatsapp', specs: {}, unknown: {}, asked: {}, message_count: 2, status: 'open', trade_codes: ['staff_transport'], options_offered: [], chosen_option: null, condition: {} },
    tradeGate: { state: 'not_open', codes: ['staff_transport'], closed: [{ code: 'staff_transport', verified: 0, open_at: 10 }], message: sentence, waitlisted: true } });
  const r = await turn(w, 'whatsapp:+971500000084', 'ZZ DEMO it is 40 staff from Sharjah to JAFZA every day');
  const joins = w.rpcs.filter((x) => x.fn === 'fn_trade_waitlist_join').map((x) => x.args.p_phone);
  const reader = w.gateway.some((g) => g.task_class === 'json_extraction' && JSON.stringify(g).includes('THE TRADE TAXONOMY'));
  assert(r.reply.includes('we will let you know the moment it opens'), 'the reply promised the notice');
  assert(joins.some((p) => typeof p === 'string' && p.startsWith('+9715')), 'the reply promised a notice but the number never joined the waiting list: ' + JSON.stringify(joins));
  assert(reader, 'the state reader (trade, specs, chosen option) did not run for this turn');
});
