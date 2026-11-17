// Run: deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/_shared/rate_gate.test.ts
// A limiter that cannot answer is 'down', never 'ok' (security audit 17 Nov 2026, finding 5).
import { assertEquals, assertMatch } from 'jsr:@std/assert@1';
import { rateGate } from './rate_gate.ts';

const rpcAnswering = (answer: () => Promise<{ data: unknown; error: unknown }>) => {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return { calls, rpc: (fn: string, args: Record<string, unknown>) => { calls.push({ fn, args }); return answer(); } };
};

Deno.test('the limiter answering yes or no is passed on, with the key, limit and window it was asked', async () => {
  const yes = rpcAnswering(async () => ({ data: true, error: null }));
  assertEquals(await rateGate(yes.rpc, 'k:1', 10, 600), 'ok');
  assertEquals(yes.calls, [{ fn: 'rl_check', args: { p_key: 'k:1', p_limit: 10, p_seconds: 600 } }]);
  assertEquals(await rateGate(rpcAnswering(async () => ({ data: false, error: null })).rpc, 'k', 1, 1), 'limited');
});

Deno.test('an error or a throw from the limiter is down, never a yes', async () => {
  assertEquals(await rateGate(rpcAnswering(async () => ({ data: null, error: { message: 'connection reset' } })).rpc, 'k', 1, 1), 'down');
  assertEquals(await rateGate(rpcAnswering(async () => { throw new Error('timeout'); }).rpc, 'k', 1, 1), 'down');
});

// The two limiters the audit named must use this answer, and must not keep a private copy that says yes on a fault.
Deno.test('complaint_status and kyc ask the limiter through rateGate and refuse when it is down', async () => {
  for (const f of ['supabase/functions/complaint_status/index.ts', 'supabase/functions/kyc/index.ts']) {
    const src = await Deno.readTextFile(f);
    assertMatch(src, /import \{ rateGate[^}]*\} from '\.\.\/_shared\/rate_gate\.ts';/, f + ' does not use the shared gate');
    assertEquals(/rpc\('rl_check'/.test(src), false, f + ' still calls rl_check itself');
    assertEquals(/if \(error\) return true/.test(src), false, f + ' still answers yes when the limiter errors');
    assertMatch(src, /=== 'down'/, f + ' never refuses on a limiter outage');
  }
});
