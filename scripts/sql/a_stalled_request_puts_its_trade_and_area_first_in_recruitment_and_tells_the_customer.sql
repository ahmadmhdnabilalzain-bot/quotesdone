-- A STALLED REQUEST PUTS ITS TRADE AND AREA FIRST IN RECRUITMENT AND TELLS THE CUSTOMER.
-- Seat: sales_engineer. Founder ledger 1018, round 3, item 1 (29 Sep 2026):
--   "An inquiry with no quotes 48 hours after matching triggers targeted recruitment for that trade and area: queue
--    uninvited leads first, using marketing's gap ranking. The customer gets an honest update in their chosen inquiry
--    language. Suppliers always get English. Keep all the existing invite brakes, caps and the founder's go switch.
--    Plain code."
--
-- MEASURED BEFORE THIS FILE (production htdblwldjkcgjvmqkbeh, 29 Sep 2026 07:21 UTC, read-only):
--   * 3 inquiries, all belonging to the two founder-demo customers (@example.invalid): 2 'quoted', 1 'revealed'.
--     So 0 real requests are stalled today, and 0 would be rescued by the daily run (fixtures are skipped).
--   * Nothing looks at a request with NO quote at all. fn_rfq_short_of_quotes_tick widens the SAME matcher's list 8 h
--     before the 24 h deadline and reminds the invited suppliers; it never recruits a supplier who is not registered.
--   * The invitation queue already orders its pool: fn_supplier_invite_candidates puts a lead in a trade the sales
--     engineer marked 'recruit' (supply_gap) first, then a lead in a trade marketing planned, by the plan's rank
--     (marketing_gap_recruitment_plan, 217 plans). A 'recruit' gap closes itself as soon as the trade has 10 matchable
--     suppliers, so a request stalled in a trade that has 10 silent suppliers would never be recruited for.
--   * 17,401 leads are eligible for a first invitation. invite_enabled = false and supplier_outreach_golive = false:
--     the founder's go switch is off, so enqueue_supplier_invites queues nothing today.
--
-- WHAT THIS ADDS (plain code; no model is asked anything):
--   1. decision_policy 'stalled_inquiry_rescue_hours' = 48 (the CEO can change it; inserted once, never overwritten).
--   2. public.inquiry_rescue: one row per stalled request - its trades (taxonomy codes, fn_taxonomy_trades_for), its
--      emirate, when it was first matched, how many uninvited eligible leads that trade and area had, marketing's
--      best rank for them, what the customer was told, and when and why the rescue ended (a quote arrived, or the
--      request closed).
--   3. fn_sales_engineer_stalled_inquiry_rescue (seat_duty 'sales_engineer.stalled_inquiry_rescue', every 30 minutes):
--      a request first matched 48 h ago or more, still open, with no quote row at all (a held draft counts as a quote:
--      that supplier answered, and recruiting is not the fix) is opened as a rescue. Then:
--        a. its trade and area go to the FRONT of the invitation queue (item 5) while the rescue is open;
--        b. enqueue_supplier_invites() is called once in that tick, UNCHANGED: the founder's go switch
--           (invite_enabled + supplier_outreach_golive), the UAE weekend and public-holiday holds, the morning inbox
--           placement gate, the Dubai sending window, the daily cap (invite_daily_cap and its warm-up) and both bounce
--           and complaint brakes all still decide whether anything is queued and how much. Nothing here writes a
--           supplier_invite row itself;
--        c. the customer is told once, in the language they chose for the request (inquiries.lang), exactly what is
--           true: no quote yet, their trade and area are now first in supplier recruitment - or, when no uninvited lead
--           is left for that trade and area, that we are sourcing new suppliers - and that the request stays open;
--        d. no uninvited lead left: the finding inquiry_rescue:no_uninvited_leads:<trades>:<emirate>, owned by
--           marketing (the seat that finds recruitment sources), raised by the sales engineer. Closed by the same duty
--           when a lead appears or the rescue ends. It is registered in every_alarm_is_quiet_on_a_healthy_day.
--      A fixture request (ZZ DEMO / @example.invalid customer) is rescued only when p_include_fixtures is true (the probe),
--      writes only to a fixture address (fn_seat_clock_refusal), and never moves the real invitation queue.
--   4. Suppliers: nothing new is written to a supplier. The only supplier messages this causes are the invitations
--      enqueue_supplier_invites queues, and those are English by construction (fn_supplier_invite_candidates' lang is
--      'en'; a04/z05 on notifications refuse anything else).
--   5. fn_supplier_invite_candidates is redefined in the companion file
--      a_stalled_request_puts_its_trade_and_area_first_in_the_invitation_queue.sql (sorted after this one): a lead in the trade
--      and emirate of an open, real rescue ranks -1, ahead of the supply-gap 'recruit' tier (0) and the marketing-plan tier
--      (1); inside every tier the order is marketing's gap ranking (plan_rank), as before.
--   6. inquiry_rescue joins the daily table export (fn_table_export_list, redefined from its canonical body in
--      the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql, MANIFEST 1879, with only that row added).
--      It has no *_path column, so it has no place in the backup registry.
--
-- Prevented by: scripts/checks/a_stalled_request_is_rescued_through_the_invitation_queue.test.mjs (static: the tier is
-- first (companion file), nothing bypasses enqueue_supplier_invites, both languages; live: this file + its _probe.sql, aborted).
-- Pending until the release applies it: scripts/sql/pending/a_stalled_request_puts_its_trade_and_area_first_in_recruitment_and_tells_the_customer.txt

-- ── 1. the setting ─────────────────────────────────────────────────────────────────────────────────────────────
insert into public.decision_policy (key, value, description) values
  ('stalled_inquiry_rescue_hours', '48'::jsonb,
   'fn_sales_engineer_stalled_inquiry_rescue: hours after a request was first sent to matched suppliers (min inquiry_matches.sent_at) at which a request with no quote at all puts its trade and area first in supplier recruitment and the customer is told. Founder ledger 1018, 29 Sep 2026.')
on conflict (key) do nothing;

-- ── 2. the record ──────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.inquiry_rescue (
  inquiry_id     uuid primary key references public.inquiries(id) on delete cascade,
  trades         text[] not null default '{}'::text[],
  emirate        text,
  matched_at     timestamptz not null,
  stalled_hours  numeric not null,
  uninvited_pool integer not null default 0 check (uninvited_pool >= 0),
  plan_rank      integer,
  fixture        boolean not null default false,
  finding_key    text,
  customer_notice jsonb,
  enqueue_result jsonb,
  opened_at      timestamptz not null default now(),
  measured_at    timestamptz not null default now(),
  closed_at      timestamptz,
  close_reason   text check (close_reason is null or close_reason in ('quoted', 'request_closed')),
  check ((closed_at is null) = (close_reason is null))
);
create index if not exists inquiry_rescue_open on public.inquiry_rescue (inquiry_id) where closed_at is null;
alter table public.inquiry_rescue enable row level security;
drop policy if exists inquiry_rescue_service_role_only on public.inquiry_rescue;
create policy inquiry_rescue_service_role_only on public.inquiry_rescue
  as permissive for all to public using (false) with check (false);
revoke all on public.inquiry_rescue from anon, authenticated;
comment on table public.inquiry_rescue is
  'A request with no quote 48 h after matching: its trade and area go first in supplier recruitment while open, and the customer is told once. Owner: sales_engineer (fn_sales_engineer_stalled_inquiry_rescue). Founder ledger 1018, 29 Sep 2026.';

-- ── 3. the pool: uninvited leads a first invitation could reach, for a trade and an area ─────────────────────────
-- The eligible set is enqueue's own (fn_supplier_invite_eligible_ids). ponytail: the count does not apply the
-- one-invitation-per-company rule the queue applies, so it can overstate by the leads of companies already invited;
-- it answers "is anybody left", which is what the customer's message and the finding need.
create or replace function public.fn_sales_engineer_rescue_pool(p_trades text[], p_emirate text)
returns integer
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select count(*)::int
    from public.leads l
   where l.id in (select e.id from public.fn_supplier_invite_eligible_ids() e(id))
     and l.invite_trades && coalesce(p_trades, '{}'::text[])
     and (p_emirate is null or p_emirate = 'UAE' or l.emirate = p_emirate)
$fn$;
revoke execute on function public.fn_sales_engineer_rescue_pool(text[], text) from public, anon, authenticated;

-- ── 4. the customer's update, in the language of the request ──────────────────────────────────────────────────
-- Written in the register of fn_seat_clock_compose (formal Gulf business correspondence, the formal plural), not
-- translated. It says only what is true whatever the go switch says: the trade and area are first for the NEXT
-- invitations, or nobody is left and new suppliers are being sourced; the request stays open. No supplier is named.
create or replace function public.fn_sales_engineer_stalled_inquiry_notice(p_lang text, p jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_ar boolean := coalesce(p_lang, '') like 'ar%';
  v_lang text := case when coalesce(p_lang, '') like 'ar%' then 'ar' else 'en' end;
  v_name text := nullif(btrim(coalesce(p->>'name', '')), '');
  v_hours int := coalesce((p->>'hours')::numeric, 48)::int;
  v_pool int := coalesce((p->>'pool')::int, 0);
  v_site text; v_link text; v_trade text; v_trade_ar text; v_em text; v_em_ar text; v_where text; v_where_ar text;
  v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from public.app_secrets where key = 'public_site_url';
  v_link := coalesce(v_site, 'https://quotesdone.com') || '/' || v_lang || '/portal';
  select t.label, coalesce(t.label_ar, t.label) into v_trade, v_trade_ar
    from public.taxonomy_trade t
   where t.code = (public.fn_taxonomy_trades_for(array[coalesce(p->>'category', '')]))[1];
  v_trade := coalesce(v_trade, nullif(p->>'category', ''), 'your trade');
  v_trade_ar := coalesce(v_trade_ar, nullif(p->>'category', ''), 'تخصصكم');
  v_em := nullif(btrim(coalesce(p->>'emirate', '')), '');
  v_em_ar := case lower(coalesce(v_em, '')) when 'dubai' then 'دبي' when 'abu dhabi' then 'أبوظبي' when 'sharjah' then 'الشارقة'
               when 'ajman' then 'عجمان' when 'umm al quwain' then 'أم القيوين' when 'ras al khaimah' then 'رأس الخيمة'
               when 'fujairah' then 'الفجيرة' else v_em end;
  v_where := v_trade || coalesce(' in ' || v_em, '');
  v_where_ar := v_trade_ar || coalesce(' في ' || v_em_ar, '');

  if v_ar then
    v_subj := 'مستجدات طلبكم — ' || v_where_ar;
    v_body := coalesce('السادة/ ' || v_name || ' المحترمين،', 'عميلنا العزيز،') || E'\n\nتحية طيبة وبعد،\n\n'
      || 'مضت ' || v_hours || ' ساعة على إرسال طلبكم في مجال ' || v_where_ar
      || ' إلى الموردين المطابقين، ولم يصلنا أي عرض سعر حتى الآن. '
      || case when v_pool > 0
           then 'ولذلك قدّمنا مجال طلبكم ومنطقته على غيرهما في دعوة الموردين الجدد، فيكون الموردون الذين ندعوهم تاليًا ممن يستطيعون تسعير طلبكم. '
           else 'وليس في قائمتنا حاليًا موردون آخرون في هذا المجال في ' || coalesce(v_em_ar, 'الإمارات')
                || '، ولذلك نعمل على استقطاب موردين جدد له. ' end
      || 'ويبقى طلبكم مفتوحًا، وسنُعلمكم فور وصول أول عرض سعر.'
      || E'\n\nيمكنكم متابعة طلبكم عبر بوابتكم:\n\n' || v_link
      || E'\n\nوتفضلوا بقبول فائق الاحترام والتقدير،';
  else
    v_subj := 'An update on your request — ' || v_where;
    v_body := coalesce('Dear ' || v_name || ',', 'Dear Customer,') || E'\n\n'
      || 'It has been ' || v_hours || ' hours since your request for ' || v_where
      || ' was sent to the matching suppliers, and no quotation has arrived yet. '
      || case when v_pool > 0
           then 'We have therefore put your trade and area first in our supplier recruitment, so the next suppliers we invite are ones who can quote for your request. '
           else 'We have no further suppliers for this trade in ' || coalesce(v_em, 'the UAE')
                || ' on our list yet, so we are sourcing new ones for it. ' end
      || 'Your request stays open, and we will let you know as soon as the first quotation arrives.'
      || E'\n\nYou can follow your request in your portal:\n\n' || v_link;
  end if;
  return jsonb_build_object('lang', v_lang, 'subject', v_subj, 'body', v_body, 'link', v_link);
end
$fn$;
revoke execute on function public.fn_sales_engineer_stalled_inquiry_notice(text, jsonb) from public, anon, authenticated;

-- ── 5. the duty ─────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_sales_engineer_stalled_inquiry_rescue(p_include_fixtures boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_hours numeric := public.fn_seat_clock_policy('stalled_inquiry_rescue_hours', 48);
  r record; rw record; v_codes text[]; v_pool int; v_rank int; v_key text; v_to text; v_why text; v_dedupe text;
  m jsonb; v jsonb; v_notice jsonb; v_enq jsonb;
  v_opened int := 0; v_real int := 0; v_told int := 0; v_no_pool int := 0; v_closed int := 0; v_refilled int := 0;
  v_quiet int := 0; v_not_told jsonb := '[]'::jsonb;
begin
  -- (a) a rescue ends when its request has a quote, or is no longer open
  update public.inquiry_rescue x
     set closed_at = now(),
         close_reason = case when exists (select 1 from public.quotes q where q.inquiry_id = x.inquiry_id
                                             and coalesce(q.status, '') not in ('withdrawn', 'cancelled', 'rejected'))
                             then 'quoted' else 'request_closed' end
    from public.inquiries i
   where x.closed_at is null and i.id = x.inquiry_id
     and (exists (select 1 from public.quotes q where q.inquiry_id = x.inquiry_id
                   and coalesce(q.status, '') not in ('withdrawn', 'cancelled', 'rejected'))
          or coalesce(i.status, '') in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost'));
  get diagnostics v_closed = row_count;

  -- (b) an open rescue that had nobody to invite is measured again: a lead may have been imported since
  for rw in select * from public.inquiry_rescue
             where closed_at is null and uninvited_pool = 0 and cardinality(trades) > 0 and (p_include_fixtures or not fixture) loop
    v_pool := public.fn_sales_engineer_rescue_pool(rw.trades, rw.emirate);
    if v_pool > 0 then
      update public.inquiry_rescue set uninvited_pool = v_pool, finding_key = null, measured_at = now() where inquiry_id = rw.inquiry_id;
      v_refilled := v_refilled + 1;
    end if;
  end loop;

  -- (c) a stalled request: first matched v_hours ago or more (and within 30 days), still open, no quote row at all
  for r in
    select i.id, i.category, i.trades, i.emirate, i.lang, c.email as cemail, c.full_name as cname,
           public.fn_seat_clock_customer_is_fixture(c) as fixture, fm.first_sent
      from public.inquiries i
      join public.customers c on c.id = i.customer_id
      join lateral (select min(mm.sent_at) as first_sent from public.inquiry_matches mm where mm.inquiry_id = i.id) fm on true
     where fm.first_sent is not null
       and now() >= fm.first_sent + make_interval(secs => (v_hours * 3600)::double precision)
       and fm.first_sent > now() - interval '30 days'
       and coalesce(i.status, '') not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
       and not exists (select 1 from public.quotes q where q.inquiry_id = i.id
                        and coalesce(q.status, '') not in ('withdrawn', 'cancelled', 'rejected'))
       and not exists (select 1 from public.inquiry_rescue x where x.inquiry_id = i.id)
       and (p_include_fixtures or not public.fn_seat_clock_customer_is_fixture(c))
     order by fm.first_sent
  loop
    v_codes := coalesce(public.fn_taxonomy_trades_for(case when coalesce(cardinality(r.trades), 0) > 0 then r.trades
                                                           else array[coalesce(r.category, '')] end), '{}'::text[]);
    v_pool := case when cardinality(v_codes) > 0 then public.fn_sales_engineer_rescue_pool(v_codes, r.emirate) else 0 end;
    select min(p.rank) into v_rank from public.marketing_gap_recruitment_plan p
     where p.trade = any(v_codes) and (p.emirate = 'UAE' or p.emirate = r.emirate);
    v_key := case when v_pool = 0 then 'inquiry_rescue:no_uninvited_leads:'
                  || coalesce(nullif(array_to_string(v_codes, '+'), ''), coalesce(nullif(r.category, ''), 'unknown'))
                  || ':' || coalesce(r.emirate, 'UAE') end;
    insert into public.inquiry_rescue (inquiry_id, trades, emirate, matched_at, stalled_hours, uninvited_pool, plan_rank, fixture, finding_key)
    values (r.id, v_codes, r.emirate, r.first_sent, v_hours, v_pool, v_rank, r.fixture, v_key);
    v_opened := v_opened + 1;
    if not r.fixture and v_pool > 0 then v_real := v_real + 1; end if;

    -- the customer, once, in the language of the request; a fixture only ever to a fixture address
    m := public.fn_sales_engineer_stalled_inquiry_notice(r.lang,
           jsonb_build_object('name', r.cname, 'category', r.category, 'emirate', r.emirate, 'hours', v_hours, 'pool', v_pool));
    v_to := lower(btrim(coalesce(r.cemail, '')));
    v_dedupe := 'inquiry_rescue:' || r.id;
    v_why := public.fn_seat_clock_refusal(r.fixture, v_to, 'inquiry_rescue_update');
    if v_why is null and public.fn_seat_clock_asked(v_dedupe) then v_why := 'already told'; end if;
    if v_why is null then
      v := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'inquiry_rescue_update', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', v_to,
        'to_role', 'customer', 'inquiry_id', r.id, 'lang', m->>'lang', 'subject', m->>'subject', 'body', m->>'body',
        'dedupe_key', v_dedupe)));
      v_notice := jsonb_build_object('sent', coalesce(v->0->>'status', '') <> 'failed', 'lang', m->>'lang', 'delivery', v->0);
    else
      v_notice := jsonb_build_object('sent', false, 'lang', m->>'lang', 'reason', v_why);
    end if;
    if (v_notice->>'sent')::boolean then v_told := v_told + 1;
    else v_not_told := v_not_told || jsonb_build_array(jsonb_build_object('inquiry_id', r.id, 'reason', coalesce(v_notice->>'reason', v_notice#>>'{delivery,error}')));
    end if;
    update public.inquiry_rescue set customer_notice = v_notice where inquiry_id = r.id;

    -- nobody left to invite for this trade and area: marketing must find where they gather
    if v_pool = 0 then
      v_no_pool := v_no_pool + 1;
      perform public.fn_it_engineer_finding_upsert(v_key,
        left('A customer''s request has had no quote for ' || v_hours || ' h and no uninvited supplier is left to invite for '
             || coalesce(nullif(array_to_string(v_codes, ', '), ''), coalesce(r.category, 'its trade')) || ' in '
             || coalesce(r.emirate, 'the UAE'), 300),
        'public.inquiry_rescue / fn_sales_engineer_stalled_inquiry_rescue', 'customer_facing', 1,
        jsonb_build_object('inquiry_id', r.id, 'trades', to_jsonb(v_codes), 'emirate', r.emirate, 'owner_seat', 'marketing',
                           'duty', 'sales_engineer.stalled_inquiry_rescue', 'demo', r.fixture),
        '{}'::text[], array['a directory, association, chamber or trade fair where suppliers of this trade in this area gather'],
        'sales_engineer');
    end if;
  end loop;

  -- (d) the queue is offered the rescued trades now, through the one door that holds every brake
  if v_real > 0 then
    begin
      v_enq := jsonb_build_object('queued', public.enqueue_supplier_invites(), 'at', now());
    exception when others then
      v_enq := jsonb_build_object('error', left(sqlerrm, 300), 'at', now());
    end;
    update public.inquiry_rescue set enqueue_result = v_enq where opened_at = now() and not fixture and uninvited_pool > 0;
  end if;

  -- (e) a finding whose trade and area now has somebody to invite, or no open rescue, is closed
  for rw in select f.issue_key from public.it_engineer_finding f
             where f.closed_at is null and f.issue_key like 'inquiry_rescue:no_uninvited_leads:%'
               and not exists (select 1 from public.inquiry_rescue y where y.closed_at is null and y.finding_key = f.issue_key) loop
    perform public.fn_it_engineer_finding_close(rw.issue_key, 'closed by fn_sales_engineer_stalled_inquiry_rescue: the trade and area have an uninvited lead again, or the request is quoted or closed');
    v_quiet := v_quiet + 1;
  end loop;

  return jsonb_build_object('ok', true, 'hours', v_hours, 'opened', v_opened, 'opened_real_with_pool', v_real,
    'customers_told', v_told, 'not_told', v_not_told, 'no_uninvited_leads', v_no_pool, 'closed', v_closed,
    'refilled', v_refilled, 'findings_closed', v_quiet, 'enqueue', v_enq,
    'open', (select count(*) from public.inquiry_rescue where closed_at is null and (p_include_fixtures or not fixture)));
end
$fn$;
revoke execute on function public.fn_sales_engineer_stalled_inquiry_rescue(boolean) from public, anon, authenticated;

insert into public.seat_duty (duty, what, every, enabled, routine, owner_file, owner_seat) values
  ('sales_engineer.stalled_inquiry_rescue',
   'a request with no quote 48 h after matching puts its trade and area first in supplier recruitment (through enqueue_supplier_invites and every brake it holds) and the customer is told once in the request''s language; nobody left to invite is marketing''s finding',
   '30 minutes', true, 'fn_sales_engineer_stalled_inquiry_rescue',
   'scripts/sql/a_stalled_request_puts_its_trade_and_area_first_in_recruitment_and_tells_the_customer.sql', 'sales_engineer')
on conflict (duty) do nothing;

-- ── 6. the daily export ────────────────────────────────────────────────────────────────────────────────────────
-- Redefined from its canonical body (the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql,
-- MANIFEST 1879, the last definer on 29 Sep 2026) with only ('inquiry_rescue','inquiry') added. If another definition is
-- applied first, rebase this one onto it.
create or replace function public.fn_table_export_list()
returns table(table_name text, subject text, change_log text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select v.t, v.s,
         (select 'table_export_change' from public.table_export_change_tracked x where x.table_name = v.t)
  from (values
    ('customers','customer'), ('customer_preference','customer'), ('customer_calls','customer'), ('projects','customer'),
    ('leads','supplier'), ('lead_category','supplier'), ('lead_subcategory','supplier'), ('supplier_capabilities','supplier'),
    ('supplier_catalog','supplier'), ('supplier_product','supplier'), ('supplier_product_variant','supplier'),
    ('supplier_capability_confirmation','supplier'), ('supplier_collaboration','supplier'), ('supplier_collaboration_event','supplier'),
    ('supplier_negotiation_policy','supplier'), ('supplier_screening_hit','supplier'), ('supplier_lead_intake','supplier'),
    ('doc_reviews','supplier'), ('licence_renewal_ask','supplier'), ('outreach','supplier'), ('company_registration','company'),
    ('inquiries','inquiry'), ('inquiry_rescue','inquiry'), ('inquiry_intake','inquiry'), ('inquiry_matches','inquiry'), ('inquiry_requirement','inquiry'),
    ('inquiry_cancellations','inquiry'), ('inquiry_supplier_brief','inquiry'), ('inquiry_state_audit','inquiry'),
    ('inquiry_gate','inquiry'), ('inquiry_answer','inquiry'), ('inquiry_answer_document','inquiry'), ('inquiry_answer_scope','inquiry'),
    ('inquiry_workstream','inquiry'), ('inquiry_workstream_group','inquiry'), ('inquiry_workstream_requirement','inquiry'),
    ('inquiry_trade_candidate','inquiry'), ('inquiry_trade_clarification','inquiry'), ('inquiry_scope_disposition','inquiry'),
    ('rfq_archives','inquiry'), ('rfq_clarification','inquiry'),
    ('quotes','quote'), ('quote_items','quote'), ('quote_reviews','quote'), ('quote_review_messages','quote'),
    ('quote_requirements','quote'), ('quote_committed_items','quote'), ('quote_comparisons','quote'), ('quote_spec_hold','quote'),
    ('spec_alternative_offer','quote'), ('po_orders','quote'), ('po_vendors','quote'), ('questions','quote'), ('reviews','quote'),
    ('category_specs','quote rules'), ('category_quote_specs','quote rules'),
    ('transactions','payment'), ('reveal_invoices','payment'), ('supplier_dues','payment'), ('refunds','payment'),
    ('refund_case','payment'), ('refund_incident','payment'), ('refund_ceo_review','payment'), ('refund_ceo_check','payment'),
    ('refund_ladder_evidence','payment'), ('refund_status_transition','payment'), ('stripe_events','payment'),
    ('stripe_payout','payment'), ('stripe_dispute','payment'), ('charge_audit','payment'), ('pricing_config','payment'),
    ('gl_journal','accounting'), ('gl_journal_lines','accounting'), ('gl_expense_map','accounting'), ('expenses','accounting'),
    ('expense_entries','accounting'), ('bank_statement_intake','accounting'), ('bank_statement_line','accounting'),
    ('accountant_month_close','accounting'), ('accountant_issued_document','accounting'),
    ('messages','conversation'), ('chat_threads','conversation'), ('conversation_archive','conversation'),
    ('inbound_messages','conversation'), ('contact_messages','conversation'), ('complaint_tickets','conversation'),
    ('support_case','conversation'), ('support_notification','conversation'), ('support_document_intake','conversation'),
    ('wa_messages','conversation'), ('wa_conversation','conversation'), ('wa_turn','conversation'),
    ('wa_document_intake','conversation'), ('notifications','conversation'), ('agent_chats','conversation'),
    ('legal_reviews','legal'), ('pdpl_requests','legal'), ('pdpl_erase_files','legal'), ('email_suppressions','legal'),
    ('founder_instruction','decision'), ('company_policy_decision','decision'),
    ('kb_chunks','knowledge'), ('dept_library','knowledge'), ('ops_knowledge','knowledge'), ('agent_knowledge','knowledge'),
    ('sales_knowledge','knowledge'), ('ceo_knowledge','knowledge'), ('support_knowledge','knowledge'),
    ('accountant_knowledge','knowledge'), ('it_engineer_knowledge','knowledge'), ('employee_knowledge','knowledge'),
    ('marketing_post','marketing'), ('marketing_connection_check','marketing'), ('marketing_insight_day','marketing'),
    ('marketing_ad_spend_day','marketing'), ('marketing_duty_run','marketing'), ('marketing_report','marketing'),
    ('marketing_article','marketing'), ('marketing_prospect','marketing'), ('marketing_outreach_message','marketing'),
    ('marketing_platform_spec','marketing'), ('marketing_platform_spec_source','marketing'),
    ('marketing_campaign','marketing'), ('marketing_founder_request','marketing'), ('marketing_video_idea','marketing'), ('supplier_campaign_daily_list','supplier'), ('marketing_post_variant','marketing'),
    ('marketing_post_platform','marketing'), ('marketing_post_channel_result','marketing'), ('marketing_calendar_resend_decision','marketing'), ('marketing_post_metric','marketing'), ('marketing_first_touch','marketing'),
    ('marketing_goal','marketing'), ('marketing_scorecard_report','marketing'),
    ('marketing_asset_feature','marketing'), ('marketing_asset_perception','marketing'), ('marketing_asset_review','marketing'),
    ('marketing_insight_note','marketing'), ('marketing_month_plan','marketing'), ('marketing_plan_review_turn','marketing'),
    ('marketing_model_run','marketing'), ('marketing_trend_source','marketing'), ('marketing_trend','marketing'),
    ('marketing_geo_question','marketing'), ('marketing_geo_check','marketing'), ('marketing_review','marketing'), ('market_intel','marketing'), ('competitor','marketing'), ('marketing_knowledge','knowledge'),
    ('marketing_recruitment_source','marketing'), ('marketing_gap_recruitment_plan','marketing'), ('marketing_plan_doc','marketing'),
    ('table_export_change','backup')
  ) v(t, s)
  -- The sibling PRs' tables may not exist yet when this applies; backup/index.ts fails the whole day on a
  -- missing table, so ONLY those nine are skipped until their own file creates them. Every other table in the
  -- list still fails loudly if it disappears.
  where v.t not in ('marketing_platform_spec','marketing_platform_spec_source','marketing_campaign','marketing_post_variant',
                    'marketing_post_platform','marketing_post_metric','marketing_first_touch','marketing_goal','marketing_scorecard_report')
     or to_regclass('public.' || v.t) is not null
$fn$;

revoke execute on function public.fn_table_export_list() from public, anon, authenticated;
