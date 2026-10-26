-- ABORT PATH: rehearse mode. The function does the full teardown, verifies, then raises,
-- so nothing is committed. The report travels in the exception message.
select public.fn_p2c1_rollback_stage_b6('rehearse', 'ops:p2c1-recovery-session');
