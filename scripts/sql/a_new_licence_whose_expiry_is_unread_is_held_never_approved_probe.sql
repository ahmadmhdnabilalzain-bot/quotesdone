-- Assigned: sales_engineer
-- PURE PROBE (no DDL): raises at the end so everything rolls back. 12 Oct 2026, review of #1353.
-- #1353 makes process_docs CLEAR license_expiry when a new licence is uploaded (the old licence's date must never
-- judge a new document) and refuses an ungrounded model read. The hole the review named: name read, expiry not
-- read -> a null expiry is "not expired" -> could the review approve it? It must not: the supplier is held as
-- licence_expiry_unread (ruling 1177: ask for a clearer copy), never approved, whether he was approved before or not.
-- One ZZ DEMO supplier (@example.invalid, the demo-fixture convention; never a real row); rows of a live stage-2 run
-- are excluded by its tag. Every case writes exactly the columns process_docs writes; z20 re-runs the verification.
--   approved : approved supplier, new licence, name + number read, expiry unread -> pending / licence_expiry_unread
--   auto     : same with auto-approve on and the supplier pending               -> pending / licence_expiry_unread
--   control  : the expiry is then read as a future date                         -> not held for the expiry
do $$
declare v_id bigint; a public.leads; p public.leads; c public.leads; v_rev text; v_real_before bigint; v_real_after bigint;
begin
  select id into v_id from public.leads
   where company_name like 'ZZ DEMO%' and email like '%@example.invalid' and company_name not like '%1be65ab2%'
     and approval_status = 'approved' and cardinality(public.fn_supplier_mandatory_six(leads)) = 0
   order by id limit 1;
  if v_id is null then raise exception 'CHK<<PROBE FAILED: no approved ZZ DEMO supplier to probe>>'; end if;
  select count(*) into v_real_before from public.leads where approval_status = 'approved' and id <> v_id;

  -- approved: what process_docs (#1353) writes for a new licence whose name and number were read, expiry not
  update public.leads set license_doc_path = license_doc_path, licence_legal_name = company_name,
                          trade_license_no = coalesce(nullif(btrim(trade_license_no), ''), 'CN-7731905'),
                          license_expiry = null, doc_extracted_at = null where id = v_id;
  select * into a from public.leads where id = v_id;
  select status into v_rev from public.agent_actions
   where agent = 'sales_engineer' and kind = 'supplier_verification' and target_id = v_id::text order by id desc limit 1;

  -- auto: auto-approve on, supplier pending, the same unread expiry, verification asked again
  update public.pricing_config set auto_approve_suppliers = true where id = 1;
  perform public.fn_sales_engineer_verifies_supplier(v_id, 'save_profile');
  select * into p from public.leads where id = v_id;

  -- control: the expiry is read (a future date) on the same licence
  update public.leads set license_expiry = current_date + 365 where id = v_id;
  perform public.fn_sales_engineer_verifies_supplier(v_id, 'save_profile');
  select * into c from public.leads where id = v_id;
  select count(*) into v_real_after from public.leads where approval_status = 'approved' and id <> v_id;

  raise exception 'CHK<<%>>', case
    when a.approval_status = 'pending' and a.licence_gate_reason = 'licence_expiry_unread' and not coalesce(a.verified, false)
         and v_rev = 'needs_review'
         and p.approval_status = 'pending' and p.licence_gate_reason = 'licence_expiry_unread' and not coalesce(p.verified, false)
         and coalesce(c.licence_gate_reason, '') <> 'licence_expiry_unread' and v_real_before = v_real_after
      then 'PROBE OK: ZZ DEMO ' || v_id || ' approved + new licence, expiry unread -> pending/licence_expiry_unread (needs_review); '
           || 'auto-approve on -> still held; expiry read -> ' || coalesce(c.approval_status, 'null') || '; other approvals untouched (' || v_real_after || ')'
    else 'PROBE FAILED: approved=' || coalesce(a.approval_status, 'null') || '/' || coalesce(a.licence_gate_reason, 'null') || ' review=' || coalesce(v_rev, 'null')
         || ' auto=' || coalesce(p.approval_status, 'null') || '/' || coalesce(p.licence_gate_reason, 'null')
         || ' control=' || coalesce(c.approval_status, 'null') || '/' || coalesce(c.licence_gate_reason, 'null') end;
end $$;
