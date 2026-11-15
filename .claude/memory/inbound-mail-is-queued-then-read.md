---
name: inbound-mail-is-queued-then-read
description: "15 Nov 2026: 18 receipts forwarded in 3 minutes were each read inside their own resend_inbound request (546 / 504 after 150 s; 5 of 18 recorded). Once released, resend_inbound verifies, records the delivery in public.inbound_mail_queue and answers; a reader reads one message per invocation, two at most at once, and a message that fails five times is an it.finding handoff to the seat that owns the mail."
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
- failure: read again after 1, 5, 15, 60 min; the 5th failure is `dead` and an `it.finding` handoff (agent_actions) to
  accountant / marketing / customer_support with the reason. After fixing the cause: `select public.fn_inbound_mail_requeue(<id>)`;
- pg_cron `inbound_mail_drain` runs the kick every minute as the net; done rows are deleted after 30 days.

**Where to look.** A stuck message: `select id, status, attempts, last_error, next_attempt_at from inbound_mail_queue where
status <> 'done' order by id`. A redelivery never reads twice: the queue key, then read_mail's "already on file"
(inbound_messages.provider_email_id), then the receipt key `expense_entries.source_msg_id = 'resend:<email_id>'`.
