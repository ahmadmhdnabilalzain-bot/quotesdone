-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727013906   name: review_gate_fail_closed_and_delegation
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ================================================================
-- Layer-4 remediation, part 1.
-- Root cause found by the stress run: quality_standard criteria for
-- supplier_application, quote and rfq carry prose only - no pattern,
-- no executable check - so fn_review_submit's loop never fired and the
-- gate APPROVED everything, including a foodstuff licence applying to a
-- fire-fighting category. A described rule is not a rule.
-- Fix has two halves: make what can be checked executable, and make
-- what cannot be checked BLOCK instead of pass.
-- ================================================================

-- ---- availability and delegation (director_unavailable scenario) ----
alter table public.org_agents
  add column if not exists available boolean not null default true,
  add column if not exists unavailable_until date,
  add column if not exists unavailable_reason text;

alter table public.review_chain
  add column if not exists delegated_from text,
  add column if not exists delegation_basis text;

create table if not exists public.delegation_rule (
  id           bigserial primary key,
  dept_key     text not null,
  when_agent   text not null,
  delegate_to  text not null,
  basis        text not null,
  rank         integer not null default 1,
  active       boolean not null default true,
  unique (dept_key, when_agent, delegate_to)
);

-- Seniority has no rank column, so give it one that code can order by.
create or replace function public.fn_seniority_rank(p text) returns integer
language sql immutable as $fn$
  select case lower(coalesce(p,''))
           when 'executive' then 1 when 'director' then 2
           when 'manager'   then 3 when 'specialist' then 4 else 9 end;
$fn$;

-- Who actually approves for this department right now, and on what basis.
create or replace function public.fn_pick_reviewer(p_dept_key text)
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare v_head text; v_ok boolean; v_delegate text; v_basis text;
begin
  select lead_agent into v_head from org_departments where dept_key = p_dept_key;

  select (a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date))
    into v_ok from org_agents a where a.agent_key = v_head;

  if v_head is null then
    return jsonb_build_object('reviewer', null, 'available', false,
      'basis', 'no lead_agent recorded for department ' || p_dept_key);
  end if;

  if coalesce(v_ok, false) then
    return jsonb_build_object('reviewer', v_head, 'available', true, 'delegated_from', null, 'basis', 'department head');
  end if;

  -- Explicit delegation first.
  select d.delegate_to, d.basis into v_delegate, v_basis
  from delegation_rule d
  join org_agents a on a.agent_key = d.delegate_to
  where d.active and d.dept_key = p_dept_key and d.when_agent = v_head
    and a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date)
  order by d.rank limit 1;

  -- Otherwise the most senior available employee in the same department.
  if v_delegate is null then
    select a.agent_key, 'most senior available employee in ' || p_dept_key
      into v_delegate, v_basis
    from org_agents a
    where a.department = p_dept_key and a.agent_key <> v_head
      and a.active and a.available and (a.unavailable_until is null or a.unavailable_until < current_date)
    order by fn_seniority_rank(a.seniority), a.agent_key limit 1;
  end if;

  if v_delegate is null then
    return jsonb_build_object('reviewer', null, 'available', false, 'delegated_from', v_head,
      'basis', 'department head unavailable and no delegate available - escalate');
  end if;

  return jsonb_build_object('reviewer', v_delegate, 'available', true,
    'delegated_from', v_head, 'basis', coalesce(v_basis, 'delegation'));
end; $fn$;

revoke execute on function public.fn_pick_reviewer(text) from anon, authenticated, public;

insert into public.delegation_rule (dept_key, when_agent, delegate_to, basis, rank)
select d.dept_key, d.lead_agent, a.agent_key,
       'standing deputy: most senior manager in the department', 1
from org_departments d
join lateral (
  select a.agent_key from org_agents a
  where a.department = d.dept_key and a.agent_key <> d.lead_agent and a.active
  order by fn_seniority_rank(a.seniority), a.agent_key limit 1
) a on true
where d.active and d.lead_agent is not null
on conflict do nothing;

alter table public.delegation_rule enable row level security;
