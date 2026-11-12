// ONE OPEN DISPUTE PER CHARGE, AND NEVER AN EMPTY ONE (12 Nov 2026, sales_engineer, built by it_engineer; second review of the walk
// fixes, R3). Drives the real dispute_charge handler against an in-memory database (ZZ DEMO rows only, no network).
// Known-bad control: on 8fb0da128 a retry filed a second charge.disputed handoff (the subject carried Date.now()) and an empty reason
// was accepted, so the first and third tests fail there.
//   deno test --no-lock --node-modules-dir=none --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY supabase/functions/supplier_api/one_dispute_per_charge.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';

type Row = Record<string, unknown>;
const EMAIL = 'zz-demo-dispute@example.invalid';

function world() {
  const actions: Row[] = [];
  const handoffs: Row[] = [];
  const from = (table: string) => {
    const f: [string, string, unknown][] = [];
    const b: Record<string, unknown> = {};
    const self = () => b;
    const rows = (): Row[] => table === 'leads' ? [{ id: 41, claimed_by: EMAIL }]
      : table === 'supplier_dues' ? [{ id: 7, supplier_id: 41 }]
      : table === 'agent_actions' ? actions : [];
    const hit = () => rows().filter((r) => f.every(([op, k, v]) => op === 'eq' ? String(r[k]) === String(v)
      : op === 'like' ? new RegExp('^' + String(v).replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/%/g, '.*') + '$').test(String(r[k]))
      : op === 'notin' ? !String(v).replace(/[()]/g, '').split(',').includes(String(r[k])) : true));
    Object.assign(b, {
      select: self, limit: self, order: self,
      eq: (k: string, v: unknown) => { f.push(['eq', k, v]); return b; },
      like: (k: string, v: unknown) => { f.push(['like', k, v]); return b; },
      not: (k: string, op: string, v: unknown) => { if (op === 'in') f.push(['notin', k, v]); return b; },
      maybeSingle: () => Promise.resolve({ data: hit()[0] ?? null, error: null }),
    });
    return b;
  };
  const rpc = (fn: string, a: Record<string, unknown>) => {
    if (fn !== 'fn_seat_handoff') return Promise.resolve({ data: null, error: null });
    const id = 900 + handoffs.length;
    handoffs.push(a);
    actions.push({ id, kind: 'handoff', agent: a.p_to, status: 'pending', target_id: a.p_type + ':' + a.p_subject_id });
    return Promise.resolve({ data: id, error: null });
  };
  return { admin: { from, rpc }, actions, handoffs };
}

async function dispute(w: ReturnType<typeof world>, reason: unknown) {
  Deno.env.set('SUPABASE_URL', 'http://127.0.0.1:9'); Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-not-a-key');
  const ctx = await import('./context.ts');
  Object.assign(ctx.admin, { from: w.admin.from, rpc: w.admin.rpc });   // the handler's own client, pointed at the stub
  const { profileActions } = await import('./actions/profile.ts');
  const res = await profileActions({ req: new Request('http://127.0.0.1/', { method: 'POST' }), email: EMAIL, action: 'dispute_charge',
    body: { action: 'dispute_charge', due_id: 7, reason } } as never);
  return { status: res!.status, j: await res!.json() };
}

Deno.test('a retry of the same dispute files nothing new and is answered as received', async () => {
  const w = world();
  const a = await dispute(w, 'ZZ DEMO the interest looks doubled');
  const b = await dispute(w, 'ZZ DEMO the interest looks doubled');
  assertEquals([a.status, a.j.ok, b.status, b.j.ok, b.j.already_recorded], [200, true, 200, true, true]);
  assertEquals(w.handoffs.length, 1, 'a second charge.disputed handoff reached the accountant');
  assertEquals(b.j.handoff_id, a.j.handoff_id);
});

Deno.test('once the accountant has closed the dispute, a new one for the same charge goes through', async () => {
  const w = world();
  await dispute(w, 'ZZ DEMO first query');
  w.actions[0].status = 'done';
  const c = await dispute(w, 'ZZ DEMO a second, later query');
  assertEquals([c.status, c.j.already_recorded], [200, undefined]);
  assertEquals(w.handoffs.length, 2);
});

Deno.test('an empty or blank reason is refused by the server and files nothing', async () => {
  for (const r of ['', '   ', null]) {
    const w = world();
    const d = await dispute(w, r);
    assertEquals([d.status, d.j.code], [400, 'reason_required'], JSON.stringify(r));
    assert(w.handoffs.length === 0);
  }
});
