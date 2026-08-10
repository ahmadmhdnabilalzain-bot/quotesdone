-- The 63 anon-executable SECURITY DEFINER functions, triaged by evidence rather than revoked blind.
-- Every one of the 63 was checked against the Next.js source and the edge functions:
--
--   BROWSER   7   named in src/ — a real product surface calls them (supplier portal, OS shell):
--                 fn_customer_preference_learn, fn_os_memory, fn_supplier_document_impact,
--                 fn_supplier_knowledge_graph, fn_supplier_opportunities,
--                 fn_supplier_quote_recommend, fn_supplier_twin.
--                 LEFT ALONE — revoking these is the thing that breaks product surfaces.
--   TRIGGER   5   return type `trigger`. Nothing calls them by name, ever, in any language.
--                 REVOKED BELOW.
--   INTERNAL 51   not named anywhere in src/. The ones with edge references are called with the
--                 service role; the rest are cron- and database-only. Each needs one look before
--                 its grant goes, so they are listed in the session record and not touched here.
--
-- A trigger function is invoked by the trigger system as the table owner, so this changes nothing
-- about whether the trigger fires — proven on production for the four emitter triggers revoked the
-- same way an hour earlier, which still emitted after the revoke.
revoke execute on function public.fn_approval_raise_on_award() from public, anon, authenticated;
revoke execute on function public.fn_org_task_cross_os_guard() from public, anon, authenticated;
revoke execute on function public.fn_po_orders_link() from public, anon, authenticated;
revoke execute on function public.trg_company_event_dispatch() from public, anon, authenticated;
revoke execute on function public.trg_learn_customer_preference() from public, anon, authenticated;
