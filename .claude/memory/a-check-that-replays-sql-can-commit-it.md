---
name: a-check-that-replays-sql-can-commit-it
description: "30 Sep and 27 Oct: SQL meant only to be tried committed to production: once through a file's own BEGIN/COMMIT, once because the probe returned a verdict row instead of raising"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-10-27T21:35:00.000Z
---

On 30 Sep 2026, running `every_model_class_is_on_the_founders_matrix.test.mjs` locally applied PR #1152's migration to production before merge. The check replays pending model_policy files and then raises to roll back. The file contained its own `begin; … commit;`, so the COMMIT ran before the raise. Main drifted, and every open PR went red.

**Why:** a replay is only as safe as the most careless file it replays.

**How to apply:**
- SQL migration files and probes must never contain their own BEGIN or COMMIT.
- Any check that replays SQL must strip or refuse transaction control first (#1152 did this for the matrix test).
- If drift appears with no applied PR behind it, suspect a replaying check before blaming a person.

**27 Oct 2026, the same failure by a second route.** A reviewer tried PR #1684 by sending the routine file and its probe as one request (one implicit transaction). The probe ended by *returning* a `PROBE OK` row rather than raising, so nothing rolled back. `fn_support_reply_watch_tick` and its new helper went live before merge; the fingerprint moved from 8007ad0e to af022966. It was caught by diffing against live `pg_get_functiondef`. The PR was then merged with bookkeeping only (MANIFEST line added, pending note deleted) and no re-apply.

- A probe that is ever run together with the DDL it tests must end in `raise exception` on every path. It carries its verdict in the message, e.g. `raise exception 'CHK<<PROBE OK>>'`. Pass and fail both raise; the caller reads the text inside `CHK<<…>>`.
- When trying a PR's SQL against production, wrap the file and the probe in one explicit transaction that ends in that raise. The failure on 27 Oct was not autocommit: it was one request that ended without an error, so it committed.
- Afterwards, read the live definition (md5 of `pg_get_functiondef`) and confirm it is unchanged.
- #1686's probe follows this form; #1684's does not and was left as merged.

Related: [[apply-at-merge-never-before]], [[diff-sql-against-live-production-not-the-mirror]].
