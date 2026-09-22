-- THE ACCOUNTANT RUNS ITS DUTIES EVERY HOUR, AND EACH ONE GOES ROUND THE LOOP.
--
-- Assigned: accountant. Founder, 14 Sep 2026: "yea add them all" (duties 1-8, duty 5 withdrawn: "just
-- ignore the corporate tax matter for companies") and "yea add them" (duties 9-11).
--
-- HOW IT RUNS. resilience_ping calls the accountant runtime (supabase/functions/accountant, action
-- 'duties') under the seat's own credential every tick. The runtime asks fn_accountant_duties_due, and
-- at most once in 55 minutes takes the readings only it can take — Stripe payouts, the balance
-- transactions behind them, Stripe's own fee and tax transactions, disputes, and the charge audit it
-- computes with _shared/reveal_fee.ts — then hands them here. Every duty is its own sub-transaction: one
-- that raises is REPORTED (fn_accountant_duty_stage makes it a finding) and does not stop the others.
--
--   1 bank          fn_accountant_payouts_record + fn_accountant_bank_reconcile     (bank file)
--   2 collections   fn_accountant_collections_tick                                   (collections file)
--   3 subscriptions fn_accountant_subscription_tick                                  (subscriptions file)
--   4 VAT           fn_accountant_vat_threshold_check — already called every tick by resilience_ping
--   6 expenses      fn_accountant_expense_duty                                       (expenses file)
--   7 disputes      fn_accountant_dispute_record + fn_accountant_disputes_tick       (disputes file)
--   8 close         fn_accountant_month_close_tick, the CEO's sweep and the completion (close file)
--   9 reserve       fn_accountant_refund_reserve — read by the close; nothing to run
--  10 charge audit  fn_accountant_charge_audit_record                                (charge audit file)
--  11 costs         fn_accountant_book_stripe_fees + fn_accountant_cost_booking_tick (costs file)
--
-- The five further duties (founder, 14 Sep 2026: "add all for accountant and IT"):
--  F1 cash          fn_accountant_bank_balance_tick; the close carries the cash and runway   (cash file)
--  F2 ad spend      fn_accountant_ad_spend_tick -- HELD since 22 Sep 2026, rule 641 (Meta invoice file)
--  F3 recovery      fn_accountant_recovery_tick                                  (recovery ledger file)
--  F4 year end      fn_accountant_year_end_tick; the runtime writes the pack      (year-end file)
--  F5 renewals      fn_accountant_renewals_tick; renewal.due from the it_engineer (renewals file)
--
--   node scripts/apply_sql.mjs scripts/sql/the_accountant_runs_its_duties_every_hour.sql --apply --ddl

create or replace function public.fn_accountant_duties_due()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select not exists (select 1 from public.agent_runs where agent = 'accountant' and counts->>'job' = 'duties'
                      and status = 'ok' and started_at > now() - interval '55 minutes')
$fn$;
revoke execute on function public.fn_accountant_duties_due() from public, anon, authenticated;

-- p_r: {stripe: {live|test: {basis, reason?, payouts[], fee_bts[], disputes[]}}, charge_audit: [..] | null}
create or replace function public.fn_accountant_duties(p_r jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare o jsonb := '{}'::jsonb; v_err jsonb := '[]'::jsonb; v_mode text; s jsonb; x jsonb; v_step text; v_rec jsonb;
begin
  if jsonb_typeof(p_r) is distinct from 'object' then
    raise exception 'fn_accountant_duties takes the readings object the accountant runtime assembles';
  end if;

  -- What only Stripe can say, recorded first so the duties below read it.
  begin
    for v_mode in select unnest(array['live', 'test']) loop
      s := p_r->'stripe'->v_mode;
      if coalesce(s->>'basis', '') <> 'measured' then
        o := o || jsonb_build_object('stripe_' || v_mode, jsonb_build_object('basis', coalesce(s->>'basis', 'not_read'), 'reason', s->>'reason'));
        continue;
      end if;
      v_rec := jsonb_build_object(
        'payouts', public.fn_accountant_payouts_record(v_mode = 'live', coalesce(s->'payouts', '[]'::jsonb)),
        'stripe_fees', public.fn_accountant_book_stripe_fees(v_mode = 'live', coalesce(s->'fee_bts', '[]'::jsonb)),
        'disputes', (select coalesce(jsonb_agg(public.fn_accountant_dispute_record(e, v_mode = 'live')), '[]'::jsonb)
                       from jsonb_array_elements(coalesce(s->'disputes', '[]'::jsonb)) e));
      o := o || jsonb_build_object('stripe_' || v_mode, v_rec);
    end loop;
  exception when others then v_err := v_err || jsonb_build_object('step', 'stripe', 'error', sqlerrm); end;

  begin o := o || jsonb_build_object('bank', public.fn_accountant_bank_reconcile());
  exception when others then v_err := v_err || jsonb_build_object('step', 'bank', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('collections', public.fn_accountant_collections_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'collections', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('subscriptions', public.fn_accountant_subscription_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'subscriptions', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('expenses', public.fn_accountant_expense_duty());
  exception when others then v_err := v_err || jsonb_build_object('step', 'expenses', 'error', sqlerrm); end;
  begin
    if jsonb_typeof(p_r->'charge_audit') = 'array' then
      o := o || jsonb_build_object('charge_audit', public.fn_accountant_charge_audit_record(p_r->'charge_audit'));
    else
      o := o || jsonb_build_object('charge_audit', jsonb_build_object('basis', 'not_read'));
    end if;
  exception when others then v_err := v_err || jsonb_build_object('step', 'charge_audit', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('disputes', public.fn_accountant_disputes_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'disputes', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('costs', public.fn_accountant_cost_booking_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'costs', 'error', sqlerrm); end;
  -- The five further duties (14 Sep 2026). Ad spend, recovery and renewals run BEFORE the close, which
  -- reads their figures; the bank balance and the year-end pack read the close, so they run after it.
  -- F2 AD SPEND IS HELD FOR THE MARKETING SEAT (founder rule 641, 22 Sep 2026: Meta and social are
  -- wired to no agent until that seat exists). The tick booked Meta spend from meta_insights (2 rows)
  -- into accountant_ad_spend_month (0 rows, measured 22 Sep 2026), so unwiring it changes no figure.
  -- fn_accountant_ad_spend_tick and _figures stay defined, and the close still reads the (empty)
  -- figures. The hold is recorded once, in public.company_policy_decision 'meta_and_social_held_for_marketing'.
  o := o || jsonb_build_object('ad_spend', jsonb_build_object('held', 'for the marketing seat (founder rule 641)'));
  begin o := o || jsonb_build_object('recovery', public.fn_accountant_recovery_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'recovery', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('renewals', public.fn_accountant_renewals_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'renewals', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('close', public.fn_accountant_month_close_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'close', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('bank_balance', public.fn_accountant_bank_balance_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'bank_balance', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('year_end', public.fn_accountant_year_end_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'year_end', 'error', sqlerrm); end;
  begin
    o := o || jsonb_build_object('ceo_acknowledged', public.fn_ceo_accountant_reports_sweep(),
                                 'completed', public.fn_accountant_reports_complete());
  exception when others then v_err := v_err || jsonb_build_object('step', 'ceo', 'error', sqlerrm); end;

  foreach v_step in array array['stripe', 'bank', 'collections', 'subscriptions', 'expenses', 'charge_audit', 'disputes', 'costs',
                                'recovery', 'renewals', 'close', 'bank_balance', 'year_end', 'ceo'] loop
    perform public.fn_accountant_duty_stage(v_step,
      (select string_agg(e->>'error', '; ') from jsonb_array_elements(v_err) e where e->>'step' = v_step));
  end loop;

  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('accountant', case when jsonb_array_length(v_err) = 0 then 'ok' else 'error' end, now(), now(),
          jsonb_build_object('job', 'duties', 'result', o, 'errors', v_err), null);
  return o || jsonb_build_object('ok', jsonb_array_length(v_err) = 0, 'errors', v_err);
end $fn$;
revoke execute on function public.fn_accountant_duties(jsonb) from public, anon, authenticated;
