select jobname, schedule, active from cron.job where command ilike '%outbox%';
