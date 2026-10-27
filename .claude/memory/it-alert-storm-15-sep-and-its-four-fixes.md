---
name: it-alert-storm-15-sep-and-its-four-fixes
description: "15 Sep 2026 — the founder got ~50 IT emails overnight; causes and the four merged fixes (#691 #692 #693 #694); what to watch next"
metadata: 
  node_type: memory
  type: project
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-09-15T07:37:09.836Z
---

15 Sep 2026, ~05:40Z: the founder said "i got so many errors on my email from the IT engineer".

**Measured:** 45 emails were "Not backed up to Dropbox: <table.column>". One `duty:backup_gap:*` finding per column fired in the same tick (23:10Z), and the IT loop sends one founder `it_new_bug` email + WhatsApp per issue. There were ~5 others: a GitHub 401 (already fixed), Dropbox/Vercel owner not accepted, the Stripe live webhook missing dispute events, and a uribl false positive. 111 more (31 email + 80 WhatsApp) were set to `status='skipped'` by hand. They are not deleted and must not be resent.

**Fixes, all merged 15 Sep:**
- **#693 (2ae67a1)** `the_founder_gets_one_it_digest_per_tick.sql`: founder `it_new_bug` requests are held, and `fn_customer_support_sends_the_it_digest` sends ONE digest per tick, at most one per 60 min. A family (issue_key prefix) is one line with its count. The check `every_send_comes_back_to_whoever_asked.test.mjs` now lists 2 files that may set `app.qd_delivery_tracked`.
- **#691 (82a6aee)** send_outbox selects only email/null channels. 20 undeliverable WhatsApp rows at the head of the queue starved all email from 01:03Z to 06:00Z. send_outbox v93.
- **#692 (b10a65a)** `fn_it_dnsbl_listed`: a DNSBL refusal code (uribl 127.0.0.1) is never a listing. quotesdone.com is NOT listed.
- **#694 (efa58ba)** export pages are sized by bytes (starting at 100 rows, about 4 MB each), and the page is halved when a 546 kill repeats on the same page. backup v12. ops_knowledge rows reach 601 kB; a fixed 1000-row page = 21 MB → CPU 546 on every resume.

**Follow-ups 15 Sep ~06:30Z:** the 2026-09-15 export finished at 06:17:37Z (manifest written; `chain_stalled` closed). #687 merged as 05eefcb after re-review against #694. 2,840 `doc_backups` EXPORT rows sat `pending` with no drain since 02:01Z; a helper is fixing the Dropbox drain in a PR. `duty:restore_table:export_stale` and `:restore` should close on the next IT tick through `fn_it_restore_table_due`'s newer-export branch.

**Backup chain closed at 07:36:51Z:** all 2,840 `EXPORT:2026-09-15` doc_backups rows are done: 0 open, 0 error, 0 abandoned. The drain was started by #696 and deployed as dropbox_backup v59. Two transient `no_dropbox_auth` failures retried clean. The per-run token-refresh fix is in flight as a separate PR.

**Supplier-portal catalogue audit, 15 Sep:** no deterministic reader for profiles or catalogues (every path needs the held LLM). The confirm panel shows only directory-derived trades. 0 of 15,305 suppliers are confirmed. The `customer_api` keyword fallback (`match_suppliers_kw`) breaks exact-match-or-none. New categories can't be proposed. `save_profile` overwrites typed services. Planned fix: `_shared/doc_read` text → `fn_norm_trades` → proposals in `CapabilityConfirmPanel`.

**Why:** the per-issue dedupe had no cross-issue batching. A new duty emitting N findings at once pages the founder N times.
**How to apply:** any new duty that can raise many findings at once should share one issue_key family. Verify the digest the next time a burst happens. The founder `it_new_bug` WhatsApp is still undeliverable until Meta approves the template (see [[checkpoint-14-sep-night-what-is-live-and-what-carries]]). #687 stays held until the 2026-09-15 export is `done`.
