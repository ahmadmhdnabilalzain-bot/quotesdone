// THE REAL inquiry_intake HANDLER at the 100-message limit and on "New request" after a portal chat (10 Nov 2026, founder
// ledger 1572). Offline: fetch and env stubbed (_shared/twilio_free_harness.ts); every request it makes is recorded.
// Run: deno test --no-lock --node-modules-dir=none supabase/functions/inquiry_intake/the_cap_and_the_carry.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

type Row = Record<string, unknown>;
const EMAIL = 'zz-demo-cap-customer@example.invalid';
const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
const fn = () => loadFunction('inquiry_intake', () => import('./index.ts'));

function world(o: { turns?: number; portal?: { episode_from: number; transcript: { message: string; reply: string }[] } | null }) {
  const turns: Row[] = [];
  for (let i = 0; i < (o.turns ?? 0); i++) turns.push(i % 2 ? { role: 'assistant', text: 'Which emirate?', slots: { missing_keys: ['location'], reply: { next_question: { key: 'location' } } } } : { role: 'user', text: 'ZZ DEMO turn ' + i });
  const w = { inserts: [] as Row[], saves: [] as Row[], rpcs: [] as { fn: string; args: Row }[], gateway: 0,
    intake: { id: 'ii-zz-cap', email: EMAIL, status: 'needs_info', turns, customer_id: 'c-zz-cap', category: 'aluminium', brief: { category: 'aluminium', category_by: 'reasoning' } } as Row };
  const stub: Stub = {
    user: { id: 'u-zz-cap', email: EMAIL },
    rows: { customers: [{ id: 'c-zz-cap', locale: 'en' }], category_specs: [{ category: 'aluminium', fields: [{ key: 'location', type: 'text', options: [], question: 'Which emirate?', required: true }] }] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      const r = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1];
      if (u.pathname.startsWith('/functions/v1/')) { w.gateway++; return J({ ok: true, content: JSON.stringify({ answer: 'ZZ DEMO: our sales engineer now has your whole request and will continue with you here.' }), model: 'stub/model' }); }
      if (r) { const args = await req.clone().json().catch(() => ({})); w.rpcs.push({ fn: r, args }); if (r === 'fn_seat_handoff') return J(77); if (r === 'rl_check') return J(true); return J(null); }
      if (t === 'inquiry_state' && req.method === 'GET') {
        return J(o.portal ? [{ conv_key: 'a-c-c-zz-cap#' + o.portal.episode_from, surface: 'portal_assistant', party_key: 'a-c-c-zz-cap', episode_from: o.portal.episode_from, status: 'open', specs: {}, unknown: {}, asked: {}, message_count: 4 }] : []);
      }
      if (t === 'assistant_logs' && req.method === 'GET') return J(o.portal ? o.portal.transcript : []);
      if (t === 'inquiry_intake') {
        if (req.method === 'GET') return J([{ ...w.intake }]);
        if (req.method === 'POST') { const body = await req.clone().json(); w.inserts.push(body); Object.assign(w.intake, body, { id: 'ii-zz-carried' }); return J({ ...w.intake }, 201); }
        if (req.method === 'PATCH') { const body = await req.clone().json(); w.saves.push(body); Object.assign(w.intake, body); return J([]); }
      }
      return undefined;
    },
  };
  return { w, stub };
}

Deno.test('message 101 is never sent: past the limit the request is held, handed to the sales engineer, and no model is called', async () => {
  const h = await fn();
  const { w, stub } = world({ turns: 100 });   // 100 messages already: this customer message is 101, the reply would be 102
  const r = await invoke(h, stub, { intake_id: 'ii-zz-cap', text: 'ZZ DEMO one more thing', turn_id: 't-zz-cap-101', lang: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.json));
  assertEquals([r.json.status, r.json.capped, r.json.stage, r.json.assistant_message], ['held', true, 'over', '']);
  assertEquals(w.gateway, 0, 'a model was called past the limit');
  const saved = w.saves.at(-1)!;
  assertEquals(saved.status, 'held');
  assertEquals((saved.turns as Row[]).length, 101, 'the message is kept, and no reply was added');
  const hand = w.rpcs.find((x) => x.fn === 'fn_seat_handoff');
  assert(hand && hand.args.p_type === 'spec.not_sure' && hand.args.p_to === 'sales_engineer', JSON.stringify(w.rpcs.map((x) => x.fn)));
  assert(w.rpcs.some((x) => x.fn === 'fn_inquiry_state_merge' && (x.args.p_patch as Row).status === 'handed_off'));
});

Deno.test('message 100 is the hand-off: one reply written by the model, then nothing more', async () => {
  const h = await fn();
  const { w, stub } = world({ turns: 98 });   // this customer message is 99, the reply is message 100
  const r = await invoke(h, stub, { intake_id: 'ii-zz-cap', text: 'ZZ DEMO still here', turn_id: 't-zz-cap-99', lang: 'en' });
  assertEquals([r.json.status, r.json.capped, r.json.stage], ['held', true, 'handoff']);
  assert(String(r.json.assistant_message).includes('sales engineer'), JSON.stringify(r.json));
  assertEquals((w.saves.at(-1)!.turns as Row[]).length, 100);
});

Deno.test('known-bad control: at message 60 the turn is an ordinary turn, not capped', async () => {
  const h = await fn();
  const { stub } = world({ turns: 58 });
  const r = await invoke(h, stub, { intake_id: 'ii-zz-cap', text: 'ZZ DEMO Dubai Marina', turn_id: 't-zz-cap-59', lang: 'en' });
  assert(!r.json.capped, JSON.stringify(r.json).slice(0, 300));
});

Deno.test('"New request" after a portal chat opens pre-filled with that job; with no job nothing is created', async () => {
  const h = await fn();
  const portal = { episode_from: 2, transcript: [{ message: 'old job', reply: 'Here it is. Is this correct?' }, { message: 'ZZ DEMO I need my MDF partition clad with PVC panels, 2.4 x 1.2 m, in JVC.', reply: 'Which finish would you like?' }] };
  const { w, stub } = world({ portal });
  const r = await invoke(h, stub, { carry_from: 'portal', text: '', lang: 'en', turn_id: 't-zz-carry' });
  assertEquals(r.status, 200, JSON.stringify(r.json));
  assertEquals(r.json.carried, true, JSON.stringify(r.json).slice(0, 400));
  const seeded = (w.inserts[0].turns as Row[]);
  assertEquals(seeded.map((t) => t.text), ['ZZ DEMO I need my MDF partition clad with PVC panels, 2.4 x 1.2 m, in JVC.', 'Which finish would you like?'], 'the job from its episode start');
  assert(seeded.every((t) => t.carried === 'portal'));
  assert(w.rpcs.some((x) => x.fn === 'fn_inquiry_state_carry' && x.args.p_from_key === 'a-c-c-zz-cap#2'), JSON.stringify(w.rpcs.map((x) => x.fn)));
  const none = world({ portal: null });
  const r0 = await invoke(h, none.stub, { carry_from: 'portal', text: '', lang: 'en' });
  assertEquals([r0.json.ok, r0.json.carried], [true, false]);
  assertEquals(none.w.inserts.length, 0, 'a blank request row was created with nothing to carry');
});
