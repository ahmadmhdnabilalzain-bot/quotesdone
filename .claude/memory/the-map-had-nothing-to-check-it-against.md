---
name: the-map-had-nothing-to-check-it-against
description: "26 of 90 roles reported to the wrong manager while fn_phase_a_organization_violations returned 0 and fn_phase_c_invariants returned 58/58 true — every check measured graph PROPERTIES, none had the founder's map as a subject."
metadata: 
  node_type: memory
  type: project
  originSessionId: e0e7f847-fa0a-4a92-8b70-4d836e3022fe
  modified: 2026-08-16T08:51:20.253Z
---

16 Aug 2026. The founder delivered `QuotesDone_PHASE_C_REPORTING_AND_CHAIN_OF_COMMAND_MAP_v2026.08.16`
and a companion agent-by-agent dossier package. Reconciling found 26 of 90 standing roles with the
wrong manager or class, and 86 of 86 overlays missing their broad-domain escalation — under a
completely green invariant board.

**Why:** `fn_phase_a_organization_violations()` and `fn_phase_c_invariants()` measure PROPERTIES of
the reporting graph — every role has a manager, the manager is active, no cycle, no self-management,
no duplicate identity. Neither had the founder's map as a **subject** to compare against. A graph can
satisfy every structural property and still be the wrong graph.

**How to apply:**
- The authority now lives in `public.phase_c_reporting_authority` (90 rows) and
  `phase_c_overlay_binding.broad_domain_escalation_role_id` (86). `fn_phase_c_reporting_map_drift()`
  compares live against it; `scripts/checks/the_reporting_map_is_what_the_founder_approved.test.mjs`
  runs it. **Move the authority first, then the runtime — never the reverse.**
- The check asserts its own subject first (`authority_not_recorded`): every other branch reads that
  table, so an empty table would report perfect agreement with nothing. See
  [[absent-input-scores-as-satisfied]].
- **Resolve BOTH sides through `org_role_alias` before comparing.** The packages address roles by
  descriptive name (`accounts_payable_specialist`), the DB by physical key (`accounts_payable`).
  Resolving one side only manufactures dozens of phantom mismatches — it also made two consistent
  founder packages look like they contradicted each other on 23 edges. See [[a-key-written-in-two-shapes]].
- **This was a CHANGE, not drift.** `docs/phase-a/PHASE_A_REPORTING_GRAPH.csv` agreed with the live
  DB on all 23 edges; the 16 Aug package supersedes the 15 Aug baseline. Recorded as PACR-001.
  The Phase A *guard* only compares COUNTS, but `fn_phase_a_baseline_drift()` hashes
  `role_id|manager|dept` — so a manager change slips past the guard and surfaces as drift at sweep
  step 8. Re-freeze the digest in the same change, recomputed in place, never transcribed.
- Chain of command as measured: 4 of 257 steps are owned by founder/chief_of_staff, all in **W01**
  (founder mandate) and **W02** (target miss) — named explicitly in the drift check so a new workflow
  cannot quietly join the exception. `refund_decision` is the only founder approval, and a partial
  unique index makes a second unwritable.
