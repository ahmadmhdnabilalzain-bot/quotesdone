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
--     removed. So this check runs on the same heartbeat, as a resilience_step row: the schedule this file seeds.
--   * The sending-day calendar is the one the batch reads. enqueue_supplier_invites holds on the Dubai
--     weekend (isodow 6/7) and on a company_calendar 'public_holiday' row covering the day. fn_is_working_day
--     reads a different table (public_holidays), and the batch does not read it. The check runs on exactly
--     the batch's days, so a day the batch sends can never be a day the check skipped.
--   * 13 supplier_invite_seed rows exist. They are sent through the real path by scripts/invitation_inbox_check.mjs
--     (to_role supplier, the live From, Reply-To and frame, never counted against the invitation cap).
--     The script only polled until the send and never read the folder back. The one Gmail reading
--     (24 Sep 11:31) was INBOX. No placement was stored anywhere.
--   * The live From is info@quotesdone.com (app_secrets.email_from_supplier). Each row records the From it
--     tested, and a pass only clears the batch while the From is still the same.
--   * The campaign pause already exists: fn_invite_same_day_brake (an_invitation_bounce_or_complaint_spike_
--     stops_the_campaign_the_same_hour.sql) sets invite_enabled=false, cancels the queued supplier_invite rows
--     and opens it_watch_finding. Its three statements move into fn_invite_campaign_pause so the brake and
--     this check stop the campaign the same way. The brake's own logic is unchanged.
--   * Credentials: app_secrets holds google_oauth_client_id / google_oauth_client_secret (the YouTube
--     connection's Google client) and no Gmail refresh token, no Microsoft Graph key. vault.secrets is
--     empty. Until they are stored, the reader cannot see a folder, the verdict is 'unread' and the day
--     does not send (fail closed).
--
-- WHAT THIS CHANGES
--   1. public.invite_placement_check: one row per Dubai sending day. It records the per-run token, the From
--      tested, both seed addresses (a CHECK constraint fixes each one, so no other address can be stored), the
--      folder each landed in, the reader's evidence and the verdict.
--   2. fn_invite_placement_due(now): the heartbeat's entry point. At 45 min before the window opens (05:15 UTC)
--      on a sending day with the campaign on, it queues ONE supplier_invite_seed to each seed inbox. The
--      subject is the live subject plus "(ref <token>)" and the body is the live body for a ZZ DEMO company.
--      Later it answers 'read' until a verdict, and settles the day once the window opens.
--   3. fn_invite_placement_record(day, gmail, outlook): the folder readings from
--      supabase/functions/_shared/inbox_placement.ts (Gmail API labelIds, Graph parentFolderId), then a settle.
--   4. fn_invite_placement_settle(day, now): verdict inbox (both in Inbox), spam (either in spam/junk),
--      elsewhere (trash or another folder), and, once the window opens without both in Inbox: not_sent,
--      unread (a mailbox could not be read) or not_found. Anything but inbox pauses the campaign
--      (fn_invite_campaign_pause) and files the it_engineer finding deliverability:inbox_placement (the
--      #935 door, fn_it_engineer_finding_upsert). An inbox verdict closes that finding.
--   5. fn_invite_placement_gate(day, now): 'pass' only for an inbox verdict under the current From.
--      'wait' before the window while the check can still finish. 'fail' otherwise, including a day with
--      no check (fail closed). enqueue_supplier_invites refuses to queue without 'pass'. The outreach tick
--      waits on 'wait' without spending its once-a-day run, and holds the day on anything else.
--   6. resilience_step 'inboxPlacement' (every 15 min, owner it_engineer): the schedule.
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

-- ── 2. the one pause, shared with the same-day brake ────────────────────────────────────────────────────
create or replace function public.fn_invite_campaign_pause(p_detector_key text, p_title text, p_evidence jsonb)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_cancelled int;
begin
  update app_secrets set value = 'false' where key = 'invite_enabled';
  update notifications set status = 'cancelled'
   where type = 'supplier_invite' and status = 'queued';
  get diagnostics v_cancelled = row_count;

  insert into it_watch_finding(detector_key, detector, subject, state, severity, title, evidence)
  values (p_detector_key, 'deliverability', 'supplier_invite', 'paused', 'high', left(p_title, 300),
          coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object('cancelled_queued', v_cancelled,
            'resume', 'set app_secrets.invite_enabled=true after reading the finding'))
  on conflict (detector_key) do update
     set state = excluded.state, severity = excluded.severity, title = excluded.title, evidence = excluded.evidence,
         last_seen_at = now(), seen_count = it_watch_finding.seen_count + 1, status = 'open', resolved_at = null;
  return v_cancelled;
end
$fn$;
revoke execute on function public.fn_invite_campaign_pause(text, text, jsonb) from public, anon, authenticated;

-- The brake of #943, its detection unchanged, pausing through the shared routine.
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
  v_sent int; v_b int; v_c int; v_why text; v_cancelled int;
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

  v_cancelled := public.fn_invite_campaign_pause('deliverability:supplier_invite',
    'Supplier invitations auto-paused: ' || v_why,
    jsonb_build_object('dubai_day', v_day, 'sent', v_sent, 'bounced', v_b, 'complained', v_c));

  insert into agent_runs(agent, status, counts, note, finished_at)
  values ('invite_same_day_brake', 'error',
          jsonb_build_object('sent_today', v_sent, 'bounced_today', v_b, 'complained_today', v_c, 'cancelled_queued', v_cancelled),
          'PAUSED: ' || v_why || '; invite_enabled=false, ' || v_cancelled || ' queued invitation(s) cancelled, it_engineer finding opened.', now());
  return null;
end
$fn$;
revoke execute on function public.fn_invite_same_day_brake() from public, anon, authenticated;

-- ── 3. when: the batch's own window and calendar ────────────────────────────────────────────────────────
-- The window opens at invite_warmup.window_start_hour Dubai (10:00 = 06:00 UTC). That instant is the
-- check's deadline, and the seed leaves 45 minutes before it (05:15 UTC).
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
create or replace function public.fn_invite_placement_settle(p_day date, p_now timestamptz default now())
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  r public.invite_placement_check;
  v text; v_sent_g text; v_sent_o text; v_title text; v_ev jsonb; v_cancelled int;
  v_key constant text := 'deliverability:inbox_placement';
begin
  select * into r from public.invite_placement_check where dubai_day = p_day for update;
  if r.dubai_day is null or r.verdict <> 'pending' then return r.verdict; end if;

  if 'spam' in (r.gmail_folder, r.outlook_folder) then v := 'spam';
  elsif r.gmail_folder in ('trash', 'other') or r.outlook_folder in ('trash', 'other') then v := 'elsewhere';
  elsif r.gmail_folder = 'inbox' and r.outlook_folder = 'inbox' then v := 'inbox';
  elsif p_now >= public.fn_invite_placement_deadline(p_day) then
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
    perform public.fn_it_engineer_finding_close(v_key,
      'the seed of ' || p_day || ' landed in the Inbox of both seed mailboxes (token ' || r.token || ')');
    insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('it_engineer', 'ok', jsonb_build_object('job', 'inbox_placement', 'dubai_day', p_day, 'verdict', v),
            'Inbox placement ' || p_day || ': Gmail inbox, Outlook inbox; the batch may send.', now(), now());
    return v;
  end if;

  v_title := 'Supplier invitations paused: the seed of ' || p_day || ' '
    || case v when 'spam' then 'landed in spam/junk'
              when 'elsewhere' then 'did not land in the Inbox'
              when 'not_sent' then 'was not sent before the batch window'
              when 'unread' then 'could not be read back from a seed mailbox'
              else 'was not found in a seed mailbox' end
    || ' (Gmail ' || coalesce(r.gmail_folder, 'unread') || ', Outlook ' || coalesce(r.outlook_folder, 'unread') || ')';
  v_ev := jsonb_build_object('dubai_day', p_day, 'token', r.token, 'from', r.from_address, 'subject', r.subject,
            'verdict', v, 'gmail', jsonb_build_object('to', r.gmail_to, 'folder', r.gmail_folder, 'detail', r.gmail_detail,
                                                      'notification_id', r.gmail_notification_id, 'status', v_sent_g),
            'outlook', jsonb_build_object('to', r.outlook_to, 'folder', r.outlook_folder, 'detail', r.outlook_detail,
                                          'notification_id', r.outlook_notification_id, 'status', v_sent_o),
            'reads', r.reads);
  v_cancelled := public.fn_invite_campaign_pause(v_key, v_title, v_ev);
  update public.invite_placement_check set verdict = v, decided_at = p_now, paused = true where dubai_day = p_day;
  perform public.fn_it_engineer_finding_upsert(v_key, v_title,
    'supplier invitation inbox placement: the daily seed to the Gmail and Microsoft 365 seed inboxes',
    'customer_facing', 1, v_ev,
    array['the seed went through the real path: send_outbox, the live From, Reply-To and frame'],
    case v when 'unread' then array['whether the Gmail / Microsoft Graph credentials in app_secrets are present and still consented']
           when 'not_sent' then array['why send_outbox did not send the seed before the window (email_enabled, supplier_emails_enabled, the daily cap)']
           else array['which content, sender or domain signal the mailbox provider acted on'] end,
    'it_engineer');
  insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
  values ('it_engineer', 'error', jsonb_build_object('job', 'inbox_placement', 'dubai_day', p_day, 'verdict', v,
            'cancelled_queued', v_cancelled),
          'PAUSED: ' || v_title || '; invite_enabled=false, finding ' || v_key || ' filed.', now(), now());
  return v;
end
$fn$;
revoke execute on function public.fn_invite_placement_settle(date, timestamptz) from public, anon, authenticated;

-- ── 5. the heartbeat's entry point: queue the seed, ask for a reading, settle at the deadline ─────────────
create or replace function public.fn_invite_placement_due(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_day date := (p_now at time zone 'Asia/Dubai')::date;
  v_deadline timestamptz := public.fn_invite_placement_deadline(v_day);
  r public.invite_placement_check;
  v_closed text; v_token text; v_subject text; v_body text; v_site text; v_from text;
  v_g bigint; v_o bigint; v_sg text; v_so text;
begin
  select * into r from public.invite_placement_check where dubai_day = v_day;

  if r.dubai_day is null then
    if p_now < v_deadline - interval '45 minutes' or p_now >= v_deadline then
      return jsonb_build_object('action', 'idle', 'dubai_day', v_day, 'reason', 'outside the seed window');
    end if;
    v_closed := public.fn_invite_placement_day_closed(p_now);
    if v_closed is not null then
      return jsonb_build_object('action', 'idle', 'dubai_day', v_day, 'reason', v_closed);
    end if;

    select coalesce(max(value) filter (where key = 'invite_subject'), ''),
           coalesce(max(value) filter (where key = 'invite_body'), ''),
           coalesce(nullif(max(value) filter (where key = 'public_site_url'), ''), 'https://quotesdone.com'),
           coalesce(nullif(max(value) filter (where key = 'email_from_supplier'), ''), 'QuotesDone <supplier@quotesdone.com>')
      into v_subject, v_body, v_site, v_from
      from public.app_secrets where key in ('invite_subject', 'invite_body', 'public_site_url', 'email_from_supplier');
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
    return jsonb_build_object('action', 'queued', 'dubai_day', v_day, 'token', v_token, 'from', v_from,
                              'notifications', jsonb_build_array(v_g, v_o));
  end if;

  if r.verdict <> 'pending' then
    return jsonb_build_object('action', 'idle', 'dubai_day', v_day, 'verdict', r.verdict);
  end if;
  if p_now >= v_deadline then
    return jsonb_build_object('action', 'settled', 'dubai_day', v_day, 'verdict', public.fn_invite_placement_settle(v_day, p_now));
  end if;

  select status into v_sg from public.notifications where id = r.gmail_notification_id;
  select status into v_so from public.notifications where id = r.outlook_notification_id;
  return jsonb_build_object('action', 'read', 'dubai_day', v_day, 'token', r.token, 'since', r.queued_at,
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
-- 'pass' | 'wait' | 'fail:<why>'. FAIL CLOSED: every state that is not a proven inbox placement under the
-- current From is 'fail' once the window opens, including a day on which no check ran at all.
create or replace function public.fn_invite_placement_gate(p_day date default null, p_now timestamptz default now())
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_day date := coalesce(p_day, (p_now at time zone 'Asia/Dubai')::date);
  r public.invite_placement_check; v text; v_from text;
begin
  select * into r from public.invite_placement_check where dubai_day = v_day;
  if r.dubai_day is null then
    return case when p_now < public.fn_invite_placement_deadline(v_day) then 'wait' else 'fail:no_check' end;
  end if;
  v := r.verdict;
  if v = 'pending' then
    if p_now < public.fn_invite_placement_deadline(v_day) then return 'wait'; end if;
    v := public.fn_invite_placement_settle(v_day, p_now);
  end if;
  if v <> 'inbox' then return 'fail:' || v; end if;
  v_from := coalesce(nullif((select value from public.app_secrets where key = 'email_from_supplier'), ''),
                     'QuotesDone <supplier@quotesdone.com>');
  if v_from is distinct from r.from_address then return 'fail:from_changed'; end if;
  return 'pass';
end
$fn$;
revoke execute on function public.fn_invite_placement_gate(date, timestamptz) from public, anon, authenticated;

-- ── 7. the outreach tick waits on the gate (live body of 24 Sep; PLACEMENT GATE marks the change) ────────
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
  v_gate text;
begin
  if not p_force then
    if extract(hour from v_now_dxb) < 9 then return jsonb_build_object('due', false, 'reason', 'before 09:00 Dubai'); end if;
    if exists (select 1 from public.agent_runs a
                where a.agent = 'sales_engineer' and a.counts->>'job' = 'supplier_outreach'
                  and a.started_at > now() - interval '1 day'
                  and (a.started_at at time zone 'Asia/Dubai')::date = v_now_dxb::date) then
      return jsonb_build_object('due', false, 'reason', 'already ran this Dubai day');
    end if;
  end if;

  v_go := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive();
  v_weekend := extract(isodow from v_now_dxb) in (6, 7);
  v_why := case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
                when not v_go then 'invite_enabled is false'
                when v_weekend then 'it is the UAE weekend' end;

  -- PLACEMENT GATE (24 Sep 2026, it_engineer). An open day sends only after that morning's seed landed in
  -- the Inbox of both seed mailboxes. While the check can still finish, the tick returns WITHOUT recording
  -- the day, so the next heartbeat asks again; any other answer holds the day (fail closed).
  if v_why is null then
    v_gate := public.fn_invite_placement_gate(v_now_dxb::date);
    if v_gate = 'wait' and not p_force then
      return jsonb_build_object('due', false, 'reason', 'waiting for the morning inbox placement check');
    end if;
    if v_gate <> 'pass' then
      v_why := 'the morning inbox placement check did not clear (' || v_gate || ')';
    end if;
  end if;

  -- 0. THE WARM-UP (22 Sep 2026). fn_invite_ramp sets today's invite_daily_cap from the last 48 h of
  --    bounces and complaints. Open days only: a held day sends nothing, so it must not move the cap.
  if v_why is null then v_cap := public.fn_invite_ramp(); end if;

  -- 1. The batch. enqueue_supplier_invites holds itself (gates, weekend, holiday, bounce brake, cap, placement).
  v_invited := public.enqueue_supplier_invites(null);

  -- 2. Reminders: always counted; written only on an open weekday.
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
    'placement_gate', v_gate,
    'invites', jsonb_build_object('queued', v_invited, 'cap', v_cap),
    'reminders', jsonb_build_object('due', v_due, 'sent', v_sent, 'failed', v_failed),
    'submissions', v_clock);
  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('sales_engineer', case when jsonb_array_length(v_failed) > 0 then 'warn' else 'ok' end, now(), now(), v_out,
          case when v_why is not null
               then 'Supplier outreach HELD (' || v_why || '): ' || v_invited || ' invitation(s) queued, ' || v_due
                    || ' reminder(s) due and none written; ' || coalesce(v_clock->>'raised_to_ceo', '0') || ' undecided submission(s) raised to the CEO.'
               else 'Supplier outreach: ' || v_invited || ' invitation(s) queued at a cap of ' || coalesce(v_cap::text, '?') || ', ' || v_sent || ' of ' || v_due
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
  -- in the Inbox of both seed mailboxes under today's From (fn_invite_placement_gate). Fail closed: a check
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

-- ── 9. the schedule: the heartbeat, not pg_cron ─────────────────────────────────────────────────────────
insert into public.resilience_step (step, every, budget_ms, place, rank, note, owner_seat) values
  ('inboxPlacement', interval '15 min', 9000, 'plan', 0,
   'it_engineer: the daily seed invitation to the Gmail and Microsoft 365 seed inboxes (05:15 UTC on a sending day), its folder read back through the Gmail API and Microsoft Graph, and the verdict that gates the 06:00 UTC batch (fn_invite_placement_due / _record). Outside 05:15-06:00 UTC a tick is one indexed read.',
   'it_engineer')
on conflict (step) do update
   set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place, rank = excluded.rank,
       note = excluded.note, owner_seat = excluded.owner_seat;
