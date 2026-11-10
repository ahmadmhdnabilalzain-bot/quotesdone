// The summary card's supplier count asks what dispatch asks (supplier_count.ts). No network: a fake rpc.
// Run: deno test --no-lock --node-modules-dir=none supabase/functions/inquiry_intake/supplier_count.test.ts
import { assertEquals, assert } from 'jsr:@std/assert@1';
import { supplierCount, taxonomyTrades } from './supplier_count.ts';

const CODES: Record<string, string[]> = { glass: ['glass', 'glazing'], fitout: ['fitout', 'interior_fitout'], 'carpentry-joinery': ['carpentry_joinery', 'joinery'], aluminium: ['aluminium'] };
function fake(registered: Record<string, number>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const rpc = async (fn: string, args: Record<string, unknown>) => {
    calls.push({ fn, args });
    if (fn === 'fn_taxonomy_trades_for') return { data: (args.p_slugs as string[]).flatMap((s) => CODES[s] ?? []), error: null };
    if (fn === 'fn_match_capability') {
      const n = (args.p_trades as string[]).reduce((k, c) => k + (registered[c] ?? 0), 0);
      return { data: Array.from({ length: Math.min(n, Number(args.p_limit)) }, (_, i) => ({ id: i })), error: null };
    }
    return { data: null, error: { message: 'unknown rpc' } };
  };
  return { rpc, calls };
}

Deno.test('a slug that is not a taxonomy code is resolved before the matcher, as dispatch does (glass is glazing)', async () => {
  const f = fake({ glazing: 3, interior_fitout: 2, joinery: 1 });
  for (const [slug, want] of [['glass', 3], ['fitout', 2], ['carpentry-joinery', 1]] as const) {
    const c = await supplierCount(f, { trades: [slug], emirate: 'Dubai', services: [] });
    assertEquals(c.count, want, slug + ' was counted on the raw slug');
  }
  const m = f.calls.filter((c) => c.fn === 'fn_match_capability').map((c) => c.args.p_trades);
  assertEquals(m, [['glass', 'glazing'], ['fitout', 'interior_fitout'], ['carpentry_joinery', 'joinery']]);
});

Deno.test('the count keeps the services, the emirate and the dispatch limit; a failed resolver leaves the slugs', async () => {
  const f = fake({ aluminium: 40 });
  const c = await supplierCount(f, { trades: ['aluminium'], emirate: 'Sharjah', services: ['aluminium.windows'] });
  assertEquals(c.count, 24);
  const args = f.calls.find((x) => x.fn === 'fn_match_capability')!.args;
  assertEquals([args.p_emirate, args.p_services, args.p_limit, args.p_need], ['Sharjah', ['aluminium.windows'], 24, 'executes']);
  assert(/fn_taxonomy_trades_for/.test(c.basis));
  const broken = async (fn: string) => fn === 'fn_taxonomy_trades_for' ? { data: null, error: { message: 'down' } } : { data: [], error: null };
  assertEquals(await taxonomyTrades({ rpc: broken }, ['glass']), ['glass']);
  assertEquals(await taxonomyTrades({ rpc: broken }, []), []);
});
