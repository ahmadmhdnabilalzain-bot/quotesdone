-- THE CEO HOLDS THE SUPPLIER TARGET AND ACTS, WITHIN BOUNDED POWERS.          seat: ceo · 2 Nov 2026 · ledger 1436, 1438, 1448, 1449
--
-- Founder, ledger 1438: "I just give targets, and the company needs to reach that target ... The plan goes to the CEO and
-- the CEO acts." Measured by the audit of 2 Nov (docs/reports/WHOLE_PICTURE_AUDIT_2_NOV.md, item 1): no fn_ceo_* routine
-- wrote a cap, a lead or a channel switch, and nobody could resume the invitations after a pause.
--
-- What this file builds:
--   ceo_supplier_goal            the live target: 300-400 registered (registration submitted) by 31 Dec 2026
--   ceo_supplier_funnel_daily    sent, delivered, replied, started, submitted, approved, per channel, per Dubai day
--   ceo_supplier_channel         every channel, its measured state, what it needs. On only with a measured send path
--   ceo_invite_trade_priority    the trades the CEO put first in the invitation queue
--   ceo_growth_action            every decision: reason, before, after, baseline, measured effect, verdict
--   fn_ceo_growth_decide         the pure decision (IMMUTABLE, replayed by the check)
--   fn_ceo_growth_act            the daily seat duty: measure, review what it did, decide, act
--   fn_ceo_daily_number_report   the one message to the founder, through founder_mail_policy
--
-- THE BOUNDS, in the order they win:
--   1. The bounce and complaint brakes. A brake reading can only lower. The sender's own brakes are untouched.
--   2. Ledger 1455 ("The cap, you are more aware about it than me"): the cap is this seat's decision on measured health.
--      fn_invite_founder_cap is now the dated schedule of ledger 1231 or the CEO's ceiling, whichever is higher. The ceiling
--      rises 10 at a time, at most weekly, on 14 clean days only, and comes back if the next reading is bad.
--   3. Ledger 1312: the placement gate stays in the sender; a resume needs at least one mailbox class open.
--   4. Ledger 1456: no ads and no boosted content. The register holds no ad channel. Nothing here can spend.
--   5. WhatsApp opens only on opt-ins, an approved template and a HIGH reading, each measured (ledger 1373, Meta policy).
--   6. No demo lead, no message to a supplier: this file writes settings, ranks and directives. The sender sends.
--
-- SWITCHES, BOTH DEFAULT OFF:
--   app_secrets.ceo_growth_act_golive     off: every decision is logged applied=false and nothing changes
--   app_secrets.ceo_daily_number_golive   off: the report text is built and returned, no mail is queued
-- app_secrets.invite_reachable_only is the CEO's own lever, seeded false, read by the invitation queue.
--
-- Measured 2 Nov 2026 (read-only), for the reachability rule: bounced of sent, by lead email check, all time:
-- unchecked 5 of 18 (27.8%); verified 1 of 22; true 1 of 9; maps 0 of 2; social 0 of 1. Checked together 2 of 34 (5.9%).
-- Small numbers, every one of them Google-class mail, because Google is the only class the placement gate has open.
--
-- prevented by: scripts/checks/the_ceo_acts_on_the_supplier_target_and_writes_its_effects.test.mjs

-- 1. THE TARGET -----------------------------------------------------------------------------------------------------
create table if not exists public.ceo_supplier_goal (
  goal text primary key,
  target_low integer not null,
  target_high integer not null,
  due_on date not null,
  counts_as text not null,
  ruling text not null,
  set_at timestamptz not null default now()
);
alter table public.ceo_supplier_goal enable row level security;
drop policy if exists ceo_supplier_goal_service_role_only on public.ceo_supplier_goal;
create policy ceo_supplier_goal_service_role_only on public.ceo_supplier_goal as permissive for all to public using (false) with check (false);
revoke all on public.ceo_supplier_goal from anon, authenticated;
insert into public.ceo_supplier_goal (goal, target_low, target_high, due_on, counts_as, ruling)
values ('suppliers_registered_2026', 300, 400, date '2026-12-31', 'leads.registration_submitted_at set on a real lead',
        'ledger 1436: 300-400 registrations by end of year without risking the email being blocked; ledger 1438: the CEO acts')
on conflict (goal) do nothing;

-- 2. THE FUNNEL -----------------------------------------------------------------------------------------------------
create table if not exists public.ceo_supplier_funnel_daily (
  day date not null,
  channel text not null,
  sent integer not null default 0,
  delivered integer not null default 0,   -- sent less a recorded bounce. No provider delivery receipt exists on the Microsoft 365 lane
  replied integer not null default 0,
  started integer not null default 0,
  submitted integer not null default 0,
  approved integer not null default 0,
  measured_at timestamptz not null default now(),
  primary key (day, channel)
);
alter table public.ceo_supplier_funnel_daily enable row level security;
drop policy if exists ceo_supplier_funnel_daily_service_role_only on public.ceo_supplier_funnel_daily;
create policy ceo_supplier_funnel_daily_service_role_only on public.ceo_supplier_funnel_daily as permissive for all to public using (false) with check (false);
revoke all on public.ceo_supplier_funnel_daily from anon, authenticated;

create or replace function public.fn_ceo_supplier_funnel_refresh(p_from date)
returns integer language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_n int;
begin
  delete from public.ceo_supplier_funnel_daily where day >= p_from;
  with real_lead as (
    select l.id, l.invite_status, l.owner_email_verified, l.claimed, l.invite_clicked_at, l.portal_updated_at,
           l.registration_submitted_at, l.approved_at,
           coalesce((select case when n.type = 'supplier_invite_wa' then 'whatsapp' else 'email' end from public.notifications n
                      where n.lead_id = l.id and n.type in ('supplier_invite', 'supplier_invite_wa') and n.status = 'sent'
                      order by n.sent_at limit 1), 'direct') as channel
      from public.leads l
     where not coalesce(l.is_demo, false) and coalesce(l.company_name, '') not ilike 'ZZ DEMO%'
       and not public.fn_is_demo_email(coalesce(l.email, ''))
       and (l.invite_status is not null or l.claimed or l.registration_submitted_at is not null or l.approved_at is not null)
  ), ev as (
    select (n.sent_at at time zone 'Asia/Dubai')::date as day,
           case when n.type = 'supplier_invite_wa' then 'whatsapp' else 'email' end as channel,
           1 as sent, case when r.invite_status = 'bounced' then 0 else 1 end as delivered, 0 as replied, 0 as started, 0 as submitted, 0 as approved
      from public.notifications n join real_lead r on r.id = n.lead_id
     where n.type in ('supplier_invite', 'supplier_invite_nudge', 'supplier_invite_wa') and n.status = 'sent' and n.sent_at is not null
    union all
    -- one reply per lead per day. ponytail: email replies only; a WhatsApp reply becomes an invite.reply handoff and is counted once that channel has run.
    select d.day, r.channel, 0, 0, 1, 0, 0, 0
      from (select distinct i.lead_id, (i.created_at at time zone 'Asia/Dubai')::date as day from public.inbound_messages i
             where i.lead_id is not null and coalesce(i.from_email, '') not ilike '%@quotesdone.com'
               and coalesce(i.from_email, '') not ilike '%@mail.quotesdone.com') d
      join real_lead r on r.id = d.lead_id
    union all
    select (coalesce(r.invite_clicked_at, r.portal_updated_at) at time zone 'Asia/Dubai')::date, r.channel, 0, 0, 0, 1, 0, 0
      from real_lead r where (r.owner_email_verified or coalesce(r.claimed, false)) and coalesce(r.invite_clicked_at, r.portal_updated_at) is not null
    union all
    select (r.registration_submitted_at at time zone 'Asia/Dubai')::date, r.channel, 0, 0, 0, 0, 1, 0 from real_lead r where r.registration_submitted_at is not null
    union all
    select (r.approved_at at time zone 'Asia/Dubai')::date, r.channel, 0, 0, 0, 0, 0, 1 from real_lead r where r.approved_at is not null
  ), ins as (
    insert into public.ceo_supplier_funnel_daily (day, channel, sent, delivered, replied, started, submitted, approved)
    select e.day, e.channel, sum(e.sent), sum(e.delivered), sum(e.replied), sum(e.started), sum(e.submitted), sum(e.approved)
      from ev e where e.day >= p_from group by e.day, e.channel
    returning 1)
  select count(*) into v_n from ins;
  return v_n;
end $fn$;
revoke execute on function public.fn_ceo_supplier_funnel_refresh(date) from public, anon, authenticated;

-- 3. THE CHANNELS ---------------------------------------------------------------------------------------------------
create table if not exists public.ceo_supplier_channel (
  channel text primary key,
  owner_seat text not null,
  switch_key text,
  ceo_may_open boolean not null default false,
  rule text not null,
  access_needed text,
  state text not null default 'not_measured' check (state in ('not_measured', 'on', 'paused', 'ready', 'blocked', 'missing')),
  state_why text,
  measured jsonb not null default '{}'::jsonb,
  measured_at timestamptz
);
alter table public.ceo_supplier_channel enable row level security;
drop policy if exists ceo_supplier_channel_service_role_only on public.ceo_supplier_channel;
create policy ceo_supplier_channel_service_role_only on public.ceo_supplier_channel as permissive for all to public using (false) with check (false);
revoke all on public.ceo_supplier_channel from anon, authenticated;
insert into public.ceo_supplier_channel (channel, owner_seat, switch_key, ceo_may_open, rule, access_needed) values
  ('email_supplier_mailbox', 'customer_support', 'invite_enabled', true,
   'One mailbox, supplier@quotesdone.com, Microsoft 365 lane. Ledger 1455 ceiling; ledger 1312 placement gate; bounce and complaint brakes.',
   'A paid email-verification vendor key, to check the 14,202 unchecked eligible leads. Cost quoted first.'),
  ('whatsapp_opt_in', 'marketing', 'wa_supplier_invite_golive', true,
   'Meta WhatsApp Business Messaging Policy: only a person who gave the number and agreed to our messages; honour every stop. Ledger 1341: the button or a yes to the consent question. Never a scraped number.',
   'None to run. The Twilio key reading the sender rating is proved by the first reading.'),
  ('email_extra_mailboxes', 'it_engineer', null, false,
   'The lane reads one mailbox setting; no rotation is built. Each mailbox would need its own warm-up and placement test, and a rotation built in the lane.',
   'An M365 admin sign-in to add mailboxes; DNS host sign-in if a new subdomain is used.'),
  ('phone_outbound', 'sales_engineer', null, false,
   'No outbound routine exists; voice_otp hangs up. UAE Cabinet Resolution 56 of 2024: 09:00-18:00, consent, the Do Not Call Registry, a recorded and identified call. Whether it binds business-to-business calls was not confirmed from the official text.',
   'A company UAE number that is not the founder''s mobile, with Twilio regulatory approval; the official telemarketing registration requirement confirmed.'),
  ('supplier_referral', 'sales_engineer', null, false,
   'A registered supplier invites others in its trade. Not built, and it has nothing to run on: 0 registered suppliers on 2 Nov. It takes an ask at approval, a code recorded at registration, and a count per referrer. The supplier sends it, so no scraped address is used.',
   null),
  ('organic_social', 'marketing', null, false,
   'Company page posts through Postiz on the monthly calendar: reaches followers, contacts nobody directly. Ledger 1456: never boosted.',
   null),
  ('linkedin_manual', 'marketing', null, false,
   'Automated LinkedIn messaging is forbidden by its User Agreement and is not built. The daily target list needs a person to send.',
   'A person with admin of the QuotesDone company page.')
on conflict (channel) do update set owner_seat = excluded.owner_seat, ceo_may_open = excluded.ceo_may_open, rule = excluded.rule,
  access_needed = excluded.access_needed, switch_key = excluded.switch_key;

create or replace function public.fn_ceo_supplier_channel_measure()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_secret jsonb := (select jsonb_object_agg(key, value) from public.app_secrets
                      where key in ('invite_enabled', 'invite_m365_enabled', 'invite_m365_mailbox', 'wa_supplier_invite_golive'));
  v_open text[] := public.fn_invite_placement_open_providers((now() at time zone 'Asia/Dubai')::date);
  v_sent7 int; v_optins int; v_tmpl int; v_q public.wa_sender_quality_reading; v_brake boolean; v_posts int; v_wa_why text[] := '{}';
begin
  select count(*) into v_sent7 from public.notifications where type = 'supplier_invite' and status = 'sent' and sent_at > now() - interval '7 days';
  select count(*) into v_optins from public.supplier_whatsapp_optin o join public.leads l on l.id = o.lead_id where not coalesce(l.is_demo, false);
  select count(*) into v_tmpl from public.messaging_template where template_key = 'supplier_invite' and channel = 'whatsapp' and status = 'approved';
  select * into v_q from public.wa_sender_quality_reading order by read_at desc, id desc limit 1;
  v_brake := exists (select 1 from public.it_watch_finding f where f.detector_key = 'deliverability:supplier_invite_wa' and f.status = 'open');
  select count(*) into v_posts from public.marketing_post where status = 'published' and created_at > now() - interval '30 days';

  update public.ceo_supplier_channel set measured_at = now(),
    state = case when v_secret->>'invite_enabled' = 'true' and cardinality(v_open) > 0 and v_sent7 > 0 then 'on' else 'paused' end,
    state_why = format('invite_enabled %s; placement open for %s; %s sent in 7 days from %s', v_secret->>'invite_enabled', coalesce(array_to_string(v_open, ', '), 'none'), v_sent7, v_secret->>'invite_m365_mailbox'),
    measured = jsonb_build_object('open_classes', to_jsonb(v_open), 'sent_7d', v_sent7)
   where channel = 'email_supplier_mailbox';

  if v_optins = 0 then v_wa_why := v_wa_why || 'no opt-in on record'::text; end if;
  if v_tmpl = 0 then v_wa_why := v_wa_why || 'template supplier_invite is not approved'::text; end if;
  if v_q.id is null or v_q.read_at < now() - interval '26 hours' then v_wa_why := v_wa_why || 'no sender reading in 26 hours'::text;
  elsif not v_q.ok then v_wa_why := v_wa_why || ('sender reads ' || coalesce(v_q.rating, 'unknown') || ' / ' || v_q.status); end if;
  if v_brake then v_wa_why := v_wa_why || 'the brake finding is open'::text; end if;
  if v_secret->>'invite_enabled' is distinct from 'true' then v_wa_why := v_wa_why || 'the email channel is paused, and WhatsApp never runs ahead of it'::text; end if;
  update public.ceo_supplier_channel set measured_at = now(),
    state = case when cardinality(v_wa_why) > 0 then 'blocked' when v_secret->>'wa_supplier_invite_golive' = 'true' then 'on' else 'ready' end,
    state_why = coalesce(nullif(array_to_string(v_wa_why, '; '), ''), 'every condition is measured true'),
    measured = jsonb_build_object('opt_ins', v_optins, 'template_approved', v_tmpl > 0, 'reading', v_q.rating, 'read_at', v_q.read_at, 'brake', v_brake)
   where channel = 'whatsapp_opt_in';

  update public.ceo_supplier_channel set measured_at = now(), state = 'missing',
    state_why = 'no send path: the lane reads one mailbox setting', measured = jsonb_build_object('mailboxes_in_the_lane', 1) where channel = 'email_extra_mailboxes';
  update public.ceo_supplier_channel set measured_at = now(), state = 'missing',
    state_why = 'no outbound call routine exists', measured = '{}'::jsonb where channel = 'phone_outbound';
  update public.ceo_supplier_channel set measured_at = now(), state = 'missing',
    state_why = 'not built; no registered supplier yet to refer', measured = '{}'::jsonb where channel = 'supplier_referral';
  update public.ceo_supplier_channel set measured_at = now(), state = case when v_posts > 0 then 'on' else 'paused' end,
    state_why = format('%s posts published in 30 days', v_posts), measured = jsonb_build_object('published_30d', v_posts) where channel = 'organic_social';
  update public.ceo_supplier_channel set measured_at = now(), state = 'missing',
    state_why = 'the target list is built; no person sends it', measured = '{}'::jsonb where channel = 'linkedin_manual';

  return (select jsonb_object_agg(channel, jsonb_build_object('state', state, 'why', state_why)) from public.ceo_supplier_channel);
end $fn$;
revoke execute on function public.fn_ceo_supplier_channel_measure() from public, anon, authenticated;

-- 4. THE TARGET'S STATUS, AND THE CAP IT NEEDS -------------------------------------------------------------------------
create or replace function public.fn_ceo_supplier_goal_status(p_at timestamptz default now())
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  g public.ceo_supplier_goal; v_today date := (p_at at time zone 'Asia/Dubai')::date;
  f record; v_left int; v_room bigint; v_start numeric; v_del numeric; v_need bigint; v_cap_need int;
begin
  select * into g from public.ceo_supplier_goal where goal = 'suppliers_registered_2026';
  select coalesce(sum(sent), 0) sent, coalesce(sum(delivered), 0) delivered, coalesce(sum(replied), 0) replied, coalesce(sum(started), 0) started,
         coalesce(sum(submitted), 0) submitted, coalesce(sum(approved), 0) approved
    into f from public.ceo_supplier_funnel_daily;
  -- the sending days left, and what the founder's dated schedule allows on them
  select count(*), coalesce(sum(public.fn_invite_founder_cap(d::date)), 0) into v_left, v_room
    from generate_series(v_today, g.due_on, interval '1 day') d
   where extract(isodow from d) < 6
     and not exists (select 1 from public.company_calendar c where c.kind = 'public_holiday' and d::date between c.starts_on and coalesce(c.ends_on, c.starts_on));
  v_del := case when f.sent > 0 then f.delivered::numeric / f.sent end;
  v_start := case when f.delivered > 0 then f.started::numeric / f.delivered end;
  -- no submission has ever been measured, so a start stands in for a registration: the most this can read, never a forecast
  if v_start > 0 and v_del > 0 then
    v_need := ceil(greatest(0, g.target_low - f.submitted) / v_start / v_del);
    v_cap_need := ceil(v_need::numeric / greatest(v_left, 1));
  end if;
  return jsonb_build_object('goal', g.goal, 'target_low', g.target_low, 'target_high', g.target_high, 'due_on', g.due_on,
    'funnel_to_date', to_jsonb(f), 'registered', f.submitted, 'approved', f.approved,
    'sending_days_left', v_left, 'schedule_room_sends', v_room,
    'delivered_rate', round(v_del, 3), 'start_rate_of_delivered', round(v_start, 4),
    'sends_needed_for_low_target', v_need, 'cap_the_target_needs_per_day', v_cap_need,
    'most_reachable_at_the_measured_rate', case when v_start > 0 and v_del > 0 then floor(v_room * v_del * v_start) + f.submitted end,
    'basis', 'starts stand in for registrations until a submission is measured; n is small');
end $fn$;
revoke execute on function public.fn_ceo_supplier_goal_status(timestamptz) from public, anon, authenticated;

-- 5. THE TRADE PRIORITY AND THE ACTION LOG ------------------------------------------------------------------------------
create table if not exists public.ceo_invite_trade_priority (
  id bigint generated always as identity primary key,
  trade text not null,
  reason text not null,
  set_at timestamptz not null default now(),
  cleared_at timestamptz,
  cleared_why text
);
create unique index if not exists ceo_invite_trade_priority_one_live on public.ceo_invite_trade_priority (trade) where cleared_at is null;
alter table public.ceo_invite_trade_priority enable row level security;
drop policy if exists ceo_invite_trade_priority_service_role_only on public.ceo_invite_trade_priority;
create policy ceo_invite_trade_priority_service_role_only on public.ceo_invite_trade_priority as permissive for all to public using (false) with check (false);
revoke all on public.ceo_invite_trade_priority from anon, authenticated;

create table if not exists public.ceo_growth_action (
  id bigint generated always as identity primary key,
  decided_on date not null,
  power text not null check (power in ('run', 'cap', 'ceiling', 'reachable', 'trade', 'channel', 'directive')),
  subject text not null,
  before_value text,
  after_value text,
  reason text not null,
  applied boolean not null default false,
  baseline jsonb not null default '{}'::jsonb,
  review_on date,
  effect jsonb,
  verdict text not null default 'pending' check (verdict in ('pending', 'not_applied', 'worked', 'failed', 'rolled_back', 'no_signal', 'recorded')),
  reviewed_at timestamptz,
  dedupe_key text not null unique,
  created_at timestamptz not null default now()
);
create index if not exists ceo_growth_action_due on public.ceo_growth_action (review_on) where verdict = 'pending';
alter table public.ceo_growth_action enable row level security;
drop policy if exists ceo_growth_action_service_role_only on public.ceo_growth_action;
create policy ceo_growth_action_service_role_only on public.ceo_growth_action as permissive for all to public using (false) with check (false);
revoke all on public.ceo_growth_action from anon, authenticated;

insert into public.app_secrets (key, value) values
  ('invite_ceo_ceiling', '0'), ('ceo_growth_act_golive', 'false'), ('ceo_daily_number_golive', 'false'), ('invite_reachable_only', 'false')
on conflict (key) do nothing;

insert into public.ceo_decision (decision_key, domain, decision, trigger_condition, measure, measure_sql, authority, evidence_required, cadence, active) values
  ('supplier_growth', 'operations', 'Move the invitation cap, the lead order, a channel or a seat toward the supplier target, inside the bounded powers.',
   'The daily reading of the funnel, the brakes and the channels calls for a change.',
   'Registered suppliers against 300-400 by 31 Dec 2026.', null, 'ceo_alone',
   'The reason, the value before and after, and the reading at the time.', 'daily', true),
  ('supplier_growth_effect', 'operations', 'Measure what a supplier growth decision did, and take it back if it did not work.',
   'A decision reaches its review date.',
   'Share of applied decisions that worked.', null, 'ceo_alone',
   'The reading at review, the verdict, and any roll back.', 'daily', true)
on conflict (decision_key) do nothing;

-- THE CEILING (ledger 1455, superseding the end of ledger 1231's "until we reach 50"). The dated weeks stay as the floor of the
-- ceiling; invite_ceo_ceiling is written only by fn_ceo_growth_act, on measured health. Every sender and the ramp read this one routine.
create or replace function public.fn_invite_schedule_cap(p_day date)
returns integer language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case
    when p_day < date '2026-10-26' then 20
    when p_day < date '2026-11-02' then 30
    when p_day < date '2026-11-09' then 40
    else 50
  end;
$fn$;
revoke execute on function public.fn_invite_schedule_cap(date) from public, anon, authenticated;
create or replace function public.fn_invite_founder_cap(p_day date)
returns integer language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select greatest(public.fn_invite_schedule_cap(p_day),
                  coalesce((select nullif(value, '')::int from public.app_secrets where key = 'invite_ceo_ceiling'), 0));
$fn$;

-- 6. WHAT THE CEO READS --------------------------------------------------------------------------------------------------
-- p_light skips the two scans of the eligible pool (7 s each, measured 2 Nov), for a directive's done test, read on every directive run.
create or replace function public.fn_ceo_growth_reading(p_at timestamptz default now(), p_light boolean default false)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_today date := (p_at at time zone 'Asia/Dubai')::date;
  v_set jsonb := (select jsonb_object_agg(key, value) from public.app_secrets
                   where key in ('invite_enabled', 'invite_daily_cap', 'invite_max_bounce_rate', 'invite_reachable_only', 'wa_supplier_invite_golive'));
  v_open text[] := public.fn_invite_placement_open_providers(v_today);
  v_cls text[] := array['verified', 'true', 'maps', 'social'];
  s record; c record; h record; v_all int; v_share numeric; v_ceil_last date; v_ceil_bad boolean; v_compl48 int; v_compl7 int; v_pool int; v_pause timestamptz; v_stuck int; v_unans int; v_opt int; v_tmpl boolean; v_q public.wa_sender_quality_reading; v_wa_brake boolean;
begin
  select count(*) sent, count(*) filter (where l.invite_status = 'bounced') bounced
    into s from public.notifications n join public.leads l on l.id = n.lead_id
   where n.type = 'supplier_invite' and n.status = 'sent' and n.sent_at > p_at - interval '7 days'
     and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(coalesce(l.email, ''));
  -- group per class, all time: n is what makes the class readable
  select count(*) filter (where l.email_verified is null or not (l.email_verified = any (v_cls))) unchecked_sent,
         count(*) filter (where (l.email_verified is null or not (l.email_verified = any (v_cls))) and l.invite_status = 'bounced') unchecked_bounced
    into c from public.notifications n join public.leads l on l.id = n.lead_id
   where n.type = 'supplier_invite' and n.status = 'sent' and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(coalesce(l.email, ''));
  select count(*) filter (where invited_at > p_at - interval '48 hours'), count(*) into v_compl48, v_compl7
    from public.leads where invite_status = 'complained' and invited_at > p_at - interval '7 days' and not coalesce(is_demo, false);
  if not p_light then
    select count(*) filter (where l.email_verified = any (v_cls)), count(*) into v_pool, v_all from public.leads l
     where l.id in (select public.fn_supplier_invite_eligible_ids()) and public.fn_mail_provider_of_email(l.email) = any (v_open);
    v_share := round(100.0 * v_pool / greatest(v_all, 1), 1);
  end if;
  -- ONLY THE CEO'S OWN PAUSE MAY BE LIFTED: its close row must be the last write to invite_enabled in the audit log. A brake's pause
  -- is restarted by sales_engineer.invite_restart; a pause by hand, or anyone's write after the close, is never lifted here.
  select a.created_at into v_pause from public.ceo_growth_action a
   where a.power = 'channel' and a.subject = 'email_supplier_mailbox' and a.after_value = 'close' and a.applied
     and a.created_at >= (select max(l.at) from public.security_audit_log l where l.table_name = 'app_secrets' and l.row_pk = 'invite_enabled') - interval '1 minute'
   order by a.id desc limit 1;
  select count(*) sent, count(*) filter (where l.invite_status = 'bounced') bounced into h from public.notifications n join public.leads l on l.id = n.lead_id
   where n.type = 'supplier_invite' and n.status = 'sent' and n.sent_at > p_at - interval '14 days' and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(coalesce(l.email, ''));
  select max(a.decided_on) filter (where a.applied), coalesce(bool_or(a.verdict in ('failed', 'rolled_back') and a.decided_on > v_today - 30), false) into v_ceil_last, v_ceil_bad
    from public.ceo_growth_action a where a.power = 'ceiling';
  select count(*) into v_stuck from public.leads l
   where (l.owner_email_verified or coalesce(l.claimed, false)) and l.registration_submitted_at is null
     and coalesce(l.portal_updated_at, l.invite_clicked_at) < p_at - interval '3 days'
     and not coalesce(l.is_demo, false) and coalesce(l.company_name, '') not ilike 'ZZ DEMO%' and not public.fn_is_demo_email(coalesce(l.email, ''));
  select count(distinct i.lead_id) into v_unans from public.inbound_messages i join public.leads l on l.id = i.lead_id
   where i.replied_at is null and i.created_at between p_at - interval '30 days' and p_at - interval '1 day'
     and coalesce(i.from_email, '') not ilike '%quotesdone.com' and l.invite_status is not null and not coalesce(l.is_demo, false);
  select count(*) into v_opt from public.supplier_whatsapp_optin o join public.leads l on l.id = o.lead_id where not coalesce(l.is_demo, false);
  v_tmpl := exists (select 1 from public.messaging_template where template_key = 'supplier_invite' and channel = 'whatsapp' and status = 'approved');
  select * into v_q from public.wa_sender_quality_reading order by read_at desc, id desc limit 1;
  v_wa_brake := exists (select 1 from public.it_watch_finding f where f.detector_key = 'deliverability:supplier_invite_wa' and f.status = 'open');
  return jsonb_build_object(
    'day', v_today, 'sent_7d', s.sent, 'bounced_7d', s.bounced, 'bounce_rate_7d', case when s.sent >= 15 then round(s.bounced::numeric / s.sent, 4) end,
    'complained_48h', v_compl48, 'complained_7d', v_compl7,
    'max_bounce', coalesce(nullif(v_set->>'invite_max_bounce_rate', '')::numeric, 0.03),
    'invite_enabled', v_set->>'invite_enabled' = 'true', 'cur_cap', coalesce(nullif(v_set->>'invite_daily_cap', '')::int, 10),
    'founder_cap', public.fn_invite_founder_cap(v_today),
    'open_classes', cardinality(v_open), 'reachable_only', v_set->>'invite_reachable_only' = 'true',
    'unchecked_sent', c.unchecked_sent, 'unchecked_bounced', c.unchecked_bounced, 'checked_pool_open', v_pool,
    'sent_14d', h.sent, 'bounced_14d', h.bounced, 'ceiling_days_since', v_today - v_ceil_last, 'ceiling_failed_recently', v_ceil_bad, 'checked_share_pct', v_share,
    'own_pause_days_ago', case when v_pause is not null then v_today - (v_pause at time zone 'Asia/Dubai')::date end,
    -- A REOPEN THAT FAILED HOLDS UNTIL HEALTH MOVES: a class opened, or the checked share of the pool rose 5 points, against every earlier reopen
    'resume_held_same_health', exists (select 1 from public.ceo_growth_action a where a.power = 'channel' and a.subject = 'email_supplier_mailbox' and a.after_value = 'open' and a.applied
                                        and not (cardinality(v_open) > coalesce((a.baseline->>'open_classes')::int, 0)
                                                 or coalesce(v_share, 0) >= coalesce((a.baseline->>'checked_share_pct')::numeric, 0) + 5)),
    'wa_golive', v_set->>'wa_supplier_invite_golive' = 'true', 'wa_opt_ins', v_opt, 'wa_template_approved', v_tmpl,
    'wa_reading_ok', v_q.id is not null and v_q.read_at > p_at - interval '26 hours' and v_q.ok, 'wa_brake', v_wa_brake,
    'started_stuck', v_stuck, 'replied_unanswered', v_unans,
    -- the trades already marked for recruitment, widest reachable pool first, past a recent failure
    'trade_live', (select count(*) from public.ceo_invite_trade_priority where cleared_at is null),
    'trade_candidates', case when p_light then '[]'::jsonb else coalesce((select jsonb_agg(x.tr) from (
        select t.tr from public.leads l cross join lateral unnest(coalesce(l.invite_trades, '{}'::text[])) t(tr)
         where l.id in (select public.fn_supplier_invite_eligible_ids()) and l.email_verified = any (v_cls)
           and public.fn_mail_provider_of_email(l.email) = any (v_open)
           and exists (select 1 from public.supply_gap g where g.trade = t.tr and g.status = 'recruit')
           and not exists (select 1 from public.ceo_invite_trade_priority p where p.trade = t.tr
                            and (p.cleared_at is null or p.cleared_at > p_at - interval '30 days'))
         group by t.tr order by count(*) desc, t.tr limit 5) x), '[]'::jsonb) end);
end $fn$;
revoke execute on function public.fn_ceo_growth_reading(timestamptz, boolean) from public, anon, authenticated;

-- 7. THE DECISION. PURE: the same reading gives the same actions, and the check replays it. ----------------------------------
create or replace function public.fn_ceo_growth_decide(r jsonb)
returns jsonb language plpgsql immutable set search_path to 'public', 'pg_temp' as $fn$
declare
  a jsonb := '[]'::jsonb;
  v_max numeric := (r->>'max_bounce')::numeric;
  v_rate numeric := (r->>'bounce_rate_7d')::numeric;       -- null under 15 sends: not a rate
  v_cur int := (r->>'cur_cap')::int; v_founder int := (r->>'founder_cap')::int;
  v_brake boolean := coalesce((r->>'complained_48h')::int, 0) >= 1 or coalesce(v_rate > v_max, false);
  v_healthy boolean := v_rate is not null and v_rate < 0.02 and coalesce((r->>'complained_7d')::int, 0) = 0;
  v_enabled boolean := (r->>'invite_enabled')::boolean;
  v_reach boolean := (r->>'reachable_only')::boolean;
  v_un_sent int := coalesce((r->>'unchecked_sent')::int, 0);
  v_un_rate numeric := case when v_un_sent >= 10 then (r->>'unchecked_bounced')::numeric / v_un_sent end;
  v_room int := greatest(0, 5 - coalesce((r->>'trade_live')::int, 0));
  v_resume boolean := false; t text;
begin
  -- CAP. Above the founder's schedule always comes down; a brake halves; only clean mail raises, one step, never past the schedule.
  if v_cur > v_founder then
    a := a || jsonb_build_object('power', 'cap', 'subject', 'invite_daily_cap', 'to', v_founder, 'review_days', 3,
      'reason', format('ledger 1455: the cap %s is above the ceiling %s', v_cur, v_founder));
  elsif v_brake and v_cur > 1 then
    a := a || jsonb_build_object('power', 'cap', 'subject', 'invite_daily_cap', 'to', greatest(1, v_cur / 2), 'review_days', 3,
      'reason', format('brake: %s bounced of %s in 7 days against a limit of %s, %s complaints in 48 hours', r->>'bounced_7d', r->>'sent_7d', v_max, r->>'complained_48h'));
  elsif v_healthy and v_enabled and v_cur < v_founder then
    a := a || jsonb_build_object('power', 'cap', 'subject', 'invite_daily_cap', 'to', least(v_founder, v_cur + 10), 'review_days', 3,
      'reason', format('clean: %s bounced of %s in 7 days, no complaint; the ceiling allows %s', r->>'bounced_7d', r->>'sent_7d', v_founder));
  elsif not v_brake and v_enabled and v_cur >= v_founder and coalesce((r->>'sent_14d')::int, 0) >= 100
        and (r->>'bounced_14d')::numeric / nullif((r->>'sent_14d')::numeric, 0) < 0.01 and coalesce((r->>'complained_7d')::int, 0) = 0
        and coalesce((r->>'open_classes')::int, 0) > 0 and coalesce((r->>'checked_pool_open')::int, 0) >= v_cur * 10
        and coalesce((r->>'ceiling_days_since')::int, 999) >= 7 and not coalesce((r->>'ceiling_failed_recently')::boolean, false) then
    -- LEDGER 1455: on measured health alone, in small steps
    a := a || jsonb_build_object('power', 'ceiling', 'subject', 'invite_ceo_ceiling', 'to', v_founder + 10, 'review_days', 3,
      'reason', format('14 clean days: %s bounced of %s, no complaint, ten days of checked leads', r->>'bounced_14d', r->>'sent_14d'));
  end if;

  -- REACHABILITY. Unchecked addresses stop when their own measured rate is over the limit, and return only when it is not.
  if not v_reach and coalesce(v_un_rate > v_max, false) then
    a := a || jsonb_build_object('power', 'reachable', 'subject', 'invite_reachable_only', 'to', true, 'review_days', 7,
      'reason', format('unchecked leads bounced %s of %s; only checked addresses go until the list is cleaned', r->>'unchecked_bounced', v_un_sent));
  elsif v_reach and coalesce((r->>'checked_pool_open')::int, 0) < v_cur * 5 and coalesce(v_un_rate <= v_max, false) then
    a := a || jsonb_build_object('power', 'reachable', 'subject', 'invite_reachable_only', 'to', false, 'review_days', 7,
      'reason', format('fewer than five days of checked leads remain (%s) and unchecked leads now bounce within the limit', r->>'checked_pool_open'));
  end if;

  -- TRADES. Inside the queue's recruitment tier, the trades with the widest reachable pool go first.
  for t in select value from jsonb_array_elements_text(coalesce(r->'trade_candidates', '[]'::jsonb)) limit v_room loop
    a := a || jsonb_build_object('power', 'trade', 'subject', t, 'to', 'first', 'review_days', 14,
      'reason', format('%s is marked for recruitment and has one of the widest reachable pools', t));
  end loop;

  -- EMAIL. The CEO's own close may be lifted: 7 days on, placement open, only checked addresses, no complaint, and health moved since any earlier reopen.
  v_resume := not v_enabled and (r->>'own_pause_days_ago')::int >= 7 and coalesce((r->>'open_classes')::int, 0) > 0
              and v_reach and coalesce((r->>'complained_7d')::int, 0) = 0 and not coalesce(v_rate > v_max, false)
              and not coalesce((r->>'resume_held_same_health')::boolean, false);
  if v_resume then
    a := a || jsonb_build_object('power', 'channel', 'subject', 'email_supplier_mailbox', 'to', 'open', 'review_days', 7,
      'reason', format('the CEO closed this %s days ago, the window is clean, only checked addresses go', r->>'own_pause_days_ago'));
    if v_cur > 10 then
      a := a || jsonb_build_object('power', 'cap', 'subject', 'invite_daily_cap', 'to', 10, 'review_days', 3, 'reason', 'a resume restarts low: the domain cooled during the pause');
    end if;
  elsif v_enabled and coalesce((r->>'sent_7d')::int, 0) >= 30 and coalesce(v_rate > 2 * v_max, false) then
    a := a || jsonb_build_object('power', 'channel', 'subject', 'email_supplier_mailbox', 'to', 'close', 'review_days', 7,
      'reason', format('bounces %s of %s are over twice the limit: ledger 1449, the mailbox is not risked', r->>'bounced_7d', r->>'sent_7d'));
  end if;

  -- WHATSAPP. Open on opt-ins, an approved template, a good reading and no brake, each measured. Close the moment one fails.
  if not (r->>'wa_golive')::boolean and v_enabled and (r->>'wa_opt_ins')::int > 0 and (r->>'wa_template_approved')::boolean
     and (r->>'wa_reading_ok')::boolean and not (r->>'wa_brake')::boolean then
    a := a || jsonb_build_object('power', 'channel', 'subject', 'whatsapp_opt_in', 'to', 'open', 'review_days', 7,
      'reason', format('%s opt-ins, template approved, sender reads HIGH, no brake (ledger 1373)', r->>'wa_opt_ins'));
  elsif (r->>'wa_golive')::boolean and ((r->>'wa_brake')::boolean or not (r->>'wa_reading_ok')::boolean) then
    a := a || jsonb_build_object('power', 'channel', 'subject', 'whatsapp_opt_in', 'to', 'close', 'review_days', 7,
      'reason', 'the WhatsApp brake is open or the sender no longer reads HIGH');
  end if;

  -- DIRECTIVES. Each carries a done test the routine reads; a directive repeats until the test is true.
  if coalesce(v_un_rate > v_max, false) or coalesce(v_rate > v_max, false) then
    a := a || jsonb_build_object('power', 'directive', 'subject', 'bounce_within_limit', 'seat', 'it_engineer', 'days', 7,
      'instruction', 'Bring invitation bounces within the limit: run the free list checks (syntax, typo domains, MX, not_found) over the eligible pool, and name what a paid check would add.',
      'done_when', 'the 7-day invitation bounce rate reads within invite_max_bounce_rate',
      'done_sql', $q$coalesce((public.fn_ceo_growth_reading(now(), true)->>'bounce_rate_7d')::numeric <= (public.fn_ceo_growth_reading(now(), true)->>'max_bounce')::numeric, false)$q$,
      'reason', format('7-day %s of %s; unchecked all-time %s of %s', r->>'bounced_7d', r->>'sent_7d', r->>'unchecked_bounced', v_un_sent));
  end if;
  if coalesce((r->>'started_stuck')::int, 0) > 0 then
    a := a || jsonb_build_object('power', 'directive', 'subject', 'started_not_submitted', 'seat', 'sales_engineer', 'days', 3,
      'instruction', 'A supplier started registration and stopped more than 3 days ago: chase each one to submission.',
      'done_when', 'no real supplier has been started and unsubmitted for over 3 days',
      'done_sql', $q$(public.fn_ceo_growth_reading(now(), true)->>'started_stuck')::int = 0$q$,
      'reason', format('%s started and stopped', r->>'started_stuck'));
  end if;
  if coalesce((r->>'replied_unanswered')::int, 0) > 0 then
    a := a || jsonb_build_object('power', 'directive', 'subject', 'reply_unanswered', 'seat', 'sales_engineer', 'days', 2,
      'instruction', 'An invited supplier replied and has not been answered: answer each one.',
      'done_when', 'no invited supplier''s reply has waited over a day in 30 days',
      'done_sql', $q$(public.fn_ceo_growth_reading(now(), true)->>'replied_unanswered')::int = 0$q$,
      'reason', format('%s replies unanswered', r->>'replied_unanswered'));
  end if;
  if (r->>'wa_opt_ins')::int = 0 then
    a := a || jsonb_build_object('power', 'directive', 'subject', 'whatsapp_opt_ins', 'seat', 'sales_engineer', 'days', 14,
      'instruction', 'Ask the consent question (fn_wa_consent_question) of each supplier who is already in conversation with us, and record each yes with fn_supplier_whatsapp_optin_record. Never message a number to ask it.',
      'done_when', 'at least one real opt-in is on record',
      'done_sql', $q$(public.fn_ceo_growth_reading(now(), true)->>'wa_opt_ins')::int > 0$q$,
      'reason', 'WhatsApp has no opt-in, so it has nobody it may message');
  end if;
  return a;
end $fn$;
revoke execute on function public.fn_ceo_growth_decide(jsonb) from public, anon, authenticated;

-- 8. MEASURING WHAT IT DID, AND TAKING BACK WHAT DID NOT WORK ---------------------------------------------------------------
create or replace function public.fn_ceo_growth_review(p_at timestamptz, p_reading jsonb, p_apply boolean)
returns integer language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  x public.ceo_growth_action; v_verdict text; v_effect jsonb; v_today date := (p_at at time zone 'Asia/Dubai')::date; v_n int := 0;
  v_rate numeric := (p_reading->>'bounce_rate_7d')::numeric; v_max numeric := (p_reading->>'max_bounce')::numeric;
  v_bad boolean := coalesce(v_rate > v_max, false) or coalesce((p_reading->>'complained_48h')::int, 0) >= 1;
  v_sent int; v_replied int; v_started int; v_base numeric; v_paused boolean;
begin
  for x in select * from public.ceo_growth_action where verdict = 'pending' and applied and review_on <= v_today order by id for update loop
    v_effect := jsonb_build_object('read_on', v_today, 'bounce_rate_7d', v_rate, 'sent_7d', p_reading->'sent_7d', 'complained_48h', p_reading->'complained_48h');
    v_base := (x.baseline->>'bounce_rate_7d')::numeric;
    if x.power = 'ceiling' then
      if v_bad then
        if p_apply then
          update public.app_secrets set value = x.before_value where key = 'invite_ceo_ceiling';
          update public.app_secrets set value = jsonb_set(value::jsonb, '{ceiling_cap}', to_jsonb(x.before_value::int))::text where key = 'invite_warmup';
          update public.app_secrets set value = least(value::int, public.fn_invite_founder_cap(v_today))::text where key = 'invite_daily_cap';
        end if;
        v_verdict := 'rolled_back';
      else
        v_verdict := 'worked';
      end if;
    elsif x.power = 'cap' and x.after_value::int > coalesce(x.before_value::int, 0) then
      if v_bad then
        if p_apply then update public.app_secrets set value = least(x.before_value::int, public.fn_invite_founder_cap(v_today))::text where key = 'invite_daily_cap'; end if;
        v_verdict := 'rolled_back';
      else
        v_verdict := case when (p_reading->>'sent_7d')::int > coalesce((x.baseline->>'sent_7d')::int, 0) then 'worked' else 'no_signal' end;
      end if;
    elsif x.power = 'cap' then
      v_verdict := case when v_rate is null then 'no_signal' when v_rate <= coalesce(v_base, v_max) then 'worked' else 'failed' end;
    elsif x.power = 'reachable' then
      v_verdict := case when v_rate is null then 'no_signal' when v_rate <= v_max then 'worked' else 'failed' end;
    elsif x.power = 'trade' then
      select count(*) filter (where n.status = 'sent'), count(distinct i.lead_id), count(distinct l.id) filter (where l.owner_email_verified or coalesce(l.claimed, false))
        into v_sent, v_replied, v_started
        from public.notifications n join public.leads l on l.id = n.lead_id
        left join public.inbound_messages i on i.lead_id = l.id and i.created_at >= x.created_at
       where n.type = 'supplier_invite' and n.created_at >= x.created_at and x.subject = any (coalesce(l.invite_trades, '{}'::text[]));
      v_effect := v_effect || jsonb_build_object('trade_sent', v_sent, 'trade_replied', v_replied, 'trade_started', v_started);
      if v_sent >= 20 and v_replied = 0 and v_started = 0 then
        if p_apply then update public.ceo_invite_trade_priority set cleared_at = p_at, cleared_why = '20 or more sent, no reply and no start' where trade = x.subject and cleared_at is null; end if;
        v_verdict := 'rolled_back';
      else
        v_verdict := case when v_replied > 0 or v_started > 0 then 'worked' else 'no_signal' end;
      end if;
    elsif x.power = 'channel' and x.subject = 'email_supplier_mailbox' and x.after_value = 'open' then
      v_paused := not (p_reading->>'invite_enabled')::boolean;
      v_verdict := case when v_paused then 'failed' when v_rate is null then 'no_signal' else 'worked' end;   -- a brake already paused it
    elsif x.power = 'channel' and x.subject = 'whatsapp_opt_in' and x.after_value = 'open' then
      if (p_reading->>'wa_brake')::boolean or not (p_reading->>'wa_reading_ok')::boolean then
        if p_apply then update public.app_secrets set value = 'false' where key = 'wa_supplier_invite_golive'; end if;
        v_verdict := 'rolled_back';
      else
        v_verdict := 'worked';
      end if;
    else
      v_verdict := 'recorded';
    end if;
    -- SWITCH OFF: nothing was undone, so nothing reads rolled back. The action stays pending for the day the switch is on.
    if v_verdict = 'rolled_back' and not p_apply then
      update public.ceo_growth_action set effect = v_effect || jsonb_build_object('would_roll_back', true) where id = x.id;
      continue;
    end if;
    update public.ceo_growth_action set effect = v_effect, verdict = v_verdict, reviewed_at = p_at where id = x.id;
    perform public.fn_ceo_plan_log('supplier_growth_effect', 'supplier_growth_effect:' || x.id,
      format('%s %s -> %s: %s. Read: bounce %s, sent %s in 7 days.', x.power, x.subject, x.after_value, v_verdict, coalesce(v_rate::text, 'not a rate'), p_reading->>'sent_7d'),
      jsonb_build_object('action_id', x.id, 'reason', x.reason, 'effect', v_effect, 'verdict', v_verdict));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $fn$;
revoke execute on function public.fn_ceo_growth_review(timestamptz, jsonb, boolean) from public, anon, authenticated;

-- 9. THE DAILY ACT --------------------------------------------------------------------------------------------------------
create or replace function public.fn_ceo_growth_act(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_local timestamp := p_at at time zone 'Asia/Dubai'; v_today date := v_local::date;
  v_apply boolean := coalesce((select value from public.app_secrets where key = 'ceo_growth_act_golive'), '') = 'true';
  v_read jsonb; v_goal jsonb; v_channels jsonb; v_actions jsonb; d jsonb; v_reviewed int; v_written int := 0; v_applied int := 0;
  v_before text; v_after text; v_founder int; v_dedupe text; v_round int; v_dir bigint; v_ok boolean;
begin
  if v_local::time < time '06:00' then return jsonb_build_object('ok', true, 'ran', false, 'reason', 'before 06:00 Dubai'); end if;
  if exists (select 1 from public.ceo_growth_action where dedupe_key = 'run:' || v_today) then
    return jsonb_build_object('ok', true, 'ran', false, 'reason', 'today''s decision exists');
  end if;

  perform public.fn_ceo_supplier_funnel_refresh(date '2026-01-01');   -- whole history: a late bounce or a backfill changes an old day, and totals sum it
  v_channels := public.fn_ceo_supplier_channel_measure();
  v_read := public.fn_ceo_growth_reading(p_at);
  v_goal := public.fn_ceo_supplier_goal_status(p_at);
  v_reviewed := public.fn_ceo_growth_review(p_at, v_read, v_apply);
  v_actions := public.fn_ceo_growth_decide(v_read);
  v_founder := (v_read->>'founder_cap')::int;

  for d in select value from jsonb_array_elements(v_actions) loop
    v_ok := v_apply; v_before := null; v_after := d->>'to'; v_dir := null;
    case d->>'power'
    when 'cap' then
      v_before := v_read->>'cur_cap';
      v_after := least((d->>'to')::int, v_founder)::text;     -- the ceiling, whatever the decision said
      if v_apply then update public.app_secrets set value = v_after where key = 'invite_daily_cap'; end if;
    when 'ceiling' then
      v_before := v_read->>'founder_cap';
      v_after := least((d->>'to')::int, v_founder + 10)::text;     -- one small step, whatever the decision said
      if v_apply then
        update public.app_secrets set value = v_after where key = 'invite_ceo_ceiling';
        update public.app_secrets set value = jsonb_set(value::jsonb, '{ceiling_cap}', to_jsonb(v_after::int))::text where key = 'invite_warmup';   -- the ramp reads both
      end if;
    when 'reachable' then
      v_before := v_read->>'reachable_only';
      if v_apply then update public.app_secrets set value = v_after where key = 'invite_reachable_only'; end if;
    when 'trade' then
      if v_apply then insert into public.ceo_invite_trade_priority (trade, reason) values (d->>'subject', d->>'reason') on conflict do nothing; end if;
    when 'channel' then
      if d->>'subject' = 'email_supplier_mailbox' then
        v_before := v_read->>'invite_enabled';
        if v_apply and d->>'to' = 'open' then
          update public.app_secrets set value = 'true' where key = 'invite_enabled';
        elsif v_apply then
          perform public.fn_invite_campaign_pause('ceo_growth', d->>'reason', jsonb_build_object('reading', v_read), jsonb_build_object('paused', true));
        end if;
      else
        v_before := v_read->>'wa_golive';
        if v_apply then update public.app_secrets set value = case when d->>'to' = 'open' then 'true' else 'false' end where key = 'wa_supplier_invite_golive'; end if;
      end if;
    when 'directive' then
      -- REPEATS UNTIL CLOSED: an open directive is left to run; once it is closed unmet the next round goes out under a new ref.
      if v_apply and not exists (select 1 from public.ceo_directive c where c.source_kind = 'target_miss' and c.source_ref like 'supplier_growth:' || (d->>'subject') || ':%' and c.status = 'open') then
        select count(*) + 1 into v_round from public.ceo_directive c where c.source_kind = 'target_miss' and c.source_ref like 'supplier_growth:' || (d->>'subject') || ':%';
        v_dir := public.fn_ceo_directive_issue(d->>'seat', 'target_miss', 'supplier_growth:' || (d->>'subject') || ':' || v_round,
                   d->>'instruction', d->>'done_when', d->>'done_sql', p_at + make_interval(days => (d->>'days')::int), jsonb_build_object('reason', d->>'reason', 'round', v_round));
      end if;
      v_ok := v_dir is not null;
      v_after := coalesce(v_dir::text, 'no new round');
    end case;

    v_dedupe := (d->>'power') || ':' || (d->>'subject') || ':' || v_today;
    insert into public.ceo_growth_action (decided_on, power, subject, before_value, after_value, reason, applied, baseline, review_on, verdict, dedupe_key)
    values (v_today, d->>'power', d->>'subject', v_before, v_after, d->>'reason', v_ok, v_read - 'trade_candidates',
            case when v_ok and d ? 'review_days' then v_today + (d->>'review_days')::int end,
            case when d->>'power' = 'directive' and v_ok then 'recorded' when v_ok then 'pending' else 'not_applied' end, v_dedupe)
    on conflict (dedupe_key) do nothing;
    v_written := v_written + 1; v_applied := v_applied + v_ok::int;
    perform public.fn_ceo_plan_log('supplier_growth', 'supplier_growth:' || v_dedupe,
      format('%s %s: %s -> %s. %s%s', d->>'power', d->>'subject', coalesce(v_before, '-'), v_after, d->>'reason', case when v_ok then '' else ' (not applied)' end),
      jsonb_build_object('action', d, 'applied', v_ok, 'reading', v_read - 'trade_candidates'));
  end loop;

  -- the run itself is a row, so a day with nothing to change still proves the CEO looked
  insert into public.ceo_growth_action (decided_on, power, subject, reason, applied, baseline, effect, verdict, dedupe_key)
  values (v_today, 'run', 'daily', format('%s decisions, %s applied, %s reviewed; switch %s', v_written, v_applied, v_reviewed, case when v_apply then 'on' else 'off' end),
          v_apply, v_read - 'trade_candidates', jsonb_build_object('goal', v_goal, 'channels', v_channels), 'recorded', 'run:' || v_today);
  return jsonb_build_object('ok', true, 'ran', true, 'switch_on', v_apply, 'decisions', v_written, 'applied', v_applied, 'reviewed', v_reviewed,
                            'registered', v_goal->'registered', 'cap_the_target_needs_per_day', v_goal->'cap_the_target_needs_per_day');
end $fn$;
revoke execute on function public.fn_ceo_growth_act(timestamptz) from public, anon, authenticated;

-- 10. THE ONE MESSAGE -----------------------------------------------------------------------------------------------------
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role)
values ('ceo_daily_number', true, 'Ledger 1438: he gives targets and reads one number a day. One message: sent, replied, registered, approved.', 'ceo')
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason, owner_role = excluded.owner_role;

create or replace function public.fn_ceo_daily_number_text(p_day date)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select format('Yesterday: %s sent, %s replied, %s registered, %s approved. Total so far: %s registered, %s approved, against 300-400 registered by 31 Dec.',
    coalesce(sum(f.sent) filter (where f.day = p_day), 0), coalesce(sum(f.replied) filter (where f.day = p_day), 0),
    coalesce(sum(f.submitted) filter (where f.day = p_day), 0), coalesce(sum(f.approved) filter (where f.day = p_day), 0),
    coalesce(sum(f.submitted), 0), coalesce(sum(f.approved), 0))
  from public.ceo_supplier_funnel_daily f
$fn$;
revoke execute on function public.fn_ceo_daily_number_text(date) from public, anon, authenticated;

create or replace function public.fn_ceo_daily_number_report(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_local timestamp := p_at at time zone 'Asia/Dubai'; v_day date := v_local::date - 1; v_text text; v_key text := 'ceo_daily_number:' || v_local::date; v_res jsonb;
begin
  if v_local::time < time '08:00' then return jsonb_build_object('ok', true, 'sent', false, 'reason', 'before 08:00 Dubai'); end if;
  if exists (select 1 from public.founder_alerts where dedupe_key = v_key and channel = 'email') then
    return jsonb_build_object('ok', true, 'sent', false, 'reason', 'today''s message is out');
  end if;
  perform public.fn_ceo_supplier_funnel_refresh(date '2026-01-01');
  v_text := public.fn_ceo_daily_number_text(v_day);
  if coalesce((select value from public.app_secrets where key = 'ceo_daily_number_golive'), '') <> 'true' then
    return jsonb_build_object('ok', true, 'sent', false, 'reason', 'ceo_daily_number_golive is off', 'would_say', v_text);
  end if;
  -- level info: fn_notify_founder sends WhatsApp only from high up, so this is one message, by email
  v_res := public.fn_notify_founder('Suppliers: the daily number', v_text, 'info', 'ceo_daily_number', v_key, 'ceo');
  return jsonb_build_object('ok', true, 'sent', coalesce((v_res->>'emailed')::boolean, false), 'text', v_text);
end $fn$;
revoke execute on function public.fn_ceo_daily_number_report(timestamptz) from public, anon, authenticated;

-- the funnel starts whole
select public.fn_ceo_supplier_funnel_refresh(date '2026-01-01');

-- 11. THE CLOCK -----------------------------------------------------------------------------------------------------------
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.supplier_growth', 'ceo', interval '1 hour', 'fn_ceo_growth_act',
   'Once a Dubai day from 06:00: refresh the funnel, measure the channels, review what the CEO changed and roll back what failed, decide and act within the bounded powers. Off (logged, not applied) until ceo_growth_act_golive. Ledger 1438.',
   'scripts/sql/the_ceo_holds_the_supplier_target_and_acts_within_bounded_powers.sql'),
  ('ceo.daily_number', 'ceo', interval '1 hour', 'fn_ceo_daily_number_report',
   'Once a Dubai day from 08:00: one message to the founder: sent, replied, registered, approved. Off until ceo_daily_number_golive.',
   'scripts/sql/the_ceo_holds_the_supplier_target_and_acts_within_bounded_powers.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

insert into public.resilience_step (step, every, budget_ms, place, rank, note) values
  ('waSenderQuality', interval '12 hours', 9000, 'plan', 0,
   'Reads the WhatsApp sender''s Meta quality rating through send_whatsapp. Read only, no message. Without it the supplier invitation gate waits for a reading only a queued invitation could cause.')
on conflict (step) do update set every = excluded.every, budget_ms = excluded.budget_ms, note = excluded.note;

-- 12. THE QUEUE READS THE CEO'S TWO LEVERS. Unchanged while invite_reachable_only is false and no trade is listed. -----------
CREATE OR REPLACE FUNCTION public.fn_supplier_invite_candidates(p_limit integer, p_providers text[])
 RETURNS TABLE(lead_id bigint, to_email text, company_name text, lang text, subject text, body text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_site text; v_target int;
  v_reach boolean := coalesce((select value from app_secrets where key = 'invite_reachable_only'), '') = 'true';
  v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  select value into v_subj    from app_secrets where key = 'invite_subject';
  select value into v_body    from app_secrets where key = 'invite_body';
  -- 27 Oct 2026: the founder's invitation carries no link ("safer to not send links"); a supplier registers at
  -- quotesdone.com or replies. Only an EMPTY template is refused now. A template that still has {{link}} is filled.
  if btrim(coalesce(v_body, '')) = '' then
    raise exception 'app_secrets.invite_body is empty: no invitation is built from nothing';
  end if;
  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_category'),
                       (select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 10);

  -- MATERIALIZED, 4 Aug 2026, and it is load-bearing (see enqueue_supplier_invites' history): both
  -- CTEs are read from a correlated subquery and would otherwise be recomputed per candidate.
  return query
  with activated as materialized (
    select ls.domain_slug, count(distinct l.id) ct
    from leads l join lead_subcategory ls on ls.lead_id = l.id
    where coalesce(l.claimed,false) = true
    group by ls.domain_slug
  ),
  under as materialized (
    select d.slug as domain_slug, coalesce(a.ct,0) as have
    from catalog_domains d left join activated a on a.domain_slug = d.slug
    where coalesce(a.ct,0) < v_target
  ),
  -- ONE COMPANY, ONE INVITATION (24 Sep 2026, marketing). A company is its email domain, unless the domain is
  -- a shared mailbox provider (gmail, emirates.net.ae ...: measured as a domain carrying 3+ different company
  -- names), where it is the address itself; and, independently, its normalised company name.
  shared as materialized (
    select split_part(lower(btrim(l.email)), '@', 2) as dom from leads l where coalesce(btrim(l.email), '') <> ''
    group by 1 having count(distinct lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g'))) >= 3
  ),
  keyed as materialized (
    select l.id,
           case when s.dom is null then split_part(lower(btrim(l.email)), '@', 2) else lower(btrim(l.email)) end as dkey,
           nullif(lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g')), '') as nkey,
           (l.invite_status is not null or l.invited_at is not null or coalesce(l.claimed, false)) as touched
    from leads l left join shared s on s.dom = split_part(lower(btrim(l.email)), '@', 2)
    where coalesce(btrim(l.email), '') <> ''
  ),
  touched_d as materialized (select distinct dkey from keyed where touched),
  touched_n as materialized (select distinct nkey from keyed where touched and nkey is not null),
  -- instr 1013: marketing's ranking of the trades below ten suppliers (the ranking orders the queue; since 27 Oct 2026
  -- every row stores the one approved text, not a per-trade variant)
  plans as materialized (select p.trade, p.emirate, p.rank from public.marketing_gap_recruitment_plan p),
  -- 29 Sep 2026 (ledger 1018): the trades and areas of the open, real stalled-request rescues (public.stalled_inquiry_rescue).
  -- A fixture rescue never moves the real queue.
  rescue as materialized (select x.trades, x.emirate from public.stalled_inquiry_rescue x where x.cleared_at is null and not x.fixture and cardinality(x.trades) > 0),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified,
           l.invite_trades, l.emirate, k.dkey, k.nkey, ec.mailbox,
           -- ALWAYS ENGLISH (24 Sep 2026, ledger 993 item 4; #1065): suppliers are always written in English.
           'en'::text as lang
    from leads l join keyed k on k.id = l.id left join public.lead_email_check ec on ec.lead_id = l.id
    where l.id in (select e.id from public.fn_supplier_invite_eligible_ids() e(id))   -- the set, read once (see header)
      -- 27 Oct 2026 (it_engineer): only recipients whose mailbox class passed the GlockApps verdict; null = every class
      and (p_providers is null or public.fn_mail_provider_of_email(l.email) = any(p_providers))
      -- 2 Nov 2026 (ceo, ledger 1438, 1449): the CEO's reachability lever; unchecked addresses wait while it is on
      and (not v_reach or l.email_verified in ('verified', 'true', 'maps', 'social'))
      -- a company already invited (bounced, unsubscribed or registered included) is not invited again at another address
      and not exists (select 1 from touched_d t where t.dkey = k.dkey)
      and (k.nkey is null or not exists (select 1 from touched_n t where t.nkey = k.nkey))
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain, c.lang, c.dkey, c.nkey,
      -- 29 Sep 2026 (ledger 1018): ahead of every tier below, a lead in the trade and area of a stalled request a customer waits on.
      -- 23 Sep 2026: a lead in a trade the sales engineer marked for recruitment (supply_gap 'recruit') goes first;
      -- 29 Sep 2026 (instr 1013): then a lead in any trade marketing planned, by the plan's rank.
      case when exists (select 1 from rescue x where x.trades && coalesce(c.invite_trades, '{}'::text[])
                          and (x.emirate is null or x.emirate = 'UAE' or x.emirate = c.emirate)) then -1
           when exists (select 1 from public.supply_gap g where g.status = 'recruit' and g.trade = any(coalesce(c.invite_trades, '{}'::text[]))
                          and (g.emirate = 'UAE' or g.emirate = c.emirate)) then 0
           when pl.rank is not null then 1 else 2 end as target_rank,
      -- 2 Nov 2026 (ceo): a trade the CEO put first leads inside its tier; a stalled request's rescue still comes before it
      case when exists (select 1 from public.ceo_invite_trade_priority t where t.cleared_at is null and t.trade = any(coalesce(c.invite_trades, '{}'::text[])))
           then -1 else coalesce(pl.rank, 2147483647) end as plan_rank,
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      -- THE LIKELIEST MAILBOX FIRST (2 Nov 2026, ledger 1449). Measured on the 52 real sends: proven 'verified' 1 bounce of 22,
      -- proven 'true' 1 of 9, unproven role address 0 of 2, unproven named address 5 of 16. So an unproven info@ goes before
      -- an unproven named address (this used to be the other way round), and free mail last. ponytail: small sample, re-read at 200.
      case when c.email_verified in ('verified','true') then 0 when c.mailbox = 'free' then 3 when c.mailbox = 'role' then 1 else 2 end as mailbox_rank
    from cand c
    left join lateral (select p.rank from plans p
                        where p.trade = any(coalesce(c.invite_trades, '{}'::text[])) and (p.emirate = 'UAE' or p.emirate = c.emirate)
                        order by p.rank limit 1) pl on true
  ),
  elig as (
    select r.id, r.email, r.company_name, r.claim_token, r.lang from (
      select p.*,
        case when p.pdomain='~none' then 1 else 0 end as is_none,
        row_number() over (partition by p.pdomain order by p.mailbox_rank, p.id) as rk,
        row_number() over (partition by coalesce(p.email_domain, split_part(p.email,'@',2)) order by p.mailbox_rank, p.id) as domain_rk,
        -- the best contact per company, by mailbox_rank. ponytail: a lead that wins one key and loses the other waits a day.
        row_number() over (partition by p.dkey order by p.mailbox_rank, p.id) as company_rk,
        row_number() over (partition by coalesce(p.nkey, p.email) order by p.mailbox_rank, p.id) as name_rk
      from prio p
    ) r
    where r.domain_rk <= 5 and r.company_rk = 1 and r.name_rk = 1
    order by r.target_rank, r.plan_rank, r.mailbox_rank, r.is_none, r.rk, r.pdomain
    limit greatest(coalesce(p_limit, 0), 0)
  )
  select e.id, btrim(e.email), e.company_name, e.lang, v_subj,
         -- an Arabic-script company name is not written into an English letter (the 29 Sep probe found 11 of 200);
         -- with no usable name the greeting is the neutral "Hello," the Microsoft 365 lane also sends
         -- (a template that still carries {{link}} is filled as before; the approved one has none)
         replace(replace(case when n.nm = '' then replace(v_body, 'Hi {{company}} team,', 'Hello,') else v_body end,
                         '{{company}}', case when n.nm = '' then 'there' else n.nm end),
                 '{{link}}', public.fn_supplier_invite_link(v_site, e.claim_token, e.id))
  from elig e
  cross join lateral (select coalesce(nullif(btrim(case when e.company_name ~ '[؀-ۿ]' then '' else e.company_name end), ''), '') as nm) n;
end
$function$;
