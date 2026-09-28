# Rollback runbook (it_engineer)

A bad release is undone by putting production back on what main last proved. Three surfaces, three moves.
Every move below is itself a production write: it goes through the release guard (`scripts/lib/release_guard.mjs`),
and a rollback of code that is not on main needs `--skip-release-guard="<reason>"`, which is logged.

## 1. Website (Vercel) — instant, no rebuild

1. Vercel dashboard, project, Deployments: pick the last deployment that was green, then **Instant Rollback**
   (CLI: `vercel rollback <deployment-url>`).
2. Instant Rollback pins that build and stops auto-promotion. After main is fixed, **Promote** the new
   deployment (or `vercel promote <url>`) or later pushes will not go live.
3. Check: the post-deploy smoke (`.github/workflows/it-post-deploy-smoke.yml`) or the page by hand.

## 2. Edge function — redeploy from main

```
git fetch origin && git checkout --detach origin/main
node scripts/deploy_functions.mjs --ref=htdblwldjkcgjvmqkbeh --production <slug>
node scripts/verify_deploy_parity.mjs          # deployed bundle carries main's literals
```
If main itself is the bad version, revert the commit through a PR first, then redeploy from the merged main.

## 3. Database routine — re-apply the prior canonical file

1. Find the file: `scripts/sql/MANIFEST.txt` order decides the canonical definition; the last line
   defining the routine wins. `node scripts/checks/canonical_routine_manifest.mjs` names it per routine.
2. The fix is a revert PR that removes the bad file's MANIFEST line (or appends a corrected file), merged green.
3. Re-apply the file that is now canonical, from main:
   ```
   git checkout --detach origin/main
   node scripts/apply_sql.mjs scripts/sql/<canonical>.sql --apply [--ddl]
   node scripts/checks/canonical_routine_manifest.mjs   # 0 drift
   ```
4. Schema changes (columns, tables) are not reversed by re-applying a routine: write a forward fix file,
   never an ad-hoc statement.

## Watching for it

`project-parity.yml` runs daily: `canonical_routine_manifest --all` (routines) and `verify_deploy_parity --all`
(functions). Either red means production runs something main does not say.
