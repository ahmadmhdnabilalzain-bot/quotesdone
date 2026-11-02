// A demo/fixture requester's ask for a person never reaches fn_review_request_open (which pages the founder); a real one does.
// Known-bad control: the same call with a real-looking number DOES open the request.
import { assertEquals } from 'jsr:@std/assert@1';
import type { ThinkDeps } from './think.ts';
import { fileReviewRequest } from './review_request.ts';

const J = JSON.stringify;
function run(requester: string) {
  const rpcs: string[] = []; const runs: Record<string, unknown>[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: false, rule: 'route_not_registered' } as never),
    llm: () => Promise.resolve({ content: J({ answer: 'They ask for a person.', decision: { choice: 'person' }, reasoning: ['s1: asked'], cited: [] }), model: 'mock' }),
    embed: () => Promise.resolve(null),
    rpc: () => Promise.resolve({ data: { cases: [] }, error: null }),
  };
  const admin = {
    rpc: (fn: string) => { rpcs.push(fn); return Promise.resolve({ data: { ok: true, id: 7, owner_seat: 'founder' }, error: null }); },
    from: (t: string) => t === 'review_route'
      ? { select: () => ({ order: () => Promise.resolve({ data: [{ decision_type: 'person', meaning: 'asking for a person' }], error: null }) }) }
      : { insert: (row: Record<string, unknown>) => { runs.push(row); return Promise.resolve({ error: null }); } },
  };
  return { rpcs, runs, go: () => fileReviewRequest(admin as never, deps, { channel: 'whatsapp', requester, message: 'I want to speak to a person', surface: 'test', dedupeKey: 'k' + requester }) };
}

Deno.test('a fixture number asking for a person is recorded suppressed and fn_review_request_open is never called', async () => {
  const t = run('whatsapp:+971500000094'); const r = await t.go();
  assertEquals(t.rpcs.filter((f) => f === 'fn_review_request_open'), []);
  assertEquals(r.filed, false);
  assertEquals(t.runs.length, 1);
  assertEquals(t.runs[0].status, 'skipped');
});

Deno.test('a demo e-mail asking for a person is suppressed the same way', async () => {
  const t = run('qd-abc-cust0@example.invalid'); await t.go();
  assertEquals(t.rpcs.filter((f) => f === 'fn_review_request_open'), []);
});

Deno.test('control: a real-looking number still opens the request (it pages the founder)', async () => {
  const t = run('whatsapp:+971501234567'); const r = await t.go();
  assertEquals(t.rpcs.filter((f) => f === 'fn_review_request_open').length, 1);
  assertEquals(r.filed, true);
  assertEquals(t.runs.length, 0);
});
