---
name: the-harness-withholds-only-w12
description: "257/257 effects holds only because the fixture withholds the workflow's own output for W12 alone; withhold it everywhere and it is 248/257."
metadata: 
  node_type: memory
  type: project
  originSessionId: f0a9ce54-2678-4fe4-bf76-b0b8f5e3e91a
  modified: 2026-08-23T18:42:54.275Z
---

`fn_phase_d_fixture_scenario` accepts `for_workflow`, and its rule is right: skip a **leaf** stage
whose object the workflow under test produces, because a harness that seeds the row the step is
supposed to create is answering its own question. The deliverable builders ask for it on **W12 and
no other workflow, by name**.

Asked for on all 30 (23 Aug 2026), the coverage matrix fell from **257 of 257** steps producing
their declared effect to **221**, and four root causes came out of it — all four fixed, K06 and K07:

* a rule governing the workflow that produces its subject (BR-018/W14, BR-032/W16)
* a run that could not see the object it had itself created (W17-S07 asking for the refund case
  W17-S01 made six steps earlier)
* a gate demanding its subject before the step that produces it (GATE-013 at W08-S01) — and the
  exemption must turn on `predicate_kind = EVIDENCE_REQUIRED`, or it kills GATE-015, which exists to
  judge the creating step
* an effect named for an object is not a reference to one: `effect_object_id` comes from the step's
  DECLARED object, so a W15 review verdict carries `quotation_comparison` with a
  `public.review_chain:id=…` reference. Match `effect_relation` against the binding's
  `canonical_relation`.

After those: **248 of 257**. The remaining 9 are all of W09, blocked by BR-025 needing a terms
acceptance W09-S06 is itself the step that records. Its subject is **not derivable** from any
register today — `phase_d_fixture_stage.contributes_ref` is null for `supplier_terms_acceptance`,
and `phase_d_context_key_object` cannot map `terms_version`/`terms_hash` to one object because W04
and W09 own different acceptances.

The committed basis stayed W12-only so the published 257/257 remains reproducible; the stricter
figure is recorded in `docs/phase-d/PHASE_D_HANDOVER_2026-08-23_R2.md` §5. Related:
[[a-rehearsal-proves-creation-not-execution]], [[an-identity-is-never-a-fixture]].
