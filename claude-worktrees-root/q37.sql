select a.pid, a.application_name, a.state, a.wait_event_type, a.wait_event, pg_blocking_pids(a.pid) blockers,
 (select jsonb_agg(jsonb_build_object('pid',b.pid,'app',b.application_name,'state',b.state,'age',now()-b.xact_start,'q',left(b.query,150))) from pg_stat_activity b where b.pid = any(pg_blocking_pids(a.pid))) who
from pg_stat_activity a where a.application_name like 'qd-apply%';
