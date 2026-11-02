-- PROBE (pure, no DDL, aborted transaction) for only_a_readable_uae_authority_is_approved_and_a_held_registration_has_a_decider.sql.
-- Run AFTER the definition, in the same transaction (scripts/ci/rehearse_sql.mjs, scripts/lib/safe_replay.mjs replaySql). It always
-- ends in raise exception, whose message starts PROBE OK or PROBE FAILED, so every row it writes rolls back. Every subject is a ZZ DEMO
-- lead at @example.invalid created here. Seat: sales_engineer. Ledgers 1442 (authority holds), 1469 (services gate), 1176 (name autofill).
-- Seven suppliers, each with all six mandatory items, a UAE authority, a matching licence name, an expiry in the future, automatic
-- approval ON, and services CONFIRMED unless the case says otherwise:
--   a  services not confirmed                        -> pending, services_unconfirmed, not verified        (ledger 1469 survives this file)
--   b  confirmed, UAE authority                      -> approved, verified                                  (the control)
--   c  authority 'Companies House, United Kingdom'   -> pending, licence_authority_not_uae                  (foreign authority holds)
--   d  authority empty                               -> pending, licence_authority_unread                   (unread authority holds)
--   e  licence expired                               -> action_required, licence_expired, not verified      (expired holds)
--   f  licence names another company than entered    -> approved, company name = licence name, old name kept (ruling 1176)
--   g  already approved, authority now foreign       -> pending, licence_authority_not_uae                  (an approved supplier is held too)
do $p$
declare
  r jsonb := '{}'::jsonb; k text; lid bigint; g jsonb; l public.leads; z text := 'zz-demo-auth1442'; bad text[] := '{}';
  real_before int; real_after int; v_kept int; v_auth text; v_conf boolean; v_exp date;
begin
  select count(*) into real_before from public.leads where not coalesce(is_demo, false) and company_name !~* '^\s*zz\s*demo';
  insert into storage.objects (bucket_id, name)
  select 'supplier-docs', dirs.dname || '/' || z || '/' || names.nname || '.pdf'
    from unnest(array['licenses', 'profiles']) as dirs(dname), unnest(array['a', 'b', 'c', 'd', 'e', 'f', 'g']) as names(nname);
  update public.pricing_config set auto_approve_suppliers = true where id = 1;
  foreach k in array array['a', 'b', 'c', 'd', 'e', 'f', 'g'] loop
    v_auth := case k when 'c' then 'Companies House, United Kingdom' when 'd' then null else 'Department of Economy and Tourism, Dubai' end;
    v_exp := case k when 'e' then current_date - 30 else date '2028-12-31' end;
    v_conf := k <> 'a';
    insert into public.leads (approval_status, verified, claimed, claimed_by, company_name, email, phone, owner_email_verified, owner_phone_verified,
                              accepted_terms_at, signed_terms_path, license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry,
                              trade_license_no, license_authority, emirate, city, source, tags)
    values (null, false, true, z || '-' || k || '@example.invalid',
            case when k = 'f' then 'ZZ DEMO AUTH1442 F ENTERED LLC' else 'ZZ DEMO AUTH1442 ' || upper(k) || ' LLC' end,
            z || '-' || k || '@example.invalid',
            '+97150014420' || (ascii(k) - 96), true, true, now(), 'terms/' || z || '/' || k || '.pdf', 'licenses/' || z || '/' || k || '.pdf',
            'profiles/' || z || '/' || k || '.pdf', 'ZZ DEMO AUTH1442 ' || case when k = 'f' then 'F LICENCE' else upper(k) end || ' LLC', v_exp,
            'ZZAUTH1442-' || upper(k), v_auth, 'Dubai', 'Dubai', 'probe', array['qd_demo'])
    returning id into lid;
    if v_conf then
      insert into public.supplier_capabilities (supplier_id, trades, roles, confirmed_at, confirmed_version, review_status)
      values (lid, array['aluminium'], array['contractor'], now(), 1, 'confirmed');
      insert into public.supplier_capability_confirmation (supplier_id, version, confirmed_at, confirmed_via) values (lid, 1, now(), 'portal');
    end if;
    if k = 'g' then
      -- approved first, with a UAE authority; the licence is then swapped for a foreign one and the gate re-run (licence_changed)
      update public.leads set license_authority = 'Department of Economy and Tourism, Dubai' where id = lid;
      perform public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
      r := r || jsonb_build_object('g_before', (select approval_status from public.leads where id = lid));
      update public.leads set license_authority = 'Companies House, United Kingdom' where id = lid;
      g := public.fn_sales_engineer_verifies_supplier(lid, 'licence_changed');
    else
      g := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
    end if;
    select * into l from public.leads where id = lid;
    r := r || jsonb_build_object(k, jsonb_build_object('decision', g ->> 'decision', 'reason', l.licence_gate_reason, 'status', l.approval_status,
           'verified', l.verified, 'company', l.company_name,
           'demo', l.company_name like 'ZZ DEMO %' and l.email like '%@example.invalid'));
  end loop;
  select count(*) into v_kept from public.agent_actions
   where kind = 'supplier_name_from_licence' and detail ->> 'supplier_id' = (select id::text from public.leads where email = z || '-f@example.invalid')
     and detail ->> 'previous_name' = 'ZZ DEMO AUTH1442 F ENTERED LLC';
  select count(*) into real_after from public.leads where not coalesce(is_demo, false) and company_name !~* '^\s*zz\s*demo';

  if (r -> 'a' ->> 'status', r -> 'a' ->> 'reason', r -> 'a' ->> 'verified') is distinct from ('pending', 'services_unconfirmed', 'false') then bad := bad || 'a: services unconfirmed must hold'; end if;
  if (r -> 'b' ->> 'status', r -> 'b' ->> 'verified') is distinct from ('approved', 'true') then bad := bad || 'b: confirmed services must approve'; end if;
  if (r -> 'c' ->> 'status', r -> 'c' ->> 'reason', r -> 'c' ->> 'verified') is distinct from ('pending', 'licence_authority_not_uae', 'false') then bad := bad || 'c: a foreign authority must hold'; end if;
  if (r -> 'd' ->> 'status', r -> 'd' ->> 'reason', r -> 'd' ->> 'verified') is distinct from ('pending', 'licence_authority_unread', 'false') then bad := bad || 'd: an unread authority must hold'; end if;
  if (r -> 'e' ->> 'status', r -> 'e' ->> 'reason', r -> 'e' ->> 'verified') is distinct from ('action_required', 'licence_expired', 'false') then bad := bad || 'e: an expired licence must hold'; end if;
  if (r -> 'f' ->> 'status', r -> 'f' ->> 'company') is distinct from ('approved', 'ZZ DEMO AUTH1442 F LICENCE LLC') or v_kept <> 1 then bad := bad || 'f: ruling 1176 name autofill must replace the name once and keep the old one'; end if;
  if (r ->> 'g_before', r -> 'g' ->> 'status', r -> 'g' ->> 'reason') is distinct from ('approved', 'pending', 'licence_authority_not_uae') then bad := bad || 'g: an approved supplier with a foreign licence must be held'; end if;
  if real_before <> real_after then bad := bad || 'real lead count changed ' || real_before || ' -> ' || real_after; end if;
  if exists (select 1 from jsonb_each(r) e where jsonb_typeof(e.value) = 'object' and (e.value ->> 'demo') is distinct from 'true') then bad := bad || 'a case is not a ZZ DEMO fixture'; end if;

  if cardinality(bad) > 0 then raise exception 'PROBE FAILED: % :: %', array_to_string(bad, '; '), r::text; end if;
  raise exception 'PROBE OK: services held, confirmed approved, foreign/unread authority held, expired held, 1176 autofill, real leads % unchanged', real_before;
end $p$;
