---
name: an-empty-string-is-not-a-null-scope
description: phase_d_fixture_catalogue scoping is `col is null or col = x`; the committed CSV renders NULL as "" and copying it back makes every new row unreachable.
metadata:
  type: reference
---

`fn_phase_d_fixture_input` selects with
`and (c.step_id is null or c.step_id = sr.step_id) and (c.workflow_id is null or c.workflow_id = v_wf)`.

Twelve EFFECT_PAYLOAD fixtures were committed on 23 Aug 2026 with `workflow_id = ''` and
`step_id = ''` because the committed CSV renders NULL as an empty quoted field and that rendering
was copied back in. Every row existed, the catalogue board counted them, and the lookup matched
none. Measured: `fn_phase_d_fixture_input(<step run>, 'EFFECT_PAYLOAD', 'bucket')` returned null
with the row sitting in the table.

**Why:** an empty string is a value; the scoping predicate tests for absence.

**How to apply:** write NULL, never `''`, for an unscoped catalogue row, and when a new fixture
"does nothing" check the scope columns before the value. Related: [[a-row-added-without-its-artefact]].
