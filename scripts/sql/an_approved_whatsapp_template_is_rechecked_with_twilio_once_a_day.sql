-- AN APPROVED WHATSAPP TEMPLATE IS RE-CHECKED WITH TWILIO ONCE A DAY
-- Seat: customer_support. 29 Sep 2026. Review of #1049.
--
-- THE GAP. wa_templates_watch read an approved/rejected verdict from public.messaging_template and
-- never asked Twilio again, and this routine opened the wa_templates gate only while something was
-- UNDECIDED. So a template Meta later PAUSES (quality) or REJECTS kept reading 'approved' in the
-- register, and send_whatsapp (which trusts an approved register row as read) kept sending with it.
-- Measured 29 Sep 2026: 15 WhatsApp register rows approved, oldest last_checked_at 6 Sep 2026.
--
-- THE FIX, in two halves that must agree:
--   * here: the wa_templates gate ALSO opens while any APPROVED row has not been confirmed with
--     Twilio for 20 hours (the same daily cadence as the undecided arm; 20 not 24 so a late tick never
--     skips a day). Rejected is final and is not asked again.
--   * supabase/functions/wa_templates_watch: an approved row older than the same 20 hours is polled
--     again; a verdict that is no longer 'approved' is written to the register (approved_at cleared),
--     which is what stops send_whatsapp using that template, and raises one customer_support finding
--     per template that closes when Meta approves it again.
-- ONLY THE wa_templates LINE CHANGES. Everything else is verbatim from the canonical body
-- (scripts/sql/the_template_watcher_keeps_watching_after_the_first_approval.sql, = live 29 Sep 2026).
--
-- prevented by: scripts/checks/the_template_watcher_polls_what_its_gate_reads.test.mjs
--   node scripts/apply_sql.mjs scripts/sql/an_approved_whatsapp_template_is_rechecked_with_twilio_once_a_day.sql --apply --ddl

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
           and status <> 'rejected'
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
  'Which of the six orphaned jobs the resilience tick should call this beat. Each gate is the WORK, not a schedule string. wa_templates: the flag arm, or any WhatsApp template not rejected and not confirmed with Twilio for 20 hours (undecided since 22 Sep 2026; approved too since 29 Sep 2026, so a template Meta pauses or rejects after approving it is noticed within a day).';

-- ══ PROBE ═══════════════════════════════════════════════════════════════════════════════════
-- DDL above, so the verdict is a ROW and nothing is written. Reads the live register: if any
-- approved template is unconfirmed for 20 hours, the gate must be open. The isolating test (every
-- other arm shut, only a stale approved row left) is the rolled-back check named above.
select case
  when exists (select 1 from public.messaging_template where channel = 'whatsapp' and status = 'approved'
                and last_checked_at < now() - interval '20 hours')
       and not coalesce((public.fn_resilience_orphan_steps_due()->>'wa_templates')::boolean, false)
    then 'PROBE FAILED: a stale approved template did not open the wa_templates gate'
  else 'PROBE OK: an approved template unconfirmed for 20 hours opens the wa_templates gate' end as verdict;
