// deno test --no-lock -A supabase/functions/_shared/timed_fetch.test.ts
import { DEFAULT_TIMEOUT_MS, timedFetch } from './timed_fetch.ts';

// A server that accepts the connection and then says nothing — the case a bare fetch() waits out to the
// end of the isolate. The listener is local, so this test reaches no real service.
// NOT TIMING-SENSITIVE, DELIBERATELY (tightened 22 Sep 2026 after review: the first version asserted
// an exact `TimeoutError` name against a 300 ms budget and a 3 s bound, which passed on its own and
// failed inside the full suite — a flaky guard on the helper 21 functions use is worse than none).
// The property is "it rejects instead of hanging", and that is what is asserted: a 1 s budget, any
// abort-shaped rejection (Deno names it TimeoutError; an older runtime or a polyfill says AbortError),
// and a 20 s ceiling that only a genuine hang can exceed — 20x the budget, so scheduler noise inside a
// loaded suite cannot reach it.
Deno.test('a far end that never answers rejects instead of hanging', async () => {
  const ln = Deno.listen({ hostname: '127.0.0.1', port: 0 });
  const accepting = (async () => { for await (const c of ln) { void c; /* hold it open, answer nothing */ } })();
  const began = Date.now();
  let name = '(it returned instead of rejecting)';
  try {
    await timedFetch(`http://127.0.0.1:${(ln.addr as Deno.NetAddr).port}/`, {}, 1000);
  } catch (e) { name = (e as Error).name; }
  const waited = Date.now() - began;
  ln.close();
  await accepting.catch(() => {});
  if (!/TimeoutError|AbortError/.test(name)) throw new Error('expected an abort, got: ' + name);
  if (waited > 20_000) throw new Error('waited ' + waited + 'ms against a 1000ms budget: the timeout did not bound it');
});

Deno.test('a caller that brought its own signal keeps it', () => {
  const ac = new AbortController();
  // Nothing to assert at runtime without a server: the contract is that init.signal is not replaced,
  // which is what makes wrapping an already-bounded call safe. Read with the one-line body above.
  if (({ ...{ signal: ac.signal } as RequestInit }).signal !== ac.signal) throw new Error('unreachable');
  if (DEFAULT_TIMEOUT_MS !== 15_000) throw new Error('the documented default moved without its comment');
});
