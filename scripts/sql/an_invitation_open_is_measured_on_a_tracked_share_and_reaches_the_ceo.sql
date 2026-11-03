-- AN INVITATION OPEN IS MEASURED, ON A TRACKED SHARE, AND REACHES THE CEO.
--
-- Seat: marketing (the supplier campaign's copy and statistics), with sales_engineer (owner of supplier outreach) and ceo.
-- 3 Nov 2026. Founder's request of 3 Nov 2026: "I want us to know when someone opened our invitation email. If they read
-- our email and chose not to register, this is very valuable information for the team and the CEO to work out a plan or
-- produce statistics about the campaign."
--
-- THE RULING THIS CHANGES, AND HOW IT IS CONTAINED. founder_instruction 1301 (27 Oct 2026): "safer to not send links" -- the
-- invitation is plain text with no link (send_outbox/m365_lane.ts, campaignMail and m365CopyLint). An open can only be seen
-- if the email carries an HTML part with an image that our server serves, and that image URL is a link in the HTML. So:
--   * app_secrets.invite_open_tracking ('off', or a whole percentage 0-100; seeded '20') decides the TRACKED SHARE. A lead
--     is in the tracked arm when fn_invite_open_arm(lead id, share) says so: a fixed hash of the lead, so the same lead is
--     always in the same arm at the same share and the two arms can be compared (fn_invite_open_summary, by_arm).
--   * A tracked email is multipart/alternative: the plain-text part is BYTE-IDENTICAL to the untracked email, the HTML part
--     is that same text in <p> paragraphs plus ONE 1x1 image, no other image, no link, no tracking domain. The image is
--     https://quotesdone.com/u/o/<token>.gif (src/app/u/o/[token]/route.ts), our own first-party domain.
--   * The token is gen_random_uuid() without its dashes: random, one per notification, held only in email_open_token. It is
--     not the email address, not the lead id, and nothing derives it from either.
--   * 'off' (or 0) = send_outbox makes no call and sends exactly today's message, byte for byte (open_tracking.test.ts).
--   * The supplier_invite_seed (GlockApps / placement) rows are never tracked: the placement test keeps measuring the
--     untracked email. Arabic, demo and non-supplier mail are never tracked.
--
-- WHAT AN OPEN IS, AND ITS LIMITS (fn_email_open_classify; written plainly because the numbers will be read as facts):
--   machine_prefetch  a scanner or bot user agent; Apple Mail Privacy Protection (user agent exactly "Mozilla/5.0", or an
--                     Apple 17.0.0.0/8 address); a Microsoft Exchange Online Protection address (Microsoft 365 endpoints
--                     ID 10: 40.92.0.0/15, 40.107.0.0/16, 52.100.0.0/14, 104.47.0.0/17, 2a01:111:f400::/48,
--                     2a01:111:f403::/48); Google or Yahoo image proxy within 60 s of the send; any load within 60 s.
--   likely_human      a Google/Yahoo image proxy load after 60 s (those proxies fetch when the message is opened), or a mail
--                     client / browser user agent after 60 s.
--   unknown           anything else (an empty or unrecognised user agent, or no send time).
--   LIMITS: Outlook and most corporate clients block remote images from an unknown sender until the reader allows them, so
--   a person can read the email and register NO open (opens are a floor, never a count of readers). Apple's proxy loads
--   every image at delivery from addresses that are not all in 17.0.0.0/8, so some Apple prefetches will read as
--   likely_human. A scanner can present a browser user agent. Gmail caches the image, so a second open by the same person
--   may not reach us. The untracked arm has no opens by construction. Nothing here is a read receipt.
--
-- PRIVACY: the raw IP address is never stored. fn_email_open_record keeps sha256(salt | address) with a random salt in
-- app_secrets.email_open_ip_salt (pseudonymous, not anonymous: whoever holds the salt can test a guessed address), the
-- address class (apple / microsoft_eop / none), the first 300 characters of the user agent and the time. The Privacy
-- Policy 1.9 says so (section 9, src/content/legal.json; scripts/sql/the_privacy_policy_1_9_says_we_measure_invitation_opens.sql).
--
-- THE FUNNEL (fn_invite_open_funnel, per Dubai day and arm): sent -> delivered (sent less bounced; the Microsoft 365 lane has
-- no delivery receipt, so "delivered" is "accepted by Graph and no bounce recorded") -> opened (any / likely_human) ->
-- replied (inbound_messages from the lead after the send) -> registered (registration_submitted_at or claimed) -> approved,
-- plus bounced / complained (leads.invite_status, the same definition as fn_invite_send_health) and unsubscribed. The
-- follow-up list is fn_invite_opened_not_registered(days). Both are in the marketing seat's daily figures
-- (fn_marketing_report_figures: measured.invitation_opens and one headline sentence) and on the CEO's seat board
-- (fn_ceo_seat_board: seats.marketing.achievement.invitation_opens). Both routines are the live bodies of 3 Nov 2026
-- (md5 4093c0d9... and adf47d6f... read back from production) with only those additions.
--
-- prevented by: supabase/functions/send_outbox/open_tracking.test.ts (MIME, switch, token, no link),
--               scripts/checks/an_invitation_open_is_measured_on_a_tracked_share.test.mjs (this file's shape, privacy text),
--               scripts/sql/an_invitation_open_is_measured_on_a_tracked_share_and_reaches_the_ceo_probe.sql (the routines on fixtures).
-- No begin/commit: the applier runs the file as one transaction. Ends with a verdict row.

-- 1. THE TOKENS AND THE OPENS ----------------------------------------------------------------------------------------------
create table if not exists public.email_open_token (
  token           text primary key check (token ~ '^[0-9a-f]{32}$'),
  notification_id bigint not null unique references public.notifications(id) on delete cascade,
  lead_id         bigint,
  share_pct       integer not null check (share_pct between 1 and 100),
  created_at      timestamptz not null default now()
);
create index if not exists email_open_token_lead_idx on public.email_open_token (lead_id);
comment on table public.email_open_token is
  'One random token per tracked supplier invitation (marketing, 3 Nov 2026): the pixel URL carries it, never the email or lead id. Written by fn_invite_open_token only.';

create table if not exists public.email_open_event (
  id                 bigserial primary key,
  token              text not null references public.email_open_token(token) on delete cascade,
  notification_id    bigint not null,
  opened_at          timestamptz not null default now(),
  seconds_after_send numeric,
  user_agent         text,
  ip_hash            text,
  ip_class           text check (ip_class in ('apple', 'microsoft_eop')),
  classification     text not null check (classification in ('machine_prefetch', 'likely_human', 'unknown')),
  rule               text not null
);
create index if not exists email_open_event_token_idx on public.email_open_event (token);
create index if not exists email_open_event_notification_idx on public.email_open_event (notification_id);
comment on table public.email_open_event is
  'Each load of a tracked invitation''s image (marketing, 3 Nov 2026). Never the raw IP: ip_hash is sha256(salt | address). classification by fn_email_open_classify; an open is a floor, never a read receipt.';

alter table public.email_open_token enable row level security;
alter table public.email_open_event enable row level security;
drop policy if exists email_open_token_service_role_only on public.email_open_token;
create policy email_open_token_service_role_only on public.email_open_token as permissive for all to public using (false) with check (false);
drop policy if exists email_open_event_service_role_only on public.email_open_event;
create policy email_open_event_service_role_only on public.email_open_event as permissive for all to public using (false) with check (false);
revoke all on public.email_open_token from anon, authenticated;
revoke all on public.email_open_event from anon, authenticated;
revoke all on sequence public.email_open_event_id_seq from anon, authenticated;

-- 2. THE SWITCH AND THE ARM ------------------------------------------------------------------------------------------------
-- 'off', '', a missing row or anything that is not a whole number reads as 0; '20' or '20%' is 20; above 100 is 100.
create or replace function public.fn_invite_open_share()
returns integer language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select case when v ~ '^\s*\d{1,3}\s*%?\s*$' then least(100, btrim(replace(v, '%', ''))::int) else 0 end
    from (select coalesce((select value from public.app_secrets where key = 'invite_open_tracking'), 'off') as v) s
$fn$;

-- A lead's bucket 0-99 is a fixed hash of its key, so the arm does not move between the invitation and its nudges.
create or replace function public.fn_invite_open_arm(p_key text, p_share integer)
returns boolean language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(p_share, 0) > 0 and coalesce(p_key, '') <> ''
     and (('x' || substr(md5('invite_open:' || p_key), 1, 7))::bit(28)::int % 100) < least(coalesce(p_share, 0), 100)
$fn$;

-- The token for one queued notification, or NULL (control arm, switch off, not a tracked kind). Idempotent: a held and
-- re-tried row keeps its first token.
create or replace function public.fn_invite_open_token(p_notification_id bigint)
returns text language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare n record; v_share int; v_tok text;
begin
  select id, type, to_role, to_email, lead_id, kind, lang into n from public.notifications where id = p_notification_id;
  if not found or n.to_role is distinct from 'supplier' or n.type not in ('supplier_invite', 'supplier_invite_nudge')
     or coalesce(n.lang, 'en') = 'ar' or public.fn_is_demo_email(n.to_email) then return null; end if;
  select token into v_tok from public.email_open_token where notification_id = n.id;
  if found then return v_tok; end if;
  v_share := public.fn_invite_open_share();
  if not public.fn_invite_open_arm(coalesce(n.lead_id::text, lower(btrim(n.to_email))), v_share) then return null; end if;
  insert into public.email_open_token (token, notification_id, lead_id, share_pct)
  values (replace(gen_random_uuid()::text, '-', ''), n.id, n.lead_id, v_share)
  on conflict (notification_id) do nothing;
  select token into v_tok from public.email_open_token where notification_id = n.id;
  return v_tok;
end $fn$;

-- 3. WHO LOADED THE IMAGE --------------------------------------------------------------------------------------------------
create or replace function public.fn_email_open_ip_class(p_ip inet)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case
    when p_ip is null then null
    when family(p_ip) = 4 and p_ip << inet '17.0.0.0/8' then 'apple'
    when (family(p_ip) = 4 and (p_ip << inet '40.92.0.0/15' or p_ip << inet '40.107.0.0/16' or p_ip << inet '52.100.0.0/14' or p_ip << inet '104.47.0.0/17'))
      or (family(p_ip) = 6 and (p_ip << inet '2a01:111:f400::/48' or p_ip << inet '2a01:111:f403::/48')) then 'microsoft_eop'
  end
$fn$;

create or replace function public.fn_email_open_classify(p_user_agent text, p_ip inet, p_seconds numeric,
                                                         out classification text, out rule text)
language plpgsql immutable set search_path to 'public', 'pg_temp' as $fn$
declare ua text := btrim(coalesce(p_user_agent, '')); ipc text := public.fn_email_open_ip_class(p_ip); c_fast constant numeric := 60;
begin
  if p_seconds is null then classification := 'unknown'; rule := 'no send time on the notification'; return; end if;
  if ua ~* '(bot\M|crawl|spider|scanner|barracuda|mimecast|proofpoint|ppops|forcepoint|symantec|messagelabs|trend ?micro|sophos|fortinet|fortimail|ironport|cisco|zscaler|libwww|python|curl/|wget|go-http|java/|okhttp|axios|node-fetch|undici|headless|phantomjs|link ?check|urlscan|safelinks|existence discovery)' then
    classification := 'machine_prefetch'; rule := 'scanner or bot user agent'; return; end if;
  if ua ~* '(googleimageproxy|ggpht\.com|yahoomailproxy)' then
    if p_seconds < c_fast then classification := 'machine_prefetch'; rule := 'mail image proxy within 60 s of the send';
    else classification := 'likely_human'; rule := 'mail image proxy fetch after 60 s (fetched when the message is opened)'; end if;
    return; end if;
  if ua = 'Mozilla/5.0' or ipc = 'apple' then classification := 'machine_prefetch'; rule := 'Apple Mail Privacy Protection'; return; end if;
  if ipc = 'microsoft_eop' then classification := 'machine_prefetch'; rule := 'Microsoft Exchange Online Protection address'; return; end if;
  if p_seconds < c_fast then classification := 'machine_prefetch'; rule := 'loaded within 60 s of the send'; return; end if;
  if ua ~* '(outlook|microsoft office|thunderbird|windows nt|macintosh|iphone|ipad|android|applewebkit|gecko|chrome|safari)' then
    classification := 'likely_human'; rule := 'mail client or browser user agent after 60 s'; return; end if;
  classification := 'unknown'; rule := case when ua = '' then 'no user agent' else 'unrecognised user agent' end;
end $fn$;

-- Called by the pixel route (service role) with the token, the user agent and the client address. Answers a word, never
-- an error the route would have to handle: bad_token / unknown_token / capped / the classification.
create or replace function public.fn_email_open_record(p_token text, p_user_agent text default null, p_ip text default null)
returns text language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare t public.email_open_token%rowtype; v_sent timestamptz; v_ip inet; v_secs numeric; v_salt text; c record;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{32}$' then return 'bad_token'; end if;
  select * into t from public.email_open_token where token = p_token;
  if not found then return 'unknown_token'; end if;
  if (select count(*) from public.email_open_event where token = p_token) >= 50 then return 'capped'; end if;
  select sent_at into v_sent from public.notifications where id = t.notification_id;
  begin v_ip := nullif(btrim(split_part(coalesce(p_ip, ''), ',', 1)), '')::inet; exception when others then v_ip := null; end;
  v_secs := case when v_sent is null then null else round(extract(epoch from (now() - v_sent))::numeric, 1) end;
  select * into c from public.fn_email_open_classify(p_user_agent, v_ip, v_secs);
  v_salt := (select value from public.app_secrets where key = 'email_open_ip_salt');
  insert into public.email_open_event (token, notification_id, seconds_after_send, user_agent, ip_hash, ip_class, classification, rule)
  values (p_token, t.notification_id, v_secs, left(p_user_agent, 300),
          case when v_ip is not null and coalesce(v_salt, '') <> '' then encode(sha256(convert_to(v_salt || '|' || host(v_ip), 'UTF8')), 'hex') end,
          public.fn_email_open_ip_class(v_ip), c.classification, c.rule);
  return c.classification;
end $fn$;

-- 4. THE FUNNEL, THE FOLLOW-UP LIST, THE SUMMARY ---------------------------------------------------------------------------
create or replace function public.fn_invite_open_funnel(p_from timestamptz, p_to timestamptz default now())
returns table(day date, arm text, sent integer, delivered integer, bounced integer, complained integer, opened_any integer,
              opened_human integer, opened_machine_only integer, replied integer, registered integer, approved integer,
              unsubscribed integer)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with inv as (
    select n.id, n.lead_id, n.to_email, n.sent_at, l.invite_status,
           (l.registration_submitted_at is not null or coalesce(l.claimed, false)) as reg,
           coalesce(l.approval_status = 'approved', false) as appr,
           exists (select 1 from public.email_open_token t where t.notification_id = n.id) as tracked
      from public.notifications n
      join public.leads l on l.id = n.lead_id
     where n.type = 'supplier_invite' and n.sent_at is not null and n.sent_at > p_from and n.sent_at <= coalesce(p_to, now())
       and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(n.to_email)),
  opens as (
    select i.id, count(e.id) as any_n, count(e.id) filter (where e.classification = 'likely_human') as human_n
      from inv i
      join public.email_open_token t on t.lead_id = i.lead_id
      join public.email_open_event e on e.token = t.token and e.opened_at >= i.sent_at
     group by i.id)
  select (i.sent_at at time zone 'Asia/Dubai')::date, case when i.tracked then 'tracked' else 'untracked' end,
         count(*)::int,
         (count(*) filter (where i.invite_status is distinct from 'bounced'))::int,
         (count(*) filter (where i.invite_status = 'bounced'))::int,
         (count(*) filter (where i.invite_status = 'complained'))::int,
         (count(o.id) filter (where o.any_n > 0))::int,
         (count(o.id) filter (where o.human_n > 0))::int,
         (count(o.id) filter (where o.any_n > 0 and o.human_n = 0))::int,
         (count(*) filter (where exists (select 1 from public.inbound_messages m
                                          where (m.lead_id = i.lead_id or lower(m.from_email) = lower(btrim(i.to_email)))
                                            and m.created_at > i.sent_at)))::int,
         (count(*) filter (where i.reg))::int,
         (count(*) filter (where i.appr))::int,
         (count(*) filter (where exists (select 1 from public.email_suppressions s
                                          where s.email = lower(btrim(i.to_email)) and s.reason = 'unsubscribe')))::int
    from inv i left join opens o on o.id = i.id
   group by 1, 2
   order by 1, 2
$fn$;

create or replace function public.fn_invite_opened_not_registered(p_min_days integer default 3)
returns table(lead_id bigint, company_name text, email text, invited_at timestamptz, first_human_open_at timestamptz,
              human_opens integer, days_since_first_open integer, replied boolean)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select l.id, l.company_name, l.email, l.invited_at, min(e.opened_at), count(*)::int,
         floor(extract(epoch from (now() - min(e.opened_at))) / 86400)::int,
         exists (select 1 from public.inbound_messages m where m.lead_id = l.id or lower(m.from_email) = lower(btrim(l.email)))
    from public.email_open_event e
    join public.email_open_token t on t.token = e.token
    join public.leads l on l.id = t.lead_id
   where e.classification = 'likely_human'
     and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(l.email)
     and l.registration_submitted_at is null and not coalesce(l.claimed, false)
     and not exists (select 1 from public.email_suppressions s where s.email = lower(btrim(l.email)))
   group by l.id
  having min(e.opened_at) <= now() - make_interval(days => greatest(0, coalesce(p_min_days, 3)))
   order by min(e.opened_at)
$fn$;

create or replace function public.fn_invite_open_summary(p_from timestamptz, p_to timestamptz default now())
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_arms jsonb;
begin
  select coalesce(jsonb_object_agg(a.arm, to_jsonb(a) - 'arm'), '{}'::jsonb) into v_arms from (
    select f.arm, sum(f.sent)::int as sent, sum(f.delivered)::int as delivered, sum(f.bounced)::int as bounced,
           sum(f.complained)::int as complained, sum(f.opened_any)::int as opened_any, sum(f.opened_human)::int as opened_human,
           sum(f.opened_machine_only)::int as opened_machine_only, sum(f.replied)::int as replied,
           sum(f.registered)::int as registered, sum(f.approved)::int as approved, sum(f.unsubscribed)::int as unsubscribed,
           round(sum(f.bounced)::numeric / nullif(sum(f.sent), 0), 4) as bounce_rate,
           round(sum(f.complained)::numeric / nullif(sum(f.sent), 0), 4) as complaint_rate,
           round(sum(f.replied)::numeric / nullif(sum(f.sent), 0), 4) as reply_rate,
           round(sum(f.unsubscribed)::numeric / nullif(sum(f.sent), 0), 4) as unsubscribe_rate,
           round(sum(f.registered)::numeric / nullif(sum(f.sent), 0), 4) as registered_rate,
           round(sum(f.opened_human)::numeric / nullif(sum(f.sent), 0), 4) as human_open_rate
      from public.fn_invite_open_funnel(p_from, p_to) f group by f.arm) a;
  return jsonb_build_object(
    'from', p_from, 'to', coalesce(p_to, now()), 'share_pct', public.fn_invite_open_share(), 'by_arm', v_arms,
    'opened_by_a_person_not_registered_after_3_days', (select count(*) from public.fn_invite_opened_not_registered(3)),
    'basis', 'supplier_invite rows sent in the window (ZZ DEMO and reserved addresses excluded), split by arm: tracked = the email carried the image (email_open_token). bounced and complained are leads.invite_status, the same as fn_invite_send_health; delivered = sent less bounced (the Microsoft 365 lane has no delivery receipt); opened counts a lead once, from any of its tracked emails, after this invitation; replied = inbound_messages from the lead after the send; registered = registration_submitted_at or claimed; unsubscribed = email_suppressions reason unsubscribe. The follow-up list is fn_invite_opened_not_registered(days).',
    'limits', 'An open is a load of the image, never a read receipt. Outlook and most corporate mail block remote images from an unknown sender, so a person can read the email and leave no open: opened is a floor. Apple Mail Privacy Protection and mail scanners load images without a person; the rules mark the known ones machine_prefetch, not all. The untracked arm has no opens by construction; compare the arms on bounce, complaint, reply, unsubscribe and registered rates, and on inbox placement.');
end $fn$;

revoke execute on function public.fn_invite_open_share() from public, anon, authenticated;
revoke execute on function public.fn_invite_open_arm(text, integer) from public, anon, authenticated;
revoke execute on function public.fn_invite_open_token(bigint) from public, anon, authenticated;
revoke execute on function public.fn_email_open_ip_class(inet) from public, anon, authenticated;
revoke execute on function public.fn_email_open_classify(text, inet, numeric) from public, anon, authenticated;
revoke execute on function public.fn_email_open_record(text, text, text) from public, anon, authenticated;
revoke execute on function public.fn_invite_open_funnel(timestamptz, timestamptz) from public, anon, authenticated;
revoke execute on function public.fn_invite_opened_not_registered(integer) from public, anon, authenticated;
revoke execute on function public.fn_invite_open_summary(timestamptz, timestamptz) from public, anon, authenticated;

-- 5. THE MARKETING SEAT'S DAILY FIGURES AND THE CEO'S SEAT BOARD CARRY IT (live bodies of 3 Nov 2026 + the additions) --------
CREATE OR REPLACE FUNCTION public.fn_marketing_report_figures(p_from timestamp with time zone, p_to timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_posts int; v_posts_ever int; v_spend jsonb; v_spend_aed numeric; v_unconv int; v_asked int; v_inq numeric; v_head text;
        v_sched int; v_held int; v_failed int; v_stuck int; v_live boolean; v_ins jsonb; v_conn jsonb; v_ins_days int;
        v_partial int; v_opens jsonb;
begin
  -- A post counts as published only when its channels say so (channel_outcome published, or not read back yet:
  -- null / pending keep the old reading). Partly published is its own figure; failed on every channel is failed.
  select count(*) filter (where published_at >= p_from and published_at < p_to and coalesce(channel_outcome, 'published') in ('published', 'pending')),
         count(*) filter (where coalesce(channel_outcome, 'published') in ('published', 'pending')),
         count(*) filter (where published_at >= p_from and published_at < p_to and channel_outcome = 'partial')
    into v_posts, v_posts_ever, v_partial from public.marketing_post where status = 'published' and not is_demo;
  select count(*) filter (where status = 'scheduled' and scheduled_at >= p_to and scheduled_at < p_to + interval '7 days'),
         count(*) filter (where status = 'scheduled' and scheduled_at <= p_to and dry_run is not null),
         count(*) filter (where (status = 'failed' and updated_at >= p_from and updated_at < p_to)
                             or (status = 'published' and channel_outcome = 'failed' and published_at >= p_from and published_at < p_to)),
         count(*) filter (where status = 'publishing' and updated_at < p_to - interval '30 minutes')
    into v_sched, v_held, v_failed, v_stuck from public.marketing_post where not is_demo;
  v_live := coalesce((select lower(value) = 'true' from public.app_secrets where key = 'marketing_golive'), false);
  select coalesce(jsonb_object_agg(platform, aed), '{}'::jsonb), coalesce(sum(aed), 0), coalesce(sum(unconv), 0)
    into v_spend, v_spend_aed, v_unconv
    from (select platform, sum(amount_aed) aed, count(*) filter (where amount_aed is null) unconv
            from public.ad_spend_reported where spend_date >= (p_from at time zone 'Asia/Dubai')::date
                                           and spend_date < (p_to at time zone 'Asia/Dubai')::date
           group by platform) s;
  select count(*) into v_asked from public.notifications
   where kind = 'social_human_request' and created_at >= p_from and created_at < p_to;
  v_inq := public.fn_ceo_plan_measure('inquiries_posted', p_from, p_to)::numeric;
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb), count(distinct d) into v_ins, v_ins_days from (
    select i.platform || '.' || i.metric k, sum(i.value) v, max(i.day) d
      from public.marketing_insight_day i
     where i.object_type <> 'post' and i.day >= (p_from at time zone 'Asia/Dubai')::date - 1
       and i.day < (p_to at time zone 'Asia/Dubai')::date
     group by 1) x;
  v_conn := public.fn_marketing_connection_status();
  v_head := format('%s post(s) published%s, %s scheduled for the next 7 days%s, AED %s ad spend reported, %s conversation(s) handed to the founder, %s customer request(s) posted.',
                   v_posts, case when v_partial > 0 then format(' (%s more only partly: a channel failed)', v_partial) else '' end, v_sched, case when not v_live and v_held > 0 then format(' (%s due and held: publishing is off)', v_held) else '' end,
                   v_spend_aed, v_asked, coalesce(v_inq::text, 'unmeasured'));
  -- 3 Nov 2026 (marketing): the invitation open measurement over the same window (fn_invite_open_summary).
  v_opens := public.fn_invite_open_summary(p_from, p_to);
  v_head := v_head || format(' Invitations: %s sent, %s opened by a person (tracked share %s%%), %s opened by a person and not registered after 3 days.',
                             coalesce((v_opens #>> '{by_arm,tracked,sent}')::int, 0) + coalesce((v_opens #>> '{by_arm,untracked,sent}')::int, 0),
                             coalesce(v_opens #>> '{by_arm,tracked,opened_human}', '0'), v_opens ->> 'share_pct',
                             v_opens ->> 'opened_by_a_person_not_registered_after_3_days');
  return jsonb_build_object(
    'headline', v_head,
    'measured', jsonb_build_object(
      'posts_published', v_posts, 'posts_partly_published', v_partial, 'posts_published_ever', v_posts_ever, 'posts_scheduled_next_7_days', v_sched,
      'posts_due_held_by_switch', v_held, 'posts_failed', v_failed, 'posts_stuck_publishing', v_stuck, 'publishing_live', v_live,
      'ad_spend_reported_aed', v_spend_aed, 'ad_spend_by_platform_aed', v_spend, 'ad_spend_rows_unconverted', v_unconv,
      'conversations_handed_to_founder', v_asked, 'customer_requests_posted', v_inq,
      'insights', v_ins, 'connections_all_ok', v_conn->'all_ok',
      'connections_failing', coalesce((select jsonb_agg(c->'check') from jsonb_array_elements(v_conn->'checks') c where not (c->>'ok')::boolean), '[]'::jsonb),
      'connections_measured_at', v_conn->'oldest_measurement',
      'business_development', (select to_jsonb(f) from public.marketing_bd_figures f),
      'social_inbox', coalesce((select jsonb_agg(to_jsonb(v)) from public.v_marketing_social_volume v), '[]'::jsonb),
      'invitation_opens', v_opens),
    'not_measured', to_jsonb(array_remove(array[
      case when v_ins_days = 0 then 'followers, reach and engagement per channel: no insight was pulled for the window yet' end,
      case when coalesce((v_conn->>'never_measured')::boolean, true) then 'channel access: the access check has not run yet' end,
      'search rankings and organic traffic: no SEO reader is built yet'], null)),
    'basis', 'Posts: marketing_post (published_at in the window; scheduled and held from its status and dry_run; published / partly / failed from channel_outcome where it has been read back from Postiz, else from status). Spend: ad_spend_reported by spend_date (Asia/Dubai), in AED at gl_settings usd_to_aed. Insights: marketing_insight_day, page and account metrics summed over the window. Connections: marketing_connection_check as last measured. Handed to the founder: notifications of kind social_human_request. Customer requests: fn_ceo_plan_measure(inquiries_posted), demo excluded. Business development: marketing_bd_figures (7-day counts, ZZ DEMO excluded). Social inbox: v_marketing_social_volume per platform. Invitation opens: fn_invite_open_summary (supplier_invite rows sent in the window, by arm; an open is a load of the image in a tracked email, so it says nothing about untracked mail or mail whose images were not loaded). Window: the 24 hours before the report.');
end $function$;

CREATE OR REPLACE FUNCTION public.fn_ceo_seat_board(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_from timestamptz := now() - make_interval(days => greatest(1, coalesce(p_days, 7)));
  j jsonb;
begin
  -- agent_runs is rolled up per AGENT first (~110 distinct), then mapped to a seat: fn_run_seat runs
  -- ~110 times instead of once per row per subquery (3 x 6 seats x ~269k rows = ~4.8M calls).
  with ar as (
    select public.fn_run_seat(a.agent) as seat,
           sum(a.runs)::bigint as runs, sum(a.errors)::bigint as errors, max(a.last_seen) as last_seen
      from (select r.agent,
                   count(*) filter (where r.started_at >= v_from)                      as runs,
                   count(*) filter (where r.status = 'error' and r.started_at >= v_from) as errors,
                   max(r.started_at)                                                     as last_seen
              from agent_runs r group by r.agent) a
     group by 1)
  select jsonb_build_object(
    'window_days', greatest(1, coalesce(p_days, 7)),
    'since', v_from,
    'seats', (
      select jsonb_object_agg(s.seat, jsonb_build_object(

        -- WHAT IT DID: every run, and every run that failed. Same source for all six, so the
        -- comparison between seats is honest.
        'runs',        coalesce((select ar.runs   from ar where ar.seat = s.seat), 0),
        'errors',      coalesce((select ar.errors from ar where ar.seat = s.seat), 0),
        'last_seen',   (select ar.last_seen from ar where ar.seat = s.seat),

        -- WHAT IS WAITING ON IT: work assigned and not finished. This is the half the CEO had no
        -- sight of at all.
        'open_tasks',  (select count(*) from org_tasks t
                         where t.assigned_agent = s.seat and t.status in ('assigned','in_progress')),
        'oldest_open_task_days', (select round(extract(epoch from (now() - min(t.created_at)))/86400)
                         from org_tasks t
                        where t.assigned_agent = s.seat and t.status in ('assigned','in_progress')),

        -- WHAT IT FILED TO THE CEO, and whether the CEO has picked it up. An unread report is the
        -- CEO's own backlog, not the seat's.
        --
        -- THE NAME OF THIS FIGURE WAS WRONG AND THE FOUNDER CAUGHT IT. It read
        -- 'awaiting_my_acceptance', and on 9 September he read the board and asked "wait is the CEO
        -- basically waiting to approve the accountant report" -- a fair reading of that phrase, and
        -- not what the number means. Measured: three routines read accepted_at
        -- (fn_ceo_weekly_figures, fn_ceo_seat_board, fn_customer_mandatory_check) and all three only
        -- COUNT it for display. Nothing gates on it. Both accountant reports say in their own
        -- requested_outcome field "NOTHING IS REQUESTED", and one had already reached the founder.
        -- It is a read receipt, not an approval queue, and the label now says which. A number whose
        -- name implies work is blocked, on a board built so the chief executive knows what is
        -- waiting on whom, is worse than no number.
        'filed_to_ceo',    (select count(*) from support_ceo_report c where c.source_agent = s.seat),
        'filed_but_not_yet_read_by_ceo', (select count(*) from support_ceo_report c
                                    where c.source_agent = s.seat and c.accepted_at is null),

        -- WHAT IT ACHIEVED: the question this seat's own job answers.
        'achievement', case s.seat
          when 'accountant' then jsonb_build_object(
            'expense_records_with_a_document', (select count(*) from expense_entries where doc_path is not null),
            'journals_posted',                 (select count(*) from gl_journal where status = 'posted'),
            'weekly_reports_delivered',        (select count(*) from accountant_weekly_report where founder_submitted_at is not null))
          when 'customer_support' then jsonb_build_object(
            'conversations_answered',          (select count(*) from assistant_logs where created_at >= v_from),
            'questions_it_could_not_answer',   (select count(*) from sales_knowledge_gap where status = 'open'),
            'supplier_contacts_logged',        (select count(*) from supplier_response_watch))
          when 'sales_engineer' then jsonb_build_object(
            'assists_given',                   (select count(*) from sales_decision_log where created_at >= v_from),
            'quotes',                          (select count(*) from quotes),
            'comparisons',                     (select count(*) from quote_comparisons))
          when 'it_engineer' then jsonb_build_object(
            'findings_open',                   (select count(*) from it_watch_finding where status = 'open'),
            'findings_closed',                 (select count(*) from it_watch_finding where status = 'resolved'),
            'alerts_delivered',                (select count(*) from notifications
                                                 where kind like 'it_%' and status = 'sent'))
          -- 22 Sep 2026 (founder instruction 721): the marketing seat reports the overall picture to the CEO.
          -- Its reports are READ, never approved; 'read_by_ceo' counts the CEO's read receipts.
          when 'marketing' then jsonb_build_object(
            'reports_filed',                   (select count(*) from marketing_report),
            'reports_read_by_ceo',             (select count(*) from marketing_report where read_by_ceo_at is not null),
            'ad_spend_reported_aed',           (select coalesce(sum(amount_aed), 0) from ad_spend_reported),
            'latest_report',                   (select jsonb_build_object('date', m.report_date, 'headline', m.figures->'headline',
                                                                          'no_data_yet', m.no_data_yet)
                                                  from marketing_report m order by m.report_date desc limit 1),
            -- 3 Nov 2026 (marketing): sent, opened, replied, registered per arm, and opened-not-registered
            'invitation_opens',                public.fn_invite_open_summary(v_from, now()))
          when 'ceo' then jsonb_build_object(
            'approvals_decided',               (select count(*) from ceo_approval),
            'reports_accepted',                (select count(*) from support_ceo_report where accepted_at is not null),
            'weekly_reports_delivered',        (select count(*) from ceo_weekly_report where founder_submitted_at is not null))
          else '{}'::jsonb end))
      from (select unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing']) as seat) s),

    'basis', 'Every figure is a count of rows that exist, over the window for activity and lifetime '
          || 'for achievement. Nothing here is scored or rated. A zero means the thing has not '
          || 'happened, not that nobody counted it — the seats were created 7-9 September 2026 and '
          || 'the company has taken no revenue yet.'
  ) into j;
  return j;
end $function$;

-- 6. THE SETTINGS, THE EXPORT REGISTRY ---------------------------------------------------------------------------------------
-- The share is seeded, never overwritten by a re-run: the CEO or the marketing seat moves it ('off' stops it at once).
insert into public.app_secrets (key, value, updated_at) values ('invite_open_tracking', '20', now()) on conflict (key) do nothing;
insert into public.app_secrets (key, value, updated_at) values ('email_open_ip_salt', encode(extensions.gen_random_bytes(32), 'hex'), now())
  on conflict (key) do nothing;

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('email_open_token', true, 'marketing', 'One random token per tracked supplier invitation: which emails carried the image (the tracked arm of the campaign comparison).', 'marketing'),
  ('email_open_event', true, 'marketing', 'Each load of a tracked invitation image, classified (machine_prefetch / likely_human / unknown); hashed address only, never the raw IP.', 'marketing')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category, reason = excluded.reason, added_by = excluded.added_by;

-- verdict
select case when
       (select count(*) from pg_class c join pg_namespace s on s.oid = c.relnamespace
         where s.nspname = 'public' and c.relname in ('email_open_token', 'email_open_event') and c.relrowsecurity) = 2
   and (select count(*) from pg_policies where schemaname = 'public' and tablename in ('email_open_token', 'email_open_event')) = 2
   and not has_table_privilege('anon', 'public.email_open_event', 'select')
   and not has_table_privilege('authenticated', 'public.email_open_token', 'select')
   and not exists (select 1 from unnest(array['public.fn_invite_open_share()', 'public.fn_invite_open_token(bigint)',
                         'public.fn_email_open_record(text,text,text)', 'public.fn_invite_open_funnel(timestamptz,timestamptz)',
                         'public.fn_invite_opened_not_registered(integer)', 'public.fn_invite_open_summary(timestamptz,timestamptz)']) s(sig)
                    where has_function_privilege('anon', s.sig, 'execute') or has_function_privilege('authenticated', s.sig, 'execute')
                       or not exists (select 1 from pg_proc where oid = s.sig::regprocedure and proconfig::text like '%search_path=public%'))
   and public.fn_invite_open_arm('1', 0) = false and public.fn_invite_open_arm('1', 100) = true
   and (select classification from public.fn_email_open_classify('Mozilla/5.0', null, 3600)) = 'machine_prefetch'
   and (select count(*) from public.app_secrets where key in ('invite_open_tracking', 'email_open_ip_salt') and coalesce(value, '') <> '') = 2
   and (select count(*) from public.table_export_registry where table_name in ('email_open_token', 'email_open_event') and exported) = 2
   and public.fn_marketing_report_figures(now() - interval '1 day', now()) -> 'measured' ? 'invitation_opens'
   and public.fn_ceo_seat_board(7) #> '{seats,marketing,achievement}' ? 'invitation_opens'
  then 'PROBE OK' else 'PROBE FAILED: the open tables, their policies or grants, the routines'' grants and search_path, the switch, the registry rows, or the report and board keys' end as verdict;
