// Run: deno test --node-modules-dir=none supabase/functions/customer_api/reveal_rate.test.ts
// The reveal rate is read from pricing_config or the reveal is refused; never a guessed 0.03.
import { assertEquals } from 'jsr:@std/assert@1';
import { readRevealRate, recordRateUnreadable } from './reveal_rate.ts';

const fakeAdmin = (answer: () => Promise<{ data: any; error: any }>) => {
  const rpcs: { fn: string; args: any }[] = [];
  return {
    rpcs,
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: answer }) }) }),
    rpc: async (fn: string, args: any) => { rpcs.push({ fn, args }); return { data: null, error: null }; },
  };
};

Deno.test('a readable rate is returned as read', async () => {
  const r = await readRevealRate(fakeAdmin(async () => ({ data: { standard_reveal_rate: '0.03', refund_window_working_days: 5 }, error: null })));
  assertEquals(r.ok && r.cfg.standard_reveal_rate, 0.03);
});

Deno.test('an unreadable, missing or nonsensical rate is refused, never defaulted', async () => {
  const cases: (() => Promise<{ data: any; error: any }>)[] = [
    async () => ({ data: null, error: { message: 'connection reset' } }),
    async () => { throw new Error('timeout'); },
    async () => ({ data: null, error: null }),
    async () => ({ data: { standard_reveal_rate: null }, error: null }),
    async () => ({ data: { standard_reveal_rate: 0 }, error: null }),
    async () => ({ data: { standard_reveal_rate: 3 }, error: null }), // 300%: a percent typed as a fraction
  ];
  for (const c of cases) {
    const r = await readRevealRate(fakeAdmin(c));
    assertEquals(r.ok, false);
    assertEquals('cfg' in r, false, 'no rate, guessed or otherwise');
  }
});

Deno.test('the refusal is recorded as a finding the accountant raised', async () => {
  const a = fakeAdmin(async () => ({ data: null, error: null }));
  await recordRateUnreadable(a, 'customer_api getCfg -> pricing_config', 'pricing_config_missing');
  assertEquals(a.rpcs.length, 1);
  assertEquals([a.rpcs[0].fn, a.rpcs[0].args.p_raised_by], ['fn_it_engineer_finding_upsert', 'accountant']);
});
