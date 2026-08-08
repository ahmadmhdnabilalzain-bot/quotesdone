create or replace function public.fn_kpi_scoreboard()
returns table (
  kpi_id bigint, agent_key text, department text, kpi text, metric text,
  cadence text, serves_goal text, target numeric, unit text,
  actual numeric, attainment numeric, verdict text
)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r record; v numeric; t numeric;
begin
  for r in
    select k.id, k.agent_key, a.department, k.kpi, k.metric, k.cadence,
           k.serves_goal, k.target_value, k.unit, k.measure_sql
    from employee_kpi k
    left join org_agents a on a.agent_key = k.agent_key
    where k.active
    order by a.department nulls last, k.agent_key, k.id
  loop
    v := null;
    begin
      if r.measure_sql is not null then execute r.measure_sql into v; end if;
    exception when others then v := null;
    end;

    t := null;
    begin
      t := r.target_value::numeric;
    exception when others then t := null;
    end;

    kpi_id := r.id; agent_key := r.agent_key; department := r.department;
    kpi := r.kpi; metric := r.metric; cadence := r.cadence;
    serves_goal := r.serves_goal; target := t; unit := r.unit; actual := v;

    if v is null or t is null or t = 0 then
      attainment := null;
    elsif r.unit = 'percent_max' then
      attainment := round(least(100.0, 100.0 * t / nullif(v,0)), 1);
    else
      attainment := round(100.0 * v / t, 1);
    end if;

    verdict := case
      when v is null then 'NO DATA'
      when attainment is null then 'NO TARGET'
      when attainment >= 100 then 'MET'
      when attainment >= 90 then 'NEAR'
      else 'MISSED' end;

    return next;
  end loop;
end
$fn$;

revoke execute on function public.fn_kpi_scoreboard() from public, anon, authenticated;