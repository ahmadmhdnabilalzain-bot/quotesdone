-- AUDIT §6 part 2. Re-enable founding_rank_daily as the backstop to trg_assign_founding_rank.
-- It only fills NULL founding_rank values, so it can never renumber or double-award; its whole job
-- is to catch a verified supplier the trigger form somehow missed.
-- Note: a direct `UPDATE cron.job SET active` is permission-denied for the migration role.
-- cron.alter_job is the supported path and is idempotent.
select cron.alter_job(job_id := j.jobid, active := true)
from cron.job j where j.jobname = 'founding_rank_daily';;
