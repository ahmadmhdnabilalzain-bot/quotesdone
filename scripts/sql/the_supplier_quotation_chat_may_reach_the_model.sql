-- the_supplier_quotation_chat_may_reach_the_model.sql
-- Assigned: sales_engineer.
--
-- MEASURED 13 Oct 2026 (live photographed-quote test after #1385/#1387). Since #1335, supplier_api writes every
-- quotation-chat reply through _shared/ai_reply.ts -> _shared/llm.ts -> ai_gateway, and llm.ts presents
-- cred_fn_supplier_api. That credential's scope did not include ai_gateway, so ai_gateway answered 403 to
-- EVERY reply: internal_credential_audit read reason 'out_of_scope' (context fn.supplier_api, function ai_gateway)
-- and agent_runs carried llm_gateway_auth gateway_forbidden for supplier_api at 01:16, 01:46 and 02:33 UTC.
-- Every supplier, not only demo ones, got the held notice instead of the engineer's answer, and the queued turn
-- was replayed into the same refusal. (The chat-attachment READ reached the model because read_every_attachment
-- calls the gateway with cred_fn_ai, not with this credential.)
--
-- THE CHANGE: ai_gateway joins fn.supplier_api's scope, as customer_api's credential already has it for the customer
-- side of the same conversation. The new check found four more functions that call the model and whose credential
-- is not scoped to the gateway: inbound_email (5 refusals in the last 7 days, measured), sales_engineer,
-- marketing_outreach and supplier_portal (no refusal recorded in 7 days: found by their source, not by a failure).
-- They get the same one entry. Nothing else in any scope moves.
-- prevented by: the verdict row below (applied with apply_sql, read back) and
--   scripts/checks/a_function_that_calls_the_model_may_reach_the_gateway.test.mjs (reads production).
update public.internal_credential
   set scope = (select array_agg(distinct s order by s) from unnest(scope || array['ai_gateway']) s)
 where context in ('fn.supplier_api', 'fn.inbound_email', 'fn.sales_engineer', 'fn.marketing_outreach', 'fn.supplier_portal')
   and active and not (scope @> array['ai_gateway']);

select case when not exists (select 1 from public.internal_credential
                            where context in ('fn.supplier_api', 'fn.inbound_email', 'fn.sales_engineer', 'fn.marketing_outreach', 'fn.supplier_portal')
                              and active and not (scope @> array['ai_gateway']))
            then 'PROBE OK: every model-calling credential may reach ai_gateway'
            else 'PROBE FAILED: a model-calling credential still cannot reach ai_gateway' end as verdict;
