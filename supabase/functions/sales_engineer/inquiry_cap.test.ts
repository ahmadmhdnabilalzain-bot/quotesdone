// The portal chat at its 100-message limit becomes a held request for the sales engineer (lib/inquiry_cap.ts). No network:
// a fake admin records every write.
// Run: deno test --no-lock --node-modules-dir=none supabase/functions/sales_engineer/inquiry_cap.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { handOffAtCap } from './lib/inquiry_cap.ts';

function fakeAdmin() {
  const w = { rows: [] as Record<string, unknown>[], rpcs: [] as { fn: string; args: Record<string, unknown> }[] };
  const chain = (table: string) => {
    const q: Record<string, unknown> = {};
    const api = {
      select: () => api, eq: (k: string, v: unknown) => { q[k] = v; return api; }, limit: () => Promise.resolve({ data: table === 'inquiry_intake' ? w.rows.filter((r) => (r.brief as { carried_from?: string })?.carried_from === q['brief->>carried_from']) : [], error: null }),
      maybeSingle: () => Promise.resolve({ data: table === 'customers' ? { email: 'zz-demo-cap@example.invalid' } : null, error: null }),
      insert: (row: Record<string, unknown>) => { const r = { id: '00000000-0000-4000-8000-00000000000' + (w.rows.length + 1), ...row }; w.rows.push(r);
        return { select: () => ({ maybeSingle: () => Promise.resolve({ data: { id: r.id }, error: null }) }) }; },
    };
    return api;
  };
  return { w, admin: { from: chain, rpc: (fn: string, args: Record<string, unknown>) => { w.rpcs.push({ fn, args }); return Promise.resolve({ data: fn === 'fn_seat_handoff' ? 4242 : {}, error: null }); } } };
}

const transcript = [{ role: 'user' as const, content: 'old job' }, { role: 'assistant' as const, content: 'Here it is. Is this correct?' }, { role: 'user' as const, content: 'yes' },
  { role: 'user' as const, content: 'I need my MDF partition clad, 2.4 x 1.2 m.' }, { role: 'assistant' as const, content: 'PVC panels or a film wrap?' }];

Deno.test('at message 100 the job becomes a held request with its whole transcript, its state carried and one handoff', async () => {
  const { w, admin } = fakeAdmin();
  const r = await handOffAtCap(admin, { customerId: 'c-zz', episodeKey: 'a-c-c-zz#3', transcript, from: 3, category: 'wallpaper', open: ['finish', 'timing'] });
  assertEquals([r.created, r.handoffId], [true, 4242]);
  assertEquals(w.rows.length, 1);
  const row = w.rows[0] as { status: string; turns: { text: string; carried: string }[]; brief: Record<string, unknown> };
  assertEquals(row.status, 'held');
  assertEquals(row.turns.map((t) => t.text), ['I need my MDF partition clad, 2.4 x 1.2 m.', 'PVC panels or a film wrap?'], 'the job from its episode start, nothing before');
  assert(row.turns.every((t) => t.carried === 'portal'));
  assertEquals(row.brief.carried_from, 'a-c-c-zz#3');
  const fns = w.rpcs.map((x) => x.fn);
  assert(fns.includes('fn_inquiry_state_carry'), fns.join(','));
  const h = w.rpcs.find((x) => x.fn === 'fn_seat_handoff')!.args;
  assertEquals([h.p_type, h.p_from, h.p_to, h.p_subject_table], ['spec.not_sure', 'customer_support', 'sales_engineer', 'inquiry_intake']);
  assertEquals((h.p_payload as { not_sure: string[] }).not_sure, ['finish', 'timing']);
  assert(w.rpcs.filter((x) => x.fn === 'fn_inquiry_state_merge').every((x) => (x.args.p_patch as { status: string }).status === 'handed_off'));
});

Deno.test('past message 100 the same call writes no second request', async () => {
  const { w, admin } = fakeAdmin();
  await handOffAtCap(admin, { customerId: 'c-zz', episodeKey: 'a-c-c-zz#3', transcript, from: 3, category: null, open: [] });
  const again = await handOffAtCap(admin, { customerId: 'c-zz', episodeKey: 'a-c-c-zz#3', transcript, from: 3, category: null, open: [] });
  assertEquals([again.created, w.rows.length], [false, 1]);
  assert(again.intakeId === (w.rows[0] as { id: string }).id);
});
