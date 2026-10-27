---
name: ad-spend-autopilot-built
description: the autonomous Meta ad spend manager EXISTS since 3 Sep 2026 (fn_ads_manage + DB ceiling guard + ad_decision ledger + meta_ads execute_decisions + daily cron 316); the only switch left is app_secrets.meta_access_token which only the founder can mint; sandbox proof is rehearse_ad_spend.mjs 19/19
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-03T05:32:41.617Z
---

Built 3 Sep 2026 on branch deterministic-engine-2026-09-03: the one genuine build the master audit listed
as missing — autonomous ad SPEND within the founder-funded balance ([[the-capable-machine-target]]).

- `scripts/sql/ad_spend_autopilot.sql`: `ad_spend_policy` (daily_cap 200, target_cpl 150, kill 3x,
  learning 3 days / 100 AED, step 20%, per-campaign 20..100, auto_activate, optional monthly_cap +
  month_spent), `ad_campaign_state` (is_demo splits two disjoint worlds), `ad_decision` ledger with
  BEFORE INSERT `a00_ad_spend_ceiling_guard` (refuses any INCREASE over `fn_ad_spend_daily_ceiling()`;
  pauses and reductions always pass), `fn_ads_manage(p_demo)` rules in order pace_down/pace_pause →
  tracking_gate → kill_3x → (learning hold) → scale_winner → activate. Truncate-guarded (enforcing table).
- `meta_ads` action `execute_decisions`: live via Graph when meta_access_token + meta_ad_account_id exist,
  otherwise SANDBOX (ledger + state updated exactly as a live call would). Credentials scoped to CALL
  meta_ads: fn.agent_act (id 32) and cron.ads_autopilot (id 108, `app_secrets.cred_cron_ads_autopilot`).
  `cred_fn_cos_execute` is NOT scoped to meta_ads; `cred_fn_enrich_capability` is enrich_capability's
  OUTBOUND credential (scope ai_gateway only) — presenting it to the callee is refused out_of_scope.
- cron `ads_autopilot_daily` = job 316 (04:20 UTC): `fn_ads_autopilot_tick()` → manage(false), then HTTP
  only if decisions are pending. Kernel-wrapped; component `cron:ads_autopilot_daily`
  (marketing_director / growth); Phase D registered. `meta_sync_daily` (job 72) re-enabled; with the token
  it mirrors campaigns, ad-set daily budgets and this_month spend into the autopilot tables.
- Proof: `QD_FIXTURES=1 node scripts/staging/rehearse_ad_spend.mjs` → 19/19 on production, token absent.

**Why:** the founder's model is "I fund the Meta balance; the machine spends it" — the top of the funnel
was the last link that needed him per boost. He also said nothing needs real data: sandbox-perfect first.

**How to apply:** do not rebuild this; the remaining input is HIS token (a credential only he can mint —
say so in the hand-over, never ask him a technical question about it). Never pace ads against
`department_budget('growth')` — that is the department's model-spend operating budget, a different pool.
Any new spender must write `ad_decision`, never call Graph directly. Postgres greatest()/least() ignore
NULLs — the first ceiling cut paced everything to zero ([[least-ignores-nulls-in-postgres]]). The
kernel wrap resets a previously declared component's authority_class to its default — restore the
committed crosswalk value in the same file ([[wrapping-a-cron-needs-a-role-that-resolves]]).
