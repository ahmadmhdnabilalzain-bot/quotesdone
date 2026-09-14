-- ASSERTS THAT A BROWSER THAT IS NOT SIGNED IN CANNOT RUN THE CUSTOMER DOCUMENT ROUTINES.
--
-- Assigned: it_engineer (security sweep). The routines are the sales engineer's
-- (documents_customer_vault.sql); this file changes nothing, it only asserts.
--
-- WHAT WAS MEASURED, 14 Sep 2026. The IT engineer's first sweep flagged fn_customer_documents(text,
-- text,integer,text[]) and fn_customer_document_refs() as anon-executable. They are not: anon cannot
-- execute either (measured by the review of #639); authenticated and service_role can, as
-- documents_customer_vault.sql intends. The flag came from fn_it_security_exposures counting
-- "authenticated can execute" as an anon exposure, fixed in the_it_engineer_runs_its_duties_every_hour.sql.
-- This file stays as the assertion that the portal RPCs remain closed to signed-out callers.
--
--   node scripts/apply_sql.mjs scripts/sql/a_browser_cannot_run_the_customer_document_routines_unsigned.sql --apply --ddl

do $check$
declare r record;
begin
  for r in select p::regprocedure p from unnest(array[
             'public.fn_customer_documents(text, text, integer, text[])'::regprocedure,
             'public.fn_customer_document_refs()'::regprocedure]) p loop
    if has_function_privilege('anon', r.p, 'execute') then
      raise exception '% is executable by anon; documents_customer_vault.sql intends authenticated and service_role only', r.p;
    end if;
    if not has_function_privilege('authenticated', r.p, 'execute') or not has_function_privilege('service_role', r.p, 'execute') then
      raise exception '% has lost the authenticated or service_role grant it is meant to have', r.p;
    end if;
  end loop;
  raise notice 'asserted: anon cannot execute the two customer document routines; authenticated and service_role can.';
end
$check$;
