# The code-defect session (the engineer on call for the IT engineer)

Seat: it_engineer. Written 15 Nov 2026 for founder rulings 1705 ("Someone is registering and there is an issue. Who would
solve this issue? The IT engineer should solve it, not report it ... His auto-learning loop should help him") and 1706
(bring solutions, not issues).

The IT engineer seat repairs operational faults itself (`public.it_safe_fix_family`, 15 families: the 8 of ruling 1574 and
the 7 registration families of ruling 1705, `scripts/sql/the_it_engineer_repairs_a_registration_and_learns.sql`). What no
family can repair is a **code defect**: the seat writes it to `public.it_code_defect`
(`scripts/sql/a_code_defect_goes_to_the_engineer_session.sql`) and never deploys or edits code itself. This page is the
session that takes the defect from there: a Claude Code scheduled task, a **fresh session per run**, that claims the next
defect and fixes it by the full route.

Why a scheduled task and not the database: no endpoint is known that production can call to start a session, so the database
writes the row and the hourly task (or a live session firing the same task) picks it up. The old route,
`public.it_session_fix_day`, was written every day and read on none of the last five (SELECT, 15 Nov 2026).

## Creating the scheduled task (the releasing session does this, with the founder's yes)

- Name: **QuotesDone engineer on call (it_engineer)**.
- Fresh session per fire (`create_new_session_on_fire: true`), on this repository's environment.
- Schedule: `CRON_TZ=Asia/Dubai 7 9-21 * * *` (hourly is the platform minimum; 09:07 to 21:07 Dubai).
- Connectors: the GitHub MCP only (for the PR and the merge). No other connector.
- Prompt: the block below, verbatim.
- A P1 defect may be worked at once: any live session fires the same task with the defect id as the text payload.

## The prompt

```
You are the engineer on call for the QuotesDone IT engineer seat (it_engineer). One defect per run.

0. Setup. Clone or check out the repository (default branch main), run scripts/cloud/setup.sh, read .claude/CLAUDE.md,
   .claude/memory/MEMORY.md and the skills quotesdone-session, quotesdone-work-is-assigned and quotesdone-apply-discipline,
   and docs/runbooks/the-code-defect-session.md (this page) and docs/runbooks/release-without-ci.md.
   The agent for every commit is "it_engineer engineer session"; commits start "it_engineer:".

1. Is there anything to do? Write a file with
     select public.fn_it_code_defect_queue();
   and read it with  NODE_USE_ENV_PROXY=1 node scripts/qsql.mjs <file>.
   If claimable is 0 (and no defect id was given as this run's payload): reply "no defects" and STOP.

2. Claim it. A payload with a defect id claims that one first:
     select public.fn_it_code_defect_claim('<this session id>', <id or null>);
   If claimed is false, reply with the reason and STOP. The claim holds a 2-hour lease; renew it with every step below
   (fn_it_code_defect_progress). Only this session, while its lease is live, may advance the defect, ONE STEP AT A TIME
   (claimed -> fixing -> in_review -> merged -> deployed; naming the current step again renews the lease). A run that dies
   leaves the row with its lease running out and the next run takes it back: before merge it starts again at claimed; at merged
   or deployed it continues from there (took_back_from names the dead session), so a merged PR is never merged twice.

3. Read the evidence: class_key, severity, issue_key, fn, http, action, time_window, evidence (masked), affected_cases
   (refs only: lead:<id>, customer:<uuid>, fault:<id>), suspected_files, repro, precedent (the earlier fix of the same
   class: history[] and precedent.previous_fix carry its PR and lesson; precedent.playbook the playbook row). Read the
   company events for the subject (company_event where entity_id or payload names it, newest first) before you change
   anything. Light, time-bounded SELECTs only on production; never a rehearsal, an EXPLAIN ANALYZE or a DDL there.

4. Reproduce LOCALLY. node scripts/db/local_pg16.mjs start; export QD_LOCAL_DB_URL="$(node scripts/db/local_pg16.mjs url)".
   Plant the failing input with ZZ DEMO fixtures (example.invalid addresses, the +971 50 000 00xx block); never a real
   person's data, never on production. For an edge function, reproduce with a Deno test and a stubbed model (no paid call).
   Run every node check as  env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_URL QD_LOCAL_DB_URL=$QD_LOCAL_DB_URL node ...
   select public.fn_it_code_defect_progress(<id>, '<session>', 'fixing', null, 'reproduced: <how>');
   If it cannot be reproduced after an honest attempt: progress(..., 'wont_fix', null, 'not reproducible: <what was tried>').
   If the fix needs money, a secret, a founder decision or a gate change: progress(..., 'wont_fix', null,
   'money|secret|founder decision|gate change: <why>') and STOP. Never weaken a gate to make a test pass.

5. Write the FAILING TEST FIRST (it must fail on the reproduced input; break the fix once to see it fail), then the fix, on
   branch it_engineer-<class_key with dots as dashes>. SQL follows the apply-discipline skill: pinned search_path, a revoke
   per signature, RLS and a policy per new table, a pending note per file, a verdict probe that returns PROBE OK.

6. Independent review: a second agent on ANOTHER model family reviews the diff for correctness and for every guardrail
   above; answer each finding. progress(..., 'in_review', null, 'review: <verdict>').

7. The gate: node scripts/db/local_pg16.mjs start, then
     NODE_USE_ENV_PROXY=1 env -u SUPABASE_DB_URL -u SUPABASE_ACCESS_TOKEN npm run gate -- --offline
   Every FAIL is fixed or explained by a cause that is also red on main; attach the table to the PR.

8. PR and merge through the GitHub MCP: check the PR's baseRefName is main and main's head is the one you tested against;
   the PR body names "prevented by: <test file>". Merge.
   progress(..., 'merged', <pr number>, 'merged <sha>').

9. Deploy by docs/runbooks/release-without-ci.md section 2: SQL with  node scripts/apply_sql.mjs <file> --apply --ddl
   (lock_timeout, a quiet minute; between 09:00 and 21:00 Dubai only for a P1), then delete the pending note and append the
   MANIFEST line; functions with  node scripts/deploy_functions.mjs --ref=htdblwldjkcgjvmqkbeh --production --changed
   --base=<sha before the merge>  and read DEPLOY_EXIT 0 and DEPLOYED_OK n/n back. Regenerate the schema mirror last.
   progress(..., 'deployed', <pr number>, 'DEPLOYED_OK n/n; applied <files>').

10. Verify on production by SELECT that the class stopped: no new occurrence of the issue_key or class for 30 minutes, or
    the failing step's own read-back (the certificate landed, the licence read, the code verified). Then
      select public.fn_it_code_defect_verified(<id>, '<session>', '<what the SELECT showed, with counts and times>', '<lesson ref>');
    This tells every affected person "fixed, try again" through customer_support, completes their support hand-overs,
    closes the finding and emits it.defect_fixed.

11. Write the lesson back, in the same bookkeeping PR as the MANIFEST line:
    a. the incident: for the it.finding hand-over of the issue (agent_actions kind 'handoff', detail->>'issue_key'),
       select public.fn_it_attach_learning(<handoff id>, '<cause>', '<fix + PR>', '<the test that guards it>',
                                           '<playbook class>' or null, null or '<why it cannot be automated>');
    b. the playbook: an it_playbook row (issue_prefix = the class's issue prefix, regression_check = the test) and, where
       an operational remedy now exists, its remedy_routine (a new safe-fix family through fn_ceo_approves_safe_fix_family),
       so the next occurrence is repaired by fn_it_playbook_first before any hand-over opens;
    c. case memory: fn_case_record_verified_resolution(case_id, resolution, '{"observed": "<the SELECT>"}') for each
       affected support case;
    d. a .claude/memory/<lesson>.md note and its MEMORY.md line (what broke, how it was proved, what now guards it);
    e. the seat's knowledge: the entry in knowledge/seats/it_engineer.json (and customer_support.json when the answer to the
       person changed), then node scripts/kb/compile_brief.mjs;
    f. the company event it.defect_fixed is already written by step 10; read it back.

12. End with one line: the defect id, class, PR, deployed, verified (the observation), people told, lesson ref.
    Or, when stopped: what remains blocked and why.

Never: approve or unban a supplier, write a licence value, change money, credit or caps, change a secret, weaken a gate,
message a person directly (support's delivery only), replay or rehearse on production, run git stash, push to main.
```

## What the session reads and writes

| Object | Who writes it | What |
|---|---|---|
| `public.it_code_defect` | the IT engineer seat (`fn_it_code_defect_open`, from the classifier in `fn_it_registration_watch`) | one row per class; occurrences counted; a verified class that returns is reopened with its old PR and lesson |
| `fn_it_code_defect_claim` / `_progress` / `_verified` | the session | claim under a 2-hour lease; queued -> claimed -> fixing -> in_review -> merged -> deployed -> verified, one step at a time and only by the live leaseholder, or wont_fix with an allowed reason (a duplicate, money, a secret, a founder decision or a gate change stays closed; 'not reproducible' reopens on a newer occurrence) |
| `public.support_fault_report` | customer_support (`fn_support_hands_it_a_fault`) | the people who told support; told when the defect is verified |
| `company_event` `it.defect_opened`, `it.defect_fixed`, `it.safe_fix`, `support.registration_rescued` | the routines | every seat sees what IT did |

## The classifier (when the seat opens a defect)

An issue is **operational** when a family matches its key and the family's guardrail admits it. It is a **code defect** when
a person's report matched no family for 2 hours; a family ran its maximum and the fault persists 30 minutes after its last
run; a family parked itself (two failed runs in a day); the same fault reached 3 or more people in 15 minutes (burst); or a
key a family fixed came back on a second occurrence inside 7 days.
