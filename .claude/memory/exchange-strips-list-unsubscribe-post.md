---
name: exchange-strips-list-unsubscribe-post
description: "27 Oct 2026: mail sent through the M365 lane (supplier@) arrives with List-Unsubscribe (https + mailto) but WITHOUT List-Unsubscribe-Post; Exchange strips it. The fix is an Exchange transport rule, not code."
metadata:
  type: project
  modified: 2026-10-27
---

Measured on 27 Oct 2026: test notification 112440 was sent from the M365 lane (`send_outbox/m365_lane.ts`) to Gmail.
It landed in Primary with no winmail.dat (TNEF had been fixed earlier that day: Remote domains → Default →
rich text Never). `List-Unsubscribe` carried the https link and `mailto:unsubscribe@mail.quotesdone.com`, but
`List-Unsubscribe-Post: List-Unsubscribe=One-Click` was missing, although the MIME we build includes it.

**Why:** Exchange Online rebuilds the header set on submission and drops List-Unsubscribe-Post. Gmail/Yahoo
bulk-sender rules expect one-click unsubscribe, so this costs deliverability before invitations resume.

**How to apply:** do not chase this in code. The founder sets it in Exchange admin → Mail flow → Rules: if the sender is
supplier@quotesdone.com, set the message header `List-Unsubscribe-Post` to `List-Unsubscribe=One-Click`. Re-measure
it with a seed send. Until that is done the opt-out is the "reply stop" line plus List-Unsubscribe.
