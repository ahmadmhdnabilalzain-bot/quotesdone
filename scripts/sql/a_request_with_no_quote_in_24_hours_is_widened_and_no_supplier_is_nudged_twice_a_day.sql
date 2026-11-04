-- A REQUEST WITH NO QUOTE IN 24 HOURS IS WIDENED, AND NO SUPPLIER IS NUDGED TWICE A DAY (founder ruling 1209, 13 Oct 2026).
-- Assigned: sales_engineer. Deterministic: templated copy (fn_seat_clock_compose), no model.
--
-- WHAT ALREADY DOES THE 24-HOUR PROMISE, and is reused rather than duplicated: the seat clock 'short_quotes'
-- (fn_rfq_short_of_quotes_tick, run by fn_seat_clocks_tick on every resilience_ping beat). Against the 24-hour quote
-- window (app_secrets sla_quote_hours = 24), for every open request short of three live quotes (zero included):
--   (a) from 8 hours before the deadline it WIDENS ONCE from the same matcher (fn_match_capability, exact trade, the
--       same need, value and emirate; demo pairs with demo only) and invites each new supplier with rfq_invite;
--   (b) it REMINDS each invited supplier who has not quoted, once per request (dedupe rfq_quote_reminder:<req>:<supplier>);
--   (c) at the deadline it TELLS THE CUSTOMER once, in the request's language (rfq_short_of_quotes).
-- So the widened invites, the one nudge and the customer's status notice exist. The one rule of 1209 they did not keep:
-- "no supplier is nudged twice in 24h". The dedupe is per request, so a supplier invited to three short requests got three
-- reminders the same day. Now a supplier reminded in the last 24 hours (any request) is not reminded again until the
-- 24 hours pass; the request still owes it its one reminder, which a later tick sends while the request is short.
-- The routine is CREATE OR REPLACE of a live one, so its ACL is kept (no revoke: the grants are unchanged).
--
-- prevented by: scripts/checks/a_request_with_no_quote_in_24_hours_is_widened_and_no_supplier_is_nudged_twice_a_day.test.mjs
-- probe: scripts/sql/a_request_with_no_quote_in_24_hours_is_widened_and_no_supplier_is_nudged_twice_a_day_probe.sql

create or replace function public.fn_rfq_short_of_quotes_tick(p_include_fixtures boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  -- the top-3 rule: the comparison report is the top 3 (founder rule). A constant, not a setting.
  c_target constant int := 3;
  v_window numeric; v_lead numeric := public.fn_seat_clock_policy('rfq_short_sweep_hours_before_deadline', 8);
  r record; s record; l public.leads; v jsonb; v_codes text[]; v_need text; v_value numeric; v_new int;
  v_swept int := 0; v_invited int := 0; v_reminded int := 0; v_told int := 0; v_skipped jsonb := '[]'::jsonb;
begin
  select nullif(regexp_replace(coalesce(value, ''), '[^0-9.]', '', 'g'), '')::numeric into v_window
    from public.app_secrets where key = 'sla_quote_hours';
  v_window := coalesce(v_window, 24);

  for r in
    with open_rfq as (
      select i.*, c.email as cemail, coalesce(i.lang, c.locale) as clocale,   -- the customer: the inquiry's own language (founder, 28 Sep 2026)
             c.full_name as cname,
             public.fn_seat_clock_customer_is_fixture(c) as fixture,
             (select min(m.sent_at) from public.inquiry_matches m where m.inquiry_id = i.id) as first_sent,
             (select count(*) from public.quotes q where q.inquiry_id = i.id
                and coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled')
                and q.stale_at is null)::int as live_quotes
        from public.inquiries i
        join public.customers c on c.id = i.customer_id
       where i.status in ('sent', 'quoted')
    )
    select o.*, o.first_sent + make_interval(secs => (v_window * 3600)::double precision) as deadline
      from open_rfq o
     where o.first_sent is not null
       and o.live_quotes < c_target
       and now() >= o.first_sent + make_interval(secs => ((v_window - v_lead) * 3600)::double precision)
       and now() <  o.first_sent + interval '14 days'
       and (p_include_fixtures or not o.fixture)
     order by o.first_sent
  loop
    v_swept := v_swept + 1;

    -- (a) widen ONCE, from the same matcher, same-kind suppliers only.
    if not coalesce(r.routing ? 'short_sweep', false) then
      v_new := 0;
      v_codes := public.fn_taxonomy_trades_for(case when coalesce(cardinality(r.trades), 0) > 0 then r.trades
                                                    else array[coalesce(r.category, '')] end);
      if coalesce(cardinality(v_codes), 0) > 0 then
        -- KEYED, NOT READ: scope_type is customer_api's own set (single | multi | turnkey) and role_needed is
        -- one of fn_match_capability's needs when the request carried one.
        v_need := case when r.scope_type = 'turnkey' then 'whole_scope'
                       when r.role_needed in ('whole_scope', 'supplies', 'executes') then r.role_needed
                       else 'executes' end;
        v_value := coalesce(r.expected_value, nullif(regexp_replace(coalesce(r.budget, ''), '[^0-9.]', '', 'g'), '')::numeric);
        if v_value is not null and v_value <= 0 then v_value := null; end if;
        for s in select m.supplier_id, m.score, m.why
                   from public.fn_match_capability(v_codes, v_need, '{}'::text[], '{}'::text[], r.scope_type, v_value, r.emirate, 100000) m
                   join public.leads ld on ld.id = m.supplier_id
                  where not exists (select 1 from public.inquiry_matches x where x.inquiry_id = r.id and x.supplier_id = m.supplier_id)
                    and public.fn_seat_clock_lead_is_fixture(ld) = r.fixture
                  order by m.score desc loop
          insert into public.inquiry_matches (inquiry_id, supplier_id, similarity, match_reason)
          values (r.id, s.supplier_id, least(1, greatest(0, round(s.score / 100, 3))),
                  left('short-of-quotes sweep (fn_rfq_short_of_quotes_tick): ' || coalesce(s.why, ''), 400))
          on conflict (inquiry_id, supplier_id) do nothing;
          if found then
            v_new := v_new + 1;
            select * into l from public.leads where id = s.supplier_id;
            v := public.fn_seat_clock_deliver('sales_engineer', 'supplier_rfq_widened_invite', 'supplier',
                   lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))), r.fixture, 'en', 'rfq_invite',   -- suppliers are always written in English (founder, 28 Sep 2026)
                  
                   jsonb_build_object('name', l.company_name, 'category', r.category, 'emirate', r.emirate),
                   'rfq_invite:' || r.id || ':' || l.id, r.id, null, l.id);
          end if;
        end loop;
      end if;
      update public.inquiries
         set routing = coalesce(routing, '{}'::jsonb) || jsonb_build_object('short_sweep', jsonb_build_object(
               'at', now(), 'quotes_then', r.live_quotes, 'invited', v_new, 'trades', to_jsonb(v_codes),
               'by', 'sales_engineer (fn_rfq_short_of_quotes_tick)'))
       where id = r.id;
      v_invited := v_invited + v_new;
    end if;

    -- (b) remind each invited supplier who has not quoted, once. Not one invited in the last 2 hours.
    --     NO SUPPLIER IS NUDGED TWICE IN 24 HOURS (ruling 1209): a supplier invited to several short requests gets one
    --     reminder a day across all of them. The one deferred here is reminded on a later tick (its dedupe key is per
    --     request and supplier, so it still gets exactly one for this request) while the request is still short.
    for l in select ld.* from public.inquiry_matches m join public.leads ld on ld.id = m.supplier_id
              where m.inquiry_id = r.id and m.sent_at < now() - interval '2 hours'
                and not exists (select 1 from public.quotes q where q.inquiry_id = r.id and q.supplier_id = m.supplier_id)
                and public.fn_seat_clock_lead_is_fixture(ld) = r.fixture
                and not exists (select 1 from public.notifications n
                                 where n.lead_id = ld.id and n.type = 'rfq_quote_reminder'
                                   and n.created_at > now() - interval '24 hours' and coalesce(n.status, '') <> 'failed') loop
      v := public.fn_seat_clock_deliver('sales_engineer', 'rfq_quote_reminder', 'supplier',
             lower(btrim(coalesce(nullif(btrim(l.claimed_by), ''), l.email))), r.fixture, 'en', 'rfq_quote_reminder',   -- suppliers are always written in English (founder, 28 Sep 2026)
             
             jsonb_build_object('name', l.company_name, 'category', r.category, 'emirate', r.emirate, 'deadline', r.deadline),
             'rfq_quote_reminder:' || r.id || ':' || l.id, r.id, null, l.id);
      if coalesce((v->>'ok')::boolean, false) and not coalesce((v->>'already')::boolean, false) then v_reminded := v_reminded + 1; end if;
    end loop;

    -- (c) at the deadline, tell the customer once.
    if now() >= r.deadline then
      v := public.fn_seat_clock_deliver('sales_engineer', 'rfq_short_of_quotes', 'customer', r.cemail, r.fixture, r.clocale,
             'rfq_short_of_quotes',
             jsonb_build_object('name', r.cname, 'category', r.category, 'emirate', r.emirate, 'quotes', r.live_quotes),
             'rfq_short_of_quotes:' || r.id, r.id);
      if coalesce((v->>'ok')::boolean, false) and not coalesce((v->>'already')::boolean, false) then v_told := v_told + 1;
      elsif not coalesce((v->>'ok')::boolean, false) then
        v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('inquiry_id', r.id, 'reason', v->>'reason'));
      end if;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'swept', v_swept, 'invited', v_invited, 'reminded', v_reminded,
                            'customers_told', v_told, 'not_written', v_skipped,
                            'deadline_hours', v_window, 'sweep_from_hours_before', v_lead);
end
$function$
;

-- verdict (reads only: this file defines a routine, so it must not raise)
select case when position('interval ''24 hours'' and coalesce(n.status' in pg_get_functiondef('public.fn_rfq_short_of_quotes_tick(boolean)'::regprocedure)) > 0
            then 'PROBE OK: fn_rfq_short_of_quotes_tick reminds a supplier at most once in 24 hours'
            else 'PROBE FAILED: the 24-hour nudge guard is not in the live routine' end as verdict;
