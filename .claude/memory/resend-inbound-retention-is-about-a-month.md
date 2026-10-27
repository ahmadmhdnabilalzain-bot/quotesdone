---
name: resend-inbound-retention-is-about-a-month
description: "Resend's inbound API keeps only ~1 month; the founder's Gmail sent folder is the durable record of forwarded receipts"
metadata: 
  node_type: memory
  type: reference
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-09T04:46:52.052Z
---

9 Sep 2026. `GET https://api.resend.com/emails/inbound?limit=100` returned **9 messages**, oldest
12 Aug, `has_more:false` in BOTH directions (asc and default). The founder said he had been
forwarding receipts to `expenses@mail.quotesdone.com` since **29 June**.

Measured in his Gmail: `in:sent to:expenses@mail.quotesdone.com` returns **36 threads**, 29 Jun →
3 Sep, every one addressed correctly. So nothing was misaddressed and nothing he did was wrong —
**Resend's inbound retention is roughly one month** and the older messages aged out of the provider
before anything existed to read them.

**Do not read an absent provider record as an absent event.** I first repeated an agent's claim that
"the receiving route for expenses@ does not exist" — wrong: the `email.received` webhook is enabled
and pointed at `resend_inbound`, and 4 messages did arrive. The real split was that the 5 missing
ones carried **no attachment** (the amount is in the email body); the current handler reads bodies.

**Durable sources, in order:** `public.inbound_messages` (captured on arrival, ours forever) →
the founder's Gmail sent folder (survives Resend) → Resend's inbound API (~1 month only).

Also: `quotesdone.com` has **receiving DISABLED**; only `mail.quotesdone.com` can receive. An
address at the bare domain silently accepts nothing.

Related: [[expenses-email-source-of-truth]], [[never-state-what-you-have-not-measured]],
[[zero-cannot-tell-a-dead-guard-from-an-idle-system]].
