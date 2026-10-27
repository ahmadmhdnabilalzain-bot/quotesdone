---
name: the-read-back-covers-bodies-not-grants
description: "apply_sql --apply reads the routine definition back and matches it, but never reads the ACL, so re-applying an earlier MANIFEST file silently reverts a later file's REVOKE and still prints success."
metadata: 
  node_type: memory
  type: project
  originSessionId: a0718a3f-8c12-4c09-9a8e-d518ddb85dd8
  modified: 2026-08-18T06:36:49.895Z
---

`node scripts/apply_sql.mjs <file> --apply` prints **"read back and identical to the file"** after
comparing `pg_get_functiondef` against the committed bytes. That comparison covers the **body only**.
It never reads `proacl`.

18 Aug 2026: re-applied `scripts/sql/kernel_k13_retire_old_runtime.sql` to deploy a one-line fix to
`fn_kernel_retired_path_state`. That file also carries, by design,
`grant execute on ... to service_role` for four kernel primitives — because it DROPs and recreates
them, and a drop takes the ACL with it. A **later** file,
`scripts/sql/kernel_k35_retired_paths_lose_the_service_grant.sql`, exists specifically to remove
those grants. Re-applying k13 alone re-granted all four, and apply_sql reported success.

`fn_kernel_retired_grant_state` caught it — `retired_paths_executable_by_an_ordinary_role` went
0 of 14 → 4 of 14 — but only because that board had just been made readable by a test in the same
session. Repaired by re-applying k35.

**How to apply:** before re-applying any existing MANIFEST file, `grep -n "grant\|revoke"` it and
check whether a LATER file in `scripts/sql/MANIFEST.txt` changes the same grants. Applying files out
of manifest order is not safe just because the routine bodies are right. After any re-apply that
touched grants, read the grant boards — `fn_kernel_retired_grant_state`, and
`fn_kernel_write_guard_state`'s `ordinary_roles_holding_direct_dml_on_a_protected_table`.

Related: [[promote-carries-the-definition-not-the-grants]] is the same blind spot on the promote
path; [[two-files-one-routine-one-commit]] is the ordering hazard on bodies rather than grants.
