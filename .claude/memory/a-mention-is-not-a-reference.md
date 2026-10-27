---
name: a-mention-is-not-a-reference
description: "How to decide a routine is dead — a reachability closure from real entry points, and the three traps that make a text scan lie"
metadata: 
  node_type: memory
  type: reference
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-08T01:20:38.535Z
---

To decide what can be deleted in this database, compute a **reachability closure**, never a mention
count. Roots are the only ways control enters from outside: a trigger function, a routine on an
ACTIVE cron job, a routine used in a view / default / check, a routine called by a surviving edge
function, a routine called by the Next.js app, and a routine named by `agent_tool.impl_target`.
Then everything those call, transitively.

Measured 8 Sep 2026: 372 roots close over 612 of 830 application routines. 218 were unreachable.

**Three traps, each of which produced a wrong answer before it produced a right one:**

1. **A mention is not a reference.** Counting any appearance of a name in any data column said 799
   of 830 were "reached". `phase_c_component` is a CATALOGUE listing 291 routine names,
   `agent_chats` are transcripts, `kernel_retired_path` records what is ALREADY retired,
   `agent_knowledge` is prose about the estate. A register that keeps its subject alive
   immortalises whatever it documents.
2. **pg_depend is the pre-check, not a text scan.** It found exactly one edge into 150 candidates:
   `fn_enforce_rls_on_new_tables` is an **EVENT trigger**, which is not in `pg_trigger` at all, so
   trigger roots can never see it. Dropping it would have silently stopped RLS applying to new
   tables. (The 3 Sep retirement header records the same lesson about a view.)
3. **scripts/ is not a root, but a CALL SITE in scripts/ is.** A routine a check ASSERTS ABOUT is
   not kept alive by that. A routine a script CALLS to do its job is. `fn_schema_export` regenerates
   the schema mirror; dropping it broke the estate's own tooling on the very next command. 14 had
   to be restored. Distinguish on `from public.X(`, `select X(`, `perform X(`, `.rpc('X'` — not on
   the name appearing.

Also: date a routine by its defining file's git **ADD** date, not last-touch — a sweep that rewrites
the MANIFEST stamps today on files written in August. And close the restore set under "calls"
before applying: a LANGUAGE sql body is validated at CREATE time, so callees must be created first.

See [[checks-retired-with-their-subject]], [[new-sql-file-needs-a-manifest-line]].
