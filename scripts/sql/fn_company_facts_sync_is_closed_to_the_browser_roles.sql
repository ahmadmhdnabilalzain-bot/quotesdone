-- fn_company_facts_sync() IS CLOSED TO THE BROWSER ROLES.
--
-- Assigned: it_engineer (security of the estate), carried out for the ceo.
--
-- MEASURED 14 Sep 2026 on production htdblwldjkcgjvmqkbeh: public.fn_company_facts_sync() is SECURITY
-- DEFINER with a pinned search_path, and anon AND authenticated could EXECUTE it. It was re-created with a
-- plain CREATE by scripts/sql/what_the_agents_tell_customers_follows_the_card_fee_and_the_new_non_response_charge.sql,
-- and a plain CREATE grants EXECUTE to PUBLIC (apply discipline, section 2). The security advisors flagged
-- two NEW findings and anon_cannot_execute_security_definer failed on PR #613.
--
-- One overload exists: fn_company_facts_sync(). No browser path calls it (grep "\.rpc(" src/ is 0); its
-- callers run as service_role or postgres, which keep EXECUTE.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_company_facts_sync_is_closed_to_the_browser_roles.sql --apply --ddl

begin;

revoke execute on function public.fn_company_facts_sync() from public, anon, authenticated;

do $check$
begin
  if has_function_privilege('anon', 'public.fn_company_facts_sync()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.fn_company_facts_sync()', 'EXECUTE') then
    raise exception 'fn_company_facts_sync() is still executable by a browser role';
  end if;
  if not has_function_privilege('service_role', 'public.fn_company_facts_sync()', 'EXECUTE') then
    raise exception 'the revoke took service_role''s grant, which the real callers depend on';
  end if;
  raise notice 'fn_company_facts_sync(): closed to anon and authenticated; service_role keeps EXECUTE';
end
$check$;

commit;
