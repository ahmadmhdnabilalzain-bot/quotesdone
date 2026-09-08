import { sql, lit } from '../lib/db.mjs';
const q = (tag) => `select ${lit(tag)} as tag,
  pg_backend_pid() as pid,
  clock_timestamp()::text as t_start,
  (select count(*) from pg_stat_activity where state='active' and query like '%QDCONCPROBE%') as active_probes,
  pg_sleep(3) is null as slept,
  clock_timestamp()::text as t_end
  -- QDCONCPROBE`;
const t0 = Date.now();
const [a, b] = await Promise.all([sql(q('A')), sql(q('B'))]);
console.log(JSON.stringify({ wall_ms: Date.now() - t0, a: a[0], b: b[0] }, null, 1));
