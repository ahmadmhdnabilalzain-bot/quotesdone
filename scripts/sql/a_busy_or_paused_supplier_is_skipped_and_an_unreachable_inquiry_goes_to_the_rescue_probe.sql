-- PROBE (never applied): a busy or paused supplier is skipped, a busy date expires on its day, and an inquiry
-- nobody can reach is flagged to the stalled-inquiry rescue and cleared when it can be reached again.
-- Seat: sales_engineer. Runs on production inside ONE block that always raises, so nothing it writes survives.
--
-- THE DATA IS ZZ DEMO ONLY. The supplier is an existing ZZ DEMO lead at @example.invalid that is matchable and
-- has a confirmed trade (29 Sep 2026: ZZ DEMO Interiors gypsum founderdemo, 126512, the only supplier
-- fn_match_capability(['gypsum']) returns). The customer is an existing ZZ DEMO customer at @example.invalid.
-- The inquiries and matches are made here. `session_replication_role = replica` stops every trigger for this
-- transaction only, so an inquiry insert queues no mail; the raise rolls every row back.
--
-- CONTROLS, so a pass is not vacuous: the supplier must be reached with no availability row before anything
-- else is asserted, and each "skipped" is followed by a "reached again".
--
-- Run: scripts/checks/a_busy_or_paused_supplier_is_skipped_and_an_unreachable_inquiry_goes_to_the_rescue.test.mjs
-- (while the change is pending it runs the change's file first, in the same rolled-back transaction).
do $probe$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_lead bigint; v_trade text; v_cust uuid; v_inq uuid; v_inq2 uuid; v_inq3 uuid;
  f text := ''; o jsonb := '{}'::jsonb; v jsonb; x record;
  reached boolean;
begin
  set local session_replication_role = replica;

  select l.id, sc.trades[1] into v_lead, v_trade
    from public.leads l join public.supplier_capabilities sc on sc.supplier_id = l.id
   where l.company_name ~* '^\s*zz\s*demo' and l.email like '%@example.invalid'
     and sc.confirmed_at is not null and cardinality(sc.trades) > 0
     and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
   order by l.id limit 1;
  select c.id into v_cust from public.customers c
   where c.full_name ~* '^\s*zz\s*demo' and c.email like '%@example.invalid' order by c.created_at limit 1;
  if v_lead is null or v_cust is null then
    raise exception 'CHK<<{"skipped":"no matchable ZZ DEMO supplier with a confirmed trade, or no ZZ DEMO customer"}>>';
  end if;
  o := o || jsonb_build_object('lead', v_lead, 'trade', v_trade);
  delete from public.supplier_availability where supplier_id = v_lead;   -- start from "no row" (rolled back)

  -- 0. control: with no row he is available and reached.
  reached := exists (select 1 from public.fn_match_capability(array[v_trade], p_limit := 500) m where m.supplier_id = v_lead);
  if not reached then raise exception 'CHK<<{"skipped":"the ZZ DEMO supplier is not reached even with no availability row; another gate excludes him"}>>'; end if;

  -- 1. busy until tomorrow: skipped, and the portal says busy.
  v := public.fn_supplier_set_availability(v_lead, 'busy', v_today + 1, 'probe');
  if not coalesce((v->>'ok')::boolean, false) then f := f || 'setting busy until tomorrow was refused: ' || v::text || '; '; end if;
  if exists (select 1 from public.fn_match_capability(array[v_trade], p_limit := 500) m where m.supplier_id = v_lead) then f := f || 'a busy supplier was still matched; '; end if;
  if public.fn_supplier_availability_of(v_lead)->>'state' <> 'busy' then f := f || 'the portal does not read busy; '; end if;

  -- 2. the date comes (written straight to the row: the writer refuses a date that is not in the future):
  --    matched again at read time, before any clock; then the duty rewrites the row to available.
  update public.supplier_availability set busy_until = v_today where supplier_id = v_lead;
  if not exists (select 1 from public.fn_match_capability(array[v_trade], p_limit := 500) m where m.supplier_id = v_lead) then f := f || 'a busy date that has come still skips the supplier; '; end if;
  if public.fn_supplier_availability_of(v_lead)->>'state' <> 'available' then f := f || 'the portal still reads busy on the date; '; end if;
  v := public.fn_sales_engineer_availability_tick(true);
  o := o || jsonb_build_object('tick_after_expiry', v);
  select state, busy_until into x from public.supplier_availability where supplier_id = v_lead;
  if x.state <> 'available' or x.busy_until is not null then f := f || 'the duty did not expire the busy row (' || coalesce(x.state, 'null') || '); '; end if;

  -- 3. paused: skipped until he says otherwise.
  perform public.fn_supplier_set_availability(v_lead, 'paused', null, 'probe');
  if exists (select 1 from public.fn_match_capability(array[v_trade], p_limit := 500) m where m.supplier_id = v_lead) then f := f || 'a paused supplier was still matched; '; end if;

  -- 4. the writer refuses what is not a state or not a future date.
  if (public.fn_supplier_set_availability(v_lead, 'busy', v_today, 'probe')->>'code') is distinct from 'busy_date_not_future' then f := f || 'busy until today was accepted; '; end if;
  if (public.fn_supplier_set_availability(v_lead, 'busy', null, 'probe')->>'code') is distinct from 'busy_date_not_future' then f := f || 'busy with no date was accepted; '; end if;
  if (public.fn_supplier_set_availability(v_lead, 'busy', v_today + 400, 'probe')->>'code') is distinct from 'busy_date_too_far' then f := f || 'busy for over a year was accepted; '; end if;
  if (public.fn_supplier_set_availability(v_lead, 'holiday', null, 'probe')->>'code') is distinct from 'bad_state' then f := f || 'an unknown state was accepted; '; end if;
  if (select state from public.supplier_availability where supplier_id = v_lead) <> 'paused' then f := f || 'a refused write changed the row; '; end if;

  -- 5. an inquiry matched only to him, while he is paused: nobody can reach it -> flagged to the rescue.
  insert into public.inquiries (customer_id, category, trades, emirate, status, summary, scope_type, role_needed)
  values (v_cust, v_trade, array[v_trade], 'Dubai', 'sent', 'ZZ DEMO availability probe', 'single', 'supplier') returning id into v_inq;
  insert into public.inquiry_matches (inquiry_id, supplier_id, match_reason) values (v_inq, v_lead, 'ZZ DEMO availability probe');
  v := public.fn_stalled_inquiry_flag(v_inq, 'probe');
  o := o || jsonb_build_object('flag_paused', v);
  if not coalesce((v->>'flagged')::boolean, false) then f := f || 'an inquiry whose only supplier is paused was not flagged; '; end if;
  select * into x from public.stalled_inquiry_rescue where inquiry_id = v_inq;
  if x.inquiry_id is null or x.cleared_at is not null or x.reason <> 'no_reachable_supplier' then f := f || 'no open rescue row for it; '; end if;
  if (x.detail->>'matched_paused')::int is distinct from 1 or not x.fixture then f := f || 'the rescue row does not say one matched supplier is paused, or does not mark the fixture: ' || coalesce(x.detail::text, 'null') || '; '; end if;

  -- 6. he is available again: the duty clears the flag.
  perform public.fn_supplier_set_availability(v_lead, 'available', null, 'probe');
  v := public.fn_sales_engineer_availability_tick(true);
  if (select cleared_at from public.stalled_inquiry_rescue where inquiry_id = v_inq) is null then f := f || 'the flag was not cleared once the supplier was available; '; end if;

  -- 7. busy after dispatch: the duty flags it again, and names the day he is back.
  perform public.fn_supplier_set_availability(v_lead, 'busy', v_today + 3, 'probe');
  v := public.fn_sales_engineer_availability_tick(true);
  o := o || jsonb_build_object('tick_busy_after_dispatch', v);
  select * into x from public.stalled_inquiry_rescue where inquiry_id = v_inq;
  if x.cleared_at is not null then f := f || 'an inquiry whose supplier went busy after dispatch was not flagged again; '; end if;
  if (x.detail->>'earliest_back') is distinct from (v_today + 3)::text then f := f || 'the rescue row does not name the day he is back: ' || coalesce(x.detail::text, 'null') || '; '; end if;

  -- 8. an inquiry that matched nobody at all is flagged too (the dispatch path calls this the moment it lands on nobody).
  insert into public.inquiries (customer_id, category, trades, emirate, status, summary, scope_type, role_needed)
  values (v_cust, v_trade, array[v_trade], 'Dubai', 'sent', 'ZZ DEMO availability probe, no match', 'single', 'supplier') returning id into v_inq2;
  v := public.fn_stalled_inquiry_flag(v_inq2, 'probe');
  if not coalesce((v->>'flagged')::boolean, false) or (v->'detail'->>'matched')::int <> 0 then f := f || 'an inquiry that matched nobody was not flagged: ' || v::text || '; '; end if;
  if (v->'detail'->>'in_trade_busy')::int is distinct from 1 then f := f || 'the rescue row does not count the busy supplier of the trade: ' || v::text || '; '; end if;

  -- 9. a closed inquiry is no longer the rescue's.
  update public.inquiries set status = 'revealed' where id = v_inq2;
  perform public.fn_stalled_inquiry_flag(v_inq2, 'probe');
  if (select cleared_at from public.stalled_inquiry_rescue where inquiry_id = v_inq2) is null then f := f || 'a closed inquiry kept its rescue flag; '; end if;

  -- 10. the live duty (fixtures excluded) does not raise a flag on a ZZ DEMO inquiry.
  insert into public.inquiries (customer_id, category, trades, emirate, status, summary, scope_type, role_needed)
  values (v_cust, v_trade, array[v_trade], 'Dubai', 'sent', 'ZZ DEMO availability probe, fixture isolation', 'single', 'supplier') returning id into v_inq3;
  perform public.fn_sales_engineer_availability_tick(false);
  if exists (select 1 from public.stalled_inquiry_rescue where inquiry_id = v_inq3) then f := f || 'the live duty flagged a ZZ DEMO inquiry; '; end if;

  raise exception 'CHK<<%>>', (o || jsonb_build_object('failures', f))::text;
end $probe$;
