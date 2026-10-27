---
name: backslash-m-does-not-survive-the-transport
description: standard_conforming_strings is OFF on this transport, so a regex '\m' arrives as 'm' and matches nothing.
metadata:
  type: reference
---

Measured 24 Aug 2026 on the Supabase management `/database/query` endpoint: `'\m'` in a SQL string
literal arrives with the backslash eaten, so a word-boundary pattern silently becomes `m || name`
and matches nothing. A widened trigger scan reported the same four doors as the narrow one until the
boundary was rewritten as a character class:

```sql
q.prosrc ~ ('[^a-zA-Z0-9_]' || r.proname || '[[:space:]]*[(]')
```

Same family as [[bash-heredoc-and-redirect-traps]]: the transport, not the logic, is what changed
the meaning. Also relevant: node's `String.replace` expands `$'` in the REPLACEMENT to "everything
after the match", which corrupted a SQL file whose regex ended `[0-9]{3}$'`.
