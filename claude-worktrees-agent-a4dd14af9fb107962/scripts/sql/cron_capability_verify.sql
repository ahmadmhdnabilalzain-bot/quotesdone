-- The schedule that makes fn_capability_verify a mechanism rather than a one-off.
--
-- 02:15 UTC daily, away from the 03:30 money suite, the 03:37 QA suite, the 03:50 DR drill, the
-- 04:30 founder brief and the 00:35 KPI snapshot. Daily rather than weekly because the verdict it
-- writes carries a THIRTY-day staleness window: a weekly job that misses four Mondays would let a
-- capability go quietly unverified, and the whole point of the table is that nothing goes quietly.
--
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
    return;
  end if;
end $$;
