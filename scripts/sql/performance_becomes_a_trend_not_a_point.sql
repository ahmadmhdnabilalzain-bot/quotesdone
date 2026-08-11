-- PERFORMANCE WAS A POINT VALUE. THE STANDARD REQUIRES A TREND.
--
-- "Every AI employee ... is monitored against them, learns from outcomes and failures, improves its
-- methods." None of that is observable from a single number that is overwritten every night.
--
-- employee_kpi.actual_value landed earlier this session and is a point: fn_employee_kpi_measure
-- overwrites it on each run, so yesterday's number is gone. An employee cannot be shown to be
-- improving, a manager cannot see a decline before it becomes a miss, and fn_kpi_review can only
-- ever compare against a target - never against the employee's own history.
--
-- Row #3's own check states the same requirement independently
-- (scripts/staging/os2_blueprint/layers_1_8.mjs:364, employee-performance-trend): more than one
-- performance observation per active employee within 90 days, with distinct timestamps.
--
-- THE UNIQUE INDEX IS THE HONEST PART, AND IT IS DELIBERATE. One row per KPI per DAY. Without it
-- this file would be a machine for manufacturing a trend: run the measure five times tonight and
-- the check goes green on five observations that all describe the same moment. With it, a second
-- observation cannot exist until tomorrow's cron, which is exactly when it should exist. The check
-- stays red tonight and passes on its own the day after - and that is the correct outcome, not a
-- limitation of this file.

create table if not exists public.employee_kpi_history (
  id           bigserial primary key,
  kpi_id       bigint      not null references public.employee_kpi(id) on delete cascade,
  agent_key    text        not null,
  actual_value numeric,
  target_value numeric,
  unit         text,
  attainment   numeric,
  verdict      text,
  measured_at  timestamptz not null default now(),
  measured_on  date        not null default (now() at time zone 'utc')::date
);

-- One observation per KPI per UTC day. See the note above: this is what stops a re-run from
-- inventing history.
create unique index if not exists employee_kpi_history_one_per_day
  on public.employee_kpi_history (kpi_id, measured_on);

create index if not exists employee_kpi_history_agent_idx
  on public.employee_kpi_history (agent_key, measured_on desc);

alter table public.employee_kpi_history enable row level security;

comment on table public.employee_kpi_history is
  'Append-only daily observation of every measurable employee KPI, written by fn_employee_kpi_measure. One row per KPI per UTC day, enforced by a unique index so a re-run cannot fabricate a trend. Added 11 Aug 2026: employee_kpi.actual_value is overwritten each night, so no employee in this company had a performance history.';

-- ---------------------------------------------------------------------------------------------
-- THE MEASURE NOW APPENDS AS WELL AS OVERWRITES.
--
-- Still sourced from fn_kpi_scoreboard - one execute loop, not two that must agree. The verdict and
-- attainment stored here are the scoreboard's own, so the history cannot drift from the live view.
-- A KPI whose measure failed writes actual NULL and verdict 'NO DATA': the row still exists, so
-- "this employee could not be measured for six days" is itself visible in the trend. That is a
-- finding, not a gap, and silently skipping it is how an outage becomes confidence.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_employee_kpi_measure()
returns table(measured integer, failed integer)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare n_ok int := 0; n_bad int := 0;
begin
  create temporary table if not exists _kpi_now on commit drop as
    select kpi_id, agent_key, actual, target, unit, attainment, verdict from fn_kpi_scoreboard();

  update employee_kpi k
     set actual_value = s.actual,
         measured_at  = case when s.actual is null then null else now() end
    from _kpi_now s where s.kpi_id = k.id;

  insert into employee_kpi_history
    (kpi_id, agent_key, actual_value, target_value, unit, attainment, verdict)
  select s.kpi_id, s.agent_key, s.actual, s.target, s.unit, s.attainment, s.verdict
    from _kpi_now s
  on conflict (kpi_id, measured_on) do update
    set actual_value = excluded.actual_value,
        target_value = excluded.target_value,
        unit         = excluded.unit,
        attainment   = excluded.attainment,
        verdict      = excluded.verdict,
        measured_at  = now();

  select count(*) filter (where measured_at is not null),
         count(*) filter (where measured_at is null and coalesce(measure_sql,'') <> '')
    into n_ok, n_bad
    from employee_kpi where active;
  return query select n_ok, n_bad;
end $function$;

revoke all on function public.fn_employee_kpi_measure() from public;

-- ---------------------------------------------------------------------------------------------
-- THE TREND, READ BY THE EMPLOYEE ITSELF.
--
-- Direction is computed against the employee's OWN previous observation, not against the target,
-- because "am I getting better" and "am I good enough" are different questions and only the second
-- one was answerable before today. percent_max metrics invert: falling is improving.
-- ---------------------------------------------------------------------------------------------

create or replace function public.fn_employee_kpi_trend(p_agent_key text, p_days integer default 90)
returns table(kpi text, unit text, observations bigint, first_value numeric, latest_value numeric,
              direction text, latest_verdict text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with h as (
    select k.kpi, h.kpi_id, h.actual_value, h.unit, h.verdict, h.measured_on,
           first_value(h.actual_value) over w_asc  as first_v,
           first_value(h.actual_value) over w_desc as latest_v,
           first_value(h.verdict)      over w_desc as latest_verdict,
           row_number()                over w_desc as rn,
           count(*)                    over (partition by h.kpi_id) as n
      from employee_kpi_history h
      join employee_kpi k on k.id = h.kpi_id
     where h.agent_key = p_agent_key
       and h.measured_on > (now() at time zone 'utc')::date - p_days
       and h.actual_value is not null
    window w_asc  as (partition by h.kpi_id order by h.measured_on),
           w_desc as (partition by h.kpi_id order by h.measured_on desc)
  )
  select kpi, unit, n,
         first_v, latest_v,
         case when n < 2 or first_v is null or latest_v is null then 'no trend yet'
              when latest_v = first_v then 'flat'
              when (unit = 'percent_max') = (latest_v < first_v) then 'improving'
              else 'worsening' end,
         latest_verdict
    from h where rn = 1
   order by kpi;
$function$;

revoke all on function public.fn_employee_kpi_trend(text, integer) from public;
revoke all on function public.fn_employee_kpi_trend(text, integer) from anon;
