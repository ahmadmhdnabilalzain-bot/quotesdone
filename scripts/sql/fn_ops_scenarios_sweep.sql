-- fn_ops_scenarios_sweep — run the pack's 282 scenarios and RECORD the verdict.
--
-- fn_ops_run_scenarios() already computes RUNNABLE/BLOCKED per scenario and is correct; it is a
-- pure reader, so ops_kb_stage.scenarios.last_run has said 2026-08-02 13:44 ever since and would
-- have kept saying it for ever. A last_run column that never moves is worse than no column: it
-- reads as "checked recently" on a screen.
--
-- This wraps the existing checker rather than restating its seven rules — one definition of
-- RUNNABLE, not two — writes the verdict back, and raises ONE incident when a scenario that used
-- to be runnable stops being runnable (a department losing its decision rules or its live-data
-- binding is exactly the drift the scenario suite exists to catch).
create or replace function public.fn_ops_scenarios_sweep()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_run int; v_block int; v_new_block int; v_keys text[];
begin
  with v as (select * from public.fn_ops_run_scenarios()),
  upd as (
    update ops_kb_stage.scenarios s
       set last_result = v.verdict, last_run = now()
      from v where v.scenario_id = s.record_id
      returning s.record_id, v.verdict, (s.last_result = 'RUNNABLE' and v.verdict = 'BLOCKED') as newly_blocked
  )
  select count(*) filter (where verdict = 'RUNNABLE'),
         count(*) filter (where verdict = 'BLOCKED'),
         count(*) filter (where newly_blocked),
         coalesce(array_agg(record_id) filter (where newly_blocked), '{}')
    into v_run, v_block, v_new_block, v_keys
    from upd;

  if coalesce(v_new_block,0) > 0 then
    insert into public.agent_actions(agent, kind, title, recommendation, detail, risk, status)
    values ('knowledge_eng', 'incident',
            format('%s operations scenario(s) became BLOCKED', v_new_block),
            'A department lost the decision rules, professional knowledge or live-data binding its scenarios depend on. Run select * from fn_ops_run_scenarios() where verdict = ''BLOCKED'' for the reasons.',
            jsonb_build_object('scenarios', to_jsonb(v_keys), 'source', 'fn_ops_scenarios_sweep'),
            'medium', 'pending');
  end if;

  return jsonb_build_object('runnable', v_run, 'blocked', v_block,
                            'newly_blocked', v_new_block, 'ran_at', now());
end $function$;

revoke execute on function public.fn_ops_scenarios_sweep() from public;
revoke execute on function public.fn_ops_scenarios_sweep() from anon;
revoke execute on function public.fn_ops_scenarios_sweep() from authenticated;

-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
