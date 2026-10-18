-- A WHATSAPP TEMPLATE TWILIO NO LONGER HAS IS 'missing', NOT "404"
-- Seat: customer_support (owner of the WhatsApp templates). 6 Oct 2026.
--
-- MEASURED 6 Oct 2026 (Twilio Content API, read-only, and public.messaging_template):
--   * six register rows read status "404": login_code en/ar (HX5c97.., HX0580..), supplier_account_notice
--     en/ar (HX7301.., HX9ef9..), support_reply en/ar (HXc0db.., HX0928..). Twilio answers 404 for all six:
--     they are SUPERSEDED Content SIDs, deleted after the 18/23 Sep resubmissions. None is in
--     app_secrets.wa_template_sids, so nothing sends with them.
--   * the LIVE SIDs in wa_template_sids for the same keys exist and Meta has APPROVED every one:
--     login_code en HX1748b80b.. / ar HXec996cbd.. (AUTHENTICATION, quotesdone_login_code_*_mul7343u),
--     supplier_account_notice en HXb4fe9f13.. / ar HX0aead0e5.. (UTILITY), support_reply en/ar (UTILITY).
--     So nothing was recreated: a second submission would have been a duplicate of an approved template.
--   * the two live login_code SIDs had NO register row at all; they are registered here as Twilio reports.
--   * the sign-in code does not use these Content templates: login_otp sends through Twilio Verify, whose
--     WhatsApp channel carries its own Authentication template. Last 7 days of phone_verifications:
--     1 code delivered by WhatsApp (5 Oct), 2 legacy rows (3 Oct), 0 failures logged by login_otp.
--
-- THE CAUSE. wa_templates_watch fell back to the body's top-level `status`, and Twilio's ERROR body has
-- `status: 404`, so an HTTP code was written as Meta's verdict. The watcher now writes 'missing' and puts
-- the code in the new column last_http_status. 'missing' is final like 'rejected' in both halves of the
-- scheduler gate (here, and the watcher's FINAL set), so a deleted SID is not polled every day.
--
-- prevented by: scripts/checks/the_template_watcher_polls_what_its_gate_reads.test.mjs
--   node scripts/apply_sql.mjs scripts/sql/a_whatsapp_template_twilio_no_longer_has_is_missing_not_404.sql --apply --ddl

alter table public.messaging_template add column if not exists last_http_status integer;
comment on column public.messaging_template.last_http_status is
  'HTTP status of the last Twilio Content ApprovalRequests read for this SID (404 = the SID no longer exists; status then reads missing). Never copied into status.';

update public.messaging_template
   set status = 'missing', last_http_status = 404, approved_at = null,
       note = coalesce(note || ' | ', '') || '6 Oct 2026: superseded SID, Twilio 404; was stored as status "404"'
 where channel = 'whatsapp' and status ~ '^[0-9]{3}$';

insert into public.messaging_template (sid, channel, template_key, lang, name, category, status, approved_at, last_checked_at, last_http_status, note)
values
  ('HX1748b80ba6f52ee34a139cf92e5f0e1c', 'whatsapp', 'login_code', 'en', 'quotesdone_login_code_en_mul7343u', 'AUTHENTICATION', 'approved', now(), now(), 200, '6 Oct 2026: live SID in wa_template_sids had no register row; Twilio read approved'),
  ('HXec996cbdd957450b52c4f7f7b3a9d3b7', 'whatsapp', 'login_code', 'ar', 'quotesdone_login_code_ar_mul7343u', 'AUTHENTICATION', 'approved', now(), now(), 200, '6 Oct 2026: live SID in wa_template_sids had no register row; Twilio read approved')
on conflict (sid) do nothing;

create or replace function public.fn_resilience_orphan_steps_due()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    -- coalesce, not '<>': a missing row must read as "not enabled", which is the state that needs
    -- reporting. A gate that opens only when a key is present and wrong is a gate that a deleted key
    -- switches off silently.
    'email_cron',   coalesce((select value from public.app_secrets where key = 'email_enabled'), '') is distinct from 'true',

    -- THE FLAG ARM, unchanged: an estate that has never had an approved set polls until it does.
    -- THE WORK ARM, added 22 Sep 2026: something is still pending and nobody has asked about it
    -- today. 'received' is Twilio's word for submitted-and-undecided; anything that is neither
    -- approved nor rejected is undecided, so the condition is written as the absence of a verdict
    -- rather than as a list of the words Twilio currently uses for waiting.
    -- THE RE-CHECK ARM, added 29 Sep 2026: the same 20 hours now applies to APPROVED rows too, so the
    -- predicate is "not rejected" rather than "neither approved nor rejected". Meta can pause or
    -- reject a template after approving it, and only asking again notices.
    'wa_templates', coalesce((select value from public.app_secrets where key = 'wa_templates_ready'), '') is distinct from 'true'
      or exists (
        select 1 from public.messaging_template
         where channel = 'whatsapp'
           and status not in ('rejected', 'missing')
           and (last_checked_at is null or last_checked_at < now() - interval '20 hours')),

    -- The queue is the gate. No flag, because nothing here costs a model call and a queued SMS has a
    -- person at the end of it.
    'send_sms', exists (
      select 1 from public.notifications where channel = 'sms' and status = 'queued'),

    -- Both halves must hold: the switch is on AND there is work. Either alone would be a step that runs
    -- for nothing 96 times a day.
    'doc_extract', coalesce((select value from public.app_secrets where key = 'doc_extract_drain_enabled'), '') = 'true'
      and exists (
        select 1 from public.documents
         where status in ('pending', 'error') and coalesce(attempts, 0) < 3),

    'email_triage', coalesce((select value from public.app_secrets where key = 'email_triage_enabled'), '') = 'true'
      and exists (
        select 1 from public.inbound_messages
         where needs_review and triaged_at is null and replied_at is null),

    -- WEEKLY, MEASURED OFF THE WORK ITSELF rather than a schedule string, AND PER SOURCE. Due while
    -- EITHER list lacks a recent enough attempt: an `ok` run holds that source for 6 days (the founder
    -- asked for a weekly check, and 6 not 7 so a slow week never skips one), a failed or unparseable one
    -- for 6 hours — a transient UN or UAE outage is retried a few times a day, never every 15 minutes.
    --
    -- PER SOURCE IS NOT A DETAIL (found in independent review before this was applied). Written as one
    -- ungrouped NOT EXISTS over the whole table, a healthy UN fetch would hold the gate shut for six days
    -- and the UAE list — failing every time — would be retried once a week instead of every six hours,
    -- with the documented back-off silently never applying to the source that actually needed it. That is
    -- the estate's "guarded by a condition that cannot occur" shape: the failure branch exists and can
    -- never be reached. The cost of the correct version is that a broken source re-opens the gate every
    -- 6 hours and the healthy list is downloaded again with it, ~4 times a day instead of once a week.
    -- That is the right way round: bandwidth is cheap and an unscreened sanctions source is not.
    --
    -- Every attempt writes a screening_run row whatever happened, which is what makes this a measurement
    -- and not a hope; a zero-run history reads as due, which is correct, because it has never run.
    'sanctions', coalesce((select value from public.app_secrets where key = 'sanctions_screen_enabled'), '') = 'true'
      and exists (
        select 1 from (values ('un_consolidated'), ('uae_local_terrorist_list')) as s(source)
         where not exists (
           select 1 from public.screening_run r
            where r.source = s.source
              and r.fetched_at > now() - case when r.status = 'ok' then interval '6 days' else interval '6 hours' end))
  )
$fn$;

comment on function public.fn_resilience_orphan_steps_due() is
  'Which of the six orphaned jobs the resilience tick should call this beat. Each gate is the WORK, not a schedule string. wa_templates: the flag arm, or any WhatsApp template neither rejected nor missing (Twilio 404, since 6 Oct 2026) and not confirmed with Twilio for 20 hours (undecided since 22 Sep 2026; approved too since 29 Sep 2026, so a template Meta pauses or rejects after approving it is noticed within a day).';

-- PROBE (DDL above, so a verdict ROW, nothing written by the probe itself).
select case
  when exists (select 1 from public.messaging_template where channel = 'whatsapp' and status ~ '^[0-9]{3}$')
    then 'PROBE FAILED: an HTTP code is still stored as a template status'
  when (select count(*) from public.messaging_template where sid in ('HX1748b80ba6f52ee34a139cf92e5f0e1c','HXec996cbdd957450b52c4f7f7b3a9d3b7')) <> 2
    then 'PROBE FAILED: the live login_code SIDs are not in the register'
  else 'PROBE OK: no numeric statuses; live login_code SIDs registered' end as verdict;
