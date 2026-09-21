-- PROBE for a_licence_reminder_reaches_whatsapp_through_the_approved_template.sql — owner: customer_support
-- Read-only. Returns one verdict row. Behaviour of the real sweep (rolled back) is proved separately by
-- scripts/checks/support_acceptance_group_licence_expiry.mjs.
with src as (
  select p.proname, p.prosrc, p.oid,
         coalesce(array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%', false) as pinned
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('fn_licence_expiry_sweep', 'fn_doc_final_notice')
), f as (
  select unnest(array[
    case when (select count(*) from src) <> 2 then 'a routine is missing' end,
    case when exists (select 1 from src where not pinned) then 'a routine has no pinned search_path' end,
    case when exists (select 1 from src where has_function_privilege('anon', oid, 'execute')
                                          or has_function_privilege('authenticated', oid, 'execute'))
         then 'a routine is callable by anon/authenticated' end,
    case when (select prosrc from src where proname = 'fn_licence_expiry_sweep') ~ 'outreach_channel_policy'
         then 'the sweep still gates WhatsApp on the stale channel policy' end,
    case when (select prosrc from src where proname = 'fn_licence_expiry_sweep') !~ '''licence_renewal'', ''licence_expiry'', r\.email, ''supplier'''
         then 'the sweep email is not addressed to the supplier role, so it is never twinned to WhatsApp' end,
    case when (select prosrc from src where proname = 'fn_doc_final_notice') ~ 'to_phone'
         then 'the final notice still queues its own WhatsApp row beside the fan-out twin' end,
    case when not exists (select 1 from public.notification_copy where type = 'licence_renewal' and subject_ar ~ '[؀-ۿ]' and body_ar ~ '[؀-ۿ]')
         then 'no Arabic copy for licence_renewal' end,
    case when (select value::jsonb ? 'control_mode_code' from public.app_secrets where key = 'wa_template_sids')
         then 'the rejected control_mode_code is still registered' end,
    case when coalesce((select value::jsonb #>> '{supplier_doc_expiry,en}' from public.app_secrets where key = 'wa_template_sids'), '') = ''
         then 'no supplier_doc_expiry template SID is registered' end
  ]) why
)
select case when count(why) = 0
            then 'PROBE OK: the licence ask is twinned to confirmed WhatsApp numbers on supplier_doc_expiry; no duplicate final-notice row; Arabic copy present'
            else 'PROBE FAILED: ' || string_agg(why, '; ') end as verdict
  from f;
