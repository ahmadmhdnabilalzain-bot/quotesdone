---
name: sales-and-support-divide-by-surface-and-by-truth
description: "Sales decides and writes the technical truth; Support carries the message. The chat widget routes by SURFACE — homepage is Support, either portal is Sales"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-09T01:42:10.675Z
---

Founder rulings, 9 Sep 2026, when he added the Sales Engineer as the third seat and said
"dont mix things up with customer support agent. each one is doing different things."

## The principle

**Sales decides and writes the technical truth. Support carries the message and owns the
conversation.** Sales must never own the pipe it speaks through.

| | Sales Engineer | Customer Support |
|---|---|---|
| Registration, both sides | owns | — |
| Technical intake, scope, questions | decides | — |
| Document *interpretation* | owns | — |
| Supplier capability + verification record | authoritative writer | — |
| Matching, RFQ construction, dispatch | owns | — |
| Comparison report | **makes it** | notifies it is ready |
| Portal reports — jobs won, ratings, spend | **fills them** | — |
| Email / WhatsApp / chat delivery | — | **owns the pipe** |
| Conversation continuity, case ownership | — | owns |
| General FAQ, invoices, refund conversations | — | owns |
| Licence renewal | validates the new document | sends the reminder |

## The two rulings he gave when asked

**Supplier technical questions always go through Support.** Sales writes the question and validates
the answer; Support delivers it and owns the thread. One conversation identity per supplier, never
two agents mid-thread with the same person.

**The chat widget routes by SURFACE, not by topic** — his words: *"if its on the home page then the
support replies. but if its on the customer or supplier portal then its the sales engineer cause he
is much stronger technically."*

- `ChatWidget.tsx` → `site_assistant` — public homepage — **Support**. Correct today.
- `PortalShell.tsx:82` → also calls `site_assistant` — **customer portal — should be Sales.**
  This was the live mismatch found on 9 Sep.

## Decided without asking, and why

- **Reading transaction data to REPORT spend is not owning payments.** Payments stay held for the
  future accountant agent; Sales reports on them. See [[payments-are-held-for-the-accountant-agent]].
- **"Licence expired -> block matching" is Sales**, because it is a verification record. Support only
  delivers the reminder.

## Ownership after the 9 Sep move

`function_owner`: sales_engineer 20 · website 34 · customer_support 16 · ceo 1. The move's own
closing assertion refuses if payments, OTP or a channel slug ever lands on sales_engineer.

Related: [[the-org-is-two-agents-and-no-departments]] is superseded on the count — there are three
seats now. [[the-chat-widget-is-the-support-agent]] is superseded on the portal surface only: the
homepage widget is still Support's.
