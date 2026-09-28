-- AN INVITED SUPPLIER WHO NEVER OPENED THE INVITATION IS NUDGED ON DAY 3, 7 AND 14 (28 Sep 2026, sales_engineer).
--
-- MEASURED 28 Sep 2026 on production (htdblwldjkcgjvmqkbeh), read-only:
--   * supplier_onboarding: 171 leads at stage 'invited', 0 nudged. leads.invited_at: 172.
--   * notifications of type 'supplier_invite': 0 ever (so 0 sent). The 171 are fixture/test writes to the column
--     (see memory a-status-column-is-not-a-delivery-record), not invitations.
--
-- ROOT CAUSE — 0 nudges by construction, not by chance:
--   1. fn_sales_engineer_supplier_onboarding nudges ONLY stage 'matched' (approved, matched, not quoted). Its comment
--      delegates the stages before approval to "the invitation reminders".
--   2. fn_supplier_registration_reminders_due selects only invite_clicked_at / claimed / action_required. A lead who
--      was invited and never opened the mail has stage NULL there and is filtered out.
--   So nothing, anywhere, followed up the 'invited' stage. (And had it read leads.invited_at it would have nudged
--   171 people who were never invited: the anchor must be the outbox.)
--
-- WHAT THIS ADDS
--   fn_supplier_invite_nudges_due(p_now, p_include_fixtures): an invited, unregistered lead (not clicked, not claimed,
--     no approval status) whose supplier_invite NOTIFICATION was delivered (status 'sent' / sent_at, never the lead's
--     status column) is due step 1 from day 3, step 2 from day 7, step 3 from day 14, nothing after day 21 — at most 3.
--     Idempotent per lead and step: the delivery key 'supplier_invite_nudge:<lead>:<step>' is read back from
--     agent_actions (the delivery request itself), as the registration reminders do.
--     Suppression: never email_suppressions, never invite_status bounced/complained/unsubscribed; real leads also pass
--     fn_supplier_outreach_reachable (fixtures, bans, screening, closed, fn_email_sendable).
--   fn_sales_engineer_nudges_invited_suppliers(p_now, p_cap, p_include_fixtures): holds on a company_calendar public
--     holiday and the UAE weekend, and after the Dubai window end (invite_warmup.window_end_hour); real mail also needs
--     invite_enabled + supplier_outreach_golive (the founder's go). It SHARES the invitation's daily cap
--     (app_secrets.invite_daily_cap, moved only by fn_invite_ramp's bounce/complaint throttle): invitations and nudges
--     queued today count against one number. Queues through fn_customer_support_takes_delivery (notifications ->
--     send_outbox). Fixture mode touches ONLY ZZ DEMO leads at @example.invalid.
--   fn_sales_engineer_supplier_onboarding calls it and reports 'invite_nudges'.
--
-- ORGANIC ONLY (founder 866): email through the company's own outbox; no paid channel, no ad spend, no LLM.
-- Prevented by: scripts/sql/an_invited_supplier_who_never_opened_the_invitation_is_nudged_on_day_3_7_and_14_probe.sql

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
    select l.id, lower(btrim(l.email)) as to_email, case when lower(coalesce(l.locale, '')) like 'ar%' then 'ar' else 'en' end as lang,
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
  v_hol text; v_cap int; v_used int; v_left int; v_queued int := 0; v_due int := 0; r record; v_ar boolean; v_link text;
begin
  select c.event_name into v_hol from public.company_calendar c
   where c.kind = 'public_holiday' and v_dxb::date between c.starts_on and coalesce(c.ends_on, c.starts_on) limit 1;
  if v_hol is not null then return jsonb_build_object('held', 'holiday: ' || v_hol, 'queued', 0); end if;
  if extract(isodow from v_dxb) in (6, 7) then return jsonb_build_object('held', 'UAE weekend', 'queued', 0); end if;
  if extract(hour from v_dxb) >= coalesce((v_cfg->>'window_end_hour')::int, 17) then
    return jsonb_build_object('held', 'after the Dubai sending window', 'queued', 0); end if;
  if not p_include_fixtures and not (coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
                                     and public.fn_supplier_outreach_golive()) then
    return jsonb_build_object('held', 'the supplier campaign is not open (invite_enabled / supplier_outreach_golive)', 'queued', 0,
                              'due', (select count(*) from public.fn_supplier_invite_nudges_due(p_now, false)));
  end if;

  -- ONE daily cap for the domain: invitations and nudges queued this Dubai day, same class (real or fixture).
  v_cap := coalesce((select nullif(value, '')::int from public.app_secrets where key = 'invite_daily_cap'), 10);
  v_cap := least(v_cap, coalesce(p_cap, v_cap));
  select count(*) into v_used from public.notifications n
   where n.type in ('supplier_invite', 'supplier_invite_nudge')
     and (n.created_at at time zone 'Asia/Dubai')::date = v_dxb::date
     and public.fn_is_demo_email(n.to_email) = p_include_fixtures;
  v_left := greatest(0, v_cap - v_used);

  for r in select d.*, l.company_name, l.claim_token from public.fn_supplier_invite_nudges_due(p_now, p_include_fixtures) d
             join public.leads l on l.id = d.lead_id loop
    v_due := v_due + 1;
    continue when v_queued >= v_left;
    v_ar := r.lang = 'ar';
    v_link := coalesce((select nullif(btrim(value), '') from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com')
              || '/' || r.lang || '/portal' || case when r.claim_token is not null then '?t=' || r.claim_token::text else '' end;
    perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_invite_nudge', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.to_email, 'to_role', 'supplier', 'lead_id', r.lead_id, 'lang', r.lang, 'dedupe_key', r.dedupe_key,
      'subject', case when v_ar then case when r.step = 3 then 'تذكير أخير: ' else '' end || 'دعوتكم للانضمام إلى الموردين في QuotesDone'
                      else case when r.step = 3 then 'A last reminder: ' else '' end || 'your invitation to join QuotesDone as a supplier' end,
      'body', case when v_ar then
          coalesce('السادة/ ' || nullif(btrim(r.company_name), '') || ' المحترمين،', 'السادة الكرام،') || E'\n\nتحية طيبة وبعد،\n\n'
          || 'نودّ تذكيركم بدعوتنا لتسجيل شركتكم مورِّدًا على QuotesDone. التسجيل مجاني ويستغرق دقائق معدودة.'
          || E'\n\n' || v_link
          || case when r.step = 3 then E'\n\nوهذا آخر تذكير نرسله إليكم بهذا الشأن.' else '' end
          || E'\n\nوفي حال عدم رغبتكم في تلقي هذه الرسائل، يكفي الرد على هذه الرسالة لإزالة عنوانكم من القائمة.'
          || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،'
        else
          coalesce('Dear ' || nullif(btrim(r.company_name), '') || ',', 'Dear Sir or Madam,') || E'\n\n'
          || 'A reminder of our invitation to register your company as a supplier on QuotesDone. It is free and takes a few minutes.'
          || E'\n\n' || v_link
          || case when r.step = 3 then E'\n\nThis is the last reminder we will send about it.' else '' end
          || E'\n\nIf you would rather not receive these e-mails, reply to this one and we will remove your address.' end)));
    v_queued := v_queued + 1;
  end loop;
  return jsonb_build_object('held', null, 'due', v_due, 'queued', v_queued, 'cap', v_cap, 'used_before', v_used);
end
$fn$;
revoke execute on function public.fn_sales_engineer_nudges_invited_suppliers(timestamptz, integer, boolean) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_nudges_invited_suppliers(timestamptz, integer, boolean) to service_role;

-- The duty that measured "171 invited, 0 nudged" now acts on the 'invited' stage. Body unchanged from
-- the_sales_engineer_owns_onboarding_performance_and_supply_gaps.sql except the call and its report line.
create or replace function public.fn_sales_engineer_supplier_onboarding()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r record; v_nudged int := 0; v_ar boolean; v_stages jsonb; v_inv jsonb;
begin
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

  -- THE 'invited' STAGE: day 3 / 7 / 14 after the invitation the OUTBOX delivered (see the header).
  v_inv := public.fn_sales_engineer_nudges_invited_suppliers();

  for r in
    select o.lead_id, o.open_matches, l.company_name, l.locale, lower(nullif(btrim(coalesce(l.claimed_by, l.email)), '')) as to_email
      from public.supplier_onboarding o join public.leads l on l.id = o.lead_id
     where o.stage = 'matched' and o.open_matches > 0 and o.first_match_at < now() - interval '3 days'
       and o.nudges < 2 and (o.last_nudge_at is null or o.last_nudge_at < now() - interval '7 days')
     order by o.first_match_at
     limit 50
  loop
    continue when r.to_email is null;
    v_ar := r.locale = 'ar';
    perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_first_quote_nudge', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.to_email, 'to_role', 'supplier', 'lead_id', r.lead_id, 'lang', case when v_ar then 'ar' else 'en' end,
      'dedupe_key', 'first_quote_nudge:' || r.lead_id || ':' || (select nudges from public.supplier_onboarding where lead_id = r.lead_id),
      'subject', case when v_ar then 'طلبات عملاء بانتظار عروض أسعاركم في QuotesDone'
                      else 'Customer requests are waiting for your quotation' end,
      'body', case when v_ar then
          'السادة/ ' || coalesce(r.company_name, 'المورّد') || ' المحترمين،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
          || 'لديكم ' || r.open_matches || ' من طلبات العملاء المطابقة لتخصصكم لم تُقدَّم لها عروض أسعار حتى الآن. '
          || 'يمكنكم الاطلاع عليها وتقديم عروضكم من بوابة المورّدين: https://quotesdone.com/ar/portal' || chr(10) || chr(10)
          || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
        else
          'Dear ' || coalesce(r.company_name, 'supplier') || ',' || chr(10) || chr(10)
          || r.open_matches || ' customer request(s) matched to your trade are open and have no quotation from you yet. '
          || 'You can read them and quote in your supplier portal: https://quotesdone.com/portal' || chr(10) || chr(10)
          || 'QuotesDone' end)));
    update public.supplier_onboarding set nudges = nudges + 1, last_nudge_at = now() where lead_id = r.lead_id;
    v_nudged := v_nudged + 1;
  end loop;

  select coalesce(jsonb_object_agg(stage, n), '{}'::jsonb) into v_stages
    from (select stage, count(*) n from public.supplier_onboarding group by stage) x;
  return jsonb_build_object('stages', v_stages, 'nudged', v_nudged, 'invite_nudges', v_inv);
end $fn$;
revoke execute on function public.fn_sales_engineer_supplier_onboarding() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_supplier_onboarding() to service_role;
