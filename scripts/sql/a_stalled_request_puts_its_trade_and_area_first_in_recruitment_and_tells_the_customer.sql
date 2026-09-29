-- A STALLED REQUEST PUTS ITS TRADE AND AREA FIRST IN RECRUITMENT AND TELLS THE CUSTOMER.
-- Seat: sales_engineer. Founder ledger 1018, round 3, item 1 (29 Sep 2026):
--   "An inquiry with no quotes 48 hours after matching triggers targeted recruitment for that trade and area: queue
--    uninvited leads first, using marketing's gap ranking. The customer gets an honest update in their chosen inquiry
--    language. Suppliers always get English. Keep all the existing invite brakes, caps and the founder's go switch.
--    Plain code."
--
-- DEPENDS-ON #1105 (a_busy_or_paused_supplier_is_skipped_and_an_unreachable_inquiry_goes_to_the_rescue.sql). ONE SUBJECT,
-- ONE HOME (review of #1106, 29 Sep 2026): #1105 creates public.stalled_inquiry_rescue, the intake of the stalled-inquiry
-- rescue, and flags an inquiry nobody can reach ('no_reachable_supplier'). This file does NOT create a second table: it
-- extends that one, adds the second way in ('no_quote_48h'), and makes ONE routine own the rescue -
-- fn_sales_engineer_stalled_inquiry_rescue acts on every open row, whichever way it came in. #1105's flag stays the
-- intake for its own reason and clears only its own reason (fn_stalled_inquiry_flag, redefined here from #1105's body
-- with that one filter).
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
--   2. public.stalled_inquiry_rescue (#1105's) gains the rescue's own record: the trades (taxonomy codes,
--      fn_taxonomy_trades_for) and emirate recruited for, when it was first matched, how many uninvited eligible leads
--      that trade and area had, marketing's best rank for them, what the customer was told, the enqueue result, and
--      when the rescue acted. Its reason also admits 'no_quote_48h'. RLS and the service-role-only policy are #1105's.
--   3. fn_sales_engineer_stalled_inquiry_rescue (seat_duty 'sales_engineer.stalled_inquiry_rescue', every 30 minutes):
--      a. a request first matched 48 h ago or more, still open, with no quote row at all (a held draft counts as a quote:
--         that supplier answered, and recruiting is not the fix) is flagged 'no_quote_48h' - once per request;
--      b. every OPEN row, either reason, is acted on once: its trade and area go to the FRONT of the invitation queue
--         (companion file) while the row is open; enqueue_supplier_invites() is called once in that tick, UNCHANGED - the
--         founder's go switch (invite_enabled + supplier_outreach_golive), the UAE weekend and public-holiday holds, the
--         morning inbox placement gate, the Dubai sending window, the daily cap (invite_daily_cap and its warm-up) and
--         both bounce and complaint brakes still decide whether anything is queued. Nothing here writes a
--         supplier_invite row itself;
--      c. the customer is told once, in the language they chose for the request (inquiries.lang), exactly what is
--         true: no quote after 48 h, or no supplier who can take it on right now; their trade and area are first for
--         the next invitations - or, when no uninvited lead is left, that new suppliers are being sourced; and that the
--         request stays open;
--      d. no uninvited lead left: the finding stalled_inquiry_rescue:no_uninvited_leads:<trades>:<emirate>, owned by
--         marketing (the seat that finds recruitment sources), raised by the sales engineer; closed by the same duty
--         when a lead appears or the row closes. Registered in every_alarm_is_quiet_on_a_healthy_day;
--      e. a 'no_quote_48h' row closes when a quote arrives or the request closes (cleared_at / cleared_why, #1105's own
--         columns); a 'no_reachable_supplier' row is cleared by #1105's flag.
--      A fixture request (ZZ DEMO / @example.invalid customer) is rescued only when p_include_fixtures is true (the probe),
--      writes only to a fixture address (fn_seat_clock_refusal), and never moves the real invitation queue.
--   4. Suppliers: nothing new is written to a supplier. The only supplier messages this causes are the invitations
--      enqueue_supplier_invites queues, and those are English by construction (fn_supplier_invite_candidates' lang is
--      'en'; a04/z05 on notifications refuse anything else).
--   5. fn_supplier_invite_candidates is redefined in the companion file
--      a_stalled_request_puts_its_trade_and_area_first_in_the_invitation_queue.sql (sorted after this one): a lead in the
--      trade and emirate of an open, real rescue ranks -1, ahead of the supply-gap 'recruit' tier (0) and the
--      marketing-plan tier (1); inside every tier the order is marketing's gap ranking (plan_rank), as before.
--   6. stalled_inquiry_rescue joins the daily table export (fn_table_export_list, redefined from its canonical body in
--      the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql, MANIFEST 1879, with only
--      that row added). It has no *_path column, so it has no place in the backup registry.
--
-- Prevented by: scripts/checks/a_stalled_request_is_rescued_through_the_invitation_queue.test.mjs (static: one table,
-- the tier is first (companion file), nothing bypasses enqueue_supplier_invites, both languages; live: #1105's file,
-- this file, the companion and the _probe.sql in one aborted transaction).
-- Pending until the release applies it: scripts/sql/pending/a_stalled_request_puts_its_trade_and_area_first_in_recruitment_and_tells_the_customer.txt

-- ── 1. the setting ─────────────────────────────────────────────────────────────────────────────────────────────
insert into public.decision_policy (key, value, description) values
  ('stalled_inquiry_rescue_hours', '48'::jsonb,
   'fn_sales_engineer_stalled_inquiry_rescue: hours after a request was first sent to matched suppliers (min inquiry_matches.sent_at) at which a request with no quote at all puts its trade and area first in supplier recruitment and the customer is told. Founder ledger 1018, 29 Sep 2026.')
on conflict (key) do nothing;

-- ── 2. the record: #1105's intake, extended (one subject, one home) ────────────────────────────────────────────
alter table public.stalled_inquiry_rescue
  add column if not exists trades text[],
  add column if not exists emirate text,
  add column if not exists matched_at timestamptz,
  add column if not exists stalled_hours numeric,
  add column if not exists uninvited_pool integer,
  add column if not exists plan_rank integer,
  add column if not exists finding_key text,
  add column if not exists customer_notice jsonb,
  add column if not exists enqueue_result jsonb,
  add column if not exists acted_at timestamptz;
alter table public.stalled_inquiry_rescue drop constraint if exists stalled_inquiry_rescue_reason_check;
alter table public.stalled_inquiry_rescue add constraint stalled_inquiry_rescue_reason_check
  check (reason in ('no_reachable_supplier', 'no_quote_48h'));
alter table public.stalled_inquiry_rescue drop constraint if exists stalled_inquiry_rescue_pool_check;
alter table public.stalled_inquiry_rescue add constraint stalled_inquiry_rescue_pool_check check (uninvited_pool is null or uninvited_pool >= 0);
comment on table public.stalled_inquiry_rescue is
  'sales_engineer: the stalled-inquiry rescue (ledgers 1018 and 1023), one row per inquiry. Flagged by fn_stalled_inquiry_flag (no_reachable_supplier, #1105) or by fn_sales_engineer_stalled_inquiry_rescue (no_quote_48h); every open row is acted on by fn_sales_engineer_stalled_inquiry_rescue: its trade and area first in the invitation queue, the customer told once, marketing''s finding when nobody is left to invite.';

-- ── 3. #1105's intake clears only its own reason ───────────────────────────────────────────────────────────────
-- fn_stalled_inquiry_flag is #1105's body with ONE change, dated 29 Sep 2026 (review of #1106): the open flag it reads
-- and the flags it clears are its own reason's. A request rescued for having no quote after 48 h is not "cleared"
-- because a matched supplier is still reachable - reachable and silent is exactly why it was rescued.
create or replace function public.fn_stalled_inquiry_flag(p_inquiry_id uuid, p_by text default 'sales_engineer')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  i public.inquiries; v_fixture boolean; v_quotes int; v_matched int; v_reach int; v_busy int; v_paused int;
  v_blocked int; v_back date; v_trades text[]; v_trade_busy int; v_trade_paused int; v_trade_back date;
  v_open boolean; v_detail jsonb; v_by text := coalesce(nullif(btrim(p_by), ''), 'sales_engineer');
begin
  select * into i from public.inquiries where id = p_inquiry_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'no such inquiry'); end if;
  -- 29 Sep 2026 (review of #1106): only this intake's own reason
  v_open := exists (select 1 from public.stalled_inquiry_rescue where inquiry_id = i.id and cleared_at is null and reason = 'no_reachable_supplier');

  select count(*)::int into v_quotes from public.quotes q
   where q.inquiry_id = i.id
     and coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled')
     and q.stale_at is null;

  if coalesce(i.status, '') not in ('sent', 'quoted') or v_quotes > 0 then
    if v_open then
      update public.stalled_inquiry_rescue set cleared_at = now(),
             cleared_why = case when v_quotes > 0 then v_quotes || ' live quote(s)' else 'inquiry is ' || coalesce(i.status, 'null') end
       where inquiry_id = i.id and cleared_at is null and reason = 'no_reachable_supplier';   -- 29 Sep 2026: own reason only
    end if;
    return jsonb_build_object('ok', true, 'inquiry_id', i.id, 'flagged', false, 'cleared', v_open,
                              'why', case when v_quotes > 0 then 'quoted' else 'not open' end);
  end if;

  select count(*)::int,
         count(*) filter (where public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
                            and public.fn_supplier_available(av.state, av.busy_until))::int,
         count(*) filter (where not public.fn_supplier_available(av.state, av.busy_until) and av.state = 'busy')::int,
         count(*) filter (where not public.fn_supplier_available(av.state, av.busy_until) and av.state = 'paused')::int,
         count(*) filter (where not public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes))::int,
         min(av.busy_until) filter (where not public.fn_supplier_available(av.state, av.busy_until))
    into v_matched, v_reach, v_busy, v_paused, v_blocked, v_back
    from public.inquiry_matches m
    join public.leads l on l.id = m.supplier_id
    left join public.supplier_availability av on av.supplier_id = m.supplier_id
   where m.inquiry_id = i.id;

  if v_reach > 0 then
    if v_open then
      update public.stalled_inquiry_rescue set cleared_at = now(), cleared_why = v_reach || ' reachable supplier(s)'
       where inquiry_id = i.id and cleared_at is null and reason = 'no_reachable_supplier';   -- 29 Sep 2026: own reason only
    end if;
    return jsonb_build_object('ok', true, 'inquiry_id', i.id, 'flagged', false, 'cleared', v_open, 'reachable', v_reach);
  end if;

  -- Nobody can reach it. Say why, for the rescue: the matched suppliers' states, and the suppliers of its
  -- trades who confirmed their scope and are matchable but said busy or paused (the trade gate only: role,
  -- authority, value and emirate are the matcher's, not repeated here).
  v_trades := public.fn_taxonomy_trades_for(case when coalesce(cardinality(i.trades), 0) > 0 then i.trades
                                                 else array[coalesce(i.category, '')] end);
  select count(*) filter (where av.state = 'busy')::int, count(*) filter (where av.state = 'paused')::int, min(av.busy_until)
    into v_trade_busy, v_trade_paused, v_trade_back
    from public.supplier_capabilities sc
    join public.leads l on l.id = sc.supplier_id
    join public.supplier_availability av on av.supplier_id = sc.supplier_id
   where sc.confirmed_at is not null
     and sc.trades && coalesce(v_trades, '{}'::text[])
     and not (sc.excluded_trades && coalesce(v_trades, '{}'::text[]))
     and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
     and not public.fn_supplier_available(av.state, av.busy_until);

  select public.fn_seat_clock_customer_is_fixture(c) into v_fixture from public.customers c where c.id = i.customer_id;
  v_detail := jsonb_build_object(
    'matched', v_matched, 'reachable', 0, 'matched_busy', v_busy, 'matched_paused', v_paused, 'matched_not_matchable', v_blocked,
    'earliest_back', v_back, 'trades', to_jsonb(v_trades), 'category', i.category, 'emirate', i.emirate,
    'in_trade_busy', coalesce(v_trade_busy, 0), 'in_trade_paused', coalesce(v_trade_paused, 0), 'in_trade_earliest_back', v_trade_back,
    'matcher_unavailable', coalesce((i.routing->>'matcher_unavailable')::boolean, false), 'at', now());

  insert into public.stalled_inquiry_rescue (inquiry_id, reason, detail, fixture, flagged_at, flagged_by)
  values (i.id, 'no_reachable_supplier', v_detail, coalesce(v_fixture, false), now(), v_by)
  on conflict (inquiry_id) do update
     set detail = excluded.detail, fixture = excluded.fixture,
         -- an open flag keeps the time it was first raised; a cleared one is raised again from now
         flagged_at = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.flagged_at else excluded.flagged_at end,
         flagged_by = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.flagged_by else excluded.flagged_by end,
         cleared_at = null, cleared_why = null;
  return jsonb_build_object('ok', true, 'inquiry_id', i.id, 'flagged', true, 'new', not v_open, 'detail', v_detail);
end
$fn$;
revoke execute on function public.fn_stalled_inquiry_flag(uuid, text) from public, anon, authenticated;

-- ── 4. the pool: uninvited leads a first invitation could reach, for a trade and an area ─────────────────────────
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

-- ── 5. the customer's update, in the language of the request ──────────────────────────────────────────────────
-- Written in the register of fn_seat_clock_compose (formal Gulf business correspondence, the formal plural), not
-- translated. It says only what is true whatever the go switch says: why the request is in the rescue (no quote after
-- the hours, or nobody who can take it on now), that the trade and area are first for the NEXT invitations - or nobody
-- is left and new suppliers are being sourced - and that the request stays open. No supplier is named.
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
  v_unreachable boolean := coalesce(p->>'reason', '') = 'no_reachable_supplier';
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
      || case when v_unreachable
           then 'لم يصل طلبكم في مجال ' || v_where_ar || ' بعدُ إلى مورّد يستطيع تسعيره، إذ لا يتوفر حاليًا أيٌّ من الموردين المسجّلين في هذا المجال لتولّيه. '
           else 'مضت ' || v_hours || ' ساعة على إرسال طلبكم في مجال ' || v_where_ar
                || ' إلى الموردين المطابقين، ولم يصلنا أي عرض سعر حتى الآن. ' end
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
      || case when v_unreachable
           then 'Your request for ' || v_where || ' has not yet reached a supplier who can quote it: none of the suppliers registered for it can take it on right now. '
           else 'It has been ' || v_hours || ' hours since your request for ' || v_where
                || ' was sent to the matching suppliers, and no quotation has arrived yet. ' end
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

-- ── 6. the duty: the ONE routine that owns the rescue ──────────────────────────────────────────────────────────
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
  v_flagged int := 0; v_acted int := 0; v_real int := 0; v_told int := 0; v_no_pool int := 0; v_closed int := 0;
  v_refilled int := 0; v_quiet int := 0; v_not_told jsonb := '[]'::jsonb;
begin
  -- (a) a no-quote rescue ends when its request has a quote, or is no longer open (#1105's flag clears its own reason)
  update public.stalled_inquiry_rescue x
     set cleared_at = now(),
         cleared_why = case when exists (select 1 from public.quotes q where q.inquiry_id = x.inquiry_id
                                            and coalesce(q.status, '') not in ('withdrawn', 'cancelled', 'rejected'))
                            then 'quoted' else 'request closed' end
    from public.inquiries i
   where x.cleared_at is null and x.reason = 'no_quote_48h' and i.id = x.inquiry_id
     and (exists (select 1 from public.quotes q where q.inquiry_id = x.inquiry_id
                   and coalesce(q.status, '') not in ('withdrawn', 'cancelled', 'rejected'))
          or coalesce(i.status, '') in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost'));
  get diagnostics v_closed = row_count;

  -- (b) an open row that had nobody to invite is measured again: a lead may have been imported since
  for rw in select * from public.stalled_inquiry_rescue
             where cleared_at is null and acted_at is not null and uninvited_pool = 0 and cardinality(trades) > 0
               and (p_include_fixtures or not fixture) loop
    v_pool := public.fn_sales_engineer_rescue_pool(rw.trades, rw.emirate);
    if v_pool > 0 then
      update public.stalled_inquiry_rescue set uninvited_pool = v_pool, finding_key = null where inquiry_id = rw.inquiry_id;
      v_refilled := v_refilled + 1;
    end if;
  end loop;

  -- (c) the second way in: first matched v_hours ago or more (within 30 days), still open, no quote row at all, never
  --     rescued for this before. An open row of the other reason is already in the rescue.
  for r in
    select i.id, fm.first_sent, public.fn_seat_clock_customer_is_fixture(c) as fixture
      from public.inquiries i
      join public.customers c on c.id = i.customer_id
      join lateral (select min(mm.sent_at) as first_sent from public.inquiry_matches mm where mm.inquiry_id = i.id) fm on true
     where fm.first_sent is not null
       and now() >= fm.first_sent + make_interval(secs => (v_hours * 3600)::double precision)
       and fm.first_sent > now() - interval '30 days'
       and coalesce(i.status, '') not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
       and not exists (select 1 from public.quotes q where q.inquiry_id = i.id
                        and coalesce(q.status, '') not in ('withdrawn', 'cancelled', 'rejected'))
       and not exists (select 1 from public.stalled_inquiry_rescue x where x.inquiry_id = i.id
                        and (x.cleared_at is null or x.reason = 'no_quote_48h'))
       and (p_include_fixtures or not public.fn_seat_clock_customer_is_fixture(c))
     order by fm.first_sent
  loop
    insert into public.stalled_inquiry_rescue (inquiry_id, reason, detail, fixture, flagged_at, flagged_by, matched_at, stalled_hours)
    values (r.id, 'no_quote_48h', jsonb_build_object('first_sent', r.first_sent, 'hours', v_hours), r.fixture, now(),
            'sales_engineer.stalled_inquiry_rescue', r.first_sent, v_hours)
    on conflict (inquiry_id) do update
       set reason = excluded.reason, detail = excluded.detail, fixture = excluded.fixture, flagged_at = excluded.flagged_at,
           flagged_by = excluded.flagged_by, matched_at = excluded.matched_at, stalled_hours = excluded.stalled_hours,
           cleared_at = null, cleared_why = null, acted_at = null, customer_notice = null, enqueue_result = null,
           trades = null, uninvited_pool = null, plan_rank = null, finding_key = null;
    v_flagged := v_flagged + 1;
  end loop;

  -- (d) every open row not yet acted on, whichever way it came in: recruit its trade and area, tell the customer once
  for r in
    select x.inquiry_id as id, x.reason, x.fixture, i.category, i.trades, i.emirate, i.lang, c.email as cemail, c.full_name as cname
      from public.stalled_inquiry_rescue x
      join public.inquiries i on i.id = x.inquiry_id
      join public.customers c on c.id = i.customer_id
     where x.cleared_at is null and x.acted_at is null and (p_include_fixtures or not x.fixture)
     order by x.flagged_at
  loop
    v_codes := coalesce(public.fn_taxonomy_trades_for(case when coalesce(cardinality(r.trades), 0) > 0 then r.trades
                                                           else array[coalesce(r.category, '')] end), '{}'::text[]);
    v_pool := case when cardinality(v_codes) > 0 then public.fn_sales_engineer_rescue_pool(v_codes, r.emirate) else 0 end;
    select min(p.rank) into v_rank from public.marketing_gap_recruitment_plan p
     where p.trade = any(v_codes) and (p.emirate = 'UAE' or p.emirate = r.emirate);
    v_key := case when v_pool = 0 then 'stalled_inquiry_rescue:no_uninvited_leads:'
                  || coalesce(nullif(array_to_string(v_codes, '+'), ''), coalesce(nullif(r.category, ''), 'unknown'))
                  || ':' || coalesce(r.emirate, 'UAE') end;
    update public.stalled_inquiry_rescue
       set trades = v_codes, emirate = r.emirate, uninvited_pool = v_pool, plan_rank = v_rank, finding_key = v_key, acted_at = now()
     where inquiry_id = r.id;
    v_acted := v_acted + 1;
    if not r.fixture and v_pool > 0 then v_real := v_real + 1; end if;

    -- the customer, once, in the language of the request; a fixture only ever to a fixture address
    m := public.fn_sales_engineer_stalled_inquiry_notice(r.lang, jsonb_build_object('name', r.cname, 'category', r.category,
           'emirate', r.emirate, 'hours', v_hours, 'pool', v_pool, 'reason', r.reason));
    v_to := lower(btrim(coalesce(r.cemail, '')));
    v_dedupe := 'stalled_inquiry_rescue:' || r.id || ':' || r.reason;
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
    update public.stalled_inquiry_rescue set customer_notice = v_notice where inquiry_id = r.id;

    -- nobody left to invite for this trade and area: marketing must find where they gather
    if v_pool = 0 then
      v_no_pool := v_no_pool + 1;
      perform public.fn_it_engineer_finding_upsert(v_key,
        left('A customer''s request is in the stalled-inquiry rescue and no uninvited supplier is left to invite for '
             || coalesce(nullif(array_to_string(v_codes, ', '), ''), coalesce(r.category, 'its trade')) || ' in '
             || coalesce(r.emirate, 'the UAE'), 300),
        'public.stalled_inquiry_rescue / fn_sales_engineer_stalled_inquiry_rescue', 'customer_facing', 1,
        jsonb_build_object('inquiry_id', r.id, 'reason', r.reason, 'trades', to_jsonb(v_codes), 'emirate', r.emirate,
                           'owner_seat', 'marketing', 'duty', 'sales_engineer.stalled_inquiry_rescue', 'demo', r.fixture),
        '{}'::text[], array['a directory, association, chamber or trade fair where suppliers of this trade in this area gather'],
        'sales_engineer');
    end if;
  end loop;

  -- (e) the queue is offered the rescued trades now, through the one door that holds every brake
  if v_real > 0 then
    begin
      v_enq := jsonb_build_object('queued', public.enqueue_supplier_invites(), 'at', now());
    exception when others then
      v_enq := jsonb_build_object('error', left(sqlerrm, 300), 'at', now());
    end;
    update public.stalled_inquiry_rescue set enqueue_result = v_enq where acted_at = now() and not fixture and uninvited_pool > 0;
  end if;

  -- (f) a finding whose trade and area now has somebody to invite, or no open row, is closed
  for rw in select f.issue_key from public.it_engineer_finding f
             where f.closed_at is null and f.issue_key like 'stalled_inquiry_rescue:no_uninvited_leads:%'
               and not exists (select 1 from public.stalled_inquiry_rescue y where y.cleared_at is null and y.finding_key = f.issue_key) loop
    perform public.fn_it_engineer_finding_close(rw.issue_key, 'closed by fn_sales_engineer_stalled_inquiry_rescue: the trade and area have an uninvited lead again, or the rescue ended');
    v_quiet := v_quiet + 1;
  end loop;

  return jsonb_build_object('ok', true, 'hours', v_hours, 'flagged_no_quote', v_flagged, 'acted', v_acted,
    'acted_real_with_pool', v_real, 'customers_told', v_told, 'not_told', v_not_told, 'no_uninvited_leads', v_no_pool,
    'closed', v_closed, 'refilled', v_refilled, 'findings_closed', v_quiet, 'enqueue', v_enq,
    'open', (select count(*) from public.stalled_inquiry_rescue where cleared_at is null and (p_include_fixtures or not fixture)));
end
$fn$;
revoke execute on function public.fn_sales_engineer_stalled_inquiry_rescue(boolean) from public, anon, authenticated;

insert into public.seat_duty (duty, what, every, enabled, routine, owner_file, owner_seat) values
  ('sales_engineer.stalled_inquiry_rescue',
   'the ONE owner of the stalled-inquiry rescue: a request with no quote 48 h after matching is flagged, and every open row (no quote, or nobody reachable) puts its trade and area first in supplier recruitment (through enqueue_supplier_invites and every brake it holds) and tells the customer once in the request''s language; nobody left to invite is marketing''s finding',
   '30 minutes', true, 'fn_sales_engineer_stalled_inquiry_rescue',
   'scripts/sql/a_stalled_request_puts_its_trade_and_area_first_in_recruitment_and_tells_the_customer.sql', 'sales_engineer')
on conflict (duty) do nothing;

-- ── 7. the daily export ────────────────────────────────────────────────────────────────────────────────────────
-- Redefined from its canonical body (the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql,
-- MANIFEST 1879, the last definer on 29 Sep 2026) with only ('stalled_inquiry_rescue','inquiry') added (#1105 creates the
-- table and does not export it). If another definition is applied first, rebase this one onto it.
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
    ('inquiries','inquiry'), ('stalled_inquiry_rescue','inquiry'), ('inquiry_intake','inquiry'), ('inquiry_matches','inquiry'), ('inquiry_requirement','inquiry'),
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
