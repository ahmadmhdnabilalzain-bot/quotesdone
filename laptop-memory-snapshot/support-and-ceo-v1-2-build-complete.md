---
name: support-and-ceo-v1-2-build-complete
description: "The v1.2 Full Autonomy build for the CEO and customer support seats, and exactly where its evidence lives"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-07T20:53:48.571Z
---

Built 7-8 September 2026 on branch `integration-2026-09-07-certifications`, PR #526.

**The evidence, not the claim.** Three things to run rather than re-derive:

- `node scripts/checks/support_acceptance_scenarios.mjs` — 112 named scenarios in eleven
  groups against the live functions, inside transactions that end in a RAISE. 81 marked
  critical (privacy, authority, payment, identity); a critical failure blocks release
  regardless of the average, and a group that fails to RUN counts as a failure of every
  scenario in it. Groups 8-11 live in their own modules because their SQL is dollar-quoted
  and shell-generated files mangle `$p$` — see [[a-hook-rewrites-shell-redirect-targets]].
- `node scripts/checks/support_delivery_report.mjs --write` — regenerates
  `docs/SUPPORT_AGENT_DELIVERY_v1_2.md` from the live database. Never edit that file by hand;
  it is a generator precisely so it cannot decay into the last hand-written status.
- `node scripts/kb/support_knowledge_retrieval_eval.mjs --scenarios <pack>/evaluation/scenarios.jsonl`
  — coverage and leakage, not precision. The support scenarios ship no `related_modules`, so
  there is no ground truth for precision and it is deliberately unmeasured.

**Two limitations that are real and disclosed, not defects to re-chase:**

- `meta_access_token` has NO ROW in app_secrets (absent, not empty).
- `twilio_auth_token` is absent, so `wa_inbound` cannot run its HMAC signature check and falls
  back to a REST provenance lookup of the MessageSid. That is a real check a forger cannot
  pass, but it is a lookup, not a proof. Supplying the token upgrades it with no code change.
  Note the API key secret is a DIFFERENT credential and cannot compute that HMAC.

**The reconfirmation route is gone.** `interpreting → clarification_required` was deleted from
`phase_c_command_transition`, so an authenticated instruction can no longer be parked waiting
for the founder. Do not re-add it; refusal (terminal, waits on nobody) is the route that stays.

Related: [[phase-freezes-removed-totally]], [[the-org-is-ten-departments-now]] is superseded —
there are two seats now, `ceo` and `customer_support`, with one reporting edge.
