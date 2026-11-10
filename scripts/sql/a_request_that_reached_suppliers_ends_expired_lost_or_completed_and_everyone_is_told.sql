-- Seat: sales_engineer. Assigned: sales_engineer (customer-journey follow-up, 10 Nov 2026; founder ruling 1608).
--
-- MEASURED on origin/main: a request that REACHED suppliers had no end. fn_sales_engineer_closes_unreached_requests ends
-- only a request that reached nobody; nothing ended one that was matched and never quoted, one with quotes the customer
-- never acted on, or one revealed and never marked hired. Such a request stayed "Matching" / "Quotes in" / "Revealed" for
-- good: it kept taking notes and questions, it counted as open on the dashboard, and its suppliers were never told the
-- job was off. The reveal-follow-up nudges (day 2 and day 7 after the first quote) and the day-3/day-14 "did you hire?"
-- e-mail ask; neither closes anything.
--
-- THE OPERATING POLICY (decided by the IT/CEO side under the founder's "no decision goes to me" — ledger 1596, the
-- session's technical delegation — and recorded here and in docs/sales-engineer/REQUEST_LIFECYCLE.md as the default; every number
-- is a decision_policy row, so it is tuned there, never in this file):
--   A. EXPIRED. A part that reached suppliers but received NO quote within request_no_quote_expiry_days (21) of the first
--      supplier being sent it is closed as 'expired', lost_reason "no matched supplier quoted in time". The sales engineer
--      gets a coverage_gap action naming its trades and emirate (the same kind flagCoverageGap files at posting).
--   B. LOST. A part with quotes and no reveal, cancel or hire gets ONE reminder request_quoted_reminder_days (14) after
--      its LAST quote, and is closed as 'lost' request_quoted_lost_days (30) after its last quote.
--   C. COMPLETED WITHOUT AWARD. A revealed part with no hire and no completion is closed 'completed' with outcome
--      'completed_without_award' request_revealed_close_days (60) after its last reveal — unless the customer's follow-up
--      answer says otherwise: "yes, hired" completes it as hired (fn_customer_followup_answer), and "not yet" given within
--      request_revealed_not_yet_grace_days (30) holds it open.
--   In every case the customer is told (customer_support's duty door, in the request's language) and every matched
--   supplier is told (customer_support's delivery door, in English; the revealed supplier is not told "no award").
--   A part is a request with no per-trade children, or one child of a split; a split's parent is closed 'closed' once
--   every child has closed. A late Hire still records: complete_inquiry awards while hired_supplier_id is null.
-- Fixtures: the duty touches only real customers; with qd.duty_fixtures = 'on' (a probe, in its own transaction) only
-- ZZ DEMO / @example.invalid ones. Every address is passed through fn_seat_clock_refusal first.
-- NOT CHANGED: the reveal nudges, the hire follow-up, the unreached closer (a_request_the_matcher_could_not_reach_...).
-- Runs as the seat duty sales_engineer.request_outcomes, every 6 hours, on the seat-duty machinery (fn_seat_duties_tick).
-- prevented by: scripts/checks/a_request_that_reached_suppliers_has_an_end.test.mjs and this file's _probe.sql.
-- Pending until the release applies it: scripts/sql/pending/a_request_that_reached_suppliers_ends_expired_lost_or_completed_and_everyone_is_told.txt

insert into public.decision_policy (key, value, description) values
  ('request_no_quote_expiry_days', '21'::jsonb, 'fn_sales_engineer_request_outcomes A: days after the first supplier was sent a request (min inquiry_matches.sent_at) at which a part with no quote at all is closed as expired, "no matched supplier quoted in time". Sales engineer, 10 Nov 2026.'),
  ('request_quoted_reminder_days', '14'::jsonb, 'fn_sales_engineer_request_outcomes B: days after the LAST quote on a part with no reveal, cancel or hire at which the customer gets the one reminder. Sales engineer, 10 Nov 2026.'),
  ('request_quoted_lost_days', '30'::jsonb, 'fn_sales_engineer_request_outcomes B: days after the LAST quote on a part with no reveal, cancel or hire at which it is closed as lost. Sales engineer, 10 Nov 2026.'),
  ('request_revealed_close_days', '60'::jsonb, 'fn_sales_engineer_request_outcomes C: days after the last reveal on a part with no hire or completion at which it is closed as completed without award. Sales engineer, 10 Nov 2026.'),
  ('request_revealed_not_yet_grace_days', '30'::jsonb, 'fn_sales_engineer_request_outcomes C: a follow-up answered "not yet" this many days ago or less holds a revealed part open past request_revealed_close_days. Sales engineer, 10 Nov 2026.')
on conflict (key) do nothing;

-- The matched suppliers of one part are told it is closed, once each (English: suppliers are always written in English).
create or replace function public.fn_sales_engineer_tells_matched_suppliers(p_unit uuid, p_kind text, p_fixture boolean, p_days integer default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare u public.inquiries; l record; v_job text; v_body text; v_why text; v_d jsonb; v_told int := 0; v_not int := 0;
begin
  if p_kind not in ('expired', 'lost', 'no_award') then raise exception 'a closed part is expired, lost or no_award, not %', p_kind; end if;
  select * into u from public.inquiries where id = p_unit;
  if not found then return jsonb_build_object('told', 0, 'reason', 'no such request'); end if;
  v_job := 'the ' || coalesce(public.fn_trade_label(u.category, 'en'), 'job') || coalesce(' job in ' || nullif(btrim(u.emirate), ''), ' job')
           || ' (request ' || coalesce(u.rfq_no::text, '-') || ')';
  v_body := case p_kind
    when 'expired' then 'The customer''s request for ' || v_job || ', which you were invited to quote, is now closed: no quotation reached the customer in time. No quote is needed for it any more. Thank you for your time.'
    when 'lost' then 'The customer''s request for ' || v_job || ', which you were invited to quote, is now closed: the customer did not go ahead with any quote within ' || coalesce(p_days, 30) || ' days of the last one. A quote you sent will not be used. Thank you for taking the time to quote.'
    else 'The customer''s request for ' || v_job || ', which you were invited to quote, is now closed on QuotesDone without an award to your company. A quote you sent will not be used. Thank you for taking the time to quote.' end;
  for l in select le.id, lower(btrim(coalesce(nullif(btrim(le.claimed_by), ''), le.email, ''))) as to_email
             from (select distinct x.supplier_id from public.inquiry_matches x where x.inquiry_id = p_unit) x
             join public.leads le on le.id = x.supplier_id
            where not coalesce(le.banned, false) and not public.fn_is_sanctioned_lead(le.id)
              -- the supplier the customer revealed is not told "no award": they hold the customer's contact
              and not (p_kind = 'no_award' and exists (select 1 from public.transactions t where t.inquiry_id = p_unit and t.supplier_id = le.id and t.revealed_at is not null)) loop
    v_why := public.fn_seat_clock_refusal(p_fixture, l.to_email, 'rfq_closed');
    if v_why is not null then v_not := v_not + 1; continue; end if;
    v_d := public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'rfq_closed', 'requested_by', 'sales_engineer', 'channel', 'email', 'to_email', l.to_email, 'to_role', 'supplier',
      'lead_id', l.id, 'inquiry_id', p_unit, 'lang', 'en', 'subject', 'A request you were invited to quote is closed', 'body', v_body,
      'dedupe_key', 'rfq_closed:' || p_unit || ':' || l.id)));
    if coalesce(v_d->0->>'status', '') in ('done', 'demo_captured', 'pending', 'claimed') then v_told := v_told + 1; else v_not := v_not + 1; end if;
  end loop;
  return jsonb_build_object('told', v_told, 'not_told', v_not);
end $fn$;
revoke execute on function public.fn_sales_engineer_tells_matched_suppliers(uuid, text, boolean, integer) from public, anon, authenticated;

create or replace function public.fn_sales_engineer_request_outcomes(p_at timestamptz default now())
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_expiry int := public.fn_seat_clock_policy('request_no_quote_expiry_days', 21)::int;
  v_remind int := public.fn_seat_clock_policy('request_quoted_reminder_days', 14)::int;
  v_lost int := public.fn_seat_clock_policy('request_quoted_lost_days', 30)::int;
  v_close int := public.fn_seat_clock_policy('request_revealed_close_days', 60)::int;
  v_grace int := public.fn_seat_clock_policy('request_revealed_not_yet_grace_days', 30)::int;
  r record; v_lang text; v_ar boolean; v_name text; v_ref text; v_trade text; v_link text; v_kind text; v_subj text; v_body text;
  v_why text; v_cust jsonb; v_sup jsonb; v_held boolean;
  n_exp int := 0; n_rem int := 0; n_lost int := 0; n_done int := 0; n_parents int := 0; v_out jsonb := '[]'::jsonb;
begin
  for r in
    with units as (
      select u.id, u.parent_inquiry_id, u.category, u.emirate, u.rfq_no, u.status, u.rfq_ready, u.customer_id,
             c.full_name, c.email, c.locale,
             (select min(m.sent_at) from public.inquiry_matches m where m.inquiry_id = u.id) as first_sent,
             (select count(distinct m.supplier_id) from public.inquiry_matches m where m.inquiry_id = u.id) as matched,
             (select max(q.created_at) from public.quotes q where q.inquiry_id = u.id
                and coalesce(q.status, '') not in ('draft', 'withdrawn', 'cancelled', 'rejected')) as last_quote,
             (select max(t.revealed_at) from public.transactions t where t.inquiry_id = u.id and t.revealed_at is not null
                and coalesce(t.refund_status, '') not in ('refunded', 'succeeded')) as last_reveal
        from public.inquiries u
        join public.customers c on c.id = u.customer_id
       where coalesce(u.status, '') not in ('split', 'closed', 'cancelled', 'completed', 'expired', 'lost')
         and u.hired_supplier_id is null
         and not exists (select 1 from public.inquiries k where k.parent_inquiry_id = u.id)
         and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
         and not coalesce(c.banned, false))
    select x.*,
           case when x.last_reveal is not null then
                  case when x.last_reveal <= p_at - make_interval(days => v_close)
                         and not exists (select 1 from public.customer_followup f join public.transactions t on t.id = f.transaction_id
                                          where t.inquiry_id = x.id and f.hired = 'not_yet' and f.answered_at > p_at - make_interval(days => v_grace))
                       then 'no_award' end
                when x.last_quote is not null then
                  case when x.last_quote <= p_at - make_interval(days => v_lost) then 'lost'
                       when x.last_quote <= p_at - make_interval(days => v_remind) then 'remind' end
                when x.matched > 0 and x.first_sent <= p_at - make_interval(days => v_expiry) then 'expired'
           end as kind
      from units x
     order by coalesce(x.last_reveal, x.last_quote, x.first_sent)
     limit 200
  loop
    continue when r.kind is null;
    v_lang := public.fn_customer_message_lang(r.id, r.locale);
    v_ar := v_lang = 'ar';
    v_ref := 'QD-' || coalesce(r.rfq_no::text, '-');
    v_name := coalesce(nullif(btrim(r.full_name), ''), case when v_ar then 'عميلنا الكريم' else 'there' end);
    v_trade := coalesce(public.fn_trade_label(r.category, v_lang), case when v_ar then 'هذا التخصص' else 'this trade' end);
    v_link := case when v_ar then 'https://quotesdone.com/ar/me' else 'https://quotesdone.com/me' end;
    v_held := not coalesce(r.rfq_ready, false);

    if r.kind = 'remind' then
      -- ONE reminder per part, keyed on the part: a later quote moves the lost clock, never sends a second one
      v_subj := case when v_ar then 'عروضكم على طلب ' || v_ref || ' ما زالت بانتظاركم' else 'Your quotes on ' || v_ref || ' are still waiting' end;
      v_body := case when v_ar then
          'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
          || 'مضى ' || public.fn_ar_days(v_remind) || ' على آخر عرض سعر وصلكم على طلبكم ' || v_ref || ' (' || v_trade || ')، ولم تكشفوا بعدُ بيانات أي مورّد. '
          || 'وإذا لم تختاروا أحد العروض خلال ' || public.fn_ar_days(v_lost - v_remind) || ' أخرى أغلقنا الطلب وأبلغنا الموردين، ولا يلزمكم أي مبلغ. '
          || 'وإن كنتم لا تحتاجون إلى الطلب بعد الآن، فبإمكانكم إلغاؤه من حسابكم.' || chr(10) || chr(10)
          || 'افتحوا عروضكم من هنا: ' || v_link || chr(10) || chr(10)
          || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
        else
          'Dear ' || v_name || ',' || chr(10) || chr(10)
          || 'It has been ' || v_remind || ' days since the last quote on your request ' || v_ref || ' (' || v_trade || '), and you have not revealed a supplier yet. '
          || 'If you have not chosen one within ' || (v_lost - v_remind) || ' more days, we will close the request and tell the suppliers; there is nothing to pay. '
          || 'If you no longer need it, you can cancel it from your account.' || chr(10) || chr(10)
          || 'Open your quotes here: ' || v_link end;
      v_why := public.fn_seat_clock_refusal(v_fx, r.email, 'duty_request_quoted_reminder');
      v_cust := case when v_why is null then public.fn_customer_support_duty_send('request.quoted_reminder', r.id::text, 'customer', r.email, v_lang, v_subj, v_body, r.customer_id, null, r.id)
                     else jsonb_build_object('sent', false, 'reason', v_why) end;
      if coalesce((v_cust->>'sent')::boolean, false) then n_rem := n_rem + 1; end if;
      v_out := v_out || jsonb_build_array(jsonb_build_object('inquiry_id', r.id, 'kind', 'remind', 'customer', v_cust));
      continue;
    end if;

    -- the end of the part: the status first (the request is closed whether or not a message can be sent)
    update public.inquiries
       set status = case r.kind when 'expired' then 'expired' when 'lost' then 'lost' else 'completed' end,
           outcome = case r.kind when 'expired' then 'expired' when 'lost' then 'lost' else 'completed_without_award' end,
           lost_reason = case r.kind when 'expired' then 'no matched supplier quoted in time'
                                     when 'lost' then 'no decision ' || v_lost || ' days after the last quote'
                                     else 'no hire recorded ' || v_close || ' days after the reveal' end,
           completed_at = p_at, stage_changed_at = p_at
     where id = r.id and hired_supplier_id is null
       and coalesce(status, '') not in ('closed', 'cancelled', 'completed', 'expired', 'lost');
    if not found then continue; end if;
    update public.stalled_inquiry_rescue set cleared_at = p_at, cleared_why = 'request closed: ' || r.kind where inquiry_id = r.id and cleared_at is null;

    if r.kind = 'expired' then
      n_exp := n_exp + 1;
      v_kind := 'request.expired_no_quote';
      v_subj := case when v_ar then 'أغلقنا طلبكم ' || v_ref else 'We have closed your request ' || v_ref end;
      v_body := case when v_ar then
          'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
          || 'وصل طلبكم ' || v_ref || ' إلى ' || r.matched || ' من الموردين المختصين في ' || v_trade
          || case when v_held then '، وكان ما زال ينتظر منكم التفاصيل التي يحتاجون إليها لتسعيره' else '' end
          || '، ولم يرسل أيٌّ منهم عرض سعر خلال ' || public.fn_ar_days(v_expiry) || '، ولذلك أغلقناه. '
          || 'نعتذر عن ذلك، ولا يلزمكم أي مبلغ، ويسعدنا أن ترسلوا الطلب من جديد في أي وقت.' || chr(10) || chr(10)
          || 'ويمكنكم الاطلاع عليه في حسابكم: ' || v_link || chr(10) || chr(10)
          || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
        else
          'Dear ' || v_name || ',' || chr(10) || chr(10)
          || 'Your request ' || v_ref || ' reached ' || r.matched || case when r.matched = 1 then ' supplier' else ' suppliers' end || ' who cover ' || v_trade
          || case when v_held then ', while it was still waiting for the details they need from you to price it' else '' end
          || ', but none of them sent a quotation within ' || v_expiry || ' days, so we have closed it. '
          || 'We are sorry. There is nothing to pay, and you are welcome to send the request again at any time.' || chr(10) || chr(10)
          || 'You can see it in your account: ' || v_link end;
      -- the sales engineer's coverage finding for its trades: matched suppliers exist and none of them quoted
      insert into public.agent_actions (agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
      values ('sales_engineer', 'coverage_gap', 'pending', 'medium',
              left('A request reached suppliers and none quoted in ' || v_expiry || ' days: ' || coalesce(r.category, 'uncategorised') || ' / ' || coalesce(r.emirate, 'UAE'), 300),
              'The ' || r.matched || ' matched supplier(s) for ' || coalesce(r.category, 'this trade') || ' in ' || coalesce(r.emirate, 'the UAE')
                || ' did not quote within ' || v_expiry || ' days, so the request was closed as expired. Ask the matched suppliers why (capacity, scope, price), and recruit suppliers who quote this trade and emirate.',
              jsonb_build_object('signal', 'coverage_gap:no_quote:' || r.id, 'inquiry_id', r.id, 'category', r.category, 'emirate', r.emirate,
                                 'trades', to_jsonb(public.fn_taxonomy_trades_for(array[coalesce(r.category, '')])), 'matched', r.matched,
                                 'first_sent', r.first_sent, 'held_for_specs', v_held, 'path', 'fn_sales_engineer_request_outcomes', 'demo', v_fx),
              'inquiries', r.id::text);
    elsif r.kind = 'lost' then
      n_lost := n_lost + 1;
      v_kind := 'request.lost';
      v_subj := case when v_ar then 'أغلقنا طلبكم ' || v_ref else 'We have closed your request ' || v_ref end;
      v_body := case when v_ar then
          'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
          || 'مضى ' || public.fn_ar_days(v_lost) || ' على آخر عرض سعر وصلكم على طلبكم ' || v_ref || ' (' || v_trade || ') دون أن تختاروا أحدها، ولذلك أغلقنا الطلب وأبلغنا الموردين. '
          || 'لا يلزمكم أي مبلغ، ويسعدنا أن ترسلوا طلبًا جديدًا في أي وقت.' || chr(10) || chr(10)
          || 'ويمكنكم الاطلاع عليه في حسابكم: ' || v_link || chr(10) || chr(10)
          || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
        else
          'Dear ' || v_name || ',' || chr(10) || chr(10)
          || 'It has been ' || v_lost || ' days since the last quote on your request ' || v_ref || ' (' || v_trade || ') and none was chosen, so we have closed the request and told the suppliers. '
          || 'There is nothing to pay, and you are welcome to send a new request at any time.' || chr(10) || chr(10)
          || 'You can see it in your account: ' || v_link end;
    else
      n_done := n_done + 1;
      v_kind := 'request.completed_without_award';
      v_subj := case when v_ar then 'أغلقنا طلبكم ' || v_ref else 'We have closed your request ' || v_ref end;
      v_body := case when v_ar then
          'السيد/ ' || v_name || ' المحترم،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
          || 'مضى ' || public.fn_ar_days(v_close) || ' على كشفكم بيانات المورّد في طلبكم ' || v_ref || ' (' || v_trade || ')، ولم يُسجَّل لدينا أنكم تعاقدتم معه، ولذلك أغلقنا الطلب. '
          || 'وإن كنتم قد تعاقدتم معه، فاضغطوا "تعاقدتُ مع هذا المورّد" على عرضه في حسابكم أو ردّوا على هذه الرسالة، لنسجّل ذلك.' || chr(10) || chr(10)
          || 'حسابكم: ' || v_link || chr(10) || chr(10)
          || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
        else
          'Dear ' || v_name || ',' || chr(10) || chr(10)
          || 'It has been ' || v_close || ' days since you revealed a supplier on your request ' || v_ref || ' (' || v_trade || '), and no hire has been recorded, so we have closed the request. '
          || 'If you did hire them, press "I hired this supplier" on their quote in your account, or reply to this e-mail, and we will record it.' || chr(10) || chr(10)
          || 'Your account: ' || v_link end;
    end if;
    v_why := public.fn_seat_clock_refusal(v_fx, r.email, 'duty_' || replace(v_kind, '.', '_'));
    v_cust := case when v_why is null then public.fn_customer_support_duty_send(v_kind, r.id::text, 'customer', r.email, v_lang, v_subj, v_body, r.customer_id, null, r.id)
                   else jsonb_build_object('sent', false, 'reason', v_why) end;
    v_sup := public.fn_sales_engineer_tells_matched_suppliers(r.id, r.kind, v_fx, v_lost);
    v_out := v_out || jsonb_build_array(jsonb_build_object('inquiry_id', r.id, 'kind', r.kind, 'customer', v_cust, 'suppliers', v_sup));
  end loop;

  -- a split's parent ends when every part has ended
  with p as (
    select pr.id from public.inquiries pr
      join public.customers c on c.id = pr.customer_id
     where pr.status = 'split' and (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email)) = v_fx
       and exists (select 1 from public.inquiries k where k.parent_inquiry_id = pr.id)
       and not exists (select 1 from public.inquiries k where k.parent_inquiry_id = pr.id
                        and coalesce(k.status, '') not in ('closed', 'cancelled', 'completed', 'expired', 'lost')))
  update public.inquiries i set status = 'closed', outcome = coalesce(i.outcome, 'all parts closed'), completed_at = coalesce(i.completed_at, p_at), stage_changed_at = p_at
    from p where i.id = p.id;
  get diagnostics n_parents = row_count;

  return jsonb_build_object('expired', n_exp, 'reminded', n_rem, 'lost', n_lost, 'completed_without_award', n_done,
                            'split_parents_closed', n_parents, 'fixtures', v_fx, 'acted', v_out);
end $fn$;
revoke execute on function public.fn_sales_engineer_request_outcomes(timestamptz) from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.request_outcomes', 'sales_engineer', interval '6 hours', 'fn_sales_engineer_request_outcomes',
   'A request that reached suppliers ends: expired (no quote in 21 days, a coverage finding), one reminder 14 days after the last quote and lost at 30, completed without award 60 days after a reveal; the customer and the matched suppliers are told.',
   'scripts/sql/a_request_that_reached_suppliers_ends_expired_lost_or_completed_and_everyone_is_told.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- Verdict row (a DDL file, so no raise): the policy, the duty and the closed doors. The behaviour is the _probe.sql's.
select case
  when (select count(*) from public.decision_policy where key in ('request_no_quote_expiry_days', 'request_quoted_reminder_days',
         'request_quoted_lost_days', 'request_revealed_close_days', 'request_revealed_not_yet_grace_days')) <> 5
    then 'PROBE FAILED: a request-outcome policy row is missing'
  when not exists (select 1 from public.seat_duty where duty = 'sales_engineer.request_outcomes' and routine = 'fn_sales_engineer_request_outcomes')
    then 'PROBE FAILED: the duty sales_engineer.request_outcomes is not registered'
  when has_function_privilege('anon', 'public.fn_sales_engineer_request_outcomes(timestamptz)', 'execute')
    or has_function_privilege('anon', 'public.fn_sales_engineer_tells_matched_suppliers(uuid, text, boolean, integer)', 'execute')
    then 'PROBE FAILED: anon can run a request-outcome routine'
  else 'PROBE OK' end as verdict;
