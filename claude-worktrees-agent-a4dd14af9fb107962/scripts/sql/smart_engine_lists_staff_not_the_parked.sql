-- SMART ENGINE SHOWS THE STAFF; THE PARKED ARE A SEPARATE LIST.
--
-- Measured 6 Sep 2026: org_agents holds 96 rows, 54 active (the STAFF_ORG roster) and 42 parked
-- (active = false, 0 runs, a last_status of "error" left over from before they were parked).
-- fn_agents_board listed all 96 in its departments, rows and org chart while its header said
-- "54 agents" — because 'total' counted everything and nothing filtered on active.
--
-- Now: 'total', 'runs24', 'departments' (and their cards) and 'rows' are the ACTIVE roster only;
-- the parked come back as 'parked' with last_status nulled (a parked persona has no status, and
-- "error" was a stale run from its previous life). The UI shows them greyed behind a toggle.
--
--   node scripts/apply_sql.mjs scripts/sql/smart_engine_lists_staff_not_the_parked.sql --apply --ddl
CREATE OR REPLACE FUNCTION public.fn_agents_board()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare out jsonb;
begin
  with runs as (
    select agent, count(*) filter (where started_at > now() - interval '24 hours') as runs24,
           count(*) filter (where started_at > now() - interval '24 hours' and status in ('error','failed')) as fails24,
           max(started_at) as last_run, (array_agg(status order by started_at desc))[1] as last_status
    from agent_runs group by agent
  ), everyone as (
    select a.agent_key, coalesce(nullif(trim(a.department),''),'General') as department, a.role, a.kind, coalesce(a.active,true) as active,
      coalesce(r.runs24,0) as runs24, coalesce(r.fails24,0) as fails24, r.last_run, r.last_status
    from org_agents a left join runs r on r.agent = a.agent_key
  ), base as (select * from everyone where active),
  dc as (select department, count(*) c, sum(runs24) rs from base group by department)
  select jsonb_build_object(
    'total',(select count(*) from base),
    'parked_total',(select count(*) from everyone where not active),
    'runs24',(select coalesce(sum(runs24),0) from base),
    'departments',(select coalesce(jsonb_agg(jsonb_build_object('key',d.department,'label',d.department,'count',d.c,'runs',d.rs,
        'cards',(select jsonb_agg(jsonb_build_object('id',b.agent_key,'agent_key',b.agent_key,'role',b.role,'kind',b.kind,'active',b.active,'runs24',b.runs24,'fails24',b.fails24,'last_status',b.last_status,'last_run',b.last_run) order by b.runs24 desc, b.agent_key) from base b where b.department=d.department))
        order by d.rs desc nulls last, d.department),'[]'::jsonb) from dc d),
    'rows',(select coalesce(jsonb_agg(jsonb_build_object('id',b.agent_key,'agent_key',b.agent_key,'department',b.department,'role',b.role,'kind',b.kind,'active',b.active,'runs24',b.runs24,'fails24',b.fails24,'last_status',b.last_status,'last_run',b.last_run) order by b.runs24 desc, b.agent_key),'[]'::jsonb) from base b),
    -- Parked personas: greyed in the UI, labelled "parked", never "error". No run figures either —
    -- a persona that is not on the roster has no run rate, only a history.
    'parked',(select coalesce(jsonb_agg(jsonb_build_object('id',e.agent_key,'agent_key',e.agent_key,'department',e.department,'role',e.role,'kind',e.kind,'active',false,'runs24',0,'fails24',0,'last_status',null,'last_run',e.last_run) order by e.department, e.agent_key),'[]'::jsonb) from everyone e where not e.active)
  ) into out; return out;
end $function$;
