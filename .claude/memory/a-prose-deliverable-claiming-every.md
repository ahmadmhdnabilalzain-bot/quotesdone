---
name: a-prose-deliverable-claiming-every
description: "A required deliverable that opens \"every X, in order\" and has no check behind it goes silently short — the ledger and its rollback twin were nine files behind, and both asserted a stale count."
metadata: 
  node_type: memory
  type: project
  originSessionId: ba4ede58-946f-4477-8042-69cef19ee057
  modified: 2026-08-20T03:15:57.399Z
---

`docs/phase-d/PHASE_D_PRODUCTION_DEPLOYMENT_LEDGER.md` opens *"Every Phase D write to
`htdblwldjkcgjvmqkbeh`, in order"*. On 20 Aug 2026 it stopped at `d51`, and so did
`PHASE_D_ROLLBACK_CLASSIFICATION_D9.md` and `scripts/sql/down/README.md`. Nine files were missing
from all three: `d45`, `d52`–`d56`, `e4`–`e6`. All three asserted **73** files; `ls` and
`git ls-files` returned **82**. All three said *"There is no `d45`"* — written hours before `d45` was
applied in the same session, and never re-read.

**Why:** the artefact-vs-registry check exists for rows and CSVs
([[a-row-added-without-its-artefact]]) but nothing compares a prose document to the corpus it claims
to cover. A completeness claim in prose has no denominator, so it cannot go red — it just stops being
true.

**How to apply:** whenever a document says *every*, *all N*, or *there is no X*, treat the number as a
measurement with a timestamp, not a fact. Re-run the count (`ls`, `git ls-files`) before quoting it,
and correct it **in place with the reason it was wrong** rather than deleting the sentence — the
correction is the useful record. When appending to such a document, append the count re-measurement
too, and give new rows their own read-back timestamp instead of restating the old one as if one
reading covered both. Related: [[stage-paths-never-git-add-all]], [[two-files-one-routine-one-commit]].
