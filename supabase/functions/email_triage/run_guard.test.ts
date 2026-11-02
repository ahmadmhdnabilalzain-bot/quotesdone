// Known-bad control: a run row left open by a killed isolate (like agent_runs 4602652) is closed with its reason and last
// beat by the next run; a fresh open run (still working) and a finished run are untouched. A run killed while ANSWERING a
// triaged message reopens that message (and only that one, and only if nothing was sent), so it is answered exactly once.
// In-memory tables, no network.
import { assertEquals } from 'jsr:@std/assert';
import { beat, budgetLeft, closeStaleRuns } from './run_guard.ts';

type Row = Record<string, any>;
// A tiny PostgREST stand-in: eq / is / not / lt filters, update, select, over named tables. Enough for run_guard only.
function fake(tables: Record<string, Row[]>, failOn?: string) {
  return { from: (t: string) => {
    const preds: Array<(r: Row) => boolean> = [];
    let patch: Row | null = null;
    const q: any = {
      select: () => q,
      eq: (c: string, v: unknown) => { preds.push((r) => r[c] === v); return q; },
      is: (c: string, v: unknown) => { preds.push((r) => (r[c] ?? null) === v); return q; },
      not: (c: string, _op: string, v: unknown) => { preds.push((r) => (r[c] ?? null) !== v); return q; },
      lt: (c: string, v: string) => { preds.push((r) => r[c] < v); return q; },
      limit: () => q,
      update: (p: Row) => { patch = p; return q; },
      then: (res: (v: unknown) => void) => {
        if (failOn === t && patch) return res({ error: { message: 'boom' } });
        const hit = tables[t].filter((r) => preds.every((p) => p(r)));
        if (patch) { hit.forEach((r) => Object.assign(r, patch)); res({ error: null }); } else res({ data: hit.map((r) => ({ ...r })), error: null });
      },
    };
    return q;
  } };
}
const run = (id: number, started_at: string, finished_at: string | null = null, agent = 'email_triage'): Row => ({ id, agent, started_at, finished_at, status: 'ok', note: null });
// the selector index.ts reads messages by (needs_review, triaged_at, replied_at, owner_role all null / true)
const pickable = (m: Row) => m.needs_review === true && !m.triaged_at && !m.replied_at && !m.owner_role;
const msg = (id: number, over: Row = {}): Row => ({ id, needs_review: true, triaged_at: '2026-11-02T03:01:20Z', replied_at: null, owner_role: null, ...over });

Deno.test('a run killed mid-message is closed by the next run with the reason and the last beat', async () => {
  const now = Date.parse('2026-11-02T04:00:00Z');
  const rows = [
    run(1, '2026-11-02T03:01:11Z'),                                   // the killed one
    run(2, '2026-11-02T03:59:30Z'),                                   // still working
    run(3, '2026-11-02T02:00:00Z', '2026-11-02T02:00:02Z'),
    run(4, '2026-11-02T01:00:00Z', null, 'other'),
  ];
  const db = fake({ agent_runs: rows, inbound_messages: [] });
  await beat(db, 1, 'answer inbound 1615', Date.parse('2026-11-02T03:01:38Z'));
  assertEquals(await closeStaleRuns(db, 'email_triage', now), 1);
  assertEquals(rows[0].status, 'error');
  assertEquals(rows[0].finished_at !== null, true);
  assertEquals(rows[0].note!.includes('answer inbound 1615'), true);
  assertEquals(rows[1].finished_at, null);
  assertEquals(rows[3].finished_at, null);
  assertEquals(await closeStaleRuns(db, 'email_triage', now), 0);   // idempotent
});

Deno.test('a run killed after triage but before the answer: the message is picked up again and answered exactly once', async () => {
  const now = Date.parse('2026-11-02T04:00:00Z');
  const runs = [run(1, '2026-11-02T03:01:11Z')];
  const inbound = [
    msg(1615),                                  // triaged, was being answered, nothing sent  -> must come back
    msg(1616),                                  // triaged earlier in the same run, not the one in hand -> untouched
  ];
  const db = fake({ agent_runs: runs, inbound_messages: inbound });
  await beat(db, 1, 'message 1615 (answer)', Date.parse('2026-11-02T03:01:38Z'));
  assertEquals(inbound.some(pickable), false, 'before the fix this is where it stayed: triaged, unanswered, never selected again');

  assertEquals(await closeStaleRuns(db, 'email_triage', now), 1);
  assertEquals(inbound.filter(pickable).map((m) => m.id), [1615]);

  // the next run answers it: fn_inbox_send queues the reply and sets replied_at together
  let sent = 0;
  for (const m of inbound.filter(pickable)) { sent++; m.replied_at = '2026-11-02T04:01:00Z'; m.needs_review = false; m.triaged_at = '2026-11-02T04:00:59Z'; }
  assertEquals(sent, 1);
  // a later stale-run sweep (even one reading the same beat again) cannot reopen an answered message
  runs.push(run(2, '2026-11-02T03:05:00Z')); runs[1].note = 'in progress: message 1615 (answer) @ 2026-11-02T03:05:10.000Z';
  assertEquals(await closeStaleRuns(db, 'email_triage', now + 60_000), 1);
  assertEquals(inbound.filter(pickable).length, 0);
  assertEquals(sent, 1);
});

Deno.test('a message already answered, or handed to the ceo, is never reopened by the run that died after it', async () => {
  const now = Date.parse('2026-11-02T04:00:00Z');
  for (const over of [{ replied_at: '2026-11-02T03:01:30Z', needs_review: false }, { owner_role: 'ceo' }] as Row[]) {
    const runs = [run(1, '2026-11-02T03:01:11Z')];
    const inbound = [msg(7, over)];
    const db = fake({ agent_runs: runs, inbound_messages: inbound });
    await beat(db, 1, 'message 7 (answer)');
    assertEquals(await closeStaleRuns(db, 'email_triage', now), 1);
    assertEquals(inbound.some(pickable), false, 'reopening this would send a second reply: ' + JSON.stringify(over));
    assertEquals(inbound[0].triaged_at !== null, true);
  }
});

Deno.test('a failed reopen keeps the run open for the next sweep instead of forgetting the message', async () => {
  const now = Date.parse('2026-11-02T04:00:00Z');
  const runs = [run(1, '2026-11-02T03:01:11Z')];
  const inbound = [msg(9)];
  await beat(fake({ agent_runs: runs, inbound_messages: inbound }), 1, 'message 9 (answer)');
  assertEquals(await closeStaleRuns(fake({ agent_runs: runs, inbound_messages: inbound }, 'inbound_messages'), 'email_triage', now), 0);
  assertEquals(runs[0].finished_at, null);
  assertEquals(await closeStaleRuns(fake({ agent_runs: runs, inbound_messages: inbound }), 'email_triage', now), 1);
  assertEquals(inbound.filter(pickable).map((m) => m.id), [9]);
});

Deno.test('the batch budget stops new messages, never the one in hand', () => {
  assertEquals(budgetLeft(0, 89_000), true);
  assertEquals(budgetLeft(0, 90_000), false);
});
