-- PROBE (pure, no DDL, aborted transaction) for the_acceptance_certificate_follows_the_trade_licence.sql (founder ruling 1672).
-- Run with the definition in one rolled-back transaction (node scripts/ci/rehearse_sql.mjs <file> <this>) or after it is applied.
-- It always ends in raise exception 'CHK<<json>>': every row it writes rolls back, and the sign request it queues (net.http_post
-- inserts into pg_net's queue in this transaction) goes with it. Subjects: ZZ DEMO leads at example.invalid, created here.
--   n  accepted and certified, not submitted, no name; the licence is read          -> issued again, recorded once
--   s  accepted and certified, submitted, named (registered before this change)      -> the licence read again: NOT re-issued
--   approved suppliers: the trigger's WHEN refuses them (read from pg_get_triggerdef: an approved row cannot be built without the six)
--   u  no acceptance                                                                 -> NOT re-issued
do $$
declare n bigint; s bigint; u bigint; fail text := ''; k int;
begin
  insert into public.leads (company_name, email, claimed, claimed_by, accepted_terms_at, signed_terms_path, signed_terms_at)
       values ('', 'zz-demo-cert-n@probe1672.example.invalid', true, 'zz-demo-cert-n@probe1672.example.invalid', now() - interval '2 minutes', 'zz-demo-probe-1672/n.pdf', now() - interval '1 minute') returning id into n;
  insert into public.leads (company_name, email, claimed, claimed_by, accepted_terms_at, signed_terms_path, signed_terms_at, registration_submitted_at)
       values ('ZZ DEMO Cert Probe Submitted LLC', 'zz-demo-cert-s@probe1672.example.invalid', true, 'zz-demo-cert-s@probe1672.example.invalid', now() - interval '9 days', 'zz-demo-probe-1672/s.pdf', now() - interval '9 days', now() - interval '9 days') returning id into s;
  if (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'public.leads'::regclass and t.tgname = 'z22_sign_supplier_again_when_his_licence_is_read')
     not like '%COALESCE(new.approval_status, ''''::text) <> ''approved''::text%' then fail := fail || 'the trigger does not refuse an approved supplier; '; end if;
  insert into public.leads (company_name, email, claimed, claimed_by)
       values ('', 'zz-demo-cert-u@probe1672.example.invalid', true, 'zz-demo-cert-u@probe1672.example.invalid') returning id into u;

  -- each its own licence number (leads_claimed_trade_licence_uidx)
  update public.leads set licence_legal_name = 'ZZ DEMO Cert Probe Licensed LLC', trade_license_no = 'ZZ-1672-CERT-' || id where id in (n, s, u);

  select count(*) into k from public.agent_actions where kind = 'supplier_agreement_reissued' and target_id = n::text;
  if k <> 1 then fail := fail || 'n: re-issued ' || k || ' times, not once; '; end if;
  select count(*) into k from public.agent_actions where kind = 'supplier_agreement_reissued' and target_id in (s::text, u::text);
  if k <> 0 then fail := fail || 'a certificate that must stand was re-issued (' || k || '); '; end if;
  -- the same licence read again changes nothing and asks nothing
  update public.leads set licence_legal_name = 'ZZ DEMO Cert Probe Licensed LLC' where id = n;
  select count(*) into k from public.agent_actions where kind = 'supplier_agreement_reissued' and target_id = n::text;
  if k <> 1 then fail := fail || 'n: an unchanged reading re-issued it; '; end if;
  if has_function_privilege('anon', 'public.fn_sign_supplier_again_when_his_licence_is_read()', 'execute') then fail := fail || 'anon may execute the trigger function; '; end if;

  delete from public.agent_actions where target_table = 'leads' and target_id in (n::text, s::text, u::text);
  delete from public.leads where id in (n, s, u);
  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end);
end $$;
