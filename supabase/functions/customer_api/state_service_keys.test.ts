// The request carries the service keys the customer chose (inquiry_state.specs.service_keys, written by the expert-advice
// catalogue) from the moment it is created; with none, service_keys stays NULL ("never derived") and dispatch reads the
// brief as before. 10 Nov 2026, sales_engineer; founder ledger 1573/1579. lib/state_service_keys.ts.
import { assertEquals } from 'jsr:@std/assert@1';
import { keysOfTrade, serviceKeyCols, stateKeysForIntake } from './lib/state_service_keys.ts';

const LIVE = [{ trade_code: 'wallpaper', code: 'wall_panels' }, { trade_code: 'wallpaper', code: 'film_wrap' }, { trade_code: 'gypsum', code: 'false_ceiling' }];
function fake(state: Record<string, unknown> | null, stateError = false) {
  const asked: string[] = [];
  return {
    asked,
    from: (t: string) => {
      const b: Record<string, unknown> = {};
      const keep: Record<string, unknown> = {};
      Object.assign(b, {
        select: () => b, in: () => b,
        eq: (c: string, v: unknown) => { keep[c] = v; if (c === 'conv_key') asked.push(String(v)); return b; },
        maybeSingle: async () => (t === 'inquiry_state' ? (stateError ? { data: null, error: { message: 'relation "inquiry_state" does not exist' } } : { data: state, error: null }) : { data: null, error: null }),
        then: (res: (v: unknown) => void) => res({ data: t === 'taxonomy_trade_service' ? LIVE : [], error: null }),
      });
      return b;
    },
    rpc: async (_fn: string, args: { p_slugs: string[] }) => ({ data: args.p_slugs[0] === 'fitout' ? ['interior_fitout'] : args.p_slugs[0] === 'wallpaper' ? ['wallpaper'] : [], error: null }),
  };
}

Deno.test('the chosen keys of the request chat are carried, live ones only, read from its own conversation key', async () => {
  const a = fake({ specs: { service_keys: { value: 'wallpaper.wall_panels, wallpaper.film_wrap, wallpaper.retired, not a key' } } });
  assertEquals(await stateKeysForIntake(a, 'abc'), ['wallpaper.film_wrap', 'wallpaper.wall_panels']);
  assertEquals(a.asked, ['intake:abc']);
});

Deno.test('no state, no keys, or no table yet: nothing is carried and service_keys stays NULL', async () => {
  assertEquals(await stateKeysForIntake(fake(null), 'abc'), []);
  assertEquals(await stateKeysForIntake(fake({ specs: {} }), 'abc'), []);
  assertEquals(await stateKeysForIntake(fake(null, true), 'abc'), []);
  assertEquals(serviceKeyCols([]), {});
  assertEquals(serviceKeyCols(['wallpaper.wall_panels']), { service_keys: ['wallpaper.wall_panels'] });
});

Deno.test('a split child carries only the keys of its own trade', async () => {
  const keys = ['gypsum.false_ceiling', 'wallpaper.wall_panels'];
  assertEquals(await keysOfTrade(fake(null), keys, 'wallpaper'), ['wallpaper.wall_panels']);
  assertEquals(await keysOfTrade(fake(null), keys, 'fitout'), []);
});
