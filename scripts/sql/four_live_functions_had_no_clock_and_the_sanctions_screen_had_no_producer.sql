-- FOUR LIVE FUNCTIONS HAD NO CLOCK, AND THE SANCTIONS SCREEN HAD NO PRODUCER (18 Sep 2026, it_engineer).
--
-- This extends the gate PR #742 introduced (two_live_edge_functions_were_invoked_by_nothing.sql) rather
-- than inventing a second mechanism: ONE routine answers for every orphan step, resilience_ping's
-- `orphans` tick acts on the answer, and the database decides whether there is work.
--
-- ═══ WHAT WAS MEASURED, 18 Sep 2026 04:35-04:40 UTC, BEFORE ANY OF THIS ═════════════════════════════
--
-- THE CLOCK. cron.job holds ONE row in the whole database — `wa_flush`, active = false. There is no
-- sanctions_screen_weekly job and no job for any of the four functions below. Whatever the file headers
-- say about "runs every 2 minutes" or "Mondays 03:00 UTC", pg_cron has been empty since 7 Sep.
--
-- A. THE SANCTIONS SCREEN. public.fn_sanctions_screen_tick() posts to functions/v1/sanctions_screen.
--    There was no such directory in supabase/functions and no such deployed function, so the POST was a
--    404 — and net.http_post is fire-and-forget, so the 404 landed in net._http_response where nothing
--    reads it: no exception, no retry, no finding, and the tick returns {"posted": true} regardless.
--    screening_run = 0, screening_entry = 0, supplier_screening_hit = 0. The weekly screening the estate
--    believes is running has NEVER run, not once, since it was built on 6 Sep.
--    NOT REDUNDANT WITH fn_supplier_sanctions_screen, repaired last night in PR #739: that routine
--    matches suppliers against rows in screening_entry, and only the edge function can PRODUCE those
--    rows — it has to fetch a 2.1 MB XML file and a legacy Excel workbook and parse them, and Postgres
--    can do neither (net.http_post's response is not readable from the calling statement, and there is
--    no XML or XLS parser in the database). It was never built and never renamed. supabase/functions/
--    sanctions_screen now exists; its clock is the `sanctions` gate below.
--
-- B1. doc_extract — 12 documents in status pending, oldest 18 Sep 04:34, none of them extractable. The
--     newest document with a non-null `extracted` was processed 12 Aug. agent_runs holds 2 rows for it,
--     the last 9 Sep 07:10. It is the ONLY writer of documents.extracted and the only OCR path, and
--     customer_documents reads and displays that column. Every document uploaded since pg_cron emptied
--     has been silently unread.
-- B2. email_triage — inbound_messages: 20 rows, 18 with triaged_at null. The DRAINABLE backlog is 0:
--     email_triage selects `needs_review = true and triaged_at is null and replied_at is null`, and none
--     of the 18 has needs_review = true. fn_inbox_list() counts the same predicate, so its `untriaged`
--     also reads 0 — the brief's "backlog nothing drains" is not there. The wire is built anyway, for the
--     first message that DOES need review; the gate is the predicate itself, so an empty queue costs the
--     already-existing RPC and no HTTP at all.
-- B3. send_sms — notifications holds 0 rows with channel = 'sms', queued or otherwise, against 240 rows
--     total from 7 Sep onwards. NOBODY is waiting on one. The producers are real (fn_… in
--     the_ceo_decides_every_sales_engineer_report… and the_whatsapp_number_is_confirmed… both fall back
--     to channel 'sms' when WhatsApp is not available) and send_outbox does deliberately refuse the
--     channel, so the gap is real and would bite on the first fallback. Note the OTP path is NOT this
--     one: kyc, login_otp and mobile_otp send through Twilio Verify directly and never touch this queue.
-- B4. supplier_onboard — DORMANT BY DESIGN, not wired. See its own header: it is a JWT-authenticated
--     request/response endpoint that turns a supplier's paragraph into structure. It has no queue, no
--     producer and no backlog, so there is nothing for a clock to drain; what it lacks is a front end.
--
-- ═══ THE GATES, AND WHY TWO OF THEM SHIP SHUT ══════════════════════════════════════════════════════
--
-- OPENROUTER IS ON HOLD, AND TWO OF THESE FOUR SPEND IT. doc_extract calls ai_gateway for every document
-- and email_triage calls the shared Sonnet-first ladder for every message. Wiring them to a 15-minute
-- clock without a switch would start real model spend against the founder's one standing limit. Both are
-- therefore gated on a key that DOES NOT EXIST in app_secrets:
--     doc_extract_drain_enabled      ships absent  -> the gate is SHUT, the step costs nothing
--     email_triage_enabled           ships absent  -> the gate is SHUT, the step costs nothing
-- Setting either to 'true' is the whole switch-on. Until then the pipe is built and dry, which is the
-- correct state while the limit stands — and it is one key, not a code change, when it lifts.
--
-- send_sms has NO flag: no model, and its gate is the queue itself, exactly like whatsappTick.
--
-- sanctions_screen_enabled is the third absent key, and it is there for a different reason: it must not
-- be possible to apply this file before the new edge function is deployed and have the tick post to a
-- 404 every 15 minutes. Deploy first, apply second, set the key third.
--
-- READ THE POLARITY. email_cron and wa_templates are due while their flag is NOT 'true' — they report and
-- watch for a condition that is currently absent. The three new ones are due while their flag IS 'true' —
-- they act, and acting costs money or reaches a third party. A MISSING key is "off" in both directions.

-- THE ONE INDEX THIS ADDS, AND WHY ONLY THIS ONE. The doc_extract gate reads
-- `status in ('pending','error')`, and the only index on the column is idx_documents_status, which is
-- PARTIAL on `status = 'pending'` — so the `error` half falls through to a sequential scan. documents
-- holds 22 live rows but its ids are already in the 62,000s, i.e. the table churns hard, and this gate
-- runs 96 times a day for ever. The other three gates read tables of 20-240 rows that no index would beat
-- today; adding indexes there would be paperwork, not performance, and they are listed here so the next
-- reader knows they were considered rather than missed: notifications(channel,status),
-- inbound_messages(needs_review,triaged_at,replied_at), screening_run(source,fetched_at) — revisit when
-- any of them passes a few thousand rows.
create index if not exists documents_drainable_idx on public.documents (id) where status in ('pending', 'error');

create or replace function public.fn_resilience_orphan_steps_due()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    -- coalesce, not '<>': a missing row must read as "not enabled", which is the state that needs
    -- reporting. A gate that opens only when a key is present and wrong is a gate that a deleted key
    -- switches off silently.
    'email_cron',   coalesce((select value from public.app_secrets where key = 'email_enabled'), '') is distinct from 'true',
    'wa_templates', coalesce((select value from public.app_secrets where key = 'wa_templates_ready'), '') is distinct from 'true',

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
-- CREATE OR REPLACE preserves the ACL, so this is a no-op re-assertion of PR #742's revoke rather than a
-- new grant being taken back. It is repeated because a future reader must not have to go and check.
revoke execute on function public.fn_resilience_orphan_steps_due() from public, anon, authenticated;

-- THE NEW FUNCTION NAMES ITS SEAT BEFORE IT IS DEPLOYED. every_deployed_function_has_an_owner.mjs reads
-- function_owner against what is live, so a function deployed without a row here is a new orphan the
-- moment it lands. sales_engineer, for the same reason kyc and compliance_archive sit there: this is
-- supplier verification. It is not the seat that DECIDES a hit — fn_supplier_sanctions_screen opens the
-- confirm/reject task on the ceo, because a confirmed hit bans a supplier and every approval is the
-- CEO's, and the hold on outreach on the sales_engineer (PR #739). Owning the screen is not deciding it.
insert into public.function_owner (function_slug, owner, note) values
  ('sanctions_screen', 'sales_engineer',
   'Downloads the UN consolidated list and the UAE local terrorist list weekly, records a screening_run '
   'per source and hands the run ids to fn_supplier_sanctions_screen, which screens registered suppliers. '
   'Opens tasks; decides nothing and removes nobody. Driven by resilience_ping''s orphans step.')
on conflict (function_slug) do update
  set owner = excluded.owner, note = excluded.note, recorded_at = now();

-- THE OLD TICK IS KEPT, AND STOPS BEING MISTAKEN FOR THE CLOCK. fn_sanctions_screen_tick() is not
-- dropped — the founder's rule is that surfaces are held — but nothing calls it, and a future reader
-- finding a routine that posts to an edge function must not have to work out whether it is the schedule.
-- The decision gets a home in the database, next to the thing it is about, rather than only in a file.
comment on function public.fn_sanctions_screen_tick() is
  'SUPERSEDED AS A CLOCK, 18 Sep 2026. This posts to functions/v1/sanctions_screen with net.http_post, '
  'which is fire-and-forget: nothing reads net._http_response, so it cannot tell a 200 from a 404 and its '
  '{"posted":true} is a claim, not a measurement. It was scheduled by pg_cron job sanctions_screen_weekly, '
  'and pg_cron has been empty since 7 Sep 2026 — so it has not run at all, and screening_run held 0 rows. '
  'The weekly screen now runs from resilience_ping''s `orphans` step, gated by '
  'fn_resilience_orphan_steps_due()->>''sanctions''. This routine is RETAINED as the manual one-off kick '
  '(service_role only). Do not re-schedule it; change the gate instead.';

-- ── PROBE 1: THE COST, BECAUSE A STEP ADDED TO A 110 s BUDGET MUST ARRIVE WITH A NUMBER ─────────────
-- This file defines a routine, so the probes end in `raise notice`. A `raise exception` at the top level
-- would roll the CREATE back with it and the apply would report success over nothing.
do $cost$
declare t0 timestamptz; v jsonb; n int := 0;
begin
  perform public.fn_resilience_orphan_steps_due();   -- warm, so the number is the query and not the plan
  t0 := clock_timestamp();
  for i in 1..20 loop select public.fn_resilience_orphan_steps_due() into v; n := n + 1; end loop;
  raise notice 'fn_resilience_orphan_steps_due: % calls in % (mean %)',
    n, clock_timestamp() - t0, (clock_timestamp() - t0) / n;
  raise notice 'gates now: %', v;
end $cost$;

-- ── PROBE 2: THE GATES ACTUALLY FLIP, AND NOTHING THE PROBE TOUCHES CAN REACH A PERSON ──────────────
-- The inner BEGIN…EXCEPTION is a real subtransaction: the raise rolls every write back and the handler
-- lets the file continue, so the numbers come out and nothing is left behind. It writes ONLY to
-- app_secrets and screening_run — configuration and a list-fetch record. Neither table has a recipient
-- column, no dispatcher reads either of them, and so this probe is incapable of addressing anybody,
-- rather than merely tidying up after itself.
--
-- WHY IT DOES NOT PROBE THE send_sms GATE. A queued notification addressed to a ZZ DEMO recipient cannot
-- prove that gate: zzzz_notifications_demo_capture rewrites any demo-addressed row to status
-- 'suppressed' on insert (measured — the row comes back channel 'sms', status 'suppressed'), so the
-- EXISTS never sees it. That is the demo guard working exactly as intended, and the alternative — a row
-- addressed to a real number — is the thing this estate's rules forbid. The send_sms gate is therefore
-- asserted by MEASUREMENT instead: 0 rows with channel 'sms' in 240 notifications, so it reads false
-- today, and its predicate is the same two columns whatsappTick has drained on since 7 Sep.
do $probe$
declare v0 jsonb; v1 jsonb; v2 jsonb; v3 jsonb; v_docs int; v_mail int;
begin
  begin
    select public.fn_resilience_orphan_steps_due() into v0;
    select count(*) into v_docs from public.documents where status in ('pending','error') and coalesce(attempts,0) < 3;
    select count(*) into v_mail from public.inbound_messages where needs_review and triaged_at is null and replied_at is null;

    insert into public.app_secrets (key, value) values
      ('doc_extract_drain_enabled', 'true'), ('email_triage_enabled', 'true'), ('sanctions_screen_enabled', 'true')
    on conflict (key) do update set value = excluded.value;
    select public.fn_resilience_orphan_steps_due() into v1;

    -- and the weekly back-off, PER SOURCE: recording ONE of the two lists must NOT shut the gate, because
    -- the other list has still not been fetched. Only both shut it. This is the assertion that fails if
    -- the ungrouped version of the predicate ever comes back.
    insert into public.screening_run (source, source_url, status, entries, note)
    values ('un_consolidated', 'about:blank', 'ok', 0, 'ZZ DEMO — proves the per-source back-off; rolled back.');
    select public.fn_resilience_orphan_steps_due() into v2;
    insert into public.screening_run (source, source_url, status, entries, note)
    values ('uae_local_terrorist_list', 'about:blank', 'ok', 0, 'ZZ DEMO — proves the per-source back-off; rolled back.');
    select public.fn_resilience_orphan_steps_due() into v3;

    raise exception 'QD_PROBE_ROLLBACK flags off -> doc_extract=% email_triage=% sanctions=% | flags on -> doc_extract=% (% drainable docs) email_triage=% (% drainable mails) sanctions=% | after UN only -> sanctions=% (must still be true) | after both -> sanctions=% (must be false)',
      v0->>'doc_extract', v0->>'email_triage', v0->>'sanctions',
      v1->>'doc_extract', v_docs, v1->>'email_triage', v_mail, v1->>'sanctions',
      v2->>'sanctions', v3->>'sanctions';
  exception when others then
    if sqlerrm not like 'QD_PROBE_ROLLBACK%' then raise; end if;
    raise notice '%', sqlerrm;
  end;
end $probe$;
