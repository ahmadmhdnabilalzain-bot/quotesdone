-- THE TEMPLATE WATCHER KEEPS WATCHING AFTER THE FIRST APPROVAL
-- (customer_support, 22 Sep 2026, finding INT-02)
--
-- WHAT WAS MEASURED, 22 Sep 2026.
--   * public.messaging_template holds SEVEN WhatsApp templates still in Twilio's 'received' state:
--     quotesdone_login_code_en/_ar and quotesdone_supplier_account_notice_en/_ar (submitted 18 Sep,
--     last_checked_at 18 Sep 04:05), the three UTILITY re-submissions from 14 Sep (last_checked_at
--     14 Sep, the moment they were created) and quotesdone_supplier_quote_accepted_en/_ar from
--     6 Sep. Nothing has asked Twilio about any of them since.
--   * app_secrets.wa_template_sids ALREADY POINTS AT four of those pending sids (login_code en/ar,
--     supplier_account_notice en/ar, supplier_quote_accepted en/ar), so the live map names templates
--     Meta has not approved.
--   * app_secrets.wa_templates_ready is nevertheless 'true'.
--
-- WHY NOTHING NOTICED. wa_templates_watch is on the scheduler — it is the 'wa_templates' job inside
-- the orphans step — but it is gated TWICE on that one stale boolean, and both gates read it the
-- same way:
--   1. here, in fn_resilience_orphan_steps_due: due only while wa_templates_ready is not 'true';
--   2. in the function itself: `if ready === 'true' return { already_ready: true }`.
-- The flag is written ONCE, by the run that first saw every tracked template approved, and nothing
-- ever writes it back. So the moment the first batch landed, the watcher switched itself off for
-- good — and every template submitted afterwards has been waiting on a poller that will never poll
-- again. That is the estate's own lens twice over: a guard that fires when the system works, and a
-- heartbeat that stops at the exact moment it starts mattering.
--
-- THE FIX IS TO GATE ON THE WORK, NOT ON THE FLAG, which is how every other job in this routine is
-- already written (send_sms gates on the queue; sanctions gates on the age of the newest run). The
-- wa_templates gate now ALSO opens while any WhatsApp template is still neither approved nor
-- rejected and has not been asked about for 20 hours. The flag arm is kept: an estate whose
-- templates were never approved at all must still poll from cold.
--
-- 20 HOURS IS A DAILY CADENCE, not a daily schedule. Meta takes hours to days to decide and the
-- founder asked for a daily re-check; 20 rather than 24 so a tick that lands a little late never
-- skips a day. The cost is bounded and already budgeted: this job's slot in the orphans step is
-- 20 s of a 60 s step, and it now costs that once a day instead of never.
--
-- THE GATE ONLY CLOSES BECAUSE THE WATCHER NOW STAMPS last_checked_at. wa_templates_watch polled
-- Twilio per sid and threw the answer away — it wrote nothing to messaging_template, which is why
-- that table's last_checked_at has been 12 days stale. The same commit makes it record each sid's
-- status and last_checked_at, so this gate shuts for 20 hours after every run instead of standing
-- open. Without that write the two halves disagree and the step polls every beat.
--
-- ONLY THE wa_templates LINE CHANGES. The rest of this routine is reproduced verbatim from the live
-- body (read from pg_proc.prosrc, 22 Sep 2026) because scripts/sql is append-only and this file
-- becomes canonical for the routine; a shortened copy here would silently delete five other gates.

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
    'wa_templates', coalesce((select value from public.app_secrets where key = 'wa_templates_ready'), '') is distinct from 'true'
      or exists (
        select 1 from public.messaging_template
         where channel = 'whatsapp'
           and status not in ('approved', 'rejected')
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

-- CREATE grants EXECUTE to PUBLIC where CREATE OR REPLACE does not; the revoke is repeated anyway so
-- this file is correct whether or not the routine already existed.
revoke execute on function public.fn_resilience_orphan_steps_due() from public, anon, authenticated;

comment on function public.fn_resilience_orphan_steps_due() is
  'Which of the six orphaned jobs the resilience tick should call this beat. Each gate is the WORK, not a schedule string. wa_templates gained its second arm on 22 Sep 2026: gated on app_secrets.wa_templates_ready alone, the watcher switched itself off the day the first batch was approved and seven templates submitted afterwards were never re-checked.';
