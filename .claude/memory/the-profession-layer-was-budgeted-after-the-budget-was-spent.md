---
name: the-profession-layer-was-budgeted-after-the-budget-was-spent
description: 6 Sep 2026 knowledge audit — fn_agent_context admits a LAYER 2 profession row only while length(out) ≤ ~8,200, but the blocks emitted before it already total 11–13k, so 54/54 agents ran with an empty profession layer; LAYER 3/4 fell past the 19,500-char cut the run-time path keeps. Ingestion was pointless until the plumbing was fixed.
metadata:
  type: project
---

Another instance of [[guarded-by-a-condition-that-cannot-occur]]: the admission test for the
profession layer (`length(out)+length(piece) <= own_cap+2200`) was correct in isolation and could
never be true at the point it ran. Companion defects found the same night: fn_ops_knowledge_search
scoped `dept_key = dept` exactly (people_ops never saw its `hr` rows; supply never saw
marketplace_expert); the 1,204 category packs were reachable only via a p_category_key the runtime
passed as NULL; decision_policy thresholds were read by no context; the exam sampled other
departments and category YAML and wrote wrong verdicts back as experience; ~2.54M of 2.65M
kb_chunks had no embedding with the backfill crons inactive; dept_library empty for 7 departments.

**How to apply:** before ingesting knowledge for an agent, call fn_agent_context(key, 22000) and
grep for the profession body and the four T&C rules — "stored" and "known" are different tables.
The audit files are docs/knowledge_audit/*.md; the plan is docs/KNOWLEDGE_PLAN_2026-09-06.md.
