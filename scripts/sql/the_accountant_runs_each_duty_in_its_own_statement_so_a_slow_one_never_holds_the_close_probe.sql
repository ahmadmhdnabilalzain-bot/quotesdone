-- PROBE for the_accountant_runs_each_duty_in_its_own_statement_so_a_slow_one_never_holds_the_close.sql (16 Nov 2026). Run
-- after the file in the same query: an aborted transaction, no DDL, ends in raise exception CHK<<...>>, so nothing commits
-- (no agent_runs row, no seat_duty clock moved, no finding). Proves:
--   1. the hourly call, with Stripe unread and no charge audit, returns ok and runs no other duty (no close, bank, books key);
--   2. all eleven accountant duties are hourly seat duties whose routine exists with every argument defaulted;
--   3. the close runs through fn_seat_duty_run, its own job's call, and its job sets its own statement_timeout;
--   4. a duty that raises is that duty's failure only: with the bank duty pointed at a routine that does not exist, the close,
--      run right after it, still succeeds and its row records ok;
--   5. every moved duty runs once through fn_seat_duty_run and records its own result row (ok or its own error).
do $probe$
declare v jsonb; v_fail text := ''; d text; v_n int := 0; v_ok int := 0; v_err text := '';
  v_all text[] := array['accountant.close_by_day_five', 'accountant.bank_reconcile', 'accountant.collections', 'accountant.subscriptions',
                        'accountant.books_chain', 'accountant.disputes', 'accountant.recovery', 'accountant.renewals',
                        'accountant.bank_balance', 'accountant.year_end_pack', 'accountant.ceo_reports'];
begin
  -- 1.
  v := public.fn_accountant_duties('{"stripe": {"live": {"basis": "not_configured", "reason": "probe"}, "test": {"basis": "not_configured", "reason": "probe"}}}'::jsonb);
  if not coalesce((v->>'ok')::boolean, false) then v_fail := v_fail || ' the hourly call is not ok: ' || left(v::text, 200) || ';'; end if;
  if v ?| array['close', 'bank', 'books', 'collections', 'recovery', 'year_end'] then v_fail := v_fail || ' the hourly call still ran another duty;'; end if;
  if not (v ? 'run_by_duty') then v_fail := v_fail || ' the hourly call does not say where the duties run;'; end if;
  -- 2.
  foreach d in array v_all loop
    if not exists (select 1 from public.seat_duty s where s.duty = d and s.enabled and s.every = interval '1 hour' and s.owner_seat = 'accountant'
                     and public.fn_seat_duty_routine_exists(s.routine)) then v_fail := v_fail || ' ' || d || ' is not an hourly duty with a routine;'; end if;
  end loop;
  -- 3.
  if not exists (select 1 from cron.job j where j.jobname = 'seat_duty:accountant.close_by_day_five' and j.active
                   and j.command like '%statement_timeout%' and j.command like '%fn_seat_duty_run(''accountant.close_by_day_five'')%')
    then v_fail := v_fail || ' the close has no job of its own with its own statement_timeout;'; end if;
  -- 4.
  update public.seat_duty set last_started_at = null where duty = any (v_all);
  update public.seat_duty set routine = 'fn_zz_probe_no_such_routine' where duty = 'accountant.bank_reconcile';
  v := public.fn_seat_duty_run('accountant.bank_reconcile');
  if coalesce((v->>'ok')::boolean, true) then v_fail := v_fail || ' the broken duty did not fail;'; end if;
  v := public.fn_seat_duty_run('accountant.close_by_day_five');
  if not coalesce((v->>'ok')::boolean, false) then v_fail := v_fail || ' the close failed after another duty failed: ' || coalesce(v->>'error', '?') || ';'; end if;
  if (select last_ok_at from public.seat_duty where duty = 'accountant.close_by_day_five') is distinct from now()
    then v_fail := v_fail || ' the close recorded no result of its own;'; end if;
  if (select last_error from public.seat_duty where duty = 'accountant.bank_reconcile') is null
    then v_fail := v_fail || ' the broken duty recorded no error of its own;'; end if;
  update public.seat_duty set routine = 'fn_accountant_bank_reconcile_hourly', last_started_at = null where duty = 'accountant.bank_reconcile';
  -- 5.
  foreach d in array v_all loop
    continue when d = 'accountant.close_by_day_five';
    v := public.fn_seat_duty_run(d);
    v_n := v_n + 1;
    if coalesce((v->>'ok')::boolean, false) then v_ok := v_ok + 1; else v_err := v_err || ' ' || d || ': ' || left(coalesce(v->>'error', v::text), 120) || ';'; end if;
    if (select last_started_at from public.seat_duty where duty = d) is distinct from now() then v_fail := v_fail || ' ' || d || ' did not run;'; end if;
  end loop;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK duties_ran=' || v_n || ' ok=' || v_ok || case when v_err <> '' then ' own_errors:' || v_err else '' end
                                   else 'PROBE FAILED:' || v_fail end;
end $probe$;
