-- THE 18:00 SUPPLIER LIST GOES ONLY BEFORE A SENDING DAY, SHOWS THE DAY-1 VOLUME, AND A COMPANY IS INVITED ONCE
-- (24 Sep 2026; seat: marketing; ledger 993, memory marketing-month-approval-flow).
--
-- Measured 24 Sep 15:07 Dubai: supportCampaignList had run (last_ok 14:46 Dubai) and supplier_campaign_daily_list
-- held 0 rows because 18:00 had not yet come since the_founder_sees_tomorrows_supplier_invitations_at_six.sql was
-- applied that morning; a rolled-back run of the tick at 18:05 built the row and the attach queued the mail to
-- management@quotesdone.com. Three defects found on the way, fixed here:
--   1. The tick fired EVERY evening. The founder wants it the evening before a UAE working day only: now Friday and
--      Saturday evenings and the eve of a company_calendar public holiday are skipped (Sunday evening goes).
--   2. It showed the stored invite_daily_cap (50). On a cold domain fn_invite_ramp resets the cap to
--      invite_warmup.base_cap (30) before the batch, so the PDF promised 20 invitations that would never leave.
--   3. fn_supplier_invite_candidates let up to 5 addresses of ONE company domain go in a day, and a second address
--      of an already-invited company go on a later day. Measured: 17,438 eligible leads, 111 duplicated company
--      names. Now one invitation per company (email domain, or the address on a shared provider; and the
--      normalised name), the best contact first, and never a company already invited. The PDF reads the same
--      function, so the list and the batch cannot diverge.
--
-- prevented by: scripts/checks/the_daily_supplier_list_goes_only_before_a_sending_day.test.mjs
--   node scripts/apply_sql.mjs scripts/sql/the_daily_supplier_list_goes_only_before_a_sending_day_and_a_company_is_invited_once.sql --apply --ddl

begin;

create or replace function public.fn_supplier_invite_candidates(p_limit integer)
returns table (lead_id bigint, to_email text, company_name text, lang text, subject text, body text)
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_site text; v_target int;
  v_subj text; v_body text; v_subj_ar text; v_body_ar text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  select value into v_subj    from app_secrets where key = 'invite_subject';
  select value into v_body    from app_secrets where key = 'invite_body';
  select value into v_subj_ar from app_secrets where key = 'invite_subject_ar';
  select value into v_body_ar from app_secrets where key = 'invite_body_ar';
  -- A template without the link placeholder is the 62-invitations-with-no-way-in failure. Refuse.
  if coalesce(v_body, '') not like '%{{link}}%' then
    raise exception 'app_secrets.invite_body has no {{link}} placeholder: an invitation with no way in is refused';
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
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified,
           l.invite_trades, l.emirate, k.dkey, k.nkey,
           -- Arabic only where the lead's own locale says so AND the Arabic copy exists; otherwise
           -- English, which is also what a04 assumes for an unregistered recipient.
           case when (lower(coalesce(l.locale, '')) like 'ar%' or coalesce(l.company_name, '') ~ '[؀-ۿ]') and coalesce(v_body_ar, '') like '%{{link}}%'   -- the language from the name too (#916, the_supplier_invitation_reads_the_language_from_the_name_and_skips_a_suppressed_address.sql)
                     and coalesce(v_subj_ar, '') <> '' then 'ar' else 'en' end as lang
    from leads l join keyed k on k.id = l.id
    where public.fn_supplier_invite_eligible(l)
      -- a company already invited (bounced, unsubscribed or registered included) is not invited again at another address
      and not exists (select 1 from touched_d t where t.dkey = k.dkey)
      and (k.nkey is null or not exists (select 1 from touched_n t where t.nkey = k.nkey))
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain, c.lang, c.dkey, c.nkey,
      -- 23 Sep 2026 (marketing.recruitment_funnel): a lead in a trade the sales engineer marked for recruitment
      -- (public.supply_gap, status 'recruit') goes first. Trade codes compared for equality; no word is read.
      case when exists (select 1 from public.supply_gap g where g.status = 'recruit' and g.trade = any(coalesce(c.invite_trades, '{}'::text[]))
                          and (g.emirate = 'UAE' or g.emirate = c.emirate)) then 0 else 1 end as target_rank,
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      case when c.email_verified in ('verified','true') then 0 else 1 end as unverified_rank,
      case when split_part(lower(c.email),'@',1) in
             ('info','sales','admin','contact','enquiry','enquiries','inquiry','office','mail',
              'support','hello','marketing','general','accounts','reception','careers','hr')
           then 1 else 0 end as role_rank
    from cand c
  ),
  elig as (
    select r.id, r.email, r.company_name, r.claim_token, r.lang from (
      select p.*,
        case when p.pdomain='~none' then 1 else 0 end as is_none,
        row_number() over (partition by p.pdomain order by p.unverified_rank, p.role_rank, p.id) as rk,
        row_number() over (partition by coalesce(p.email_domain, split_part(p.email,'@',2)) order by p.unverified_rank, p.role_rank, p.id) as domain_rk,
        -- the best contact per company: a verified, named mailbox before info@/sales@ (a role address goes only
        -- when it is the company's only one). ponytail: a lead that wins one key and loses the other waits a day.
        row_number() over (partition by p.dkey order by p.unverified_rank, p.role_rank, p.id) as company_rk,
        row_number() over (partition by coalesce(p.nkey, p.email) order by p.unverified_rank, p.role_rank, p.id) as name_rk
      from prio p
    ) r
    where r.domain_rk <= 5 and r.company_rk = 1 and r.name_rk = 1
    order by r.target_rank, r.is_none, r.rk, r.unverified_rank, r.role_rank, r.pdomain
    limit greatest(coalesce(p_limit, 0), 0)
  )
  select e.id, btrim(e.email), e.company_name, e.lang,
         case when e.lang = 'ar' then v_subj_ar else v_subj end,
         replace(
           replace(case when e.lang = 'ar'
                        then case when coalesce(btrim(e.company_name), '') = ''
                                  then replace(v_body_ar, 'السادة/ {{company}} المحترمين،', 'السادة الكرام،')
                                  else v_body_ar end
                        else v_body end,
                   '{{company}}', coalesce(nullif(btrim(e.company_name),''), case when e.lang = 'ar' then 'الكرام' else 'there' end)),
           '{{link}}', v_site || '/' || e.lang || '/portal?t=' || e.claim_token::text)
  from elig e;
end
$fn$;
revoke execute on function public.fn_supplier_invite_candidates(integer) from public, anon, authenticated;

create or replace function public.fn_supplier_campaign_next_list(p_after date default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_after date := coalesce(p_after, (now() at time zone 'Asia/Dubai')::date);
  v_day date := v_after + 1; v_skipped jsonb := '[]'::jsonb; v_why text; i int := 0;
  v_cap int; v_pool int; v_n int; v_switch boolean; v_held text; v_rows jsonb;
begin
  loop
    v_why := public.fn_supplier_invites_hold_reason(v_day);
    exit when v_why is null;
    v_skipped := v_skipped || jsonb_build_object('day', v_day, 'why', v_why);
    v_day := v_day + 1; i := i + 1;
    if i > 20 then raise exception 'no supplier sending day within 20 days of %', v_after; end if;
  end loop;
  v_switch := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
              and public.fn_supplier_outreach_golive();
  v_held := case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
                 when not v_switch then 'invite_enabled is false' end;
  -- the sender's own numbers (enqueue_supplier_invites): cap, eligible pool, planned = least of the two
  v_cap := coalesce((select nullif(value, '')::int from public.app_secrets where key = 'invite_daily_cap'), 10);
  -- fn_invite_ramp runs before the batch on the sending day; with nothing sent in the 3 days before it, it resets
  -- the cap to invite_warmup.base_cap (a cold domain restarts). Show that number, not the stale stored cap.
  if coalesce((select max(l.invited_at) from public.leads l), '-infinity'::timestamptz) < (v_day::timestamp at time zone 'Asia/Dubai') - interval '3 days' then
    v_cap := coalesce((select (nullif(value, '')::jsonb->>'base_cap')::int from public.app_secrets where key = 'invite_warmup'), 30);
  end if;
  select count(*) into v_pool from public.leads l where public.fn_supplier_invite_eligible(l);
  v_n := greatest(least(v_cap, v_pool), 0);
  select coalesce(jsonb_agg(jsonb_build_object('n', c.rn, 'lead_id', c.lead_id,
            'company', coalesce(nullif(btrim(c.company_name), ''), '(no company name)'),
            'emirate', coalesce(nullif(btrim(l.emirate), ''), '-'), 'language', c.lang,
            'email', public.fn_mask_email(c.to_email)) order by c.rn), '[]'::jsonb)
    into v_rows
    from (select x.*, row_number() over () rn from public.fn_supplier_invite_candidates(v_n) x) c
    join public.leads l on l.id = c.lead_id;
  return jsonb_build_object('send_day', v_day, 'skipped', v_skipped, 'switch_on', v_switch, 'held_because', v_held,
                            'cap', v_cap, 'pool', v_pool, 'planned', v_n, 'rows', v_rows);
end $fn$;
revoke execute on function public.fn_supplier_campaign_next_list(date) from public, anon, authenticated;

create or replace function public.fn_customer_support_campaign_list_tick(p_now timestamptz default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_local timestamp := coalesce(p_now, now()) at time zone 'Asia/Dubai'; v_at time; r public.supplier_campaign_daily_list;
  v_l jsonb; v_c jsonb; v_subj text; v_body text; v_blocks jsonb; v_state text; v_send text;
begin
  begin
    select coalesce(nullif(btrim(value), ''), '18:00')::time into v_at from public.app_secrets where key = 'supplier_campaign_list_local_time';
  exception when others then v_at := time '18:00'; end;
  v_at := coalesce(v_at, time '18:00');
  if v_local::time < v_at then return jsonb_build_object('due', false, 'reason', 'before ' || to_char(v_at, 'HH24:MI') || ' Dubai'); end if;

  -- ONLY ON THE EVENING BEFORE A SENDING DAY (24 Sep 2026, ledger 993): nothing goes on Friday or Saturday evening,
  -- nor on the eve of a company_calendar public holiday; Sunday evening and the last evening of a holiday do.
  if public.fn_supplier_invites_hold_reason(v_local::date + 1) is not null then
    return jsonb_build_object('due', false, 'reason', 'tomorrow is not a sending day: ' || public.fn_supplier_invites_hold_reason(v_local::date + 1));
  end if;
  select * into r from public.supplier_campaign_daily_list where list_day = v_local::date;
  if r.notification_id is not null then return jsonb_build_object('due', false, 'reason', 'already sent today', 'id', r.id); end if;
  if r.id is not null and r.attempts >= 8 then return jsonb_build_object('due', false, 'ok', false, 'reason', 'render failed 8 times today', 'error', r.pdf_error); end if;

  if r.id is null then
    v_l := public.fn_supplier_campaign_next_list(v_local::date);
    v_c := public.fn_supplier_campaign_day_counts(v_local::date);
    v_send := to_char((v_l->>'send_day')::date, 'FMDay DD FMMonth YYYY');
    v_state := case when (v_l->>'switch_on')::boolean
                    then 'The campaign is ON: these ' || (v_l->>'planned') || ' supplier(s) will be invited on ' || v_send || ', spread across the working day.'
                    else 'The campaign is SWITCHED OFF (' || (v_l->>'held_because') || '): NOTHING will be sent on ' || v_send
                         || '. This is the list that WOULD be sent if it were on.' end;
    v_subj := 'Supplier campaign: ' || case when (v_l->>'switch_on')::boolean then '' else 'OFF — would invite ' end
              || (v_l->>'planned') || ' supplier(s) on ' || to_char((v_l->>'send_day')::date, 'Dy DD Mon');
    v_body := v_state || E'\n\n'
      || 'Today (' || to_char(v_local::date, 'Dy DD Mon') || '): ' || (v_c->>'sent') || ' invitation(s) sent, ' || (v_c->>'bounced') || ' bounced, '
      || (v_c->>'unsubscribed') || ' unsubscribed, ' || (v_c->>'registered') || ' supplier(s) registered.' || E'\n\n'
      || 'The attached PDF lists each supplier: company, emirate, language and email (masked). It is produced by code from the same '
      || 'selection the sender uses (cap ' || (v_l->>'cap') || ', eligible pool ' || (v_l->>'pool') || '). The morning warm-up may move the cap, '
      || 'and a supplier who registers, bounces or unsubscribes overnight drops out.'
      || coalesce(E'\n\nNo sending on: ' || (select string_agg(to_char((s->>'day')::date, 'Dy DD Mon') || ' (' || (s->>'why') || ')', ', ')
                                               from jsonb_array_elements(v_l->'skipped') s), '');
    v_blocks := jsonb_build_array(
        jsonb_build_object('t', 'h2', 'text', 'Suppliers to be invited on ' || v_send),
        jsonb_build_object('t', 'p', 'text', v_state),
        jsonb_build_object('t', 'p', 'text', 'Today (' || to_char(v_local::date, 'Dy DD Mon YYYY') || '): sent ' || (v_c->>'sent') || ', bounced ' || (v_c->>'bounced')
                                              || ', unsubscribed ' || (v_c->>'unsubscribed') || ', registered ' || (v_c->>'registered') || '.'),
        jsonb_build_object('t', 'note', 'text', 'Selection: fn_supplier_invite_candidates(' || (v_l->>'planned') || '), the sender''s own; cap ' || (v_l->>'cap')
                                              || ', eligible pool ' || (v_l->>'pool') || '. Emails are masked. Prepared by customer_support, by code.'),
        jsonb_build_object('t', 'space', 'h', 6),
        jsonb_build_object('t', 'table', 'head', jsonb_build_array('#', 'Company', 'Emirate', 'Language', 'Email'),
          'widths', jsonb_build_array(0.06, 0.44, 0.14, 0.1, 0.26),
          'rows', coalesce((select jsonb_agg(jsonb_build_array((x->>'n'), x->>'company', x->>'emirate', upper(x->>'language'), x->>'email') order by (x->>'n')::int)
                              from jsonb_array_elements(v_l->'rows') x), '[]'::jsonb)));
    insert into public.supplier_campaign_daily_list (list_day, send_day, switch_on, held_because, planned, rows, counts, subject, body, pdf_blocks)
    values (v_local::date, (v_l->>'send_day')::date, (v_l->>'switch_on')::boolean, v_l->>'held_because', (v_l->>'planned')::int,
            v_l->'rows', v_c, v_subj, v_body, v_blocks)
    returning * into r;
  end if;
  return jsonb_build_object('due', true, 'pdf_pending', true, 'id', r.id, 'subject', r.subject,
                            'report_key', 'supplier_list_' || to_char(r.send_day, 'YYYY-MM-DD'), 'pdf_blocks', r.pdf_blocks,
                            'planned', r.planned, 'switch_on', r.switch_on);
end $fn$;
revoke execute on function public.fn_customer_support_campaign_list_tick(timestamptz) from public, anon, authenticated;

commit;
