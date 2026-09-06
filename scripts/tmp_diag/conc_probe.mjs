// CAN THIS HARNESS HOLD TWO CONCURRENT BACKENDS AT ONCE?
//
// The recorded blocker on PD-CONC-001 says two concurrent sessions are unavailable. That is a claim
// about the transport, and a blocker is a claim too. The management endpoint runs each POST in its
// own transaction on its own backend -- so two POSTs issued at the same moment ARE two sessions,
// and a transaction that sleeps holds its locks for the other one to collide with.
//
// This proves the mechanism before anything is built on it: two overlapping statements, their
// backend pids, and their start/end instants.
import { q } from './q.mjs';

const one = async (tag) => {
  const t0 = Date.now();
  const r = await q(`select pg_backend_pid() pid,
                            clock_timestamp()::text started,
                            pg_sleep(4) is null slept,
                            clock_timestamp()::text ended`);
  return { tag, pid: r[0].pid, started: r[0].started, ended: r[0].ended, ms: Date.now() - t0 };
};

const [a, b] = await Promise.all([one('A'), one('B')]);
for (const r of [a, b]) console.log(`${r.tag} pid=${r.pid} ${r.started} -> ${r.ended} (${r.ms}ms wall)`);
const overlap = a.started < b.ended && b.started < a.ended;
console.log(`\ndistinct backends : ${a.pid !== b.pid}`);
console.log(`overlapped in time: ${overlap}`);
console.log(overlap && a.pid !== b.pid
  ? 'TWO CONCURRENT SESSIONS ARE AVAILABLE to this harness.'
  : 'the two statements were serialised; concurrency is NOT available this way.');
