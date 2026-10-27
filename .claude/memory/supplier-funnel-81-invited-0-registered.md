---
name: supplier-funnel-81-invited-0-registered
description: "The supplier confirmation funnel measured on 13 Aug 2026 — 81 invited, 0 registered, 1 claimed (a probe), 1 confirmed."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8c3f363e-c107-4cc8-a2b7-67b6692cd25a
  modified: 2026-08-13T12:24:00.738Z
---

Measured on production 13 Aug 2026:

- 20,471 leads · all have a `claim_token` · **81 invited** (`invited_at not null`)
- `v_invite_funnel` shows **registered = 0 for every trade**
- 7 leads `claimed` — 6 are ZZ DEMO fixtures, 1 is MERIDIAN MEP (`source='qd_live_path_probe'`,
  never invited)
- 15,306 `supplier_capabilities` rows · **1 confirmed** (MERIDIAN, 2026-08-12 11:45:35.128+00)

So the funnel is not "suppliers won't confirm" — **nobody gets to the portal at all**. The invite
email itself is good (no commission, free until 31 Jul 2027, first 1,000 never pay). What it linked
to was a generic marketing hero with a sign-in box headed "Welcome back", to someone who by
definition has no account. `claim_lookup` — public by design, token-only, resolves the company name
— had no caller in `src/`. Fixed in PR #328.

**Why:** the brief framed this as a confirmation problem. The confirmation *screen* works: MERIDIAN
registered at 11:41:08 and confirmed at 11:45:35, four and a half minutes. The gap is upstream of
it.

**How to apply:** when a conversion number is 1, measure every stage before blaming the last one.
Related: [[one-confirmed-supplier-gates-every-rfq]], [[finished-capability-with-no-entry-point]]
(this was instance six), [[filter-values-written-by-a-path-that-never-ran]].
