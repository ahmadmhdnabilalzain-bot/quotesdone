# Releasing without CI

Seat: it_engineer. Written 26 Oct 2026; scheduled jobs moved to Claude cloud routines 27 Oct 2026.

**IN FORCE AGAIN from 10 Nov 2026 (founder_instruction 1564).** The founder's GitHub Actions budget (USD 200) is
spent: *"find a way to solve all these issues without GitHub ... Use the Claude processor itself."* Every workflow
is manual-only again, under `# founder 10 Nov (ledger 1564): ...` above its `on:`, and
`scripts/checks/the_schedules_moved_off_github_stay_on_pg_cron.test.mjs` requires that on every workflow. Everything
below applies, with two updates: jobs now name `ubuntu-latest` (GitHub-hosted, billed), so a dispatched run would
cost money — never dispatch one; and in a Claude cloud session the merge goes through the GitHub MCP tools, and the
Supabase token is proxy-injected (`NODE_USE_ENV_PROXY=1 SUPABASE_ACCESS_TOKEN=proxy-injected`). For the
Supabase CLI itself (`deploy_functions.mjs` calls `supabase functions deploy`) the placeholder must LOOK like a token or
the CLI refuses before sending anything (`LegacyInvalidAccessTokenError`, measured 10 Nov 2026 on all 74 functions):
use `SUPABASE_ACCESS_TOKEN=sbp_0000000000000000000000000000000000000000` (sbp_ + 40 zeros); the proxy replaces it.

**The founder's order, 26 Oct 2026:** Ubicloud is stopped. No paid service runs CI until the bugs are cleared,
and that includes GitHub-hosted Actions minutes. Claude sessions run the checks, the deploys and the scheduled
work themselves.

So all 13 workflows in `.github/workflows` now start only by hand (`workflow_dispatch`). Each one has the line
`# founder 26 Oct: automatic triggers off until bugs clear; re-enable push/pull_request/schedule then` above its
`on:` block, and its original triggers are still in the file as comments. Do not dispatch a workflow either. Every
job still runs on `vars.RUNNER || 'ubicloud-standard-…'`, so with Ubicloud stopped a dispatched run waits in the
queue and never starts. And if a GitHub-hosted runner were set, the run would use billed minutes.
`scripts/checks/the_schedules_moved_off_github_stay_on_pg_cron.test.mjs` fails if a trigger comes back while the
note is still there.

## 1. Before a PR is labelled for merge: run the gate

From the PR's own worktree, on its branch, with `npm ci` done (or the lockfile-exact tree below):

```
npm run gate -- --pr <number>
```

`scripts/ci/local_gate.mjs` runs the commands that the PR-gate jobs ran:

| Workflow | Jobs it replaces |
|---|---|
| `checks.yml` | `npm test` (node --test over `scripts/checks` and the deno suite), the SSRF guard, the fetch-deadline ratchet, the four drawing `.check.ts` proofs, squawk, `npm run typecheck`, `npm audit`, `deno check` on the gated functions and on all of them, and the OTP race |
| `project-parity.yml` | the parity job (canonical_routine_manifest, export-identical, advisors baseline, edge-log attack read, function owners, duty clocks, model matrix, registry sync, receipts) and the kernel gate (anon_cannot_execute_security_definer, every_alarm_is_quiet_on_a_healthy_day) |

- It prints one PASS/FAIL table, exits 1 on any FAIL and, with `--pr`, posts the table as a PR comment. The comment
  goes through REST (`gh api -X POST repos/<owner>/<repo>/issues/<n>/comments`), which works in a cloud or phone
  session. Each step's log is in `<tmp>/qd-gate-<time>/`.
- `--pr` refuses to run when the worktree has uncommitted changes or when HEAD is not the PR's head (read through
  `gh api repos/<owner>/<repo>/pulls/<n>`). A posted PASS therefore always certifies the PR's own code.
- The production steps need `SUPABASE_ACCESS_TOKEN` or `~/.supabase/access-token`. Without one they **FAIL**. A
  check that cannot reach its subject has not passed.
- The OTP race needs a throwaway Postgres: set `QD_OTP_RACE_PG`, or start Docker so the gate can run `postgres:16`
  itself. It never uses production.
- `--skip=<id,...>` leaves out the steps you name, and they show as SKIPPED in the table. Name a step only when it
  cannot run on the machine. Never skip one to turn the table green.
- `--daily` also runs `verify_deploy_parity.mjs --all`. `project-parity.yml` ran that check only on its daily
  schedule.
- **The gate certifies the tree that ships (11 Nov 2026).** Three steps no workflow had: `node-tree` (the worktree's
  own `node_modules` is exactly `package-lock.json`: npm's layout, every locked version, nothing extra, not a link to
  another checkout), `next-build` (`npm run build`, as Vercel builds the site), and `tree-unchanged` (no step rewrote
  `node_modules` during the run). Every Deno call runs with `--node-modules-dir=none`, so none of them can. With no
  disk for a second `npm ci`, build the tree by hard links from an existing store, inside the worktree:
  `node scripts/ci/node_modules_from_lockfile.mjs package-lock.json <store>/node_modules node_modules`. In a cloud
  session put `.next` on tmpfs (`ln -s /dev/shm/<name> .next`; the build writes ~400 MB).
- **Offline is how a release is checked while Actions is off:** `npm run gate -- --offline --skip=npm-test`, and the
  offline subset of `npm test` run per file on the branch and on `origin/main` and compared (TD-26), so a red check
  `--skip=npm-test` hides cannot reach `main`.

The release operator merges only on a posted table with no FAIL, the same as the old required checks. Main has
**no branch protection and no rulesets** (measured 26 Oct 2026: `GET /branches/main/protection` returns 404 "Branch
not protected", and `/rulesets` returns `[]`). GitHub never enforced the green checks. The only thing that did was
`REQUIRED_CHECKS` in `scripts/it/release_train.mjs`. With CI off those checks never report, so
`release_train.mjs` refuses every PR, and the operator merges by hand.

## 1b. A whole merge over REST (cloud and phone sessions)

In a cloud or phone session the proxy blocks GitHub's GraphQL API, so `gh pr ...` and `gh issue ...` answer 403
there. `scripts/it/release_train.mjs` is built on `gh pr` and cannot run in those sessions. Use `gh api` (REST) for
every step, as below. `git` itself works. The same commands also work on a desktop.

```
R=repos/ahmadmhdnabilalzain-bot/quotesdone; N=<pr number>

# read: open, mergeable, head and base
gh api $R/pulls/$N --jq '{state, draft, mergeable, mergeable_state, head: .head.sha, base: .base.ref, labels: [.labels[].name]}'
HEAD_SHA=$(gh api $R/pulls/$N --jq .head.sha)
# read: the newest gate table. It must say "all PASS", or "<n> PASS, <m> SKIPPED" where every SKIPPED row is
# daily only (deploy-parity without --daily) — never FAILED or NOT RUN (#1636) — and its "@ <sha>" (12 characters)
# must be the start of HEAD_SHA
gh api "$R/issues/$N/comments?per_page=100" --jq '[.[] | select(.body | startswith("### Local gate:"))] | last | .body | split("\n")[0]'
# read: what still reports on the head (Vercel's preview is a commit status; anything left is a check run)
gh api $R/commits/$HEAD_SHA/status --jq '{state, statuses: [.statuses[] | {context, state}]}'
gh api "$R/commits/$HEAD_SHA/check-runs?per_page=100" --jq '[.check_runs[] | {name, status, conclusion}]'
# read: each "Depends-on: #M" in the body must be merged
gh api $R/pulls/<M> --jq '{merged, state}'

# label (add; remove)
gh api -X POST $R/issues/$N/labels -f 'labels[]=review-approved'
gh api -X DELETE $R/issues/$N/labels/hold

# merge: squash, and only if the head is still the commit the gate certified
gh api -X PUT $R/pulls/$N/merge -f merge_method=squash -f sha=$HEAD_SHA
#   409 = the head moved since you read it (re-read, re-gate); 405 = not mergeable (conflict or draft)

# comment (the gate's --pr does this itself)
gh api -X POST $R/issues/$N/comments -f body='released: applied <file>, deployed <slugs>'
```

Then do section 2 from a checkout of main. If the bookkeeping commit needs a PR, open it over REST too:
`gh api -X POST $R/pulls -f title='<seat>: ...' -f head=<branch> -f base=main -f body='...'`.

## 2. After each merge: apply, then deploy the functions

`deploy-functions.yml` used to deploy the changed edge functions on every push to main. The release operator now
does it from an up-to-date main checkout, right after the merge:

```
git fetch origin main && git checkout --detach origin/main
# 1. SQL the PR added: apply each pending file at merge, never before
node scripts/apply_sql.mjs scripts/sql/<file>.sql --apply --ddl
#    delete scripts/sql/pending/<file>.txt, append the file as the LAST line of scripts/sql/MANIFEST.txt
node scripts/checks/canonical_routine_manifest.mjs            # 0 findings
node scripts/checks/export_from_either_source_is_identical.mjs --write   # last, after every apply
# 2. the functions the merge changed
node scripts/deploy_functions.mjs --ref=htdblwldjkcgjvmqkbeh --production --changed --base=<sha before the merge> --dry-run
node scripts/deploy_functions.mjs --ref=htdblwldjkcgjvmqkbeh --production --changed --base=<sha before the merge>
```

- The `--dry-run` prints the slug set first. "Deployed nothing" and "had nothing to deploy" look the same in a log
  otherwise.
- Typecheck what is about to deploy: `deno check --no-lock --node-modules-dir=auto supabase/functions/<slug>/index.ts`.
  The workflow did this before every deploy.
- `deploy_functions.mjs` keeps the workflow's rules. It needs a ref, it refuses production without
  `--production`, it refuses a verify_jwt drift, and it checks every version bump.
- Deploy only from main's head. If main moved while you worked, fetch and start again. On 13 Oct an older run
  deployed over a newer one this way.
- Push the bookkeeping (the MANIFEST line, the deleted note, the schema mirror) as one commit through a PR.
- **A merge that changes `knowledge/seats/*.json` or `knowledge/exams/*.json` is not live until it is loaded** (10 Nov
  2026, P10 of the seat audit: the six exams were committed in September and never loaded, so every monthly
  self-review read `no_exam`). After the applies, from the same checkout:
  `node scripts/kb/load_verified_packs.mjs --apply` (the packs; free gte-small embedding, no OpenRouter) and
  `node scripts/eval/seat_qualification_exam.mjs --load` (writes `public.seat_exam_item`, each question with its vector).
  `scripts/checks/every_seat_exam_is_loaded_for_the_monthly_self_review.test.mjs` fails until both are done.

## 3. Scheduled jobs now run as Claude cloud routines

**Founder's clarification, 27 Oct 2026 (founder_instruction 1296, clarifying 1279):** GitHub Actions comes back later. Until then, jobs run on Claude's own
cloud (the "Claude server") to keep costs down. The coordinator created five scheduled Claude cloud routines on the
QuotesDone environment, and they replace the Actions schedules that need a runner:

| Routine | Schedule (UTC) | Replaces | Link |
|---|---|---|---|
| CAD read worker | every 2 h at :15 | `cad-read-worker.yml` (every 6 h) | [trig_01Ba9wRwSSbwrs6byguTqAYB](https://claude.ai/code/routines/trig_01Ba9wRwSSbwrs6byguTqAYB) |
| Multilingual embed backfill | daily 02:50 | `ml-embed-backfill.yml` | [trig_01PvyTpFGoLyy9iLeLbyHnUo](https://claude.ai/code/routines/trig_01PvyTpFGoLyy9iLeLbyHnUo) |
| Daily parity gate | daily 05:41 | `project-parity.yml` schedule | [trig_01RKafcU3CoLJKtfUGJXxJS1](https://claude.ai/code/routines/trig_01RKafcU3CoLJKtfUGJXxJS1) |
| Weekly readings | Mondays 04:30 | `it-weekly-readings.yml` | [trig_01Bxp48JvtXygiQ7M3Eq3ATK](https://claude.ai/code/routines/trig_01Bxp48JvtXygiQ7M3Eq3ATK) |
| Nightly journey | daily 22:00 | `nightly-journey.yml` | [trig_01BYYDz8uEKUyoiEaKuR9eyJ](https://claude.ai/code/routines/trig_01BYYDz8uEKUyoiEaKuR9eyJ) |

Each routine runs the same scripts the workflow ran (the commands are in the table below). Those scripts report to
the same database rows, so the existing heartbeats watch the routines with no change: `journey_heartbeat` (26 h),
`dependency` and `platform` (8 d), and `parity` (36 h, through the advisor refresh). A routine that stops, fails or
cannot report opens the same finding a failed workflow did. The routines are Claude's cloud, not this repository,
so a change to one is made at its link, and this table must change with it.

## 3b. Every scheduled job, and where it runs now

| Was (GitHub schedule) | Now | If it does not run |
|---|---|---|
| `dropbox-backup-second-scheduler.yml`, every 6 h | **pg_cron `dropbox_backup_second_scheduler`**, same minute (`scripts/sql/the_github_schedules_that_can_move_run_on_pg_cron_while_actions_are_off.sql`, applied at merge) | A document still reaches Dropbox through the pg_net kick when it lands and through resilience_ping every 15 min. What is lost: this was the one kick path outside both Supabase and Vercel. |
| `kb-embed-backfill.yml`, daily 02:20 UTC | **pg_cron `kb_embed_daily`**, `fn_kb_embed_scheduled_run()` (same file) | 0 rows were unembedded on 26 Oct. resilience_ping embeds new rows every 15 min. |
| `nightly-journey.yml`, daily 22:00 UTC | **Claude cloud routine "Nightly journey"**, 22:00 UTC (section 3). It runs `npm ci && npx playwright install chromium`, then `node scripts/e2e/run.mjs`, `node scripts/e2e/drawing_journeys_into_report.mjs e2e-out`, `node scripts/e2e/report_to_it_engineer.mjs e2e-out`, `node scripts/e2e/supplier_quote_review.mjs`, then `node scripts/e2e/close_job_windows.mjs "$QD_E2E_RUN_TAGS"` (set `QD_E2E_REPORTS=e2e-out`, `QD_E2E_DEADLINE_MS=2460000`, `QD_E2E_WINDOW_MIN=120`, `QD_E2E_RUN_TAGS=e2e-run-tags.txt`) | Nothing proves the funnel and the screens on demo data. `fn_it_duties` journey_heartbeat raises a finding after 26 h. |
| `it-post-deploy-smoke.yml`, after each main deploy | The release operator, after a merge that deployed: `node scripts/e2e/run.mjs --journey a,b,c`, then `node scripts/e2e/report_to_it_engineer.mjs e2e-out --smoke <sha> changed-files.txt` (`git diff --name-only <sha>~1 <sha> > changed-files.txt`, `QD_E2E_WINDOW_MIN=33`) | A merge that broke sign-in, a portal, a quote or the PDF is not seen until the nightly runs. The `smoke` heartbeat (7 d) raises it. |
| `it-weekly-readings.yml`, Mondays 04:30 UTC | **Claude cloud routine "Weekly readings"**, Mondays 04:30 UTC. It runs `node scripts/it/report_dependency_audit.mjs`, `node scripts/it/report_platform_readings.mjs`, `node scripts/it/workflow_audit.mjs`, `node scripts/it/open_dependency_patch_pr.mjs` | No dependency advisories, backups/PITR, members or disk readings. The `dependency` and `platform` heartbeats (8 d) raise it. |
| `project-parity.yml`, daily 05:41 UTC | **Claude cloud routine "Daily parity gate"**, 05:41 UTC: `npm run gate -- --daily` on main. Its advisor refresh beats the `parity` heartbeat (36 h) | Routine drift, a new advisor finding and an edge-log attack pattern go unread. |
| `cad-read-worker.yml`, every 6 h and dispatched by customer_api | **Claude cloud routine "CAD read worker"**, every 2 h at :15 UTC, when `select count(*) from cad_read_jobs where status not in ('done','failed')` is above 0: `deno run --no-lock --node-modules-dir=auto --allow-net --allow-env --allow-read scripts/cad_read_worker.ts` | A CAD drawing too big for the edge stays unread. A queued drawing now waits up to 2 h for the routine instead of being read at once. 0 open jobs on 26 Oct. customer_api's dispatch still calls the workflow, and that run queues on the stopped runner. |
| `ml-embed-backfill.yml`, daily 02:50 UTC | **Claude cloud routine "Multilingual embed backfill"**, 02:50 UTC: `npm i --no-save @huggingface/transformers@3.8.1 && node scripts/kb/run_ml_embed_backfill.mjs --minutes=40 --claim=64` (free, local CPU) | The Arabic/multilingual backlog drains only at resilience_ping's 4 rows a tick. |
| `marketing-asset-features.yml`, Mondays 03:41 UTC | A Claude session after a campaign upload (needs ffmpeg and tesseract): `node scripts/media/measure_marketing_assets.mjs --check-determinism --write` | New videos are not measured. |
| `resilience-ping.yml`, daily 07:17 UTC | Not replaced. Vercel Cron still calls resilience_ping every 15 min. | Nothing outside both Supabase and Vercel checks them, so an outage of both at once goes unseen. |
| `release-train.yml`, every 10 min | The release operator, by hand (sections 1 and 2) | PRs wait for the operator. |

## 4. Turning CI back on

Uncomment the triggers in each workflow and delete the founder line above `on:`. The test above then asserts
only that `workflow_dispatch` survived. If the pg_cron jobs should hand back to GitHub, unschedule
`dropbox_backup_second_scheduler` and `kb_embed_daily` in a new SQL file. Pause the five Claude cloud routines in
section 3 at their links in the same change. If a routine and its workflow both run, the job runs twice. The
journey and smoke runs then open and tear down their demo windows twice.
