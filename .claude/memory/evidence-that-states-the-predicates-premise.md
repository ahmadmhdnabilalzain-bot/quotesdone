---
name: evidence-that-states-the-predicates-premise
description: A board's evidence string written as a literal asserts the condition the predicate is testing, so a red sits beside a sentence saying everything is fine.
metadata:
  type: project
---

`fn_os_portals_gates()` reported "Monitoring and alerts configured." as **not_met**, beside:

> "23 active cron jobs; watch_failed_runs_hourly is scheduled and last succeeded inside 3 hours;
> 0 cron run(s) failed in the last 24 hours"

Every clause except the two counts was a literal. Measured: that job is INACTIVE, 488 prior runs,
last run 16 Aug 2026 06:15Z — switched off in the stand-down with 182 others (183 inactive, 23
active). The verdict was right and its own evidence contradicted it.

**Why:** an evidence string is read as the explanation of the verdict. If it is a sentence rather
than a measurement, it can only ever describe the passing case, and it hides the reason for a red.

**How to apply:** on any board, check that every clause of the evidence is COMPUTED. A verdict that
is `case when <predicate>` beside evidence that is `format('... <premise stated as fact> ...')` is
the defect, whichever way the verdict currently reads.

Reading it here surfaced the finding the sentence was hiding: **nothing among the 23 active cron
jobs watches for a failed cron run.**

Related: [[instruments-report-on-the-wrong-subject]], [[deactivation-is-not-death]].
