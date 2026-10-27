---
name: the-org-is-ten-departments-now
description: "Since 14 Aug 2026 the company is 10 active departments and 176 canonical roles in org_role; org_agents.agent_key is the physical key, org_role.role_id the clear one."
metadata: 
  node_type: memory
  type: project
  originSessionId: fd0754be-8798-4bcf-aec6-6ae1c72265c4
  modified: 2026-08-14T13:05:42.866Z
---

`exec`, `growth`, `customer_experience`, `marketplace`, `product_eng`, `data_intel`, `finance`,
`legal`, `people_ops`, `assurance`. The other 22 rows survive with `merged_into` set and
`active = false` — never delete them, `fn_dept_scope` reads that column.

**Identity is two layers.** `org_role.role_id` is the unambiguous name (`chief_of_staff`,
`general_counsel`, `marketplace_director`); `org_agents.agent_key` keeps the physical runtime key
(`brief`, `legal`, `procurement`) because those ten keys are string literals in 51 sites across 40+
live routines. `fn_org_role_resolve` / `fn_org_agent_resolve` / `fn_org_role_agent` convert in every
direction; `org_agent_alias` and `org_role_alias` must stay in step or an addressee silently becomes
`brief` + escalated.

**Why:** the founder asked for renames AND for no orphans. Only the two-layer form gives both.

**How to apply:** address agents by canonical `role_id` in anything new. Never write a bare
`agent_key` comparison for a role that could be merged — resolve it. `fn_org_role_violations()`
must stay at zero; it is the completeness gate.

Related: [[exact-match-scoping-breaks-on-merge]], [[spec-names-22-departments]],
[[a-picker-not-told-who-wrote-it]].

**Superseded 3 Sep 2026 (PACR-004):** still 10 active departments, but re-carved — exec (Office
of the CEO), supply (NEW; lead bd), growth (Demand), marketplace (Marketplace Ops), finance,
customer_experience, legal (Trust, Safety & Compliance), product_eng (Platform & Reliability;
absorbed assurance), data_intel (Data & Experimentation), people_ops (Agent Ops). Keys unchanged;
assurance inactive/merged_into product_eng; supplier_success + bizdev merged_into supply.
71 canonical roles active, 24 personas parked. Baseline counts live in org_phase_baseline (phase A).
