-- it_engineer, 24 Sep 2026: each sending day, one seed invitation goes to the founder's Gmail and his
-- Microsoft 365 mailbox before the batch. Which folder it lands in decides whether the day's batch goes.
--
-- MEASURED (24 Sep 2026, production, read-only):
--   * The batch is not a pg_cron job. cron.job holds one row (wa_flush, active=false), because every cron job
--     was deleted on the founder's instruction of 7 Sep. The heartbeat (resilience_ping, about every 15 min)
--     runs fn_sales_engineer_supplier_outreach_tick. From 09:00 Dubai, once per Dubai day, the tick calls
--     fn_invite_ramp and enqueue_supplier_invites. The enqueue spreads the day over notifications.not_before
--     from invite_warmup.window_start_hour (10, so 10:00 Dubai = 06:00 UTC) to window_end_hour (17).
--     A pg_cron schedule would never fire, and reactivating pg_cron would restart machinery the founder
--     removed. So this check runs on the same heartbeat, INSIDE the existing itintegrations step (it_engineer,
--     resilience_step every 15 min, measured 24 Sep). No new resilience_step row: the step list and the schedule
--     stay equal whether this file is applied or not (scripts/checks/every_tick_step_is_scheduled.mjs), as #961 does.
--   * The sending-day calendar is the one the batch reads. enqueue_supplier_invites holds on the Dubai
--     weekend (isodow 6/7) and on a company_calendar 'public_holiday' row covering the day. fn_is_working_day
--     reads a different table (public_holidays), and the batch does not read it. The check runs on exactly
--     the batch's days, so a day the batch sends can never be a day the check skipped.
--   * 13 supplier_invite_seed rows exist. They are sent through the real path by scripts/invitation_inbox_check.mjs
--     (to_role supplier, the live From, Reply-To and frame, never counted against the invitation cap).
--     The script only polled until the send and never read the folder back. The one Gmail reading
--     (24 Sep 11:31) was INBOX. No placement was stored anywhere.
--   * The live From is info@quotesdone.com (app_secrets.email_from_supplier). PR #963 adds an invitation lane:
--     with app_secrets.invite_lane_enabled='true', send_outbox sends supplier_invite AND supplier_invite_seed from
--     invite_lane_from (send_outbox/invite_lane.ts). Neither key exists on production today (the lane is off).
--     Each row records the EFFECTIVE sender it tested, and a pass only clears the batch while it is unchanged.
--   * The campaign pause already exists: fn_invite_same_day_brake (#943) sets invite_enabled=false, cancels the
--     queued supplier_invite rows and opens it_watch_finding. PR #961
--     (the_it_engineer_reads_gmail_postmaster_daily_and_a_spam_spike_stops_the_invitations.sql) moves it into
--     fn_invite_campaign_pause(source, why, evidence, counts) and has the brake call it. THAT IS CANONICAL: this
--     file carries #961's fn_invite_campaign_pause and fn_invite_same_day_brake blocks BYTE-FOR-BYTE (commit
--     f444d565), so whichever of the two files applies second is a no-op on them, and no second overload exists.
--   * Credentials: app_secrets holds google_oauth_client_id / google_oauth_client_secret (the YouTube
--     connection's Google client) and no Gmail refresh token, no Microsoft Graph key. vault.secrets is
--     empty. Until they are stored, the reader cannot see a folder, the verdict is 'unread' and the day
--     does not send (fail closed).
--
-- WHAT THIS CHANGES
--   1. public.invite_placement_check: one row per Dubai sending day. It records the per-run token, the effective
--      From tested, both seed addresses (a CHECK constraint fixes each one, so no other address can be stored),
--      the folder each landed in, the reader's evidence and the verdict.
--   2. fn_invite_placement_due(now): the heartbeat's entry point. From 90 min before the window opens (04:30 UTC)
--      on a sending day with the campaign on, it queues ONE supplier_invite_seed to each seed inbox. The subject is
--      the live subject plus "(ref <token>)" and the body is the live body for a ZZ DEMO company. Later it answers
--      'read' until a verdict, and settles the day at the read cutoff (the window + 2 h, 08:00 UTC).
--   3. fn_invite_placement_record(day, gmail, outlook): the folder readings from
--      supabase/functions/_shared/inbox_placement.ts (Gmail labelIds, Graph parentFolderId; the owner's Sent and
--      Drafts copies and any other sender's mail excluded), then a settle.
--   4. fn_invite_placement_settle(day, now): verdict inbox (both in Inbox), spam (either in spam/junk), elsewhere
--      (trash or another folder), and, at the cutoff without both in Inbox: not_sent, unread or not_found.
--      FOUNDER RULING, ledger 1001 (28 Sep 2026): a junk placement must NOT pause the batch. spam and elsewhere
--      are diagnosed instead: the reader returns the provider's reasons (Gmail labels + Authentication-Results;
--      Microsoft X-Forefront-Antispam-Report SCL/SFV/CAT + Authentication-Results), the finding carries them
--      with the sender lane, a deliverability.inbox_placement handoff asks the marketing seat to fix the cause,
--      and the day's batch keeps sending. The #943 hard brake (bounce/complaint spike, fn_invite_same_day_brake)
--      is the ONLY automatic pause. not_sent, unread and not_found are our side failing to measure and still hold
--      the day without touching invite_enabled. Every non-inbox verdict files the it_engineer finding
--      deliverability:inbox_placement (fn_invite_placement_finding -> fn_it_engineer_finding_upsert, the #935
--      door), once per day and verdict. An inbox verdict closes it and completes the open marketing handoff.
--   5. fn_invite_placement_gate(day, now): 'pass' for a measured placement (inbox, spam, elsewhere) under the current effective sender
--      (fn_invite_placement_sender: the #963 invitation lane when invite_lane_enabled='true', else
--      email_from_supplier). 'wait' until a verdict or the cutoff. 'fail' otherwise. A day with no check is
--      'fail:no_check', filed as the same finding on an open day. enqueue_supplier_invites refuses to queue without
--      'pass'. In the outreach tick only the batch waits; reminders and the 24-hour clock run on time.
--   6. No schedule row. resilience_ping's itintegrations step (every 15 min) calls placementTick. If this file is
--      applied before that code is deployed, nothing calls fn_invite_placement_due, no seed is queued, the gate
--      answers 'wait' until 08:00 UTC and then 'fail:no_check': the batch is held, the finding is filed and the
--      campaign is not paused. If the code is deployed first, the missing routine is recorded as "skipped: schema
--      not applied".
--
-- WHAT THIS DELIBERATELY DOES NOT CHANGE
--   * The founder's go. invite_enabled and supplier_outreach_golive are only ever set to false here, never
--     true. As with the brake, resuming after a failed check is a deliberate act by hand.
--   * The invitation's cap, window, ramp, bounce brake and candidate selection. The two redefined routines
--     are the live bodies of 24 Sep with one gate each, marked PLACEMENT GATE.
--   * The seed path. It is still a supplier_invite_seed row through send_outbox, not a supplier_invite, so it
--     never spends invite_daily_cap. It does count toward the all-mail daily_send_cap (2 of 80).
--   * No model is called. Classification is deterministic code.
--
-- Prevented by: scripts/checks/the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.test.mjs
--               supabase/functions/_shared/inbox_placement.test.ts

-- ── 1. the record ───────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.invite_placement_check (
  dubai_day               date primary key,
  token                   text not null unique check (token ~ '^QD[0-9A-F]{10}$'),
  from_address            text not null,
  subject                 text not null,
  -- THE ALLOWLIST IS THE SCHEMA. Exact addresses, never a domain: a colleague at the same company is still
  -- a real person (scripts/invitation_inbox_check.mjs FOUNDER_INBOXES). management@quotesdone.com is left
  -- out on purpose: it is our own Microsoft 365 tenant, so a mail from info@quotesdone.com is internal
  -- there and says nothing about an outside mailbox. doratajewelries.com is a separate tenant.
  gmail_to                text not null check (gmail_to = 'ahmadmhdnabilalzain@gmail.com'),
  outlook_to              text not null check (outlook_to = 'management@doratajewelries.com'),
  gmail_notification_id   bigint,
  outlook_notification_id bigint,
  queued_at               timestamptz not null default now(),
  gmail_folder            text check (gmail_folder in ('inbox', 'spam', 'trash', 'other', 'not_found')),
  outlook_folder          text check (outlook_folder in ('inbox', 'spam', 'trash', 'other', 'not_found')),
  gmail_detail            jsonb not null default '{}'::jsonb,
  outlook_detail          jsonb not null default '{}'::jsonb,
  reads                   integer not null default 0,
  last_read_at            timestamptz,
  verdict                 text not null default 'pending'
                          check (verdict in ('pending', 'inbox', 'spam', 'elsewhere', 'not_found', 'unread', 'not_sent')),
  decided_at              timestamptz,
  paused                  boolean not null default false,
  note                    text
);
comment on table public.invite_placement_check is
  'it_engineer: one seed invitation per Dubai sending day to the founder''s Gmail and Microsoft 365 inbox; the folder each landed in and the verdict that gates the day''s supplier invitation batch (the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.sql).';

alter table public.invite_placement_check enable row level security;
drop policy if exists invite_placement_check_service_role_only on public.invite_placement_check;
create policy invite_placement_check_service_role_only on public.invite_placement_check
  as permissive for all to public using (false) with check (false);
revoke all on public.invite_placement_check from anon, authenticated;

-- ── 2. the one pause and the brake: BYTE-FOR-BYTE the blocks of PR #961 (commit f444d565) ──────────────
-- Copied verbatim from the_it_engineer_reads_gmail_postmaster_daily_and_a_spam_spike_stops_the_invitations.sql, so
-- whichever of the two files applies second re-creates identical definitions (a no-op on them). The check
-- the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.test.mjs fails if they ever differ.

-- ── 2. THE ONE PAUSE (moved out of fn_invite_same_day_brake, PR #943) ───────────────────────────────
create or replace function public.fn_invite_campaign_pause(p_source text, p_why text, p_evidence jsonb, p_counts jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_cancelled int;
begin
  if coalesce(btrim(p_source), '') = '' or coalesce(btrim(p_why), '') = '' then
    raise exception 'fn_invite_campaign_pause(source, why, evidence, counts): a source and a reason are required';
  end if;
  update app_secrets set value = 'false' where key = 'invite_enabled';
  update notifications set status = 'cancelled'
   where type = 'supplier_invite' and status = 'queued';
  get diagnostics v_cancelled = row_count;

  insert into it_watch_finding(detector_key, detector, subject, state, severity, title, evidence)
  values ('deliverability:supplier_invite', 'deliverability', 'supplier_invite', 'paused', 'high',
          'Supplier invitations auto-paused: ' || p_why,
          coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object('cancelled_queued', v_cancelled, 'paused_by', p_source,
                             'resume', 'set app_secrets.invite_enabled=true after reading the bounces/complaints'))
  on conflict (detector_key) do update
     set state = excluded.state, severity = excluded.severity, title = excluded.title, evidence = excluded.evidence,
         last_seen_at = now(), seen_count = it_watch_finding.seen_count + 1, status = 'open', resolved_at = null;

  insert into agent_runs(agent, status, counts, note, finished_at)
  values (p_source, 'error', coalesce(p_counts, '{}'::jsonb) || jsonb_build_object('cancelled_queued', v_cancelled),
          'PAUSED: ' || p_why || '; invite_enabled=false, ' || v_cancelled || ' queued invitation(s) cancelled, it_engineer finding opened.', now());
  return jsonb_build_object('paused', true, 'cancelled_queued', v_cancelled, 'source', p_source);
end
$fn$;
revoke execute on function public.fn_invite_campaign_pause(text, text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.fn_invite_campaign_pause(text, text, jsonb, jsonb) to service_role;

-- The brake keeps its thresholds and its decision exactly; only the pause it used to write inline is now the call.
create or replace function public.fn_invite_same_day_brake()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  c jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_br_max numeric := coalesce((c->>'same_day_pause_bounce_rate')::numeric, 0.05);
  v_b_min  int     := coalesce((c->>'same_day_pause_min_bounces')::int, 3);
  v_cr_max numeric := coalesce((c->>'pause_complaint_rate')::numeric, 0.003);
  v_c_min  int     := coalesce((c->>'same_day_pause_min_complaints')::int, 1);
  v_day date := (now() at time zone 'Asia/Dubai')::date;
  v_sent int; v_b int; v_c int; v_why text;
begin
  if coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') <> 'true' then
    return null;  -- already stopped; nothing more to stop
  end if;

  select count(*),
         count(*) filter (where invite_status = 'bounced'),
         count(*) filter (where invite_status = 'complained')
    into v_sent, v_b, v_c
    from leads
   where invited_at is not null and (invited_at at time zone 'Asia/Dubai')::date = v_day;

  if v_c >= v_c_min and v_c::numeric / greatest(v_sent, 1) >= v_cr_max then
    v_why := v_c || ' spam complaint(s) on ' || v_sent || ' invitation(s) today';
  elsif v_b >= v_b_min and v_b::numeric / greatest(v_sent, 1) >= v_br_max then
    v_why := v_b || ' bounce(s) on ' || v_sent || ' invitation(s) today (' || round(v_b * 100.0 / greatest(v_sent, 1), 1) || '%)';
  else
    return null;
  end if;

  perform public.fn_invite_campaign_pause('invite_same_day_brake', v_why,
    jsonb_build_object('dubai_day', v_day, 'sent', v_sent, 'bounced', v_b, 'complained', v_c),
    jsonb_build_object('sent_today', v_sent, 'bounced_today', v_b, 'complained_today', v_c));
  return null;
end
$fn$;
revoke execute on function public.fn_invite_same_day_brake() from public, anon, authenticated;

-- ── 3. when and from whom: the batch's own window, calendar and sender ──────────────────────────────────
-- The window opens at invite_warmup.window_start_hour Dubai (10:00 = 06:00 UTC): the deadline. The seed is
-- queued from 90 minutes before it (04:30 UTC), so a deferred or slow heartbeat still has several beats to read
-- it before 06:00. Reading goes on after 06:00 until the cutoff (deadline + 2 h, 08:00 UTC). The batch waits
-- until a verdict exists, because a late pass can still send inside the day's window (to 17:00 Dubai).
create or replace function public.fn_invite_placement_deadline(p_day date)
returns timestamptz
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select (p_day + make_interval(hours => coalesce(
            (select (nullif(value,'')::jsonb ->> 'window_start_hour')::int from app_secrets where key = 'invite_warmup'), 10)))
         at time zone 'Asia/Dubai';
$fn$;
revoke execute on function public.fn_invite_placement_deadline(date) from public, anon, authenticated;

create or replace function public.fn_invite_placement_cutoff(p_day date)
returns timestamptz
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select public.fn_invite_placement_deadline(p_day) + interval '2 hours';
$fn$;
revoke execute on function public.fn_invite_placement_cutoff(date) from public, anon, authenticated;

-- THE EFFECTIVE SENDER (review of #966). With the #963 invitation lane on, send_outbox sends invitations AND their
-- seed from app_secrets.invite_lane_from (invite_lane.ts senderFor); otherwise from email_from_supplier. The keys
-- are read defensively: #963 may not be applied, and a missing key is the lane off. The check records this value
-- and the gate compares it, so switching the lane on or off, or changing either From, makes an earlier pass stale.
create or replace function public.fn_invite_placement_sender()
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select case
    when coalesce((select lower(btrim(value)) from public.app_secrets where key = 'invite_lane_enabled'), 'false') = 'true'
     and coalesce((select btrim(value) from public.app_secrets where key = 'invite_lane_from'), '') <> ''
      then (select btrim(value) from public.app_secrets where key = 'invite_lane_from')
    else coalesce(nullif((select btrim(value) from public.app_secrets where key = 'email_from_supplier'), ''),
                  'QuotesDone <supplier@quotesdone.com>')
  end;
$fn$;
revoke execute on function public.fn_invite_placement_sender() from public, anon, authenticated;

-- NULL = the batch will run today; otherwise why it will not. Same predicates as enqueue_supplier_invites.
create or replace function public.fn_invite_placement_day_closed(p_now timestamptz default now())
returns text
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select case
    when extract(isodow from (p_now at time zone 'Asia/Dubai')) in (6, 7) then 'the UAE weekend'
    when exists (select 1 from public.company_calendar c
                  where c.kind = 'public_holiday'
                    and (p_now at time zone 'Asia/Dubai')::date between c.starts_on and coalesce(c.ends_on, c.starts_on))
      then 'a company_calendar public holiday'
    when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
    when coalesce((select lower(btrim(value)) from public.app_secrets where key = 'invite_enabled'), 'false') <> 'true'
      then 'invite_enabled is false'
  end;
$fn$;
revoke execute on function public.fn_invite_placement_day_closed(timestamptz) from public, anon, authenticated;

-- ── 4. the verdict, and what a failed one does ──────────────────────────────────────────────────────────
-- The it_engineer finding, the #935 door. One key; each Dubai day is filed once (a repeat call the same day
-- for the same verdict is not a new sighting), so a held day is visible without being counted on every beat.
create or replace function public.fn_invite_placement_finding(p_day date, p_verdict text, p_why text, p_evidence jsonb)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_key constant text := 'deliverability:inbox_placement';
begin
  if exists (select 1 from public.it_engineer_finding
              where issue_key = v_key and closed_at is null
                and evidence ->> 'dubai_day' = p_day::text and evidence ->> 'verdict' = p_verdict) then
    return;
  end if;
  perform public.fn_it_engineer_finding_upsert(v_key,
    left(case when p_verdict in ('spam', 'elsewhere') then 'Supplier invitation seed misplaced (batch still sending): '
              else 'Supplier invitations held: ' end || p_why, 300),
    'supplier invitation inbox placement: the daily seed to the Gmail and Microsoft 365 seed inboxes',
    'customer_facing', 1,
    coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object('dubai_day', p_day, 'verdict', p_verdict),
    array['the seed goes through the real path: send_outbox, the effective From (invitation lane or email_from_supplier), Reply-To and frame'],
    case p_verdict
      when 'unread' then array['whether the Gmail / Microsoft Graph credentials in app_secrets are present and still consented',
                               'whether the itintegrations heartbeat step ran between 04:30 and 08:00 UTC']
      when 'not_sent' then array['why send_outbox did not send the seed (email_enabled, supplier_emails_enabled, the daily cap)',
                                 'invite_lane_domain_unverified: with the invitation lane on, send_outbox holds the seed while the lane''s domain is not verified in Resend']
      when 'no_check' then array['whether the itintegrations heartbeat step ran between 04:30 and 08:00 UTC, or resilience_ping is deployed without the placement code',
                                 'invite_lane_domain_unverified, if the lane is on']
      when 'not_found' then array['whether a mailbox rule moved or deleted the seed', 'whether the seed arrived from a different From than the one recorded']
      else array['which content, sender or domain signal the mailbox provider acted on'] end,
    'it_engineer');
end
$fn$;
revoke execute on function public.fn_invite_placement_finding(date, text, text, jsonb) from public, anon, authenticated;

-- THE MARKETING HANDOFF (ledger 1001). it_engineer diagnoses, marketing owns the fix (content, sender, domain
-- reputation). The handler records that marketing is on it; it_engineer closes the handoff itself when a later
-- seed lands in both Inboxes (originator_closes), so a fix is proved by a placement, never by a note.
insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
  ('deliverability.inbox_placement', 'it_engineer', 'marketing',
   'The daily seed invitation landed outside the Inbox of a seed mailbox. The payload carries the provider''s diagnosis (Gmail labels and Authentication-Results; Microsoft SCL/SFV/CAT and Authentication-Results) and the sender lane. Marketing fixes the cause; the batch keeps sending; it_engineer closes this when a seed lands in both Inboxes.',
   'fn_marketing_takes_the_inbox_placement_fix', interval '1 day', true,
   'scripts/sql/the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.sql')
on conflict (type, from_seat, to_seat) do update
  set meaning = excluded.meaning, handler = excluded.handler, reply_within = excluded.reply_within,
      originator_closes = excluded.originator_closes, owner_file = excluded.owner_file;

create or replace function public.fn_marketing_takes_the_inbox_placement_fix(p_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object('waiting', 'marketing to fix the cause the diagnosis names ('
           || coalesce(a.detail ->> 'verdict', 'misplaced') || ' on ' || coalesce(a.detail ->> 'dubai_day', a.target_id)
           || '); it_engineer closes this when a seed lands in both Inboxes')
    from public.agent_actions a where a.id = p_id
$fn$;
revoke execute on function public.fn_marketing_takes_the_inbox_placement_fix(bigint) from public, anon, authenticated;

-- NO PAUSE ON A PLACEMENT (founder ruling, ledger 1001). spam or elsewhere is diagnosed, filed, handed to
-- marketing, and the day's batch sends; the #943 brake stays the only automatic pause. not_sent / unread /
-- not_found at the cutoff is OUR side failing to measure: the day is held (the gate fails) and the finding is
-- filed, but invite_enabled is not touched, so tomorrow's check runs on its own.
create or replace function public.fn_invite_placement_settle(p_day date, p_now timestamptz default now())
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  r public.invite_placement_check;
  v text; v_sent_g text; v_sent_o text; v_why text; v_ev jsonb; v_lane text; v_handoff bigint; h record;
begin
  select * into r from public.invite_placement_check where dubai_day = p_day for update;
  if r.dubai_day is null or r.verdict <> 'pending' then return r.verdict; end if;

  if 'spam' in (r.gmail_folder, r.outlook_folder) then v := 'spam';
  elsif r.gmail_folder in ('trash', 'other') or r.outlook_folder in ('trash', 'other') then v := 'elsewhere';
  elsif r.gmail_folder = 'inbox' and r.outlook_folder = 'inbox' then v := 'inbox';
  elsif p_now >= public.fn_invite_placement_cutoff(p_day) then
    select status into v_sent_g from public.notifications where id = r.gmail_notification_id;
    select status into v_sent_o from public.notifications where id = r.outlook_notification_id;
    v := case when coalesce(v_sent_g, '') <> 'sent' or coalesce(v_sent_o, '') <> 'sent' then 'not_sent'
              when r.gmail_folder is null or r.outlook_folder is null then 'unread'
              else 'not_found' end;
  else
    return 'pending';
  end if;

  if v = 'inbox' then
    update public.invite_placement_check set verdict = v, decided_at = p_now where dubai_day = p_day;
    perform public.fn_it_engineer_finding_close('deliverability:inbox_placement',
      'the seed of ' || p_day || ' landed in the Inbox of both seed mailboxes (token ' || r.token || ')');
    -- The fix is proved by a placement: it_engineer closes marketing's open placement handoffs.
    for h in select a.id from public.agent_actions a
              where a.kind = 'handoff' and a.agent = 'marketing' and a.status <> 'done'
                and a.detail ->> 'type' = 'deliverability.inbox_placement' and a.detail ->> 'from' = 'it_engineer'
    loop
      perform set_config('qd.handoff_closer', 'it_engineer', true);
      perform public.fn_seat_handoff_complete(h.id, jsonb_build_object('verified_by', 'it_engineer', 'verified_at', now(),
        'proof', 'the seed of ' || p_day || ' landed in the Inbox of both seed mailboxes'));
      perform set_config('qd.handoff_closer', '', true);
    end loop;
    insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('it_engineer', 'ok', jsonb_build_object('job', 'inbox_placement', 'dubai_day', p_day, 'verdict', v),
            'Inbox placement ' || p_day || ': Gmail inbox, Outlook inbox; the batch may send.', now(), now());
    return v;
  end if;

  v_why := 'the inbox placement seed of ' || p_day || ' '
    || case v when 'spam' then 'landed in spam/junk'
              when 'elsewhere' then 'did not land in the Inbox'
              when 'not_sent' then 'was not sent by the read cutoff'
              when 'unread' then 'could not be read back from a seed mailbox'
              else 'was not found in a seed mailbox' end
    || ' (Gmail ' || coalesce(r.gmail_folder, 'unread') || ', Outlook ' || coalesce(r.outlook_folder, 'unread') || ')';
  v_lane := case when coalesce((select lower(btrim(value)) from public.app_secrets where key = 'invite_lane_enabled'), '') = 'true'
                 then 'invitation_lane' else 'email_from_supplier' end;
  v_ev := jsonb_build_object('token', r.token, 'from', r.from_address, 'sender_lane', v_lane, 'subject', r.subject,
            'diagnosis', jsonb_build_object('gmail', coalesce(r.gmail_detail -> 'messages', '[]'::jsonb),
                                            'outlook', coalesce(r.outlook_detail -> 'messages', '[]'::jsonb)),
            'gmail', jsonb_build_object('to', r.gmail_to, 'folder', r.gmail_folder, 'detail', r.gmail_detail,
                                        'notification_id', r.gmail_notification_id, 'status', v_sent_g),
            'outlook', jsonb_build_object('to', r.outlook_to, 'folder', r.outlook_folder, 'detail', r.outlook_detail,
                                          'notification_id', r.outlook_notification_id, 'status', v_sent_o),
            'reads', r.reads);
  update public.invite_placement_check set verdict = v, decided_at = p_now, paused = false where dubai_day = p_day;
  perform public.fn_invite_placement_finding(p_day, v, v_why, v_ev);
  if v in ('spam', 'elsewhere') then
    -- A provider's placement: diagnose and hand the cause to marketing; the batch sends (ledger 1001).
    v_handoff := public.fn_seat_handoff('it_engineer', 'marketing', 'deliverability.inbox_placement',
      'invite_placement_check', p_day::text, v_ev || jsonb_build_object('dubai_day', p_day, 'verdict', v, 'why', v_why));
    insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('it_engineer', 'warn', jsonb_build_object('job', 'inbox_placement', 'dubai_day', p_day, 'verdict', v, 'paused', false,
                                                      'handoff_id', v_handoff, 'sender_lane', v_lane),
            'MISPLACED: ' || v_why || '; the day''s batch still sends, diagnosis filed in deliverability:inbox_placement, marketing handoff ' || v_handoff || ' opened.', now(), now());
  else
    insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('it_engineer', 'warn', jsonb_build_object('job', 'inbox_placement', 'dubai_day', p_day, 'verdict', v, 'paused', false),
            'HELD: ' || v_why || '; the day''s batch does not go, invite_enabled untouched, finding deliverability:inbox_placement filed.', now(), now());
  end if;
  return v;
end
$fn$;
revoke execute on function public.fn_invite_placement_settle(date, timestamptz) from public, anon, authenticated;

-- ── 5. the heartbeat's entry point: queue the seed, ask for a reading, settle at the cutoff ──────────────
-- What it returns goes to _shared/inbox_placement.ts only; placementTick passes the action, day, verdict and
-- reason on to resilience_ping's public answer, never the token, the From or the notification ids.
create or replace function public.fn_invite_placement_due(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_day date := (p_now at time zone 'Asia/Dubai')::date;
  v_deadline timestamptz := public.fn_invite_placement_deadline(v_day);
  v_cutoff timestamptz := public.fn_invite_placement_cutoff(v_day);
  r public.invite_placement_check;
  v_closed text; v_token text; v_subject text; v_body text; v_site text; v_from text;
  v_g bigint; v_o bigint; v_sg text; v_so text;
begin
  select * into r from public.invite_placement_check where dubai_day = v_day;

  if r.dubai_day is null then
    -- Queued from 04:30 UTC; not later than 30 minutes before the cutoff, which leaves beats to read it.
    if p_now < v_deadline - interval '90 minutes' or p_now >= v_cutoff - interval '30 minutes' then
      return jsonb_build_object('action', 'idle', 'dubai_day', v_day, 'reason', 'outside the seed window');
    end if;
    v_closed := public.fn_invite_placement_day_closed(p_now);
    if v_closed is not null then
      return jsonb_build_object('action', 'idle', 'dubai_day', v_day, 'reason', v_closed);
    end if;

    select coalesce(max(value) filter (where key = 'invite_subject'), ''),
           coalesce(max(value) filter (where key = 'invite_body'), ''),
           coalesce(nullif(max(value) filter (where key = 'public_site_url'), ''), 'https://quotesdone.com')
      into v_subject, v_body, v_site
      from public.app_secrets where key in ('invite_subject', 'invite_body', 'public_site_url');
    v_from := public.fn_invite_placement_sender();
    -- The body exactly as scripts/invitation_inbox_check.mjs inviteBody() fills it: a ZZ DEMO company and a
    -- zero portal token. The token goes in the subject, the one field both the Gmail and Graph APIs match
    -- without a full-text index lag.
    v_token := 'QD' || upper(substr(md5(gen_random_uuid()::text), 1, 10));
    v_subject := v_subject || ' (ref ' || v_token || ')';
    v_body := replace(replace(v_body, '{{company}}', 'ZZ DEMO Supplier'),
                      '{{link}}', v_site || '/en/portal?t=00000000-0000-0000-0000-000000000000');

    insert into public.invite_placement_check(dubai_day, token, from_address, subject, gmail_to, outlook_to, queued_at)
    values (v_day, v_token, v_from, v_subject, 'ahmadmhdnabilalzain@gmail.com', 'management@doratajewelries.com', p_now)
    returning * into r;

    insert into public.notifications (type, to_email, to_role, subject, body, lang, status, requested_by)
    values ('supplier_invite_seed', r.gmail_to, 'supplier', v_subject, v_body, 'en', 'queued', 'it_engineer')
    returning id into v_g;
    insert into public.notifications (type, to_email, to_role, subject, body, lang, status, requested_by)
    values ('supplier_invite_seed', r.outlook_to, 'supplier', v_subject, v_body, 'en', 'queued', 'it_engineer')
    returning id into v_o;
    update public.invite_placement_check set gmail_notification_id = v_g, outlook_notification_id = v_o
     where dubai_day = v_day;
    return jsonb_build_object('action', 'queued', 'dubai_day', v_day);
  end if;

  if r.verdict <> 'pending' then
    return jsonb_build_object('action', 'idle', 'dubai_day', v_day, 'verdict', r.verdict);
  end if;
  if p_now >= v_cutoff then
    return jsonb_build_object('action', 'settled', 'dubai_day', v_day, 'verdict', public.fn_invite_placement_settle(v_day, p_now));
  end if;

  select status into v_sg from public.notifications where id = r.gmail_notification_id;
  select status into v_so from public.notifications where id = r.outlook_notification_id;
  return jsonb_build_object('action', 'read', 'dubai_day', v_day, 'token', r.token, 'since', r.queued_at,
    'sender', lower(coalesce(substring(r.from_address from '<([^<>[:space:]]+@[^<>[:space:]]+)>'), btrim(r.from_address))),
    'gmail', jsonb_build_object('to', r.gmail_to, 'sent', v_sg = 'sent', 'folder', r.gmail_folder),
    'outlook', jsonb_build_object('to', r.outlook_to, 'sent', v_so = 'sent', 'folder', r.outlook_folder));
end
$fn$;
revoke execute on function public.fn_invite_placement_due(timestamptz) from public, anon, authenticated;

-- p_gmail / p_outlook: {"folder": inbox|spam|trash|other|not_found|null, "detail": {...}}. A null folder is
-- a reading that failed (no credentials, an API error, a refused mailbox) and never overwrites a folder found
-- earlier. A found folder is never downgraded to not_found by a later reading.
create or replace function public.fn_invite_placement_record(p_day date, p_gmail jsonb, p_outlook jsonb, p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_g text := nullif(p_gmail ->> 'folder', ''); v_o text := nullif(p_outlook ->> 'folder', ''); v text;
begin
  update public.invite_placement_check
     set gmail_folder   = case when v_g is null or (v_g = 'not_found' and gmail_folder is not null and gmail_folder <> 'not_found')
                               then gmail_folder else v_g end,
         outlook_folder = case when v_o is null or (v_o = 'not_found' and outlook_folder is not null and outlook_folder <> 'not_found')
                               then outlook_folder else v_o end,
         gmail_detail   = case when p_gmail is null then gmail_detail else coalesce(p_gmail -> 'detail', '{}'::jsonb) end,
         outlook_detail = case when p_outlook is null then outlook_detail else coalesce(p_outlook -> 'detail', '{}'::jsonb) end,
         reads = reads + 1, last_read_at = p_now
   where dubai_day = p_day and verdict = 'pending';
  if not found then
    return jsonb_build_object('recorded', false, 'dubai_day', p_day, 'reason', 'no pending check for this day');
  end if;
  v := public.fn_invite_placement_settle(p_day, p_now);
  return jsonb_build_object('recorded', true, 'dubai_day', p_day, 'verdict', v);
end
$fn$;
revoke execute on function public.fn_invite_placement_record(date, jsonb, jsonb, timestamptz) from public, anon, authenticated;

-- ── 6. the gate the batch asks ──────────────────────────────────────────────────────────────────────────
-- 'pass' | 'wait' | 'fail:<why>'. FAIL CLOSED: only a proven Inbox + Inbox under the current effective sender
-- passes. Before the cutoff an undecided day waits; at the cutoff every other state is 'fail'. A day on which no
-- check ran at all is 'fail:no_check', and on an open day that is filed (review of #966: a starved or undeployed
-- step must not hold the batch in silence).
create or replace function public.fn_invite_placement_gate(p_day date default null, p_now timestamptz default now())
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_day date := coalesce(p_day, (p_now at time zone 'Asia/Dubai')::date);
  r public.invite_placement_check; v text;
begin
  select * into r from public.invite_placement_check where dubai_day = v_day;
  if r.dubai_day is null then
    if p_now < public.fn_invite_placement_cutoff(v_day) then return 'wait'; end if;
    if public.fn_invite_placement_day_closed(p_now) is null then
      perform public.fn_invite_placement_finding(v_day, 'no_check',
        'no inbox placement check ran on ' || v_day || ', an open sending day',
        jsonb_build_object('checked_at', p_now, 'sender', public.fn_invite_placement_sender()));
    end if;
    return 'fail:no_check';
  end if;
  v := r.verdict;
  if v = 'pending' then
    if p_now < public.fn_invite_placement_cutoff(v_day) then return 'wait'; end if;
    v := public.fn_invite_placement_settle(v_day, p_now);
  end if;
  -- A measured placement lets the batch go, junk included (ledger 1001); only a failure to measure holds it.
  if v not in ('inbox', 'spam', 'elsewhere') then return 'fail:' || v; end if;
  if public.fn_invite_placement_sender() is distinct from r.from_address then return 'fail:from_changed'; end if;
  return 'pass';
end
$fn$;
revoke execute on function public.fn_invite_placement_gate(date, timestamptz) from public, anon, authenticated;

-- ── 7. the outreach tick: only the batch waits on the gate (live body of 24 Sep; PLACEMENT GATE marks it) ─
-- Review of #966: the first version returned early while the gate said 'wait', which also delayed the
-- registration reminders and the 24-hour clock by up to an hour. Now the tick's daily work runs on its first
-- beat from 09:00 Dubai exactly as before, and only the batch (ramp + enqueue) waits. A later beat that finds
-- the daily work done and the batch still owed runs the batch alone, recorded as job 'supplier_outreach_batch'.
create or replace function public.fn_sales_engineer_supplier_outreach_tick(p_force boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_now_dxb timestamp := now() at time zone 'Asia/Dubai';
  v_go boolean; v_weekend boolean; v_invited int; r record; s jsonb; v_cap int;
  v_due int := 0; v_sent int := 0; v_failed jsonb := '[]'::jsonb; v_clock jsonb; v_out jsonb; v_why text;
  v_gate text; v_daily_done boolean; v_batch_done boolean; v_batch_why text; v_batch_wait boolean := false;
begin
  select exists (select 1 from public.agent_runs a
                  where a.agent = 'sales_engineer' and a.counts->>'job' = 'supplier_outreach'
                    and a.started_at > now() - interval '1 day'
                    and (a.started_at at time zone 'Asia/Dubai')::date = v_now_dxb::date),
         exists (select 1 from public.agent_runs a
                  where a.agent = 'sales_engineer'
                    and ((a.counts->>'job' = 'supplier_outreach' and coalesce(a.counts->>'batch_waiting', 'false') <> 'true')
                         or a.counts->>'job' = 'supplier_outreach_batch')
                    and a.started_at > now() - interval '1 day'
                    and (a.started_at at time zone 'Asia/Dubai')::date = v_now_dxb::date)
    into v_daily_done, v_batch_done;
  if not p_force then
    if extract(hour from v_now_dxb) < 9 then return jsonb_build_object('due', false, 'reason', 'before 09:00 Dubai'); end if;
    if v_daily_done and v_batch_done then
      return jsonb_build_object('due', false, 'reason', 'already ran this Dubai day');
    end if;
  end if;

  v_go := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive();
  v_weekend := extract(isodow from v_now_dxb) in (6, 7);
  v_why := case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
                when not v_go then 'invite_enabled is false'
                when v_weekend then 'it is the UAE weekend' end;

  -- 1. THE BATCH, behind the PLACEMENT GATE (24 Sep 2026, it_engineer). On an open day it goes only after that
  --    morning's seed landed in the Inbox of both seed mailboxes; while the check can still finish it waits (the
  --    next beat asks again); any other answer holds it (fail closed). enqueue_supplier_invites asks the same gate.
  if p_force or not v_batch_done then
    v_batch_why := v_why;
    if v_why is null then
      v_gate := public.fn_invite_placement_gate(v_now_dxb::date);
      if v_gate = 'wait' and not p_force then
        v_batch_wait := true;
      elsif v_gate <> 'pass' then
        v_batch_why := 'the morning inbox placement check did not clear (' || v_gate || ')';
      end if;
    end if;
    if not v_batch_wait then
      -- THE WARM-UP (22 Sep 2026). fn_invite_ramp sets today's invite_daily_cap from the last 48 h of bounces and
      -- complaints. Open days only: a held day sends nothing, so it must not move the cap.
      if v_batch_why is null then v_cap := public.fn_invite_ramp(); end if;
      -- enqueue_supplier_invites holds itself (gates, weekend, holiday, bounce brake, cap, placement).
      v_invited := public.enqueue_supplier_invites(null);
    end if;
  end if;

  -- A later beat of the same day: the daily work is done, only the batch was owed.
  if v_daily_done and not p_force then
    if v_batch_wait then
      return jsonb_build_object('due', false, 'reason', 'the batch waits for the morning inbox placement check');
    end if;
    v_out := jsonb_build_object('job', 'supplier_outreach_batch', 'dubai_day', v_now_dxb::date, 'held', v_batch_why is not null,
      'held_because', v_batch_why, 'placement_gate', v_gate, 'invites', jsonb_build_object('queued', v_invited, 'cap', v_cap));
    insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
    values ('sales_engineer', 'ok', now(), now(), v_out,
            case when v_batch_why is not null
                 then 'Supplier invitation batch HELD (' || v_batch_why || '): ' || coalesce(v_invited, 0) || ' queued.'
                 else 'Supplier invitation batch: ' || coalesce(v_invited, 0) || ' invitation(s) queued at a cap of ' || coalesce(v_cap::text, '?') || '.' end);
    return v_out;
  end if;

  -- 2. Reminders: always counted; written only on an open weekday (the campaign gates, not the placement gate).
  for r in select * from public.fn_supplier_registration_reminders_due() loop
    v_due := v_due + 1;
    if v_why is not null then continue; end if;
    s := public.fn_sales_engineer_sends_registration_reminder(r.lead_id, r.stage, r.step, r.last_activity);
    if coalesce((s->>'ok')::boolean, false) then v_sent := v_sent + 1;
    else v_failed := v_failed || jsonb_build_array(jsonb_build_object('lead_id', r.lead_id, 'reason', s->>'reason'));
    end if;
  end loop;

  -- 3. The 24-hour clock: internal, so not held by the campaign gates.
  v_clock := public.fn_sales_engineer_raises_undecided_submissions(false);

  v_out := jsonb_build_object('job', 'supplier_outreach', 'dubai_day', v_now_dxb::date, 'held', v_why is not null, 'held_because', v_why,
    'placement_gate', v_gate, 'batch_waiting', v_batch_wait, 'batch_held_because', v_batch_why,
    'invites', jsonb_build_object('queued', coalesce(v_invited, 0), 'cap', v_cap),
    'reminders', jsonb_build_object('due', v_due, 'sent', v_sent, 'failed', v_failed),
    'submissions', v_clock);
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('sales_engineer', case when jsonb_array_length(v_failed) > 0 then 'warn' else 'ok' end, now(), now(), v_out,
          case when v_why is not null
               then 'Supplier outreach HELD (' || v_why || '): ' || coalesce(v_invited, 0) || ' invitation(s) queued, ' || v_due
                    || ' reminder(s) due and none written; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.'
               else 'Supplier outreach: '
                    || case when v_batch_wait then 'the invitation batch waits for the morning inbox placement check'
                            when v_batch_why is not null then 'the invitation batch was HELD (' || v_batch_why || ')'
                            else coalesce(v_invited, 0) || ' invitation(s) queued at a cap of ' || coalesce(v_cap::text, '?') end
                    || ', ' || v_sent || ' of ' || v_due
                    || ' reminder(s) sent; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.' end);
  return v_out;
end
$fn$;
revoke execute on function public.fn_sales_engineer_supplier_outreach_tick(boolean) from public, anon, authenticated;

-- ── 8. the batch itself refuses without a pass (live body of 24 Sep; PLACEMENT GATE marks the change) ────
create or replace function public.enqueue_supplier_invites(p_cap integer default null::integer)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_today date := (now() at time zone 'UTC')::date;
  v_planned int; v_used int; v_remaining int; v_count int;
  v_inv_recent int; v_bounced_recent int; v_rate numeric; v_max_rate numeric; v_cap int;
  v_pause boolean := false; v_why text; v_go boolean; v_pool int;
  v_hol_name text; v_hol_action text; v_hol_end date;
  v_cfg jsonb := coalesce((select nullif(value,'')::jsonb from app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_win_start timestamptz; v_win_end timestamptz;
  v_gate text;
begin
  select c.event_name, c.action, c.ends_on into v_hol_name, v_hol_action, v_hol_end
    from public.company_calendar c
   where c.kind = 'public_holiday'
     and v_today between c.starts_on and coalesce(c.ends_on, c.starts_on)
   order by c.starts_on limit 1;
  if v_hol_name is not null then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'calendar_paused', true, 'resumes_on', coalesce(v_hol_end, v_today) + 1),
            'Invites held: company_calendar has "' || v_hol_name || '" covering today. Its recorded action: '
            || coalesce(v_hol_action, '(none recorded)'), now(), now());
    return 0;
  end if;

  -- THE UAE WEEKEND IS SATURDAY AND SUNDAY. A cold invitation queued then waits under Monday's pile.
  -- Self-clearing like the holiday hold: nothing is switched off, Monday simply runs.
  if extract(isodow from (now() at time zone 'Asia/Dubai')) in (6, 7) then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'weekend_hold', true),
            'Invites held: it is the UAE weekend in Dubai; the next weekday batch runs as normal.', now(), now());
    return 0;
  end if;

  v_go  := (coalesce((select value from app_secrets where key = 'invite_enabled'), 'false') = 'true')
           and public.fn_supplier_outreach_golive();
  v_cap := coalesce((select nullif(value,'')::int from app_secrets where key='invite_daily_cap'), 10);
  select count(*) into v_pool from leads l where public.fn_supplier_invite_eligible(l);
  v_planned := least(coalesce(p_cap, v_cap), v_cap, v_pool);
  insert into invite_schedule(day, planned, status, note)
  values (v_today, greatest(v_planned, 0),
          case when v_go then 'approved' else 'pending' end,
          'batch of ' || greatest(v_planned, 0) || ' from a pool of ' || v_pool || ' eligible never-invited lead(s), cap ' || v_cap
          || case when v_go then '; sending open'
                  when not public.fn_supplier_outreach_golive() then '; HELD — real invitations wait for the founder''s go (app_secrets.supplier_outreach_golive is false)'
                  else '; HELD — real invitations wait for the founder''s go (app_secrets.invite_enabled)' end)
    on conflict (day) do update
      set planned = excluded.planned, status = excluded.status, note = excluded.note;

  if not v_go then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok',
            jsonb_build_object('queued', 0, 'planned', greatest(v_planned, 0), 'pool', v_pool, 'cap', v_cap, 'held', true),
            'Invites planned and HELD: ' || greatest(v_planned, 0) || ' of a pool of ' || v_pool
            || ' would be queued at cap ' || v_cap || '; '
            || case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive' else 'invite_enabled' end
            || ' is false, so nothing was written to the outbox.', now(), now());
    return 0;
  end if;
  if v_planned <= 0 then return 0; end if;

  -- PLACEMENT GATE (24 Sep 2026, it_engineer). Nothing is queued unless this morning's seed invitation landed
  -- in the Inbox of both seed mailboxes under today's effective sender (fn_invite_placement_gate). Fail closed: a check
  -- that is still running, failed, or never ran all hold the batch.
  v_gate := public.fn_invite_placement_gate((now() at time zone 'Asia/Dubai')::date);
  if v_gate <> 'pass' then
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; held: inbox placement ' || v_gate where day = v_today;
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'planned', v_planned, 'placement_gate', v_gate, 'held', true),
            'Invites held: the morning inbox placement check answered ' || v_gate || ', so nothing was written to the outbox.', now(), now());
    return 0;
  end if;

  -- THE SENDING WINDOW (22 Sep 2026). Invitations leave between the later of now and the window's start
  -- and the end of the Dubai working day, evenly spaced. Past the window nothing is queued: a cold
  -- invitation at night lands under the morning's pile, and tomorrow's batch runs as normal.
  v_win_start := greatest(now(), ((now() at time zone 'Asia/Dubai')::date
                   + make_interval(hours => coalesce((v_cfg->>'window_start_hour')::int, 9))) at time zone 'Asia/Dubai');
  v_win_end := ((now() at time zone 'Asia/Dubai')::date + make_interval(hours => coalesce((v_cfg->>'window_end_hour')::int, 17)))
               at time zone 'Asia/Dubai';
  if v_win_end < v_win_start + interval '30 minutes' then
    insert into agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('supplier_invites', 'ok', jsonb_build_object('queued', 0, 'planned', v_planned, 'outside_window', true),
            'Invites held: the Dubai sending window closes at ' || to_char(v_win_end at time zone 'Asia/Dubai', 'HH24:MI')
            || '; the next weekday batch runs as normal.', now(), now());
    return 0;
  end if;

  v_max_rate := coalesce((select nullif(value,'')::numeric from app_secrets where key='invite_max_bounce_rate'), 0.08);
  select count(*) into v_inv_recent from leads where invited_at > now() - interval '3 days';
  select count(*) into v_bounced_recent from leads where invite_status='bounced' and invited_at > now() - interval '3 days';
  v_rate := round(v_bounced_recent::numeric / greatest(v_inv_recent,1), 3);

  if v_inv_recent >= 15 and v_rate > v_max_rate then
    v_pause := true;
    v_why := 'bounce rate '||(v_rate*100)||'% over 3 days ('||v_bounced_recent||'/'||v_inv_recent||') exceeds the '||(v_max_rate*100)||'% limit';
  end if;
  if not v_pause and v_bounced_recent >= greatest(5, ceil(v_inv_recent * v_max_rate)::int) then
    v_pause := true;
    v_why := v_bounced_recent||' hard bounces in 3 days against '||v_inv_recent||' sent. Regardless of rate, that is a list-quality problem';
  end if;

  if v_pause then
    update app_secrets set value='false' where key='invite_enabled';
    update invite_schedule set status = 'pending', note = coalesce(note,'') || '; auto-paused: ' || v_why where day = v_today;
    if not exists (select 1 from founder_alerts where event='invite_paused_bounce' and created_at > now()-interval '24 hours') then
      insert into founder_alerts(level,event,detail,channel)
        values('crit','invite_paused_bounce','Supplier invites AUTO-PAUSED: '||v_why||'. Clean the list before resuming.','system');
      insert into notifications(type,to_email,to_role,channel,subject,body,status)
        values('invite_paused_bounce', coalesce((select split_part(value,',',1) from app_secrets where key='admin_emails'),'management@quotesdone.com'),'admin','email','Supplier invites paused - deliverability risk','Invites were auto-paused: '||v_why||'. Validate the list, then re-enable.','queued');
    end if;
    return 0;
  end if;

  -- test-path rows (fixture addresses) are not invitations and must not spend the day's cap:
  -- measured in the rolled-back rehearsal, two test sends plus one real row cut a batch of 5 to 2.
  select count(*) into v_used from notifications where type='supplier_invite' and (created_at at time zone 'UTC')::date = v_today
     and not public.fn_is_demo_email(to_email);
  v_remaining := greatest(0, v_planned - v_used);
  if v_remaining <= 0 then return 0; end if;

  with c as (
    select c.*, row_number() over () as rn, count(*) over () as n
      from public.fn_supplier_invite_candidates(v_remaining) c
  ), ins as (
    insert into notifications(type, to_email, to_role, lead_id, subject, body, lang, status, created_at, not_before)
    select 'supplier_invite', c.to_email, 'supplier', c.lead_id, c.subject, c.body, c.lang, 'queued', now(),
           v_win_start + (c.rn - 1) * ((v_win_end - v_win_start) / greatest(c.n, 1))
      from c
    on conflict (lower(btrim(to_email))) where type = 'supplier_invite' do nothing
    returning lead_id
  )
  update leads set invite_status='queued', invited_at=now()
  where invite_status is null and id in (select lead_id from ins);
  get diagnostics v_count = row_count;
  update invite_schedule set sent = sent + v_count where day = v_today;
  insert into agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('supplier_invites', 'ok',
          jsonb_build_object('queued', v_count, 'planned', v_planned, 'pool', v_pool, 'cap', v_cap, 'held', false,
                             'window_ends', v_win_end),
          'Invites: ' || v_count || ' queued of ' || v_planned || ' planned (pool ' || v_pool || ', cap ' || v_cap
          || '), spread until ' || to_char(v_win_end at time zone 'Asia/Dubai', 'HH24:MI') || ' Dubai.', now(), now());
  return v_count;
end;
$fn$;
revoke execute on function public.enqueue_supplier_invites(integer) from public, anon, authenticated;
