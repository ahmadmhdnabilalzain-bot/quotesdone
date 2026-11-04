// DRILL D10, client side (docs/release/qualification_matrix.md §5.1): Postgres restarting, or its
// connection pool exhausted, while a customer is describing a job. Seat accountable: it_engineer.
// The matrix does not inject this on production; offline, the REAL inquiry_intake handler runs with
// fetch and env stubbed (_shared/twilio_free_harness.ts) and PostgREST answering the turn's write the
// way it does when the database is gone: 503 PGRST000 "Database connection error. Retrying the
// connection." and 504 PGRST003 "Timed out acquiring connection from connection pool.".
//
// Why this path: the customer's RFQ is the write a lost row hurts most. The intake row IS the request;
// if a turn is lost the customer's words never reach a supplier and nothing else holds them.
// supabase-js retries only GET/HEAD on 503/520 (postgrest-js fetchWithRetry); a PATCH or a POST is never
// retried by the library, so the handler must either retry or say so.
//
// Expected, in the matrix's terms:
//   safe      no success is reported for a turn that was not saved: the customer is told to send it
//             again (the portal resends a turn with the same turn_id, which placeUserTurn makes a no-op
//             if it did land), never shown a reply as if the message were recorded
//   visible   an agent_runs row at error level under 'inquiry_intake' names the lost write
//   recovery  the same turn resent after the database is back is saved once
//
// The positive control: the same turn with the database up is saved and answered ok.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';

type Row = Record<string, unknown>;
const EMAIL = 'zz-demo-d10-customer@example.invalid';
const DOWN = {
  'PGRST000 503': { status: 503, body: { code: 'PGRST000', details: 'connection to server failed', hint: null, message: 'Database connection error. Retrying the connection.' } },
  'PGRST003 504': { status: 504, body: { code: 'PGRST003', details: null, hint: null, message: 'Timed out acquiring connection from connection pool.' } },
};

// Two places a turn is saved: the HELD branch (no trade reasoned yet, the model unavailable, which is
// what the stub gives) and the INTERVIEW branch (the trade already reasoned on an earlier turn, so the
// deterministic interview runs and the turn is saved at the end).
const ALUMINIUM_FIELDS = [
  { key: 'element', type: 'text', options: [], question: 'What aluminium work?', required: true },
  { key: 'location', type: 'text', options: [], question: 'Which emirate and area?', required: true },
];
function world(fail: { status: number; body: unknown } | null, branch: 'held' | 'interview' = 'held') {
  const reasoned = branch === 'interview' ? { category: 'aluminium', brief: { category: 'aluminium', category_by: 'reasoning' } } : {};
  const w = { saves: [] as Row[], failedSaves: 0, runs: [] as Row[], intake: { id: 'ii-zz-d10', email: EMAIL, status: 'needs_info', turns: [] as Row[], customer_id: 'c-zz-d10', ...reasoned } as Row };
  const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
  const state = { fail };
  const stub: Stub = {
    user: { id: 'u-zz-d10', email: EMAIL },
    rows: { customers: [{ id: 'c-zz-d10', locale: 'en' }], category_specs: [{ category: 'aluminium', fields: ALUMINIUM_FIELDS }] },
    rpc: { rl_check: true },
    handle: async (req, u) => {
      const t = u.pathname.match(/^\/rest\/v1\/([^/]+)$/)?.[1];
      if (t === 'agent_runs' && req.method === 'POST') { w.runs.push(await req.clone().json().catch(() => ({}))); return J([], 201); }
      if (t === 'inquiry_intake') {
        if (req.method === 'GET') return J([{ ...w.intake }]);
        if (req.method === 'POST') return J({ ...w.intake }, 201);
        if (req.method === 'PATCH') {
          if (state.fail) { w.failedSaves++; return J(state.fail.body, state.fail.status); }
          const body = await req.clone().json(); w.saves.push(body); Object.assign(w.intake, body); return J([]);
        }
      }
      return undefined;
    },
  };
  return { w, stub, state };
}
const turn = (turnId: string) => ({ intake_id: 'ii-zz-d10', turn_id: turnId, lang: 'en',
  text: 'ZZ DEMO D10: we need 40 aluminium windows supplied and installed for a villa in Dubai Marina, 1200 x 1500 mm, double glazed.' });
const fn = () => loadFunction('inquiry_intake', () => import('./index.ts'));
const errorRuns = (w: { runs: Row[] }) => w.runs.filter((r) => r.agent === 'inquiry_intake' && r.status === 'error');

for (const branch of ['held', 'interview'] as const) {
Deno.test(`D10 positive control (${branch} branch): with the database up, the turn is saved and answered`, async () => {
  const h = await fn();
  const { w, stub } = world(null, branch);
  const r = await invoke(h, stub, turn('t-zz-d10-up'));
  assertEquals(r.status, 200, JSON.stringify(r.json));
  assertEquals(r.json.ok, true);
  assertEquals(r.json.status === 'held', branch === 'held', 'the drill reached the ' + branch + ' branch: ' + r.json.status);
  assert(w.saves.length >= 1, 'the turn was written to inquiry_intake');
  assert((w.saves.at(-1)!.turns as Row[]).some((x) => x.role === 'user'), 'the customer\'s words are in the saved row');
});

for (const [label, fail] of Object.entries(DOWN)) {
  Deno.test(`D10 database ${label} on the turn's save (${branch} branch): no success is reported, the loss is logged, the resend is saved`, async () => {
    const h = await fn();
    const { w, stub, state } = world(fail, branch);
    const r = await invoke(h, stub, turn('t-zz-d10-' + fail.status));
    assert(w.failedSaves >= 1, 'the drill reached the write');
    assertEquals(w.saves.length, 0);
    // safe: a turn that was not saved is not answered as if it were
    assert(r.status >= 500, 'the caller is told the turn was not saved (got ' + r.status + ' ' + JSON.stringify(r.json).slice(0, 200) + ')');
    assert(r.json?.ok !== true, 'no ok:true for a lost write');
    // visible
    assert(errorRuns(w).some((x) => /could not be saved|failed to persist|not saved/i.test(String(x.note))), 'an error row names the lost write');
    // recovery: the database comes back and the portal resends the same turn
    state.fail = null;
    const again = await invoke(h, stub, turn('t-zz-d10-' + fail.status));
    assertEquals(again.status, 200, JSON.stringify(again.json));
    assertEquals((w.intake.turns as Row[]).filter((x) => x.role === 'user').length, 1, 'the resent turn is saved once');
  });
}
}
