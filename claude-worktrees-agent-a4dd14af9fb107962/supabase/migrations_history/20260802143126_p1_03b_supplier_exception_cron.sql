-- The sweep runs daily. Same shape as the other in-database jobs (run_doc_reminders,
-- fn_reconcile_doc_blocks) - a plain SQL call with no shared secret, because it never leaves the
-- database. 06:20 UTC is 10:20 in the UAE, so reminders and closure notices land in working hours.
select cron.unschedule('supplier_exception_sweep_daily')
where exists (select 1 from cron.job where jobname = 'supplier_exception_sweep_daily');

select cron.schedule('supplier_exception_sweep_daily', '20 6 * * *',
                     $$select public.fn_supplier_exception_sweep()$$);
