-- Assigned: sales_engineer
-- PURE PROBE (no DDL): raises at the end so everything rolls back. Run AFTER
-- an_approved_supplier_who_swaps_in_an_unreadable_licence_is_held_again.sql is applied.
-- Takes one APPROVED ZZ DEMO supplier (@example.invalid, the demo-fixture convention; never a real row),
-- gives it a read licence name, then makes ONLY the write supplier_api process_docs makes for a new
-- licence whose name code cannot read: a new license_doc_path and licence_legal_name null. It never
-- calls fn_sales_engineer_verifies_supplier itself - the trigger must. Expected: pending/licence_unreadable.
do $$
declare v_id bigint; a public.leads; b public.leads; v_real_before bigint; v_real_after bigint;
begin
  select id into v_id from public.leads
   where company_name like 'ZZ DEMO%' and email like '%@example.invalid'
     and approval_status = 'approved' and cardinality(public.fn_supplier_mandatory_six(leads)) = 0
   order by id limit 1;
  if v_id is null then raise exception 'CHK<<PROBE FAILED: no approved ZZ DEMO supplier to probe>>'; end if;
  select count(*) into v_real_before from public.leads where approval_status = 'approved' and id <> v_id;

  update public.leads set licence_legal_name = company_name where id = v_id;
  select * into a from public.leads where id = v_id;
  -- same object path (it exists in storage, so the six gate stays satisfied); the column is still
  -- written, and the name goes from read to unread exactly as process_docs writes it
  update public.leads set license_doc_path = license_doc_path, licence_legal_name = null where id = v_id;
  select * into b from public.leads where id = v_id;
  select count(*) into v_real_after from public.leads where approval_status = 'approved' and id <> v_id;

  raise exception 'CHK<<%>>', case
    when a.approval_status = 'approved'
         and b.approval_status = 'pending' and b.licence_gate_reason = 'licence_unreadable'
         and not coalesce(b.verified, false) and v_real_before = v_real_after
      then 'PROBE OK: ZZ DEMO supplier ' || v_id || ' approved -> pending/licence_unreadable by the trigger alone; other approvals untouched (' || v_real_after || ')'
    else 'PROBE FAILED: before=' || coalesce(a.approval_status, 'null') || ' after=' || coalesce(b.approval_status, 'null')
         || '/' || coalesce(b.licence_gate_reason, 'null') end;
end $$;
