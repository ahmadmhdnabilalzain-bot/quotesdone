-- PROBE: a decoration company reaches a flooring inquiry, and stops when it removes flooring.
-- Seat: sales_engineer. 18 Sep 2026. Founder instructions 438-439.
--
-- This proves the implication map END TO END against the real fn_match_capability, with a ZZ DEMO
-- supplier that never reaches a real person (demo_identities_are_marked_and_never_reach_a_real_person:
-- 'ZZ DEMO' in the name, @example.invalid as the email). The whole probe runs inside ONE transaction
-- that RAISES at the end, so nothing is committed -- the counts still come out in the error message.
-- Run it with: node scripts/qsql.mjs scripts/sql/a_supplier_describes_its_services_in_its_own_words_probe.sql
--
-- WHAT IT ASSERTS
--   1. Stated flooring.tiling is matched by a flooring inquiry (the ordinary case).
--   2. A supplier that stated ONLY interior_fitout.decoration is matched by a flooring.tiling
--      inquiry, and via_implication names the curated row that put it there.
--   3. After it removes flooring.tiling (services_removed), the same inquiry does NOT reach it.
--   4. NO CHAINING: decoration implies gypsum.false_ceiling; false_ceiling implies
--      gypsum.acoustic_ceiling; a decoration-only supplier is NOT matched for acoustic_ceiling.
--   5. An inquiry naming no service matches exactly as it did before (the trade gate alone).
do $$
declare
  v_lead   bigint;
  v_n_stated int; v_n_implied int; v_n_removed int; v_n_chain int; v_n_noservice int;
  v_via    text[];
  v_lic text := 'zz-demo/own-words-probe-licence.pdf';
  v_prof text := 'zz-demo/own-words-probe-profile.pdf';
  v_six text[];
begin
  set local statement_timeout = '8s';

  -- THE MANDATORY SIX ARE EVIDENCE, NOT COLUMN VALUES (measured 18 Sep 2026, after this probe was
  -- refused by trg_leads_e0_mandatory_six_gate with "missing: reg_mobile, reg_email, reg_licence,
  -- reg_profile, reg_terms" on a row that did supply an email). fn_supplier_mandatory_six reads:
  --   reg_mobile  -> owner_phone_verified AND the digits of phone/phone_e164 match ^9715[0-9]{8}$
  --                  (the OTP verification, not a number typed into a column)
  --   reg_email   -> owner_email_verified -- NOT leads.email, which is why an email was present and
  --                  the item still missing
  --   reg_licence -> storage.objects actually HOLDS license_doc_path in bucket supplier-docs
  --   reg_profile -> the same for company_profile_doc_path (a path naming nothing is not a document)
  --   reg_terms   -> signed_terms_path non-empty
  -- So every seeding script in the estate that inserts an approved supplier directly must supply the
  -- evidence. The gate is the founder's rule and is never softened; the fixture is what changes.
  -- These two storage rows belong to this probe and are rolled back with everything else, so no real
  -- supplier's document is pointed at or re-registered.
  insert into storage.objects (bucket_id, name) values ('supplier-docs', v_lic), ('supplier-docs', v_prof)
  on conflict do nothing;  -- no target: since Supabase storage versioning (measured 22 Sep 2026) the (bucket_id, name) uniques are partial indexes, which a column list cannot name (42P10)

  insert into public.leads (company_name, email, emirate, sector, phone, owner_phone_verified,
                            owner_email_verified, license_doc_path, company_profile_doc_path,
                            signed_terms_path, verified, approval_status)
  values ('ZZ DEMO — Decoration probe', 'zz.demo.decoration.probe@example.invalid', 'Dubai',
          'interior_fitout', '+971500000099', true, true, v_lic, v_prof,
          'suppliers/zz-demo-own-words-probe.pdf', true, 'approved')
  returning id into v_lead;

  -- The gate would already have refused the insert; this states the seed's own completeness so a
  -- future change to the definition of the six is named here rather than read as a matching result.
  v_six := public.fn_supplier_mandatory_six_for(v_lead);
  if cardinality(v_six) <> 0 then
    raise exception 'PROBE FAIL: the ZZ DEMO supplier is not complete, so nothing below measures matching. Missing: %', v_six;
  end if;

  insert into public.supplier_capabilities
    (supplier_id, trades, roles, services, coverage_emirates, confirmed_at)
  values (v_lead, array['interior_fitout'], array['contractor'],
          array['interior_fitout.decoration'], array['Dubai'], now());

  -- 1. the ordinary case: a stated service is matched.
  update public.supplier_capabilities
     set services = array['flooring.tiling'], trades = array['interior_fitout','flooring']
   where supplier_id = v_lead;
  select count(*) into v_n_stated
  from public.fn_match_capability(array['flooring'], 'executes', '{}'::text[], '{}'::text[],
                                  null, null, null, 50, array['flooring.tiling']) m
  where m.supplier_id = v_lead;

  -- 2. decoration only, matched for flooring through the curated map.
  update public.supplier_capabilities
     set services = array['interior_fitout.decoration'],
         trades = array['interior_fitout','flooring'],   -- the trade gate is unchanged and still applies
         services_removed = '{}'::text[]
   where supplier_id = v_lead;
  select count(*), min(m.via_implication) into v_n_implied, v_via
  from public.fn_match_capability(array['flooring'], 'executes', '{}'::text[], '{}'::text[],
                                  null, null, null, 50, array['flooring.tiling']) m
  where m.supplier_id = v_lead;

  -- 3. the supplier removes flooring.tiling -- the same inquiry no longer reaches it.
  update public.supplier_capabilities
     set services_removed = array['flooring.tiling'] where supplier_id = v_lead;
  select count(*) into v_n_removed
  from public.fn_match_capability(array['flooring'], 'executes', '{}'::text[], '{}'::text[],
                                  null, null, null, 50, array['flooring.tiling']) m
  where m.supplier_id = v_lead;

  -- 4. no chaining: decoration -> false_ceiling -> acoustic_ceiling must NOT reach acoustic_ceiling.
  update public.supplier_capabilities
     set services_removed = '{}'::text[], trades = array['interior_fitout','gypsum']
   where supplier_id = v_lead;
  select count(*) into v_n_chain
  from public.fn_match_capability(array['gypsum'], 'executes', '{}'::text[], '{}'::text[],
                                  null, null, null, 50, array['gypsum.acoustic_ceiling']) m
  where m.supplier_id = v_lead;

  -- 5. an inquiry that names no service is matched on the trade gate alone, as before.
  select count(*) into v_n_noservice
  from public.fn_match_capability(array['gypsum'], 'executes', '{}'::text[], '{}'::text[],
                                  null, null, null, 50, '{}'::text[]) m
  where m.supplier_id = v_lead;

  -- EACH NUMBER IS ASSERTED, not merely printed. A probe whose only outcome is "it ran" cannot fail,
  -- and a check that cannot fail is worse than no check (database review, 18 Sep 2026).
  if v_n_stated <> 1 then
    raise exception 'PROBE FAIL: a stated flooring.tiling should match a flooring.tiling inquiry once, got %', v_n_stated;
  end if;
  if v_n_implied <> 1 then
    raise exception 'PROBE FAIL: a decoration-only supplier should reach a flooring.tiling inquiry through the implication map, got %', v_n_implied;
  end if;
  if v_via is null or cardinality(v_via) = 0 then
    raise exception 'PROBE FAIL: the implied match records no implication rule; via_implication was %', coalesce(array_to_string(v_via, '; '), 'null');
  end if;
  if not ('interior_fitout.decoration -> flooring.tiling' = any(v_via)) then
    raise exception 'PROBE FAIL: via_implication names the wrong rule: %', array_to_string(v_via, '; ');
  end if;
  if v_n_removed <> 0 then
    raise exception 'PROBE FAIL: after removing flooring.tiling the inquiry must not reach this supplier, got %', v_n_removed;
  end if;
  if v_n_chain <> 0 then
    raise exception 'PROBE FAIL: chaining leaked — decoration reached gypsum.acoustic_ceiling through gypsum.false_ceiling, got %', v_n_chain;
  end if;
  if v_n_noservice <> 1 then
    raise exception 'PROBE FAIL: an inquiry naming no service must still match on the trade gate alone, got %', v_n_noservice;
  end if;

  raise exception
    'PROBE PASS (rolled back) stated_match=% implied_match=% via=% after_removal=% chained=% no_service_named=%',
    v_n_stated, v_n_implied, array_to_string(v_via, '; '),
    v_n_removed, v_n_chain, v_n_noservice;
end $$;
