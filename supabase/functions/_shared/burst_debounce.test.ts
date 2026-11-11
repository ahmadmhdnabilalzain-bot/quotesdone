// Several messages in a few seconds get one reply (burst_debounce.ts). Run: deno test supabase/functions/_shared/burst_debounce.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { BURST_MAX_MS, BURST_QUIET_MS, combinedBody, FOLLOWER_GRACE_MS, mergeable, planBurst, quietFrom, type ArrivalRow } from './burst_debounce.ts';

const row = (id: number, at: number, o: Partial<ArrivalRow> = {}): ArrivalRow => ({ id, at, stage: 'received', burst: null, media: 0, inbound: 'msg ' + id, ...o });

Deno.test('one message alone: it waits the quiet time from its arrival, then answers itself with nothing merged', () => {
  const me = { id: 10, at: 0 };
  assertEquals(planBurst(me, [row(10, 0)], 1_000), { kind: 'wait', ms: BURST_QUIET_MS - 1_000 });
  assertEquals(planBurst(me, [row(10, 0)], BURST_QUIET_MS), { kind: 'lead', merge: [] });
});

Deno.test('a burst: the first message waits until the newest is quiet, then takes the later ones; the later ones follow', () => {
  const rows = [row(10, 0), row(11, 1_500), row(12, 3_000)];
  // the first: still going at 5 s (the newest arrived at 3 s), leads at 7 s with both later messages
  assertEquals(planBurst({ id: 10, at: 0 }, rows, 5_000), { kind: 'wait', ms: 2_000 });
  const lead = planBurst({ id: 10, at: 0 }, rows, 7_000);
  assertEquals(lead.kind === 'lead' ? lead.merge.map((r) => r.id) : null, [11, 12]);
  // the last: an earlier message is still waiting, so it follows, until the leader's moment plus the grace
  assertEquals(planBurst({ id: 12, at: 3_000 }, rows, 7_000), { kind: 'follow', ms: FOLLOWER_GRACE_MS });
});

Deno.test('the burst is never waited on past BURST_MAX_MS from its first message', () => {
  const rows = [row(1, 0), ...Array.from({ length: 8 }, (_, i) => row(2 + i, (i + 1) * 2_000))];   // one every 2 s for 16 s
  const p = planBurst({ id: 1, at: 0 }, rows.filter((r) => r.at <= BURST_MAX_MS), BURST_MAX_MS);
  assertEquals(p.kind, 'lead');
});

Deno.test('a document, a voice note, a claimed or answered row is never merged; an earlier claimed leader is not waited for', () => {
  assert(!mergeable(row(1, 0, { media: 1 })));
  assert(!mergeable(row(1, 0, { burst: 'lead' })));
  assert(!mergeable(row(1, 0, { stage: 'handled' })));
  assert(!mergeable(row(1, 0, { inbound: '  ' })));
  // the earlier message's turn already claimed itself (it is answering): this one leads itself after its own quiet time
  const p = planBurst({ id: 2, at: 1_000 }, [row(1, 0, { burst: 'lead' }), row(2, 1_000)], 1_000 + BURST_QUIET_MS);
  assertEquals(p, { kind: 'lead', merge: [] });
});

Deno.test('the setting: a whole number of ms up to 8 s, 0 turns it off, anything else is the default', () => {
  assertEquals(quietFrom('0'), 0);
  assertEquals(quietFrom('3000'), 3_000);
  assertEquals(quietFrom('99999'), 8_000);
  assertEquals(quietFrom(''), BURST_QUIET_MS);
  assertEquals(quietFrom('stub-secret-value'), BURST_QUIET_MS);
});

Deno.test('the combined message keeps every line, in the order they arrived', () => {
  assertEquals(combinedBody('hi', [row(12, 3, { inbound: 'for 12 windows' }), row(11, 2, { inbound: 'I need a quote' })]), 'hi\nI need a quote\nfor 12 windows');
});
