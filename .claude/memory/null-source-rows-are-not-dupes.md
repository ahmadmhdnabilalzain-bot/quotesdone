---
name: null-source-rows-are-not-dupes
description: "the kb_chunks \"1,485 md5 dupes\" was 1,317 NULL-source_id rows a NULL-concat hash miscounts, not duplicates"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 56ec6d94-4a33-47cf-b0a7-2607922d67ad
  modified: 2026-08-28T20:38:25.063Z
---

The global corpus-dupe probe `count(*) - count(distinct md5(source_id||coalesce(title,'')||content))`
over `public.kb_chunks` reported **1,485 "dupes"**, but only **168** were real (one source,
`fm-arxiv-smart-maintenance-historic-buildings`, 336→168). The other **1,317 are rows with
`source_id IS NULL`** — the pre-existing ~97k corpus. In Postgres `NULL || anything = NULL`, so those
rows hash to NULL, `count(distinct)` drops every NULL, and each one is miscounted as a duplicate.
Verified: all 1,317 NULL-source rows have distinct `md5(title||content)` — they are legitimate,
unique content and must NOT be deleted.

**How to measure real dupes** (per-source, temp-safe — never a global window dedup, it spills prod
pgsql_tmp at 1.6M rows): 
`select source_id from kb_chunks where source_id is not null group by source_id
 having count(*) <> count(distinct md5(coalesce(title,'')||content));`
Then delete per flagged source with `row_number() over (partition by title,content) where rn>1`.

After the 29 Aug cleanup: 0 sources with dupes; corpus 1,674,104 chunks / 103,025 sources.
Relates to [[the-funnel-was-all-fixtures]] scale-of-corpus context and [[agent-knowledge-loads-into-ops-knowledge]].
