-- THE SUPPLIER WHATSAPP INVITATION WAITS FOR AN OPT-IN, BOTH SWITCHES AND A HIGH-QUALITY SENDER, AND CARRIES NO LINK.
-- Seat: marketing (with sales_engineer, who receives the replies). 27 Oct 2026. Founder ledger 1184 (12 Oct): "use every
-- safe channel beyond email (WhatsApp, LinkedIn, others) ... nothing that risks bans"; 1301: "safer to not send links";
-- 1312: the supplier campaign is PAUSED until a GlockApps test shows Outlook >= 80% inbox.
--
-- MEASURED 27 Oct 2026 (production, read-only):
--   * #1511 WAS merged (through integration PR #1496, 19 Oct) and its file is MANIFEST line 2082. The brief's "never
--     merged" was a misreading of the closed-not-merged PR; app_secrets.wa_supplier_invite_golive = 'false' is the
--     founder's switch, not a missing merge.
--   * Nothing calls fn_wa_supplier_invite_queue: no cron job, no seat duty. Switching it on would have queued nothing.
--   * The 'supplier_invite' template was never submitted (no messaging_template row). Its text carried a claim link.
--   * The queue selected 2,857 leads whose only WhatsApp fact is a UAE mobile published on a business listing. 0 of
--     2,863 such leads have marketing_consent, 0 have wa_optin, 0 have ever written to our WhatsApp number.
--
-- WHY THE OPT-IN RULE (the ban risk the founder asked us to avoid). Meta's WhatsApp Business Messaging Policy lets a
-- business message a person only after that person gave the business their number AND opted in to receive its
-- messages. A number scraped from a map listing is neither. Messaging 2,857 such numbers is exactly the traffic that
-- collects blocks and reports, drops the quality rating, cuts the messaging limit and can disconnect the ONE number
-- customer support and the founder's alerts run on. So this file makes an opt-in a hard condition, and the pool is 0
-- today. The channel fills from opt-ins the company collects safely: a supplier who writes to our WhatsApp first
-- (wa_inbound records it), a supplier who asks for WhatsApp in an email reply or on a call (the sales engineer records
-- it with fn_supplier_whatsapp_optin_record), the website form. docs/marketing/supplier_channels_beyond_email.md.
--
-- WHAT THIS CHANGES
--   1. public.supplier_whatsapp_optin: one row per lead and number with its source and evidence. Service role only.
--   2. public.wa_sender_quality_reading: Meta's quality rating for our sender as Twilio reports it (send_whatsapp reads
--      it at most once an hour, only while it is about to send a marketing message). Service role only.
--   3. fn_wa_sender_quality_record: stores a reading; anything but ONLINE + HIGH (or GREEN) applies the brake.
--   4. fn_wa_supplier_invite_brake: THE BRAKE. Opens it_watch_finding 'deliverability:supplier_invite_wa' (it_engineer
--      owns it), cancels every invitation still queued, logs agent_runs. It never touches app_secrets: the founder's
--      switches stay his. Resuming = resolving the finding after reading it.
--   5. fn_wa_supplier_invite_gate(p_at): the one place the rules live. Go only when wa_supplier_invite_golive AND
--      invite_enabled are 'true', no brake is open, a quality reading under 26 hours old says HIGH/ONLINE, it is a
--      weekday (Mon-Fri) 10:00-16:59 Dubai and not a public holiday, and the 7-day STOP rate is under the line (>= 2
--      opt-outs and >= 5% of the invitations sent in 7 days applies the brake).
--   6. fn_wa_supplier_invite_queue(p_limit, p_at, p_demo_only): replaces the 19 Oct two-argument routine (dropped
--      here: one signature, so a call is never ambiguous). Opt-in required; one invitation per lead AND per number for
--      life (a second message is never sent; a reply goes to a person instead); at most 20 a Dubai day; ordered by
--      marketing's gap ranking; the stored body is the template text with no link. p_demo_only = true selects ONLY
--      demo leads (ZZ DEMO / example.invalid), so a probe is incapable of reaching a real person.
--   7. fn_marketing_wa_supplier_invites(): the hourly seat duty marketing.whatsapp_supplier_invites. Harmless while
--      either switch is off: the gate says no and nothing is written.
--   8. fn_marketing_files_wa_invite_reply(p_from, p_body): wa_inbound calls it for every non-STOP message. A number
--      that is a lead's records an 'inbound_whatsapp' opt-in; an invited lead with no company page yet is handed to the
--      sales engineer as 'invite.reply' (the same conversation the email reply files, channel 'whatsapp').
--   9. fn_supplier_whatsapp_optin_record(p_lead_id, p_source, p_evidence): how the sales engineer records an opt-in.
--  10. fn_marketing_supplier_outreach_targets(p_per_trade) + seat duty marketing.manual_outreach_targets (daily): the
--      per-trade list for MANUAL outreach on LinkedIn / Instagram / Facebook from the company's own accounts: uninvited,
--      unsuppressed, not opted out, with the public profile links we already hold. It contacts nobody; no scraping.
-- NOT CHANGED: fn_wa_supplier_invite_opt_out (19 Oct file) and the STOP path; the email lane; any app_secrets value.
-- Apply at merge, after send_whatsapp / wa_inbound / wa_template_setup are deployed. Never before (ledger 1312 pause).
-- Prevented by: scripts/checks/the_supplier_whatsapp_invitation_waits_for_opt_in_and_both_switches.test.mjs and
-- supabase/functions/_shared/marketing_send_gate.test.ts.

-- 1. opt-ins
create table if not exists public.supplier_whatsapp_optin (
  id bigint generated always as identity primary key,
  lead_id bigint not null references public.leads(id) on delete cascade,
  phone text not null check (phone ~ '^\+[0-9]{8,15}$'),
  source text not null check (source in ('inbound_whatsapp', 'email_reply', 'sales_engineer', 'web_form')),
  evidence text not null check (btrim(evidence) <> ''),
  opted_in_at timestamptz not null default now(),
  unique (lead_id, phone)
);
create index if not exists supplier_whatsapp_optin_phone_idx on public.supplier_whatsapp_optin (phone);
alter table public.supplier_whatsapp_optin enable row level security;
drop policy if exists supplier_whatsapp_optin_service_role_only on public.supplier_whatsapp_optin;
create policy supplier_whatsapp_optin_service_role_only on public.supplier_whatsapp_optin
  as permissive for all to public using (false) with check (false);
revoke all on public.supplier_whatsapp_optin from anon, authenticated;

-- 2. sender quality readings
create table if not exists public.wa_sender_quality_reading (
  id bigint generated always as identity primary key,
  read_at timestamptz not null default now(),
  rating text,
  status text not null,
  messaging_limit text,
  ok boolean not null,
  raw jsonb not null default '{}'::jsonb
);
create index if not exists wa_sender_quality_reading_read_at_idx on public.wa_sender_quality_reading (read_at desc);
alter table public.wa_sender_quality_reading enable row level security;
drop policy if exists wa_sender_quality_reading_service_role_only on public.wa_sender_quality_reading;
create policy wa_sender_quality_reading_service_role_only on public.wa_sender_quality_reading
  as permissive for all to public using (false) with check (false);
revoke all on public.wa_sender_quality_reading from anon, authenticated;

-- 4. the brake (defined before 3, which calls it)
create or replace function public.fn_wa_supplier_invite_brake(p_why text, p_evidence jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_cancelled int;
begin
  update public.notifications set status = 'cancelled', last_error = left('brake: ' || p_why, 500)
   where type = 'supplier_invite_wa' and status in ('queued', 'sending');
  get diagnostics v_cancelled = row_count;
  insert into public.it_watch_finding (detector_key, detector, subject, state, severity, title, evidence)
  values ('deliverability:supplier_invite_wa', 'deliverability', 'supplier_invite_wa', 'paused', 'high',
          left('Supplier WhatsApp invitations braked: ' || p_why, 300),
          coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object('cancelled_queued', v_cancelled,
            'resume', 'read the reason, then resolve this finding (status resolved); the switches are untouched'))
  on conflict (detector_key) do update
     set state = excluded.state, severity = excluded.severity, title = excluded.title, evidence = excluded.evidence,
         last_seen_at = now(), seen_count = it_watch_finding.seen_count + 1, status = 'open', resolved_at = null;
  insert into public.agent_runs (agent, status, counts, note, finished_at)
  values ('wa_supplier_invite_brake', 'error', jsonb_build_object('cancelled_queued', v_cancelled),
          left('BRAKED: ' || p_why || '; ' || v_cancelled || ' queued WhatsApp invitation(s) cancelled; it_engineer finding open.', 1000), now());
  return jsonb_build_object('braked', true, 'why', p_why, 'cancelled_queued', v_cancelled);
end $fn$;
revoke execute on function public.fn_wa_supplier_invite_brake(text, jsonb) from public, anon, authenticated;

-- 3. a quality reading
create or replace function public.fn_wa_sender_quality_record(p_rating text, p_status text, p_limit text default null,
                                                              p_raw jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_ok boolean := upper(btrim(coalesce(p_status, ''))) = 'ONLINE'
                        and upper(btrim(coalesce(p_rating, ''))) in ('HIGH', 'GREEN');
  v_brake jsonb;
begin
  insert into public.wa_sender_quality_reading (rating, status, messaging_limit, ok, raw)
  values (nullif(btrim(coalesce(p_rating, '')), ''), coalesce(nullif(btrim(coalesce(p_status, '')), ''), 'UNKNOWN'), p_limit, v_ok,
          coalesce(p_raw, '{}'::jsonb));
  if not v_ok then
    v_brake := public.fn_wa_supplier_invite_brake('the sender reads quality ' || coalesce(p_rating, 'unknown') || ' / '
                 || coalesce(p_status, 'unknown') || ', not HIGH / ONLINE',
                 jsonb_build_object('rating', p_rating, 'status', p_status, 'messaging_limit', p_limit));
  end if;
  return jsonb_build_object('ok', v_ok, 'rating', p_rating, 'status', p_status, 'brake', v_brake);
end $fn$;
revoke execute on function public.fn_wa_sender_quality_record(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.fn_wa_sender_quality_record(text, text, text, jsonb) to service_role;

-- 5. the gate
create or replace function public.fn_wa_supplier_invite_gate(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_local timestamp := p_at at time zone 'Asia/Dubai';
  v_why text[] := '{}';
  q public.wa_sender_quality_reading;
  v_sent7 int; v_stops7 int;
begin
  if coalesce((select value from public.app_secrets where key = 'wa_supplier_invite_golive'), '') <> 'true' then
    v_why := array_append(v_why, 'wa_supplier_invite_golive is not true'); end if;
  if coalesce((select value from public.app_secrets where key = 'invite_enabled'), '') <> 'true' then
    v_why := array_append(v_why, 'invite_enabled is not true (the supplier campaign is paused)'); end if;
  if extract(isodow from v_local) not between 1 and 5 then v_why := array_append(v_why, 'not a weekday in Dubai'); end if;
  if extract(hour from v_local) not between 10 and 16 then v_why := array_append(v_why, 'outside 10:00-17:00 Dubai'); end if;
  if exists (select 1 from public.public_holidays h where h.holiday_date = v_local::date) then
    v_why := array_append(v_why, 'a UAE public holiday'); end if;

  -- the STOP-rate brake: opt-outs among the leads invited over WhatsApp in 7 days
  select count(*), count(*) filter (where l.whatsapp_opt = 'none') into v_sent7, v_stops7
    from public.notifications n join public.leads l on l.id = n.lead_id
   where n.type = 'supplier_invite_wa' and n.status = 'sent' and n.sent_at > now() - interval '7 days';
  if v_stops7 >= 2 and v_stops7::numeric >= 0.05 * greatest(v_sent7, 1)
     and not exists (select 1 from public.it_watch_finding f where f.detector_key = 'deliverability:supplier_invite_wa' and f.status = 'open') then
    perform public.fn_wa_supplier_invite_brake(v_stops7 || ' STOP replies on ' || v_sent7 || ' WhatsApp invitations in 7 days',
              jsonb_build_object('sent_7d', v_sent7, 'stops_7d', v_stops7));
  end if;
  if exists (select 1 from public.it_watch_finding f where f.detector_key = 'deliverability:supplier_invite_wa' and f.status = 'open') then
    v_why := array_append(v_why, 'the brake is on (it_watch_finding deliverability:supplier_invite_wa)'); end if;

  select * into q from public.wa_sender_quality_reading order by read_at desc, id desc limit 1;   -- id: ties in one transaction
  if q.id is null or q.read_at < now() - interval '26 hours' then
    v_why := array_append(v_why, 'no sender quality reading in 26 hours');
  elsif not q.ok then
    v_why := array_append(v_why, 'sender quality ' || coalesce(q.rating, 'unknown') || ' / ' || q.status);
  end if;

  return jsonb_build_object('go', cardinality(v_why) = 0, 'why', to_jsonb(v_why), 'dubai_time', v_local,
                            'sent_7d', v_sent7, 'stops_7d', v_stops7);
end $fn$;
revoke execute on function public.fn_wa_supplier_invite_gate(timestamptz) from public, anon, authenticated;

-- 6. the queue (one signature from now on)
drop function if exists public.fn_wa_supplier_invite_queue(int, timestamptz);
create or replace function public.fn_wa_supplier_invite_queue(p_limit int default 20, p_at timestamptz default now(),
                                                              p_demo_only boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  -- THE TEXT: identical to _shared/marketing_send_gate.ts WA_INVITE_TEMPLATE_EN (a check compares them). No link.
  c_text constant text := 'Hello from QuotesDone. We connect companies in the UAE with qualified suppliers: each request for quotation reaches only the suppliers registered for that exact trade. We are now onboarding {{1}} suppliers ahead of our buyer launch. Requests that match your trade come directly to you, you choose which ones to quote on, and there is no commission on work you win. Registration is free for our first 1,000 suppliers. To join, reply with the trades you cover and our team will set up your company page for you, or register at quotesdone.com. If this isn''t relevant, reply STOP and we won''t message you again.';
  v_gate jsonb := public.fn_wa_supplier_invite_gate(p_at);
  v_today int; v_room int; v_eligible int; v_queued int := 0;
begin
  select count(*) into v_today from public.notifications
   where type = 'supplier_invite_wa' and channel = 'whatsapp'
     and (created_at at time zone 'Asia/Dubai')::date = (now() at time zone 'Asia/Dubai')::date;
  v_room := greatest(0, least(coalesce(p_limit, 20), 20) - v_today);

  create temp table if not exists _wa_inv(lead_id bigint, phone text, trade text, rnk int) on commit drop;
  truncate _wa_inv;
  -- Driven from the opt-ins (a handful of rows), never a scan of 20k+ leads: the first draft read every lead and took
  -- 71 s in a rolled-back replay on 27 Oct 2026, past the seat duty tick's 60 s statement timeout.
  -- THE NUMBER IS THE OPTED-IN ONE (independent review of #1634, 27 Oct 2026): an opt-in is a (lead, number) pair and
  -- may name a number other than the lead's phone_e164 (fn_supplier_whatsapp_optin_record's p_phone, or the lead's
  -- whatsapp_phone in fn_marketing_files_wa_invite_reply). The invitation goes to opted.phone, never to a number
  -- nobody opted in from.
  insert into _wa_inv
  select l.id, opted.phone, coalesce(l.invite_trades[1], l.sector), coalesce(p.rank, 2147483647)
    from (select o.lead_id id, o.phone from public.supplier_whatsapp_optin o
           union select x.id, o.phone from public.supplier_whatsapp_optin o join public.leads x on x.phone_e164 = o.phone) opted
    join public.leads l on l.id = opted.id
    left join lateral (select min(g.rank) rank from public.marketing_gap_recruitment_plan g
                        where g.trade = coalesce(l.invite_trades[1], l.sector)) p on true
   where opted.phone ~ '^\+9715[0-9]{8}$'
     -- a STOP from this number on any lead record is an opt-out of the number
     and not exists (select 1 from public.leads y where (y.phone_e164 = opted.phone or y.whatsapp_phone = opted.phone)
                       and y.whatsapp_opt = 'none')
     and (case when p_demo_only then coalesce(l.is_demo, false) else not coalesce(l.is_demo, false) end)
     and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)
     and not coalesce(l.claimed, false) and l.approval_status is null
     and coalesce(l.whatsapp_opt, '') <> 'none'
     and coalesce(l.invite_status, '') not in ('bounced', 'complained', 'unsubscribed')
     and (l.email is null or not exists (select 1 from public.email_suppressions s where lower(s.email) = lower(l.email)))
     -- Meta: only a person who opted in (see header) -- the join on `opted` above is that condition
     -- never twice: once per lead and once per number, for life
     and not exists (select 1 from public.notifications n where n.type = 'supplier_invite_wa' and n.lead_id = l.id)
     and not exists (select 1 from public.notifications n where n.type = 'supplier_invite_wa' and n.to_phone = opted.phone);
  select count(*) into v_eligible from _wa_inv;

  if (v_gate->>'go')::boolean and v_room > 0 then
    with pick as (select * from (select distinct on (phone) * from _wa_inv order by phone, rnk, lead_id) d
                   order by rnk, lead_id limit v_room),
    lbl as (select p.*, coalesce(nullif(left(btrim(lower(regexp_replace(coalesce(p.trade, ''), '[_-]+', ' ', 'g'))), 60), ''), 'new') label
              from pick p)
    -- to_role stays NULL, as in the 19 Oct file: a lead is not yet a supplier. With to_role 'supplier' the confirmed-number
    -- trigger (fn_notifications_whatsapp_goes_to_a_confirmed_number, clause 21) marks the row skipped, because a lead
    -- has no OTP-confirmed WhatsApp number; that rule is for a registered account's notices. Here the number is the one
    -- the lead opted in from (supplier_whatsapp_optin). Measured in a rolled-back replay, 27 Oct 2026.
    insert into public.notifications (type, channel, sender, to_phone, to_role, lead_id, subject, body, status, lang, dedupe_key)
    select 'supplier_invite_wa', 'whatsapp', 'customer_support', b.phone, null, b.lead_id, b.label,
           replace(c_text, '{{1}}', b.label), 'queued', 'en', 'supplier_invite_wa:' || b.lead_id
      from lbl b;
    get diagnostics v_queued = row_count;
  end if;

  return jsonb_build_object('live', (v_gate->>'go')::boolean, 'why', v_gate->'why', 'eligible', v_eligible,
                            'sent_today', v_today, 'room_today', v_room, 'queued', v_queued, 'demo_only', p_demo_only,
                            'dubai_time', v_gate->'dubai_time');
end $fn$;
revoke execute on function public.fn_wa_supplier_invite_queue(int, timestamptz, boolean) from public, anon, authenticated;
grant execute on function public.fn_wa_supplier_invite_queue(int, timestamptz, boolean) to service_role;

-- 7. the hourly duty
create or replace function public.fn_marketing_wa_supplier_invites()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  return public.fn_wa_supplier_invite_queue(20, now(), false);
end $fn$;
revoke execute on function public.fn_marketing_wa_supplier_invites() from public, anon, authenticated;

-- 9. an opt-in the sales engineer records (an email reply or a call that asked for WhatsApp)
create or replace function public.fn_supplier_whatsapp_optin_record(p_lead_id bigint, p_source text, p_evidence text,
                                                                    p_phone text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare l public.leads; v_phone text; v_id bigint;
begin
  select * into l from public.leads where id = p_lead_id;
  if l.id is null then return jsonb_build_object('ok', false, 'reason', 'no such lead'); end if;
  if coalesce(l.whatsapp_opt, '') = 'none' then return jsonb_build_object('ok', false, 'reason', 'the lead opted out of WhatsApp'); end if;
  v_phone := '+' || regexp_replace(coalesce(p_phone, l.phone_e164, ''), '\D', '', 'g');
  if v_phone !~ '^\+[0-9]{8,15}$' then return jsonb_build_object('ok', false, 'reason', 'no usable number'); end if;
  insert into public.supplier_whatsapp_optin (lead_id, phone, source, evidence)
  values (l.id, v_phone, p_source, p_evidence)
  on conflict (lead_id, phone) do nothing
  returning id into v_id;
  return jsonb_build_object('ok', true, 'lead_id', l.id, 'phone', v_phone, 'new', v_id is not null);
end $fn$;
revoke execute on function public.fn_supplier_whatsapp_optin_record(bigint, text, text, text) from public, anon, authenticated;
grant execute on function public.fn_supplier_whatsapp_optin_record(bigint, text, text, text) to service_role;

-- 8. a lead writes to our WhatsApp
create or replace function public.fn_marketing_files_wa_invite_reply(p_from text, p_body text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_phone text := '+' || regexp_replace(coalesce(p_from, ''), '\D', '', 'g');
  v_optins int := 0; l public.leads; v_reply text := btrim(coalesce(p_body, '')); v_id bigint;
begin
  if v_phone !~ '^\+[0-9]{8,15}$' then return jsonb_build_object('due', false, 'reason', 'no number'); end if;
  -- the person wrote first: that is the opt-in Meta asks for, for every lead on this number that has not opted out
  insert into public.supplier_whatsapp_optin (lead_id, phone, source, evidence)
  select x.id, v_phone, 'inbound_whatsapp', 'wrote to the QuotesDone WhatsApp number first at ' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai'
    from public.leads x
   where (x.phone_e164 = v_phone or x.whatsapp_phone = v_phone) and coalesce(x.whatsapp_opt, '') <> 'none'
  on conflict (lead_id, phone) do nothing;
  get diagnostics v_optins = row_count;

  select * into l from public.leads x
   where (x.phone_e164 = v_phone or x.whatsapp_phone = v_phone)
     and not coalesce(x.claimed, false)
     and (x.invited_at is not null or x.invite_status is not null
          or exists (select 1 from public.notifications n where n.type = 'supplier_invite_wa' and n.lead_id = x.id and n.status = 'sent'))
   order by x.id limit 1;
  if l.id is null then return jsonb_build_object('due', false, 'reason', 'no invited lead without a company page on this number', 'optins', v_optins); end if;
  if v_reply = '' then return jsonb_build_object('due', false, 'reason', 'an empty message', 'optins', v_optins); end if;
  v_id := public.fn_seat_handoff('marketing', 'sales_engineer', 'invite.reply', 'leads', l.id::text,
    jsonb_build_object('lead_id', l.id, 'company_name', l.company_name, 'channel', 'whatsapp', 'from_phone', v_phone,
                       'reply_text', left(v_reply, 4000),
                       'ask', 'Set up the company page for this supplier from the trades it listed in its WhatsApp reply.'));
  -- null = a demo lead (ruling 1199: a demo row files no handoff)
  return jsonb_build_object('due', true, 'reason', 'an invited supplier wrote on WhatsApp', 'lead_id', l.id,
                            'handoff_id', v_id, 'optins', v_optins);
end $fn$;
revoke execute on function public.fn_marketing_files_wa_invite_reply(text, text) from public, anon, authenticated;
grant execute on function public.fn_marketing_files_wa_invite_reply(text, text) to service_role;

-- 10. the manual outreach list (LinkedIn / Instagram / Facebook from the company's own accounts; contacts nobody)
create or replace function public.fn_marketing_supplier_outreach_targets(p_per_trade int default 3)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v jsonb;
begin
  with trades as (
    select g.trade, min(g.rank) rank from public.marketing_gap_recruitment_plan g group by g.trade order by 2 limit 15
  ), pool as (
    select t.trade, t.rank, l.id, l.company_name, l.emirate, l.website, l.linkedin, l.instagram, l.facebook,
           row_number() over (partition by t.trade order by (coalesce(l.linkedin, '') = ''), l.id) rn
      from trades t join public.leads l on coalesce(l.invite_trades[1], l.sector) = t.trade
     where not coalesce(l.is_demo, false) and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)
       and not coalesce(l.claimed, false) and l.invited_at is null and l.invite_status is null
       and coalesce(l.whatsapp_opt, '') <> 'none'
       and (l.email is null or not exists (select 1 from public.email_suppressions s where lower(s.email) = lower(l.email)))
       and coalesce(l.linkedin, l.instagram, l.facebook, '') <> ''
  )
  select jsonb_build_object('built_at', now(), 'per_trade', p_per_trade,
           'rule', 'manual outreach from the company''s own LinkedIn / Instagram / Facebook accounts; no automation, no scraping, English only, no link in a first message',
           'trades', coalesce(jsonb_agg(jsonb_build_object('trade', x.trade, 'rank', x.rank, 'targets', x.targets) order by x.rank), '[]'::jsonb))
    into v
    from (select trade, rank, jsonb_agg(jsonb_build_object('lead_id', id, 'company', company_name, 'emirate', emirate,
                   'website', website, 'linkedin', linkedin, 'instagram', instagram, 'facebook', facebook) order by rn) targets
            from pool where rn <= greatest(1, least(coalesce(p_per_trade, 3), 10)) group by trade, rank) x;
  return v;
end $fn$;
revoke execute on function public.fn_marketing_supplier_outreach_targets(int) from public, anon, authenticated;

create or replace function public.fn_marketing_manual_outreach_targets()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select public.fn_marketing_supplier_outreach_targets(3)
$fn$;
revoke execute on function public.fn_marketing_manual_outreach_targets() from public, anon, authenticated;

-- the two duties (marketing owns both; the founder confirmed the channel work in ledger 1184)
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('marketing.whatsapp_supplier_invites', 'marketing', interval '1 hour', 'fn_marketing_wa_supplier_invites',
   'The WhatsApp supplier invitation: at most 20 a Dubai weekday 10:00-17:00, only to leads that opted in, only while wa_supplier_invite_golive AND invite_enabled are true, no brake is open and the sender reads quality HIGH. No link. Ruling 1184.',
   'scripts/sql/the_supplier_whatsapp_invitation_waits_for_opt_in_both_switches_and_a_high_quality_sender.sql'),
  ('marketing.manual_outreach_targets', 'marketing', interval '1 day', 'fn_marketing_manual_outreach_targets',
   'The per-trade list (15 thinnest trades, 3 each) of uninvited suppliers with a public LinkedIn / Instagram / Facebook page, for manual outreach from the company''s own accounts. Contacts nobody. Ruling 1184.',
   'scripts/sql/the_supplier_whatsapp_invitation_waits_for_opt_in_both_switches_and_a_high_quality_sender.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- verdict (reads only: this file defines routines, so it must not raise)
select case
  when exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname = 'fn_wa_supplier_invite_queue' and p.pronargs <> 3)
    then 'PROBE FAILED: a second signature of fn_wa_supplier_invite_queue survives'
  when (public.fn_wa_supplier_invite_queue(20, '2026-10-27 08:00+00', true)->>'queued')::int <> 0
       and coalesce((select value from public.app_secrets where key = 'invite_enabled'), '') <> 'true'
    then 'PROBE FAILED: the queue wrote with invite_enabled off'
  when (select relrowsecurity from pg_class where oid = 'public.supplier_whatsapp_optin'::regclass) is not true
    then 'PROBE FAILED: supplier_whatsapp_optin has no row security'
  else 'PROBE OK' end as verdict;
