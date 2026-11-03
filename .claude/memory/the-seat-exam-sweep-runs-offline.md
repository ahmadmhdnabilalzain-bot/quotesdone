---
name: the-seat-exam-sweep-runs-offline
description: "3 Nov 2026: the full seat-exam sweep (641 items) runs without production; code grades first against the canon; the commonest failure is a rewording that asks less than its rubric grades"
metadata:
  node_type: memory
  type: lesson
---

**What exists.** `scripts/eval/seat_exam_sweep.mjs` asks every exam item (633 + the 8-item trade bank) offline. It
works like this:

- A subscription model stands in for the seat. It gets the settled facts (company.md, seats.md, the seat card) and six
  2,400-character sources: the expected entries plus BM25 neighbours.
- Code grades first, in `scripts/eval/seat_exam_canon.mjs`: a canon contradiction fails outright; an expected fact or
  AED/% figure it cannot find goes to the judge.
- The judge is used only after `calibrate` passes (≥ 48/50, ≤ 1 good answer flagged).

No token, no gateway, no production write. Report: `docs/reports/seat_exam_sweep_2026-11-03.md`.

**Lessons from the first sweep:**

- **Run `audit` before asking any model.** On main it found 45 canon contradictions in the knowledge itself: 22
  entries said a silent supplier's refund is "automatic" (Terms v11 §5: "no refund is automatic"), and four said
  banks take "5 to 10" days instead of 7–14. Code found these for free; the answers then repeated them.
- **The commonest failure was the ITEM, not the knowledge.** In 18 items the rewording (`q_reworded`, or a bank
  `wordings[i]`) asked something narrower than the rubric grades. When writing a wording, keep q_en's whole scope,
  audience and channel. Only failing items were checked, so others may still drift.
- **A judge shown only the reference fails facts it cannot see.** Rule v1 failed true settled facts (NOL number, day-5
  ladder). The fix was to tell it that code has traced every figure; it now fails only a contradiction. Recalibrate
  after any rule change, and re-judge only the judge's failures when the change can only remove a reason to fail.
- **The answer cap must not be tighter than production.** 160 words cut multi-point answers; think() allows about 900
  tokens.
- **The robustness figure is the regression sample, not the composite.** Re-asking failures until they pass reaches
  100%; previously passing items held at 105/107 on fresh wording.
- **A batch file showed the sources of every question in it.** Use one question per file when that matters.

**Still open.** The corrected packs reach production only when loaded after merge. The same exam through `think()`
on the gateway (retrieval rank, the production model, Arabic) waits on a token and on OpenRouter.
