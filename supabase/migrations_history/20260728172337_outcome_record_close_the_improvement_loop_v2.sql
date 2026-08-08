create table if not exists public.outcome_record (
  id              bigserial primary key,
  actor           text not null,
  dept_key        text,
  subject_type    text not null,
  subject_id      text,
  decision        text not null,
  rationale       text,
  evidence        jsonb default '[]'::jsonb,
  expected_kpi_id bigint references employee_kpi(id),
  expected_metric text,
  expected_direction text not null default 'up' check (expected_direction in ('up','down')),
  baseline_value  numeric,
  baseline_at     timestamptz not null default now(),
  measure_after   interval not null default '14 days',
  due_at          timestamptz not null default (now() + interval '14 days'),
  observed_value  numeric,
  observed_at     timestamptz,
  delta           numeric,
  verdict         text not null default 'pending'
                  check (verdict in ('pending','improved','no_change','worse','unmeasurable')),
  promoted        boolean not null default false,
  rolled_back     boolean not null default false,
  rollback_reason text,
  lesson          text,
  closed_at       timestamptz,
  created_at      timestamptz not null default now()
);

create index if not exists outcome_record_due_idx on public.outcome_record (due_at) where verdict='pending';
create index if not exists outcome_record_actor_idx on public.outcome_record (actor);
create index if not exists outcome_record_subject_idx on public.outcome_record (subject_type, subject_id);
alter table public.outcome_record enable row level security;

comment on table public.outcome_record is
  'One row per autonomous decision that claims it will improve something. Records the claim and the baseline BEFORE execution, then grades it against reality after measure_after. A change that made things worse is marked worse and flagged for rollback. Turns execution into proof.';

create or replace function public.fn_outcome_open(
  p_actor text, p_decision text,
  p_subject_type text default 'manual', p_subject_id text default null,
  p_expected_kpi_id bigint default null, p_rationale text default null,
  p_evidence jsonb default '[]'::jsonb, p_direction text default 'up',
  p_measure_after interval default '14 days'
) returns bigint
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare v_sql text; v_base numeric; v_metric text; v_dept text; v_id bigint;
begin
  if p_expected_kpi_id is not null then
    select measure_sql, metric into v_sql, v_metric from employee_kpi where id = p_expected_kpi_id;
    begin
      if v_sql is not null then execute v_sql into v_base; end if;
    exception when others then v_base := null; end;
  end if;

  select a.department into v_dept from org_agents a where a.agent_key = p_actor;

  insert into outcome_record (actor, dept_key, subject_type, subject_id, decision, rationale,
                              evidence, expected_kpi_id, expected_metric, expected_direction,
                              baseline_value, measure_after, due_at)
  values (p_actor, v_dept, p_subject_type, p_subject_id, p_decision, p_rationale,
          coalesce(p_evidence,'[]'::jsonb), p_expected_kpi_id, v_metric,
          coalesce(p_direction,'up'), v_base, coalesce(p_measure_after, interval '14 days'),
          now() + coalesce(p_measure_after, interval '14 days'))
  returning id into v_id;
  return v_id;
end $fn$;

revoke execute on function public.fn_outcome_open(text,text,text,text,bigint,text,jsonb,text,interval)
  from public, anon, authenticated;