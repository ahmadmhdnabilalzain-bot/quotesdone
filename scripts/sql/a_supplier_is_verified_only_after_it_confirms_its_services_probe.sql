-- PROBE (pure, no DDL, aborted transaction) for a_supplier_is_verified_only_after_it_confirms_its_services.sql.
-- Run AFTER the definition, in the same transaction (scripts/lib/safe_replay.mjs replaySql). It always ends in
-- raise exception 'CHK<<json>>', so every row it writes rolls back. Every subject is a ZZ DEMO lead at @example.invalid created here.
-- Six suppliers, each with all six mandatory items, a matching licence name and automatic approval ON:
--   a  no capability record                          -> pending, services_unconfirmed, not verified           (the fix)
--   b  confirmed, ledger version 1 = confirmed 1       -> approved, verified                                  (the control)
--   c  confirmed 1, but the ledger holds version 2     -> pending, services_unconfirmed (current version)     (the version rule)
--   d  already approved, no capability record          -> stays approved                                       (nobody is demoted)
--   e  no capability record, source demo_factory       -> approved                                             (seeders are exempt)
--   f  as a, then confirmed, gate run as services_confirmed -> approved                                       (the confirm releases the hold)
do $p$
declare
  r jsonb := '{}'::jsonb; k text; lid bigint; g jsonb; l public.leads; z text := 'zz-demo-svc1469';
  real_before int; real_after int;
begin
  select count(*) into real_before from public.leads where not coalesce(is_demo, false) and company_name !~* '^\s*zz\s*demo';
  insert into storage.objects (bucket_id, name)
  select 'supplier-docs', dirs.dname || '/' || z || '/' || names.nname || '.pdf'
    from unnest(array['licenses', 'profiles']) as dirs(dname), unnest(array['a', 'b', 'c', 'd', 'e', 'f']) as names(nname);
  update public.pricing_config set auto_approve_suppliers = true where id = 1;
  foreach k in array array['a', 'b', 'c', 'd', 'e', 'f'] loop
    insert into public.leads (approval_status, verified, claimed, claimed_by, company_name, email, phone, owner_email_verified, owner_phone_verified,
                              accepted_terms_at, signed_terms_path, license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry,
                              trade_license_no, emirate, city, source, tags)
    values (null, false, true, z || '-' || k || '@example.invalid', 'ZZ DEMO SVC1469 ' || upper(k) || ' LLC', z || '-' || k || '@example.invalid',
            '+97150014690' || (ascii(k) - 96), true, true, now(), 'terms/' || z || '/' || k || '.pdf', 'licenses/' || z || '/' || k || '.pdf',
            'profiles/' || z || '/' || k || '.pdf', 'ZZ DEMO SVC1469 ' || upper(k) || ' LLC', '2028-12-31', 'ZZSVC1469-' || upper(k), 'Dubai', 'Dubai', 'probe', array['qd_demo'])
    returning id into lid;
    if k in ('b', 'c', 'f') then
      -- f is confirmed only after its first gate run (below)
      if k <> 'f' then
        insert into public.supplier_capabilities (supplier_id, trades, roles, confirmed_at, confirmed_version, review_status)
        values (lid, array['aluminium'], array['contractor'], now(), 1, 'confirmed');
        insert into public.supplier_capability_confirmation (supplier_id, version, confirmed_at, confirmed_via) values (lid, 1, now(), 'portal');
        if k = 'c' then insert into public.supplier_capability_confirmation (supplier_id, version) values (lid, 2); end if;
      end if;
    end if;
    if k = 'd' then update public.leads set approval_status = 'approved', verified = true, approved_at = now() where id = lid; end if;
    g := public.fn_sales_engineer_verifies_supplier(lid, case when k = 'e' then 'demo_factory' else 'save_profile' end);
    if k = 'f' then
      r := r || jsonb_build_object('f_before', (select jsonb_build_object('status', approval_status, 'reason', licence_gate_reason) from public.leads where id = lid));
      insert into public.supplier_capabilities (supplier_id, trades, roles, confirmed_at, confirmed_version, review_status)
      values (lid, array['aluminium'], array['contractor'], now(), 1, 'confirmed');
      insert into public.supplier_capability_confirmation (supplier_id, version, confirmed_at, confirmed_via) values (lid, 1, now(), 'portal');
      g := public.fn_sales_engineer_verifies_supplier(lid, 'services_confirmed');
    end if;
    select * into l from public.leads where id = lid;
    r := r || jsonb_build_object(k, jsonb_build_object('decision', g ->> 'decision', 'reason', l.licence_gate_reason, 'status', l.approval_status,
           'verified', l.verified, 'demo', l.company_name like 'ZZ DEMO %' and l.email like '%@example.invalid'));
  end loop;
  select count(*) into real_after from public.leads where not coalesce(is_demo, false) and company_name !~* '^\s*zz\s*demo';
  r := r || jsonb_build_object('real_leads_before', real_before, 'real_leads_after', real_after);
  if r #>> '{a,status}' = 'pending' and r #>> '{a,reason}' = 'services_unconfirmed' and r #>> '{b,status}' = 'approved'
     and r #>> '{c,status}' = 'pending' and r #>> '{c,reason}' = 'services_unconfirmed' and r #>> '{d,status}' = 'approved'
     and r #>> '{e,status}' = 'approved' and r #>> '{f,status}' = 'approved' and r #>> '{f_before,status}' = 'pending'
     and real_before = real_after then
    raise exception 'CHK<<PROBE OK %>>', r::text;
  end if;
  raise exception 'CHK<<PROBE FAILED %>>', r::text;
end $p$;
