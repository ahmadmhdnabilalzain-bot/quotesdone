---
name: receipts-fell-into-the-founders-queue-under-the-hold
description: From 15 Aug to 6 Sep 2026 zero expenses were booked because resend_inbound booked a forwarded receipt only after a paid model extraction; under the hold every receipt fell to the generic attachment path and landed in the founder's inbox and document-review queue. Fixed by a deterministic parser first and a bookkeeper task for anything unparsed (PR #522).
metadata:
  type: project
---

Walked in the founder's browser (Claude in Chrome, his session) on 6 Sep: Escalations "Inbox —
awaiting your reply 3" and Documents "Reviews pending 7" were all his own forwarded SaaS receipts.
Measured: expense_entries since 15 Aug = 0; inbound 67/73/74/75 needs_review; doc_reviews 8-12
pending with ai_summary "skipped_due_to_zero_cost_mode". The allow-list was fine; the model was the
only parser. Now: _shared/receipt_parse.ts (vendor from the original sender domain, amount/date/
period from text) runs before any model; fn_receipt_hand_to_bookkeeper opens ONE finance task;
inbound_messages/doc_reviews carry owner_role and the founder lists exclude owned rows.

**Why:** a deterministic company must not have a money path whose only parser is a paid model —
the hold turned "book the expense" into "ask the founder" without any error.

**How to apply:** when a queue shows the founder his own inputs, look for a held model call on the
path; also, when browser-walking the OS, Vercel production lags a merge by a few minutes — check
list_deployments before judging a screen. See [[expenses-email-source-of-truth]] and
[[the-surfaces-counted-raw-status-as-his-approvals]].
