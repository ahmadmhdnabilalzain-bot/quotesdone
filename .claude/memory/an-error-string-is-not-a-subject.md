---
name: an-error-string-is-not-a-subject
description: Never infer which table owns a row from the error text; read the column that names it
metadata:
  type: reference
---

Closing 26 orphaned `doc_backups` rows, I keyed the guard on the ERROR STRING (`supplier_missing`,
`compare parse_failed`) and invented the tables to check against — `public.suppliers` and
`public.quote_comparisons`. Neither is the subject; `suppliers` does not exist at all and the apply
failed 42P01. `doc_backups` carries an `entity` column that names the subject: `supplier` →
`public.leads`, `inquiry` → `public.inquiries`.

**Why:** an error string describes HOW a job failed. It is not a statement about which table owns
the row, and reading it as one leads to checking the emptiness of an unrelated table and calling
that proof.

**How to apply:** find the column that names the subject and branch on it. Then state per class
whether the control is STRONG (the parent holds rows, so the lookup can return true) or WEAK (the
parent is empty, so "not exists" is trivially satisfied) — an empty parent still means every child
is orphaned, but say so rather than presenting it as the check discriminating.
See [[zero-cannot-tell-a-dead-guard-from-an-idle-system]] and [[group-per-class-not-in-aggregate]].
