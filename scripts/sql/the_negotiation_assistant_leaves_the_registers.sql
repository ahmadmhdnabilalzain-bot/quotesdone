-- THE NEGOTIATION ASSISTANT LEAVES THE REGISTERS (21 Sep 2026, it_engineer, founder instruction 526).
--
-- MEASURED, read-only on production at 2026-09-21 09:22 UTC:
--   * Callers of the edge function negotiation_assistant: in src/ only the customer portal's
--     NegotiationAssistant panel (deleted in this PR); in supabase/functions none; in pg_proc 0 routines
--     name it; in cron.job 0 commands name it. A mention is not a reference: the remaining text matches
--     are ownership/registry rows and scorer scripts, listed here.
--   * Registry rows naming it: public.function_owner 1, public.it_watch_subject 1 (public_surface=true,
--     verify_jwt=true — the IT engineer probes it every tick), public.llm_seat_binding 1.
--     it_watch_finding rows with subject='negotiation_assistant': 0. No trigger and no foreign key sits on
--     any of the three tables.
--
-- WHAT WAS WRONG. The founder removed negotiations from both portals. The edge function then has no caller
-- and the coordinator deletes it from the project. If the three registry rows outlive it:
--   * scripts/checks/every_deployed_function_has_an_owner.mjs fails on "owned, not deployed";
--   * the IT engineer's tick probes a public surface that now 404s and raises a finding every run;
--   * the OpenRouter ledger keeps a seat binding for a function that can no longer spend.
--
-- WHAT THIS CHANGES. Deletes those three rows and returns ONE verdict row with the counts. Apply it in the
-- same step as the function deletion (either order inside the same coordinator turn).
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE. fn_negotiation_guidance(uuid,uuid), fn_supplier_negotiation(uuid),
-- fn_supplier_network_map() and public.supplier_negotiation_policy stay: the founder's order named the
-- portal surfaces and the function, and fn_customer_savings still reads the policy table. They are routines
-- with no surface — dropping them is a separate file once the sales_engineer confirms nothing it plans needs
-- them.

create temp table na_purge on commit drop as
with fo as (delete from public.function_owner   where function_slug = 'negotiation_assistant' returning 1),
     ws as (delete from public.it_watch_subject where subject       = 'negotiation_assistant' returning 1),
     sb as (delete from public.llm_seat_binding where fn            = 'negotiation_assistant' returning 1)
select (select count(*) from fo)::int as function_owner,
       (select count(*) from ws)::int as it_watch_subject,
       (select count(*) from sb)::int as llm_seat_binding;

select case
         when exists (select 1 from public.function_owner   where function_slug = 'negotiation_assistant')
           or exists (select 1 from public.it_watch_subject where subject       = 'negotiation_assistant')
           or exists (select 1 from public.llm_seat_binding where fn            = 'negotiation_assistant')
           then 'PROBE FAILED: a negotiation_assistant registry row survived'
         else 'PROBE OK: deleted function_owner=' || function_owner || ' it_watch_subject=' || it_watch_subject
              || ' llm_seat_binding=' || llm_seat_binding
       end as verdict,
       function_owner, it_watch_subject, llm_seat_binding
  from na_purge;
