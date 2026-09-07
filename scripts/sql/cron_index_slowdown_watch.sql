-- The schedule that makes fn_index_slowdown_watch a mechanism rather than a routine nobody calls.
--
-- 04:15 UTC daily, deliberately between the 03:50 opportunity scan and the 04:30 founder brief: a
-- fall raised at 04:15 is on the record before the brief that morning is written, rather than a day
-- behind it. Daily because the check's own window is 7 days and the indices are measured daily —
-- a weekly watcher would let six of seven falls sit unexamined inside the window it is judged on.
--
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
    return;
  end if;
end $$;
