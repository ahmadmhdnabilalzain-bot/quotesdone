-- the_supplier_onboarding_duty_passes_its_fixture_switch_to_the_invite_nudges
-- Seat: sales_engineer (owner of sales_engineer.supplier_onboarding). Found by it_engineer in stage-2 run f0b2de8f (2 Nov 2026, S18).
--
-- Measured on production 2 Nov 2026: the duty keeps its fixture switch for its own two steps (the stage rows and the first-quote nudge both
-- select `l.is_demo = v_fx`, v_fx = qd.duty_fixtures = 'on'), but it calls fn_sales_engineer_nudges_invited_suppliers() with its defaults,
-- and that function has its own fixture mode, p_include_fixtures (default false = REAL mail). So a duty run in fixture mode still
-- queued the day-3/7/14 invitation reminders to real suppliers: the probe counted 20 real notification rows (cap 20, 32 due) that the
-- rolled-back transaction discarded. In production the switch is never on, so nothing changes there; the gap is that the fixture
-- switch stopped at the duty's boundary, so a rehearsal that runs the duty could send a real invitation reminder.
--
-- The one change: v_inv := public.fn_sales_engineer_nudges_invited_suppliers(p_include_fixtures => v_fx);
-- Production (v_fx false) calls it exactly as before. The body below is the live body (read from production 2 Nov 2026) plus that
-- argument. CREATE OR REPLACE keeps the ACL, so no new revoke is needed.
-- Proved by the_supplier_onboarding_duty_passes_its_fixture_switch_to_the_invite_nudges_probe.sql (rolled back).
-- Applied at merge (release operator), never before.

create or replace function public.fn_sales_engineer_supplier_onboarding()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; v_nudged int := 0; v_to text; v_stages jsonb; v_inv jsonb;
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';   -- fixture run: ONLY demo rows
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
     where (l.invited_at is not null or coalesce(l.claimed, false) or l.approval_status is not null) and l.is_demo = v_fx
  )
  insert into public.supplier_onboarding as o (lead_id, stage, first_match_at, first_quote_at, open_matches)
  select id, stage, first_match_at, first_quote_at, open_matches from s
  on conflict (lead_id) do update set
    stage_since    = case when o.stage is distinct from excluded.stage then now() else o.stage_since end,
    stage          = excluded.stage,
    first_match_at = excluded.first_match_at, first_quote_at = excluded.first_quote_at,
    open_matches   = excluded.open_matches, updated_at = now();

  -- THE 'invited' STAGE (#1007): day 3 / 7 / 14 after the invitation the OUTBOX delivered (see the header).
  -- The fixture switch goes down with the call: fixture mode nudges fixture addresses only.
  v_inv := public.fn_sales_engineer_nudges_invited_suppliers(p_include_fixtures => v_fx);

  -- THE NUDGE. Before approval the invitation reminders and the 14-day window already act; from approval to the
  -- first quote nothing did. Matched, requests open for him, not quoted 3 days after the first match: told, at
  -- most twice, a week apart, in his language, through customer_support.
  for r in
    select o.lead_id, o.open_matches, l.company_name, lower(nullif(btrim(coalesce(l.claimed_by, l.email)), '')) as to_email
      from public.supplier_onboarding o join public.leads l on l.id = o.lead_id and l.is_demo = v_fx
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
      'body', 'Dear ' || coalesce(nullif(btrim(case when r.company_name ~ '[؀-ۿ]' then '' else r.company_name end), ''), 'supplier') || ',' || chr(10) || chr(10)
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
end $fn$;
