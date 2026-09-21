-- PROBE: a supplier who limited itself to Dubai is matched for Dubai, not for Sharjah, and is matched
-- for Sharjah again once it states no limit (national default). Pure probe -- NO DDL in this file.
-- Seat: sales_engineer. 21 Sep 2026. Pairs with a_supplier_who_limits_its_emirates_is_matched_only_there.sql.
--
-- Run it with: node scripts/qsql.mjs scripts/sql/a_supplier_who_limits_its_emirates_is_matched_only_there_probe.sql
--
-- ONE transaction. The DO block seeds a ZZ DEMO supplier that is incapable of reaching a real person
-- ('ZZ DEMO' in the name, @example.invalid email, the reserved +9715000000xx fixture block), asks the
-- live fn_match_capability three questions, then deletes exactly the rows it created -- every write
-- names the probe's own ids -- and asserts they are gone. The verdict is ONE row from the final
-- select; nothing is raised as a notice. Any failure inside the block rolls the block's own writes
-- back (a plpgsql exception unwinds the block's subtransaction) and is reported as PROBE FAILED.
--
-- WHAT IT ASSERTS
--   1. coverage_emirates {Dubai}: a Dubai painting request returns the supplier, why says 'in Dubai'.
--   2. the same row: a Sharjah painting request does NOT return it (the stated limit is honoured).
--   3. coverage_emirates and service_emirates cleared: Sharjah returns it, why says 'UAE-wide (no stated limit)'.
--   4. after cleanup: 0 leads, 0 capabilities, 0 storage objects carry the probe's ids/paths.
begin;

do $$
declare
  v_lead   bigint;
  v_lic    text := 'zz-demo/emirate-probe-licence.pdf';
  v_prof   text := 'zz-demo/emirate-probe-profile.pdf';
  v_six    text[];
  v_n_dubai   int; v_why_dubai   text;
  v_n_sharjah int;
  v_n_national int; v_why_national text;
  v_left_leads int; v_left_caps int; v_left_objs int;
begin
  set local statement_timeout = '8s';

  -- THE MANDATORY SIX ARE EVIDENCE, NOT COLUMN VALUES (see a_supplier_describes_its_services_in_its_own_words_probe.sql,
  -- 18 Sep 2026): reg_mobile = owner_phone_verified + a ^9715[0-9]{8}$ number, reg_email =
  -- owner_email_verified, reg_licence / reg_profile = the path EXISTS in bucket supplier-docs,
  -- reg_terms = signed_terms_path. The two storage rows are the probe's own and are deleted below.
  insert into storage.objects (bucket_id, name) values ('supplier-docs', v_lic), ('supplier-docs', v_prof)
  on conflict (bucket_id, name) do nothing;

  insert into public.leads (company_name, email, emirate, sector, phone, owner_phone_verified,
                            owner_email_verified, license_doc_path, company_profile_doc_path,
                            signed_terms_path, verified, approval_status, service_emirates)
  values ('ZZ DEMO — emirate probe', 'zz.demo.emirate.probe@example.invalid', 'Dubai',
          'painting', '+971500000098', true, true, v_lic, v_prof,
          'suppliers/zz-demo-emirate-probe.pdf', true, 'approved', array['Dubai'])
  returning id into v_lead;

  v_six := public.fn_supplier_mandatory_six_for(v_lead);
  if cardinality(v_six) <> 0 then
    raise exception 'the ZZ DEMO supplier is not complete, so nothing below measures matching. Missing: %', v_six;
  end if;

  insert into public.supplier_capabilities (supplier_id, trades, roles, coverage_emirates, confirmed_at)
  values (v_lead, array['painting'], array['executes'], array['Dubai'], now());

  -- 1. Dubai request, Dubai-only supplier: returned, and the reason names the emirate.
  select count(*), min(m.why) into v_n_dubai, v_why_dubai
  from public.fn_match_capability(array['painting'], 'executes', p_emirate => 'Dubai', p_limit => 50) m
  where m.supplier_id = v_lead;

  -- 2. Sharjah request, Dubai-only supplier: NOT returned.
  select count(*) into v_n_sharjah
  from public.fn_match_capability(array['painting'], 'executes', p_emirate => 'Sharjah', p_limit => 50) m
  where m.supplier_id = v_lead;

  -- 3. No stated limit anywhere: Sharjah returns it (national default).
  update public.supplier_capabilities set coverage_emirates = '{}'::text[] where supplier_id = v_lead;
  update public.leads set service_emirates = null where id = v_lead;
  select count(*), min(m.why) into v_n_national, v_why_national
  from public.fn_match_capability(array['painting'], 'executes', p_emirate => 'Sharjah', p_limit => 50) m
  where m.supplier_id = v_lead;

  -- CLEANUP, by the probe's own ids only, then proved.
  delete from public.supplier_capabilities where supplier_id = v_lead;
  delete from public.leads where id = v_lead;
  delete from storage.objects where bucket_id = 'supplier-docs' and name in (v_lic, v_prof);
  select count(*) into v_left_leads from public.leads where id = v_lead or email = 'zz.demo.emirate.probe@example.invalid';
  select count(*) into v_left_caps  from public.supplier_capabilities where supplier_id = v_lead;
  select count(*) into v_left_objs  from storage.objects where bucket_id = 'supplier-docs' and name in (v_lic, v_prof);

  -- EACH NUMBER IS ASSERTED, not merely printed.
  if v_n_dubai <> 1 then
    raise exception 'a Dubai-only supplier should be returned once for a Dubai request, got %', v_n_dubai;
  end if;
  if v_why_dubai not like '%in Dubai%' then
    raise exception 'the Dubai match should say "in Dubai", why was: %', v_why_dubai;
  end if;
  if v_n_sharjah <> 0 then
    raise exception 'a Dubai-only supplier must NOT be returned for a Sharjah request, got %', v_n_sharjah;
  end if;
  if v_n_national <> 1 then
    raise exception 'with no stated limit a Sharjah request should return the supplier once (national default), got %', v_n_national;
  end if;
  if v_why_national not like '%UAE-wide (no stated limit)%' then
    raise exception 'the national match should say "UAE-wide (no stated limit)", why was: %', v_why_national;
  end if;
  if v_left_leads + v_left_caps + v_left_objs <> 0 then
    raise exception 'cleanup left rows behind: leads=% capabilities=% storage=%', v_left_leads, v_left_caps, v_left_objs;
  end if;

  perform set_config('qd.probe_verdict',
    format('PROBE OK dubai_match=%s (%s) sharjah_match_when_limited=%s national_match=%s (%s) left_behind=0',
           v_n_dubai, v_why_dubai, v_n_sharjah, v_n_national, v_why_national), true);
exception when others then
  perform set_config('qd.probe_verdict', 'PROBE FAILED ' || sqlerrm, true);
end $$;

select coalesce(current_setting('qd.probe_verdict', true), 'PROBE FAILED (the block set no verdict)') as verdict;

commit;
