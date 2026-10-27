-- PROBE for the_it_engineer_finds_duplicate_contacts_by_email_and_merges_only_reviewed_or_demo_ones.sql
-- Pure, ZZ DEMO / @example.invalid only, one aborted transaction: run AFTER the .sql in the same query.
-- Ends in raise exception 'CHK<<...>>' so everything (the DDL included) rolls back. Contacts no one.
do $p$
declare v_tag text := substr(md5(random()::text), 1, 8);
        a bigint; b bigint; c bigint; f bigint; e uuid; ga uuid; gx uuid; r jsonb; n int; v_ok boolean;
        n_leads_before int; n_leads_after int; v_rep jsonb;
begin
  -- A: the scraped lead (unclaimed). B: the same supplier registered fresh, its LOGIN is A's email.
  insert into public.leads (company_name, email, phone) values
    ('ZZ DEMO dedup A ' || v_tag, 'zz-dedup-' || v_tag || '@example.invalid', '+971 50 000 0111') returning id into a;
  insert into public.leads (company_name, email, claimed, claimed_by, approval_status, phone) values
    ('ZZ DEMO dedup B ' || v_tag, 'zz-dedup-b-' || v_tag || '@example.invalid', true,
     '  ZZ-DEDUP-' || upper(v_tag) || '@example.invalid ', 'pending', '0500000111') returning id into b;
  -- C: SAME PHONE, different email - a phone must never select a duplicate.
  insert into public.leads (company_name, email, phone) values
    ('ZZ DEMO dedup C ' || v_tag, 'zz-dedup-c-' || v_tag || '@example.invalid', '+971500000111') returning id into c;
  -- E/F: one mailbox as a customer AND a supplier - reported and handed over, never merged.
  insert into public.customers (email, full_name, locale) values
    ('zz-cross-' || v_tag || '@example.invalid', 'ZZ DEMO cross ' || v_tag, 'en') returning id into e;
  insert into public.leads (company_name, email) values
    ('ZZ DEMO dedup F ' || v_tag, 'zz-cross-' || v_tag || '@example.invalid') returning id into f;
  -- a child row that points at the loser and must follow the winner
  insert into public.supplier_availability (supplier_id, set_by) values (a, 'zz-probe');

  select count(*) into n_leads_before from public.leads where company_name like 'ZZ DEMO dedup % ' || v_tag;
  r := public.fn_it_engineer_contact_dedup();

  select id into ga from public.contact_duplicate_group where run_on = current_date and identity_key = 'zz-dedup-' || v_tag || '@example.invalid';
  select id into gx from public.contact_duplicate_group where run_on = current_date and identity_key = 'zz-cross-' || v_tag || '@example.invalid';
  if ga is null or gx is null then raise exception 'PROBE FAILED: groups not reported (%): %', v_tag, r; end if;

  -- demo group of one kind: merged, the CLAIMED lead wins, the loser survives and is blocked
  if (select status from public.contact_duplicate_group where id = ga) <> 'merged' then raise exception 'PROBE FAILED: demo group not merged'; end if;
  if not (select phone_confirms from public.contact_duplicate_group where id = ga) then raise exception 'PROBE FAILED: shared phone did not confirm'; end if;
  if (select merged_into from public.leads where id = a) is distinct from b then raise exception 'PROBE FAILED: A not merged into the claimed B'; end if;
  if not (select matching_blocked from public.leads where id = a) then raise exception 'PROBE FAILED: loser still matchable'; end if;
  if (select supplier_id from public.supplier_availability where supplier_id in (a, b) and set_by = 'zz-probe') is distinct from b then
    raise exception 'PROBE FAILED: child row not re-pointed to the winner'; end if;
  select repointed into v_rep from public.contact_merge_audit where group_id = ga and loser_id = a::text and winner_id = b::text and reviewed_by_seat = 'it_engineer';
  if v_rep is null or not v_rep @> jsonb_build_array(jsonb_build_object('table', 'supplier_availability', 'column', 'supplier_id', 'rows', 1)) then
    raise exception 'PROBE FAILED: audit missing or does not name the re-pointed FK: %', v_rep; end if;

  -- phone never selects: C is in no group
  if exists (select 1 from public.contact_duplicate_group where run_on = current_date and members @> jsonb_build_array(jsonb_build_object('kind', 'lead', 'id', c::text))) then
    raise exception 'PROBE FAILED: a shared phone selected a duplicate'; end if;

  -- cross-kind: handed to sales_engineer as a finding, not merged
  if (select status || '/' || handed_to_seat from public.contact_duplicate_group where id = gx) <> 'handed_to_seat/sales_engineer' then
    raise exception 'PROBE FAILED: cross-kind group not handed to sales_engineer'; end if;
  if not exists (select 1 from public.it_engineer_finding where issue_key = 'duty:contact_dedup:contact_duplicate:' || md5('zz-cross-' || v_tag || '@example.invalid') and closed_at is null) then
    raise exception 'PROBE FAILED: no open finding for the owning seat'; end if;
  if (select merged_into from public.leads where id = f) is not null or (select merged_into from public.customers where id = e) is not null then
    raise exception 'PROBE FAILED: a customer and a supplier were merged'; end if;

  -- the reviewed merge refuses what it must
  v_ok := false; begin perform public.fn_contact_merge(gx, 'sales_engineer', 'same company, reviewed'); exception when others then v_ok := sqlerrm like '%never merged%'; end;
  if not v_ok then raise exception 'PROBE FAILED: cross-kind merge was not refused'; end if;
  v_ok := false; begin perform public.fn_contact_merge(gx, 'sales_engineer', 'short'); exception when others then v_ok := sqlerrm like '%reason%'; end;
  if not v_ok then raise exception 'PROBE FAILED: a merge without a reason was not refused'; end if;
  v_ok := false; begin perform public.fn_contact_merge(gx, 'zz_no_such_seat', 'a long enough reason here'); exception when others then v_ok := sqlerrm like '%not a live seat%'; end;
  if not v_ok then raise exception 'PROBE FAILED: a dead seat was not refused'; end if;
  v_ok := false; begin perform public.fn_contact_merge(ga, 'sales_engineer', 'a long enough reason here'); exception when others then v_ok := sqlerrm like '%already merged%'; end;
  if not v_ok then raise exception 'PROBE FAILED: a merged group merged twice'; end if;
  v_ok := false; begin update public.contact_merge_audit set reason = 'x' where group_id = ga; exception when others then v_ok := sqlerrm like '%append-only%'; end;
  if not v_ok then raise exception 'PROBE FAILED: audit row could be changed'; end if;

  -- nothing deleted
  select count(*) into n_leads_after from public.leads where company_name like 'ZZ DEMO dedup % ' || v_tag;
  if n_leads_after <> n_leads_before or n_leads_after <> 4 then raise exception 'PROBE FAILED: leads deleted (% -> %)', n_leads_before, n_leads_after; end if;

  raise exception 'CHK<<PROBE OK tag=% groups=% demo_merged=% handed=% repointed=%>>', v_tag, r->>'groups', r->>'demo_merged', r->>'handed_to_sales_engineer', v_rep;
end $p$;
