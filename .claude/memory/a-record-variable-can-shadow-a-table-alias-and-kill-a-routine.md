---
name: a-record-variable-can-shadow-a-table-alias-and-kill-a-routine
description: "A PL/pgSQL record variable named d made a later query's alias d ambiguous, so the whole routine aborted and nine scheduled IT duties died silently for three days"
metadata:
  type: reference
---

15-18 Sep 2026. `fn_it_duties_scheduled` declares `d public.doc_backups` for the restore drill. A section added later aliased `public.doc_backups AS d` inside an anti-join. Postgres refuses to plan that (42702, "column reference d.bucket is ambiguous"), and the error aborts the WHOLE routine, not just that section.

**What it cost:** every scheduled IT duty after the failing line stopped running from 15 Sep 19:02Z until 18 Sep — workflow_heartbeat, restore, backup_gap, sender (SPF/DKIM/DMARC, blocklists, bounce rates, WhatsApp quality), spend, otp, access, db_health, rotation. Ten real db_health findings had been invisible the whole time. The routine also never reached `fn_it_duty_ran`, so backup_gap stayed permanently "due" and the failure repeated 215 times.

**The lens:** a one-line syntax-level collision inside a long routine takes out every duty downstream of it, and the only symptom is one heartbeat finding that reads like a small thing. When one step of a multi-duty routine reports a planner error, assume everything after it stopped too, and list what was not being checked.

**How to apply:**
- Never alias a table with a single letter that a DECLARE block already uses; qualify or rename.
- In a routine that performs many independent duties, a failure in one must not abort the rest — each duty belongs in its own exception block.
- After fixing a long-dead check, read what it raises the first time it works again; a burst of "new" findings is a backlog, not a regression.

Related: [[a-guard-that-fires-when-the-system-works]], [[zero-cannot-tell-a-dead-guard-from-an-idle-system]], [[lessons-postgres-kernel-and-deploy]].
