---
name: revenue-loop-mechanics-proven-blocker-is-data
description: "the marketplace's revenue mechanics (inquiry entry, supplier matching, 3% fee) are proven correct by execution 3 Sep 2026; the blocker to a live loop is registered-supplier DATA, not logic — includes the exact demo-seeding recipe"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-03T06:15:10.043Z
---

Proven by aborted-transaction probes, 3 Sep 2026 (all rolled back, no data left):

1. **Entry**: an inquiry INSERT emits `rfq.created`; fn_workflow_start_due starts the rfq_handling
   run. (After fixing [[revenue-loop-entry-was-a-vocabulary-mismatch]].)
2. **Matching**: `fn_match_capability(array['electrical'],'executes',...)` returned 4 of 4 seeded
   ZZ-DEMO confirmed suppliers — ≥3, enough for the T&C best-3 comparison. So
   [[one-confirmed-supplier-gates-every-rfq]] is a DATA gap (no confirmed suppliers registered
   yet), NOT a matching-logic defect. The logic is correct.
3. **Fee**: pricing_config id=1 has standard_reveal_rate=0.03 (3%), cap=99,999,999 (a sentinel that
   only binds above a ~AED 3.3bn quote — effectively no cap, as the T&C requires), no promo.
   stripe_checkout.revealFee = min(round(quote*rate,2), cap). Correct 3%, T&C-compliant.

THE DEMO-SEEDING RECIPE (fn_match_capability gates, all must pass — this is how to seed a working
sandbox supplier for the safe rehearsal the founder wants, [[safe-marketplace-demo-rehearsal]]):
- `leads`: id is GENERATED ALWAYS (use RETURNING). Matchable via fn_is_matchable needs
  verified=true, banned=false, matching_blocked=false, approval_status='approved',
  permanently_closed=false, chat_strikes=0. claim_token is uuid. Use ZZ DEMO name + @example.invalid.
- `supplier_capabilities`: confirmed_at IS NOT NULL; trades ∩ requested (real taxonomy_trade code,
  e.g. 'electrical'); excluded_trades disjoint; `roles` must hold a real taxonomy_role CODE whose
  executes/supplies/whole_scope flag matches p_need — NOT the literal 'executes' (valid executing
  roles: contractor, installer, maintenance, turnkey_fitout); authority_approvals is a jsonb OBJECT
  KEYED by each code in taxonomy_trade.authority_required (electrical needs key 'electrical_utility');
  coverage_emirates contains the asked emirate; min/max_project_value brackets the value.

Remaining to a full live loop: registered suppliers + customers (DATA — the funnel, downstream of
the backend), and the actual Stripe reveal (needs test-mode checkout completion). The LOGIC of the
money loop is verified. rfq_handling's 18 steps bind to real edge executors (match, quote_compare,
route_inquiry, inquiry_ai) per [[revenue-loop-entry-was-a-vocabulary-mismatch]].

**UPDATE 3 Sep 2026 — PROVEN END-TO-END ON COMMITTED DATA.** `QD_FIXTURES=1 node
scripts/staging/rehearse_revenue_loop.mjs` (built on demo_factory's withRun teardown) passed 10/10 on
production: 4 confirmed suppliers → customer → inquiry (emits rfq.created; rfq_handling waits on it) →
fn_match_capability 4/4 → 4 quotes → quote_compare 200 ok, engine=deterministic (model held), best 3 of
4 with a stated #1 reason → reveal fee 3,540 on 118,000 (3%, live pricing_config rate). Everything torn
down; only 3 log rows drift (company_event customer.registered/test.failed, 1 doc_versions — a
demo_factory teardown scoping gap). quote_compare's internal caller credential is `cred_fn_cos_execute`
(internal_credential id 53, context fn.cos_execute, scoped to the marketplace executor set). This is the
"sandbox-perfect" proof: the money loop runs on real code, no model, leaves nothing behind.

**UPDATE 3 Sep 2026 (later) — THE WHOLE FUNNEL, 18/18.** `QD_FIXTURES=1 node
scripts/staging/rehearse_full_funnel.mjs` on production, inside a declared rehearsal window: invited
lead → claim_lookup by token → supplier_api claim with a real account → profile + terms → approval
happens on the licence-facts TRIGGER path (action_required after terms; approved the moment licence
facts land — fn_supplier_autoapprove_clean is a sweep for the same criteria) → capability confirmed →
matchable → inquiry (rfq.created) → matching includes the claimed supplier → 3 quotes → deterministic
compare → stripe_checkout creates the REAL Checkout session for the 3% fee (AED 3,540 on 118,000),
expired at once via Stripe → a checkout.session.completed event signed with
app_secrets.stripe_webhook_secret_test (harness-only value the script creates if absent) → transaction
paid, quote+inquiry revealed, reveal_receipt to the customer and quote_accepted to the supplier (2
emails) → customer_api reveal returns the contact → teardown clean, kernel orphan board ok. Simulated:
licence OCR outputs (held model surface), the card payment, the intake conversation. What remains for
a live loop is therefore only the founder's inputs: Meta token, Stripe test/live mode, real suppliers.
