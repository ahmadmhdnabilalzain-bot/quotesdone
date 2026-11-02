// deno test supabase/functions/_shared/not_reached.test.ts
import { assert } from 'jsr:@std/assert';
import { notReached, platformRefused } from './not_reached.ts';

Deno.test('a relay 502/503 with no runtime header did nothing and may be asked again', () => {
  for (const s of [502, 503, 521, 522, 523]) assert(platformRefused(s, null), String(s));
  assert(platformRefused(503, 'base/server'));   // the main worker could not start a user worker in 10 s
  assert(notReached(new Response('<html>502</html>', { status: 502, headers: { server: 'cloudflare' } })));
});

Deno.test('KNOWN-BAD control: anything a worker answered, and every timeout, is never treated as unreached', () => {
  assert(!platformRefused(546, 'supabase-edge-runtime'));
  assert(!platformRefused(502, 'supabase-edge-runtime'));
  assert(!platformRefused(503, 'Supabase-Edge-Runtime'));
  for (const s of [504, 520, 524, 500, 200, 404]) assert(!platformRefused(s, null), String(s));
});
