---
name: the-org-is-two-agents-and-no-departments
description: 7 Sep 2026 — the org chart, every pre-programmed workflow and the kernel gates were all removed totally; only ceo and customer_support remain
metadata:
  type: project
---

On 7 September 2026 the founder dismantled the whole structure, in four rulings, each in his words:

1. *"actually remove the whole organization chart that you made cause its trash"*, *"literally
   everyone else should have nothing"*, *"so no departments from now"*, *"no tasks excepts what i
   confirm"*, *"not archive. remove totally"* (I had archived first; he refused that).
2. *"and rename lifecycle channel operation into customer support"*.
3. *"dont link everything to CEO. i didnt say that. keep them unlinked now till we come up with the
   new structure"* — after I had repointed 1,740 components at the ceo.
4. *"remove everything except the company knowledge, terms and conditions and website related stuff
   and my decisions which i shared earlier. i dont want any pre programmed workflow as things will
   totally be different"*, then *"i said remove the kernel gates"*, and *"the CEO we built today
   remains"*.

**What exists now:** two seats, `ceo` and `customer_support` (the WhatsApp agent), both with
`primary_department_id` null. No departments, no tasks, no workflows, no handoffs, no event
subscriptions, no action executors, no kernel write/trace gates.

**Removed totally:** 179 of 181 roles · 94 of 96 agents · all aliases · 33 org_departments + 14
os_department · budgets and objectives · 2,489 tasks · 30 workflows · 257 steps · 8 handoffs ·
347 events · 56 business objects · 54 rules · 32 gates · 719 crosswalk rows · every Phase C binding ·
every Phase D handler schema, gate contract and fixture · the older second copy (20 workflows,
187 steps, 27,559 runs) · 41 subscriptions · 94 executors · 36 kernel gate triggers.

**Kept:** knowledge (9,140 ops_knowledge, 2.69M kb_chunks, 484 FAQs), terms, website data
(22,265 leads, customers), his decisions (10 boundaries, 11 reserved decisions, 27 commands), the
CEO's own machinery and charter, `phase_c_component` + cron (infrastructure), and every trace and
audit log — history is not an org chart, so `phase_c_system_execution`'s 61,721 rows kept their
truth by dropping the FK rather than repointing them.

**Two guards deliberately survived** and must not be removed: the TRUNCATE guard on 100+ tables, and
`anon_cannot_execute_security_definer` in CI — that one is security, not structure.

**How to apply:** never invent a third agent, never write a department, never create a task he has
not confirmed, and never rebuild a workflow registry. He is building back one by one. See
[[quotesdone-work-is-assigned]] and [[checks-retired-with-their-subject]].
