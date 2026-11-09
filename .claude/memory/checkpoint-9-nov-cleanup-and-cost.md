---
name: checkpoint-9-nov-cleanup-and-cost
description: "CHECKPOINT 9 Nov 2026 — the founder's code cleanup (container, linter, god files split, rebuildable DB, launch checklist) and the Supabase cost forensics. PR #1874 (draft). Read before the founder's next task list."
metadata:
  type: project
  modified: 2026-11-09
---

Founder, 9 Nov 2026: the code is "vibe coded"; clean it up to proper engineering standards (modules, a
container, easy troubleshooting) and check his 105-item launch checklist; then he gives the next task list.
Then: a Supabase email (DB 1 → 11.3 GB, 1,291 MAU, egress past 1 TB on 19 and 27 Oct) — "find the glitch".

**PR #1874 (draft, branch claude/sleepy-johnson-5fg2g9).** Everything below is on it; measured details in each
commit message.
- Container: Dockerfile, docker-compose.yml (app / checks / shell / db), .devcontainer, docs/runbooks/docker.md;
  `npm run gate -- --offline`. In Docker: 13/14 gate steps PASS incl. the OTP race on the compose Postgres; the
  npm-test step was being re-run in the container to read its one failure (see below).
- `npm run db:local` rebuilds the whole public schema from the mirror and measures it (784/784 tables …).
- Five god files split as pure moves (customer_api, supplier_api, resilience_ping, CustomerPortal,
  SupplierPortal); checks read code through scripts/lib/function_sources.mjs and portal_sources.mjs.
- oxlint (`npm run lint`), 0 errors; dead UI files, 9 unused packages, 39 one-shot scripts archived.
- Launch items: error.tsx/global-error.tsx, /api/health, runbooks, docs/engineering/tech-debt.md (TD-01..17),
  docs/reports/2026-11-09-launch-checklist.md (95 apply: 47 present, 42 partial, 6 missing).
- Security: H1 (verified supplier mobile) fixed; Stripe return URLs pinned; inbound_email constant-time compare.
- DB clean-up (founder approved): drop public.kb_chunks_old (8.1 GB of the 11 GB) + hourly purge of
  cron.job_run_details keeping 7 days (698,600 rows). Applies AT MERGE (MANIFEST line). Until then
  canonical_routine_manifest shows exactly 1 finding: fn_cron_history_purge not on production (expected).

**The cost cause, measured on production (logs API, 9 Nov).** Every cold embed_ml worker downloads the 47.6 MB
model from the public `ml-models` bucket = billed cached egress. Model downloads at the CDN edge, 2-9 Nov:
2,565 / 1,752 / 370 / 330 / 230 / 109 / 117 / 95 (~122 GB on 2 Nov). Volume tracks test runs against production
(embed_ml calls 8,992 on 2 Nov → 378 on 9 Nov). Founder chose Hugging Face hosting: the switch is merged-ready
(ML_MODEL_HF_REPO edge secret; scripts/kb/publish_ml_model_to_hf.mjs uploads, verifies sha256, sets the secret).
BLOCKED ONLY on a Hugging Face WRITE token saved as an environment network secret for huggingface.co (the
Hugging Face connector, user "Quotesdone", is read-only). He declined the form once on 9 Nov — do not re-ask
in the same session; tell him where to add it.
MAU 1,291 = test users (40 auth users exist now); free under the plan. GitHub Actions: 114,687 run-minutes
1 Oct-9 Nov (per run, not per job), peaks 23,049 on 26 Oct and 20,530 on 2 Nov (merge-train days).

**Access in a cloud session.** The Supabase management token is a network secret for api.supabase.com (saved
9 Nov, works). Scripts that read SUPABASE_ACCESS_TOKEN: run them with `SUPABASE_ACCESS_TOKEN=proxy-injected
NODE_USE_ENV_PROXY=1` (Node's fetch ignores HTTPS_PROXY without it, so the header was never injected → 401).
The logs API (analytics/endpoints/logs) is ClickHouse over one table `logs` filtered by `source`, one day per
query, and throttles: ~1 query per 6 s.

**Owed next:** merge #1874 when its checks are green (founder's standing approval for reviewed, gate-clean PRs);
after merge, confirm the DB apply read-back (kb_chunks_old gone, purge job active) and regenerate the mirror;
publish the model once the HF token exists; TD-16 (7 routines calling dropped routines) on production;
M2 (password sign-up confirmation setting) one production read.

Related: [[checkpoint-4-nov-handover-pr-drain]], [[deno-node-modules-auto-breaks-next-build]],
[[docker-and-a-local-database-in-a-cloud-session]], [[checks-read-split-code-through-a-sources-helper]].
