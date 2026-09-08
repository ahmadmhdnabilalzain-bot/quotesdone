// Can a REAL race be staged? Two concurrent management calls, each a DO block taking the SAME
// transaction-scoped advisory lock and holding it 2s. If each call is its own transaction and the
// two are genuinely concurrent, they SERIALISE: total wall ~4s, not ~2s. xact locks release at
// commit, so nothing is left behind.
import { sql, lit } from '../lib/db.mjs';
const q = (tag) => `do $$
declare t0 timestamptz := clock_timestamp();
begin
  perform pg_advisory_xact_lock(918273645);
  perform pg_sleep(2);
  raise exception 'QDLOCK % pid=% waited_ms=% end=%', ${lit(tag)}, pg_backend_pid(),
    round(extract(epoch from (clock_timestamp()-t0))*1000), clock_timestamp();
end $$;`;
const run = async (t) => { try { await sql(q(t)); return 'no raise'; }
  catch (e) { const m = String(e.message); const i = m.indexOf('QDLOCK'); return i<0?m.slice(0,300):m.slice(i, i+140); } };
const t0 = Date.now();
const [a, b] = await Promise.all([run('A'), run('B')]);
console.log(JSON.stringify({ total_wall_ms: Date.now()-t0, a, b }, null, 1));
const left = await sql(`select count(*)::int n from pg_locks where locktype='advisory'`);
console.log('advisory locks still held:', JSON.stringify(left));
