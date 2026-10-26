---
name: a-cleanup-that-stops-at-the-first-table
description: "public.documents feeds doc_backups, which retries 5x and outlives the document; and the management endpoint commits each statement on its own."
metadata: 
  node_type: memory
  type: project
  originSessionId: f0a9ce54-2678-4fe4-bf76-b0b8f5e3e91a
  modified: 2026-08-23T18:42:01.788Z
---

Setting a document path on `public.leads` is not inert. Trigger `reg_lead_docs` fires
`AFTER INSERT OR UPDATE OF (license_doc_path, company_profile_doc_path, egr_doc_path,
catalog_doc_paths)` and registers a row in `public.documents`. `fn_enqueue_doc_backups` then copies
it into **`public.doc_backups`**, and THAT is the queue cron job 88 (`dropbox_backup_scan`, every 15
min) drains — it retries a row **five times** and **outlives the document that produced it**.

23 Aug 2026: a §8 fixture set `license_doc_path` on two suppliers. Deleting the two `documents` rows
did not stop anything — `doc_backups` 46209/46210 kept failing "download Object not found" at
attempts 4 of 5 and produced 4 `company_event` rows and 4 `agent_runs` **error** rows across four
15-minute sweeps, which reddened `a_failed_scheduled_run_has_a_reader`. Nothing reached Dropbox (the
storage objects never existed), but an *attempted* production Dropbox write is what the hold forbids.

**Why deleting in the next statement does not save you:** the Supabase management endpoint
**commits each statement on its own**, so a create-then-delete pair leaves a real window a cron job
can run inside. It did, twice.

**How to give a supplier a document safely:** use `iban_doc_path` — exposed by `supplier_portal`
through `DOC_KINDS` exactly like the licence, and in **no** watch list of `reg_lead_docs`. Measured
in an aborted transaction: `iban_doc_path` registers 0 documents, `license_doc_path` registers 1.

**How to clean up:** follow the chain to its end and COUNT the end in the zero-effect assertion, not
just the table you wrote. See [[http-probes-commit-so-pick-safe-tables]].
