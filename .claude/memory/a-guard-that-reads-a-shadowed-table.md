---
name: a-guard-that-reads-a-shadowed-table
description: "A trigger function with a mutable search_path runs as the writer, so the writer can shadow the table it checks — pin search_path on every guard, SECURITY DEFINER or not."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: da613f58-5cf3-4795-ab24-f89cb598e1b2
  modified: 2026-08-15T08:24:42.932Z
---

15 Aug 2026. Phase B shipped three trigger functions that refuse a workflow step owned by a name
nobody models: `fn_phase_b_owner_guard`, `fn_phase_b_workflow_owner_guard`,
`fn_phase_b_handoff_guard`. The Supabase security advisor flagged all eight Phase B functions
`function_search_path_mutable`.

The reflex is to dismiss that on a non-`SECURITY DEFINER` function — no privilege escalation, so
who cares. Wrong for a **trigger**: it executes with the `search_path` of whoever is doing the
write, so a caller who sets `search_path` to a schema of their own can put a `org_role` there that
answers differently, and the guard passes while checking the wrong table.

**Why:** the risk is not what the function can DO, it is what it can be made to LOOK AT. That is
[[instrument-measuring-wrong-subject-is-the-lens]] pointed at a security guard: the check runs,
returns green, and reports on a subject the author never intended.

**How to apply:** `alter function … set search_path = public, pg_temp;` on every function that
enforces something, whether or not it is SECURITY DEFINER. `pg_temp` goes **last** so a temporary
table cannot shadow a real one. `ALTER FUNCTION … SET` changes no body, so it is a safe follow-up
on already-deployed code — verify with `select proconfig from pg_proc where proname = …` and
re-run the guard tests (77/77 and 18/18 were unchanged here).

And: read `get_advisors` after any DDL session. It found this; nothing in the repo's own checks
did.
