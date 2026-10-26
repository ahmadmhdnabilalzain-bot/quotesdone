-- ROLLBACK for kernel_k8_refund_only_founder_approval.sql
--
-- Restores the general founder inbox and removes the refund-decision immutability. Running this
-- puts seven non-refund kinds back on a surface named for the founder, so it is a deliberate
-- decision, not a tidy-up.
--
-- The supersedes_decision_id / supersession_reason columns and the closed org_tasks rows are kept:
-- dropping them destroys the record of what was decided and superseded.

begin;

drop trigger if exists a00_phase_c_refund_decision_immutable on public.phase_c_refund_decision;
drop function if exists public.fn_phase_c_refund_decision_immutable();

drop trigger if exists a00_org_tasks_founder_routing_refund_only on public.org_tasks;
drop function if exists public.fn_kernel_founder_routing_is_refund_only();

drop function if exists public.fn_kernel_founder_approval_state();
drop view if exists public.v_internal_escalation_queue;

-- the pre-K8 general inbox, verbatim
create or replace view public.v_founder_inbox as
  select id, created_at, agent, kind, risk, title, recommendation, target_table, target_id,
         case when kind = any (array['payment_approval','purchase_order','refund_decision',
                                     'credential_change','legal_flag','security_incident',
                                     'supplier_ban','data_deletion'])
              then 'blocking' else 'automation_gap' end as bucket
    from public.agent_actions a
   where status = 'needs_review';

-- fn_phase_c_refund_decision_guard is NOT reverted: it now calls fn_phase_c_require_founder, which
-- is strictly narrower than the check it replaced (it refuses a non-email identity). Reverting it
-- would re-admit a machine identity as a refund approver.

-- The unique index is NOT restored. phase_c_refund_decision_original_uk still refuses a second
-- ORIGINAL decision per request; restoring UNIQUE(request_id) would delete supersession rows.

commit;
