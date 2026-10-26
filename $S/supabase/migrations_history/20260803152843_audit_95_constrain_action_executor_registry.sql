-- AUDIT 9.5 (3 Aug 2026): constrain the action-executor registry AT WRITE TIME.
--
-- WHAT THE REPAIR BRIEF GOT WRONG. §4.3 said: "cos_execute:152 dispatches to ex.target, read from
-- an org_tasks row. Whoever can write an org_tasks row chooses the callee. Today that is unbounded."
-- Both halves are wrong, checked against this database:
--
--   1. The target does not come from org_tasks. The task row supplies action_class; cos_execute
--      looks that up in public.org_action_executor, a registry keyed by action_class carrying
--      kind, target, params, active and advisory_safe. The callee set is bounded by that registry.
--   2. Nothing outside service_role can write either table. org_action_executor, org_tasks and
--      org_objectives all have RLS on, ZERO policies, and grants only to postgres and service_role.
--      anon and authenticated cannot read or write them at all.
--
-- WHAT IS ACTUALLY SHARP, AND WAS NOT FLAGGED. 16 of the registry's rows are kind='rpc' and run
-- admin.rpc(ex.target, ex.params) - arbitrary Postgres function invocation with service-role
-- authority. Scoping cos_execute's CREDENTIAL does nothing about that path at all, because it never
-- goes over HTTP. A registry row is therefore a more powerful object than it looks, and the place to
-- constrain it is the write, not the call.
--
-- THE CONSTRAINT.
--   kind='edge' -> target must be in the scope of the live fn.cos_execute credential. That makes the
--                  credential the single source of truth: widening what the executor may call is one
--                  deliberate act (rotate/reissue the credential with a wider scope), not an INSERT.
--   kind='rpc'  -> target must be in org_action_executor_rpc_allowed, an explicit list seeded from
--                  the 16 rows in service today. Adding an rpc executor is now two reviewed steps.
--   any other kind, or no live credential -> rejected. Fail closed: a registry the verifier cannot
--                  evaluate must not accept writes, because cos_execute would execute them.

create table if not exists public.org_action_executor_rpc_allowed (
  target      text primary key,
  note        text,
  added_at    timestamptz not null default now()
);
comment on table public.org_action_executor_rpc_allowed is
  'Allow-list for org_action_executor rows with kind=''rpc''. cos_execute runs these as service-role '
  'via admin.rpc(), so an entry here is a grant of arbitrary database authority. Add only after review.';

alter table public.org_action_executor_rpc_allowed enable row level security;
revoke all on public.org_action_executor_rpc_allowed from anon, authenticated;

-- Seed from what is actually in service, so the constraint freezes a reviewed set rather than
-- inventing one. Anything already live keeps working; anything new has to be added deliberately.
insert into public.org_action_executor_rpc_allowed (target, note)
select distinct e.target, 'seeded 3 Aug 2026 from the registry in service at the time of the constraint'
  from public.org_action_executor e
 where e.kind = 'rpc'
on conflict (target) do nothing;

create or replace function public.fn_org_action_executor_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_scope text[];
begin
  if new.kind = 'edge' then
    select c.scope into v_scope
      from public.internal_credential c
     where c.context = 'fn.cos_execute'
       and c.active and c.retired_at is null
     limit 1;

    if v_scope is null then
      raise exception
        'org_action_executor: no live fn.cos_execute credential, so an edge executor target cannot '
        'be validated. Refusing the write rather than registering a callee nothing has authorised.'
        using errcode = 'check_violation';
    end if;

    if not (new.target = any (v_scope)) then
      raise exception
        'org_action_executor: edge target % is outside the fn.cos_execute credential scope. '
        'cos_execute would POST service-role authority to it. Widen the credential scope '
        'deliberately if this executor is intended; do not widen it to make an INSERT succeed.',
        new.target
        using errcode = 'check_violation';
    end if;

  elsif new.kind = 'rpc' then
    if not exists (select 1 from public.org_action_executor_rpc_allowed a where a.target = new.target) then
      raise exception
        'org_action_executor: rpc target % is not in org_action_executor_rpc_allowed. cos_execute '
        'runs rpc executors as service-role, so this is a grant of arbitrary database authority. '
        'Add it to the allow-list deliberately first.',
        new.target
        using errcode = 'check_violation';
    end if;

  else
    raise exception
      'org_action_executor: unknown kind %. cos_execute only understands edge and rpc, so a row with '
      'any other kind is either dead or a mistake. Refusing it rather than storing it.', new.kind
      using errcode = 'check_violation';
  end if;

  return new;
end $$;

revoke all on function public.fn_org_action_executor_guard() from public, anon, authenticated;

drop trigger if exists trg_org_action_executor_guard on public.org_action_executor;
create trigger trg_org_action_executor_guard
  before insert or update of kind, target on public.org_action_executor
  for each row execute function public.fn_org_action_executor_guard();

-- Operator view: what the executor may reach, and by what authority.
create or replace view public.v_action_executor_authority as
select e.action_class, e.kind, e.target, e.active, e.advisory_safe,
       case e.kind
         when 'edge' then (select e.target = any (c.scope) from public.internal_credential c
                            where c.context = 'fn.cos_execute' and c.active and c.retired_at is null)
         when 'rpc'  then exists (select 1 from public.org_action_executor_rpc_allowed a where a.target = e.target)
         else false
       end as authorised_now
  from public.org_action_executor e;
comment on view public.v_action_executor_authority is
  'Every action executor and whether its target is still authorised. authorised_now=false on a live '
  'row means the registry drifted from the credential/allow-list AFTER the row was written - the '
  'trigger only guards writes, so this view is how you catch a scope narrowed underneath a row.';
