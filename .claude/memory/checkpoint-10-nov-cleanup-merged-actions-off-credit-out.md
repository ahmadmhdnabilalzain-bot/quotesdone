---
name: checkpoint-10-nov-cleanup-merged-actions-off-credit-out
description: "CHECKPOINT 10 Nov 2026 — READ FIRST: #1874 merged and live (DB 11 GB -> 3.55 GB, model off billed egress, uptime monitor); #1876 splits + gateway fix and #1877 error fixes open; GitHub Actions OFF (ledger 1564); OpenRouter OUT OF CREDIT; 15 lost PRs being ported; ledger rows 1548-1564"
metadata:
  type: project
  modified: 2026-11-10
---

**State at 01:40 UTC, 10 Nov 2026 (it_engineer session, session_01MHFn2pe3REUYi65EDVrW7G).**

LIVE on production (merged #1874 at 00:23, applied and deployed by GitHub Actions just before its budget ran out):
- kb_chunks_old dropped: pg_database_size 11 GB -> 3,550 MB. cron_history_purge_hourly active (7 days kept).
- site_uptime_5min active; armed (first 200 at 00:32).
- embed_ml loads the model from Hugging Face (Quotesdone/multilingual-e5-small-ar-en, pinned revision): 0 Storage model
  downloads after the 00:30 deploy, 39 embed_ml 200s by 00:52.
- SSL enforced, direct DB access closed (9 Nov). Founder ledger rows 1548-1564 written 10 Nov (5-9 Nov had NONE).

OPEN, in merge order (all gated locally — Actions is off):
1. #1876 `claude/sleepy-johnson-5fg2g9`: the remaining 700+-line files split (pure moves), the held-replay answer
   reserve + gateway_wall label (ai_gateway, resilience_ping), schema mirror regenerated, every workflow manual-only.
   Local gate: 13 steps PASS, otp-race PASS on mirror.gcr.io postgres; npm-test step re-running after a restart.
   After merge THIS SESSION deploys (deploy_functions.mjs --changed) — no SQL in it.
2. #1877 `it_engineer-fixes-10-nov` (stacked on #1876): brief counts problems (266 alerts -> 51 problems), four
   detectors, low-credit warning (finance_reminder, < USD 10 / < 2), workflow_audit, dropbox 200, embed_ml tick 2,
   postiz maxLength hashing, continuity grader phone fix, OTP-race mirror fallback. 5 MANIFEST files: apply with
   apply_sql at merge, then deploy dropbox_backup, embed_ml, marketing, resilience_ping.
3. `it_engineer-pr-queue-drain`: 11 of the 15 lost session PRs ported (1845 1795 1792 1784 1780 1778 1710 1703 1643
   1636 1392), 4 SQL files held as pending notes; being rebased onto #1877. Close #1864 (superseded). Founder decides
   #1649 (GlockApps self-test vs main's deliverability_test) and #1482 (CSP nonce makes pages dynamic).
4. `ceo-founder-rulings-10-nov`: one SQL file for ledger 1558-1561 (Stripe test payments resolved, bank-statement duty
   retired, demo CAD jobs closed, unsigned routine changes accepted only where md5-identical to canonical) — in progress.
5. `it_engineer-prompt-size`: wa_inbound sends ~100k prompt tokens per reply, seat calls 35-75k — trimming in progress.
6. `it_engineer-verify-funnel`: fix ef25fc98e (a phone tap is never hidden under the account assistant).

BLOCKERS / FOUNDER:
- OpenRouter balance ~USD 0 (540 topped up, 540.13 spent at 01:16). Real-AI verification owed after top-up:
  conversation_quality whatsapp_customer/supplier/widget, widget_matrix, continuity, drawing_reaches_suppliers,
  cad_identity_reaches_no_supplier, supplier_document/profile_read_walk, document_reading_qualification --real.
- GitHub Actions OFF (ledger 1564). The CAD read worker for DWGs over the edge ceiling ran on Actions: until the founder
  picks (a) the existing Claude routine "QuotesDone — CAD read worker" every 2 h, or (b) a Hugging Face Space, a big DWG
  waits for the daily-jobs routine. All drawings are demo today (ledger 1561).
- Four duplicate Claude routines (created via http_api, only the founder can switch them off): nightly journey,
  daily parity gate, multilingual embed backfill, weekly readings — the combined daily/weekly routines already run them.

LESSONS of this session: a container restart stops every agent and background run — push branches early; the ledger
must be written in the turn the founder speaks; never leave a session's PR unmerged without a checkpoint naming it.
