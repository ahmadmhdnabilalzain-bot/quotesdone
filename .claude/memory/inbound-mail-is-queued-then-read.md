---
name: inbound-mail-is-queued-then-read
description: "15 Nov 2026: 18 receipts forwarded in 3 minutes were each read inside their own resend_inbound request (546 / 504 after 150 s; 5 of 18 recorded). Once released, resend_inbound verifies, records the delivery in public.inbound_mail_queue and answers; a reader reads one message per invocation, two at most at once, and a message that fails five times is an IT finding (inbound_mail_queue:<id>) whose it.finding handoff goes to the seat that owns the mail."
metadata:
  type: lesson
  modified: 2026-11-15
---

**What happened (it_engineer, 15 Nov 2026 18:40-18:54 UTC).** The founder forwarded 18 receipts to expenses@ in about three
minutes. resend_inbound read each one inside its webhook request (Resend read, attachments, PDF and vision reads, booking): most
answered 546 WORKER_RESOURCE_LIMIT, others 504 after 150 s, successes took 30-142 s; 5 reached inbound_messages, 4 were booked,
and Resend's retries trickled in over the next hour. The same function receives supplier quotations and replies.

**How it works once released** (branch it_engineer-an-inbound-burst-is-accepted-at-once-and-read-in-turn;
`scripts/sql/an_inbound_burst_is_accepted_at_once_and_read_in_turn.sql`, `supabase/functions/resend_inbound/lib/queue.ts`):
- the webhook verifies the ?s token and the Svix signature, records the body in `inbound_mail_queue` (unique on the provider id:
  Resend's email_id, `m365:<id>`, else `svix:<svix-id>`), answers 200 `{queued}` or `{duplicate}`, then starts a reader;
- a reader claims ONE message (`fn_inbound_mail_claim`: advisory lock, at most `fn_inbound_mail_readers()` = 2 reading,
  per-sender thread order outside the finance mailboxes), reads it with `pipeline.ts` (the old steps, unchanged), renews a
  150 s lease every 30 s, records the verdict (`fn_inbound_mail_finish`) and calls `fn_inbound_mail_kick` to start the next.
  One per invocation because the edge caps CPU per invocation (see the 27 Oct runner-died lesson);
- failure: read again after 1, 5, 15, 60 min, each stretched by up to half again at random (`fn_inbound_mail_retry_at`: readers
  killed together must not come back together); the 5th failure is `dead` and an IT FINDING `inbound_mail_queue:<id>`
  (`fn_it_engineer_finding_upsert`, owner_seat accountant / marketing / customer_support in its evidence) with its `it.finding`
  handoff (`fn_it_loop_open`). The title names our mailbox, the sender's domain, the subject (80 chars) and when it came.
  **A handoff with no finding behind it is closed by the IT loop within minutes** (`fn_it_loop_reverify`: "the finding is no
  longer open"; review of 15 Nov, confirmed LOCAL), so anything handed to a seat as `it.finding` must go through a finding.
  After fixing the cause: `select public.fn_inbound_mail_requeue(<id>)` — it closes the finding and clears handoff_id and
  last_error; a successful read closes it too; a second death reopens it as a new occurrence with a new handoff;
- one message is handed once across Microsoft 365 mailboxes: the queue keeps the RFC `message_id`, and the M365 readers'
  lookups (`_shared/m365_reply_inbox.ts inboundOnFile`) read inbound_messages AND inbound_mail_queue;
- `read_mail.ts` answers "already on file" BEFORE the Resend read, so a re-read after a crash never fails on Resend;
- pg_cron `inbound_mail_drain` runs the kick every minute as the net; done rows are deleted after 30 days.

**Replaying lost receipts.** Never run `expense_sweep` over pages, even as a dry run: it downloads every unbooked message's
attachments and runs pdf_text, vision and the model for each inside one invocation (the 546 pattern, and paid). List Resend's
inbound mail with one `net.http_get`, find the missing ids by joining on `expense_entries.source_msg_id = 'resend:'||id`,
`inbound_messages.provider_email_id` and `inbound_mail_queue.provider_email_id`, filter times with `::timestamptz` (Resend writes
a space, not a T), then dry-run and book ONE email_id at a time.

**Where to look.** A stuck message: `select id, status, attempts, last_error, next_attempt_at from inbound_mail_queue where
status <> 'done' order by id`. A redelivery never reads twice: the queue key, then read_mail's "already on file"
(inbound_messages.provider_email_id), then the receipt key `expense_entries.source_msg_id = 'resend:<email_id>'`.
