-- ============================================================================================
-- KERNEL K8 — REFUND-ONLY FOUNDER APPROVAL
--
-- Two of the three claims in this area were already true and are left alone: founder_approval_request
-- carries z10_founder_approval_refund_only, and phase_c_action_class names exactly one class,
-- refund_decision, as founder_approval_required. What the audit found was that neither of them was
-- the surface the founder actually sees.
--
--   v_founder_inbox  =  select ... from agent_actions where status = 'needs_review'
--                       with kind in (payment_approval, purchase_order, refund_decision,
--                       credential_change, legal_flag, security_incident, supplier_ban,
--                       data_deletion) bucketed as 'blocking' and EVERYTHING ELSE as
--                       'automation_gap'.
--
-- Seven non-refund blocking kinds and an open-ended catch-all, on a view named for the founder's
-- inbox. And org_tasks.needs_founder was unrestricted: 46 rows carry it today and NOT ONE is a
-- refund — analysis 17, investigate 17, evolution_scan 2, capability_review 2, legal_review 2,
-- role_define, capability_enrich, supplier_verify, brand_scan, nudge, outreach_draft.
--
-- Nothing is deleted. The work those rows represent still needs a human; it needs the ACCOUNTABLE
-- HUMAN, which is a canonical role, not the founder. So the queue is split rather than emptied:
-- v_founder_inbox becomes refund-only, and v_internal_escalation_queue carries everything else to
-- the role that owns it. A queue that quietly discarded seven kinds would have been a worse defect
-- than the one being fixed.
-- ============================================================================================

-- ------------------------------------------------- 1. a refund decision is append-only, and final
--
-- phase_c_refund_decision carried UNIQUE(request_id), which makes 'a changed decision is a new
-- superseding record' impossible: the second row cannot exist. Replaced with a partial unique index
-- on the ORIGINAL decision — exactly one row per request that supersedes nothing — so a chain of
-- supersessions is expressible and a second independent original is still refused.
alter table public.phase_c_refund_decision
  add column if not exists supersedes_decision_id bigint
    references public.phase_c_refund_decision(decision_id),
  add column if not exists supersession_reason text;

-- It is a bare UNIQUE INDEX, not a table constraint, so `drop constraint if exists` is a silent
-- no-op on it — the same shape as `revoke ... from anon` when the grant is held through PUBLIC.
-- Dropped by its real kind, and the partial replacement created in the same statement pair.
drop index if exists public.phase_c_refund_decision_request_uk;
alter table public.phase_c_refund_decision drop constraint if exists phase_c_refund_decision_request_uk;
create unique index if not exists phase_c_refund_decision_original_uk
  on public.phase_c_refund_decision (request_id) where supersedes_decision_id is null;

do $sup$
begin
  if not exists (select 1 from pg_constraint where conname = 'phase_c_refund_decision_supersession_ck') then
    alter table public.phase_c_refund_decision
      add constraint phase_c_refund_decision_supersession_ck
      check ((supersedes_decision_id is null) = (coalesce(supersession_reason,'') = ''));
  end if;
end $sup$;

create or replace function public.fn_phase_c_refund_decision_immutable()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  if tg_op = 'DELETE' then
    raise exception
      'phase_c_refund_decision %: a founder refund decision cannot be deleted', old.decision_id
      using errcode = '23514',
            hint = 'A decision that changed is a NEW row citing the old one in '
                || 'supersedes_decision_id, with supersession_reason. The record of what was '
                || 'decided, by whom and when is the point of the table.';
  end if;

  -- The decision itself is frozen. Only the post-decision execution record may be filled in, and
  -- only once, and only from NULL: an executor cannot rewrite who approved, or why, or when.
  if new.decided_by  is distinct from old.decided_by
     or new.decision is distinct from old.decision
     or new.reason   is distinct from old.reason
     or new.decided_at is distinct from old.decided_at
     or new.request_id is distinct from old.request_id then
    raise exception
      'phase_c_refund_decision %: the decision is append-only; supersede it, do not edit it',
      old.decision_id
      using errcode = '23514',
            hint = 'Insert a NEW decision whose supersedes_decision_id points at this one.';
  end if;

  if old.executed_at   is not null and new.executed_at   is distinct from old.executed_at   then
    raise exception 'phase_c_refund_decision %: executed_at is written once', old.decision_id using errcode = '23514';
  end if;
  if old.reconciled_at is not null and new.reconciled_at is distinct from old.reconciled_at then
    raise exception 'phase_c_refund_decision %: reconciled_at is written once', old.decision_id using errcode = '23514';
  end if;

  return new;
end $$;

revoke all on function public.fn_phase_c_refund_decision_immutable() from public;

drop trigger if exists a00_phase_c_refund_decision_immutable on public.phase_c_refund_decision;
create trigger a00_phase_c_refund_decision_immutable
  before update or delete on public.phase_c_refund_decision
  for each row execute function public.fn_phase_c_refund_decision_immutable();

-- ------------------------------------------- 2. the decider is the founder, through the K0 verifier
-- The existing guard checked phase_c_founder_identity directly and accepted any active row — which
-- on 16 Aug included build-mode@quotesdone.local. K0 built one verifier so this kind of check has a
-- single definition to share; this is that share, not a second copy.
create or replace function public.fn_phase_c_refund_decision_guard()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  perform public.fn_phase_c_require_founder(new.decided_by);   -- raises 28000 for anyone else

  if new.executed_at is not null and new.decision <> 'approved' then
    raise exception 'phase_c_refund_decision %: execution recorded against a % decision',
      new.decision_id, new.decision using errcode = '23514';
  end if;
  if new.reconciled_at is not null and new.executed_at is null then
    raise exception 'phase_c_refund_decision %: reconciled before it was executed', new.decision_id
      using errcode = '23514';
  end if;
  if new.executor_role_id is not null and new.reconciler_role_id is not null
     and new.executor_role_id = new.reconciler_role_id then
    raise exception 'phase_c_refund_decision %: the executor and the reconciler are the same role (%)',
      new.decision_id, new.executor_role_id using errcode = '23514';
  end if;
  return new;
end $$;

-- ------------------------------------------- 3. no non-refund routine action may route to founder
create or replace function public.fn_kernel_founder_routing_is_refund_only()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  -- Only fires when a row is NEWLY routed to the founder. Historical rows stay editable so the 46
  -- closed ones can still be maintained; what is refused is CREATING more of them.
  if coalesce(new.needs_founder, false)
     and (tg_op = 'INSERT'
          or coalesce(old.needs_founder, false) is distinct from true
          or old.action_class is distinct from new.action_class)
     and not exists (select 1 from public.phase_c_action_class
                      where action_class = new.action_class and founder_approval_required) then
    raise exception
      'org_tasks: action_class % cannot be routed to the founder; only a refund decision reaches him',
      coalesce(new.action_class, '(null)')
      using errcode = '23514',
            hint = 'Escalate to the accountable canonical role instead. phase_c_action_class names '
                || 'the classes that require a founder decision, and today that is refund_decision '
                || 'and nothing else.';
  end if;
  return new;
end $$;

revoke all on function public.fn_kernel_founder_routing_is_refund_only() from public;

drop trigger if exists a00_org_tasks_founder_routing_refund_only on public.org_tasks;
create trigger a00_org_tasks_founder_routing_refund_only
  before insert or update on public.org_tasks
  for each row execute function public.fn_kernel_founder_routing_is_refund_only();

-- ------------------------------------------------------- 4. split the queue, do not empty it
-- What the founder sees.
create or replace view public.v_founder_inbox as
  select a.id, a.created_at, a.agent, a.kind, a.risk, a.title, a.recommendation,
         a.target_table, a.target_id, 'refund_decision'::text as bucket
    from public.agent_actions a
   where a.status = 'needs_review'
     and exists (select 1 from public.phase_c_action_class c
                  where c.action_class = a.kind and c.founder_approval_required);

comment on view public.v_founder_inbox is
  'REFUND ONLY (kernel K8, 17 Aug 2026). This view used to select every agent_actions row in '
  'needs_review and bucket seven non-refund kinds as "blocking" on a surface named for the '
  'founder. Membership is now derived from phase_c_action_class.founder_approval_required, which '
  'names refund_decision and nothing else, so widening it means changing the action class, not '
  'editing a view. Everything else moved to v_internal_escalation_queue.';

-- What the accountable role sees. Nothing was discarded; it changed audience.
create or replace view public.v_internal_escalation_queue as
  select a.id, a.created_at, a.agent, a.kind, a.risk, a.title, a.recommendation,
         a.target_table, a.target_id,
         case when a.kind = any (array['payment_approval','purchase_order','credential_change',
                                       'legal_flag','security_incident','supplier_ban','data_deletion'])
              then 'blocking' else 'automation_gap' end as bucket
    from public.agent_actions a
   where a.status = 'needs_review'
     and not exists (select 1 from public.phase_c_action_class c
                      where c.action_class = a.kind and c.founder_approval_required);

comment on view public.v_internal_escalation_queue is
  'The seven blocking kinds and the automation-gap catch-all that used to sit in v_founder_inbox. '
  'These need a human; they need the ACCOUNTABLE human, which is a canonical role. Phase D gives '
  'each kind its owning role.';

-- ------------------------------------------------------------------- 5. the invariant that watches
-- ROUTINE REMOVED 7 September 2026. public.fn_kernel_founder_approval_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke all on function public.fn_kernel_founder_approval_state() from public;
grant execute on function public.fn_kernel_founder_approval_state() to service_role;
