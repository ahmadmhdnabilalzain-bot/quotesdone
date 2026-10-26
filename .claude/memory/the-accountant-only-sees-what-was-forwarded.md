---
name: the-accountant-only-sees-what-was-forwarded
description: The expenses mailbox captures only forwarded receipts; vendors billing other addresses are invisible
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-09T05:03:53.029Z
---

9 Sep 2026. The founder said "anthropic must be much more than that, i pay 200 usd monthly" against a
booked Anthropic total of USD 257.25. He was right, and the cause is structural.

**THREE separate gaps, all found the same day:**

1. **Resend inbound retention (~1 month).** Its API held 9 of 36 forwarded receipts. Recovered from
   the founder's Gmail SENT folder. See [[resend-inbound-retention-is-about-a-month]].
2. **A second mailbox.** Anthropic bills `management@doratajewelries.com` (Outlook), not Gmail. Six
   receipts exist there (invoices YXWTXUVD-0001..0006, a consecutive series — a good completeness
   check); only the first three were ever forwarded, on 29 June. Confirmed by reading the 23 Aug
   receipt in full: **Max plan 20x, $200.00 + $10.00 UAE VAT (5%) = $210.00**.
3. **Receipts that arrived and were never forwarded.** The Gmail INBOX holds vendor receipts with no
   corresponding forward: **Replicate** (31 Aug, 4 Sep — a vendor the ledger had never seen at all),
   OpenRouter 7 Aug, Supabase billing notices 11 + 31 Aug, GoDaddy 11 Aug.

**The lens:** an ingestion path fed by a human forwarding step captures only what someone
remembered to forward, and the gap is invisible from inside — every forwarded receipt processes
perfectly, so the pipeline looks healthy at 100%. Completeness must be measured against the VENDOR
side (what was billed), never against the intake side (what arrived).

**How to check:** search each mailbox's INBOX for receipt-shaped mail and diff against
`expense_entries`, rather than sweeping only the forwards. Watch for consecutive invoice numbering
per vendor — a gap in the series is a missing receipt with no other evidence.

**Sequencing:** never run two mailbox sweeps concurrently. `source_msg_id` differs per mailbox
(`resend:`/`gmail:`/`outlook:`), so the key alone cannot catch a charge forwarded to two places —
dedup on the ECONOMIC identity (vendor + charge date + amount + currency), and that read-then-write
races if two agents run at once.

Related: [[expenses-email-source-of-truth]], [[zero-cannot-tell-a-dead-guard-from-an-idle-system]],
[[never-state-what-you-have-not-measured]].
