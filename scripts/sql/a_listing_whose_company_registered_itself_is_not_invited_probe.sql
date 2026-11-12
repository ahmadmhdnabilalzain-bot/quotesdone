-- PROBE (pure, no DDL, aborted transaction) for a_listing_whose_company_registered_itself_is_not_invited.sql (12 Nov 2026,
-- sales_engineer). Run with the definition in one rolled-back transaction (node scripts/ci/rehearse_sql.mjs <file> <this>) or after
-- it is applied. It always ends in raise exception 'CHK<<json>>', so every row it writes rolls back; nothing it writes is ever
-- committed, so nothing can be sent. Its rows carry the ZZ PROBE name; the "registered" twin must be non-demo by the rule's own
-- definition, so it has no reserved address and no demo mark, and exists only inside this transaction.
--   reg  a claimed, non-demo company "ZZPROBE Twin Steel Establishment"     -> the registered company
--   twn  an unclaimed listing "ZZPROBE Twin Steel Est."                     -> has a registered twin (same name key)
--   oth  an unclaimed listing "ZZPROBE Other Steel Est."                    -> no twin
--   dem  a claimed DEMO company "ZZ DEMO Probe Glass LLC" and its listing   -> a demo registration never removes a listing
do $$
declare reg bigint; twn bigint; oth bigint; dem bigint; dml bigint; fail text := '';
        v_cands int; v_twins int; v_uses boolean;
begin
  insert into public.leads (company_name, claimed, claimed_by, emirate) values ('ZZPROBE Twin Steel Establishment', true, 'zzprobe-owner@zzprobe-steel-probe.ae', 'Dubai') returning id into reg;
  insert into public.leads (company_name, emirate) values ('ZZPROBE Twin Steel Est.', 'Dubai') returning id into twn;
  insert into public.leads (company_name, emirate) values ('ZZPROBE Other Steel Est.', 'Dubai') returning id into oth;
  insert into public.leads (company_name, claimed, claimed_by) values ('ZZ DEMO Probe Glass LLC', true, 'zz-demo-probe-glass@example.invalid') returning id into dem;
  insert into public.leads (company_name) values ('ZZ DEMO Probe Glass L.L.C.') returning id into dml;
  if (select is_demo from public.leads where id = reg) then fail := fail || 'the registered twin reads as demo (probe fixture wrong); '; end if;
  if not public.fn_supplier_listing_has_registered_twin(twn, 'ZZPROBE Twin Steel Est.') then fail := fail || 'a listing with a registered twin is not skipped; '; end if;
  if public.fn_supplier_listing_has_registered_twin(oth, 'ZZPROBE Other Steel Est.') then fail := fail || 'a listing without a twin is skipped; '; end if;
  if public.fn_supplier_listing_has_registered_twin(reg, 'ZZPROBE Twin Steel Establishment') then fail := fail || 'the registered company is its own twin; '; end if;
  if public.fn_supplier_listing_has_registered_twin(dml, 'ZZ DEMO Probe Glass L.L.C.') then fail := fail || 'a demo registration removes a listing; '; end if;
  if public.fn_supplier_listing_has_registered_twin(oth, '...') then fail := fail || 'a name with no key matched; '; end if;
  v_uses := pg_get_functiondef('public.fn_supplier_invite_candidates(integer,text[])'::regprocedure) like '%and not public.fn_supplier_listing_has_registered_twin(l.id, l.company_name)%';
  if not v_uses then fail := fail || 'fn_supplier_invite_candidates does not call the rule; '; end if;
  -- the real candidate list (fixtures excluded by fn_supplier_invite_eligible_ids): nobody on it has a registered twin
  select count(*), count(*) filter (where public.fn_supplier_listing_has_registered_twin(c.lead_id, c.company_name))
    into v_cands, v_twins from public.fn_supplier_invite_candidates(100000, null) c;
  if v_twins <> 0 then fail := fail || 'a candidate still has a registered twin; '; end if;
  if v_cands = 0 then fail := fail || 'the candidate list is empty (2,607 on 12 Nov 2026 before this file; 0 had a twin); '; end if;
  if (select count(*) from public.fn_supplier_listing_has_registered_twin(twn, 'ZZPROBE Twin Steel Est.') x) <> 1 then fail := fail || 'the rule is not a single answer; '; end if;
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'candidates', v_cands, 'candidates_with_twin', v_twins, 'candidates_routine_calls_rule', v_uses);
end $$;
