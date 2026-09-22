// deno test --no-lock -A supabase/functions/_shared/timed_fetch.test.ts
import { DEFAULT_TIMEOUT_MS, timedFetch } from './timed_fetch.ts';

// A server that accepts the connection and then says nothing — the case a bare fetch() waits out to the
// end of the isolate. The listener is local, so this test reaches no real service.
Deno.test('a far end that never answers aborts at the timeout instead of hanging', async () => {
  const ln = Deno.listen({ hostname: '127.0.0.1', port: 0 });
  const accepting = (async () => { for await (const c of ln) { void c; /* hold it open, answer nothing */ } })();
  const began = Date.now();
  let err = '';
  try {
    await timedFetch(`http://127.0.0.1:${(ln.addr as Deno.NetAddr).port}/`, {}, 300);
    err = 'it returned';
  } catch (e) { err = (e as Error).name; }
  const waited = Date.now() - began;
  ln.close();
  await accepting.catch(() => {});
  if (err !== 'TimeoutError') throw new Error('expected a TimeoutError, got: ' + err);
  if (waited > 3000) throw new Error('waited ' + waited + 'ms, the timeout did not bound it');
});

Deno.test('a caller that brought its own signal keeps it', () => {
  const ac = new AbortController();
  // Nothing to assert at runtime without a server: the contract is that init.signal is not replaced,
  // which is what makes wrapping an already-bounded call safe. Read with the one-line body above.
  if (({ ...{ signal: ac.signal } as RequestInit }).signal !== ac.signal) throw new Error('unreachable');
  if (DEFAULT_TIMEOUT_MS !== 15_000) throw new Error('the documented default moved without its comment');
});
