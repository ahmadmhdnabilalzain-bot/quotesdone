// sales_engineer — every call leaves an agent_runs row.
// Moved here verbatim from index.ts on 9 Nov 2026 (it_engineer: the 1,214-line index.ts split into modules, a pure move).
import { admin } from '../context.ts';

// EVERY CALL LEAVES A ROW. fn_agents_board LEFT JOINs agent_runs on agent = agent_key, so a seat
// that never writes one renders with runs24 = 0 — indistinguishable from a seat that is down.
// Neither existing agent does this; measured 9 Sep, agent_runs holds rows for send_outbox and
// login_otp only. Best-effort: attribution must never fail the call it is attributing.
export async function run(action: string, status: string, counts: Record<string, unknown>, note?: string) {
  try {
    await admin.from('agent_runs').insert({
      agent: 'sales_engineer',
      status,
      started_at: new Date().toISOString(),
      finished_at: new Date().toISOString(),
      counts: { action, ...counts },
      note: note ?? null,
    });
  } catch { /* an unwritten log must not turn a good answer into a 500 */ }
}
