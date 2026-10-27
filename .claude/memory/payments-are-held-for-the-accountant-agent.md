---
name: payments-are-held-for-the-accountant-agent
description: "9 Sep 2026 — surfaces are HELD for future agents rather than deleted; payments go to an accountant, OTP/auth to another agent"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-09T02:07:41.841Z
---

Founder, 9 September 2026, while stripping every edge function that is not one of the two live
agents:

> **"fine leave payments stuff so we link them later to the new accountant"**
> **"otp will go to another agent also later"**
> **"website health and all technical stuff with go to the IT agent later"** (9 Sep)

**The seats reserved so far, and what each holds:**

| future seat | surfaces held for it |
|---|---|
| accountant | `stripe_*`, `supplier_pay`, `refunds_api`, `refund_flow`, `reveal_invoice`, `quote_pdf`, and ALL credit/balance/budget work |
| OTP / auth seat | `auth_api`, `login_otp`, `mobile_otp`, `voice_otp`, `voice_otp_capture`, `sup_dob`, `send_sms` |
| **IT** | website health, monitoring and infrastructure — `resilience_ping`, `role_guard`, `public_stats`, `edge_health_probe`, cron/scheduler health, the `health_ping` task class |

None of these were assigned to `sales_engineer` in the 9 Sep ownership move — verified against
`function_owner` at the time, and its closing assertion refuses if payments, OTP or a channel slug
ever lands on Sales. Add IT's surfaces to that assertion when the seat exists.

**This is a rule, not two exceptions.** He is not deleting the estate down to two agents — he is
assigning each surface to the seat that will own it, and deleting only what belongs to no seat at
all. Ask "which agent will own this?" before proposing any deletion. "Nobody owns it today" is not
the same answer as "nobody will own it".

## MONEY IS THE ACCOUNTANT'S — including model spend. Do not raise it.

Extended 9 Sep 2026 after I asked him for a monthly AED ceiling so the existing budget halt could
fire:

> **"i dont wanna discuss credits and balance programming now cause all those will go the accountant
> agent which we will add later"**

So do NOT build, propose or ask about: `department_budget` population, spend ceilings, the
degrade-at-70%/halt-at-95% logic, OpenRouter credit top-ups, the key's spend limit, or
`openrouter_min_usd`. All of it waits for the accountant seat. Report a measured fact if it blocks
work — "the routes are held and only you can release them" is a blocker, not a budget discussion —
but do not turn it into a design conversation.

**What is NOT accounting, and should still be done:** using code instead of a model where code
suffices. His words, same day: *"for the tasks that don't require llm they should be in the code to
reduce cost."* That is architecture. The estate already proves the pattern — `site_assistant` runs a
level-0 ladder (template → keyword FAQ → free semantic retrieval at a 0.86 floor → only then a
paid model), and 4 of the 11 calls in the retained `ai_cost_log` window were answered with **no
model at all**. Generalise that ladder; do not price it.

**Held so far:**

| Surface | Future owner | Functions |
|---|---|---|
| Payments | the accountant agent | `stripe_checkout`, `stripe_confirm`, `stripe_webhook`, `stripe_setup`, `stripe_setup_page`, `supplier_pay`, `refunds_api`, `refund_flow`, `reveal_invoice` |
| OTP / identity | an agent not yet named | `login_otp`, `mobile_otp`, `voice_otp`, `voice_otp_capture`, `auth_api`, `role_guard` |

**Already owned:** `ceo` (1 function), `customer_support` (15) — see
[[the-ceo-seat-has-tools-but-no-runtime]] and [[the-chat-widget-is-the-support-agent]]. The signed-in
customer/supplier assistant is a further seat he named first and it does not exist yet.

**Why this matters beyond bookkeeping:** `stripe_webhook` is an endpoint Stripe calls directly, and
the Twilio voice/SMS and Resend inbound webhooks are the same shape. No grep of this repository will
ever show a caller for them. A function that looks uncalled and is actually reached by an external
service is the most dangerous kind to delete — see [[a-mention-is-not-a-reference]]. The same is true
of `supplier_ack` and `unsubscribe`, which are reached only by links built into emails the product
sends.

Refund AUTHORITY is already the CEO's and does not move to the accountant — see
[[refunds-belong-to-the-ceo]]. The accountant would own the money PLUMBING: reconciliation, payouts,
invoices, the books. Deciding a refund and executing one are different jobs.
