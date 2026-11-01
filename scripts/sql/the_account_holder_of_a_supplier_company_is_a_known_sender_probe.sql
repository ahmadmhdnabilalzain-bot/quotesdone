-- PROBE (pure, no DDL, aborted transaction) for the_account_holder_of_a_supplier_company_is_a_known_sender.sql.
-- Run after the definition, in the same rolled-back transaction while it is pending, or alone once it is applied. It always
-- ends in raise exception 'CHK<<json>>', so its one ZZ DEMO lead rolls back. It answers PROBE FAILED before the fix.
do $$
declare v_holder text; v_listing text; v_stranger text; v_real_before bigint; v_real_after bigint;
begin
  select count(*) into v_real_before from public.leads where company_name not like 'ZZ DEMO%';
  insert into public.leads (company_name, email, claimed, claimed_by)
  values ('ZZ DEMO - known sender probe', 'zz-demo-known-listing@example.invalid', true, 'ZZ-Demo-Known-Holder@example.invalid');
  v_holder := public.fn_mail_sender_known(' zz-demo-known-holder@example.invalid ');
  v_listing := public.fn_mail_sender_known('zz-demo-known-listing@example.invalid');
  v_stranger := public.fn_mail_sender_known('zz-demo-known-stranger@example.invalid');
  select count(*) into v_real_after from public.leads where company_name not like 'ZZ DEMO%';
  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when v_holder is distinct from 'supplier' then 'PROBE FAILED: the account holder is not a known supplier'
                    when v_listing is distinct from 'supplier' then 'PROBE FAILED: the listing address is no longer known'
                    when v_stranger is not null then 'PROBE FAILED: a stranger reads as known'
                    when v_real_before <> v_real_after then 'PROBE FAILED: real leads moved'
                    else 'PROBE OK' end,
    'holder', v_holder, 'listing', v_listing, 'stranger', v_stranger);
end $$;
