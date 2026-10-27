---
name: ask-before-the-internal-test-email
description: "Never send the internal test email from management@ to supplier@quotesdone.com without the founder's explicit yes (27 Oct 2026, instruction 1314)"
metadata:
  node_type: memory
  type: feedback
  modified: 2026-10-27T06:00:00.000Z
---

The founder, 27 Oct 2026: *"I have not yet said yes to the internal test email from management@ to
supplier@. Ask me before sending it."*

**Rule:** draft it if useful, but do not send it until he says yes in this conversation or a later
one. Approval does not carry over from an earlier session, and a yes to another email is not a yes
to this one. It is day 1 of the supplier@ warm-up, so the warm-up's conversation week waits on it.

**Why:** it is mail from his own mailbox, so it is his call. It is an exception to "never ask him",
and he set it himself.

**Update, 27 Oct 2026: he said YES** (in answer to the question in the session that wrote this note).
It is still NOT sent. Nothing this session could reach sends AS management@:
- the claude.ai Microsoft 365 connector is signed in as supplier@quotesdone.com (`get_me`);
- send_outbox's M365 lane sends only from `invite_m365_mailbox` (supplier@).

Sending supplier@ → management@ instead is a different email, and his yes does not cover it. To
deliver it, either sign the Microsoft 365 connector in as management@, or he sends the one email
himself. Ledger 1314 carries the state.

Related: [[checkpoint-27-oct-cloud-invitations-held]]
