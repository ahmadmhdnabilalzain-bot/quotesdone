---
name: safe-marketplace-demo-rehearsal
description: "How to rehearse the marketplace funnel with demo customers/suppliers safely — aborted-tx over persistent, and the exact side-effect neutralizations."
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-01T09:59:42.724Z
---

1 Sep 2026: the founder asked to create 10 demo customers + 20 demo suppliers to build/confirm the
customer-dependent flows, then delete them and clear the log. **Do it as an aborted-transaction probe,
NOT persistent demos** — persistent demos leave `decision_log` rows that are IMMUTABLE (declog_immutable),
and an ACTIVE 1-min consumer (`phase_c_outbox_deliver_1min` job 278) keeps writing kernel residue from
demo emits; a rollback leaves literally zero, which is what "clear the log so I don't mistake it for real
data" actually needs. The whole funnel is DB-drivable in one tx (no Stripe, no edge functions, no crons —
they're stood down anyway).

The funnel that confirms the flow, all inside `BEGIN … RAISE`(rollback): insert customers → leads(+
supplier_capabilities) → inquiries → quotes → transactions → reviews, then `perform fn_company_indices()`
and `perform fn_graph_rebuild()` and assert. Proven: s30 went 8/8 (sat/rev/retention populate), and
`graph_nodes` gained customer/quote/revenue/rfq kinds — so s22-graph-navigation and company-map-entities
are OTHER_HOLD (no real trade) not broken code. Zero residue after rollback.

**Side-effect neutralizations (mandatory even in an aborted tx — a synchronous net.http_post escapes the
rollback):** demo email `@example.invalid` + name `ZZ DEMO`; **phone NULL on every row** (the kill-switch
`zzz_notifications_demo_guard` / `decision_policy.demo_rehearsal_active` keys ONLY on to_email, so a real
to_phone slips past it); `leads.source='demo_factory'` (skips category provisioning) + `capability_enriched_at
=now()` (skips `trg_enrich_capability` HTTP) + all `*_doc_path` NULL (skips doc registration);
`inquiries.routing.dispatched_at=now()` (makes `trg_autodispatch_inquiry` skip its dispatch_inquiry HTTP —
the ONLY business-row trigger that calls out). `fn_company_indices`/`fn_graph_rebuild` are both HTTP-free.
NEVER select `transactions.created_at` (no such column — use `revealed_at`); never drive
`refund_status='requested'` (emails real management@). A proven tool exists for a persistent run if ever
needed: `scripts/staging/demo_factory.mjs` with `QD_FIXTURES=1` + a fixed `--tag` (create and `--purge` on
one path) — but mgmtFixture writes DIRECTLY to prod now that staging is gone, so aborted-tx is safer.
See [[demo-fixture-convention]], [[least-ignores-nulls-in-postgres]].
