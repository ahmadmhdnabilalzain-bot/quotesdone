---
name: checkpoint-9-sep-the-accountant-and-the-books
description: "State after the 9 Sep 2026 accountant build — READ FIRST on resume; PR #552, books at AED 6,905.59, one shortfall open"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-09T06:12:37.745Z
---

**PR [#552](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/552)**, branch
`agent/accountant-money-gets-an-owner`. Local suite green, canonical manifest 0 findings, deploy
parity 63/63, schema mirror regenerated LAST and identical.

## The accountant is the 4th seat and it is live

Seated with 10 payment functions. Refunds and Meta-ads spend carry a **zero ceiling** — the
founder's ruling, not a limit awaiting a number — so every one refuses here and routes to a CEO
decision. Runtime deployed with actions `health, grants, ledger, refund_request, assist,
expense_sweep, spend_report, document, documents`. Model pair `openai/gpt-5.6-luna` →
`google/gemini-3.1-flash-lite`. 113 knowledge records, embedded, 35/35 retrieval, and it holds **no
tax rate, threshold or deadline anywhere** by design — it names the FTA instead.

## The books

**AED 6,905.59 · 48 receipts · 13 May – 4 Sep 2026.** Ledger balanced. 48/48 records carry an
openable PDF (5 vendor invoices, 43 email prints; `doc_kind` says which). The spend report links
every line to its document.

Delivered to the founder as **Revision 4** — each revision names itself and supersedes, because two
PDFs with the same filename and different totals is worse than one wrong one.

**One shortfall stands, correctly:** OpenAI/ChatGPT is still billing monthly and **never emails an
invoice** — the Aug/Sep charges are real and unbooked, and live only in the ChatGPT billing portal.
The founder said he will share them.

## Open items for him, not for us

- **GoDaddy may be double-charging.** Order 4109276253 (10 Jun, AED 392.55) prepaid ~12 months of
  Advanced Email Security + Email Archiving to Jun 2027, yet the 10 Jul and 10 Aug renewals charge
  those same two products again at **AED 34.33/month**. Only GoDaddy's account can settle it; no
  credit was assumed. Written onto the entry's own note.
- **Vercel invoice `OOJ7APIU-0002` is missing from the sequence** — voided or never forwarded, never
  checked.
- Mashreq bank charges (AED 200/mo, two debited) deliberately NOT booked —
  see [[the-bank-is-mashreq-and-statements-come-monthly]].

## What was found and fixed along the way

See [[the-accountant-only-sees-what-was-forwarded]] (three ingestion gaps),
[[a-guard-that-names-a-remedy-that-does-not-exist]] (`fn_gl_reverse` never existed),
[[the-estate-could-not-email-a-file]], [[a-correction-must-reach-who-got-the-original]],
[[pg_cron_removal_left_queues_with_no_consumer]] (WhatsApp),
[[resend-inbound-retention-is-about-a-month]].

**Every UAE invoice was invisible to the parser** — the printed dirham `د.إ.` wrapped in U+200F
defeated the amount pattern, and a `\b`-less total matched inside SUBTOTAL. Both fixed at the root
in `_shared/receipt_parse.ts`.

**`llm_calls` is a dead table** — the live LLM ledger is `public.ai_cost_log`, written by
`fn_llm_log` from `ai_gateway`. Its null tokens came from a variable declared and never assigned in
`site_assistant`. OpenRouter spend now records the seat that spent it; unattributed spend gets its
own line and is never spread across agents.

## The registers that stop it recurring

- `expense_billing_mailbox` — every mailbox, whether swept, and how it was reached.
- `expense_vendor_billing_mailbox` — vendor → mailbox → in_ledger_scope (three-valued; undecided is
  reported, never guessed). 17 ours, 12 not, 0 undecided.
- `vendor_billing_ended` — WHY a vendor stopped emailing receipts: `ended` / `annual` / `one_off`
  (no money missing) vs **`portal_only`** (money IS missing, fetch it from the vendor's portal).
  Rork ended, Figma ended, Tasjeel annual, Twilio one_off, OpenAI portal_only.
- `fn_accountant_receipt_cadence_gaps` asks the vendor-side question and the report reads its own
  `suspected_missing`, so a finding added later cannot fail to reach him.

**A trusted forwarder is not proof a charge is ours.** GoDaddy order 4161152146 was reversed out
because the vendor addressed it `To: djzaino@outlook.com` — a second GoDaddy account. The allowlist
answers "is this sender legitimate"; the recipient line answers "is this charge ours".
