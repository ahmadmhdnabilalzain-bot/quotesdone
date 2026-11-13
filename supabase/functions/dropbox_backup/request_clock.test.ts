// The worker's clock is per request. Before 13 Nov 2026 it was a module-level constant, so a request reaching an isolate older
// than 110 s was past its deadline before it began (request_clock.ts carries the measurement).
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { BUDGET_MS, deadline, inRequest, t0 } from './request_clock.ts';

Deno.test('a request that reaches an old isolate still has its whole budget', async () => {
  const boot = 1_000_000;                       // the isolate started here and served its first request
  await inRequest(async () => { assertEquals(t0(), boot); }, boot);
  const later = boot + 200_000;                 // 200 s later, the same isolate serves another request
  await inRequest(async () => {
    assertEquals(t0(), later);
    assertEquals(deadline(), later + BUDGET_MS);
    assert(deadline() > later, 'with the module-level clock this deadline was boot + 110 s: already past');
  }, later);
});

Deno.test('two requests that overlap in one isolate keep their own clocks', async () => {
  const seen: number[] = [];
  const a = inRequest(async () => { await new Promise((r) => setTimeout(r, 20)); seen.push(t0()); return deadline(); }, 5_000);
  const b = inRequest(async () => { seen.push(t0()); return deadline(); }, 9_000);
  assertEquals(await b, 9_000 + BUDGET_MS);
  assertEquals(await a, 5_000 + BUDGET_MS);     // the later request did not move the earlier one's deadline
  assertEquals(seen, [9_000, 5_000]);
});

Deno.test('the worker keeps no start time at module level', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  const moduleLevelClock = src.split('\n').filter((l) => /^(const|let|var)\s+\w+\s*=.*Date\.now\(\)/.test(l));
  assertEquals(moduleLevelClock, []);
  assert(/Deno\.serve\(observe\('dropbox_backup', \(req: Request\) => inRequest\(\(\) => handle\(req\)\)\)\);/.test(src), 'every request runs inside inRequest');
});
