---
name: all-conversations-are-kept-for-sales
description: "Founder 14 Sep 2026 — every conversation saved permanently, backed up to Supabase AND Dropbox (email as PDF); sales engineer files, IT engineer verifies"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5fbd934d-0d8b-4d31-9206-29d664d2fd4b
  modified: 2026-10-05T20:44:25.144Z
---

"all conversations need to be saved and the sales agent has access to them at any time. just in case we needed them for any reason" (14 Sep 2026). Then: "if the provider has one month history then we print a pdf copy of that email and keep it in our back up" and "by back up i mean 2 points. supabase and dropbox". Then: "i think the IT agent need to check such details yea?"

**SUPERSEDED IN PART, 6 Oct 2026 (ledger 1123):** the founder set a retention limit for PDPL: *"1 year is enough"*, then the same day (ledger 1126) *"if 5 years wont make a big difference in the size … keep 5 years, if legal"*. Conversation storage is tiny (about 3 MB of text and about 100 KB a day of PDFs), so the period is **5 years**, as long as the legal basis checks out (UAE commercial record-keeping); otherwise 1 year. A conversation is kept while the account is active and for 5 years after the account closes or goes inactive, then purged from Supabase AND Dropbox. The privacy policy states this period in EN and AR. Everything below still applies inside that window.

**Why:** disputes, refunds and supplier incidents may need the full record later; Resend keeps inbound mail only ~1 month.
**How to apply:**
- No purge/TTL on conversation stores other than the retention window above (active + 5 years after closure); every channel persists full text, readable by the sales_engineer seat.
- **The one exception, founder 14 Sep 2026 (founder_instruction 408):** *"conversation for test data can be deleted"*.
  A conversation or message row may be deleted only if it's provably a test fixture, i.e. the row itself carries a
  `+9715000000XX` number, an `@example.invalid` email, a ZZ DEMO name, `demo_factory`, or an e2e run tag. Never infer it
  from timing. Real conversations are never purged.
- Every email in/out → PDF → private Supabase bucket `backups` + Dropbox under the existing tree (fn_enqueue_doc_backups: entity → type → date, `Correspondence/` folders). Reuse doc_backups + dropbox_backup; never a second uploader.
- Duties split: sales_engineer FILES (tree, uploads); it_engineer VERIFIES (post-upload metadata check, weekly re-check, 48h coverage watch), hands failures back to sales via handoff, re-checks, and sends the daily summary to the CEO. Sales never marks its own work verified.
- Trigger today: resilience_ping → fn_dropbox_backup_due → dropbox_backup (pg_cron holds one inactive row).
Related: [[payments-are-the-accountant-and-talk-to-sales]], [[resend-inbound-retention-is-about-a-month]].
