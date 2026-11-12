// A CUSTOMER'S JOB ON WHATSAPP IS THE EXPERT INTERVIEW (10 Nov 2026, customer_support with sales_engineer; founder ledger 1572,
// 1586). Drives the REAL wa_inbound handler (signed Twilio form post from the fixture block, the gateway stubbed; the harness
// is the_whole_exchange.test.ts's) for a customer whose number's state already places the job in staff_transport:
//   * the reply is asked on the interview class with the ADVISE rule, the trade's checklist, its location rules and its
//     services in the facts; then the state reader (json_extraction) runs and its reading reaches fn_inquiry_state_merge;
//   * known-bad control: a supplier gets neither the expert block nor the interview class (ruling 1008 and the seat split).
// Run: deno test --no-lock --node-modules-dir=none -A supabase/functions/wa_inbound/a_customer_job_is_the_expert_interview.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invokeRequest, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

const TAX = [{ code: 'staff_transport', label: 'Staff transport', group_code: 'transport_mobility', authority_required: [] },
  { code: 'vehicle_leasing', label: 'Vehicle leasing', group_code: 'transport_mobility', authority_required: [] }];
const fn = () => loadFunction('wa_inbound', () => import('./index.ts'));
const TOKEN = 'stub-secret-value-0123456789abcdef';   // every unlisted app_secrets key reads as this
const URL_SIGNED = 'https://db.invalid/functions/v1/wa_inbound';
const A = 'whatsapp:+971500000031', B = 'whatsapp:+971500000032';

async function sign(params: Record<string, string>, token = TOKEN): Promise<string> {
  const data = URL_SIGNED + Object.keys(params).sort().map((k) => k + params[k]).join('');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(token), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data)));
  return btoa(String.fromCharCode(...mac));
}

type World = { state?: Record<string, unknown> | null; msgs: Record<string, unknown>[]; seen: Set<string>; gateway: Record<string, unknown>[]; rpcs: { fn: string; args: Record<string, unknown> }[]; nextId: number; audience: Record<string, unknown>; replies: string[]; script?: string[]; log?: string[]; slowMs?: number;
  /** what a classification (any call that is not a conversation reply) answers, and how long a review of a decision takes */
  classify?: Record<string, unknown>; reviewMs?: number;
  /** every reply call that carries the company brief answers a cut-off object (nothing usable) */
  briefedReplyCut?: boolean;
  /** the gateway refuses every call that carries a sender rate_key (the bucket is spent) */
  bucketSpent?: boolean;
  /** what fn_trade_waitlist_join answers (ledger 1614); unset = the stub's default (no answer, read as an outage) */
  tradeGate?: Record<string, unknown>;
  /** the person's open cases (fn_support_open_cases); unset = the stub's default */
  cases?: Record<string, unknown>[];
  /** Twilio refuses every send */
  twilioFails?: boolean };
const world = (audience: Record<string, unknown> = { audience: 'supplier', name: 'ZZ DEMO Glass LLC', claimed: true, approved: true }): World =>
  ({ msgs: [], seen: new Set(), gateway: [], rpcs: [], nextId: 1, audience, replies: [] });

function stubFor(w: World): Stub {
  return {
    rpc: {
      fn_internal_auth: { ok: true, context: 'test', credential_id: 1, legacy: false },
      fn_wa_lead_id: w.audience.audience === 'supplier' ? 77 : null,   // the supplier's lead row, so a file goes down the supplier-document path
      fn_wa_route: { ok: true, needs_model: true, needs_a_person: false, deterministic_intent: null, deterministic_reply: '', fact_pack: { known: false } },
    },
    secrets: { wa_autoreply_enabled: 'true', twilio_wa_from: 'whatsapp:+14155550100' },
    ...(w.twilioFails ? { twilio: () => new Response(JSON.stringify({ code: 20003, message: 'ZZ DEMO refused' }), { status: 401, headers: { 'content-type': 'application/json' } }) } : {}),
    handle: async (req: Request, u: URL) => {
      const J = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'content-type': 'application/json' } });
      const q = (k: string) => (u.searchParams.get(k) || '').replace(/^(eq|lt|gte|lte)\./, '');
      if (u.pathname === '/functions/v1/ai_gateway') {
        const body = JSON.parse(await req.clone().text()); w.gateway.push(body);
        w.log?.push('req:' + String(body.fn ?? '') + ':' + String(body.task_class ?? ''));
        if (w.slowMs && body.fn !== 'supplier_directive') await new Promise((r) => setTimeout(r, w.slowMs));
        if (body.fn === 'supplier_directive') { w.log?.push('res:supplier_directive'); return J({ ok: true, content: '{"change":false}', model: 'stub/model' }); }
        if (w.classify && body.task_class !== 'conversation_reply') {
          const review = /decision_under_review/.test(JSON.stringify(body));
          if (review && w.reviewMs) await new Promise((r) => setTimeout(r, w.reviewMs));
          w.log?.push('res:' + (review ? 'review' : 'classify'));
          return J({ ok: true, content: JSON.stringify(review ? { ...w.classify, decision: { choice: 'none' } } : w.classify), model: 'stub/model' });
        }
        w.log?.push('res:' + String(body.task_class ?? ''));
        if (w.bucketSpent && body.rate_key) return J({ ok: true, used_llm: false, outcome: 'rate_limited', detail: { allowed: false } });
        if (w.briefedReplyCut && body.task_class === 'conversation_reply' && body.sys_stable) return J({ ok: true, content: '{"answer":"We will', model: 'stub/model' });
        const n = w.replies.length + 1; const text = w.script?.shift() ?? 'ZZ DEMO reply ' + n;
        return J({ ok: true, content: JSON.stringify({ answer: text, reply: text, lang: 'en', escalate: false }), model: 'stub/model' });
      }
      const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/);
      if (rpc) {
        const args = JSON.parse((await req.clone().text()) || '{}'); w.rpcs.push({ fn: rpc[1], args });
        if (rpc[1] === 'fn_identify_contact') return J(w.audience);
        if (rpc[1] === 'fn_trade_waitlist_join' && w.tradeGate) return J(w.tradeGate);
        if (rpc[1] === 'fn_support_open_cases' && w.cases) return J({ profile: 7, cases: w.cases });
        if (rpc[1] === 'fn_support_case_route' && w.cases) return J({ ok: true, case_ref: w.cases[0].case_ref });
        return undefined;
      }
      if (u.pathname === '/rest/v1/inquiry_state' && req.method === 'GET') return J(w.state ? [w.state] : []);
      if (u.pathname === '/rest/v1/taxonomy_trade') return J(TAX);
      if (u.pathname === '/rest/v1/taxonomy_trade_service') return J([{ trade_code: 'staff_transport', code: 'bus_rental', label_en: 'Bus rental with driver' }]);
      if (u.pathname === '/rest/v1/trade_spec_checklist') return J([{ trade_code: 'staff_transport', topic_id: 'staff_transport:spec-checklist', specs: [{ code: 'spec_number_of_passengers_and_routes', label_en: 'number of passengers and routes' }, { code: 'spec_vehicle_type_and_seating_capacity', label_en: 'vehicle type and seating capacity' }] }]);
      if (u.pathname === '/rest/v1/sales_knowledge') return J([{ tags: ['trade:staff_transport', 'kind:standard', 'lang:en'], content: 'ZZ DEMO In Dubai passenger transport is regulated by the RTA.' }]);
      if (u.pathname === '/rest/v1/review_route') return J([{ decision_type: 'person', meaning: 'an explicit request to speak to a person' }]);
      if (u.pathname === '/rest/v1/wa_inbound_seen' && req.method === 'POST') {
        const sid = JSON.parse(await req.clone().text()).message_sid;
        if (w.seen.has(sid)) return J({ code: '23505', message: 'duplicate key value violates unique constraint' }, 409);
        w.seen.add(sid); return J([], 201);
      }
      if (u.pathname === '/rest/v1/wa_messages') {
        if (req.method === 'POST') {
          const row = { id: w.nextId++, ...JSON.parse(await req.clone().text()) }; w.msgs.push(row);
          if (row.sent === true && row.reply) w.replies.push(String(row.reply));
          return J((req.headers.get('accept') || '').includes('vnd.pgrst.object') ? row : [row], 201);
        }
        if (req.method === 'PATCH') {
          const id = Number(q('id')); const row = w.msgs.find((m) => m.id === id);
          if (row) { Object.assign(row, JSON.parse(await req.clone().text())); if (row.sent === true && row.reply) w.replies.push(String(row.reply)); }
          return J(row ? [row] : [], 200);
        }
        if (req.method === 'GET') {
          const from = q('wa_from'), before = q('created_at');
          const rows = w.msgs.filter((m) => (!from || m.wa_from === from) && (!before || String(m.created_at) < before))
            .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
          return J(rows);
        }
      }
      return undefined;
    },
  };
}

let seq = 0;
async function inbound(w: World, from: string, body: string, extra: Record<string, string> = {}, token = TOKEN) {
  const pending: Promise<unknown>[] = [];
  (globalThis as unknown as { EdgeRuntime: unknown }).EdgeRuntime = { waitUntil: (p: Promise<unknown>) => { pending.push(p); } };
  const params: Record<string, string> = { From: from, To: 'whatsapp:+14155550100', Body: body, MessageSid: 'SM' + (++seq).toString(16).padStart(32, '0'), NumMedia: '0', ProfileName: 'ZZ DEMO', ...extra };
  const req = new Request(URL_SIGNED, { method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded', 'x-twilio-signature': await sign(params, token) },
    body: new URLSearchParams(params).toString() });
  const before = w.gateway.length;
  const r = await invokeRequest(await fn(), stubFor(w), req, async () => { await Promise.all(pending); });
  return { ...r, sid: params.MessageSid, gw: w.gateway.slice(before) };
}

const C = 'whatsapp:+971500000033';
const STATE = { conv_key: 'wa:+971500000033', surface: 'whatsapp', specs: {}, unknown: {}, asked: {}, message_count: 2, status: 'open', trade_codes: ['staff_transport'], options_offered: [], chosen_option: null, condition: {} };

Deno.test('a customer describing a bus job: interview class, the ADVISE rule and the trade pack; the reader updates the state', async () => {
  const w = world({ audience: 'customer', name: 'ZZ DEMO Customer', requests: [] });
  w.state = STATE;
  w.classify = { trade_codes: ['staff_transport'], service_keys: ['staff_transport.bus_rental'], condition: { use: '40 staff, Sharjah to JAFZA' } };
  const r = await inbound(w, C, 'ZZ DEMO I need a bus for 40 staff from Sharjah to JAFZA every day');
  assertEquals(r.status, 200);
  const reply = r.gw.find((g) => g.task_class === 'inquiry_qualification_conversation');
  assert(reply, 'the reply was not asked on the interview class: ' + r.gw.map((g) => g.task_class).join(', '));
  const said = JSON.stringify(reply);
  assert(said.includes('ADVISE LIKE AN EXPERT') && said.includes('[staff_transport]') && said.includes('number of passengers and routes'), 'the expert block is not in the facts');
  assert(said.includes('LOCATION RULES') && said.includes('staff_transport.bus_rental = Bus rental with driver'));
  assert(r.gw.some((g) => g.task_class === 'json_extraction' && JSON.stringify(g).includes('THE TRADE TAXONOMY')), 'the state reader did not run with the taxonomy');
  const merges = w.rpcs.filter((x) => x.fn === 'fn_inquiry_state_merge').map((x) => x.args.p_patch as Record<string, unknown>);
  assert(merges.some((p) => JSON.stringify(p.trade_codes) === '["staff_transport"]' && (p.specs as Record<string, unknown>)?.service_keys === 'staff_transport.bus_rental'), JSON.stringify(merges));
});

Deno.test('known-bad control: a supplier is never given the expert block or the interview class', async () => {
  const w = world();
  w.state = STATE;
  const r = await inbound(w, A, 'ZZ DEMO When do I start receiving jobs?');
  assertEquals(r.status, 200);
  assert(!r.gw.some((g) => g.task_class === 'inquiry_qualification_conversation'));
  assert(!JSON.stringify(r.gw).includes('ADVISE LIKE AN EXPERT'));
});

Deno.test('a job in a trade that is not open yet: the number joins its waiting list and the reply must carry the sentence (ledger 1614)', async () => {
  const w = world({ audience: 'customer', name: 'ZZ DEMO Customer', requests: [] });
  w.state = STATE;
  const sentence = 'Thank you. We are onboarding verified suppliers for Staff transport right now, so requests in this trade are not open yet.';
  w.tradeGate = { state: 'not_open', codes: ['staff_transport'], closed: [{ code: 'staff_transport', verified: 0, open_at: 10 }], message: sentence, waitlisted: true };
  const r = await inbound(w, C, 'ZZ DEMO I need a bus for 40 staff from Sharjah to JAFZA every day');
  assertEquals(r.status, 200);
  const join = w.rpcs.find((x) => x.fn === 'fn_trade_waitlist_join');
  assert(join, 'the door never asked whether the trade is open');
  assertEquals([join!.args.p_channel, join!.args.p_slugs], ['whatsapp', ['staff_transport']]);
  assert(String(join!.args.p_phone).startsWith('+9715'), 'the number was not recorded for the notice: ' + join!.args.p_phone);
  const reply = r.gw.find((g) => g.task_class === 'inquiry_qualification_conversation');
  assert(reply && JSON.stringify(reply).includes('THE TRADE IS NOT OPEN TO CUSTOMERS YET') && JSON.stringify(reply).includes(sentence), 'the facts do not say the trade is not open');
  // a draft that leaves the sentence out is sent back for a rewrite naming it (ai_reply.ts must-carry): the reply is bound to it
  assert(r.gw.some((g) => JSON.stringify(g).includes('it leaves out \\"' + sentence)), 'the reply is not bound to carry the waiting sentence');
});

// Final audit 12 Nov 2026, W4: "this trade is not open yet" was bound into EVERY later reply (7 replies to 4 people, word for
// word, including a question about a cousin's cleaning company and an Arabic refund complaint). It is carried once, recorded on
// the number's state, and then it is a fact the reply may use, never a sentence it must repeat. The second test fails on main.
Deno.test('the trade-not-open sentence is carried once: the reply that carries it records it on the number\'s state', async () => {
  const w = world({ audience: 'customer', name: 'ZZ DEMO Customer', requests: [] });
  w.state = STATE;
  const sentence = 'Thank you. We are onboarding verified suppliers for Staff transport right now, so requests in this trade are not open yet.';
  w.tradeGate = { state: 'not_open', codes: ['staff_transport'], closed: [{ code: 'staff_transport', verified: 0, open_at: 10 }], message: sentence, waitlisted: true };
  w.script = Array(12).fill(sentence + ' Meanwhile, how many staff and which shifts?');   // every call of the turn answers with it
  const r = await inbound(w, C, 'ZZ DEMO I need a bus for 40 staff from Sharjah to JAFZA every day');
  assertEquals(r.status, 200);
  const marks = w.rpcs.filter((x) => x.fn === 'fn_inquiry_state_merge').map((x) => (x.args.p_patch as { asked?: string[] }).asked).filter(Boolean);
  assertEquals(marks, [['said:trade_not_open:staff_transport']]);
});

Deno.test('once said, the next reply is not bound to the sentence again, and is told not to repeat it', async () => {
  const w = world({ audience: 'customer', name: 'ZZ DEMO Customer', requests: [] });
  w.state = { ...STATE, asked: { 'said:trade_not_open:staff_transport': { count: 1, last_turn: 1 } } };
  const sentence = 'Thank you. We are onboarding verified suppliers for Staff transport right now, so requests in this trade are not open yet.';
  w.tradeGate = { state: 'not_open', codes: ['staff_transport'], closed: [{ code: 'staff_transport', verified: 0, open_at: 10 }], message: sentence, waitlisted: true };
  const r = await inbound(w, C, 'ZZ DEMO my cousin runs a cleaning company, how does he register?');
  assertEquals(r.status, 200);
  const all = JSON.stringify(r.gw);
  assert(!all.includes('carry this sentence exactly'), 'the facts still bind the reply to the sentence');
  assert(!r.gw.some((g) => JSON.stringify(g).includes('it leaves out \\"' + sentence)), 'a draft without the sentence was sent back for a rewrite');
  assert(all.includes('EARLIER IN THIS CONVERSATION they were told this trade is not open'), 'the reply is not told it was said');
});

// Review of 12 Nov 2026 (SHOULD FIX 3): the case step ran when a draft was ADOPTED, so a lane reply replaced by the full path
// gave two versions, and a guard-refused or Twilio-failed reply was still summarised (its promises in the ledger). Now it runs
// once, at the turn's end, for a reply that was delivered (a fixture capture counts as delivered). Fails on 1e8378c59 (the
// failed-send turn routes and summarises).
Deno.test('the case records the reply that was delivered, once; a reply Twilio refused records nothing', async () => {
  const kase = { case_ref: 'QD-S-ZZ0001', title: 'ZZ DEMO bus', summary_text: 'ASKED: a bus', summary_version: 1, last_activity_at: new Date().toISOString() };
  const ok = world({ audience: 'customer', name: 'ZZ DEMO Customer', requests: [] });
  ok.cases = [kase];
  await inbound(ok, C, 'ZZ DEMO I need a bus for 40 staff');
  assertEquals(ok.rpcs.filter((x) => x.fn === 'fn_support_case_route').length, 1, 'a delivered (captured) reply is recorded once');
  const bad = world({ audience: 'customer', name: 'ZZ DEMO Customer', requests: [] });
  bad.cases = [kase]; bad.twilioFails = true;
  await inbound(bad, 'whatsapp:+971501234567', 'ZZ DEMO I need a bus for 40 staff');
  assertEquals(bad.rpcs.filter((x) => x.fn === 'fn_support_case_route' || x.fn === 'fn_support_case_summary_write').length, 0, 'a refused send is not an exchange');
});

// Review round 2 (12 Nov 2026, probe arabic_mark.test.ts): the mark was looked for in the words SENT, and an Arabic reply has its
// link wrapped in bidi isolates (replies.ts toContact), so it was never found and the sentence repeated in every Arabic
// conversation. It is matched on the reply as written. Fails on 81f76e7d5 (no mark).
Deno.test('an Arabic reply that carried the trade sentence is marked said too', async () => {
  const w = world({ audience: 'customer', name: 'ZZ DEMO Customer', requests: [] });
  w.state = { ...STATE, language: 'ar' };
  const ar = 'شكرًا لكم. نعمل حاليًا على اعتماد موردين موثّقين لهذا النشاط، لذا الطلبات فيه غير مفتوحة بعد. سجّلوا هنا وسنبلغكم فور فتحه: https://quotesdone.com/ar/me?new=1';
  w.tradeGate = { state: 'not_open', codes: ['staff_transport'], closed: [{ code: 'staff_transport', verified: 0, open_at: 10 }], message: ar, waitlisted: true };
  w.script = Array(12).fill(ar + '\nكم عدد الموظفين؟');
  await inbound(w, C, 'ZZ DEMO أحتاج باص لأربعين موظف من الشارقة إلى جافزا كل يوم');
  const marks = w.rpcs.filter((x) => x.fn === 'fn_inquiry_state_merge').map((x) => (x.args.p_patch as { asked?: string[] }).asked).filter(Boolean);
  assertEquals(marks, [['said:trade_not_open:staff_transport']]);
});
