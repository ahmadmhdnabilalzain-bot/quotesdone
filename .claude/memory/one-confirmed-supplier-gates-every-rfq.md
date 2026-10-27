---
name: one-confirmed-supplier-gates-every-rfq
description: "15,306 suppliers carry capability data and exactly 1 has confirmed scope, so the structured matcher can shortlist at most one supplier — the blocker is confirmations, not supplier count."
metadata: 
  node_type: memory
  type: project
  originSessionId: 66a952a6-eec2-4b4b-9915-b04839a8d384
  modified: 2026-08-13T11:07:22.031Z
---

Measured on production 13 Aug 2026: `supplier_capabilities` holds **15,306 rows, every one
carrying trades** (1,275 on `flooring` alone), and exactly **1** has `confirmed_at` set —
MERIDIAN MEP CONTRACTING LLC (hvac, electrical, plumbing, mep_general).

`fn_match_capability` gates on `sc.confirmed_at is not null`, so **the structured matcher can
return at most one supplier for any query in today's database**. `route_inquiry` takes that path
whenever a capability requirement row exists, and on zero candidates it deliberately does NOT fall
back to keyword retrieval — it logs "a real coverage gap" and contacts nobody. That refusal is
intentional and reasoned in the code; do not "fix" it by widening the gate.

**Why this matters:** "No registered supplier matches that" reads as *buy more suppliers* — the
most expensive possible response, and the one that would restart Apify. The actual blocker is
**confirmations**, which is a different and much cheaper job. See [[apify-paused-until-2027]].

The customer-facing empty state now names the real reason (PR #317), so discovery says
"1275 suppliers list this trade, but matching only shortlists suppliers who have confirmed their
own scope — one has done so."

**Now on his screen** (PR #324): `fn_os_health` returns `supplier_reach` — leads 20,471 /
with_capability 15,306 / confirmed 1 / **matchable_now 1** — rendered at the top of Operations on
System Health, above the cron board, because when it is 1 nothing below it matters.
`fn_founder_brief` still does not mention it; the daily e-mail is a separate surface.
