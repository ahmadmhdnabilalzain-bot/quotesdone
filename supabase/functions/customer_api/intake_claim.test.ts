// One ready intake posts one request (lib/intake_claim.ts; customer-journey audit 10 Nov 2026).
//   deno test -A --no-lock --node-modules-dir=none supabase/functions/customer_api/intake_claim.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { claimIntake, releaseIntake } from './lib/intake_claim.ts';

// A one-row table whose conditional update behaves as Postgres does: the row changes only when every eq() matches now.
function table(row: Record<string, unknown>) {
  return {
    row,
    from: (_t: string) => {
      let patch: Record<string, unknown> = {}; const where: [string, unknown][] = [];
      const b: Record<string, unknown> = {};
      const run = () => { const hit = where.every(([k, v]) => row[k] === v); if (hit) Object.assign(row, patch); return { data: hit ? [{ id: row.id }] : [], error: null }; };
      Object.assign(b, {
        update: (p: Record<string, unknown>) => { patch = p; return b; },
        eq: (k: string, v: unknown) => { where.push([k, v]); return b; },
        select: async () => run(),
        then: (res: (v: unknown) => void) => res(run()),
      });
      return b;
    },
  };
}

Deno.test('two posts of one ready intake: exactly one claims it', async () => {
  const t = table({ id: 'I1', email: 'zz@example.invalid', status: 'ready' });
  const [a, b] = await Promise.all([claimIntake(t, 'I1', 'zz@example.invalid'), claimIntake(t, 'I1', 'zz@example.invalid')]);
  assertEquals([a, b].filter(Boolean).length, 1);
  assertEquals(t.row.status, 'consumed');
});

Deno.test('another customer\'s intake, or one already consumed, is not claimed', async () => {
  assertEquals(await claimIntake(table({ id: 'I1', email: 'zz@example.invalid', status: 'ready' }), 'I1', 'other@example.invalid'), false);
  assertEquals(await claimIntake(table({ id: 'I1', email: 'zz@example.invalid', status: 'consumed' }), 'I1', 'zz@example.invalid'), false);
});

Deno.test('a post that saved nothing hands the intake back, so Send works again', async () => {
  const t = table({ id: 'I1', email: 'zz@example.invalid', status: 'ready' });
  assert(await claimIntake(t, 'I1', 'zz@example.invalid'));
  await releaseIntake(t, 'I1');
  assertEquals(t.row.status, 'ready');
  assert(await claimIntake(t, 'I1', 'zz@example.invalid'));
});

Deno.test('create_inquiry claims the intake before it writes any request, and hands it back on every failed save', async () => {
  const src = await Deno.readTextFile(new URL('./actions/inquiry_create.ts', import.meta.url));
  const create = src.slice(src.indexOf("if (action === 'create_inquiry')"));
  const claim = create.indexOf('claimIntake(admin');
  const firstInsert = Math.min(...['wantSplit) {', "from('inquiries').insert("].map((s) => create.indexOf(s)).filter((i) => i >= 0));
  assert(claim > 0 && claim < firstInsert, 'the claim comes before the first request is written');
  assert(/already_posted/.test(create), 'a post that loses the claim is told the request was already sent');
  assertEquals((create.match(/releaseIntake\(admin/g) || []).length, 3, 'split_failed, and the turnkey and single insert failures, hand the intake back');
  assert(!/update\(\{ status: 'consumed' \}\)/.test(create), 'no second, late consume after matching');
});
