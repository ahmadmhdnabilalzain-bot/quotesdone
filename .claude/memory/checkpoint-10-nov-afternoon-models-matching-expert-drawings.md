---
name: checkpoint-10-nov-afternoon-models-matching-expert-drawings
description: "CHECKPOINT 10 Nov 2026 afternoon — READ FIRST: #1876-#1879 merged and live (model tiers, seats act); #1880 carries inquiry state + 100 cap, general matching (44/44 trades), expert advice in every trade, drawing reader to engineer level, the 5ec4ba8 acceptance; signup-solid and open-PR guard in flight"
metadata:
  type: project
  modified: 2026-11-10
---

**State at ~11:00 UTC, 10 Nov 2026 (session_01MHFn2pe3REUYi65EDVrW7G). Supersedes checkpoint-10-nov-cleanup-merged-actions-off-credit-out.**

LIVE on production (all applied with PROBE OK, all deployed, 0 failures):
- #1876 module splits, held-replay answer reserve, workflows manual-only (GitHub Actions OFF, ledger 1564).
- #1877 brief counts problems not alerts; low-credit warning (openrouter_low_balance_hourly, finance_reminder < USD 10 / < 2).
- #1878 the 11 lost session PRs ported; the founder's 10 Nov rulings (Stripe test payments, no bank statement, demo CAD,
  unsigned changes accepted by md5). The 12 superseded PRs were closed with a pointer to #1878.
- #1879 model tiers (simple tasks and customer chat off Sonnet, Sonnet as fallback) and seats that act.

OPEN — #1880 `sales_engineer-general-matching` (merge order: this one next):
- inquiry_state + the 100-message cap + the whole conversation (ledger 1572); general matching (supplier's own words ->
  services, licence check, alias queue, adjacency; 44/44 matrix rows, 12/12 confusables, ledger 1573/1579/1586);
  expert advice in every trade (diagnose -> advise -> qualify, 223 trades, catalogue of 30 families, ledger 1572/1586);
  drawing reader to engineer level (bench 20/65 -> 65/65; competitor quotation 0/24 prices, 0/15 identities left);
  schema mirror regenerated after #1879; the_off_main_revision_of_19_october_is_accepted_once_its_last_routine_is_verified.sql.
- AT MERGE: node scripts/ci/apply_new_manifest_lines.mjs <main-before> <merge> (4 files, in MANIFEST order), then
  NODE_USE_ENV_PROXY=1 SUPABASE_ACCESS_TOKEN=proxy-injected node scripts/kb/embed_taxonomy_services.mjs, then
  deploy_functions.mjs --changed (SUPABASE_ACCESS_TOKEN=sbp_000...0), then regenerate the mirror into the next PR.
- Proposed services stay UNTICKED: ruling 862 CONFIRMED by the founder 10 Nov (ledger 1598); the one-tap "tick all proposed" button stays.

IN FLIGHT: customer_support-signup-solid (5 commits pushed; production walks of supplier registration and customer sign-up);
it_engineer-open-pr-guard (a daily duty that flags a session PR idle > 48 h).

REAL-AI EVALS OWED (cost money; OpenRouter balance is low — top-up decides): expert advice (scripts/eval/expert_advice_eval.mjs,
~USD 1 on Luna Pro for the full bank), interview eval B (40-turn memory, 100 cap, dialects), matching with live embeddings,
drawing eval (~USD 2-3 per pass).

STANDING (10 Nov): technical decisions are the session's, as the founder's hired IT expert (ledger 1596); OpenRouter money is
tight, every paid run planned and capped (1595; ~USD 33 on 10 Nov, plan ~USD 10). #1649 and #1482 CLOSED by that delegation.
FOUNDER (a toggle only he can make, routines made via http_api): switch off trig_01BYYDz8uEKUyoiEaKuR9eyJ,
trig_01RKafcU3CoLJKtfUGJXxJS1, trig_01PvyTpFGoLyy9iLeLbyHnUo, trig_01Bxp48JvtXygiQ7M3Eq3ATK at claude.ai/code/routines/<id>.
NEXT PRs: customer_support-signup-solid (3 SQL, deploy supplier_api/supplier_portal/supplier_catalog_ingest),
sales_engineer-quote-review (1 SQL), sales_engineer-expert-knowledge-all (k1+k2+k3; then a loader so blocking/spec_guide/
brand_origins reach the DB and the interview), it_engineer-open-pr-guard (1 SQL). Regulations: 210 authority entries, ~4 high;
a verifier with Playwright is working on kb-all; www.dcd.gov.ae, www.dewa.gov.ae, pcfc.ae refuse non-UAE traffic.

KNOWN GAPS: duplicate services across trades (packaging.labels vs labels_sleeves, cartons vs corrugated_packaging);
the bare word "rental" reads as scaffolding.rental; a PDF-only architectural plan has no deterministic room take-off.
