---
name: a-later-sql-file-can-silently-delete-a-rule
description: 2 Nov 2026. Two PRs replacing one routine: the later MANIFEST line deletes the earlier rule with every check green.
metadata:
  type: feedback
---
#1746 replaced fn_sales_engineer_verifies_supplier without the services gate #1760 had just added; applying it would have removed founder ledger 1469 silently. Caught by grep, not by any check.

**Why:** the highest MANIFEST line wins and read-back only proves the file landed.

**How to apply:** before merging any PR with SQL, list every routine it defines and diff against the live body. the_supplier_gate_keeps_the_services_hold_in_every_later_body.test.mjs guards this one rule. Related: [[apply-at-merge-never-before]], [[applying-an-old-file-resurrects-a-superseded-routine]].
