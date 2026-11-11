---
name: the-supplier-mailbox-is-read-before-it-is-answered
description: "11 Nov 2026, ruling 1633: supplier@ is also the founder's mailbox; Azure and Microsoft support got the registration template through a second path that never read the decline. Every reply from that mailbox now needs a recorded reading that says answer, checked at enqueue AND at send."
metadata:
  type: project
  modified: 2026-11-11
---

**What happened.** email_triage declined inbound 1874 (azure-noreply@microsoft.com), 1994 and 2069 (Microsoft support).
The decline fired z53, which filed a sales_engineer `mailbox.supplier_reply` handoff. Its handler
(`fn_sales_engineer_acts_on_supplier_reply`) looked only at `replied_at` and sent a regex-picked template through
`fn_inbox_send`. That produced notifications 129468, 134514 and 138326, plus follow-ups 14, 15 and 16 due to Microsoft.

**What is in place** (PR from branch customer_support-supplier-mailbox-thinks-first):

- **The reading.** `email_triage/supplier_mailbox_reading.ts` reads every supplier-mailbox mail first. Code rules run first;
  then the model, at HIGH effort with the correspondence, gives one of 9 readings. Only `supplier_registration`,
  `supplier_account_question` and `customer` may be answered, and the model writes the answer.
- **The record.** `public.mailbox_reply_decision` holds each reading. `may_reply` is a GENERATED column.
- **The enqueue gate.** `fn_inbox_send` refuses a seat's reply without a decision that says answer.
- **The send gate.** `send_outbox` asks `fn_mailbox_reply_may_leave` before the provider call.
- **The handoff.** It never writes a reply any more.

**Why:** "a decision with no home" was the defect. The decline lived in `ai_category` text and the second path never read
it. The decision now has one row, and both gates read that row.

**How to apply:**

- Never add a path that answers supplier@ or suppliers@mail mail without `fn_mailbox_reply_decide`. A person's reply
  (`fn_inbox_send` with `p_by` null or `'founder'`) is exempt and is marked `mailbox_person_reply:`.
- To replay model decisions over production with no management token, generate SQL that sends pg_net to `ai_gateway`. Read
  the credential inside the statement, use pg_temp helpers, and run inside a rehearsal window
  (`scripts/eval/supplier_mailbox_reading/replay.ts`). Prove the SQL input mirror equals the TypeScript by md5 first.
- **Ordering.** Deploy email_triage and send_outbox BEFORE applying the SQL. Both fail closed until the SQL is applied.
