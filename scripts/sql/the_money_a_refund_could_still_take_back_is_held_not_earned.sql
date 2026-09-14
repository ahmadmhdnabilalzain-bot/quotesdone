-- THE MONEY A REFUND COULD STILL TAKE BACK IS HELD, NOT EARNED.
--
-- Assigned: accountant (duty 9, founder 14 Sep 2026: "yea add them").
--
-- WHAT WAS MEASURED (14 Sep 2026, production htdblwldjkcgjvmqkbeh):
--   * A reveal can be refunded in full while its supplier-response window is open
--     (transactions.refund_deadline, set by stripe_webhook from pricing_config.refund_window_working_days)
--     and while a refund case is open (public.refund_case, states requested .. provider_pending/failed).
--   * fn_gl_sync_business books reveal revenue to 4000 at the sale, and the weekly report prints revenue
--     the same way. Nothing said how much of it could still go back.
--
-- WHAT THIS BUILDS: fn_accountant_refund_reserve — every open refund case at its amount, plus every paid,
-- unrefunded reveal still inside its window at everything the customer paid (a refund returns all of it),
-- each transaction counted once. It is a REPORTED figure ("held for possible refunds") in the monthly
-- close and in the CEO's report of it, and v_accountant_refund_reserve lists the lines. It posts nothing:
-- a reserve journal would be a provision, and no rule on this estate books one.
--
--   node scripts/apply_sql.mjs scripts/sql/the_money_a_refund_could_still_take_back_is_held_not_earned.sql --apply --ddl

create or replace view public.v_accountant_refund_reserve with (security_invoker = true) as
  with open_case as (
    select c.transaction_id, max(c.amount_aed) amount_aed, string_agg('refund ' || coalesce(c.refund_id::text, '?') || ' ' || c.state, ', ') cases
      from public.refund_case c
     where c.state in ('requested', 'investigating', 'eligible', 'ceo_authorized', 'submitted', 'provider_pending', 'failed')
     group by c.transaction_id),
  in_window as (
    select t.id transaction_id, coalesce(t.total_charged, t.reveal_fee) amount_aed, t.refund_deadline
      from public.transactions t
     where t.fee_status = 'paid' and t.refund_deadline > now()
       and coalesce(t.refund_status, '') not in ('refunded', 'succeeded', 'rejected'))
  select coalesce(o.transaction_id, w.transaction_id) as transaction_id,
         greatest(coalesce(o.amount_aed, 0), coalesce(w.amount_aed, 0)) as held_aed,
         case when o.transaction_id is not null then 'open refund case ' || o.cases
              else 'inside the supplier-response window until ' || to_char(w.refund_deadline at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') end as reason,
         coalesce(c.is_demo, false) as demo
    from open_case o
    full join in_window w on w.transaction_id = o.transaction_id
    left join public.transactions t on t.id = coalesce(o.transaction_id, w.transaction_id)
    left join public.customers c on c.id = t.customer_id;
comment on view public.v_accountant_refund_reserve is
  'Every reveal whose money a refund could still take back: an open refund_case, or a paid reveal inside its supplier-response window. Reported as "held for possible refunds"; nothing is posted.';
revoke all on public.v_accountant_refund_reserve from anon, authenticated;

create or replace function public.fn_accountant_refund_reserve()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'held_for_possible_refunds_aed', coalesce(sum(held_aed) filter (where not demo), 0),
    'reveals', count(*) filter (where not demo),
    'demo_held_aed', coalesce(sum(held_aed) filter (where demo), 0),
    'lines', coalesce(jsonb_agg(jsonb_build_object('transaction_id', transaction_id, 'held_aed', held_aed, 'reason', reason, 'demo', demo)
                                order by transaction_id), '[]'::jsonb),
    'basis', 'Open refund cases at their amount, and paid unrefunded reveals inside transactions.refund_deadline at total_charged, each transaction once. Revenue booked to 4000 includes this money; it is not earned while it can still be refunded. ZZ DEMO customers are shown apart and not counted.')
  from public.v_accountant_refund_reserve;
$fn$;
revoke execute on function public.fn_accountant_refund_reserve() from public, anon, authenticated;
