// deno test supabase/functions/resilience_ping/archive_rounds.test.ts
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { anotherRound, ARCHIVE_ROUNDS_MAX, ARCHIVE_WALL_MS, isolateOffsets, type SliceOut } from './archive_rounds.ts';

const ok = (offset: number, archived: number, deferred = 0): SliceOut => ({ offset, status: 200, result: { ok: true, archived, deferred } });
const killed = (offset: number): SliceOut => ({ offset, status: 546, result: null });

Deno.test('a backlog the budget deferred gets another round, inside the round cap and the wall', () => {
  const r = [ok(0, 2, 2), ok(4, 4), ok(8, 4), ok(12, 4)];
  assert(anotherRound(r, 0, 5_000));
  assert(!anotherRound([ok(0, 4), ok(4, 4), ok(8, 0), ok(12, 0)], 0, 5_000), 'nothing deferred: one round');
  assert(!anotherRound(r, ARCHIVE_ROUNDS_MAX - 1, 5_000), 'the round cap holds');
  assert(!anotherRound(r, 0, ARCHIVE_WALL_MS + 1), 'the wall holds');
  // 4 rounds of 4 slices of up to 4: the 64 an hour of 6 Oct is still reachable in one tick when the queue is long
  assert(ARCHIVE_ROUNDS_MAX * 4 * 4 >= 16 * 4);
});

Deno.test('KNOWN-BAD control: a slice killed by one oversized message is re-run one message per worker', () => {
  // the 546 body is the platform's {code:'WORKER_LIMIT'} JSON: it is not the sweep's answer
  const dead: SliceOut = { offset: 4, status: 546, result: { code: 'WORKER_LIMIT' } as never };
  assertEquals(isolateOffsets([ok(0, 4), dead, ok(8, 3), ok(12, 4)], 4), [0, 1, 2, 3], 're-based for the 4 that slice 0 archived');
  assertEquals(isolateOffsets([killed(0), ok(4, 4)], 4), [0, 1, 2, 3]);
  assertEquals(isolateOffsets([{ offset: 8, status: 0, result: null }, ok(0, 1), ok(4, 0)], 4), [7, 8, 9, 10]);
  assertEquals(isolateOffsets([ok(0, 4), ok(4, 4)], 4), [], 'every slice answered: nothing to isolate');
});

Deno.test('the heartbeat runs rounds and isolates dead slices', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assertMatch(src, /const iso = isolateOffsets\(sweeps, ARCHIVE_BATCH\);/);
  assertMatch(src, /iso\.map\(\(o\) => one\(o, 1\)\)/);
  assertMatch(src, /if \(!anotherRound\(sweeps, round, Date\.now\(\) - t0\)\) break;/);
});
