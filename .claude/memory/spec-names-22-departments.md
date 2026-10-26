---
name: spec-names-22-departments
description: "quotesdone agents and knowledge.txt" names 22 departments; dept_plan and dept_learn fan out over org_departments where active, so a row in that table is how the company hires.
metadata:
  type: project
---

The department list in `quotesdone agents and knowledge.txt` has **22** entries.
On 11 Aug 2026 the live company had 14, one of them (`supplier_success`)
switched off. Eleven were created and Data & Analytics restored, taking the
company to 25 departments and 93 employees.

Why the table is load-bearing rather than decorative: `dept_plan` (index.ts:252)
and `dept_learn` (index.ts:72) both fan out over
`org_departments where active = true`. A department that exists there plans its
own work daily and learns from outcomes nightly, and `cos_execute` carries the
tasks out. So adding a row IS hiring, and `active=false` silently stops a
department planning, learning, and — if it also has no `os_department` row —
knowing its own purpose, mission or escalation path.

The spec forbids a one-person department ("Departments should not consist of a
single AI"), so each needs ≥2 staff, a named manager, an objective, an authority
grant, a budget row and an OS mapping.

`dept_key = 'knowledge'` is the **Operations** team under a legacy key. Do not
rename it: it is a primary key behind four foreign keys and many bare string
literals. Relates to [[specs-are-upgrades-not-repairs]].
