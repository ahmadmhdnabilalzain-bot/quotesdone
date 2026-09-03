-- fn_kernel_refund_decision_record reads the refund roles from decision_policy (3 Sep 2026).
--
-- MASTER_PLAN 5.3: the money path defaulted its executor and reconciler to the literals
-- payments_and_billing_manager / financial_controller, so a role rename would have orphaned every
-- refund record silently. The two roles are now rows in decision_policy (below), resolved through
-- fn_org_role_resolve so an alias or rename still lands on the active canonical role, and an unset
-- or unresolvable policy REFUSES the record instead of guessing. Every other line of the function is
-- the live definition, unchanged.
--
--   node scripts/apply_sql.mjs scripts/sql/refund_roles_are_policy_not_literals.sql --apply --ddl
insert into public.decision_policy (key, value, description)
values
  ('refund_executor_role_id', to_jsonb('payments_and_billing_manager'::text),
   'The canonical role that executes an approved refund on the payment provider (fn_kernel_refund_decision_record op=execute). Resolved through the alias registry; unset refuses.'),
  ('refund_reconciler_role_id', to_jsonb('financial_controller'::text),
   'The canonical role that reconciles an executed refund into the ledger (fn_kernel_refund_decision_record op=reconcile). Resolved through the alias registry; unset refuses.')
on conflict (key) do nothing;

CREATE OR REPLACE FUNCTION public.fn_kernel_refund_decision_record(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_op        text   := lower(coalesce(nullif(btrim(p_input->>'op'),''), 'record'));
  v_request   bigint := nullif(btrim(coalesce(p_input->>'request_id','')), '')::bigint;
  v_decision  text   := lower(coalesce(btrim(p_input->>'decision'), ''));
  v_reason    text   := coalesce(btrim(p_input->>'reason'), '');
  v_super     bigint := nullif(btrim(coalesce(p_input->>'supersedes_decision_id','')), '')::bigint;
  v_super_why text   := coalesce(btrim(p_input->>'supersession_reason'), '');
  v_exec_role text   := nullif(btrim(coalesce(p_input->>'executor_role_id','')), '');
  v_rec_role  text   := nullif(btrim(coalesce(p_input->>'reconciler_role_id','')), '');
  v_target    bigint := nullif(btrim(coalesce(p_input->>'decision_id','')), '')::bigint;
  v_founder   text;
  v_id        bigint;
  d           public.phase_c_refund_decision%rowtype;
begin
  -- THE IDENTITY IS RESOLVED, NEVER ACCEPTED. fn_phase_c_require_founder raises 28000 when the
  -- call carries no verified auth subject; a caller-supplied identity string is an assertion it
  -- checks against the verified one, and never a source.
  v_founder := public.fn_phase_c_require_founder(nullif(btrim(p_input->>'decided_by'),''));

  if v_op not in ('record','execute','reconcile') then
    raise exception 'fn_kernel_refund_decision_record: op must be record, execute or reconcile, got % (pd_refund_decision_op_unknown)',
      v_op using errcode = '22023';
  end if;

  -- ---- THE TWO THINGS THIS SERVICE WILL NOT DO -------------------------------------------------
  -- Stated here rather than left for a caller to discover from the table trigger, because a
  -- service that quietly forwards an edit to a guard is a service that taught its callers the
  -- edit was worth trying.
  if coalesce((p_input->>'edit')::boolean, false) or coalesce((p_input->>'delete')::boolean, false) then
    raise exception 'fn_kernel_refund_decision_record: a founder refund decision is append-only. Record a NEW decision citing the prior one in supersedes_decision_id with a supersession_reason. (pd_refund_decision_append_only)'
      using errcode = '23514';
  end if;

  if v_op = 'record' then
    if v_request is null then
      raise exception 'fn_kernel_refund_decision_record: request_id is required and names the founder_approval_request this decision answers (pd_refund_decision_request_absent)'
        using errcode = '22023';
    end if;
    if v_decision not in ('approved','rejected') then
      raise exception 'fn_kernel_refund_decision_record: decision must be approved or rejected, got % (pd_refund_decision_verdict_unknown)',
        v_decision using errcode = '22023';
    end if;
    if v_reason = '' then
      raise exception 'fn_kernel_refund_decision_record: a refund decision with no stated reason is not a decision (pd_refund_decision_reason_absent)'
        using errcode = '23514';
    end if;
    -- The supersession pair is all-or-nothing at the table too
    -- (phase_c_refund_decision_supersession_ck); refusing it here names which half is missing.
    if (v_super is null) <> (v_super_why = '') then
      raise exception 'fn_kernel_refund_decision_record: supersedes_decision_id and supersession_reason are given together or not at all (pd_refund_decision_supersession_incomplete)'
        using errcode = '23514';
    end if;
    if v_super is not null and not exists (
         select 1 from public.phase_c_refund_decision x where x.decision_id = v_super) then
      raise exception 'fn_kernel_refund_decision_record: decision % does not exist, so nothing can supersede it (pd_refund_decision_supersedes_unknown)',
        v_super using errcode = '23503';
    end if;

  -- 3 SEP 2026 (MASTER_PLAN 5.3): the refund executor and reconciler are DATA (decision_policy
  -- refund_executor_role_id / refund_reconciler_role_id), resolved through the alias registry so a
  -- role rename cannot orphan the money path, and an unset or unresolvable policy refuses rather
  -- than defaulting to a name typed here.
  v_exec_role := coalesce(v_exec_role, public.fn_org_role_resolve((select p.value #>> '{}' from public.decision_policy p where p.key = 'refund_executor_role_id')));
  v_rec_role  := coalesce(v_rec_role,  public.fn_org_role_resolve((select p.value #>> '{}' from public.decision_policy p where p.key = 'refund_reconciler_role_id')));
  if v_exec_role is null or v_rec_role is null then
    raise exception 'fn_kernel_refund_decision_record: refund executor/reconciler roles are not configured or do not resolve to an active canonical role (decision_policy refund_executor_role_id / refund_reconciler_role_id) (pd_refund_roles_unconfigured)'
      using errcode = '22023';
  end if;

    insert into public.phase_c_refund_decision
      (request_id, decided_by, decision, reason, supersedes_decision_id, supersession_reason,
       executor_role_id, reconciler_role_id)
    values (v_request, v_founder, v_decision, v_reason, v_super, nullif(v_super_why,''),
            v_exec_role,
            v_rec_role)
    returning decision_id into v_id;

    select * into d from public.phase_c_refund_decision where decision_id = v_id;
    return jsonb_build_object('ok', true, 'op','record', 'decision_id', v_id,
      'decided_by', d.decided_by, 'decision', d.decision,
      'supersedes_decision_id', d.supersedes_decision_id,
      'note','decided_by is the identity fn_phase_c_require_founder verified, not the identity the call named');
  end if;

  -- ---- execute / reconcile: the only two columns the frozen trigger lets an UPDATE fill ---------
  if v_target is null then
    raise exception 'fn_kernel_refund_decision_record: decision_id is required for op % (pd_refund_decision_target_absent)',
      v_op using errcode = '22023';
  end if;
  select * into d from public.phase_c_refund_decision where decision_id = v_target;
  if not found then
    raise exception 'fn_kernel_refund_decision_record: no decision % (pd_refund_decision_unknown)',
      v_target using errcode = '23503';
  end if;
  if d.decision <> 'approved' then
    raise exception 'fn_kernel_refund_decision_record: decision % is %, so no refund may be executed against it (pd_refund_execution_without_founder_decision)',
      v_target, d.decision using errcode = '23514';
  end if;
  if exists (select 1 from public.phase_c_refund_decision s where s.supersedes_decision_id = v_target) then
    raise exception 'fn_kernel_refund_decision_record: decision % has been superseded and is no longer the founder''s decision (pd_refund_execution_without_founder_decision)',
      v_target using errcode = '23514';
  end if;

  if v_op = 'execute' then
    update public.phase_c_refund_decision set executed_at = now() where decision_id = v_target;
  else
    update public.phase_c_refund_decision set reconciled_at = now() where decision_id = v_target;
  end if;
  select * into d from public.phase_c_refund_decision where decision_id = v_target;
  return jsonb_build_object('ok', true, 'op', v_op, 'decision_id', v_target,
    'executed_at', d.executed_at, 'reconciled_at', d.reconciled_at);
end $function$

