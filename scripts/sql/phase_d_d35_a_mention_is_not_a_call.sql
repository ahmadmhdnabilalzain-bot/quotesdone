-- =================================================================================================
-- Phase D — D35. A mention is not a call.
--
-- FOUND BY PROBE 6, which is the only reason it was found: the §8 probe that calls RPCs directly as
-- `anon` got HTTP 200 from public.fn_supplier_opportunities — a SECURITY DEFINER function that
-- ranks open inquiries for a supplier. It answered an unauthenticated caller.
--
-- It returned `{"note":"no open opportunities yet","count":0}` at the time, because the estate
-- currently holds zero inquiries. That is the whole danger: a zero cannot tell a dead guard from an
-- idle system. The function is reachable, executes as its owner, and returns nothing today only
-- because there is nothing to return. The first live RFQ changes the payload, not the permission.
--
-- WHY IT WAS OPEN, AND IT IS NOT AN OVERSIGHT — IT IS A MEASUREMENT DEFECT.
--
-- scripts/sql/revoke_execute_on_trigger_only_secdef_fns.sql triaged 63 anon-executable SECURITY
-- DEFINER functions and set seven aside:
--
--     BROWSER  7  named in src/ — a real product surface calls them (supplier portal, OS shell):
--                 fn_customer_preference_learn, fn_os_memory, fn_supplier_document_impact,
--                 fn_supplier_knowledge_graph, fn_supplier_opportunities,
--                 fn_supplier_quote_recommend, fn_supplier_twin.
--                 LEFT ALONE — revoking these is the thing that breaks product surfaces.
--
-- The evidence for "a real product surface calls them" was that the NAME appears in src/. Measured
-- now, on this tree:
--
--     grep -rn "\.rpc(" src/                                         ->  0 occurrences, total.
--     grep -rn "rpc(['\"]fn_supplier_opportunities['\"]" src/        ->  0
--     ... the same 0 for all seven.
--
-- The browser does not call ANY RPC directly. The one hit that produced the BROWSER classification
-- is src/components/portal/supplier/SupplierQuoteBuilder.tsx:26, and it is a COMMENT:
--
--     // The field names are fn_supplier_opportunities', read off the live payload rather than guessed:
--
-- A scanner that matches a mention instead of a call left seven SECURITY DEFINER functions
-- executable by anon for the sake of a product surface that does not exist. Every one of the seven
-- has a real caller and every real caller is an EDGE FUNCTION using admin.rpc(...) — the
-- service_role client — which holds its own explicit grant and is unaffected by this file:
--
--     fn_customer_preference_learn   customer_api/index.ts:1257
--     fn_os_memory                   os_api/index.ts:374
--     fn_supplier_document_impact    supplier_portal/index.ts:167
--     fn_supplier_knowledge_graph    supplier_portal/index.ts:178
--     fn_supplier_opportunities      supplier_portal/index.ts:294
--     fn_supplier_quote_recommend    supplier_portal/index.ts:159
--     fn_supplier_twin               supplier_portal/index.ts:97
--
-- REVOKING FROM anon ALONE WOULD BE A SILENT NO-OP. The grant is held through PUBLIC — the ACL reads
-- `=X/postgres` — and `revoke ... from anon` against a PUBLIC grant changes nothing while appearing
-- to succeed. PUBLIC is named first below for exactly that reason.
-- =================================================================================================

revoke execute on function public.fn_customer_preference_learn(p_customer_id uuid, p_stated jsonb)  from public, anon, authenticated;
revoke execute on function public.fn_os_memory(p_q text, p_from date, p_to date)                    from public, anon, authenticated;
revoke execute on function public.fn_supplier_document_impact(p_lead_id bigint)                     from public, anon, authenticated;
revoke execute on function public.fn_supplier_knowledge_graph(p_lead_id bigint)                     from public, anon, authenticated;
revoke execute on function public.fn_supplier_opportunities(p_lead_id bigint)                       from public, anon, authenticated;
revoke execute on function public.fn_supplier_quote_recommend(p_lead_id bigint, p_inquiry_id uuid)  from public, anon, authenticated;
revoke execute on function public.fn_supplier_twin(p_lead_id bigint)                                from public, anon, authenticated;

-- -------------------------------------------------------------------------------------------------
-- DEPLOY-TIME CONTROL. Asserted with has_function_privilege against the ROLE, not by reading the
-- text of the ACL: a SECURITY DEFINER guard that inspects its own identity is how the maintenance
-- door stayed open once already on this estate.
-- -------------------------------------------------------------------------------------------------
do $ctl$
declare r record; v_open text := ''; v_broken text := '';
begin
  for r in
    select p.oid, p.proname,
           has_function_privilege('anon',          p.oid, 'EXECUTE') as anon_can,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') as authed_can,
           has_function_privilege('service_role',  p.oid, 'EXECUTE') as service_can
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('fn_customer_preference_learn','fn_os_memory','fn_supplier_document_impact',
                         'fn_supplier_knowledge_graph','fn_supplier_opportunities',
                         'fn_supplier_quote_recommend','fn_supplier_twin')
  loop
    if r.anon_can or r.authed_can then
      v_open := v_open || r.proname || '(' || case when r.anon_can then 'anon ' else '' end
                       || case when r.authed_can then 'authenticated' else '' end || ') ';
    end if;
    -- The revoke must not take the grant the real callers depend on. service_role holds an
    -- explicit grant; if this ever goes false the supplier portal stops working.
    if not r.service_can then
      v_broken := v_broken || r.proname || ' ';
    end if;
  end loop;

  if v_open <> '' then
    raise exception 'D35: still executable without a service role: %', v_open;
  end if;
  if v_broken <> '' then
    raise exception 'D35: the revoke removed service_role EXECUTE from %, which is the grant the edge functions actually use.', v_broken;
  end if;

  raise notice 'D35: seven SECURITY DEFINER routines are no longer executable by anon or authenticated; service_role retains EXECUTE on all seven.';
end $ctl$;
