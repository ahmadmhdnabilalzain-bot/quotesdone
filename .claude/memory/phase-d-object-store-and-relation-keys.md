---
name: phase-d-object-store-and-relation-keys
description: "phase_d_scenario_record keys by the real relation row id, phase_d_object_record by a derived uuid — they never match, and that blocks ~10 workflows."
metadata: 
  node_type: memory
  type: project
  originSessionId: aa55e49d-4ddb-44db-87b4-c412a7a8e170
  modified: 2026-08-22T18:46:51.756Z
---

Measured 22 Aug 2026 inside one fixture scenario: for `customer_terms_acceptance`,
`supplier_safe_package`, `quotation_revision` and `ux_specification`, the key on
`phase_d_scenario_record` is the primary key of the row in the real business relation (e.g. `44779`)
and the key on `phase_d_object_record` is a derived uuid (`a0744275-…`). Rows matching: **0** in
every case.

The context resolver hands rules the first; rules like BR-012, BR-026 and BR-035 look it up in the
second (`fn_phase_d_rule_check` BR-012: `o.business_key = v_txt or 'supplier_safe_package:' ||
o.business_key = v_txt`). So a package that IS approved reads as 0 approved packages. This is the
first refusal for roughly ten of the fifteen workflows that execute nothing.

It is **not uniform** — BR-013 and BR-015 read `public.inquiries` and `public.leads` and want the
relation key they already get. Keying the object store by the relation id would fix three rules,
break two, and destroy the replay determinism the md5-derived key exists for.

**Why:** two stores for one object, with no mechanism keeping their identities in step.

**How to apply:** this is the next Phase D increment and the largest single unlock. The three
candidate routes and what each costs are written up in `docs/phase-d/PHASE_D_BUILDER_CLOSURE.md`
under "The one defect behind most of what is left". Related: [[a-key-written-in-two-shapes]],
[[two-gates-one-vocabulary-nothing-keeps-them-in-step]].
