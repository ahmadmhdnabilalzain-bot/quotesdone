-- PROBE (pure, no DDL, aborted transaction) for the_supplier_onboarding_duty_passes_its_fixture_switch_to_the_invite_nudges.sql.
-- Run AFTER the definition, in the same transaction. It always ends in raise exception 'CHK<<json>>', so every row it writes rolls back.
-- The duty is run in FIXTURE mode (qd.duty_fixtures = 'on', "ONLY demo rows"). Before the fix it still queued invitation reminders to real
-- suppliers (measured 2 Nov 2026: 20 real notification rows, cap 20, 32 due); after it, fixture mode reaches fixture addresses only.
--   real_rows  = notifications this transaction wrote to an address that is not @example.invalid   (must be 0)
do $p$
declare v jsonb; n_real int; n_demo int;
begin
  perform set_config('qd.duty_fixtures', 'on', true);
  v := public.fn_sales_engineer_supplier_onboarding();
  select count(*) filter (where n.to_email like '%@example.invalid'), count(*) filter (where n.to_email not like '%@example.invalid')
    into n_demo, n_real from public.notifications n where age(n.xmin) = 0;
  raise exception 'CHK<<%>>', jsonb_build_object('demo_rows', n_demo, 'real_rows', n_real, 'pass', n_real = 0, 'result', v);
end $p$;
