// THE DETACHED KICK IS NOT A CALL FROM resilience_ping TO ITSELF (it_engineer, 19 Nov 2026).
// Measured over 96 ticks (18-19 Nov): a tick that POSTed /resilience_ping to itself 3 or more times (the :00 and :30 ticks) hit
// the edge runtime's per-chain limit ("Rate limit exceeded for trace <the tick's request id>") and drained the outbox 9 of 48
// times; with at most 2, 47 of 48. The kick now goes through fn_resilience_detached_kick (pg_net, a chain of its own).
// Read from the source for the "no self-call" rule; the kick's answers are exercised with the client's rpc stubbed.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

const src: string = functionSource('resilience_ping');
const code = src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`])\/\/.*$/gm, '$1');

Deno.test('no code in resilience_ping fetches resilience_ping: a detached run is kicked through the database', () => {
  assertEquals((code.match(/['"`]\/resilience_ping\b|\/functions\/v1\/resilience_ping/g) || []).length, 0,
    'a fetch of FN + "/resilience_ping" is back: the kicked run shares the tick\'s request chain and its rate limit');
  assertMatch(code, /admin\.rpc\('fn_resilience_detached_kick', \{ p_name: name \}\)/);
  // every detached run is still kicked by name, from the tick or from inside another detached run
  for (const k of ['marketing', 'itlater', 'supportVoice', 'caseCatchup', 'heldReplay', 'routineJudgements']) assert(code.includes(`kickDetached('${k}')`), k);
});

Deno.test('the kick answers ok only when the database started it, and says why otherwise (a failed kick is still the step\'s finding)', async () => {
  Deno.env.set('SUPABASE_URL', Deno.env.get('SUPABASE_URL') || 'http://127.0.0.1:9');
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || 'zz-demo-not-a-key');
  const shared = await import('./shared.ts');
  const calls: unknown[] = [];
  const answer = (data: unknown, error: unknown = null) => {
    // deno-lint-ignore no-explicit-any
    (shared.admin as any).rpc = (fn: string, args: unknown) => { calls.push([fn, args]); return Promise.resolve({ data, error }); };
  };
  answer({ ok: true, started: true, request: 41 });
  assertEquals(await shared.kickDetached('supportVoice'), { ok: true, started: true, request: 41 });
  assertEquals(calls[0], ['fn_resilience_detached_kick', { p_name: 'supportVoice' }]);

  answer({ ok: false, started: true, request: 42, error: 'the detached supportVoice run kicked at 14:00 answered 401: unauthorized' });
  const prev = await shared.kickDetached('supportVoice') as { ok: boolean; error: string };
  assertEquals(prev.ok, false); assertMatch(prev.error, /answered 401/);

  answer({ ok: false, started: false, error: 'no db.internal credential or project ref' });
  assertEquals((await shared.kickDetached('marketing') as { ok: boolean }).ok, false);

  answer(null, { message: 'function public.fn_resilience_detached_kick(p_name => text) does not exist' });
  const missing = await shared.kickDetached('itlater') as { ok: boolean; error: string };
  assertEquals(missing.ok, false); assertMatch(missing.error, /does not exist/);

  answer({ ok: true });
  assertEquals((await shared.kickDetached('caseCatchup') as { ok: boolean }).ok, false, 'ok without started is not a start');
});
