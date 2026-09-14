-- A BROWSER THAT IS NOT SIGNED IN CANNOT RUN THE CUSTOMER DOCUMENT ROUTINES.
--
-- Assigned: it_engineer (the security sweep found it). The routines are the sales engineer's
-- (documents_customer_vault.sql); only their grants change here.
--
-- WHAT WAS MEASURED, 14 Sep 2026: fn_customer_documents(text,text,integer,text[]) and
-- fn_customer_document_refs() are SECURITY DEFINER and anon could execute them.
-- documents_customer_vault.sql revoked EXECUTE from public and granted it to authenticated and
-- service_role, which is its stated intent, but anon held its own grant, so the revoke from public did
-- not close it. The IT engineer's first security baseline recorded both as accepted; that seeding was
-- removed (the_it_engineer_runs_its_duties_every_hour.sql), which is how they surfaced.
--
-- WHAT THIS CHANGES: revoke from anon only. authenticated and service_role keep EXECUTE. Neither
-- routine body is touched.
--
--   node scripts/apply_sql.mjs scripts/sql/a_browser_cannot_run_the_customer_document_routines_unsigned.sql --apply --ddl

revoke execute on function public.fn_customer_documents(text, text, integer, text[]) from anon;
revoke execute on function public.fn_customer_document_refs() from anon;

do $check$
declare r record;
begin
  for r in select p::regprocedure p from unnest(array[
             'public.fn_customer_documents(text, text, integer, text[])'::regprocedure,
             'public.fn_customer_document_refs()'::regprocedure]) p loop
    if has_function_privilege('anon', r.p, 'execute') then
      raise exception '% is still executable by anon', r.p;
    end if;
    if not has_function_privilege('authenticated', r.p, 'execute') or not has_function_privilege('service_role', r.p, 'execute') then
      raise exception '% lost the authenticated or service_role grant it is meant to keep', r.p;
    end if;
  end loop;
  raise notice 'anon can no longer execute the two customer document routines; authenticated and service_role still can.';
end
$check$;
