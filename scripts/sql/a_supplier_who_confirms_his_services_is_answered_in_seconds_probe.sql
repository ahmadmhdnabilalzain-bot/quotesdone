-- PROBE (pure, no DDL, aborted transaction) for a_supplier_who_confirms_his_services_is_answered_in_seconds.sql. Seat: sales_engineer.
-- Run AFTER the definition, in the same transaction (scripts/ci/rehearse_sql.mjs <file> <this probe>). It always ends in
-- raise exception 'CHK<<...>>', so every row it writes rolls back. Every subject is a ZZ DEMO lead at @example.invalid made here.
-- Two suppliers with all six mandatory items, a matching licence and automatic approval ON, each first held services_unconfirmed:
--   n  confirms, and the confirm calls fn_sales_engineer_verifies_supplier_now -> approved at once, queued false, ranked
--   t  confirms, but the confirm's gate run is LOST (never called)            -> the minute tick approves him, ranked
-- The lock half (an approval while ANOTHER transaction holds the rank lock) cannot be shown inside one transaction, where
-- the lock re-enters: supabase/functions/_shared/founding_rank_race.check.ts proves it on a throwaway Postgres.
do $p$
declare
  r jsonb := '{}'::jsonb; k text; lid bigint; ids jsonb := '{}'::jsonb; g jsonb; z text := 'zz-demo-gate-now';
  real_before int; real_after int; t0 timestamptz;
begin
  select count(*) into real_before from public.leads where not coalesce(is_demo, false) and company_name !~* '^\s*zz\s*demo';
  insert into storage.objects (bucket_id, name)
  select 'supplier-docs', dirs.dname || '/' || z || '/' || names.nname || '.pdf'
    from unnest(array['licenses', 'profiles']) as dirs(dname), unnest(array['n', 't']) as names(nname);
  update public.pricing_config set auto_approve_suppliers = true where id = 1;
  foreach k in array array['n', 't'] loop
    insert into public.leads (approval_status, verified, claimed, claimed_by, company_name, email, phone, owner_email_verified, owner_phone_verified,
                              accepted_terms_at, signed_terms_path, signed_terms_at, license_doc_path, company_profile_doc_path, licence_legal_name,
                              license_expiry, trade_license_no, license_authority, emirate, city, source, tags)
    values (null, false, true, z || '-' || k || '@example.invalid', 'ZZ DEMO GATENOW ' || upper(k) || ' LLC', z || '-' || k || '@example.invalid',
            '+97150019100' || case k when 'n' then '1' else '2' end, true, true, now(), 'terms/' || z || '/' || k || '.pdf', now(),
            'licenses/' || z || '/' || k || '.pdf', 'profiles/' || z || '/' || k || '.pdf', 'ZZ DEMO GATENOW ' || upper(k) || ' LLC',
            '2028-12-31', 'ZZGATENOW-' || upper(k), 'Dubai Economy and Tourism', 'Dubai', 'Dubai', 'probe', array['qd_demo'])
    returning id into lid;
    ids := ids || jsonb_build_object(k, lid);
    g := public.fn_sales_engineer_verifies_supplier(lid, 'save_profile');
    r := r || jsonb_build_object(k || '_held', jsonb_build_object('decision', g ->> 'decision', 'reason', g ->> 'reason'));
    -- the supplier presses Confirm my services
    insert into public.supplier_capabilities (supplier_id, trades, roles, confirmed_at, confirmed_version, review_status)
    values (lid, array['aluminium'], array['contractor'], now(), 1, 'confirmed');
    insert into public.supplier_capability_confirmation (supplier_id, version, confirmed_at, confirmed_via) values (lid, 1, now(), 'portal');
  end loop;

  t0 := clock_timestamp();
  g := public.fn_sales_engineer_verifies_supplier_now((ids ->> 'n')::bigint, 'services_confirmed');
  r := r || jsonb_build_object('n_now', jsonb_build_object('decision', g ->> 'decision', 'queued', g -> 'queued',
                                 'ms', round(extract(epoch from clock_timestamp() - t0) * 1000)));
  g := public.fn_sales_engineer_reruns_held_verifications();
  r := r || jsonb_build_object('tick', g);
  r := r || jsonb_build_object('n', (select jsonb_build_object('status', approval_status, 'verified', verified, 'ranked', founding_rank is not null) from public.leads where id = (ids ->> 'n')::bigint),
                               't', (select jsonb_build_object('status', approval_status, 'verified', verified, 'ranked', founding_rank is not null) from public.leads where id = (ids ->> 't')::bigint));
  select count(*) into real_after from public.leads where not coalesce(is_demo, false) and company_name !~* '^\s*zz\s*demo';
  r := r || jsonb_build_object('real_leads_before', real_before, 'real_leads_after', real_after);
  if r #>> '{n_held,reason}' = 'services_unconfirmed' and r #>> '{t_held,reason}' = 'services_unconfirmed'
     and r #>> '{n_now,decision}' = 'approved' and r #>> '{n_now,queued}' = 'false'
     and r #>> '{n,status}' = 'approved' and r #>> '{n,ranked}' = 'true'
     and r #>> '{t,status}' = 'approved' and r #>> '{t,verified}' = 'true' and r #>> '{t,ranked}' = 'true'
     and (r #>> '{tick,approved}')::int >= 1 and real_before = real_after then
    raise exception 'CHK<<PROBE OK %>>', r::text;
  end if;
  raise exception 'CHK<<PROBE FAILED %>>', r::text;
end $p$;
