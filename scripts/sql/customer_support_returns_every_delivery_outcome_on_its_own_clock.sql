-- CUSTOMER SUPPORT RETURNS EVERY DELIVERY OUTCOME ON ITS OWN CLOCK (19 Oct 2026). Assigned: customer_support.
-- Founder ledger 1003 stage 2, contribution CS-C08: "Deliver every other seat's messages and return a verified delivery
-- outcome". (CS-C09's daily delivery-health duty is its own file.)
--
-- MEASURED 19 Oct 2026 (repo + production, read-only): the outcome loop exists. A seat asks through a delivery.request
-- handoff (fn_customer_support_takes_delivery); fn_customer_support_delivery_watch(p_request_id) reads the notification
-- (and Twilio's status), retries a failed send once, and returns a delivery.result handoff to the asking seat. But it
-- has no clock of its own: its only caller is fn_refund_ladder_sweep (the accountant's refund ladder), so the outcome
-- of every other seat's message waited on a refund sweep, and nothing measured a request left without its result.
--
-- WHAT THIS ADDS: customer_support.delivery_outcome_return, every 15 minutes, fn_customer_support_delivery_outcome_tick():
--   1. runs fn_customer_support_delivery_watch(null) (up to 50 terminal requests per run), unchanged;
--   2. counts the requests still owed an outcome: a delivery.request done or failed more than 2 hours ago, with no
--      delivery.result returned and no open watch window. Any such request is the finding
--      delivery_outcome_unreturned owned by customer_support (closed when none is left), with the oldest ids.
-- The refund sweep still calls the watch too; the watch is idempotent (result_handoff_id guards a second return).
--
-- Prevented by: scripts/checks/customer_support_senior_contributions_are_working_duties.test.mjs.
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/customer_support_returns_every_delivery_outcome_on_its_own_clock.sql --apply --ddl

create or replace function public.fn_customer_support_delivery_outcome_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_watch jsonb; v_n int; v_ids jsonb; v_oldest timestamptz;
begin
  v_watch := public.fn_customer_support_delivery_watch(null);

  select count(*), min(a.created_at), coalesce(jsonb_agg(a.id order by a.id) filter (where a.id is not null), '[]'::jsonb)
    into v_n, v_oldest, v_ids
    from public.agent_actions a
   where a.kind = 'handoff' and a.agent = 'customer_support' and a.status in ('done', 'failed')
     and a.detail->>'type' = 'delivery.request' and (a.detail->>'result_handoff_id') is null
     and coalesce(a.decided_at, a.created_at) < now() - interval '2 hours'
     and coalesce((a.detail->>'watch_until')::timestamptz, '-infinity'::timestamptz) < now();

  if v_n > 0 then
    perform public.fn_it_engineer_finding_upsert('delivery_outcome_unreturned',
      v_n || ' message request(s) from other seats have no delivery outcome returned after 2 hours (oldest '
        || to_char(v_oldest at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai)',
      'customer_support delivery outcome return (fn_customer_support_delivery_outcome_tick)', 'agent_facing', v_n,
      jsonb_build_object('ids', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select x from jsonb_array_elements(v_ids) x limit 20) z),
                         'owner_seat', 'customer_support', 'duty', 'delivery_outcome_return', 'watch', v_watch),
      '{}'::text[], array['why fn_customer_support_delivery_watch did not return these'], 'customer_support');
  elsif exists (select 1 from public.it_engineer_finding where issue_key = 'delivery_outcome_unreturned' and closed_at is null) then
    perform public.fn_it_engineer_finding_close('delivery_outcome_unreturned', 'every delivery request has its outcome returned to the asking seat');
  end if;
  return jsonb_build_object('ok', true, 'watch', v_watch, 'unreturned', v_n);
end $fn$;
revoke execute on function public.fn_customer_support_delivery_outcome_tick() from public, anon, authenticated;
grant execute on function public.fn_customer_support_delivery_outcome_tick() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('customer_support.delivery_outcome_return', 'customer_support', interval '15 minutes', 'fn_customer_support_delivery_outcome_tick',
   'CS-C08: every other seat''s message request gets its verified delivery outcome returned (fn_customer_support_delivery_watch on the seat clock); a request left without one past 2 hours is a finding',
   'scripts/sql/customer_support_returns_every_delivery_outcome_on_its_own_clock.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
