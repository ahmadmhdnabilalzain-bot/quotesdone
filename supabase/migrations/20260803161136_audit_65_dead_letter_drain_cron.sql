-- AUDIT 6.5(e): give the drain a schedule. Deliberately ONLY the dead-letter drain, not the
-- release: releasing held mail automatically would undo a deliberate pause on supplier outbound,
-- which is a decision an operator makes, not a cron. The drain is different — it moves mail that
-- has been paused for a month into a queue someone reads, and marks it 'dead' so send_outbox will
-- never quietly deliver a month-old sourcing request to a supplier who has forgotten the context.
select cron.schedule(
  'dead_letter_drain_held',
  '17 3 * * *',
  $$select public.fn_notifications_dead_letter_held(30);$$
)
where not exists (select 1 from cron.job where jobname = 'dead_letter_drain_held');

select jobid, jobname, schedule, active from cron.job where jobname = 'dead_letter_drain_held';;
