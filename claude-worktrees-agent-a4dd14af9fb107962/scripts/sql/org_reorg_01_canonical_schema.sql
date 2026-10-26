-- REORGANISING THE AGENT COMPANY — 1 of 5: the canonical organisation.
--
-- Five things were being treated as one: department, role, runtime agent, knowledge overlay and
-- committee membership. org_agents already models the runtime agent well; it models nothing else.
-- This file adds the missing four as their own objects, keyed on a CANONICAL role_id that says
-- what the role IS ('chief_of_staff', 'general_counsel'), while org_agents keeps the physical
-- runtime key it has always had ('brief', 'legal').
--
-- WHY THE PHYSICAL KEY IS NOT RENAMED. Measured on production, 14 Aug 2026: the ten "vague" agent
-- keys appear as string literals inside 51 sites across 40+ live SQL routines (security 8,
-- brief 7, it 7, marketing 7, procurement 6, legal 6, onboarding 5, docs 3, followup 1,
-- analytics 1) and in ~50 text columns across 25 tables, only 5 of which carry a foreign key.
-- Renaming the primary key would silently orphan every non-FK column and every routine literal.
-- The brief's own instruction is "do not rename blindly — find every caller first, create
-- backward-compatible aliases". Found them; the alias direction that leaves nothing orphaned is
-- canonical-name -> physical-key, resolved by fn_org_agent_resolve, which already exists and is
-- already read by the addressee trigger and the workflow actor resolver.

-- ---------------------------------------------------------------------------------------------
-- COMMITTEES. A department head who sits on the executive committee must not exist twice.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.org_committee (
  committee_key text primary key,
  name          text not null,
  purpose       text not null,
  chair_role_id text,
  cadence       text not null default 'weekly',
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------------------------
-- THE CANONICAL ROLE REGISTRY.
-- ---------------------------------------------------------------------------------------------
create table if not exists public.org_role (
  role_id               text primary key,
  display_name          text not null,
  primary_department_id text not null references public.org_departments(dept_key),
  manager_role_id       text references public.org_role(role_id),
  runtime_mode          text not null,
  runtime_agent_key     text references public.org_agents(agent_key),
  responsibilities      text not null,
  owned_decisions       text[] not null default '{}',
  forbidden_decisions   text[] not null default '{}',
  activation_conditions text not null,
  required_inputs       text[] not null default '{}',
  output_contracts      text[] not null default '{}',
  tools                 text[] not null default '{}',
  knowledge_scopes      text[] not null default '{}',
  authority_level       text not null,
  budget_limit          numeric,
  handoff_targets       text[] not null default '{}',
  escalation_targets    text[] not null default '{}',
  model_policy          text,
  evaluation_suite      text,
  status                text not null default 'active',
  source_agent_keys     text[] not null default '{}',
  rationale             text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint org_role_runtime_mode_ck check (runtime_mode in
    ('persistent_manager','scheduled_manager','event_driven_operator',
     'on_demand_specialist','knowledge_overlay','independent_reviewer')),
  constraint org_role_authority_ck check (authority_level in
    ('advisory','execute_low','execute_medium','execute_high','stop_authority')),
  constraint org_role_status_ck check (status in ('active','deferred','retired')),
  -- no self-management
  constraint org_role_no_self_manage_ck check (manager_role_id is distinct from role_id)
);

-- ONE canonical role per runtime agent. This is the constraint that makes "a department head who
-- attends the executive committee should not exist twice" unrepresentable rather than merely
-- discouraged: committee seats live in org_role_committee, never in a second role row.
create unique index if not exists org_role_one_per_agent_ux
  on public.org_role (runtime_agent_key)
  where status = 'active' and runtime_agent_key is not null;

create index if not exists org_role_dept_ix on public.org_role (primary_department_id) where status='active';
create index if not exists org_role_mgr_ix  on public.org_role (manager_role_id);

create table if not exists public.org_role_committee (
  role_id       text not null references public.org_role(role_id) on delete cascade,
  committee_key text not null references public.org_committee(committee_key) on delete cascade,
  seat          text not null default 'member',
  since         date not null default current_date,
  note          text,
  primary key (role_id, committee_key),
  constraint org_role_committee_seat_ck check (seat in ('chair','member','observer','secretary'))
);

-- Backwards-compatible identity: any historical or external name resolves to one canonical role.
create table if not exists public.org_role_alias (
  alias      text primary key,
  role_id    text not null references public.org_role(role_id) on delete cascade,
  kind       text not null default 'legacy_agent_key',
  reason     text,
  created_at timestamptz not null default now(),
  constraint org_role_alias_kind_ck check (kind in
    ('legacy_agent_key','legacy_role_id','packaged_role_id','title','merged_role'))
);

-- ---------------------------------------------------------------------------------------------
-- NO REPORTING CYCLES. A cycle is not a data-quality report, it is a hang: fn_workflow_actor_resolve
-- and every "escalate to my manager" path walks this edge.
-- ---------------------------------------------------------------------------------------------
create or replace function public.trg_org_role_no_cycle() returns trigger
language plpgsql as $$
declare v_cur text; v_depth int := 0;
begin
  if new.manager_role_id is null then return new; end if;
  v_cur := new.manager_role_id;
  while v_cur is not null and v_depth < 64 loop
    if v_cur = new.role_id then
      raise exception 'reporting cycle: % -> % would close a loop', new.role_id, new.manager_role_id;
    end if;
    select r.manager_role_id into v_cur from public.org_role r where r.role_id = v_cur;
    v_depth := v_depth + 1;
  end loop;
  if v_depth >= 64 then
    raise exception 'reporting chain deeper than 64 above %; refusing', new.role_id;
  end if;
  return new;
end $$;

drop trigger if exists a10_org_role_no_cycle on public.org_role;
create trigger a10_org_role_no_cycle
  before insert or update of manager_role_id on public.org_role
  for each row execute function public.trg_org_role_no_cycle();

create or replace function public.trg_org_role_touch() returns trigger
language plpgsql as $$ begin new.updated_at := now(); return new; end $$;
drop trigger if exists a20_org_role_touch on public.org_role;
create trigger a20_org_role_touch before update on public.org_role
  for each row execute function public.trg_org_role_touch();

-- ---------------------------------------------------------------------------------------------
-- RESOLVERS. Old ID in, canonical role out; canonical role in, runtime agent out.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_org_role_resolve(p_any text)
returns text language sql stable as $$
  select coalesce(
    (select r.role_id from public.org_role r where r.role_id = p_any and r.status = 'active'),
    (select a.role_id from public.org_role_alias a
        join public.org_role r on r.role_id = a.role_id and r.status = 'active'
       where a.alias = p_any),
    (select r.role_id from public.org_role r
       where r.runtime_agent_key = p_any and r.status = 'active' limit 1),
    -- last arm: whatever org_agents' own alias table already knew, mapped forward
    (select r.role_id from public.org_agent_alias g
        join public.org_role r on r.runtime_agent_key = g.agent_key and r.status = 'active'
       where g.alias = p_any limit 1)
  );
$$;

-- The executor for a role. A knowledge_overlay has no standing executor of its own: it is loaded
-- INTO its invoking manager, so this returns that manager's agent rather than null, which is what
-- "the customer should not visibly bounce between agents" means at the runtime layer.
-- ROUTINE REMOVED 7 September 2026. public.fn_org_role_agent was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- Manager chain to the top, cycle-safe, used by escalation and by the tests.
-- ROUTINE REMOVED 7 September 2026. public.fn_role_manager_chain was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


-- ---------------------------------------------------------------------------------------------
-- THE ENFORCEMENT THE BRIEF ASKS FOR, AS A MEASUREMENT RATHER THAN A COMMENT.
-- Structural rules (unique id, one department, one manager, no self-management, no cycle) are
-- constraints above. The completeness rules cannot be constraints — a role is seeded before its
-- KPIs exist — so they are a function that returns every violation, and a test asserts it is empty.
-- ---------------------------------------------------------------------------------------------
-- ROUTINE REMOVED 7 September 2026. public.fn_org_role_violations was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

alter function public.fn_org_role_violations() set search_path to 'public';

-- ---------------------------------------------------------------------------------------------
-- Views the OS screens and the tests read.
-- ---------------------------------------------------------------------------------------------
create or replace view public.v_org_role_full as
select r.role_id, r.display_name, r.primary_department_id, d.name as department_name,
       r.manager_role_id, m.display_name as manager_name, r.runtime_mode, r.runtime_agent_key,
       r.authority_level, r.status,
       (select count(*) from public.employee_kpi k where k.agent_key=r.runtime_agent_key and k.active) as kpi_count,
       (select count(*) from public.employee_knowledge k where k.agent_key=r.runtime_agent_key) as knowledge_count,
       (select count(*) from public.employee_authority k where k.agent_key=r.runtime_agent_key) as authority_count,
       (select count(*) from public.org_tasks t where t.assigned_agent=r.runtime_agent_key
          and t.status in ('assigned','in_progress')) as open_tasks,
       (select coalesce(array_agg(c.committee_key order by c.committee_key),'{}')
          from public.org_role_committee c where c.role_id=r.role_id) as committees
  from public.org_role r
  join public.org_departments d on d.dept_key = r.primary_department_id
  left join public.org_role m on m.role_id = r.manager_role_id;

-- RLS. A new table gets RLS on production by event trigger and NOT on staging; set it explicitly
-- on both so the two projects cannot drift on the one thing that decides who can read the org.
alter table public.org_committee       enable row level security;
alter table public.org_role            enable row level security;
alter table public.org_role_committee  enable row level security;
alter table public.org_role_alias      enable row level security;

revoke all on public.org_committee, public.org_role, public.org_role_committee, public.org_role_alias from anon, authenticated;
grant select on public.org_committee, public.org_role, public.org_role_committee, public.org_role_alias to service_role;
grant select on public.v_org_role_full to service_role;

-- CREATE grants EXECUTE to PUBLIC; these read the org chart and must not be callable by anon.
revoke all on function public.fn_org_role_resolve(text)      from public;
revoke all on function public.fn_org_role_agent(text)        from public;
revoke all on function public.fn_role_manager_chain(text)    from public;
revoke all on function public.fn_org_role_violations()       from public;
grant execute on function public.fn_org_role_resolve(text)   to service_role;
grant execute on function public.fn_org_role_agent(text)     to service_role;
grant execute on function public.fn_role_manager_chain(text) to service_role;
grant execute on function public.fn_org_role_violations()    to service_role;
