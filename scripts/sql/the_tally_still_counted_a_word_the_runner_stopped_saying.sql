-- The tally still counted a word the runner stopped saying
-- ========================================================
--
-- scenario_library holds 32 named failure scenarios - Supabase outage, cyberattack, cash-flow
-- reduction, campaign failure, key supplier leaves, duplicate payment, and so on. Not one of them
-- has ever been checked, because fn_scenario_run_all() HAS NO CALLER: the hourly cron
-- ops_scenarios_hourly runs fn_ops_scenarios_sweep(), a different function entirely. Seventh
-- finished capability with no entry point this week.
--
-- AND THE TALLY IS WRONG, which is why wiring it up without reading it first would have been worse
-- than leaving it alone. fn_scenario_run was deliberately changed to return 'staffed' instead of
-- 'ready' - its own comment explains why: "'READY' beside 'OpenRouter becomes unavailable' reads as
-- 'we are ready for that outage'. What was actually checked is that somebody is employed to answer
-- it." The rename never reached fn_scenario_run_all, which still counts:
--
--     if verdict = 'ready' then ready+1; elsif verdict = 'partial' then partial+1;
--     else gap+1; end if;
--
-- 'staffed' and 'staffed_unmanaged' both fall into the else, so EVERY scenario is counted as a gap.
-- Measured: fn_scenario_run_all() returns ready=0 partial=0 gap=32, while running the same
-- scenarios individually returns 'staffed' for supabase_outage (engineering, it, exec - none
-- missing, none unstaffed) and 'staffed' for security_incident. The summary said the company cannot
-- answer a single one of its 32 failure scenarios. That is not what the runner found.
--
-- Same two-vocabularies defect as leads.invite_trades against taxonomy_trade, action_worker's
-- `outcome` against the extractor's three key names, and 'ai_budget_aed' against \yai\y - all four
-- found today. A counter and its source drifted apart and nothing failed, so nothing noticed.
--
-- LAST_RUN IS DELIBERATELY NOT TOUCHED. fn_scenario_run writes last_staffing_check and says so:
-- "last_run belongs to a real rehearsal and this is not one." s34-stress-six-scenarios asks for
-- last_run and stays MISSING, correctly - a staffing check is not a rehearsal, and stamping
-- last_run to satisfy the check would be exactly the fabrication that comment guards against.

create or replace function public.fn_scenario_run_all()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_out jsonb := '[]'::jsonb; v_one jsonb; v_v text;
        v_staffed int := 0; v_unmanaged int := 0; v_gap int := 0;
begin
  for r in select scenario_key from public.scenario_library order by scenario_key loop
    v_one := public.fn_scenario_run(r.scenario_key);
    v_v := v_one->>'verdict';
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'scenario_key', r.scenario_key, 'verdict', v_v));
    -- THE RUNNER'S OWN VOCABULARY, not the one it used to speak. See the header.
    if v_v = 'staffed' then v_staffed := v_staffed + 1;
    elsif v_v = 'staffed_unmanaged' then v_unmanaged := v_unmanaged + 1;
    else v_gap := v_gap + 1; end if;
  end loop;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('scenario_staffing', now(), now(), case when v_gap > 0 then 'error' else 'ok' end,
          jsonb_build_object('checked', jsonb_array_length(v_out), 'staffed', v_staffed,
                             'staffed_unmanaged', v_unmanaged, 'gap', v_gap),
          'Staffing-checked '||jsonb_array_length(v_out)||' failure scenario(s): '||v_staffed
          ||' have an active, staffed department named for them, '||v_unmanaged
          ||' are staffed but have no lead_agent, '||v_gap||' name a department that is absent, '
          ||'inactive or unstaffed. THIS IS A STAFFING CHECK, NOT A REHEARSAL - nothing here says '
          ||'the organisation would survive any of these failures, only that somebody is employed '
          ||'to answer them.');

  return jsonb_build_object('ok', true, 'ran', jsonb_array_length(v_out),
    'staffed', v_staffed, 'staffed_unmanaged', v_unmanaged, 'gap', v_gap,
    'is_rehearsal', false, 'scenarios', v_out);
end
$function$;
