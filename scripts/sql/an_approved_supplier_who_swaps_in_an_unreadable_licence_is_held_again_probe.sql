-- Assigned: sales_engineer
-- PURE PROBE (no DDL): raises at the end so everything rolls back. Run AFTER
-- an_approved_supplier_who_swaps_in_an_unreadable_licence_is_held_again.sql is applied (or with it, first, in
-- the same rolled-back transaction).
-- One APPROVED ZZ DEMO supplier (@example.invalid, the demo-fixture convention; never a real row). Every case
-- writes columns only, as the upload paths do; the routine is called by hand only for the save_profile control,
-- because save_profile itself calls it that way.
--   control  : licence name = registered name, then an ordinary profile save -> stays approved
--   unread   : new licence, name null (process_docs on a scan)               -> pending / licence_unreadable
--   mismatch : new licence naming another company                            -> pending / licence_name_mismatch, needs_review
do $$
declare v_id bigint; c1 public.leads; c2 public.leads; u public.leads; m public.leads; s public.leads; v_rev text; s_rev text; s_rec text;
        v_real_before bigint; v_real_after bigint;
begin
  select id into v_id from public.leads
   where company_name like 'ZZ DEMO%' and email like '%@example.invalid'
     and approval_status = 'approved' and cardinality(public.fn_supplier_mandatory_six(leads)) = 0
   order by id limit 1;
  if v_id is null then raise exception 'CHK<<PROBE FAILED: no approved ZZ DEMO supplier to probe>>'; end if;
  select count(*) into v_real_before from public.leads where approval_status = 'approved' and id <> v_id;

  -- control: the licence names this company, then a profile save that touches no licence column
  update public.leads set licence_legal_name = company_name where id = v_id;
  select * into c1 from public.leads where id = v_id;
  update public.leads set description = coalesce(description, '') || ' (probe)', phone_e164 = phone_e164 where id = v_id;
  perform public.fn_sales_engineer_verifies_supplier(v_id, 'save_profile');
  select * into c2 from public.leads where id = v_id;

  -- unread: what process_docs writes for a licence code cannot name
  update public.leads set license_doc_path = license_doc_path, licence_legal_name = null where id = v_id;
  select * into u from public.leads where id = v_id;

  -- back to approved with a matching name (the six are complete, so the six gate allows it)
  update public.leads set approval_status = 'approved', verified = true, licence_gate_reason = null,
                          licence_legal_name = company_name where id = v_id;
  -- mismatch: a new, READABLE licence that names another company
  update public.leads set license_doc_path = license_doc_path, licence_legal_name = 'Totally Unrelated Steel Trading LLC' where id = v_id;
  select * into m from public.leads where id = v_id;
  select status into v_rev from public.agent_actions
   where agent = 'sales_engineer' and kind = 'supplier_verification' and target_id = v_id::text
   order by id desc limit 1;
  -- save: an approved supplier ALREADY holding another company's licence saves his profile. Status and name
  -- land in one statement; the name does not change, so z20 does not run and only the save asks.
  update public.leads set approval_status = 'approved', verified = true, licence_gate_reason = null where id = v_id;
  perform public.fn_sales_engineer_verifies_supplier(v_id, 'save_profile');
  select * into s from public.leads where id = v_id;
  select status, recommendation into s_rev, s_rec from public.agent_actions
   where agent = 'sales_engineer' and kind = 'supplier_verification' and target_id = v_id::text
   order by id desc limit 1;
  select count(*) into v_real_after from public.leads where approval_status = 'approved' and id <> v_id;

  raise exception 'CHK<<%>>', case
    when c1.approval_status = 'approved' and c2.approval_status = 'approved' and c2.verified
         and u.approval_status = 'pending' and u.licence_gate_reason = 'licence_unreadable' and not coalesce(u.verified, false)
         and m.approval_status = 'pending' and m.licence_gate_reason = 'licence_name_mismatch' and not coalesce(m.verified, false)
         and v_rev = 'needs_review' and v_real_before = v_real_after
         and s.approval_status = 'pending' and s.licence_gate_reason = 'licence_name_mismatch'
         and s_rev = 'needs_review' and s_rec not ilike '%name matches%'
      then 'PROBE OK: ZZ DEMO ' || v_id || ' control approved->approved after a profile save; unread -> pending/licence_unreadable; '
           || 'other company''s licence -> pending/licence_name_mismatch (needs_review); approved + other company''s licence + profile save -> held, log truthful; other approvals untouched (' || v_real_after || ')'
    else 'PROBE FAILED: control=' || coalesce(c1.approval_status, 'null') || '>' || coalesce(c2.approval_status, 'null')
         || ' unread=' || coalesce(u.approval_status, 'null') || '/' || coalesce(u.licence_gate_reason, 'null')
         || ' mismatch=' || coalesce(m.approval_status, 'null') || '/' || coalesce(m.licence_gate_reason, 'null') || ' review=' || coalesce(v_rev, 'null') || ' save=' || coalesce(s.approval_status, 'null') || '/' || coalesce(s.licence_gate_reason, 'null')
         || ' save_log=' || coalesce(s_rev, 'null') || ':' || left(coalesce(s_rec, 'null'), 60) end;
end $$;
