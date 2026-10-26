---
name: a-check-that-replays-sql-can-commit-it
description: "30 Sep: a local check that replays pending SQL inside an 'aborted' transaction committed a migration to production because the file had its own BEGIN/COMMIT"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-09-30T01:27:19.261Z
---

On 30 Sep 2026, running `every_model_class_is_on_the_founders_matrix.test.mjs` locally applied PR #1152's migration to production before merge. The check replays pending model_policy files and then raises to roll back. The file contained its own `begin; … commit;`, so the COMMIT ran before the raise. Main drifted, and every open PR went red.

**Why:** a replay is only as safe as the most careless file it replays.

**How to apply:**
- SQL migration files and probes must never contain their own BEGIN or COMMIT.
- Any check that replays SQL must strip or refuse transaction control first (#1152 did this for the matrix test).
- If drift appears with no applied PR behind it, suspect a replaying check before blaming a person.

Related: [[apply-at-merge-never-before]].
