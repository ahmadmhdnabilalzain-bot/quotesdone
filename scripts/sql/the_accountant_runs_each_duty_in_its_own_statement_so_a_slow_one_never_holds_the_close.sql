-- THE ACCOUNTANT RUNS EACH DUTY IN ITS OWN STATEMENT, SO A SLOW ONE NEVER HOLDS THE CLOSE.
--
-- Seat: accountant (built by it_engineer, wave 3 OPS builder, 16 Nov 2026; hole H12 of the operations hunt, founder ledgers
-- 1711-1713: the company finds its own holes and builds them).
--
-- WHAT WAS WRONG. fn_accountant_duties(p_r) ran sixteen duties (Stripe, bank, collections, subscriptions, expenses, the charge
-- audit, disputes, costs, owner card, books, recovery, renewals, THE MONTH CLOSE, bank balance, year end, the CEO's reports)
-- as ONE PostgREST call, i.e. one statement under the authenticator's 8 s statement_timeout. Each duty sat in its own
-- exception block, but a statement timeout is query_canceled, which `when others` does not catch: one slow duty cancelled the
-- whole statement and rolled back every duty of that hour, the close included.
--
-- MEASURED on production 16 Nov 2026 ~09:30 UTC (SELECT only):
--   * agent_runs: 2 cancellations of the hourly call in 20 days ("fn_accountant_duties raised: canceling statement due to
--     statement timeout", 10 Nov 09:00 and 13 Nov 08:00 UTC); the hour's next tick succeeded both times. The "62 timeouts of
--     13-15 Nov" in the hunt were every accountant error row of those days: 59 are "invoice refused: No paid reveal found for
--     this quote", 2 are these, 1 is fn_accountant_reveal_reconcile_record.
--   * the October close: closed 10 Nov 10:15 UTC, due by 5 Nov. The hourly result read close status 'waiting_for_statement'
--     on every run from 3 to 9 Nov: the bank-statement gate that founder ruling 1559 removed on 10 Nov, not a timeout.
--   * pg_stat_statements (track = top): the hourly call, mean 290 ms, max 5,208 ms over 314 calls. A cancelled statement is
--     not recorded and nested routines are not tracked, so WHICH duty is slow cannot be read on production today. After this
--     file each duty is its own public.seat_duty row, whose avg_ms, last_error and failures say exactly that.
--
-- WHAT THIS FILE DOES (the seat_duty machinery already does this for the other 27 accountant duties):
--   1. the close: accountant.close_by_day_five (fn_accountant_close_by_day_5 runs fn_accountant_month_close_tick, then reports
--      a late close to the CEO once per month) runs every hour instead of once a day, on its own pg_cron job: its own
--      statement, `set statement_timeout = '60s'`, its own result row. It is isolated FIRST, so nothing runs ahead of it in
--      its statement. Ordering note: the close used to run after recovery and renewals in the same call. Those run hourly
--      all month, so a month's figures are booked long before the close falls due (day 3, gl_settings.month_close_day).
--   2. every other parameterless duty is a seat_duty row of its own, every hour. A new duty has no measured time, so the next
--      fn_seat_duties_tick gives it its own job (fn_seat_duty_isolate): its own statement and 60 s timeout. One that fails
--      or times out is a seat_duty:<duty> finding for the it_engineer (fn_seat_duty_health) and stops nothing else.
--   3. the four duties that are a real chain stay a chain, in one routine: expenses, then costs (posts the month's
--      expenses), then the owner card (restates the ruled subscriptions after costs), then the books (raises staleness after
--      posting). Each keeps its own stage finding (fn_accountant_duty_stage), as before.
--   4. fn_accountant_duties keeps what only the runtime can hand it: the Stripe readings and the charge audit. It still writes
--      the agent_runs 'duties' row fn_accountant_duties_due reads, so the Stripe readings stay hourly.
--   5. any open acct:stage:<step> finding of a moved step closes with the reason (none open at 16 Nov 09:30 UTC).
-- Prevented by: scripts/checks/the_accountant_close_never_waits_behind_another_duty.test.mjs
-- Probe: the_accountant_runs_each_duty_in_its_own_statement_so_a_slow_one_never_holds_the_close_probe.sql
-- Base: fn_accountant_duties is production's body (md5 c47dfc4919a05791719dc6f0b7304793, read 16 Nov 2026), edited.
-- Rollback: re-apply the_accountant_runs_its_duties_every_hour.sql's fn_accountant_duties (production text above), and
--   delete from public.seat_duty where duty in (the ten new rows); update accountant.close_by_day_five set every = '1 day'.
set local lock_timeout = '3s';

-- ── 3. the chain that must keep its order ─────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_books_chain_duty()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare o jsonb := '{}'::jsonb; v_err jsonb := '[]'::jsonb; v_step text;
begin
  -- expenses -> costs -> owner_card -> books: costs posts the month's expenses (fn_gl_sync_business), the owner card restates
  -- the ruled subscriptions after costs, and the books duty reads what posting left. Each raise is its own stage finding.
  begin o := o || jsonb_build_object('expenses', public.fn_accountant_expense_duty());
  exception when others then v_err := v_err || jsonb_build_object('step', 'expenses', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('costs', public.fn_accountant_cost_booking_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'costs', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('owner_card', public.fn_accountant_owner_card_tick());
  exception when others then v_err := v_err || jsonb_build_object('step', 'owner_card', 'error', sqlerrm); end;
  begin o := o || jsonb_build_object('books', public.fn_accountant_books_duty());
  exception when others then v_err := v_err || jsonb_build_object('step', 'books', 'error', sqlerrm); end;
  foreach v_step in array array['expenses', 'costs', 'owner_card', 'books'] loop
    perform public.fn_accountant_duty_stage(v_step,
      (select string_agg(e->>'error', '; ') from jsonb_array_elements(v_err) e where e->>'step' = v_step));
  end loop;
  return o || jsonb_build_object('ok', jsonb_array_length(v_err) = 0, 'errors', v_err);
end $fn$;
revoke execute on function public.fn_accountant_books_chain_duty() from public, anon, authenticated;

-- the CEO's acknowledgement sweep and the reports' completion were one stage ('ceo'); one duty, two calls, as before
create or replace function public.fn_accountant_ceo_reports_duty()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  return jsonb_build_object('ceo_acknowledged', public.fn_ceo_accountant_reports_sweep(),
                            'completed', public.fn_accountant_reports_complete());
end $fn$;
revoke execute on function public.fn_accountant_ceo_reports_duty() from public, anon, authenticated;

-- ── 4. the hourly call keeps only what the runtime reads from Stripe ───────────────────────────────────────────────────
create or replace function public.fn_accountant_duties(p_r jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare o jsonb := '{}'::jsonb; v_err jsonb := '[]'::jsonb; v_mode text; s jsonb; v_step text; v_rec jsonb;
begin
  if jsonb_typeof(p_r) is distinct from 'object' then
    raise exception 'fn_accountant_duties takes the readings object the accountant runtime assembles';
  end if;

  -- What only Stripe can say, recorded first so the duties read it.
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

  begin
    if jsonb_typeof(p_r->'charge_audit') = 'array' then
      o := o || jsonb_build_object('charge_audit', public.fn_accountant_charge_audit_record(p_r->'charge_audit'));
    else
      o := o || jsonb_build_object('charge_audit', jsonb_build_object('basis', 'not_read'));
    end if;
  exception when others then v_err := v_err || jsonb_build_object('step', 'charge_audit', 'error', sqlerrm); end;

  -- EVERY OTHER DUTY IS A SEAT DUTY OF ITS OWN (16 Nov 2026, the_accountant_runs_each_duty_in_its_own_statement_so_a_slow_
  -- one_never_holds_the_close.sql): its own statement and statement_timeout, its own result row in public.seat_duty. Named
  -- here so a reader of this result knows where each one now runs and when it last succeeded.
  o := o || jsonb_build_object('run_by_duty', (select coalesce(jsonb_object_agg(sd.duty, sd.last_ok_at), '{}'::jsonb)
                                                 from public.seat_duty sd
                                                where sd.duty in ('accountant.close_by_day_five', 'accountant.bank_reconcile',
                                                  'accountant.collections', 'accountant.subscriptions', 'accountant.books_chain',
                                                  'accountant.disputes', 'accountant.recovery', 'accountant.renewals',
                                                  'accountant.bank_balance', 'accountant.year_end_pack', 'accountant.ceo_reports',
                                                  'accountant.ad_spend_reconcile')));

  foreach v_step in array array['stripe', 'charge_audit'] loop
    perform public.fn_accountant_duty_stage(v_step,
      (select string_agg(e->>'error', '; ') from jsonb_array_elements(v_err) e where e->>'step' = v_step));
  end loop;

  insert into public.agent_runs (agent, status, started_at, finished_at, counts, note)
  values ('accountant', case when jsonb_array_length(v_err) = 0 then 'ok' else 'error' end, now(), now(),
          jsonb_build_object('job', 'duties', 'result', o, 'errors', v_err), null);
  return o || jsonb_build_object('ok', jsonb_array_length(v_err) = 0, 'errors', v_err);
end $function$;
revoke execute on function public.fn_accountant_duties(jsonb) from public, anon, authenticated;

-- ── 2a. one routine per duty: a seat duty names a routine defined in the file that registers it ─────────────────────────
-- Each is the duty routine itself, called as the hourly call called it (its date argument at its default). A raise is the
-- duty's own failure (seat_duty.last_error, a seat_duty:<duty> finding); a timeout cancels this duty's statement only.
create or replace function public.fn_accountant_bank_reconcile_hourly()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_accountant_bank_reconcile() $fn$;
revoke execute on function public.fn_accountant_bank_reconcile_hourly() from public, anon, authenticated;
create or replace function public.fn_accountant_collections_hourly()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_accountant_collections_tick() $fn$;
revoke execute on function public.fn_accountant_collections_hourly() from public, anon, authenticated;
create or replace function public.fn_accountant_subscriptions_hourly()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_accountant_subscription_tick() $fn$;
revoke execute on function public.fn_accountant_subscriptions_hourly() from public, anon, authenticated;
create or replace function public.fn_accountant_disputes_hourly()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_accountant_disputes_tick() $fn$;
revoke execute on function public.fn_accountant_disputes_hourly() from public, anon, authenticated;
create or replace function public.fn_accountant_recovery_hourly()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_accountant_recovery_tick() $fn$;
revoke execute on function public.fn_accountant_recovery_hourly() from public, anon, authenticated;
create or replace function public.fn_accountant_renewals_hourly()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_accountant_renewals_tick() $fn$;
revoke execute on function public.fn_accountant_renewals_hourly() from public, anon, authenticated;
create or replace function public.fn_accountant_bank_balance_hourly()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_accountant_bank_balance_tick() $fn$;
revoke execute on function public.fn_accountant_bank_balance_hourly() from public, anon, authenticated;
create or replace function public.fn_accountant_year_end_pack_hourly()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_accountant_year_end_tick() $fn$;
revoke execute on function public.fn_accountant_year_end_pack_hourly() from public, anon, authenticated;

-- ── 2. one seat duty per duty, every hour ──────────────────────────────────────────────────────────────────────────────
insert into public.seat_duty (duty, what, every, enabled, routine, owner_file, owner_seat) values
 ('accountant.bank_reconcile', 'the bank statement lines are matched to the books every hour', '1 hour', true, 'fn_accountant_bank_reconcile_hourly',
  'scripts/sql/the_accountant_runs_each_duty_in_its_own_statement_so_a_slow_one_never_holds_the_close.sql', 'accountant'),
 ('accountant.collections', 'what suppliers owe is chased on its clock every hour', '1 hour', true, 'fn_accountant_collections_hourly',
  'scripts/sql/the_accountant_runs_each_duty_in_its_own_statement_so_a_slow_one_never_holds_the_close.sql', 'accountant'),
 ('accountant.subscriptions', 'supplier subscriptions are billed and dunned every hour', '1 hour', true, 'fn_accountant_subscriptions_hourly',
  'scripts/sql/the_accountant_runs_each_duty_in_its_own_statement_so_a_slow_one_never_holds_the_close.sql', 'accountant'),
 ('accountant.books_chain', 'expenses, then costs posted, then the owner card restated, then the books checked for staleness, in that order, every hour', '1 hour', true, 'fn_accountant_books_chain_duty',
  'scripts/sql/the_accountant_runs_each_duty_in_its_own_statement_so_a_slow_one_never_holds_the_close.sql', 'accountant'),
 ('accountant.disputes', 'every open card dispute is tracked to its Stripe deadline every hour', '1 hour', true, 'fn_accountant_disputes_hourly',
  'scripts/sql/the_accountant_runs_each_duty_in_its_own_statement_so_a_slow_one_never_holds_the_close.sql', 'accountant'),
 ('accountant.recovery', 'every supplier charge claim moves on the UAE clock every hour', '1 hour', true, 'fn_accountant_recovery_hourly',
  'scripts/sql/the_accountant_runs_each_duty_in_its_own_statement_so_a_slow_one_never_holds_the_close.sql', 'accountant'),
 ('accountant.renewals', 'every renewal the it_engineer sees coming is budgeted every hour', '1 hour', true, 'fn_accountant_renewals_hourly',
  'scripts/sql/the_accountant_runs_each_duty_in_its_own_statement_so_a_slow_one_never_holds_the_close.sql', 'accountant'),
 ('accountant.bank_balance', 'what is in the bank and how long it lasts, read after the close, every hour', '1 hour', true, 'fn_accountant_bank_balance_hourly',
  'scripts/sql/the_accountant_runs_each_duty_in_its_own_statement_so_a_slow_one_never_holds_the_close.sql', 'accountant'),
 ('accountant.year_end_pack', 'the year-end pack is built when it falls due, checked every hour', '1 hour', true, 'fn_accountant_year_end_pack_hourly',
  'scripts/sql/the_accountant_runs_each_duty_in_its_own_statement_so_a_slow_one_never_holds_the_close.sql', 'accountant'),
 ('accountant.ceo_reports', 'the CEO''s acknowledgements of the accountant''s reports are swept and finished reports completed, every hour', '1 hour', true, 'fn_accountant_ceo_reports_duty',
  'scripts/sql/the_accountant_runs_each_duty_in_its_own_statement_so_a_slow_one_never_holds_the_close.sql', 'accountant')
on conflict (duty) do nothing;

-- ── 1. the close runs every hour, on its own job, first ────────────────────────────────────────────────────────────────
update public.seat_duty
   set every = '1 hour',
       what = 'the previous month closed and locked by day 5: the close runs here every hour, in its own statement, and a miss goes to the CEO'
 where duty = 'accountant.close_by_day_five';
select public.fn_seat_duty_isolate('accountant.close_by_day_five');

-- ── 5. a stage that moved to a seat duty can no longer close its own acct:stage finding ────────────────────────────────
select public.fn_it_engineer_finding_close('acct:stage:' || s,
         'the accountant''s ' || s || ' duty runs as its own seat duty since 16 Nov 2026; a failure there is a seat_duty: finding')
  from unnest(array['bank', 'collections', 'subscriptions', 'disputes', 'recovery', 'renewals', 'close', 'bank_balance', 'year_end', 'ceo']) s
 where exists (select 1 from public.it_engineer_finding f where f.issue_key = 'acct:stage:' || s and f.closed_at is null);

select case
  when exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'fn_accountant_duties'
                  and p.prosrc ~ 'fn_accountant_(month_close_tick|bank_reconcile|collections_tick|recovery_tick|books_duty)\(')
    then 'PROBE FAILED: fn_accountant_duties still runs a duty that has its own seat duty'
  when (select count(*) from public.seat_duty where owner_seat = 'accountant' and every = '1 hour' and enabled
          and duty in ('accountant.close_by_day_five', 'accountant.bank_reconcile', 'accountant.collections', 'accountant.subscriptions',
                       'accountant.books_chain', 'accountant.disputes', 'accountant.recovery', 'accountant.renewals',
                       'accountant.bank_balance', 'accountant.year_end_pack', 'accountant.ceo_reports')) <> 11
    then 'PROBE FAILED: not every accountant duty is an hourly seat duty'
  when not exists (select 1 from public.seat_duty where duty = 'accountant.close_by_day_five' and own_job)
    then 'PROBE FAILED: the close is not on its own job'
  else 'PROBE OK: each accountant duty runs in its own statement; the close is hourly on its own job' end as verdict;
