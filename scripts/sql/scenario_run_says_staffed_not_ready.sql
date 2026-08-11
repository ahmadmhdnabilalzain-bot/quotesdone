-- =================================================================================================
-- last_run STOPS MEANING "REHEARSED", BECAUSE NOTHING HAS EVER REHEARSED A SCENARIO.
--
-- THIS FIX MAKES A CHECK FAIL, ON PURPOSE. s34-stress-six-scenarios goes 6 of 6 -> 0 of 6.
-- The old pass was false and this is what correcting it looks like.
--
-- WHAT WAS WRONG
-- The Row #3 check reads:
--     from public.scenario_library where last_run > now() - interval '180 days'
-- and describes what it finds as scenarios that "exist and were exercised in 180d".
--
-- The only writer of last_run is fn_scenario_run, and fn_scenario_run does not exercise anything.
-- It checks that the departments a scenario names exist, are active, are staffed and have a
-- lead_agent. Its own output has always said so in plain English:
--     "...This verifies the organisation can answer the scenario; it does not claim the failure
--      itself was rehearsed."
-- So the honest sentence was already in the data, and the column it was written next to meant
-- something else. 19 of 19 scenarios showed a last_run; 0 of 19 had been rehearsed.
--
-- Measured before changing anything: all 19 rows carry a last_run, all 19 last_result values begin
-- with 'ORG READINESS', and 0 came from any other origin. So every last_run in the table was
-- written by the staffing checker and moving them loses no rehearsal history, because there is
-- none to lose.
--
-- WHAT CHANGES
--   1. Two new columns record what fn_scenario_run actually measures.
--   2. fn_scenario_run writes those and no longer touches last_run/last_result.
--   3. The 19 existing values move across, and last_run is cleared.
--   4. The verdict word 'ready' becomes 'staffed'. A status is read faster than a paragraph, and
--      'READY' next to a failure scenario reads as "we are ready for this failure". We are not.
--
-- last_run / last_result now mean one thing only: a real rehearsal drove this failure and this is
-- what happened. The dress rehearsal in NEXT_SESSION_BRIEF_2026_08_12_REHEARSAL.md is what will
-- legitimately write to them, one scenario at a time.
-- =================================================================================================

alter table public.scenario_library add column if not exists last_staffing_check timestamptz;
alter table public.scenario_library add column if not exists last_staffing_result text;

comment on column public.scenario_library.last_staffing_check is
  'When fn_scenario_run last confirmed the named departments exist, are active, staffed and led. '
  'NOT a rehearsal. Does not mean the failure was simulated.';
comment on column public.scenario_library.last_run is
  'When this failure was actually driven end to end. Written only by a real rehearsal. '
  'Cleared 11 Aug 2026 because every prior value was a staffing check, not a rehearsal.';

-- Move, do not delete. Guarded on the marker so a genuine rehearsal written after this migration
-- is never overwritten if the file is applied twice.
update public.scenario_library
   set last_staffing_check = coalesce(last_staffing_check, last_run),
       last_staffing_result = coalesce(last_staffing_result, last_result),
       last_run = null,
       last_result = null
 where last_result like 'ORG READINESS%';

CREATE OR REPLACE FUNCTION public.fn_scenario_run(p_scenario_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  s public.scenario_library%rowtype;
  v_named text[]; v_missing text[] := '{}'; v_unstaffed text[] := '{}'; v_unmanaged text[] := '{}';
  v_dept text; v_verdict text; v_result text; v_staff int;
begin
  select * into s from public.scenario_library where scenario_key = p_scenario_key;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'no scenario '||p_scenario_key);
  end if;

  v_named := coalesce(s.departments, '{}'::text[]);
  if array_length(v_named, 1) is null then
    -- A scenario that names nobody cannot be answered by anybody. That is a finding, not a pass.
    v_verdict := 'gap';
    v_result  := 'NOT RUNNABLE: the scenario names no department, so there is no owner to respond.';
  else
    foreach v_dept in array v_named loop
      if not exists (select 1 from public.org_departments d
                      where d.dept_key = v_dept and coalesce(d.active, true)) then
        v_missing := v_missing || v_dept;
      else
        select count(*) into v_staff from public.org_agents a
         where a.department = v_dept and coalesce(a.active, true);
        if coalesce(v_staff, 0) = 0 then v_unstaffed := v_unstaffed || v_dept; end if;
        -- org_departments names its manager in lead_agent; there is no manager_key on this table.
        if not exists (select 1 from public.org_departments d
                        where d.dept_key = v_dept
                          and nullif(btrim(coalesce(d.lead_agent, '')), '') is not null)
        then v_unmanaged := v_unmanaged || v_dept; end if;
      end if;
    end loop;

    if array_length(v_missing, 1) is not null or array_length(v_unstaffed, 1) is not null then
      v_verdict := 'gap';
    elsif array_length(v_unmanaged, 1) is not null then
      v_verdict := 'staffed_unmanaged';
    else
      -- WAS 'ready'. A one-word status is read faster than the paragraph that qualifies it, and
      -- 'READY' beside "OpenRouter becomes unavailable" reads as "we are ready for that outage".
      -- What was actually checked is that somebody is employed to answer it.
      v_verdict := 'staffed';
    end if;

    v_result := format(
      'ORG STAFFING %s. %s department(s) named: %s. Absent or inactive: %s. Active but unstaffed: %s. Staffed but unmanaged: %s. Checked against org_departments and org_agents at %s UTC. THIS IS A STAFFING CHECK, NOT A REHEARSAL: the failure was not simulated and nothing here says the organisation would survive it.',
      upper(v_verdict), array_length(v_named, 1), array_to_string(v_named, ', '),
      coalesce(nullif(array_to_string(v_missing, ', '), ''), 'none'),
      coalesce(nullif(array_to_string(v_unstaffed, ', '), ''), 'none'),
      coalesce(nullif(array_to_string(v_unmanaged, ', '), ''), 'none'),
      to_char(now() at time zone 'utc', 'YYYY-MM-DD HH24:MI'));
  end if;

  -- WRITES THE STAFFING COLUMNS ONLY. last_run belongs to a real rehearsal and this is not one.
  update public.scenario_library
     set last_staffing_check = now(), last_staffing_result = v_result
   where scenario_key = p_scenario_key;

  return jsonb_build_object('ok', true, 'scenario_key', p_scenario_key, 'verdict', v_verdict,
    'is_rehearsal', false,
    'departments', to_jsonb(v_named), 'missing', to_jsonb(v_missing),
    'unstaffed', to_jsonb(v_unstaffed), 'unmanaged', to_jsonb(v_unmanaged), 'result', v_result);
end $function$;
