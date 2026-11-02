-- PROBE for a_licence_naming_another_company_is_held_for_the_sales_engineer_and_never_overwrites_the_name.sql.
-- Seat: sales_engineer. Never applied: it always raises CHK<<...>>, so every row rolls back. Its subjects are ZZ DEMO
-- fixtures at @example.invalid, so nothing here can reach a person even before the rollback. Automatic approval is
-- forced ON inside the transaction (the strongest case). Proves:
--  A. a not-yet-approved supplier whose licence names another company: pending / licence_name_mismatch, NOT verified,
--     the registered name kept, the supplier told once in English;
--  B. an APPROVED supplier whose new licence names another company: held the same way;
--  C. after fn_sales_engineer_confirms_licence_name the same licence is accepted (approved), the name unchanged;
--     and a licence naming a THIRD company is held again.
insert into storage.objects (bucket_id, name)
select 'supplier-docs', d || '/zz-demo-lic1467/' || k || '.pdf' from unnest(array['licenses', 'profiles']) d, unnest(array['a', 'b', 'c']) k;
insert into public.leads (approval_status, verified, claimed, claimed_by, company_name, email, phone, owner_email_verified, owner_phone_verified,
                          accepted_terms_at, signed_terms_path, license_doc_path, company_profile_doc_path, licence_legal_name, license_expiry,
                          trade_license_no, emirate, city, source, tags)
select s, s = 'approved', true, 'zz-demo-lic1467-' || k || '@example.invalid', 'ZZ DEMO Lic1467 Registered ' || upper(k) || ' LLC', 'zz-demo-lic1467-' || k || '@example.invalid',
       '+9715001467' || n, true, true, now(), 'terms/zz-demo-lic1467/' || k || '.pdf', 'licenses/zz-demo-lic1467/' || k || '.pdf', 'profiles/zz-demo-lic1467/' || k || '.pdf',
       'ZZ DEMO Lic1467 Subsidiary ' || upper(k) || ' FZ LLC', '2028-12-31', 'ZZLIC1467-' || upper(k), 'Dubai', 'Dubai', 'probe', array['qd_demo']
  from (values ('a', 'pending', '10'), ('b', 'approved', '11'), ('c', 'pending', '12')) v(k, s, n);
do $p$
declare r jsonb := '{}'::jsonb; k text; lid bigint; g jsonb; l public.leads; f text[] := '{}'; n_mail int; c jsonb;
begin
  update public.pricing_config set auto_approve_suppliers = true where id = 1;
  foreach k in array array['a', 'b'] loop
    select id into lid from public.leads where email = 'zz-demo-lic1467-' || k || '@example.invalid';
    g := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
    select * into l from public.leads where id = lid;
    select count(*) into n_mail from public.notifications where lead_id = lid and type = 'licence_names_another_company' and channel = 'email';
    if g ->> 'decision' <> 'pending' or g ->> 'reason' <> 'licence_name_mismatch' or l.verified then f := f || (k || ': not held: ' || g::text); end if;
    if l.company_name <> 'ZZ DEMO Lic1467 Registered ' || upper(k) || ' LLC' then f := f || (k || ': the registered name was overwritten: ' || l.company_name); end if;
    if n_mail <> 1 then f := f || (k || ': the supplier was told ' || n_mail || ' times, not once'); end if;
    r := r || jsonb_build_object(k, jsonb_build_object('decision', g ->> 'decision', 'reason', g ->> 'reason', 'company', l.company_name, 'told', n_mail));
  end loop;
  -- C: confirmed, then a different licence name
  select id into lid from public.leads where email = 'zz-demo-lic1467-c@example.invalid';
  g := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  c := public.fn_sales_engineer_confirms_licence_name(lid, 'ZZ DEMO probe: subsidiary of the registered company');
  select * into l from public.leads where id = lid;
  if c ->> 'decision' <> 'approved' or l.company_name <> 'ZZ DEMO Lic1467 Registered C LLC' then f := f || ('c: confirmed licence not accepted or name changed: ' || c::text || ' ' || l.company_name); end if;
  update public.leads set licence_legal_name = 'ZZ DEMO Lic1467 Third Company LLC' where id = lid;
  g := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
  if g ->> 'reason' <> 'licence_name_mismatch' then f := f || ('c: a third licence name was accepted: ' || g::text); end if;
  raise exception 'CHK<<%>> %', case when cardinality(f) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(f, '; ') end, r::text;
end $p$;
