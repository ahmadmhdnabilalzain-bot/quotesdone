---
name: a-status-column-is-not-a-delivery-record
description: "Verify sends through the outbox, never through a status column on the subject row — 171 leads read \"invited\" when nothing was ever emailed"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-09T00:54:14.410Z
---

9 Sep 2026. I reported "171 leads invited, 161 sent, 0 registered, 5.8% bounce rate" from
`leads.invited_at` / `leads.invite_status`. The founder corrected it:

> "not a single lead was invited. it was a test. **always verify through the outbox** and stop
> doing such mistakes"

He was right. Measured at the send path instead:

```
notifications total          2      (both type='founder_alert')
invitation notifications     0      — ever
notifications ever sent      1
send_outbox agent_runs      51      — has run 51 times, never sent an invitation
leads with invited_at       171     — test data written straight to the column
```

**Why:** `leads.invite_status` is written by the planner *before* anything is queued, and by
fixtures. Delivery is `notifications` → `send_outbox` → Resend. The two are not the same fact and
nothing reconciles them, so a status column can say "sent" for a message that was never queued.

**How to apply:** for anything that claims an outbound effect — email, WhatsApp, SMS, webhook —
measure at the QUEUE and the SENDER, not on the subject row. `notifications` (with `status`,
`attempts`), `agent_runs` for the drainer, and the provider's own event rows are the evidence.
A count on the recipient's row is an intention, not a delivery.

This is the same shape as [[connected-is-a-claim-not-a-measurement]] and
[[zero-cannot-tell-a-dead-guard-from-an-idle-system]]: a derived rate off a fabricated denominator
("0 of 161 registered") reads as a business finding when the true statement is "nothing was sent,
so there is no rate". See also [[never-state-what-you-have-not-measured]].

**2 Nov 2026, the M365 lane.** Graph's sendMail answers 202 with no id, so all 52 M365 invitations read provider_status NULL.
Now resilience_ping reads each one back from supplier@'s Sent Items by internetMessageId and writes 'sent' (Exchange sent it;
never 'delivered', which Graph cannot see). A delivery report that quotes a send's exact Message-ID writes 'undelivered'
'bounce:<code>' (`fn_mail_bounce_marks_its_send`), and only by In-Reply-To, from an authenticated sender or our own
tenant's Exchange on its own stamp (raw.exchange_internal), with a standalone 5.x.x code. The Message-ID alone is no proof:
the recipient knows it (review of #1792). Whether Graph shows the AuthAs header on an NDR is unmeasured.
