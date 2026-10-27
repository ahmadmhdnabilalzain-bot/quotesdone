---
name: addressed-to-an-identity-nobody-models
description: "QuotesDone's recurring root cause — a complete thing addressed to an identity the system does not model; fix at the write boundary, never by widening the reader's join."
metadata: 
  node_type: memory
  type: project
  originSessionId: 589dfbd3-2168-48da-b6d1-e2f19bb101eb
  modified: 2026-08-14T08:58:38.677Z
---

Four times now the same defect: something complete and correct exists, is addressed to an
identity the system does not model, so nothing reaches it.

1. 115,148 knowledge records in a table no customer path read.
2. The founder himself — `app_secrets.admin_mfa_phone` resolved to nobody, so mobile sign-in
   404'd and WhatsApp answered him with the public marketing script.
3. (fixed 10 Aug 2026) 75 of 82 pending `agent_actions` addressed to `strategy_ai`,
   `knowledge_curator`, `legal_ai` and four department names — none an `org_agents` row.
4. Still open as of 11 Aug 2026: `ai_quality_snapshots.agent` 754 of 1,066 and
   `agent_expectations.agent` 29 of 36 are not employee keys either; `agent_runs.agent` is
   deliberately a JOB name, not an employee, and the Row #3 `employee-performance` check
   assumes otherwise.
5. (fixed 14 Aug 2026) The SIX executive officers in `exec_agents` — `strategy`,
   `operations`, `procurement_quality`, `data_science`, `product_ux`, `competitive` — existed
   in neither `org_agents` nor `org_agent_alias`. They filed a report and a decision every day
   under names no role covered, and consequently reasoned with none of their department's SOPs,
   decision rules or authority. Aliased by charter; the officer's prompt now comes from
   `fn_agent_context_capped`.
6. (fixed 14 Aug 2026) One layer up again: the 24 PACKAGED department names and the runtime
   `dept_key`s were two vocabularies for the same departments, bridged by nothing. String
   similarity resolved 8 of 24 and would have mapped three wrongly — `admin_operations` is
   runtime `knowledge`, `knowledge_learning` is `knowledge_eng`, `marketplace_operations` is
   `procurement`. Read the charter, not the name. Bridge is `org_department_alias`.

**The fix shape that worked:** a `BEFORE INSERT` trigger on the target table plus a curated
alias table (`org_agent_alias`) and a resolver (`fn_org_agent_resolve`): active key → alias →
department head. Not by widening the reader's join — the next reader
(`fn_agent_context`) would still have got an empty identity. The raw name is preserved in
`detail.addressed_as`; an unresolvable addressee goes to the Chief of Staff with
`escalated = true` rather than being silently reassigned.

**Why a trigger counts as "at the writer":** 38 functions insert into `agent_actions`.
Patching 38 leaves writer 39 free to invent the next name.

See [[two-queues-two-vocabularies]] and [[executors-are-edge-functions]].
