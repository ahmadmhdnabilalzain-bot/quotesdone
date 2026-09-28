-- THE TEMPLATE WATCHER WAS CALLED WITH A CREDENTIAL NOT SCOPED TO IT (it_engineer, 28 Sep 2026).
--
-- Measured: internal_credential_audit held 137 rows in 48 h of function 'wa_templates_watch',
-- context 'fn.resilience_ping', allowed=false, reason 'out_of_scope' — every hourly orphan step
-- answered HTTP 403. fn.resilience_ping (credential 49) is scoped to ten callees and none of them is
-- wa_templates_watch. NO active credential in the table named wa_templates_watch at all.
--
-- Why it only showed now: the scheduler's gate for this job was shut from 9 Sep to 22 Sep (the stale
-- wa_templates_ready flag), and the_template_watcher_keeps_watching_after_the_first_approval.sql
-- re-opened it. The first call in two weeks was the first 403.
--
-- The same step's four siblings present the same credential and are equally out of scope (send_sms,
-- email_cron and email_triage are scoped only to cron.notifications, doc_extract only to
-- cron.documents); their gates are shut today, so they have not failed yet. resilience_ping now
-- presents the credential the scope model says owns each call — the pattern it already uses for
-- sanctions_screen (cron.compliance) — rather than widening fn.resilience_ping, which would make the
-- scoped credentials decorative.
--
-- The one widening here: cron.notifications is the WhatsApp/notification context (it already holds
-- send_whatsapp, send_sms, email_cron), so it is where the template watcher belongs.
update public.internal_credential
   set scope = (select array_agg(distinct s order by s) from unnest(scope || array['wa_templates_watch']) s)
 where context = 'cron.notifications' and retired_at is null and not (scope @> array['wa_templates_watch']);

select case when exists (select 1 from public.internal_credential
                          where context = 'cron.notifications' and retired_at is null
                            and scope @> array['send_sms','email_cron','email_triage','wa_templates_watch'])
             and exists (select 1 from public.internal_credential
                          where context = 'cron.documents' and retired_at is null and scope @> array['doc_extract'])
            then 'PROBE OK' else 'PROBE FAILED: a resilience_ping orphan job has no credential scoped to it' end as verdict;
