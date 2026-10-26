-- The schedule that makes fn_improvement_handover a MECHANISM rather than a one-off sweep.
--
-- Hourly, at :10, deliberately away from :40 (fn_task_approve) and :50 (cos_execute) so the three
-- hourly governance jobs do not contend. The questions are raised WEEKLY by fn_os_improve, so an
-- hour of latency is immaterial; what the hourly cadence buys is that a question raised at any time
-- is in its owner's queue within the hour, and that the sweep self-heals — switch it off and the
-- undelivered count climbs until comp-17 goes MISSING inside its 21-day window.
--
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
    return;
  end if;
end $$;
