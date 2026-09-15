// deno test supabase/functions/dropbox_backup/drain.test.ts
// A run that stops early hands back every row it claimed and never reached, at once.
import { assertEquals } from 'jsr:@std/assert@1';
import { AuthUnavailable } from './dropbox.ts';
import { drainClaim, type DrainHooks } from './drain.ts';

const rows = [1, 2, 3, 4, 5].map((id) => ({ id }));
function hooks(process: (r: { id: number }) => Promise<void>, over: Partial<DrainHooks<{ id: number }>> = {}) {
  const log = { processed: [] as number[], failed: [] as number[], requeued: [] as number[], released: [] as number[] };
  const h: DrainHooks<{ id: number }> = {
    deadline: Infinity,
    process: async (r) => { log.processed.push(r.id); await process(r); },
    fail: (r) => { log.failed.push(r.id); return Promise.resolve(); },
    requeue: (r) => { log.requeued.push(r.id); return Promise.resolve(); },
    release: (ids) => { log.released.push(...ids); return Promise.resolve(ids.length); },
    ...over,
  };
  return { h, log };
}

Deno.test('no_dropbox_auth fails the row in hand loudly and releases the rest now', async () => {
  const { h, log } = hooks((r) => r.id === 2 ? Promise.reject(new Error('no_dropbox_auth')) : Promise.resolve());
  const d = await drainClaim(rows, h);
  assertEquals(log.failed, [2]);
  assertEquals(log.released, [3, 4, 5]);
  assertEquals(d, { failed: 1, released: 3, authUnavailable: '', notes: ['#2: no_dropbox_auth'] });
});

Deno.test('an unavailable token endpoint fails nothing: the row in hand is requeued, the rest released', async () => {
  const { h, log } = hooks((r) => r.id === 1 ? Promise.reject(new AuthUnavailable('oauth2/token 429')) : Promise.resolve());
  const d = await drainClaim(rows, h);
  assertEquals(log.failed, []);
  assertEquals(log.requeued, [1]);
  assertEquals(log.released, [2, 3, 4, 5]);
  assertEquals([d.failed, d.released, d.authUnavailable], [0, 5, 'oauth2/token 429']);
});

Deno.test('the deadline releases the row in hand and everything after it', async () => {
  let t = 0;
  const { h, log } = hooks(() => { t += 10; return Promise.resolve(); }, { deadline: 20, now: () => t });
  const d = await drainClaim(rows, h);
  assertEquals(log.processed, [1, 2]);
  assertEquals(log.released, [3, 4, 5]);
  assertEquals(d.released, 3);
});

Deno.test('any other error fails that one row and the walk goes on; nothing to release', async () => {
  const { h, log } = hooks((r) => r.id === 3 ? Promise.reject(new Error('dbx_upload 409 path/conflict')) : Promise.resolve());
  const d = await drainClaim(rows, h);
  assertEquals(log.processed, [1, 2, 3, 4, 5]);
  assertEquals(log.failed, [3]);
  assertEquals(log.released, []);
  assertEquals(d.released, 0);
});
