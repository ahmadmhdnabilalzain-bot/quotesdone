-- Assigned: sales_engineer
-- PURE PROBE (no DDL): raises at the end so everything rolls back. Run AFTER
-- a_supplier_whose_licence_could_not_be_read_is_held_never_approved.sql is applied.
-- Takes one APPROVED ZZ DEMO supplier (@example.invalid, the demo-fixture convention; never a real row),
-- empties its licence name (= the licence could not be read: extraction stubbed, failed or unreadable)
-- and asks the sales engineer's review. Expected: pending, reason licence_unreadable, never approved.
do $$
declare v_id bigint; v_rev jsonb; v_row public.leads; v_real_before bigint; v_real_after bigint;
begin
  select id into v_id from public.leads
   where company_name like 'ZZ DEMO%' and email like '%@example.invalid'
     and approval_status = 'approved' and cardinality(public.fn_supplier_mandatory_six(leads)) = 0
   order by id limit 1;
  if v_id is null then raise exception 'CHK<<PROBE FAILED: no approved ZZ DEMO supplier to probe>>'; end if;
  select count(*) into v_real_before from public.leads where approval_status = 'approved' and id <> v_id;

  update public.leads set licence_legal_name = null where id = v_id;
  v_rev := public.fn_sales_engineer_verifies_supplier(v_id, 'probe');
  select * into v_row from public.leads where id = v_id;
  select count(*) into v_real_after from public.leads where approval_status = 'approved' and id <> v_id;

  raise exception 'CHK<<%>>', case
    when v_row.approval_status = 'pending' and v_row.licence_gate_reason = 'licence_unreadable'
         and not coalesce(v_row.verified, false) and v_real_before = v_real_after
      then 'PROBE OK: ZZ DEMO supplier ' || v_id || ' held pending/licence_unreadable; other approvals untouched (' || v_real_after || ')'
    else 'PROBE FAILED: ' || v_rev::text || ' status=' || coalesce(v_row.approval_status, 'null') || ' reason=' || coalesce(v_row.licence_gate_reason, 'null') end;
end $$;
