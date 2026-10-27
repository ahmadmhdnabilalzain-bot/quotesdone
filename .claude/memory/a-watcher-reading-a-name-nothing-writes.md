---
name: a-watcher-reading-a-name-nothing-writes
description: A monitor whose subject does not exist reports catastrophe forever, not "unknown"
metadata:
  type: reference
---

`fn_backup_watch` opened with `agent_runs where agent = 'backup'` — a name nothing has ever
written. It got NULL, read NULL as "no backup has ever succeeded", and paged the founder at
`critical` with "no successful backup for as long as there are records". It had done that on every
call it ever made. The real backup agent is `dropbox_backup`.

**Why:** an empty lookup is a fact about the QUERY, not about the subject. Monitors written this way
have a branch for "found nothing" that reads as disaster, so the false alarm is maximally loud and
maximally convincing.

**How to apply:** before a watcher may conclude anything, assert the name it looks for HAS matched
rows at some point. If it never has, return `ok:false, reason:'subject_not_found'` and alert nobody.
Also: test a cumulative failure counter by the TIME of the last failure, never `count > 0` — a
cumulative counter stays true forever after one bad hour. Same family as
[[zero-cannot-tell-a-dead-guard-from-an-idle-system]] and
[[instrument-measuring-wrong-subject-is-the-lens]]. Related: [[a-guard-that-fires-when-the-system-works]].
