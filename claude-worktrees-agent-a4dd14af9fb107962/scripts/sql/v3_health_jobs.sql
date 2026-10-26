-- The V3 runtime's own health jobs. Readiness derived once and never recomputed would be a
-- number that describes the day it was written; source freshness marked once would be the
-- same. Both are cheap and both belong on a schedule rather than in a session's memory.
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.



-- A retrieval row is only useful while an action might still cite it; the trace has already
-- captured what mattered.
