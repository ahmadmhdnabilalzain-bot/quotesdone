# Synced from production — 27 July 2026

**Production was the source of truth for this sync, not this repo.** Local files were
overwritten from the live Supabase edge functions of project `htdblwldjkcgjvmqkbeh`.
Do not assume a file here is current just because its mtime looks recent — check the
deployed version before editing.

Source: live `get_edge_function` pull per slug. Every written file was verified
byte-identical (sha256) to the production pull after writing.

## Synced (local copy was BEHIND production — overwritten)

| slug | prod version | local before | after |
|---|---|---|---|
| os_api | v30 | 12,258 B | 18,164 B |
| inquiry_intake | v11 | 26,536 B | 28,575 B |
| quote_compare | v21 | 27,227 B | 28,657 B |
| agent_brain | v18 | 11,889 B | 17,742 B |
| meta_sync | v4 | 7,537 B | 8,103 B |
| knowledge_exam | v5 | 13,746 B | 14,228 B |
| drawing_redact | v7 | 6,636 B | 8,590 B |
| supplier_api | v27 | 41,975 B | 45,773 B |
| deploy_next_preview | v4 | 5,847 B | 6,749 B |
| retention_purge | v3 | 5,291 B | 5,759 B |

Recovered in this sync (would have been reverted if anyone had edited from the stale copy):

- **Fail-closed `__secret` auth guard** (`secretOk()`, "FAIL-CLOSED 27 Jul 2026") in
  `meta_sync`, `knowledge_exam`, `drawing_redact`, `retention_purge`. The stale local
  copies used a strict-equality check that could be satisfied by a missing/empty secret
  on functions that do not require a JWT.
- **Anonymity fixes 27 Jul 2026** in `supplier_api` (`scrubDeep()`, reveal-gating of
  `summary`/`spec`/`boq` before payment) and `drawing_redact` (opaque UUID storage
  prefix in place of a timestamp-based one).
- `deploy_next_preview` Vercel `target` fix; `quote_compare` v21 expert-reference
  feature; `os_api` v22→v30 action set; `agent_brain` pre-v14 → v17 employee runtime.

## Skipped — already identical to production (no write)

| slug | prod version | reason |
|---|---|---|
| customer_api | v36 | byte-identical to production |
| agent_act | v20 | byte-identical to production |
| cos_execute | v5 | byte-identical to production |
| dept_plan | v4 | byte-identical to production |
| canon_eval | v3 | byte-identical to production |

## Skipped — local work ahead of production

None. No local file contained work that production did not have, so nothing was
withheld and nothing unpushed was destroyed.

## Shared files

`agent_brain`, `agent_act`, `cos_execute`, `dept_plan`, `canon_eval` and
`knowledge_exam` are multi-file functions that also ship `_shared/llm.ts`
(reported by the pull as `functions/_shared/llm.ts`). The local
`supabase/functions/_shared/llm.ts` was already byte-identical to production
(sha256 `4c5fa242ad6986d43a09938cd5eaa262ba1469d01df036d7d454fbf48557ea74`,
8,229 B) — it already contained the 27 Jul 2026 AI cost-governor changes — so it
was verified and left untouched rather than rewritten.

## Scope

Only `index.ts` files under `supabase/functions/<slug>/` were written. Nothing was
deleted, nothing outside `supabase/functions/` was touched, and no git command was run —
these changes are unstaged working-tree edits for you to review and commit yourself.
