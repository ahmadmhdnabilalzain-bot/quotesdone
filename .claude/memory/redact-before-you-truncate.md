---
name: redact-before-you-truncate
description: Truncating first and redacting after measures the window on text that still holds the id, so the row shifts when the id gains a digit.
metadata:
  type: reference
---

`PHASE_D_WORKFLOW_IMPLEMENTATION_RESULT.csv` redacted per-run ids out of its reason columns so the
deliverable would reproduce — but it ran `left(reason, 400)` FIRST and `regexp_replace(..., '<id>')`
after. The 400-character window was therefore measured on the text with the id still in it. When
capability request ids crossed 9999 on 24 Aug 2026, every reason column shifted by one character and
ten rows stopped reproducing: `...completing a busines` vs `...completing a busine`. **The id was
redacted and its length was not.**

- Redact first, then bound.
- Choose the digit width by measuring what actually varies. Two consecutive builds of
  `PHASE_D_INJECTED_DEFECT_RESULT.csv` differed on five rows, all step run / task / trace ids of six
  or more digits; `[0-9]{3,}` would have eaten "28 of 257" and "20,465", which ARE the finding.
- `PHASE_D_DRIVE=1 node --test scripts/checks/phase_d_deliverables_match_production.test.mjs` is the
  only check that catches this — the two driven reproductions are SKIPPED without that env var.

Related: [[a-committed-constant-beat-the-record-it-described]], [[regenerate-the-mirror-after-the-last-apply]].
