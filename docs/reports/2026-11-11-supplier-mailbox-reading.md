# The supplier mailbox is read before it is answered: 30-day replay (11 Nov 2026)

Assigned: customer_support. Founder rulings 1633 (understand an email before replying), 1630 (HIGH effort for a decision),
1631 (read the history first). Code: `supabase/functions/email_triage/supplier_mailbox_reading.ts`,
`supabase/functions/send_outbox/mailbox_reply_gate.ts`,
`scripts/sql/a_reply_from_the_supplier_mailbox_leaves_only_when_the_reading_said_answer.sql` (not applied yet; see
`scripts/sql/pending/`).

## What was wrong

email_triage declined inbound 1874 (azure-noreply@microsoft.com), 1994 and 2069 (supportmail@techsupport.microsoft.com)
with `no_auto_reply`. The decline fired trigger z53. That trigger handed every sender that was not a bounce, the founder's
own inbox or an auto-reply to sales_engineer as a `mailbox.supplier_reply` handoff. The handoff's handler,
`fn_sales_engineer_acts_on_supplier_reply`, checked only `replied_at`. When it was empty, the handler sent a regex-chosen
template through `fn_inbox_send`, and nothing in that path read the decline. That produced notifications 129468, 134514
and 138326. The template also filed follow-ups 14, 15 and 16 to Microsoft, due 16, 17 and 24 Nov.

## How it was measured

- **Scope.** Every `inbound_messages` row from the last 30 days addressed to the supplier mailbox. That means
  `invite_m365_mailbox` and `email_reply_supplier`: 26 rows, ids 653 to 2098.
- **Code rules.** The rules are the exact bodies from the SQL file. They were created in `pg_temp`, a session-only schema,
  so nothing in `public` changed.
- **Model input.** The input was built by a line-for-line SQL mirror of `readingInput`. The mirror gave the same md5 as the
  TypeScript on a hard fixture: angle brackets, Arabic, a 5,000-character body and a thread in both directions.
- **Model call.** The call went through `ai_gateway` as `email_triage`, with HIGH effort and class `internal_judgement`. The
  request body was captured from the real call path.
- **Run.** Run tag `qd_run:csread1111a`, inside a rehearsal window capped at USD 0.30 and closed afterwards.
- **What it sent.** No mail was sent. The replayed senders had 0 notifications queued in the hour of the run.
- **Generator.** `scripts/eval/supplier_mailbox_reading/replay.ts`.

## Before and after, 30 days

| inbound | sender | before | after: reading (how) | after: answered |
|---|---|---|---|---|
| 653, 654, 655, 1483 | the founder's own inboxes | not answered | founder_correspondence (code: founder_inbox) | no |
| 1484, 1828, 1868, 2079 | mailer-daemon@googlemail.com | not answered | bounce (code) | no |
| 1611-1618, 1867, 1869, 1870 (9) | MicrosoftExchange NDRs | not answered | bounce (code) | no |
| 1485 | info@algouri.com | answered (customer_support) | supplier_registration (model) | yes, by the model |
| 1829 | info@hindco.co.in | answered (customer_support) | supplier_registration (model) | yes, by the model |
| 1871 | sales@powdercoating.ae | answered (customer_support) | supplier_registration (model) | yes, by the model |
| 1872 | info@666realestate.ae "How to register our company?" | template (sales_engineer) | supplier_registration (model) | yes, by the model, not the template |
| 1873 | info@666realestate.ae "But thats so complicated" | template (sales_engineer) | supplier_registration (model) | yes, by the model, not the template |
| **1874** | **azure-noreply@microsoft.com** | **template (sales_engineer)** | **automated_notice (code: machine_sender)** | **no** |
| **1994** | **supportmail@techsupport.microsoft.com** | **template (sales_engineer)** | **vendor_our_account (model)** | **no** |
| **2069** | **supportmail@techsupport.microsoft.com** | **template, "later" (sales_engineer)** | **vendor_our_account (model)** | **no** |
| 2098 | office365reports@microsoft.com | not answered | automated_notice (code: auto_submitted) | no |

Answered automatically: **8 of 26 before** (5 by the template), **5 of 26 after**. Every answer after the change is written
by the model and based on what the sender wrote. The three Microsoft rows are now vendor or automated, never answered.

The model's reasons for the two Microsoft rows:

- 1994: "Microsoft Azure Support is notifying us about a quota increase request on our Azure account."
- 2069: "Microsoft Azure support is updating us about the quota request on our Azure account and asking how we want the
  support case handled."

## Spend

There were 7 model calls; code decided the other 19 rows.

| | |
|---|---|
| total (`ai_cost_log`, e2e_run_tag `csread1111a`) | **USD 0.004322** |
| model | openai/gpt-6-luna-pro |
| prompt tokens per call | 3,750 to 6,653 |
| output tokens per call | 337 to 748 |

## Not measured

- **The model-written answers.** This run read the mails and did not write answers to them. The answer path is unchanged
  and is covered by `email_triage/supplier_mailbox_reading.test.ts` against a stub model.
- **Whether info@666realestate.ae is the founder.** It is not in `fn_is_founder_own_inbox` (ahmad@666realestate.ae is), so
  code does not treat it as his. The model read both of its mails as a supplier asking to register.

## Recommended clean-up of the three replies already sent to Microsoft (nothing to send)

- The replies cannot be unsent. Inbound 2098 is the Outlook recall report for the third reply (138326), so the founder
  already tried a recall. No further mail to Microsoft is advised: an apology to a no-reply address or a support queue adds
  noise.
- **When the SQL is applied**, the file drops the due follow-ups whose answer the reading did not allow (12, 13, 14, 15, 16
  on 11 Nov), using the same rule the follow-up duty now applies. Until then, the follow-ups to azure-noreply@microsoft.com
  (16 Nov), supportmail@techsupport.microsoft.com (17 and 24 Nov) and info@666realestate.ae (15/16 Nov) are still due.
  Follow-up 15 is also dropped by the existing "wrote again" rule.
- **Optional, the founder's call.** Mark inbound 1874, 1994 and 2069 (and 2098) as read in the Outlook mailbox. Nothing in
  the database needs to change for them: once applied, the reading decides any new mail of this kind.
