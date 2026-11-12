// A CUT READING NEVER ASKS WHAT THE CONVERSATION ANSWERED (12 Nov 2026, it_engineer; founder ruling 1631 "read the history,
// never repeat", ledger 1642; final audit 2026-11-12 section 3, customer_journey.md H1).
//
// The exact-spec reader runs on the turn's clock (turn_clock.ts) and is started only for the required specs the row does not
// hold yet. When it is cut (11 Nov 2026: 23 of 41 intake readings, "model_failed: no reply" at 21-23 s) or the model's brief
// leaves out a spec an earlier turn recorded, the spec was blank at the ready gate and "simply asked": the customer was asked
// again for what he had already said. This drives the real handler (twilio_free_harness, no network, no model): the model
// says ready, its brief omits the location the request's state recorded two turns ago, and the reader is cut. The location
// is not asked (the turn goes on to the next open question). The control: with nothing recorded the same turn asks it (the gate still holds).
// Run: deno test --no-lock --node-modules-dir=auto -A supabase/functions/inquiry_intake/a_cut_reading_never_asks_what_the_conversation_answered.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { recordedSpecs } from './blocking_gate.ts';

type Row = Record<string, unknown>;
const EMAIL = 'zz-demo-cut-reading@example.invalid';
const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
const FIELDS = [
  { key: 'element', type: 'text', options: [], question: 'What aluminium work?', required: true },
  { key: 'location', type: 'text', options: [], question: 'Which emirate and area is the property in?', required: true },
];
const MODEL = { category: 'aluminium', trades: ['aluminium'], status: 'ready', claims_ready: true, assistant_message: 'All set.', questions: [], missing: [], readiness: 100,
  dialect: 'english', trade_codes: [], service_keys: [], checklist_topics: [], condition: {}, problem: '', options_offered: [], chosen_option: '', budget: '',
  // 12 Nov 2026 (review of #1979, A1): the stand-in returns the emirate the conversation states, as the interview contract now
  // asks (brief.emirate); with none held the request asks "Which emirate?" before it is ready, which is not this test's subject.
  brief: { summary: 'ZZ DEMO aluminium windows', emirate: 'Dubai', details: { element: 'Windows, sliding' } } };

function world(state: Row | null) {
  const w = { readerCalls: 0, intake: { id: 'ii-zz-cut', email: EMAIL, status: 'needs_info', turns: [], customer_id: 'c-zz-cut', category: 'aluminium', brief: {} } as Row };
  const stub: Stub = {
    user: { id: 'u-zz-cut', email: EMAIL },
    rows: { customers: [{ id: 'c-zz-cut', locale: 'en' }], category_specs: [{ category: 'aluminium', label: 'Aluminium', fields: FIELDS }],
      taxonomy_trade: [], taxonomy_trade_service: [], trade_spec_checklist: [], sales_knowledge: [] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      const r = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1];
      if (u.pathname.startsWith('/functions/v1/')) {
        const body = await req.clone().json().catch(() => ({}));
        if (body.fn === 'inquiry_intake' && body.response_format) return J({ ok: true, content: JSON.stringify(MODEL), model: 'stub/model' });
        // every other model call (the exact-spec reader among them) is cut at the turn's clock
        w.readerCalls++;
        return J({ ok: false, error: 'gateway_deadline', detail: 'turn_deadline' }, 502);
      }
      if (r) return J(r === 'rl_check' ? true : null);
      if (t === 'inquiry_state' && req.method === 'GET') return J(state ? [state] : []);
      if (t === 'inquiry_intake') {
        if (req.method === 'GET') return J([{ ...w.intake }]);
        if (req.method === 'PATCH') { Object.assign(w.intake, await req.clone().json()); return J([]); }
      }
      return undefined;
    },
  };
  return { w, stub };
}
const fnOf = () => loadFunction('inquiry_intake', () => import('./index.ts'));
const STATE = { conv_key: 'intake:ii-zz-cut', surface: 'request_chat', specs: { location: { value: 'Dubai Marina, Dubai', turn: 2, src: 'request_chat' } }, unknown: {}, asked: { location: { count: 1 } }, message_count: 4, status: 'open', trade_codes: [] };

Deno.test('the reading is cut and the brief omits a spec the conversation answered: the spec is not asked again', async () => {
  const { stub } = world(STATE);
  const r = await invoke(await fnOf(), stub, { intake_id: 'ii-zz-cut', text: 'ZZ DEMO yes, sliding windows as I said', turn_id: 't-zz-cut-1', lang: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.json).slice(0, 400));
  const asked = [...((r.json.missing_keys as string[]) ?? []), ...((r.json.questions as string[]) ?? [])].join(' | ');
  assert(!/location|emirate/i.test(asked), 'the location recorded on turn 2 is asked again: ' + asked);
  assertEquals(r.json.next_question && (r.json.next_question as Row).key === 'location', false, 'the next question is the recorded spec');
});

Deno.test('control: with nothing recorded, the same cut turn asks for the location (the gate still holds)', async () => {
  const { stub } = world({ ...STATE, specs: {} });
  const r = await invoke(await fnOf(), stub, { intake_id: 'ii-zz-cut', text: 'ZZ DEMO sliding windows please', turn_id: 't-zz-cut-2', lang: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.json).slice(0, 400));
  assertEquals(r.json.status, 'needs_info');
  assert(((r.json.missing_keys as string[]) ?? []).includes('location'), JSON.stringify(r.json).slice(0, 400));
});

Deno.test('a spec the portal assistant recorded is not taken as this chat\'s answer: it is asked', async () => {
  // the portal assistant keeps whole customer sentences under its own plan ids; 'location' is one of them (review of 12 Nov)
  const { stub } = world({ ...STATE, specs: { location: { value: 'ZZ DEMO we have a villa somewhere near the marina I think, not sure yet', turn: 1, src: 'portal_assistant' } } });
  const r = await invoke(await fnOf(), stub, { intake_id: 'ii-zz-cut', text: 'ZZ DEMO sliding windows please', turn_id: 't-zz-cut-3', lang: 'en' });
  assertEquals(r.status, 200, JSON.stringify(r.json).slice(0, 400));
  assert(((r.json.missing_keys as string[]) ?? []).includes('location'), JSON.stringify(r.json).slice(0, 400));
});

Deno.test('recordedSpecs: this chat\'s state over the row, no other surface, no codes, no empty values', () => {
  const rc = (value: string) => ({ value, src: 'request_chat' });
  assertEquals(recordedSpecs({ specs: { location: rc('Dubai'), service_keys: rc('x'), blank: rc(' '), scope: { value: 'a whole sentence', src: 'portal_assistant' }, size: { value: 'no src' } } },
    { location: 'Sharjah', element: 'Doors', qty: 4 }),
    { location: 'Dubai', element: 'Doors', qty: '4' });
  assertEquals(recordedSpecs(null, null), {});
});
