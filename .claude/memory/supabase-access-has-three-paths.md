---
name: supabase-access-has-three-paths
description: "the ~/.supabase/access-token file can expire mid-session; never call that a wall — the Supabase MCP works independently, and I can refresh the file token myself via the browser."
metadata: 
  node_type: memory
  type: reference
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-01T19:08:31.570Z
---

Production access to the one Supabase project (htdblwldjkcgjvmqkbeh) has THREE independent paths — a
401 on one is never a wall:

1. **`~/.supabase/access-token`** (an `sbp_` legacy PAT, 44 chars) — read by every `.mjs` helper
   (`apply_sql.mjs`, the check scripts, `canonical_routine_manifest`, `export_from_either_source`).
   It EXPIRES (default new-token expiry is short; the one that died 1 Sep 2026 had ~30 days). When it
   401s, the helpers stop, but production is still reachable via:
2. **The Supabase MCP** — `mcp__94696680-91a7-4449-a548-ded2e7d4eae8__execute_sql` (raw SQL) and
   `apply_migration` (DDL). Independent auth, always works. Use it for any query/DDL when the file
   token is dead — e.g. the fn_agent_context_v3 ledger UPDATE on 1 Sep was applied this way.
3. **The browser** — his Chrome is logged into supabase.com. I can REFRESH the file token myself:
   claude-in-chrome → https://supabase.com/dashboard/account/tokens → Generate new token →
   "Create legacy token" → set a 90-day expiry (not the 7-day default) → click the copy button (do
   NOT screenshot/read the value) → PowerShell `((Get-Clipboard) -join '').Trim()` written straight
   to the file with `[System.IO.File]::WriteAllText`, printing only length/prefix/auth-status, never
   the token. Verified with an `/v1/projects` call returning 200. Refreshed 1 Sep 2026, valid ~90d.

Lesson (the founder made this point directly): I have permanent Supabase + browser + all-keys access.
Do NOT declare a credential wall on a single expired token — reach for the MCP immediately, and
refresh the file token via the browser when the helpers are needed. GitHub (`gh`) uses its own keyring
auth and is unaffected by the Supabase token.
