-- Assigned: it_engineer (for marketing). 18 Oct 2026.
--
-- THE OUTLOOK PLACEMENT SEED MOVES TO management@quotesdone.com, READ BY THE M365 APP THAT ALREADY SENDS.
-- The Outlook seed was management@doratajewelries.com, read through a delegated OAuth token (oauth_connect
-- provider=ms_graph_seed) that needed a second Entra app nobody had made, so the Outlook half of the morning
-- seed could never be read. The app send_outbox's M365 lane already uses (edge secrets MS_TENANT_ID /
-- MS_CLIENT_ID / MS_CLIENT_SECRET) holds application Mail.Read: measured 18 Oct 2026 from an edge function,
-- token roles Mail.Read, Mail.ReadWrite, Mail.Send; GET /users/management@quotesdone.com/mailFolders/inbox/messages
-- answered HTTP 200. _shared/inbox_placement.ts now reads that mailbox app-only; this file moves the address
-- the database queues the seed to and the CHECK that pins it.
--
-- The CHECK is added NOT VALID: the past days' rows keep the address they were actually sent to (history is not
-- rewritten); every new row must carry the new one.

alter table public.invite_placement_check drop constraint if exists invite_placement_check_outlook_to_check;
alter table public.invite_placement_check add constraint invite_placement_check_outlook_to_check
  check (outlook_to = 'management@quotesdone.com') not valid;

CREATE OR REPLACE FUNCTION public.fn_invite_placement_due(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
    values (v_day, v_token, v_from, v_subject, 'ahmadmhdnabilalzain@gmail.com', 'management@quotesdone.com', p_now)
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
$function$
;

-- management@quotesdone.com is admin_emails, so a10_notifications_founder_mail_policy turns any notification to it
-- whose kind founder_mail_policy does not allow into a routed task and returns NULL: the seed would never be sent
-- (measured 18 Oct 2026: a supplier_invite_seed insert to that address returned 0 rows). The seed is the founder's
-- own placement test (ledger 993: "placement is read in his Gmail and his Outlook"); one a sending day, and the
-- invite_placement_check CHECKs pin it to his two inboxes.
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role, updated_at)
values ('supplier_invite_seed', true,
  'Ledger 993 (24 Sep 2026): the morning invitation seed is placement-tested in the founder''s own Gmail and Outlook; since 18 Oct 2026 the Outlook seed is management@quotesdone.com. One seed a sending day, pinned by the invite_placement_check CHECKs.',
  'customer_support', now())
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason, updated_at = now();

-- Verdict: the routine queues the new address, and the constraint refuses the old one on a new row.
select case
  when position('''management@quotesdone.com'', p_now' in pg_get_functiondef('public.fn_invite_placement_due(timestamptz)'::regprocedure)) = 0
    then 'PROBE FAILED: fn_invite_placement_due does not queue management@quotesdone.com'
  when (select pg_get_constraintdef(oid) from pg_constraint where conname = 'invite_placement_check_outlook_to_check') not like '%management@quotesdone.com%'
    then 'PROBE FAILED: the outlook_to CHECK does not pin management@quotesdone.com'
  when not coalesce((select allowed_to_email from public.founder_mail_policy where kind = 'supplier_invite_seed'), false)
    then 'PROBE FAILED: founder_mail_policy would swallow the seed to management@quotesdone.com'
  else 'PROBE OK' end as verdict;
