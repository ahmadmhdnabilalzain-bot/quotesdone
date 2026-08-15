# Founder-reserved decisions — enforced, not documented

Eleven decisions the autonomous company may not take. They are not a policy page: they are rows in
`founder_reserved_decision`, and the `a00_org_role_no_reserved_decision` trigger on `org_role`
**refuses the write** when a role's owned decisions match one of them. The guard was forced to fire
during verification rather than assumed idle — granting the AI CEO "set the reveal fee percentage"
is rejected, not logged.

| decision_key | what it covers |
|---|---|
| `founder_commercial_rules` | Permanent changes to founder-defined commercial rules. |
| `founding_supplier_exemption` | Which suppliers are exempt as founding suppliers, and for how long. |
| `fundraising` | Raising capital, and on what terms. |
| `market_expansion` | Entering a new market or country. |
| `material_policy_change` | A material change to company policy. |
| `ownership_and_equity` | Ownership and equity in the company. |
| `reveal_fee_pct` | The reveal-fee percentage charged to a customer. |
| `spend_above_budget` | Spending above an approved budget. |
| `subscription_start_date` | The date supplier subscriptions begin to be charged. |
| `supplier_subscription_price` | The price of a supplier subscription. |
| `unapproved_legal_commitment` | Committing the company legally without approval. |

**Measured after Phase A: 0 active roles own any of them.**

Department heads may decide *how* to reach the AED 1,000,000 objective within these boundaries. They
may not redefine the boundaries. Every one of the 90 canonical roles carries the same
`founder_policy_boundary` line in the package registry, and every one carries explicit
`forbidden_decisions` in the database — a post-deployment invariant refuses to pass if any
accountable role has an empty forbidden list, because a role with no stated limits has no limits.

Phase A changed none of these eleven rows. The `reserved` fingerprint is byte-identical before and
after: `605818d3478111a03053ea8b7f5f6ef3e5e83c1446ab9bba75390f2c34f621c8`.
