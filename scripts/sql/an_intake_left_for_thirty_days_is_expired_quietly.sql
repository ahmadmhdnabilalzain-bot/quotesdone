-- Seat: sales_engineer. Assigned: sales_engineer (customer-journey follow-up, 10 Nov 2026; founder ruling 1608).
--
-- MEASURED on production (SELECT only, 10 Nov 2026 20:30 UTC): public.inquiry_intake holds 3 rows in 'needs_info' (last
-- touched 14 Sep to 12 Oct 2026) and 1 in 'ready' (21 Sep), all real customers' request conversations abandoned before a
-- request was posted. Nothing ever ends an intake: only create_inquiry moves one ('ready' -> 'consumed'). A 'ready' one
-- also keeps inquiry_intake_one_open_repeat (one open repeat per customer and original) taken for good.
--
-- WHAT THIS CHANGES: an intake in 'needs_info' or 'ready' untouched (updated_at) for decision_policy.intake_abandoned_days
-- (30) is marked 'expired', by the seat duty sales_engineer.abandoned_intakes, once a day. NO message is sent: none exists
-- for an abandoned intake (measured: no routine in the schema mirror messages a customer about an inquiry_intake row
-- except fn_sales_engineer_spec_handoff_waits, which answers an open spec question and is not an expiry notice), and a
-- conversation the customer walked away from is not a reason to e-mail them. updated_at is left as it was, so the row still
-- says when the customer last spoke. Nothing is deleted. A customer who comes back to it carries on: inquiry_intake reads a
-- draft by its id whatever its status and writes the new status on the next turn; create_inquiry asks for the details again.
-- NOT CHANGED: 'held' intakes (waiting on a hold that has its own clock), 'consumed' and 'rejected' ones.
-- prevented by: scripts/checks/an_intake_left_for_thirty_days_is_expired_quietly.test.mjs and this file's _probe.sql.
-- Pending until the release applies it: scripts/sql/pending/an_intake_left_for_thirty_days_is_expired_quietly.txt

insert into public.decision_policy (key, value, description) values
  ('intake_abandoned_days', '30'::jsonb, 'fn_sales_engineer_expires_abandoned_intakes: days without a turn (inquiry_intake.updated_at) after which a needs_info or ready intake is marked expired, with no message. Sales engineer, 10 Nov 2026.')
on conflict (key) do nothing;

create or replace function public.fn_sales_engineer_expires_abandoned_intakes(p_at timestamptz default now())
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';
  v_days int := public.fn_seat_clock_policy('intake_abandoned_days', 30)::int;
  v_ids uuid[];
begin
  with x as (
    update public.inquiry_intake t set status = 'expired'
      from (select it.id from public.inquiry_intake it
              left join public.customers c on c.id = it.customer_id
             where it.status in ('needs_info', 'ready')
               and coalesce(it.updated_at, it.created_at) <= p_at - make_interval(days => v_days)
               -- a fixture is expired only by a probe that asked for fixtures, a real intake only by the real duty
               and (coalesce(c.is_demo, false) or public.fn_is_demo_email(coalesce(c.email, it.email))) = v_fx
             order by coalesce(it.updated_at, it.created_at) limit 500 for update of it skip locked) d
     where t.id = d.id
    returning t.id)
  select array_agg(id) into v_ids from x;
  return jsonb_build_object('expired', coalesce(cardinality(v_ids), 0), 'days', v_days, 'fixtures', v_fx, 'ids', to_jsonb(coalesce(v_ids, '{}'::uuid[])));
end $fn$;
revoke execute on function public.fn_sales_engineer_expires_abandoned_intakes(timestamptz) from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.abandoned_intakes', 'sales_engineer', interval '1 day', 'fn_sales_engineer_expires_abandoned_intakes',
   'A request conversation (inquiry_intake) left in needs_info or ready for 30 days is marked expired, with no message.',
   'scripts/sql/an_intake_left_for_thirty_days_is_expired_quietly.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

select case
  when not exists (select 1 from public.seat_duty where duty = 'sales_engineer.abandoned_intakes') then 'PROBE FAILED: the duty is not registered'
  when has_function_privilege('anon', 'public.fn_sales_engineer_expires_abandoned_intakes(timestamptz)', 'execute') then 'PROBE FAILED: anon can run it'
  else 'PROBE OK' end as verdict;
