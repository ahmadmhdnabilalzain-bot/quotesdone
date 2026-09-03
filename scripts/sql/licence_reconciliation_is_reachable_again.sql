-- fn_reconcile_licence_blocks IS REACHABLE AGAIN, AND ITS COMPONENT SAYS SO (4 Sep 2026).
--
-- The supply agent's rewritten fn_doc_expiry_scan (3 Sep 2026) suspends and restores matching through
-- public.fn_reconcile_licence_blocks(p_grace_days integer), whose component row still read
-- DEFERRED_RUNTIME_IMPLEMENTATION / inactive from the Phase C inventory. The exposure board measured
-- the truth (deferred_or_inactive_but_reachable 1 of 148: derived ACTIVE_INTERNAL_CALLER via
-- fn_doc_expiry_scan). The row now records what production does; the classification guard accepts an
-- ACTIVE_* row only because the derivation reaches it, which it does.
--
--   node scripts/apply_sql.mjs scripts/sql/licence_reconciliation_is_reachable_again.sql --apply --ddl
update public.phase_c_component
   set activation_state = 'deployed', classification = 'ACTIVE_INTERNAL_CALLER',
       accountable_role_id = 'supplier_verification', department_id = 'supply',
       repair_or_keep_action = 'keep; reachable again since 3 Sep 2026 through fn_doc_expiry_scan (licence expiry suspends and restores matching through it); owned by the Verification seat of Supply',
       evidence = coalesce(evidence, '') || ' | 4 Sep 2026: fn_kernel_component_reachability derives ACTIVE_INTERNAL_CALLER (internal_caller: fn_doc_expiry_scan)'
 where component_id = 'dbfn:fn_reconcile_licence_blocks(p_grace_days integer)';

do $proof$
declare v text;
begin
  select actual into v from public.fn_kernel_component_exposure_state() where check_name = 'deferred_or_inactive_but_reachable';
  if v not like '0 of %' then raise exception 'exposure board still reports %', v; end if;
  raise notice 'proof: deferred_or_inactive_but_reachable = %', v;
end $proof$;
