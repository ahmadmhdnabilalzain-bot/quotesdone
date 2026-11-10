---
name: an-eval-answer-key-is-a-claim-too
description: "28 Oct 2026: 13 of 34 market packs 'below the recall floor' had been answered correctly by their own trade's base-pack entry; the eval named only one of two right answers. Read what was returned before tuning retrieval or content."
metadata:
  type: feedback
  modified: 2026-10-28
---

The knowledge eval failed 34 market packs. The brief offered two causes, retrieval or the content of the packs. The
first thing that moved the number was neither. In 25 packs the routine's top 5 held the question's OWN trade's
base-pack entry (usually `product-distinctions`), and in 13 of them that entry's body answered the question as asked.
The eval expected only the market entry, so a right answer scored 0.

**Why:** an answer key written once, per question, before later entries existed (the base packs were enriched after
the market evals were written) goes stale silently. A recall of 0 then reads as a retrieval defect.

**How to apply:**
- Before changing a routine or an entry to fix recall, print what the routine RETURNED for the failing question and
  read those bodies. A correct answer under another id is an answer-key error.
- It is fixed with `expected_mode: "any"` plus a per-question `why`, never a blanket.
- Accept an alternate only if its body answers the question as asked. Refuse it when the question's point (for
  example "made locally?") is not in the body.
- Do NOT edit an entry until it scores on a ONE-question eval. With nothing held out, any gain is overfit (a title
  echoing the question's words raised 0.858 to 0.887).
- Report: docs/reports/market-pack-recall-2026-10-27.md.

Related: [[a-fixs-own-check-measures-the-case-the-fix-handles]], [[instrument-measuring-wrong-subject-is-the-lens]].
