-- The live definition of fn_model_autoswitch, written back into a file.
--
-- 14 Aug 2026 the autoswitch stopped counting our own zero-token client timeouts as model
-- failure. That change was applied by token surgery on the dumped routine and never landed in
-- scripts/sql, so the repository disagreed with production. This file is that definition verbatim.

CREATE OR REPLACE FUNCTION public.fn_model_autoswitch()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_new text; v_n int := 0;
begin
  for r in
    select o.task_class, o.model_used,
           avg(case when o.ok then 1.0 else 0.0 end) sr, count(*) n
    from ai_cost_log o
    where o.occurred_at > now() - interval '14 days'
      and o.task_class is not null
      and o.model_used is not null
      -- ONLY CALLS THAT REACHED THE MODEL MAY JUDGE IT (14 Aug 2026). A row with no prompt
      -- tokens and no output tokens never got there: it is our own client/gateway abort and
      -- belongs to latency, not to model selection. Sixteen such rows scored
      -- chief_of_staff_decision at 75.4%% and bought opus-4.8 at ~2.3x — a slower model, to
      -- answer a timeout. See scripts/sql/the_autoswitch_repriced_our_own_timeouts.sql.
      and (coalesce(o.prompt_tokens,0) > 0 or coalesce(o.output_tokens,0) > 0)
      -- ONLY CALLS THAT REACHED THE MODEL MAY JUDGE IT (14 Aug 2026). A row with no prompt
      -- tokens and no output tokens never got there: it is our own client/gateway abort and
      -- belongs to latency, not to model selection. Sixteen such rows scored
      -- chief_of_staff_decision at 75.4%% and bought opus-4.8 at ~2.3x — a slower model, to
      -- answer a timeout. See scripts/sql/the_autoswitch_repriced_our_own_timeouts.sql.
      and (coalesce(o.prompt_tokens,0) > 0 or coalesce(o.output_tokens,0) > 0)
    group by 1,2 having count(*) >= 20
       and avg(case when o.ok then 1.0 else 0.0 end) < 0.85
  loop
    -- only act if this model is still the primary for that class
    if not exists (select 1 from model_policy p where p.task_class = r.task_class
                    and p.model_primary = r.model_used and p.active) then continue; end if;

    select mr.model_id into v_new from model_registry mr
     join model_registry cur on cur.model_id = r.model_used
     where mr.active and mr.approved and mr.in_per_mtok_usd > cur.in_per_mtok_usd
     order by mr.in_per_mtok_usd asc limit 1;
    if v_new is null then continue; end if;

    update model_policy set model_primary = v_new where task_class = r.task_class and active;
    v_n := v_n + 1;

    insert into founder_alerts (level, event, detail, channel)
    values ('warn','model_autoswitched',
      'Task class "' || r.task_class || '" was failing on ' || r.model_used || ' (' ||
      round(r.sr*100,1) || '% success over ' || r.n || ' runs, floor 85%). Promoted to ' || v_new ||
      '. Cheaper is only correct while it works; this is the loop that checks.', 'system');

    insert into org_tasks (dept_key, title, detail, status, tier, action_class, needs_founder)
    values ('it', left('Model auto-switched for ' || r.task_class, 200),
      'Automatic promotion after measured failure. Class: ' || r.task_class ||
      E'\nWas: ' || r.model_used || ' at ' || round(r.sr*100,1) || '% success over ' || r.n || ' runs' ||
      E'\nNow: ' || v_new ||
      E'\n\nReview whether the prompt is at fault rather than the model - a badly specified task fails on every tier, and promoting it just costs more.',
      'proposed','supervised','analysis', false);
  end loop;
  return v_n;
end $function$
;
