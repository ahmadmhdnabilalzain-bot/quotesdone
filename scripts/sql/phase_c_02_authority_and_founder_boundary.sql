-- Phase C — the authority gate and the founder boundary.
--
-- The founder's stated operating model is that QuotesDone runs itself: he issues orders,
-- observes outcomes, funds or declines to fund, and approves or rejects specific refunds.
-- That last clause is the ONLY routine manual approval, and this file is where that stops
-- being a policy document and becomes something the database refuses to violate.
--
-- The invariant is `founder approval requests where action_class != refund_decision = 0`.
-- It is held three ways, deliberately, because one of them alone would be a convention:
--
--   1. founder_approval_request.action_class is a foreign key into phase_c_action_class.
--   2. A CHECK pins it to the literal 'refund_decision'.
--   3. A trigger re-reads phase_c_action_class.founder_approval_required at write time, so
--      even if a future migration flipped that flag on a second class, this table would still
--      refuse the row rather than quietly accept the new queue.
--
-- Measured before writing this file, and worth recording because it is counter-evidence the
-- founder specifically asked not to have conflated: TEN executors in org_action_executor carry
-- notifies_human = true and all ten are active, and none is a refund.  `notifies_human` is not
-- the same field as "creates a founder approval request" — it means the executor sends a human
-- a message.  public.founder_release_approval holds ONE row, a founder approval for a release,
-- which the autonomy policy explicitly lists as something that must not reach him;
-- public.procurement_approval_request holds zero.  What this file does about each of those is
-- stated at section 4, and what it deliberately does NOT do is delete anything.
--
-- scripts/sql is append-only.  To change any of this, add a new file.

set lock_timeout = '8s';
set statement_timeout = '600s';

-- ============================================================ 1. the founder identity
--
-- Who may command the company.  One row.  This is an allow-list, not a role: the founder is an
-- external decision boundary and deliberately not one of the 90 canonical employees.
create table if not exists public.phase_c_founder_identity (
  identity   text primary key,
  kind       text not null,
  active     boolean not null default true,
  note       text not null default '',
  added_at   timestamptz not null default now()
);

-- ============================================================ 2. founder approval requests
create table if not exists public.founder_approval_request (
  request_id       bigint generated always as identity primary key,
  command_id       bigint,
  action_class     text not null references public.phase_c_action_class(action_class),
  subject_ref      text not null,
  prepared_by_role_id text not null,
  amount_note      text not null default '',
  evidence         jsonb not null default '{}'::jsonb,
  state            text not null default 'pending',
  decided_at       timestamptz,
  decision         text,
  decision_note    text not null default '',
  created_at       timestamptz not null default now()
);
alter table public.founder_approval_request drop constraint if exists founder_approval_request_refund_only_ck;
alter table public.founder_approval_request add constraint founder_approval_request_refund_only_ck
  check (action_class = 'refund_decision') not valid;
alter table public.founder_approval_request validate constraint founder_approval_request_refund_only_ck;
alter table public.founder_approval_request drop constraint if exists founder_approval_request_state_ck;
alter table public.founder_approval_request add constraint founder_approval_request_state_ck
  check (state in ('pending','approved','rejected','withdrawn')) not valid;
alter table public.founder_approval_request validate constraint founder_approval_request_state_ck;

-- The third guard.  A CHECK pins the literal; this re-reads the registry, so the rule survives
-- a future migration that flips founder_approval_required on some other action class.
create or replace function public.fn_founder_approval_refund_only()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if not exists (select 1 from public.phase_c_action_class
                 where action_class = new.action_class and founder_approval_required) then
    raise exception 'founder_approval_request: % is not a founder-approval action class. The founder is not the company''s approval queue; only a specific refund decision reaches him.', new.action_class
      using errcode = '23514';
  end if;
  return new;
end $$;
drop trigger if exists z10_founder_approval_refund_only on public.founder_approval_request;
create trigger z10_founder_approval_refund_only before insert or update
  on public.founder_approval_request for each row
  execute function public.fn_founder_approval_refund_only();

-- ============================================================ 3. the refund decision
--
-- Execution cannot begin without a valid founder decision, and the executor must differ from
-- the reconciler.  Both are enforced here rather than assumed downstream.
create table if not exists public.phase_c_refund_decision (
  decision_id      bigint generated always as identity primary key,
  request_id       bigint not null references public.founder_approval_request(request_id),
  decided_by       text not null,
  decision         text not null,
  reason           text not null default '',
  decided_at       timestamptz not null default now(),
  executor_role_id text not null default 'payments_and_billing_manager',
  reconciler_role_id text not null default 'financial_controller',
  executed_at      timestamptz,
  reconciled_at    timestamptz,
  trace_id         bigint
);
alter table public.phase_c_refund_decision drop constraint if exists phase_c_refund_decision_ck;
alter table public.phase_c_refund_decision add constraint phase_c_refund_decision_ck
  check (decision in ('approved','rejected') and executor_role_id <> reconciler_role_id) not valid;
alter table public.phase_c_refund_decision validate constraint phase_c_refund_decision_ck;
create unique index if not exists phase_c_refund_decision_request_uk
  on public.phase_c_refund_decision (request_id);

create or replace function public.fn_phase_c_refund_decision_guard()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  -- only the founder decides
  if not exists (select 1 from public.phase_c_founder_identity
                 where identity = lower(btrim(new.decided_by)) and active) then
    raise exception 'phase_c_refund_decision: % is not the registered founder identity; the command secretary cannot approve a refund', new.decided_by
      using errcode = '28000';
  end if;
  -- execution requires an APPROVED decision, not merely a decision
  if new.executed_at is not null and new.decision <> 'approved' then
    raise exception 'phase_c_refund_decision %: execution recorded against a % decision', new.decision_id, new.decision
      using errcode = '23514';
  end if;
  if new.reconciled_at is not null and new.executed_at is null then
    raise exception 'phase_c_refund_decision %: reconciled before execution', new.decision_id using errcode = '23514';
  end if;
  return new;
end $$;
drop trigger if exists z10_phase_c_refund_decision_guard on public.phase_c_refund_decision;
create trigger z10_phase_c_refund_decision_guard before insert or update
  on public.phase_c_refund_decision for each row
  execute function public.fn_phase_c_refund_decision_guard();

-- ============================================================ 4. the authority gate
--
-- One authoritative answer to "may this actor take this action, and does it need a reviewer or
-- the founder?".  An action class the registry does not know FAILS CLOSED; that is the whole
-- reason it returns a row with an explicit allowed=false rather than null.
create or replace function public.fn_phase_c_authority_check(
  p_action_class text, p_actor text, p_reviewer text default null)
returns table (allowed boolean, mode text, requires_reviewer boolean, reviewer_independent boolean,
               founder_approval boolean, founder_initiated_only boolean, reason text)
language plpgsql stable set search_path to 'public', 'pg_temp' as $$
declare a public.phase_c_action_class%rowtype; v_actor text; v_kind text;
begin
  select * into a from public.phase_c_action_class where action_class = p_action_class;
  if not found then
    allowed := false; mode := 'unknown'; requires_reviewer := true; reviewer_independent := false;
    founder_approval := false; founder_initiated_only := false;
    reason := format('unknown action class %L — fail closed', p_action_class);
    return next; return;
  end if;

  select kind, role_id into v_kind, v_actor from public.fn_phase_c_resolve_actor(p_actor);
  if v_kind is distinct from 'canonical' and v_kind is distinct from 'founder' then
    allowed := false; mode := a.execution_mode; requires_reviewer := true;
    reviewer_independent := false; founder_approval := a.founder_approval_required;
    founder_initiated_only := a.founder_initiated_only;
    reason := format('actor %L resolves to %s and may not act', p_actor, coalesce(v_kind, 'nothing'));
    return next; return;
  end if;

  founder_approval := a.founder_approval_required;
  founder_initiated_only := a.founder_initiated_only;
  mode := a.execution_mode;
  requires_reviewer := a.execution_mode in ('autonomous_internal_review','autonomous_dual_review');
  reviewer_independent := case when requires_reviewer
                               then public.fn_phase_c_reviewer_independent(p_actor, p_reviewer)
                               else true end;

  -- Founder-reserved matters are not an approval queue.  An agent may research and recommend;
  -- it may not commit without an explicit founder-originated command.
  if a.founder_initiated_only then
    allowed := false;
    reason := format('%s is founder_initiated_only: research and recommendation are autonomous, commitment requires an explicit founder command', a.action_class);
    return next; return;
  end if;

  if a.founder_approval_required and v_kind <> 'founder' then
    allowed := false;
    reason := format('%s requires the founder''s own decision', a.action_class);
    return next; return;
  end if;

  if requires_reviewer and not reviewer_independent then
    allowed := false;
    reason := case when coalesce(p_reviewer,'') = ''
                   then format('%s needs an independent reviewer and none was named', a.action_class)
                   else format('reviewer %L is the same effective identity as %L', p_reviewer, p_actor) end;
    return next; return;
  end if;

  allowed := true;
  reason := format('%s permitted under %s for %s', a.action_class, a.execution_mode, v_actor);
  return next;
end $$;
revoke all on function public.fn_phase_c_authority_check(text, text, text) from public;
grant execute on function public.fn_phase_c_authority_check(text, text, text) to service_role;

-- ============================================================ 5. closing the other two doors
--
-- Two pre-existing tables could put a non-refund decision in front of the founder.  Measured
-- before this file was written:
--
--   public.founder_release_approval      1 row.  id=1, approved_at 2026-08-10 18:12 UTC,
--                                        approved_by management@quotesdone.com, release_ref
--                                        f756bcb.  It is a COMPLETED, dated, attributed record
--                                        of an approval the founder actually gave — evidence,
--                                        not a queue item.  Phase C does not delete it; deleting
--                                        the founder's own approval record to make a count look
--                                        better would be exactly the fabrication this project
--                                        forbids.  What Phase C does is close the door so no
--                                        SECOND one can ever be created.
--
--   public.procurement_approval_request  0 rows.  The door is closed the same way.
--
-- After this file, a release approval is the internal gate the autonomy policy names
-- (qa_release_management_director, with cybersecurity_engineer and model_evaluation_reviewer as
-- independent reviewers), and a procurement approval is company_payment_within_budget under
-- accounts_payable_specialist with financial_controller reviewing.  Neither reaches the founder.
create or replace function public.fn_phase_c_no_new_founder_approval_path()
returns trigger language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  raise exception
    'Phase C founder autonomy: % is not an approval path any more. The founder receives exactly one routine manual approval, a specific refund decision. Route this to the internal authority gate (fn_phase_c_authority_check) instead.',
    tg_table_name using errcode = '23514';
end $$;

drop trigger if exists z10_phase_c_no_new_release_approval on public.founder_release_approval;
create trigger z10_phase_c_no_new_release_approval before insert on public.founder_release_approval
  for each row execute function public.fn_phase_c_no_new_founder_approval_path();

drop trigger if exists z10_phase_c_no_new_procurement_approval on public.procurement_approval_request;
create trigger z10_phase_c_no_new_procurement_approval before insert on public.procurement_approval_request
  for each row execute function public.fn_phase_c_no_new_founder_approval_path();

-- ============================================================ 6. what reaches the founder
--
-- The measurement the founder asked for by name, as a view so it can be re-run rather than
-- quoted.  It names exactly what it looked at and keeps four different things separate:
--
--   founder_approval_request           the Phase C queue, refund-only by three guards
--   founder_release_approval           pre-existing; 1 completed historical record, door closed
--   procurement_approval_request       pre-existing; 0 rows, door closed
--   org_action_executor.notifies_human an executor that MESSAGES a human. This is not the same
--                                      field as "creates a founder approval request", and it is
--                                      not conflated with one here. Ten are active and none is
--                                      a refund; what they do is send mail, not open a queue.
create or replace view public.v_phase_c_what_reaches_the_founder as
select 'founder_approval_request' as surface,
       'approval request the founder must decide' as kind,
       count(*)::bigint as rows_total,
       count(*) filter (where state = 'pending')::bigint as awaiting_founder,
       count(*) filter (where action_class <> 'refund_decision')::bigint as non_refund_rows
from public.founder_approval_request
union all
select 'founder_release_approval', 'completed historical record; insert refused since Phase C',
       count(*)::bigint, count(*) filter (where approved_at is null)::bigint, count(*)::bigint
from public.founder_release_approval
union all
select 'procurement_approval_request', 'insert refused since Phase C',
       count(*)::bigint, count(*) filter (where status = 'pending')::bigint, count(*)::bigint
from public.procurement_approval_request
union all
select 'org_action_executor.notifies_human', 'executor that messages a human — not an approval queue',
       count(*)::bigint, 0::bigint, 0::bigint
from public.org_action_executor where notifies_human and active;

-- The invariant number, on its own, so no reader has to sum four different things to get it.
-- It counts what is WAITING for the founder and is not a refund.  A completed historical
-- approval is evidence of a past decision, not a decision he still owes; counting it would make
-- the number permanently non-zero and therefore permanently uninformative.  The insert triggers
-- above are what stop the historical set from growing.
create or replace function public.fn_phase_c_non_refund_founder_approvals()
returns bigint language sql stable set search_path to 'public', 'pg_temp' as $$
  select (select count(*) from public.founder_approval_request
           where action_class <> 'refund_decision' and state = 'pending')
       + (select count(*) from public.founder_release_approval where approved_at is null)
       + (select count(*) from public.procurement_approval_request where status = 'pending');
$$;
revoke all on function public.fn_phase_c_non_refund_founder_approvals() from public;
grant execute on function public.fn_phase_c_non_refund_founder_approvals() to service_role;
