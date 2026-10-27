---
name: a-score-that-fell-because-the-clock-moved
description: "A scorer line REGRESSED with nothing changed — a 14-day freshness window passed 36 minutes earlier — and the available fix would have demoted four AI employees for the founder's own stand-down."
metadata: 
  node_type: memory
  type: project
  originSessionId: e91f68dd-ccad-4fba-8fd1-3cb4e80753e3
  modified: 2026-08-26T14:25:40.618Z
---

26 Aug 2026, end-of-session sweep. `verify_os2_blueprint` reported 104/152 with one line changed:

```
REGRESSED  s32-reputation-drives-authority
```

Nothing in the session touched reputation. The check requires
`max(agent_reputation.computed_at) > now() - interval '14 days'`; the snapshot is from
**2026-08-12 13:45:16** and the cutoff crossed it at **14:21:56 that day — 36 minutes before the
run**. `cron.job` 161 `reputation_weekly` (`select public.fn_reputation_recompute()`) is INACTIVE
under the 16 August stand-down.

**The obvious fix was the wrong one.** Driven in an aborted transaction, the recompute moves five
tiers and every move is downward: `brief` senior_trusted→trusted, `marketing` trusted→standard,
`kb_engineer` unmeasured→probation, `knowledge_director` standard→probation, plus one new row. They
fall because the company was stood down and they did nothing, not because they did anything badly.
Running it buys a green line by narrowing four AI employees' autonomous authority for a fortnight of
enforced idleness — an instrument reporting on the wrong subject, applied to people.

**Two habits worth keeping.** When a scorer line moves and your session did not touch its subject,
compare the freshness cutoff to the data's timestamp before looking for a cause. And before running
a recompute to clear a red, drive it in an aborted transaction and read WHICH WAY it moves — a fix
that only ever demotes is telling you the input is missing, not that the subject got worse.

Related: [[instruments-report-on-the-wrong-subject]], [[deactivation-is-not-death]],
[[a-fix-that-makes-the-headline-fall]], [[a-keep-list-can-miss-a-category]].
