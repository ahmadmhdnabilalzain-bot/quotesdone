---
name: a-new-guard-reddens-the-fixture-not-the-code
description: "When a tightened predicate turns green cases red, ask whether the FIXTURE became incomplete before you soften the rule — 66 cases in one session, and softening any of them would have restored the defect."
metadata: 
  node_type: memory
  type: project
  originSessionId: 051dbf76-3315-4c3b-9c5c-69c40409fdcc
  modified: 2026-08-24T11:51:17.924Z
---

24 Aug 2026, Phase D. Giving BR-012 and GATE-013 the leg PD-PRIV-002 needs — *every live file
revision of a supplier-safe package must be redaction-approved and metadata-clean, and a package
naming no file is refused* — turned green things red in three waves:

| wave | what went red | why |
|---|---|---|
| 1 | PD-DISP-003, on its **CONTROL** arm | its approved package registered no file |
| 2 | 41 of 1,799 step-contract cases (W08, W12, W13) | `fn_phase_d_fixture_scenario`'s package stage built an inquiry, an approver and a prose string and **no files** |
| 3 | 25 more (W08, W14, W15) | the package W08 judges is produced by the **drive**, not the fixture; and the comparison W14/W15 read defaulted to `DRAFT` |

**Every one of them was the fixture being incomplete under the new contract, not the rule being
wrong.** Softening BR-012 back would have restored the exact defect the case exists to catch: a
package with an unredacted drawing passing identically to one with a clean drawing.

The fixes, in order, and each is the shape to reach for:

1. give the committed fixture the artefact it always implied (`phase_d_o10`);
2. give the fixture FACTORY the same artefact (`phase_d_o11`);
3. find where the artefact is really created — for W08 it is `fn_phase_d_effect_produce` during the
   drive, not the factory — and hook it there, **guarded on `fn_phase_d_fixture_context()`** so
   production gains nothing (`phase_d_o14`);
4. where a new column defaults to the SAFE value (`publication_state` DRAFT), the fixture must state
   the value the workflow actually models, and a state change stamps its own moment rather than
   trusting a caller to date it (`phase_d_o13`).

**The diagnostic question: did the code change behaviour, or did the fixture stop satisfying a
contract it never satisfied?** Drive one workflow and read `first_handler_refusal` — it names the
gate, the rule and the subject, and it distinguishes the two in one line.

Related: [[a-key-written-in-two-shapes]], [[harness-seeds-an-order-reality-cannot-produce]],
[[tightening-a-guard-reddens-its-own-probes]].
