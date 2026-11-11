// site_assistant/limit_chain.ts: a widget turn's rate-limit buckets are spent in ONE round trip (fn_rl_check_chain), with
// exactly the buckets and the answers the old one-call-per-bucket path gave (it_engineer, 11 Nov 2026, load test round 2).
//   DENO_NO_PACKAGE_JSON=1 deno test --no-lock --allow-read=. supabase/functions/site_assistant/limit_chain.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { _resetChainForTest, hitFrom, prefetchLimits, widgetChain, type Hit, type Step } from './limit_chain.ts';
import { pastVisitorCap } from './visitor_scope.ts';

// A bucket store and rl_check, the way the database counts them; the chain RPC is the SQL file's rule over the same store.
function store(limits: Record<string, number>) {
  const used = new Map<string, number>(); const calls: string[] = [];
  const spend = (k: string, l: number) => { const n = used.get(k) ?? 0; if (n >= (limits[k] ?? l)) return false; used.set(k, n + 1); return true; };
  const rl: Hit = (k, l) => { calls.push('rl_check ' + k); return Promise.resolve(spend(k, l)); };
  const rpc = (fn: string, args: Record<string, unknown>) => {
    calls.push(fn);
    if (fn !== 'fn_rl_check_chain') return Promise.resolve({ data: null, error: { code: 'PGRST202', message: 'no such function' } });
    let go = true;
    const data = (args.p_groups as Step[][]).map((g) => { const row = g.map((s) => (go ? spend(s.k, s.l) : null)); if (go && row.includes(false)) go = false; return row; });
    return Promise.resolve({ data, error: null });
  };
  return { used, calls, rl, rpc };
}

// index.ts's own limiter logic, exactly as it reads (hard, then start+conv together, then global; then the visitor cap).
async function turn(hit: Hit, c: Parameters<typeof widgetChain>[0]) {
  let ipOk: boolean;
  if (c.hasConv) {
    const hardOk = await hit('site_assistant_ip_hard:' + c.ip, c.ipHardLimit, 3600);
    const [startOk, convOk] = !hardOk ? [false, false] : await Promise.all([c.firstTurn ? hit('site_assistant_ipconv:' + c.ip, c.ipLimit, 3600) : Promise.resolve(true), hit(c.rlKey, c.rlLimit, 3600)]);
    ipOk = hardOk && startOk && convOk;
  } else ipOk = await hit(c.rlKey, c.rlLimit, 3600);
  const globalOk = ipOk ? await hit(c.globalKey, c.dayLimit, 86400) : true;
  const capped = ipOk && globalOk && !c.who ? await pastVisitorCap(hit, { ip: c.ip, conv: c.conv, cap: { conv: c.capConv, ip: c.capIp } }) : null;
  return { ipOk, globalOk, capped };
}
const base = { who: false, hasConv: true, firstTurn: true, ip: '198.18.0.9', conv: 'c1', rlKey: 'site_assistant_conv:198.18.0.9:c1', rlLimit: 15,
  ipLimit: 10, ipHardLimit: 80, globalKey: 'site_assistant_global_day', dayLimit: 1500, capConv: 8, capIp: 40 };

Deno.test('one round trip, and the same buckets spent and the same answers as one call per bucket, in every refusal position', async () => {
  const shapes = [base, { ...base, firstTurn: false }, { ...base, hasConv: false, conv: '', rlKey: 'site_assistant_ip:198.18.0.9' },
    { ...base, who: true, hasConv: false, conv: '', rlKey: 'site_assistant_acct:a@example.invalid', rlLimit: 60 }];
  for (const c of shapes) {
    const keys = widgetChain(c).flat().map((s) => s.k);
    // every bucket full in turn (limit 0 = refuses), and none full
    for (const full of [null, ...keys]) {
      const limits = full ? { [full]: 0 } : {};
      const old = store(limits); const oldOut = await turn(old.rl, c);
      _resetChainForTest();
      const now = store(limits); const pre = await prefetchLimits(now.rpc, widgetChain(c));
      const newOut = await turn(hitFrom(pre, now.rl), c);
      const label = (c.who ? 'signed in' : c.hasConv ? 'conv' + (c.firstTurn ? ' first' : '') : 'no conv') + ', full=' + full;
      assertEquals(newOut, oldOut, label + ': a different answer');
      assertEquals([...now.used].sort(), [...old.used].sort(), label + ': different buckets spent');
      assertEquals(now.calls, ['fn_rl_check_chain'], label + ': more than one round trip: ' + now.calls.join(', '));
      assert(old.calls.length >= 1);
    }
  }
});

Deno.test('a database without fn_rl_check_chain: one call per bucket as before, and the chain is not asked again for a while', async () => {
  _resetChainForTest();
  const missing = { ...store({}), rpc: (fn: string) => { missing.calls.push(fn); return Promise.resolve({ data: null, error: { code: 'PGRST202', message: 'Could not find the function public.fn_rl_check_chain(p_groups)' } }); } };
  const pre = await prefetchLimits(missing.rpc, widgetChain(base));
  assertEquals(pre, null);
  const out = await turn(hitFrom(pre, missing.rl), base);
  assertEquals(out, { ipOk: true, globalOk: true, capped: false });
  assertEquals(missing.calls.filter((c) => c.startsWith('rl_check')).length, 6, 'the old path spends hard, start, conv, global, cap conv, cap ip');
  missing.calls.length = 0;
  assertEquals(await prefetchLimits(missing.rpc, widgetChain(base)), null);
  assertEquals(missing.calls, [], 'the missing function was asked again on the next turn');
  // a failure that is not "missing" (a timeout) falls back for this turn only
  _resetChainForTest();
  const flaky = (_fn: string) => Promise.resolve({ data: null, error: { code: '57014', message: 'canceling statement due to statement timeout' } });
  assertEquals(await prefetchLimits(flaky, widgetChain(base)), null);
  let asked = 0; await prefetchLimits((fn) => { asked++; return flaky(fn); }, widgetChain(base)); assertEquals(asked, 1);
});

Deno.test('index.ts spends the chain first and answers every limiter question through it', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const code = src.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');
  assert(/const hitP = prefetchLimits\(\(fn, args\) => admin\.rpc\(fn, args\), widgetChain\(/.test(code), 'the chain is not prefetched');
  const rate = code.slice(code.indexOf('const pRate = (async () => {'), code.indexOf('return { ipOk, globalOk };'));
  assert(rate.length > 100 && !/\brl\(/.test(rate), 'the rate block calls rl() directly again');
  assert(/pastVisitorCap\(await hitP, /.test(code), 'the visitor cap is not answered from the chain');
});
