# A deploy that refused is not a deploy (11 Nov 2026)

**What happened.** On 11 Nov a session chained `deploy_functions.mjs … ; sleep 300 ; <paid certification>` with `;` in
one background command. The deploy of #1935 stopped before deploying anything: its verify_jwt drift check called the
Management API and got `401 Invalid access token` from the session proxy (a transient refusal; the same command
passed minutes later), printed `REFUSING TO DEPLOY`, and exited 1. The `;` ran the paid certification anyway, against
the previous code. The session read only `grep`-filtered lines, missed `DEPLOY_EXIT 1`, and told the founder the new
design was live. It was caught about an hour later, the run was stopped, the deploy re-run (75/75), and the run
repeated. The same proxy 401 also failed one function (`reveal_invoice`) mid-deploy once that day; a re-deploy of
that one function passed.

**The rule.**
- Chain a deploy and whatever depends on it with `&&`, never `;`, and print the deploy's own exit code and its
  `DEPLOYED_OK n/n` line before saying anything is live.
- A `REFUSING TO DEPLOY`, a `DEPLOY FAILED` line, or `DEPLOYED_OK` below the count means nothing (or not everything)
  shipped. Re-run the deploy (the 401 is transient), or re-deploy the named functions, then verify again.
- Never tell the founder a change is live from a background chain's summary; read the deploy's own result first.

**A second trap the same day.** `/tmp/claude-0/main-base/node_modules` was a symlink into another worktree's
`node_modules`. Removing that worktree to free disk left main-base with a dangling link: `npm`-based scripts (the
certification harness, `playwright`) failed with ERR_MODULE_NOT_FOUND while Deno-based ones (deploy, apply) kept
working, so the break showed up late. Before removing a worktree, check `find /tmp/claude-0 -maxdepth 2 -name
node_modules -type l -lname '*<that worktree>*'`. Rebuild with `npm ci --ignore-scripts --no-audit --no-fund` (22 s).

Related: [agent worktrees fill the founder's disk](agent-worktrees-fill-the-founders-disk.md),
[npm ci in a worktree empties the shared node_modules](npm-ci-in-a-worktree-empties-the-shared-node-modules.md),
[green PR does not mean deployable](green-pr-does-not-mean-deployable.md).
