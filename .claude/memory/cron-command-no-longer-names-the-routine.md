---
name: cron-command-no-longer-names-the-routine
description: 22 of 23 active cron jobs run fn_kernel_cron_exec(jobid); the real command is in phase_c_system_execution_wrapper.original_command
metadata:
  type: project
---

Since Phase C, `cron.job.command` for 22 of the 23 ACTIVE jobs reads
`select public.fn_kernel_cron_exec(<jobid>)`. The command they actually execute lives in
`public.phase_c_system_execution_wrapper.original_command`.

Any check that matches a routine name against `cron.job.command` therefore matches NOTHING for
every live job. Found 27 Aug 2026: it made spec #3's s35, s37 and both s39 lines red while
evolution_scan_weekly, monthly_report, regulation_watch_weekly and fn_ai_spend_guard were all
running on schedule with a succeeded kernel trace. Same defect in spec #2's components_14_17.

**Why:** the wrapper was introduced to trace scheduled execution, and every liveness instrument in
the estate predates it.

**How to apply:** resolve the effective command as
`coalesce(w.original_command, j.command)` via a left join on the wrapper table. And note the
wrapper SWALLOWS failures — it records `result='failed'` on `phase_c_system_execution` and returns
normally, so `cron.job_run_details` reads 'succeeded' either way. Resolving the command alone makes
a liveness check WEAKER; pair it with a NOT EXISTS on a traced failure. Paused jobs still read
false, correctly. See [[a-mention-is-not-a-call]] and [[two-gates-one-vocabulary]].
