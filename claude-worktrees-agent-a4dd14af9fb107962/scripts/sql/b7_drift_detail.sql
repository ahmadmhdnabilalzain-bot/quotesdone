select line from (
  select id::text as k, 'expectation change #' || id::text || ' at ' || changed_at::text
         || ' by ' || coalesce(changed_by,'?') || ' | ' || scenario_id as line
    from public.scenario_expectation_change
  union all
  select 'zz1', 'changes in the last 6 hours: ' || count(*)::text
    from public.scenario_expectation_change where changed_at > now() - interval '6 hours'
  union all
  select 'zz2', 'result_of_record: ' || row_to_json(r)::text
    from public.p2c1_holdout_result_of_record r
) q order by k;
