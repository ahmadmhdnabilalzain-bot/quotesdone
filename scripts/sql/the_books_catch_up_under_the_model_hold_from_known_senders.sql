-- accountant, 28 Sep 2026. THE BOOKS CATCH UP UNDER THE MODEL HOLD, FROM SENDERS THE BOOKS ALREADY KNOW.
--
-- MEASURED (production, 28 Sep 2026): 11 expense-mailbox rows held with owner_role 'accountant' since 23-24 Sep
-- (inbound_messages 161, 163-172): 9 OpenAI "account has been funded" top-ups, the 13 Sep Google Play renewal
-- (Dropbox Simple, AED 26.99/month: the register's "Google" monthly line, next_due 2026-09-13) and one Anthropic
-- receipt. The last expense_entries row is 19 Sep. Cause, read in resend_inbound/index.ts and
-- _shared/reasoned_books.ts: WHAT the document is (documentKind) and WHO issued it (receiptVendor) are reasoned;
-- under the model hold both return null and the row is held for "the accountant's queue replays it". The
-- known-sender shortcut exists (public.expense_sender_reading, reused after SENDER_REUSE_AFTER = 2 identical
-- answers) but it learns ONLY from the model's answers, so under the hold it never learned anything: the table
-- held 0 rows. And nothing scheduled the replay: no seat_duty, no cron job and no resilience_ping step runs the
-- accountant's expense_sweep, so even a learned sender would never have been swept.
--
-- THE FIX, two halves (routine work is code, 24 Sep ruling):
--  1. The readings the books already prove are written down: exact ISSUING addresses (the forwarded "From:"
--     header, read by format, never a word), each tied to the vendor and cadence the books already carry for it.
--     They are seeded at the reuse threshold, so documentKind/receiptVendor answer from the books with no model.
--     Only the figures are then parsed (_shared/receipt_parse.ts); verified offline on rows 163 and 172:
--     USD 10.50 on 2026-09-19 (labelled:paid) and AED 26.99 on 2026-09-13 with VAT 1.29 (labelled:total).
--     Anthropic (row 161) is NOT seeded: its PDF has no text layer, so no amount can be read without a vision
--     model, and it stays held rather than guessed.
--  2. resilience_ping gains an `expense_sweep` step (edge change in the same PR), gated here: due while an
--     accountant-held expense row waits AND the accountant has not swept in the last 20 hours.
--
-- A later model answer still updates a seeded reading (fn_expense_sender_learn resets on a different answer).
-- ponytail: Google Play sells more than Dropbox; the seed names the vendor the books already use ("Google", 4
-- prior entries). A different Play purchase would be booked to Google until the reasoning disagrees twice.

insert into public.expense_sender_reading (sender, kind, kind_times, vendor, vendor_times, last_email_id)
values
  ('noreply@tm.openai.com',                  'receipt_one_off', 2, 'OpenAI', 2, 'seed:books 28 Sep 2026 (prepaid API top-ups)'),
  ('googleplay-noreply@google.com',          'receipt_monthly', 2, 'Google', 2, 'seed:books 28 Sep 2026 (register: Google monthly AED 26.99)'),
  ('invoice+statements@invoicing.resend.com','receipt_monthly', 2, 'Resend', 2, 'seed:books 28 Sep 2026 (register: Resend monthly USD 20)')
on conflict (sender) do nothing;

create or replace function public.fn_resilience_orphan_steps_due()
 returns jsonb
 language sql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
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

    -- 28 Sep 2026 (the_books_catch_up_under_the_model_hold_from_known_senders.sql): the accountant's sweep.
    -- Work AND a quiet clock: an expense-mailbox row the accountant holds, and no sweep run in 20 hours. The
    -- sweep writes agent_runs (agent 'accountant', counts.action 'expense_sweep') whatever happens, so a
    -- failing sweep is retried the next day, not every 15 minutes.
    'expense_sweep', exists (
        select 1 from public.inbound_messages
         where owner_role = 'accountant' and needs_review and replied_at is null
           and to_email ilike 'expenses@%')
      and not exists (
        select 1 from public.agent_runs
         where agent = 'accountant' and counts->>'action' = 'expense_sweep'
           and started_at > now() - interval '20 hours'),

    -- WEEKLY, MEASURED OFF THE WORK ITSELF rather than a schedule string, AND PER SOURCE. See
    -- four_live_functions_had_no_clock_and_the_sanctions_screen_had_no_producer.sql for why per source.
    'sanctions', coalesce((select value from public.app_secrets where key = 'sanctions_screen_enabled'), '') = 'true'
      and exists (
        select 1 from (values ('un_consolidated'), ('uae_local_terrorist_list')) as s(source)
         where not exists (
           select 1 from public.screening_run r
            where r.source = s.source
              and r.fetched_at > now() - case when r.status = 'ok' then interval '6 days' else interval '6 hours' end))
  )
$function$;
-- CREATE OR REPLACE keeps the ACL (PR #742's revoke stands); re-asserted so a reader need not check.
revoke execute on function public.fn_resilience_orphan_steps_due() from public, anon, authenticated;

-- PROBE (runs at apply, reports through a final SELECT, never raises: this file carries DDL).
select 'PROBE ' || case
  when (public.fn_expense_sender_reading('noreply@tm.openai.com')->>'kind_times')::int >= 2
   and public.fn_expense_sender_reading('googleplay-noreply@google.com')->>'vendor' = 'Google'
  then 'OK known senders readable at the reuse threshold; expense_sweep due now = '
       || (public.fn_resilience_orphan_steps_due()->>'expense_sweep')
  else 'FAILED a seeded sender does not read back' end as verdict;
