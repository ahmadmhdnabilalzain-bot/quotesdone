// Known-bad control: a run row left open by a killed isolate (like agent_runs 4602652) is closed with its reason and last
// beat by the next run; a fresh open run (still working) and a finished run are untouched. In-memory table, no network.
import { assertEquals } from 'jsr:@std/assert';
import { beat, budgetLeft, closeStaleRuns } from './run_guard.ts';

type Row = { id: number; agent: string; started_at: string; finished_at: string | null; status: string; note: string | null };
function fake(rows: Row[]) {
  return { from: (_t: string) => {
    const f: { agent?: string; id?: number; open?: boolean; before?: string } = {};
    const q: any = {
      select: () => q, eq: (c: string, v: unknown) => { if (c === 'agent') f.agent = String(v); if (c === 'id') f.id = Number(v); return q; },
      is: () => { f.open = true; return q; }, lt: (_c: string, v: string) => { f.before = v; return q; }, limit: () => q,
      update: (patch: Partial<Row>) => { q._patch = patch; return q; },
      then: (res: (v: unknown) => void) => {
        const hit = rows.filter((r) => (f.agent === undefined || r.agent === f.agent) && (f.id === undefined || r.id === f.id) && (!f.open || r.finished_at === null) && (!f.before || r.started_at < f.before));
        if (q._patch) { hit.forEach((r) => Object.assign(r, q._patch)); res({ error: null }); } else res({ data: hit.map((r) => ({ ...r })), error: null });
      },
    };
    return q;
  } };
}

Deno.test('a run killed mid-message is closed by the next run with the reason and the last beat', async () => {
  const now = Date.parse('2026-11-02T04:00:00Z');
  const rows: Row[] = [
    { id: 1, agent: 'email_triage', started_at: '2026-11-02T03:01:11Z', finished_at: null, status: 'ok', note: null },           // the killed one
    { id: 2, agent: 'email_triage', started_at: '2026-11-02T03:59:30Z', finished_at: null, status: 'ok', note: null },           // still working
    { id: 3, agent: 'email_triage', started_at: '2026-11-02T02:00:00Z', finished_at: '2026-11-02T02:00:02Z', status: 'ok', note: null },
    { id: 4, agent: 'other', started_at: '2026-11-02T01:00:00Z', finished_at: null, status: 'ok', note: null },
  ];
  const db = fake(rows);
  await beat(db, 1, 'answer inbound 1615', Date.parse('2026-11-02T03:01:38Z'));
  assertEquals(await closeStaleRuns(db, 'email_triage', now), 1);
  assertEquals(rows[0].status, 'error');
  assertEquals(rows[0].finished_at !== null, true);
  assertEquals(rows[0].note!.includes('answer inbound 1615'), true);
  assertEquals(rows[1].finished_at, null);
  assertEquals(rows[3].finished_at, null);
  assertEquals(await closeStaleRuns(db, 'email_triage', now), 0);   // idempotent
});

Deno.test('the batch budget stops new messages, never the one in hand', () => {
  assertEquals(budgetLeft(0, 89_000), true);
  assertEquals(budgetLeft(0, 90_000), false);
});
