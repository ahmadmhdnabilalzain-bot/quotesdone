
-- AN UNOPENED SUPPLIER INVITATION IS NUDGED ON DAY 3, 7 AND 14, UNDER THE SAME SWITCH, CAP AND BRAKES.
-- Seat: sales_engineer. 30 Sep 2026. Supersedes #1007's never-applied
-- an_invited_supplier_who_never_opened_the_invitation_is_nudged_on_day_3_7_and_14.sql (removed with its pending note).
--
-- MEASURED 30 Sep 2026 00:26 UTC on production (htdblwldjkcgjvmqkbeh), read-only:
--   * fn_supplier_invite_nudges_due and fn_sales_engineer_nudges_invited_suppliers do not exist.
--   * enqueue_supplier_invites' live body is byte-identical to MANIFEST 1823
--     (the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.sql), still the highest MANIFEST file
--     that defines it. #1051 (MANIFEST 1844) and #1106 (MANIFEST 1888) changed fn_supplier_invite_eligible_ids,
--     fn_supplier_invite_link and fn_supplier_invite_candidates, which the batch CALLS; none redefined the batch. This
--     file redefines neither of those routines, so the pool read once as a set and the rescue tier stay as they are.
--   * fn_sales_engineer_supplier_onboarding's live body is byte-identical to MANIFEST 1833, still its highest file.
--   * notifications of type supplier_invite or supplier_invite_nudge: 0. invite_enabled and supplier_outreach_golive:
--     false. So today 0 real nudges are due and 0 can be queued.
--
-- ROOT CAUSE of "171 invited, 0 nudged": fn_sales_engineer_supplier_onboarding nudged only stage 'matched', and
-- fn_supplier_registration_reminders_due only clicked / claimed / action_required leads. Nothing followed up a lead
-- who was invited and never opened the mail. The anchor must be the OUTBOX (a delivered supplier_invite), never
-- leads.invited_at, which carries fixture and test writes.
--
-- WHAT THIS ADDS (the nudge only; every other line of the two redefined routines is their canonical body)
--   fn_supplier_invite_nudges_due: an invited lead whose supplier_invite was delivered, not clicked, not claimed, not
--     registered, no approval status, is due step 1 from day 3, 2 from day 7, 3 from day 14, nothing from day 21.
--     Once per lead and step (the delivery key is read back from agent_actions). Never a suppressed address, never
--     invite_status bounced / complained / unsubscribed; real leads also pass fn_supplier_outreach_reachable.
--   fn_sales_engineer_nudges_invited_suppliers: the founder's rules, in the order they refuse:
--     1. no send on a company_calendar public holiday or the UAE weekend (as the batch);
--     2. the campaign go switch: invite_enabled AND supplier_outreach_golive, in BOTH modes (the fixture mode used by
--        the probe too, so the probe proves the switch rather than walking round it);
--     3. the brakes the batch obeys: after the Dubai window end nothing is queued; before its start a nudge waits
--        (not_before = window_start_hour Dubai); a measured inbox-placement failure today (fn_invite_placement_gate
--        'fail:...'; 'wait' before the seed is read is not a failure) holds real nudges; the batch's 3-day bounce brake
--        holds real nudges too (the batch owns the auto-pause flip; this only refuses to add to it);
--     4. ONE daily cap: invitations and nudges queued on the UTC day count against app_secrets.invite_daily_cap
--        (fn_invite_ramp's throttle), and send_outbox's invitation lane caps both types again at send time.
--     Always ENGLISH (lang 'en', the /en/ link from fn_supplier_invite_link, no Arabic copy; an Arabic-script company
--     name is not written into the greeting). Queued through fn_customer_support_takes_delivery.
--   fn_sales_engineer_supplier_onboarding (base: MANIFEST 1833) calls it and reports 'invite_nudges'; its first-quote
--     nudge loses the Arabic branch that #1065 had already switched off (suppliers are always English).
--   enqueue_supplier_invites (base: MANIFEST 1823) - ONE line: its used-today count includes supplier_invite_nudge,
--     so the batch and the nudger spend one cap from both sides.
--
-- RELEASE: apply this file, THEN deploy send_outbox (invite_lane.ts carries supplier_invite_nudge as a lane type
--   inside the lane's daily cap) in the same release. Until both are live no nudge is queued anyway: the switch is off.
-- ORGANIC ONLY (founder 866): the company's own outbox; no paid channel, no LLM.
-- Prevented by: scripts/sql/an_unopened_supplier_invitation_is_nudged_on_day_3_7_and_14_under_the_same_switch_cap_and_brakes_probe.sql

create or replace function public.fn_supplier_invite_nudges_due(p_now timestamptz default now(), p_include_fixtures boolean default false)
returns table (lead_id bigint, step integer, to_email text, lang text, dedupe_key text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with inv as (   -- the invitation as the OUTBOX recorded it, one per lead
    select n.lead_id, min(coalesce(n.sent_at, n.created_at)) as sent_at
      from public.notifications n
     where n.type = 'supplier_invite' and n.lead_id is not null
       and (n.status = 'sent' or n.sent_at is not null)
     group by n.lead_id
  ), c as (
    -- ALWAYS ENGLISH (review, 29 Sep 2026; founder rule: suppliers are always English, ledger 993). The column
    -- stays so the signature does not change; send_outbox would hold an Arabic row of this type anyway.
    select l.id, lower(btrim(l.email)) as to_email, 'en'::text as lang,
           l as lead,
           case when p_now >= i.sent_at + interval '14 days' then 3
                when p_now >= i.sent_at + interval '7 days'  then 2
                when p_now >= i.sent_at + interval '3 days'  then 1 end as step
      from inv i join public.leads l on l.id = i.lead_id
     where l.invite_clicked_at is null and not coalesce(l.claimed, false) and l.approval_status is null
       and l.registration_submitted_at is null
       and p_now < i.sent_at + interval '21 days'
  )
  select c.id, c.step, c.to_email, c.lang, 'supplier_invite_nudge:' || c.id || ':' || c.step
    from c
   where c.step is not null
     and coalesce((c.lead).invite_status, '') not in ('bounced', 'complained', 'unsubscribed')
     and not exists (select 1 from public.email_suppressions s where lower(s.email) = c.to_email)
     and case when p_include_fixtures
              -- the test path can only ever see a fixture: both marks, asserted, never assumed
              then (c.lead).company_name like 'ZZ DEMO%' and c.to_email like '%@example.invalid'
              else public.fn_supplier_outreach_reachable(c.lead, c.to_email) end
     and not exists (select 1 from public.agent_actions a
                      where a.kind = 'handoff' and a.agent = 'customer_support'
                        and a.target_id = 'delivery.request:supplier_invite_nudge:' || c.id || ':' || c.step)
   order by c.id
$fn$;
revoke execute on function public.fn_supplier_invite_nudges_due(timestamptz, boolean) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_nudges_invited_suppliers(p_now timestamptz default now(), p_cap integer default null,
                                                                             p_include_fixtures boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_dxb timestamp := p_now at time zone 'Asia/Dubai';
  v_cfg jsonb := coalesce((select nullif(value, '')::jsonb from public.app_secrets where key = 'invite_warmup'), '{}'::jsonb);
  v_hol text; v_cap int; v_used int; v_left int; v_queued int := 0; v_due int := 0; r record; v_link text;
  v_res jsonb; v_not_before timestamptz;
  v_gate text; v_inv_recent int; v_bounced_recent int; v_max_rate numeric;
begin
  select c.event_name into v_hol from public.company_calendar c
   where c.kind = 'public_holiday' and v_dxb::date between c.starts_on and coalesce(c.ends_on, c.starts_on) limit 1;
  if v_hol is not null then return jsonb_build_object('held', 'holiday: ' || v_hol, 'queued', 0); end if;
  if extract(isodow from v_dxb) in (6, 7) then return jsonb_build_object('held', 'UAE weekend', 'queued', 0); end if;
  -- THE SENDING WINDOW (review of #1007, 29 Sep 2026). The duty that calls this runs at 00:01 UTC (04:01 Dubai),
  -- before the window opens, so a start-hour HOLD would block every nudge. Instead a nudge queued before the
  -- window leaves no earlier than window_start_hour (default 9) Dubai the same day: not_before, exactly as
  -- enqueue_supplier_invites spreads its batch from the window's start. After window_end_hour it is held.
  v_not_before := greatest(p_now, (v_dxb::date + make_interval(hours => coalesce((v_cfg->>'window_start_hour')::int, 9)))
                                  at time zone 'Asia/Dubai');
  if extract(hour from v_dxb) >= coalesce((v_cfg->>'window_end_hour')::int, 17) then
    return jsonb_build_object('held', 'after the Dubai sending window', 'queued', 0); end if;
  -- THE GO SWITCH governs every mode, the probe's fixture mode included (30 Sep 2026).
  if not (coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
          and public.fn_supplier_outreach_golive()) then
    return jsonb_build_object('held', 'the supplier campaign is not open (invite_enabled / supplier_outreach_golive)', 'queued', 0,
                              'due', (select count(*) from public.fn_supplier_invite_nudges_due(p_now, p_include_fixtures)));
  end if;
  -- THE BATCH'S BRAKES, for real mail (a fixture address never leaves: send_outbox suppresses @example.invalid).
  if not p_include_fixtures then
    v_gate := public.fn_invite_placement_gate(v_dxb::date, p_now);
    if v_gate like 'fail:%' then
      return jsonb_build_object('held', 'inbox placement ' || v_gate, 'queued', 0); end if;
    -- enqueue_supplier_invites' 3-day bounce brake, read only (the batch owns the auto-pause)
    select count(*), count(*) filter (where invite_status = 'bounced') into v_inv_recent, v_bounced_recent
      from public.leads where invited_at > p_now - interval '3 days';
    v_max_rate := coalesce((select nullif(value, '')::numeric from public.app_secrets where key = 'invite_max_bounce_rate'), 0.08);
    if (v_inv_recent >= 15 and v_bounced_recent::numeric / greatest(v_inv_recent, 1) > v_max_rate)
       or v_bounced_recent >= greatest(5, ceil(v_inv_recent * v_max_rate)::int) then
      return jsonb_build_object('held', 'bounce brake: ' || v_bounced_recent || ' of ' || v_inv_recent || ' in 3 days', 'queued', 0); end if;
  end if;

  -- ONE daily cap for the domain: invitations and nudges queued this day, same class (real or fixture). The day is
  -- the UTC date, exactly as enqueue_supplier_invites counts it (review of #1007): on a Dubai-date basis the two
  -- would disagree between 00:00 and 04:00 Dubai and could each spend a full cap.
  v_cap := coalesce((select nullif(value, '')::int from public.app_secrets where key = 'invite_daily_cap'), 10);
  v_cap := least(v_cap, coalesce(p_cap, v_cap));
  select count(*) into v_used from public.notifications n
   where n.type in ('supplier_invite', 'supplier_invite_nudge')
     and (n.created_at at time zone 'UTC')::date = (p_now at time zone 'UTC')::date
     and public.fn_is_demo_email(n.to_email) = p_include_fixtures;
  v_left := greatest(0, v_cap - v_used);

  for r in select d.*, l.company_name, l.claim_token from public.fn_supplier_invite_nudges_due(p_now, p_include_fixtures) d
             join public.leads l on l.id = d.lead_id loop
    v_due := v_due + 1;
    continue when v_queued >= v_left;
    -- ALWAYS ENGLISH (review, 29 Sep 2026; founder rule: suppliers are always English): one copy, and the link is
    -- the invitation's own: fn_supplier_invite_link (#1051) - /en/portal with the claim token and the invitation ref.
    -- A lead with no claim token (the function then answers null) gets the plain English portal.
    v_link := coalesce(public.fn_supplier_invite_link(
                         (select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), r.claim_token, r.lead_id),
                       coalesce((select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com')
                       || '/en/portal');
    v_res := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_invite_nudge', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.to_email, 'to_role', 'supplier', 'lead_id', r.lead_id, 'lang', 'en', 'dedupe_key', r.dedupe_key,
      'subject', case when r.step = 3 then 'A last reminder: ' else '' end || 'your invitation to join QuotesDone as a supplier',
      -- #1070's greeting guard: an Arabic-script company name is not written into an English letter
      'body', coalesce('Dear ' || nullif(btrim(case when r.company_name ~ '[\u0600-\u06FF]' then '' else r.company_name end), '') || ',',
                       'Dear Sir or Madam,') || E'\n\n'
          || 'A reminder of our invitation to register your company as a supplier on QuotesDone. It is free and takes a few minutes.'
          || E'\n\n' || v_link
          || case when r.step = 3 then E'\n\nThis is the last reminder we will send about it.' else '' end
          || E'\n\nIf you would rather not receive these e-mails, reply to this one and we will remove your address.')));
    -- support's handler queues the row without a not_before (it takes only the words and the address), so the
    -- requester sets the window start on the row it was just given back (by id, whatever the outbox's status:
    -- a fixture address is 'suppressed' on insert, a real one 'queued')
    update public.notifications set not_before = v_not_before
     where id = (v_res->0->>'notification_id')::bigint and type = 'supplier_invite_nudge';
    v_queued := v_queued + 1;
  end loop;
  return jsonb_build_object('held', null, 'due', v_due, 'queued', v_queued, 'cap', v_cap, 'used_before', v_used);
end
$fn$;
revoke execute on function public.fn_sales_engineer_nudges_invited_suppliers(timestamptz, integer, boolean) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_nudges_invited_suppliers(timestamptz, integer, boolean) to service_role;

-- The duty that measured "171 invited, 0 nudged" now acts on the 'invited' stage. Base: #1065's
-- suppliers_are_always_written_in_english_and_customers_in_their_inquirys_language.sql (MANIFEST 1833, the current
-- canonical), byte for byte except: the nudger call and its report line ('invite_nudges'); the first-quote nudge's
-- Arabic branch (dead behind v_ar := false in #1065) removed, so the letter is English only; its portal link is
-- /en/portal; and #1070's greeting guard on the English greeting.
CREATE OR REPLACE FUNCTION public.fn_sales_engineer_supplier_onboarding()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_nudged int := 0; v_to text; v_stages jsonb; v_inv jsonb;
begin
  -- THE STAGE, from what the rows say happened (never from a status someone typed).
  with m as (
    select im.supplier_id, min(im.sent_at) as first_match_at,
           count(*) filter (where i.status not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
                              and not exists (select 1 from public.quotes q where q.inquiry_id = im.inquiry_id and q.supplier_id = im.supplier_id)) as open_matches
      from public.inquiry_matches im join public.inquiries i on i.id = im.inquiry_id
     group by im.supplier_id
  ), q as (
    select supplier_id, min(created_at) as first_quote_at from public.quotes group by supplier_id
  ), s as (
    select l.id,
           case when coalesce(l.banned, false) or coalesce(l.permanently_closed, false) or l.approval_status = 'rejected' then 'closed'
                when q.first_quote_at is not null then 'quoting'
                when l.approval_status = 'approved' and m.first_match_at is not null then 'matched'
                when l.approval_status = 'approved' then 'approved'
                when l.approval_status = 'action_required' then 'action_required'
                when l.registration_submitted_at is not null or coalesce(l.claimed, false) then 'registering'
                when l.invite_clicked_at is not null then 'clicked'
                else 'invited' end as stage,
           m.first_match_at, q.first_quote_at, coalesce(m.open_matches, 0) as open_matches
      from public.leads l
      left join m on m.supplier_id = l.id
      left join q on q.supplier_id = l.id
     where l.invited_at is not null or coalesce(l.claimed, false) or l.approval_status is not null
  )
  insert into public.supplier_onboarding as o (lead_id, stage, first_match_at, first_quote_at, open_matches)
  select id, stage, first_match_at, first_quote_at, open_matches from s
  on conflict (lead_id) do update set
    stage_since    = case when o.stage is distinct from excluded.stage then now() else o.stage_since end,
    stage          = excluded.stage,
    first_match_at = excluded.first_match_at, first_quote_at = excluded.first_quote_at,
    open_matches   = excluded.open_matches, updated_at = now();

  -- THE 'invited' STAGE (#1007): day 3 / 7 / 14 after the invitation the OUTBOX delivered (see the header).
  v_inv := public.fn_sales_engineer_nudges_invited_suppliers();

  -- THE NUDGE. Before approval the invitation reminders and the 14-day window already act; from approval to the
  -- first quote nothing did. Matched, requests open for him, not quoted 3 days after the first match: told, at
  -- most twice, a week apart, in his language, through customer_support.
  for r in
    select o.lead_id, o.open_matches, l.company_name, lower(nullif(btrim(coalesce(l.claimed_by, l.email)), '')) as to_email
      from public.supplier_onboarding o join public.leads l on l.id = o.lead_id
     where o.stage = 'matched' and o.open_matches > 0 and o.first_match_at < now() - interval '3 days'
       and o.nudges < 2 and (o.last_nudge_at is null or o.last_nudge_at < now() - interval '7 days')
     order by o.first_match_at
     limit 50
  loop
    continue when r.to_email is null;
    -- ENGLISH ONLY (#1007, review of 29 Sep 2026): #1065's body kept an Arabic branch behind a flag fixed to English; it is
    -- removed, not switched off. A matched supplier is registered, so the link is the English portal (no claim token).
    perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_first_quote_nudge', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.to_email, 'to_role', 'supplier', 'lead_id', r.lead_id, 'lang', 'en',
      'dedupe_key', 'first_quote_nudge:' || r.lead_id || ':' || (select nudges from public.supplier_onboarding where lead_id = r.lead_id),
      'subject', 'Customer requests are waiting for your quotation',
      -- #1070's greeting guard (#1007): an Arabic-script company name is not written into an English letter
      'body', 'Dear ' || coalesce(nullif(btrim(case when r.company_name ~ '[\u0600-\u06FF]' then '' else r.company_name end), ''), 'supplier') || ',' || chr(10) || chr(10)
          || r.open_matches || ' customer request(s) matched to your trade are open and have no quotation from you yet. '
          || 'You can read them and quote in your supplier portal: '
          || coalesce((select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com')
          || '/en/portal' || chr(10) || chr(10)
          || 'QuotesDone')));
    update public.supplier_onboarding set nudges = nudges + 1, last_nudge_at = now() where lead_id = r.lead_id;
    v_nudged := v_nudged + 1;
  end loop;

  select coalesce(jsonb_object_agg(stage, n), '{}'::jsonb) into v_stages
    from (select stage, count(*) n from public.supplier_onboarding group by stage) x;
  return jsonb_build_object('stages', v_stages, 'nudged', v_nudged, 'invite_nudges', v_inv);
end $function$;
revoke execute on function public.fn_sales_engineer_supplier_onboarding() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_supplier_onboarding() to service_role;


-- THE INVITATION BATCH COUNTS THE DAY'S NUDGES AGAINST THE SAME CAP (review of #1007, 29 Sep 2026).
-- enqueue_supplier_invites is the canonical body of
-- the_invitation_batch_waits_for_the_mornings_seed_to_land_in_both_inboxes.sql (MANIFEST 1823), byte for byte except the
-- used-today count, which now includes supplier_invite_nudge. Before: the nudger counted invitations against
-- invite_daily_cap, but the batch did not count nudges, so a day could queue cap invitations on top of its nudges.
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
  -- ONE daily cap for invitations and their nudges (review of #1007, 29 Sep 2026): a nudge queued today spends it too,
  -- as fn_sales_engineer_nudges_invited_suppliers already counts the invitations queued today against the same cap.
  select count(*) into v_used from notifications where type in ('supplier_invite', 'supplier_invite_nudge') and (created_at at time zone 'UTC')::date = v_today
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
