-- THE SAME ROOT CAUSE, A THIRD TIME: A COMPLETE THING ADDRESSED TO AN IDENTITY THE SYSTEM DOES NOT MODEL.
--
--   1. 115,148 knowledge records in a table no customer path read.
--   2. The founder himself: app_secrets.admin_mfa_phone resolved to nobody, so mobile sign-in 404'd
--      and WhatsApp answered him with the public marketing script.
--   3. This: 75 of the 82 pending agent_actions are addressed to `knowledge_curator`, `strategy_ai`,
--      `marketing_ai`, `reporting_ai`, `document_controller`, `legal_ai`, `security_ai`, `finance_ai`,
--      `operations_ai`, `ai_trainer`, `customer_success`, `compliance` — and to four DEPARTMENT names,
--      `evolution`, `intelligence`, `knowledge_eng`, `sales`. None of them is an org_agents row.
--      fn_agent_action_work_sweep joins `org_agents ... and o.active`, so nothing reaches them; and
--      action_worker calls fn_agent_context(agent_key), which would return an empty brain even if it did.
--
-- THE DECISION. These are not distinct jobs. `strategy_ai` is what this org already staffs as
-- `strategy_director`; `legal_ai` is `legal`. Creating twenty new employees for work sixty-five
-- existing ones already own would be inventing an org chart to satisfy a string. So: the keys map to
-- the real employees, the map is DATA rather than code, and the mapping happens at the WRITE
-- boundary — not by widening the sweep's join, which would leave fn_agent_context empty and the next
-- reader broken in the same way.
--
-- WHY A TRIGGER IS "AT THE WRITER". 38 functions insert into agent_actions. Patching 38 leaves
-- writer 39 free to invent `procurement_ai` next month. BEFORE INSERT on the table is the one place
-- every writer, present and future, routes through, and it is the smallest diff that is also complete.
--
-- NOTHING IS FABRICATED. The name the writer used is preserved in detail.addressed_as. An addressee
-- that resolves to nobody is NOT silently reassigned: it goes to the Chief of Staff with
-- escalated = true and the reason on it, so "addressed to nobody" becomes visible instead of silent.
-- That deliberately makes `approval-center-everything-else-automatic` HARDER — an unaddressable
-- action now counts as paused, where before it sat pending forever and counted the same. Correct.

create table if not exists public.org_agent_alias (
  alias       text primary key,
  agent_key   text not null references public.org_agents(agent_key),
  reason      text not null,
  created_at  timestamptz not null default now()
);
comment on table public.org_agent_alias is
  'Role names that writers address work to which are not employee keys. Resolved at INSERT on '
  'agent_actions by trg_agent_action_resolve_addressee. Add a row, not a deploy, for a new name.';

insert into public.org_agent_alias(alias, agent_key, reason) values
  ('knowledge_curator',    'docs',                  'Documentation Manager owns capture/fill/retrieve'),
  ('document_controller',  'docs',                  'Documentation Manager owns controlled documents'),
  ('strategy_ai',          'strategy_director',     'Strategy & Performance Director'),
  ('marketing_ai',         'marketing',             'Marketing Director'),
  ('reporting_ai',         'analytics',             'Head of Analytics & Intelligence owns metric reporting'),
  ('operations_ai',        'ops_director',          'Operations Director'),
  ('finance_ai',           'cfo',                   'Finance Director owns money, books, cash, spend'),
  ('legal_ai',             'legal',                 'Legal Counsel'),
  ('security_ai',          'security',              'Cybersecurity Manager'),
  ('ai_trainer',           'ai_architect',          'AI Architect owns prompts and model behaviour'),
  ('customer_success',     'followup',              'Customer Success Director (also the department name)'),
  ('compliance',           'compliance_mgr',        'Compliance Manager'),
  ('chief_of_staff',       'brief',                 'Chief of Staff'),
  ('supplier_success',     'onboarding',            'Supplier Success Manager'),
  ('supplier_onboard',     'onboarding',            'Supplier Success Manager owns onboarding'),
  ('supplier_risk_monitor','supplier_verification', 'Supplier Verification Specialist owns supplier risk'),
  ('bd_outreach',          'bd',                    'Business Development Manager'),
  ('designer',             'marketing_design',      'Graphic Design Director'),
  ('email',                'brief',                 'no mailbox employee exists; Chief of Staff owns the company inbox'),
  ('autogen',              'org_designer',          'Organisational Designer owns agent creation')
on conflict (alias) do update
  set agent_key = excluded.agent_key, reason = excluded.reason;

-- Resolution order: a real active employee wins; then the curated alias; then a DEPARTMENT name,
-- which resolves to its most senior active member. The department rule is a rule rather than fifteen
-- alias rows because it stays correct when a department is restaffed.
create or replace function public.fn_org_agent_resolve(p_addressee text)
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select coalesce(
    (select o.agent_key from public.org_agents o
      where o.agent_key = p_addressee and o.active),
    (select a.agent_key from public.org_agent_alias a
       join public.org_agents o on o.agent_key = a.agent_key and o.active
      where a.alias = p_addressee),
    (select o.agent_key from public.org_agents o
      where o.department = p_addressee and o.active
      order by case o.seniority
                 when 'executive' then 0 when 'chief' then 1 when 'director' then 2
                 when 'lead'      then 3 when 'manager' then 4 when 'senior' then 5 else 6 end,
               o.agent_key
      limit 1)
  );
$$;

create or replace function public.fn_agent_action_resolve_addressee()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v_key text;
begin
  if new.agent is null or new.agent = '' then
    new.agent := 'brief';
    new.escalated := true;
    new.escalation_reason := coalesce(new.escalation_reason, 'written with no addressee at all');
    return new;
  end if;

  if exists (select 1 from public.org_agents o where o.agent_key = new.agent and o.active) then
    return new;                                   -- already a real employee: the common case, untouched
  end if;

  v_key := public.fn_org_agent_resolve(new.agent);

  if v_key is null then
    -- Addressed to nobody. Do not drop it, do not guess a recipient, do not leave it invisible.
    new.detail := coalesce(new.detail, '{}'::jsonb)
                  || jsonb_build_object('addressed_as', new.agent, 'addressee_unresolved', true);
    new.escalated := true;
    new.escalation_reason := coalesce(new.escalation_reason,
      'addressee "' || new.agent || '" is not an employee and no org_agent_alias maps it');
    new.agent := 'brief';
    return new;
  end if;

  new.detail := coalesce(new.detail, '{}'::jsonb) || jsonb_build_object('addressed_as', new.agent);
  new.agent := v_key;
  return new;
end $$;

drop trigger if exists trg_agent_action_resolve_addressee on public.agent_actions;
create trigger trg_agent_action_resolve_addressee
  before insert on public.agent_actions
  for each row execute function public.fn_agent_action_resolve_addressee();

-- Backfill: PENDING only. Done rows are history and history is not rewritten. This routes existing
-- real work to a real person; it closes nothing and back-dates nothing.
update public.agent_actions a
   set agent  = public.fn_org_agent_resolve(a.agent),
       detail = coalesce(a.detail, '{}'::jsonb) || jsonb_build_object('addressed_as', a.agent)
 where a.status = 'pending'
   and public.fn_org_agent_resolve(a.agent) is not null
   and public.fn_org_agent_resolve(a.agent) <> a.agent;

-- The one row this catches on production is #2297: fn_execution_run put the ROUTE (`cat:signage`)
-- in the addressee slot of a "which agent owns signage work" decision. A category is not a person.
-- It goes to the Chief of Staff, escalated, with the name it was written under kept — the same
-- outcome the trigger gives a future one, so the backfilled state and the live path agree.
update public.agent_actions a
   set detail = coalesce(a.detail, '{}'::jsonb)
                || jsonb_build_object('addressed_as', a.agent, 'addressee_unresolved', true),
       escalated = true,
       escalation_reason = coalesce(a.escalation_reason,
         'addressee "' || a.agent || '" is not an employee and no org_agent_alias maps it'),
       agent = 'brief'
 where a.status = 'pending'
   and public.fn_org_agent_resolve(a.agent) is null;

revoke execute on function public.fn_org_agent_resolve(text) from public, anon, authenticated;
revoke execute on function public.fn_agent_action_resolve_addressee() from public, anon, authenticated;

alter table public.org_agent_alias enable row level security;

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- TRIGGER ORDER IS ALPHABETICAL, AND THE FIRST NAME WAS WRONG.
--
-- Postgres fires BEFORE triggers in NAME order, so `action_gate` ran before
-- `trg_agent_action_resolve_addressee` and read NEW.agent while it was still the unresolved role
-- name. trg_action_gate does not merely stamp: it hands NEW.agent to fn_should_escalate as the ACTOR
-- the escalation routes FROM, and writes it to decision_log.actor.
--
-- Probed on production in an aborted transaction, one action addressed to strategy_ai:
--     BEFORE   row.agent = strategy_director   decision_log.actor = strategy_ai
--     AFTER    row.agent = strategy_director   decision_log.actor = strategy_director
-- Staging reads the same after.
--
-- So the fix was correct one layer up and still handed the router an identity that does not exist --
-- the same defect one layer down, introduced by the fix for it. The rename IS the whole repair.
alter trigger trg_agent_action_resolve_addressee on public.agent_actions
  rename to a00_agent_action_resolve_addressee;

comment on trigger a00_agent_action_resolve_addressee on public.agent_actions is
  'MUST fire before action_gate. BEFORE triggers fire in NAME order and trg_action_gate reads '
  'NEW.agent as the actor it routes the escalation FROM, so an unresolved addressee here becomes an '
  'unresolved actor in decision_log and in fn_should_escalate. The a00_ prefix is the ordering '
  'contract; do not rename it back.';
