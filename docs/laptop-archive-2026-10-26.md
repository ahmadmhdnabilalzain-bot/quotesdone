# Laptop archive, 26 Oct 2026

**Seat:** it_engineer. **Order (founder, 26 Oct 2026):** GitHub is the single source of truth; nothing may
exist only on the laptop; then the laptop is cleared; nothing may be lost.

Everything that existed only on the laptop was pushed to `origin` under `refs/heads/archive/laptop-2026-10-26/`.
Every ref below was verified after the push: the sha `git ls-remote` returned equals the local sha
(492 of 492 matched). Nothing was force-pushed and `main` was not touched.

## How each kind was archived

| kind | ref prefix | what the commit holds |
|---|---|---|
| worktree-uncommitted | `archive/laptop-2026-10-26/worktree/<name>` | every modified, staged, deleted and untracked (not ignored) file of that worktree, committed on top of its HEAD with a private index, so the worktree itself was not changed. Unmerged files are committed **with their conflict markers**, named in the commit message. |
| worktree-ignored | `archive/laptop-2026-10-26/worktree-ignored/<name>` | on top of the above (or of HEAD when clean): the git-ignored files that are not generated - root scratch scripts, notes, outputs, ignored folders. Left out: node_modules, .next, venv, graphify-out, .claude-flow, *.tsbuildinfo, *.lock, nested worktrees. |
| worktree-head | `archive/laptop-2026-10-26/worktree-head/<name>` | a detached HEAD that was on no branch and not on origin. |
| stash | `archive/laptop-2026-10-26/stash/NN` | stash@{NN} of the shared repository. The archived commit's first parent IS the stash commit (base, index and untracked parents included). |
| branch | `archive/laptop-2026-10-26/branch/<name>` | a local branch whose tip no origin ref contained. The archived commit's first parent IS the branch tip; its tree is the tip's tree. |
| loose-files | `archive/laptop-2026-10-26/loose-files` | folders with no git at all: `qd-packs` (knowledge packs v2026.07.31), `qd-se-dwg-samples`, `qd-deploy`, `qd-worktree-backup-20260728-194857`, and `.claude/worktrees/agent-a4dd14af9fb107962` (node_modules left out). `loose-files-2`: copies of the `C:/Users/Opera/qd-*.sh` release scripts (left in place) and the stray `C:/c/Users/Opera` scratch folder. `loose-files-3`: scratch SQL and logs sitting at the root of `.claude/worktrees`. |

Every archive commit's message starts with `[skip ci]`, so the push started no workflow
(`deploy-functions.yml` runs on a push to any branch).

**Secrets.** Every file entering an archive commit was scanned for `sb_secret_`, `sk-` keys, JWTs and
private keys, and `.env*`, `*.key`, `*.pem` files were refused by name. A token already present on
`origin/main` (the public anon key) was not treated as new. **Files left out for a secret: none were
found.** Left out by size or as generated: `deno297.exe` (>50 MB binary, main checkout root),
`.claude/scheduled_tasks.lock`, `tsconfig.tsbuildinfo` (every worktree).

**"On main"** = for the files the ref changes against its base, how many differ from `origin/main` at
the time of measurement (5446f60 era). "yes" means every changed file already matches main. For a
branch, "unique commits" is `git cherry origin/main <tip>`'s "+" count (squash merges show as "+",
so read it with the PR column).

## Cleanup

Done only after every ref above was verified on origin, and after `git rev-list --branches --not
--remotes=origin` and the same for every stash and worktree HEAD returned **0** commits.

| what | count | how |
|---|---|---|
| worktrees removed | 313 | `git worktree remove --force` (single force, so a locked worktree would have been refused - none were), then `git worktree prune`. Each was checked for activity in the last 30 minutes (its index, HEAD, HEAD log and folder) immediately before removal. Leftover `node_modules` shells were removed with `rmdir /s /q`, which deletes junctions without following them. |
| unregistered folders removed | 193 + 124 shells | 188 held only `node_modules` or `.claude-flow` metrics, 20 were empty; the six with content went to `loose-files` first. |
| local branches deleted | 2,114 | every one had its tip on an origin ref at the moment of deletion (265 of them through the archive refs). |
| stashes dropped | 26 | `git stash clear`, after confirming the 26 shas were unchanged and archived. |
| main checkout | reset | `git reset --hard origin/main` + `git clean -fd` (ignored files kept), a stale interactive rebase and a stale revert sequence (both of commits already on origin) were quit. It now sits on 5446f60 with a clean status. |
| disk | +70.9 GB free | `df`: 606,479,101,952 bytes used before, 535,561,506,816 after (other sessions were writing meanwhile, so this is approximate). |

**Deliberately left on the laptop** (in use by the release operator or another live session when the
cleanup ran): worktrees `qd-rel26`, `qd-rel26-b`, `qd-seedtoken`, `qd-wt-ceo-sot`, `qd-wt-ci-off`,
`qd-wt-cloud`, `qd-wt-cloud-base`; the branches checked out in them; and the 13 PR branches the release
operator asked to keep (`#1586 #1590 #1587 #1588 #1592 #1483 #1548 #1574 #1575 #1370 #1369 #1193 #1182`).
`qd-wt-ci-off` and `qd-wt-cloud` were archived (refs above) but changed again after the archive, so
their owners must push them. The release scripts `C:/Users/Opera/qd-*.sh` stay in place (copies archived).

## Worktrees: uncommitted work (64)

Four scratch worktrees (`wt_charges`, `wt_b4`, `wt887`, `rel1004/wtsess`) had most tracked files
deleted on disk; their archives record those deletions faithfully - the work in them is the added files.

| ref | source | files | deleted | already on main | description |
|---|---|---|---|---|---|
| `worktree/cw-agent-a14b836d48d88cd89` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a14b836d48d88cd89 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-a1aa27ca62a51cb11` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a1aa27ca62a51cb11 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-a23a04afd57de8098` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a23a04afd57de8098 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-a50af47c04033b9be` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a50af47c04033b9be | 12 | 0 | no: 12 of 12 files differ from main | uncommitted: knowledge/seats(5), knowledge/exams(5), scripts/eval(1) |
| `worktree/cw-agent-a5448d5f37392f369` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a5448d5f37392f369 | 3 | 0 | no: 3 of 3 files differ from main | uncommitted: supabase/functions(1), next-env.d.ts(1), deno.lock(1) |
| `worktree/cw-agent-a55307e025981d320` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a55307e025981d320 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-a5a9fe829024faff0` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a5a9fe829024faff0 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-a668c697a376f70a8` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a668c697a376f70a8 | 2 | 0 | no: 2 of 2 files differ from main | uncommitted: package-lock.json(1), deno.lock(1) |
| `worktree/cw-agent-a6d3c11b36216720f` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a6d3c11b36216720f | 2 | 0 | no: 2 of 2 files differ from main | uncommitted: next-env.d.ts(1), CLAUDE.md(1) |
| `worktree/cw-agent-a9449996cd4c7116a` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a9449996cd4c7116a | 2 | 0 | no: 2 of 2 files differ from main | uncommitted: scripts/sql(1), deno.lock(1) |
| `worktree/cw-agent-aaec6fea8086cb0ae` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aaec6fea8086cb0ae | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-ab29a0f6fe1eda1d7` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ab29a0f6fe1eda1d7 | 35 | 0 | no: 18 of 35 files differ from main | uncommitted: supabase/functions(15), scripts/sql(8), scripts/checks(8) |
| `worktree/cw-agent-ab57f2828a00b54f4` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ab57f2828a00b54f4 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-ab80d858a26514fb2` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ab80d858a26514fb2 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-ac32a91bc48f9987a` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ac32a91bc48f9987a | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-acd4a32578adb291b` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-acd4a32578adb291b | 15 | 0 | no: 12 of 15 files differ from main | uncommitted: supabase/functions(11), src/components(2), scripts/sql(2) |
| `worktree/cw-agent-ace149458131fd238` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ace149458131fd238 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-ad1242d0f209161bf` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ad1242d0f209161bf | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-ad13e24ccf536e543` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ad13e24ccf536e543 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-ad1a23b13d711e28d` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ad1a23b13d711e28d | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-ad6429d442ae81d73` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ad6429d442ae81d73 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-adeac957acd1d6a66` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-adeac957acd1d6a66 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-adfc5496cb6645b7f` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-adfc5496cb6645b7f | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: supabase/functions(1) |
| `worktree/cw-agent-ae1205deb24274a9a` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ae1205deb24274a9a | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-af2dceff4f17de8c8` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-af2dceff4f17de8c8 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-agent-af33735b37fd5bd18` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-af33735b37fd5bd18 | 2 | 0 | no: 2 of 2 files differ from main | uncommitted: next-env.d.ts(1), deno.lock(1) |
| `worktree/cw-agent-af57471ece540c62a` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-af57471ece540c62a | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/cw-cs-chat-remembers-whole-conversation` | C:/Users/Opera/quotesdone/.claude/worktrees/cs-chat-remembers-whole-conversation | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/main-checkout` | C:/Users/Opera/quotesdone | 185 | 2 | no: 112 of 185 files differ from main | uncommitted: scripts/sql(68), supabase/functions(43), scripts/checks(30) |
| `worktree/qd-1207` | C:/Users/Opera/qd-1207 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-audit-main` | C:/Users/Opera/qd-audit-main | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: docs/sessions(1) |
| `worktree/qd-ceo-facts` | C:/Users/Opera/qd-ceo-facts | 3 | 0 | no: 3 of 3 files differ from main | uncommitted: scripts/eval(2), deno.lock(1) |
| `worktree/qd-ceo-plan` | C:/Users/Opera/qd-ceo-plan | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-ceo-verify` | C:/Users/Opera/qd-ceo-verify | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-exam3` | C:/Users/Opera/qd-exam3 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-int5` | C:/Users/Opera/qd-int5 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-liab` | C:/Users/Opera/qd-liab | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-mkt-duties` | C:/Users/Opera/qd-mkt-duties | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-op-954` | C:/Users/Opera/qd-op-954 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: supabase/schema(1) |
| `worktree/qd-placement-hdrs` | C:/Users/Opera/qd-placement-hdrs | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-qa-fix` | C:/Users/Opera/qd-qa-fix | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-se-base` | C:/Users/Opera/qd-se-base | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-se-read` | C:/Users/Opera/qd-se-read | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-se-repeat` | C:/Users/Opera/qd-se-repeat | 3 | 0 | no: 3 of 3 files differ from main | uncommitted: next-env.d.ts(1), deno.lock(1), CLAUDE.md(1) |
| `worktree/qd-se-taxonomy` | C:/Users/Opera/qd-se-taxonomy | 14 | 0 | no: 14 of 14 files differ from main | uncommitted: knowledge/packs(14) |
| `worktree/qd-sec-cwe` | C:/Users/Opera/qd-sec-cwe | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-smokefix-1` | C:/Users/Opera/qd-smokefix-1 | 8 | 0 | no: 7 of 8 files differ from main | uncommitted: supabase/functions(4), scripts/e2e(3), deno.lock(1) |
| `worktree/qd-wa-404` | C:/Users/Opera/qd-wa-404 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-wt-1209` | C:/Users/Opera/qd-wt-1209 | 17 | 0 | no: 17 of 17 files differ from main | uncommitted: knowledge/brief(13), scripts/checks(3), scripts/kb(1) |
| `worktree/qd-wt-993` | C:/Users/Opera/qd-wt-993 | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-wt-audience` | C:/Users/Opera/qd-wt-audience | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-wt-ci-off` | C:/Users/Opera/qd-wt-ci-off | 17 | 0 | no: 17 of 17 files differ from main | uncommitted: .github/workflows(13), scripts/sql(2), scripts/checks(2) |
| `worktree/qd-wt-cloud` | C:/Users/Opera/qd-wt-cloud | 130 | 1 | no: 130 of 130 files differ from main | uncommitted: scripts/checks(54), scripts/staging(16), scripts/kb(11) |
| `worktree/qd-wt-email-ctx` | C:/Users/Opera/qd-wt-email-ctx | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/qd-wt-exam` | C:/Users/Opera/qd-wt-exam | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: scripts/lib(1) |
| `worktree/qd-wt-reaccept` | C:/Users/Opera/qd-wt-reaccept | 1 | 0 | no: 1 of 1 files differ from main | uncommitted: deno.lock(1) |
| `worktree/quotesdone-W` | C:/Users/Opera/quotesdone/$W | 3 | 0 | no: 3 of 3 files differ from main | uncommitted: supabase/functions(3) |
| `worktree/scratch-drift` | <scratchpad>/drift | 1 | 1 | no: 1 of 1 files differ from main | uncommitted: scripts/sql(1) |
| `worktree/scratch-rel1004-wtsess` | <scratchpad>/rel1004/wtsess | 3535 | 3535 | no: 3535 of 3535 files differ from main | uncommitted: scripts/sql(1720), supabase/migrations_history(734), supabase/functions(598) |
| `worktree/scratch-wt_b4` | <scratchpad>/wt_b4 | 4485 | 4328 | no: 4473 of 4485 files differ from main | uncommitted: scripts/sql(1377), supabase/migrations_history(739), supabase/functions(500) |
| `worktree/scratch-wt_charges` | <scratchpad>/wt_charges | 4751 | 4482 | no: 4740 of 4751 files differ from main | uncommitted: scripts/sql(1420), supabase/migrations_history(739), supabase/functions(531) |
| `worktree/scratch-wt_idor` | <scratchpad>/wt_idor | 1 | 1 | no: 1 of 1 files differ from main | uncommitted: scripts/sql(1) |
| `worktree/scratch-wt1312` | <scratchpad>/wt1312 | 1 | 1 | no: 1 of 1 files differ from main | uncommitted: scripts/sql(1) |
| `worktree/scratch-wt887` | <scratchpad>/wt887 | 4319 | 4319 | no: 4306 of 4319 files differ from main | uncommitted: scripts/sql(1376), supabase/migrations_history(739), supabase/functions(492) |

## Worktrees: git-ignored files (133)

| ref | source | files added |
|---|---|---|
| `worktree-ignored/cw-agent-a0893cf7b25361879` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a0893cf7b25361879 | 1 |
| `worktree-ignored/cw-agent-a09b63bd4c8061afd` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a09b63bd4c8061afd | 1 |
| `worktree-ignored/cw-agent-a0b2d5f6313072116` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a0b2d5f6313072116 | 1 |
| `worktree-ignored/cw-agent-a0ce159d1748666d3` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a0ce159d1748666d3 | 1 |
| `worktree-ignored/cw-agent-a0d515afef9ccb6ad` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a0d515afef9ccb6ad | 1 |
| `worktree-ignored/cw-agent-a0d679634e396e733` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a0d679634e396e733 | 1 |
| `worktree-ignored/cw-agent-a0fe933a31fc5a0fb` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a0fe933a31fc5a0fb | 1 |
| `worktree-ignored/cw-agent-a1034e68bdd52d859` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a1034e68bdd52d859 | 1 |
| `worktree-ignored/cw-agent-a10fe26e817a2bbc7` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a10fe26e817a2bbc7 | 1 |
| `worktree-ignored/cw-agent-a13ad99e0d1102be6` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a13ad99e0d1102be6 | 1 |
| `worktree-ignored/cw-agent-a141a0944873de76f` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a141a0944873de76f | 1 |
| `worktree-ignored/cw-agent-a14b836d48d88cd89` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a14b836d48d88cd89 | 2 |
| `worktree-ignored/cw-agent-a16d5233e34d6fa93` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a16d5233e34d6fa93 | 1 |
| `worktree-ignored/cw-agent-a16ff0e1d64a7dd3a` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a16ff0e1d64a7dd3a | 1 |
| `worktree-ignored/cw-agent-a19ef852ecf9eef80` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a19ef852ecf9eef80 | 1 |
| `worktree-ignored/cw-agent-a1aa27ca62a51cb11` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a1aa27ca62a51cb11 | 1 |
| `worktree-ignored/cw-agent-a20c499c47c139694` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a20c499c47c139694 | 1 |
| `worktree-ignored/cw-agent-a228c19db435e4a6c` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a228c19db435e4a6c | 1 |
| `worktree-ignored/cw-agent-a236743a22a918018` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a236743a22a918018 | 1 |
| `worktree-ignored/cw-agent-a23a04afd57de8098` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a23a04afd57de8098 | 4 |
| `worktree-ignored/cw-agent-a27a0df99224ba5fe` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a27a0df99224ba5fe | 1 |
| `worktree-ignored/cw-agent-a2972dfcddb952b4b` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a2972dfcddb952b4b | 1 |
| `worktree-ignored/cw-agent-a2a14a5ea2b53a5d0` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a2a14a5ea2b53a5d0 | 1 |
| `worktree-ignored/cw-agent-a2addcac2ecba1bfb` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a2addcac2ecba1bfb | 2 |
| `worktree-ignored/cw-agent-a2b55f2b951a9088f` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a2b55f2b951a9088f | 1 |
| `worktree-ignored/cw-agent-a2fbbfbdba32f8057` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a2fbbfbdba32f8057 | 1 |
| `worktree-ignored/cw-agent-a3109263b5362d791` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a3109263b5362d791 | 1 |
| `worktree-ignored/cw-agent-a39cb0790e54c3e4c` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a39cb0790e54c3e4c | 1 |
| `worktree-ignored/cw-agent-a3ae4522730c176b6` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a3ae4522730c176b6 | 1 |
| `worktree-ignored/cw-agent-a3e35ec0dcc319402` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a3e35ec0dcc319402 | 2 |
| `worktree-ignored/cw-agent-a4195c459b1b73812` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a4195c459b1b73812 | 3 |
| `worktree-ignored/cw-agent-a42938e26d086741f` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a42938e26d086741f | 1 |
| `worktree-ignored/cw-agent-a42a4db75f005269f` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a42a4db75f005269f | 1 |
| `worktree-ignored/cw-agent-a435111c25a6e2af0` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a435111c25a6e2af0 | 1 |
| `worktree-ignored/cw-agent-a4401f389f04f8501` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a4401f389f04f8501 | 1 |
| `worktree-ignored/cw-agent-a44575bb3b2b6dc9c` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a44575bb3b2b6dc9c | 1 |
| `worktree-ignored/cw-agent-a4dd16589cc3b1aea` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a4dd16589cc3b1aea | 2 |
| `worktree-ignored/cw-agent-a50af47c04033b9be` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a50af47c04033b9be | 1 |
| `worktree-ignored/cw-agent-a532bbc7af1603a8e` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a532bbc7af1603a8e | 1 |
| `worktree-ignored/cw-agent-a5448d5f37392f369` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a5448d5f37392f369 | 9 |
| `worktree-ignored/cw-agent-a55307e025981d320` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a55307e025981d320 | 1 |
| `worktree-ignored/cw-agent-a56c635bf02189106` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a56c635bf02189106 | 1 |
| `worktree-ignored/cw-agent-a584a982922da1533` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a584a982922da1533 | 1 |
| `worktree-ignored/cw-agent-a5a9fe829024faff0` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a5a9fe829024faff0 | 1 |
| `worktree-ignored/cw-agent-a5be13b381e30c69b` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a5be13b381e30c69b | 1 |
| `worktree-ignored/cw-agent-a62112e1bbf6404da` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a62112e1bbf6404da | 2 |
| `worktree-ignored/cw-agent-a629b1320cf764eed` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a629b1320cf764eed | 1 |
| `worktree-ignored/cw-agent-a668c697a376f70a8` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a668c697a376f70a8 | 1 |
| `worktree-ignored/cw-agent-a669ebef03e2b8ba0` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a669ebef03e2b8ba0 | 1 |
| `worktree-ignored/cw-agent-a670ba3ace4fcd4d5` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a670ba3ace4fcd4d5 | 1 |
| `worktree-ignored/cw-agent-a6d3c11b36216720f` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a6d3c11b36216720f | 2 |
| `worktree-ignored/cw-agent-a6e5b823148eee45e` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a6e5b823148eee45e | 1 |
| `worktree-ignored/cw-agent-a708827e58cb0698e` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a708827e58cb0698e | 3 |
| `worktree-ignored/cw-agent-a70ad2525e6929386` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a70ad2525e6929386 | 2 |
| `worktree-ignored/cw-agent-a7587e55b05094631` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a7587e55b05094631 | 2 |
| `worktree-ignored/cw-agent-a7c47fa510b153a9f` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a7c47fa510b153a9f | 1 |
| `worktree-ignored/cw-agent-a7dfeb1a2f5322269` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a7dfeb1a2f5322269 | 1 |
| `worktree-ignored/cw-agent-a7e1a4d9a978855da` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a7e1a4d9a978855da | 2 |
| `worktree-ignored/cw-agent-a7e7dfce636199158` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a7e7dfce636199158 | 1 |
| `worktree-ignored/cw-agent-a83947477ce22e95f` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a83947477ce22e95f | 1 |
| `worktree-ignored/cw-agent-a845b99b17272e2c0` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a845b99b17272e2c0 | 1 |
| `worktree-ignored/cw-agent-a8895e427b00e14a2` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a8895e427b00e14a2 | 1 |
| `worktree-ignored/cw-agent-a8a2417814a0e7c69` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a8a2417814a0e7c69 | 1 |
| `worktree-ignored/cw-agent-a9449996cd4c7116a` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a9449996cd4c7116a | 1 |
| `worktree-ignored/cw-agent-a944ef46f9fb1ed91` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a944ef46f9fb1ed91 | 2 |
| `worktree-ignored/cw-agent-a9453de8376c3a52a` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a9453de8376c3a52a | 1 |
| `worktree-ignored/cw-agent-a96782bde3fdf5beb` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a96782bde3fdf5beb | 1 |
| `worktree-ignored/cw-agent-a96cdd10921428565` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a96cdd10921428565 | 1 |
| `worktree-ignored/cw-agent-a99b3721809486e29` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a99b3721809486e29 | 1 |
| `worktree-ignored/cw-agent-a99c82735dad112ae` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a99c82735dad112ae | 1 |
| `worktree-ignored/cw-agent-a99df8eb41a39263a` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a99df8eb41a39263a | 1 |
| `worktree-ignored/cw-agent-a9b2644659540d9e2` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-a9b2644659540d9e2 | 2 |
| `worktree-ignored/cw-agent-aa1154930c93acc16` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aa1154930c93acc16 | 3 |
| `worktree-ignored/cw-agent-aa347f0e95c61e656` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aa347f0e95c61e656 | 1 |
| `worktree-ignored/cw-agent-aa454220f572a91fc` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aa454220f572a91fc | 1 |
| `worktree-ignored/cw-agent-aa5b18e0983b7e4a5` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aa5b18e0983b7e4a5 | 1 |
| `worktree-ignored/cw-agent-aa6b9dcc0645c54aa` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aa6b9dcc0645c54aa | 1 |
| `worktree-ignored/cw-agent-aa7caa51d70a67fb6` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aa7caa51d70a67fb6 | 2 |
| `worktree-ignored/cw-agent-aa92a42da2ecd1818` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aa92a42da2ecd1818 | 1 |
| `worktree-ignored/cw-agent-aaec6fea8086cb0ae` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aaec6fea8086cb0ae | 1 |
| `worktree-ignored/cw-agent-aaf54bda9066e0fb0` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aaf54bda9066e0fb0 | 1 |
| `worktree-ignored/cw-agent-ab0d1fbcfa8bcad63` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ab0d1fbcfa8bcad63 | 1 |
| `worktree-ignored/cw-agent-ab29a0f6fe1eda1d7` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ab29a0f6fe1eda1d7 | 1 |
| `worktree-ignored/cw-agent-ab57f2828a00b54f4` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ab57f2828a00b54f4 | 2 |
| `worktree-ignored/cw-agent-ab80d858a26514fb2` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ab80d858a26514fb2 | 1 |
| `worktree-ignored/cw-agent-aba0740700543b04d` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aba0740700543b04d | 1 |
| `worktree-ignored/cw-agent-aba2a896e0131c407` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aba2a896e0131c407 | 5 |
| `worktree-ignored/cw-agent-abb62aa2dc9c8ddb5` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-abb62aa2dc9c8ddb5 | 1 |
| `worktree-ignored/cw-agent-abd0a79b0eb3b75ef` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-abd0a79b0eb3b75ef | 1 |
| `worktree-ignored/cw-agent-abf1c978cdf88f885` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-abf1c978cdf88f885 | 1 |
| `worktree-ignored/cw-agent-ac0eb96153596d8f5` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ac0eb96153596d8f5 | 5 |
| `worktree-ignored/cw-agent-ac32a91bc48f9987a` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ac32a91bc48f9987a | 1 |
| `worktree-ignored/cw-agent-ac36c4bbe60755119` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ac36c4bbe60755119 | 1468 |
| `worktree-ignored/cw-agent-ac39b416f0f62d8f3` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ac39b416f0f62d8f3 | 1 |
| `worktree-ignored/cw-agent-ac4d3c77337228e9b` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ac4d3c77337228e9b | 2 |
| `worktree-ignored/cw-agent-ac8c377517ab52c57` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ac8c377517ab52c57 | 1 |
| `worktree-ignored/cw-agent-acd4a32578adb291b` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-acd4a32578adb291b | 2 |
| `worktree-ignored/cw-agent-ace149458131fd238` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ace149458131fd238 | 1 |
| `worktree-ignored/cw-agent-acf9710f446d4f547` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-acf9710f446d4f547 | 1 |
| `worktree-ignored/cw-agent-ad1242d0f209161bf` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ad1242d0f209161bf | 1 |
| `worktree-ignored/cw-agent-ad13e24ccf536e543` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ad13e24ccf536e543 | 2 |
| `worktree-ignored/cw-agent-ad1a23b13d711e28d` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ad1a23b13d711e28d | 2 |
| `worktree-ignored/cw-agent-ad37f298f6ec6372d` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ad37f298f6ec6372d | 2 |
| `worktree-ignored/cw-agent-ad5e1155315c69a40` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ad5e1155315c69a40 | 1 |
| `worktree-ignored/cw-agent-ad6429d442ae81d73` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ad6429d442ae81d73 | 1 |
| `worktree-ignored/cw-agent-ad8739bd8f7e258f5` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ad8739bd8f7e258f5 | 1 |
| `worktree-ignored/cw-agent-adc83726a9917b84a` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-adc83726a9917b84a | 1 |
| `worktree-ignored/cw-agent-adcba637ca474f695` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-adcba637ca474f695 | 1 |
| `worktree-ignored/cw-agent-add060524ce5850b9` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-add060524ce5850b9 | 1 |
| `worktree-ignored/cw-agent-add1c4077afaf4291` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-add1c4077afaf4291 | 1 |
| `worktree-ignored/cw-agent-add95d5626dabcfed` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-add95d5626dabcfed | 1 |
| `worktree-ignored/cw-agent-adeac957acd1d6a66` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-adeac957acd1d6a66 | 1 |
| `worktree-ignored/cw-agent-adfc5496cb6645b7f` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-adfc5496cb6645b7f | 1 |
| `worktree-ignored/cw-agent-ae1205deb24274a9a` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ae1205deb24274a9a | 3 |
| `worktree-ignored/cw-agent-ae13111e6376da149` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ae13111e6376da149 | 2 |
| `worktree-ignored/cw-agent-ae4e242603aae8c5b` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ae4e242603aae8c5b | 1 |
| `worktree-ignored/cw-agent-ae72697ceb9121909` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-ae72697ceb9121909 | 1 |
| `worktree-ignored/cw-agent-aeac1644e6a8e7ce2` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aeac1644e6a8e7ce2 | 1 |
| `worktree-ignored/cw-agent-aeb60af5e00f9bc30` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aeb60af5e00f9bc30 | 1 |
| `worktree-ignored/cw-agent-aef54a79cc0a6958f` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aef54a79cc0a6958f | 1 |
| `worktree-ignored/cw-agent-aefa763748611c62d` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aefa763748611c62d | 7 |
| `worktree-ignored/cw-agent-aefce13ce05b00789` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-aefce13ce05b00789 | 4 |
| `worktree-ignored/cw-agent-af2dceff4f17de8c8` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-af2dceff4f17de8c8 | 1 |
| `worktree-ignored/cw-agent-af33735b37fd5bd18` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-af33735b37fd5bd18 | 1 |
| `worktree-ignored/cw-agent-af57471ece540c62a` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-af57471ece540c62a | 1 |
| `worktree-ignored/cw-agent-af6ad32c5853d907e` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-af6ad32c5853d907e | 1 |
| `worktree-ignored/cw-agent-af9b4bf1fffb25586` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-af9b4bf1fffb25586 | 2 |
| `worktree-ignored/cw-agent-afab730965af1d06e` | C:/Users/Opera/quotesdone/.claude/worktrees/agent-afab730965af1d06e | 1 |
| `worktree-ignored/main-checkout` | C:/Users/Opera/quotesdone | 705 |
| `worktree-ignored/qd-apply` | C:/Users/Opera/qd-apply | 1 |
| `worktree-ignored/qd-se-read` | C:/Users/Opera/qd-se-read | 1 |
| `worktree-ignored/qd-supready` | C:/Users/Opera/qd-supready | 1 |
| `worktree-ignored/quotesdone-W` | C:/Users/Opera/quotesdone/$W | 4 |

## Detached HEAD on no branch (1)

| ref | source | files vs merge-base | already on main | unique commits | description |
|---|---|---|---|---|---|
| `worktree-head/wt-1234` | C:/Users/Opera/wt-1234 | 4 | no: 4 of 4 files differ from main | 4 | Merge branch 'main' into ceo/privacy-policy-v1-6 |

## Stashes (26)

| ref | files | already on main | stash |
|---|---|---|---|
| `stash/00` | 1 | no: 1 of 1 files differ from main | WIP on it_engineer/a-knowledge-reload-keeps-unchanged-rows-multilingual-vectors: 9ba3184 it_engineer: #1496 applied - MANIFEST, pending note |
| `stash/01` | 12 | no: 12 of 12 files differ from main | WIP on (no branch): 1cc9efe customer_support: decision_points anchors the WhatsApp classifications on classifyDeps |
| `stash/02` | 5 | no: 5 of 5 files differ from main | WIP on (no branch): 9124d9a sales_engineer: the conversation rehearsal lets the agent reach its summary (14 turns, not 9) and marks a capped |
| `stash/03` | 5 | no: 5 of 5 files differ from main | WIP on (no branch): 1b3e9fb sales_engineer: review of #1352 - lock_timeout 3s before the ALTERs, Arabic phrases registered, quote_review_mes |
| `stash/04` | 4 | no: 4 of 4 files differ from main | WIP on (no branch): 41bc32f it_engineer: the knowledge rerank measurement script, with breaker guard, spend ceiling, 2-lane throttle and abo |
| `stash/05` | 11 | no: 10 of 11 files differ from main | WIP on (no branch): 9b30699 it_engineer: schema mirror records the cred_site_error_ingest secret name (repo and database agree was red) |
| `stash/06` | 1 | no: 1 of 1 files differ from main | WIP on it_engineer/release-1259-applied: 2f98778 it_engineer: an Arabic question is ranked in the space that reads Arabic (#1259) |
| `stash/07` | 2 | no: 2 of 2 files differ from main | WIP on (no branch): 82681dd ceo: the CEO runs the company on the founder's year-one targets (#923) |
| `stash/08` | 4 | no: 4 of 4 files differ from main | WIP on (no branch): 2898498 it_engineer: a closed seat_duty finding says whether the duty recovered or was disabled (review of #901) |
| `stash/09` | 2 | no: 2 of 2 files differ from main | WIP on audits-part-1-what-was-measured: eafe6fe The two audits, part 1: everything the readers measured before the session limit |
| `stash/10` | 1 | no: 1 of 1 files differ from main | WIP on worktree-agent-a81dfe2da0058337b: a06780a Merge pull request #525 from ahmadmhdnabilalzain-bot/integration-2026-09-06e |
| `stash/11` | 0 | yes | WIP on fix/a-row-id-is-not-a-key: c08cbf5 A row id is not a key: one contact form, two customer cases |
| `stash/12` | 1 | no: 1 of 1 files differ from main | WIP on phase-d/os-surface-honest-numbers: b5aa02b The error surface was two standing conditions, repeated hourly |
| `stash/13` | 9 | no: 9 of 9 files differ from main | WIP on main: dadc7af Next-session prompt: finish what is pending (#287) |
| `stash/14` | 8 | no: 8 of 8 files differ from main | WIP on main: 045290a The backup outgrew its worker (#286) |
| `stash/15` | 6 | no: 6 of 6 files differ from main | WIP on main: a1c579d The hand-written map fell behind the spending (#285) |
| `stash/16` | 7 | no: 7 of 7 files differ from main | WIP on main: b6ec147 The spend guard told the founder his only ceiling was the alert itself (#284) |
| `stash/17` | 8 | no: 8 of 8 files differ from main | WIP on main: 4e48eeb The security audit trail was ninety percent one counter ticking (#283) |
| `stash/18` | 8 | no: 8 of 8 files differ from main | WIP on main: dff07cc The reflection budget counted what had finished and gated what was starting (#282) |
| `stash/19` | 8 | no: 8 of 8 files differ from main | WIP on main: 9a97866 Twenty thousand suppliers rated zero for work never offered (#281) |
| `stash/20` | 8 | no: 8 of 8 files differ from main | WIP on main: cdfd9e2 A literal project ref must never be promoted (#280) |
| `stash/21` | 7 | no: 7 of 7 files differ from main | WIP on main: 59c5a40 The supplier the matcher could not see (#279) |
| `stash/22` | 8 | no: 8 of 8 files differ from main | WIP on main: 9973e95 A recommendation that cannot say what it assumed (#278) |
| `stash/23` | 1 | no: 1 of 1 files differ from main | WIP on main: 64d374e The RFQ that arrived before its supplier existed (#277) |
| `stash/24` | 5 | no: 5 of 5 files differ from main | WIP on the-rfq-that-arrived-before-its-supplier-existed: 47dcac8 The RFQ waiting behind those two clicks lands on a real supplier |
| `stash/25` | 11 | no: 11 of 11 files differ from main | WIP on main: b23bd69 Row #5: migration for the repo, and a drift the replay caught |

## Local branches not on origin (265)

| ref | tip date | files vs merge-base | already on main | unique commits | PR | last commit |
|---|---|---|---|---|---|---|
| `branch/accountant-notice-kinds-after-648` | 2026-09-14 | 23 | no: 17 of 23 files differ from main | 5 | no PR | The founder's Supplier Agreement approval, in full, and his trade-licence ruling |
| `branch/accountant-reveal-rate-fail-closed` | 2026-10-13 | 6 | no: 6 of 6 files differ from main | 2 | #1378 merged | accountant: register the reviewed Arabic of reveal_rate_unavailable (same wording as stripe_checkout element_init, fathatan-first) |
| `branch/accountant-stage2-reveal-contract` | 2026-10-13 | 1 | no: 1 of 1 files differ from main | 0 | #1372 merged | accountant: stage2 S10/S13/S14 call the reveal, chat and rating APIs by their real contracts |
| `branch/accountant/consumer-safe-charges` | 2026-09-24 | 41 | no: 34 of 41 files differ from main | 3 | #919 merged | accountant: no buyer pays a card fee (Cabinet Res. 66/2023 Art. 5(3)); the licence number leaves marketing copy |
| `branch/accountant/every-pdf-we-issue-is-on-our-template` | 2026-09-21 | 20 | no: 17 of 20 files differ from main | 2 | #775 merged | accountant: a PAID invoice only for a settled payment; a refund prints REFUNDED with amount, date and net; unpaid is refused in EN/AR (revie |
| `branch/accountant/interest-never-above-nine` | 2026-09-30 | 5 | no: 5 of 5 files differ from main | 3 | #1161 closed | accountant: re-run the pull request checks on the merged head |
| `branch/accountant/one-reveal-rate-reader` | 2026-10-13 | 9 | no: 4 of 9 files differ from main | 0 | #1388 merged | accountant: one fail-closed reveal-rate reader; main's edge typecheck is green again |
| `branch/accountant/t6-legal-compliance-calendar` | 2026-10-05 | 3 | no: 3 of 3 files differ from main | 1 | #1177 closed | accountant: the legal calendar carries the trade licence, TDRA NOL, VAT threshold watch and Terms versions (T6) |
| `branch/accountant/the-open-account-facts-of-21-september` | 2026-09-21 | 4 | no: 2 of 4 files differ from main | 1 | #784 merged | accountant: record the open account facts of 21 Sep (WhatsApp name, provider caps, .ae expiry) |
| `branch/audits-part-1-what-was-measured` | 2026-09-14 | 9 | no: 8 of 9 files differ from main | 3 | #568 merged | Code graph refreshed after the registered-language change |
| `branch/ceo/every-ceo-answer-is-cross-checked` | 2026-10-19 | 4 | no: 2 of 4 files differ from main | 0 | #1585 merged | ceo: every CEO answer is cross-checked - the cross-family reviewer gets thinking headroom |
| `branch/ceo/every-seat-carries-its-own-operating-facts` | 2026-10-19 | 22 | no: 16 of 22 files differ from main | 8 | #1567 merged | Merge remote-tracking branch 'origin/main' into ceo/every-seat-carries-its-own-operating-facts |
| `branch/ceo/improvement-sweep-settles-in-one-run` | 2026-09-30 | 7 | no: 4 of 7 files differ from main | 1 | #1175 merged | ceo: the improvement sweep closes before it proposes and settles in one run; one open improvement per target; the weekly review counts what  |
| `branch/ceo/privacy-policy-v1-6` | 2026-10-12 | 4 | no: 3 of 4 files differ from main | 5 | #1234 merged | ceo: privacy 1.6 states that an unfinished sign-up is deleted in full after 30 minutes (ruling 1181, EN and AR) |
| `branch/customer_support/held-reply-names-open-question` | 2026-10-19 | 3 | yes | 2 | #1577 merged | customer_support: held reply is the sales engineer's on the portal chat; no raw key reaches the model; fallback described exactly |
| `branch/customer-support/a-cut-off-answer-is-never-shown` | 2026-10-13 | 3 | no: 2 of 3 files differ from main | 3 | #1360 merged | customer_support: the output-ceiling note moves above the call so the widget's call still names its subject within the check's window (revie |
| `branch/customer-support/a-stated-reveal-fee-says-what-is-not-added` | 2026-10-13 | 10 | no: 8 of 10 files differ from main | 9 | #1356 merged | customer_support: Arabic letters in the fee-check matchers are written as \u escapes (house rule; review of #1356) |
| `branch/customer-support/arabic-faq-no-card-fee` | 2026-10-12 | 3 | no: 3 of 3 files differ from main | 0 | #1323 merged | customer_support: the Arabic FAQ adds no card fee and states the v14 non-response charge |
| `branch/customer-support/arabic-faq-tanwin-reviewed` | 2026-10-12 | 4 | no: 2 of 4 files differ from main | 0 | #1329 merged | customer_support: the Arabic FAQ writes the tanwin fathatan-first, and its lines are reviewed |
| `branch/customer-support/chat-answers-the-question` | 2026-10-13 | 5 | no: 5 of 5 files differ from main | 4 | #1346 merged | customer_support: the 3% base is the final quoted price after any discount, excluding VAT (ruling 1208) |
| `branch/customer-support/conversation-replies-are-model-written` | 2026-10-12 | 50 | no: 31 of 50 files differ from main | 13 | #1335 merged | customer_support + sales_engineer: a replayed answer reaches a person only through aiReply's guard; the rehearsal measures with aiReply's ow |
| `branch/customer-support/replies-see-photos-and-log-their-attempts` | 2026-10-13 | 20 | no: 13 of 20 files differ from main | 3 | #1342 merged | customer_support: chat_images test uses a fake project ref (no hard-coded production ref) |
| `branch/customer-support/reply-chain-parallel` | 2026-10-12 | 3 | no: 3 of 3 files differ from main | 0 | #1322 merged | customer_support: the plain-language rewrite runs beside the independent check, not after it |
| `branch/customer-support/revert-widget-concurrency` | 2026-10-12 | 6 | no: 4 of 6 files differ from main | 0 | #1327 merged | customer_support: revert #1318 and #1322 - running reply chains side by side kills the widget worker |
| `branch/customer-support/visitor-chat-en-latency` | 2026-10-12 | 3 | no: 3 of 3 files differ from main | 2 | #1318 merged | customer_support: review of #1318 - the beside composition is one helper, never rejects, and its count is tested |
| `branch/customer-support/widget-stream-and-answer-cache` | 2026-10-12 | 40 | no: 27 of 40 files differ from main | 13 | #1330 merged | customer_support: the figure check reads number words to the millions and fee figures after subscription/price/cost |
| `branch/dep1027` | 2026-09-28 | 1 | no: 1 of 1 files differ from main | 0 | no PR | it_engineer: merge main (carries #982) into #1027 |
| `branch/dep1028` | 2026-09-28 | 10 | no: 10 of 10 files differ from main | 0 | no PR | it_engineer: merge main (carries #982) into #1028 |
| `branch/dep1029` | 2026-09-28 | 11 | no: 11 of 11 files differ from main | 1 | no PR | it_engineer: merge main into #1029 |
| `branch/dep1030` | 2026-09-28 | 2 | no: 2 of 2 files differ from main | 1 | no PR | it_engineer: merge main (carries #982) into #1030 |
| `branch/dep1031` | 2026-09-28 | 3 | no: 2 of 3 files differ from main | 2 | no PR | it_engineer: merge main (carries #982) into #1031 |
| `branch/dep1032` | 2026-09-28 | 2 | no: 2 of 2 files differ from main | 0 | no PR | it_engineer: merge main (carries #982) into #1032 |
| `branch/dep1033` | 2026-09-28 | 2 | no: 2 of 2 files differ from main | 1 | no PR | it_engineer: merge main (carries #982) into #1033 |
| `branch/dep1034` | 2026-09-28 | 4 | no: 4 of 4 files differ from main | 2 | no PR | it_engineer: the app builds on Tailwind 4 (#1034) |
| `branch/fix-1176` | 2026-10-05 | 4 | no: 1 of 4 files differ from main | 2 | no PR | sales_engineer: the licence-in-force item no longer asks to renew a licence never uploaded (review of #1176) |
| `branch/fix-1368` | 2026-10-13 | 26 | no: 22 of 26 files differ from main | 3 | no PR | sales_engineer: FAQ 610 names the reveal fee رسوم الكشف; verdict fails if 609/610 still say رسوم الاطلاع (supersedes #13 |
| `branch/fix/five-prod-checks-1006` | 2026-10-06 | 5 | no: 3 of 5 files differ from main | 0 | #1242 merged | sales_engineer: the drawing ceiling budget reads the median of three runs, not one wall-clock sample |
| `branch/fix1054` | 2026-09-29 | 4 | no: 3 of 4 files differ from main | 2 | no PR | it_engineer: register fn_invite_placement_finding as a relay of the placement settle verdict (#1054) |
| `branch/int5-merge` | 2026-10-19 | 320 | no: 1 of 320 files differ from main | 101 | no PR | it_engineer: the library check holds the guarded readers (no legacy reader redefined here); mirror carries round 5's seat-duty schedules |
| `branch/it_engineer/apply-1260` | 2026-10-19 | 8 | no: 7 of 8 files differ from main | 1 | #1583 merged | it_engineer: ruling-1260 file applied with founder:1260; MANIFEST + mirror |
| `branch/it_engineer/apply-1479-bookkeeping` | 2026-10-19 | 33 | no: 12 of 33 files differ from main | 10 | #1493 merged | it_engineer: the probe's Arabic customer line is reviewed (one register entry) |
| `branch/it_engineer/apply-1496-bookkeeping` | 2026-10-19 | 35 | no: 10 of 35 files differ from main | 2 | #1529 merged | it_engineer: a probe keeps its pending note and stays out of the MANIFEST (pending XOR MANIFEST) |
| `branch/it_engineer/apply-1566-bookkeeping` | 2026-10-19 | 23 | no: 10 of 23 files differ from main | 0 | #1568 merged | it_engineer: #1566 applied - 13 files live, packs loaded; MANIFEST + mirror |
| `branch/it_engineer/browser-walk` | 2026-10-07 | 1 | no: 1 of 1 files differ from main | 4 | #1270 merged | Merge remote-tracking branch 'origin/main' into it_engineer/browser-walk |
| `branch/it_engineer/customer-register-never-lists-a-fixture` | 2026-10-12 | 3 | yes | 0 | #1309 merged | it_engineer: the customer register never lists a fixture |
| `branch/it_engineer/dependency-check-ruling-1254` | 2026-10-19 | 1 | yes | 0 | #1589 merged | it_engineer: the dependency duty check asserts ruling 1254 - no advisory reaches the founder, a high one goes to the ceo |
| `branch/it_engineer/dropbox-tree-repair` | 2026-10-12 | 3 | no: 3 of 3 files differ from main | 5 | #1284 merged | it_engineer: the repair moves only what the founder's ruling counts, refuses on any mismatch, and reports a half-done move |
| `branch/it_engineer/every-attachment-is-read` | 2026-10-12 | 29 | no: 17 of 29 files differ from main | 7 | #1289 merged | customer_support: re-review of #1289 - the fence escapes every angle bracket, and a stranger's read slot is claimed before the read |
| `branch/it_engineer/every-fix-of-21-september-has-a-check-that-fails-if-it-returns` | 2026-09-21 | 22 | no: 19 of 22 files differ from main | 1 | #779 merged | it_engineer: every fix of 21 September has a check that fails if its cause returns (founder instruction 573) |
| `branch/it_engineer/fix-integration-3-damage` | 2026-10-19 | 5 | no: 2 of 5 files differ from main | 1 | #1531 merged | it_engineer: merge origin/main into #1531 (keep the rebuilt ruling-1260 file) |
| `branch/it_engineer/fn-email-sendable-both-overloads-one-file` | 2026-10-06 | 4 | no: 3 of 4 files differ from main | 2 | #1261 merged | it_engineer: schema mirror records the backup_prune_mode secret name (prune armed after inspected dry run) |
| `branch/it_engineer/idor-product-match-gate` | 2026-10-19 | 2 | no: 1 of 2 files differ from main | 0 | #1481 merged | it_engineer: a supplier's product_match is gated to an enquiry they were matched to (IDOR) |
| `branch/it_engineer/integration-3` | 2026-10-19 | 223 | no: 69 of 223 files differ from main | 121 | #1496 merged | it_engineer: the later read of a stored upload has a deadline (timedFetch, 120 s); outbound fetches back at the baseline of 68 |
| `branch/it_engineer/integration-4` | 2026-10-19 | 247 | no: 50 of 247 files differ from main | 92 | #1566 merged | it_engineer: merge #1565 (ceo/seat-audit-1003) into integration-4 |
| `branch/it_engineer/integration-5` | 2026-10-19 | 323 | no: 28 of 323 files differ from main | 96 | #1578 merged | it_engineer: Dynblocks.dwg take-off pinned at 77 rows. #1523/#1532 now count its 7 dynamic variants and 20 nested inserts, and the test asse |
| `branch/it_engineer/knowledge-exam-off-the-tick` | 2026-09-24 | 2 | no: 2 of 2 files differ from main | 1 | #947 closed | it_engineer: the knowledge exam runs on its own pg_cron clock; inside the 8 s duty tick it cancelled every duty from 10:15Z (applied, PROBE  |
| `branch/it_engineer/ledger-760-e2e-sweep` | 2026-09-29 | 7 | no: 4 of 7 files differ from main | 2 | #1048 merged | Merge remote-tracking branch 'origin/main' into it_engineer/ledger-760-e2e-sweep |
| `branch/it_engineer/manifest-lists-the-sign-in-file-once` | 2026-10-06 | 1 | no: 1 of 1 files differ from main | 0 | #1267 merged | it_engineer: MANIFEST lists the sign-in code file once |
| `branch/it_engineer/mirror-after-1337` | 2026-10-12 | 2 | no: 2 of 2 files differ from main | 0 | #1344 merged | it_engineer: release - #1337 applied (trg_quote_quality), mirror recorded |
| `branch/it_engineer/one-session-per-harness` | 2026-10-06 | 1 | no: 1 of 1 files differ from main | 1 | #1254 merged | it_engineer: the customer_api check reuses one admin session instead of minting one per run |
| `branch/it_engineer/pdpl-me-routines-are-authenticated-on-purpose` | 2026-10-06 | 1 | no: 1 of 1 files differ from main | 0 | #1262 merged | it_engineer: the three PDPL self-service routines are authenticated-executable on purpose, reviewed by name |
| `branch/it_engineer/pin-sharp-for-ocr-test` | 2026-09-28 | 1 | no: 1 of 1 files differ from main | 0 | #1021 merged | it_engineer: merge origin/main into this branch |
| `branch/it_engineer/playbook-check-counts-what-reverify-acts-on` | 2026-10-13 | 1 | no: 1 of 1 files differ from main | 0 | #1414 merged | it_engineer: the playbook check counts the handoffs fn_it_loop_reverify actually fills |
| `branch/it_engineer/registration-day-holds-under-a-surge` | 2026-09-21 | 8 | no: 7 of 8 files differ from main | 1 | #786 merged | it_engineer: registration day holds under a surge — honest code sends, per-account SMS cap, OTP duty judges unused codes |
| `branch/it_engineer/release-1311-applied` | 2026-10-12 | 3 | no: 2 of 3 files differ from main | 0 | #1315 merged | it_engineer: release - #1311 applied (aluminum alias), MANIFEST and mirror recorded |
| `branch/it_engineer/release-1345-applied` | 2026-10-12 | 4 | no: 3 of 4 files differ from main | 0 | #1347 merged | it_engineer: release - #1345 applied (no invite count cap), MANIFEST and mirror recorded |
| `branch/it_engineer/run4-walk-and-kyc-race` | 2026-10-13 | 3 | no: 2 of 3 files differ from main | 1 | no PR | it_engineer: run 71b75b60 - Save waits for the kyc read; the walk opens the quoted card, confirms the reveal, attaches on a fresh composer |
| `branch/it_engineer/run4-walk-and-kyc-race-v2` | 2026-10-13 | 4 | no: 2 of 4 files differ from main | 2 | #1375 merged | Merge branch 'it_engineer/run4-walk-and-kyc-race-v2' of https://github.com/ahmadmhdnabilalzain-bot/quotesdone into it_engineer/run4-walk-and |
| `branch/it_engineer/section-4-says-a-probe-returns-a-row` | 2026-09-21 | 2 | no: 1 of 2 files differ from main | 0 | #762 merged | merge main |
| `branch/it_engineer/sharp-0-35-5` | 2026-10-06 | 2 | no: 2 of 2 files differ from main | 0 | #1263 merged | it_engineer: sharp 0.35.5 (GHSA-wq5f-xc86-pv6w, high) - npm audit in 'typecheck the app' is red on every PR |
| `branch/it_engineer/stage2-run4-cleanup-and-judge` | 2026-10-13 | 1 | no: 1 of 1 files differ from main | 0 | #1374 merged | it_engineer: stage2 run 71b75b60 - cleanup removes the run's id-named PDFs and comparison cache; the judge knows rulings 1207/1208 and sees  |
| `branch/it_engineer/stage2-s07-price-ex-vat` | 2026-10-12 | 1 | no: 1 of 1 files differ from main | 0 | #1354 merged | it_engineer: stage2 S07 confirms price_ex_vat with the quote's own amount |
| `branch/it_engineer/stage2-teardown-fk-judge-facts` | 2026-10-12 | 2 | no: 2 of 2 files differ from main | 0 | #1350 merged | it_engineer: stage2 run 1c94fa6a - teardown follows every foreign key to leads/customers; DDL audit is not demo data; the judge knows the pu |
| `branch/it_engineer/the-customer-portal-reads-cleanly-in-both-languages` | 2026-09-21 | 22 | no: 16 of 22 files differ from main | 0 | #771 merged | merge origin/main (#766) |
| `branch/it_engineer/the-engineer-decides-the-unsure-knowledge` | 2026-09-21 | 2 | no: 1 of 2 files differ from main | 0 | #774 merged | it_engineer: the engineer decides the unsure knowledge — codes the UAE uses stay, the rest goes (founder instruction 570) |
| `branch/it_engineer/the-foreign-bulk-leaves-the-knowledge-library-permanently` | 2026-09-21 | 7 | no: 6 of 7 files differ from main | 1 | #769 merged | it_engineer: the foreign bulk leaves the knowledge library permanently — the purge is built, nothing is deleted |
| `branch/it_engineer/the-forty-open-it-findings-of-21-september` | 2026-09-21 | 36 | no: 28 of 36 files differ from main | 3 | #785 merged | it_engineer: the founder's decisions of 21 September close PITR, the receipt alarms and the recorded caps (instruction 585) |
| `branch/it_engineer/the-it-failures-of-18-to-21-september-and-their-fixes` | 2026-09-21 | 13 | no: 8 of 13 files differ from main | 1 | #767 merged | it_engineer: the IT failures of 18-21 September were 11 causes, and the five that paged the founder are fixed at their root |
| `branch/it_engineer/the-last-traces-of-bank-details-negotiations-and-the-network-map` | 2026-09-21 | 6 | no: 5 of 6 files differ from main | 1 | #777 merged | it_engineer: the last traces of bank details, negotiations and the network map leave (instructions 525/526/527) |
| `branch/it_engineer/the-purge-census-slice-fits-the-gateway` | 2026-09-21 | 1 | no: 1 of 1 files differ from main | 0 | #781 merged | it_engineer: the purge census slice is 20,000 ids so each request fits the gateway |
| `branch/it_engineer/the-purge-plan-sums-its-own-column` | 2026-09-21 | 1 | no: 1 of 1 files differ from main | 0 | #789 merged | it_engineer: the purge plan sums its own column |
| `branch/it_engineer/the-seed-must-satisfy-the-mandatory-six` | 2026-09-18 | 0 | yes | 1 | #733 merged | Merge remote-tracking branch 'origin/main' into it_engineer/the-seed-must-satisfy-the-mandatory-six |
| `branch/it_engineer/the-supplier-portal-tells-one-truth-in-every-panel` | 2026-09-21 | 37 | no: 30 of 37 files differ from main | 3 | #788 merged | it_engineer: graphify update after the supplier-portal one-truth fixes |
| `branch/it_engineer/the-truncate-marker-fix-is-applied` | 2026-09-22 | 3 | no: 2 of 3 files differ from main | 1 | #823 closed | it_engineer: the truncate-marker restore fix (#799) is applied (PROBE OK) |
| `branch/it_engineer/the-two-it-emails-of-21-september` | 2026-09-21 | 4 | no: 3 of 4 files differ from main | 3 | #776 merged | it_engineer: a back-off earned under the v1 consumer does not hide rows from v2 |
| `branch/it_engineer/ubicloud-runners` | 2026-10-06 | 13 | no: 13 of 13 files differ from main | 0 | #1233 merged | it_engineer: every workflow job runs on Ubicloud (ubicloud-standard-2), one repo variable reverts it |
| `branch/it_engineer/unfinished-signups-and-one-signature` | 2026-10-12 | 11 | no: 7 of 11 files differ from main | 5 | #1292 merged | it_engineer: the purge waits out an upload in flight, lists every record, never blocks on a bad row, and takes an invited lead's sign-up fil |
| `branch/it_engineer/unreviewed-research-never-reaches-external` | 2026-10-19 | 22 | no: 14 of 22 files differ from main | 9 | #1569 merged | it_engineer: unreviewed research never reaches an external audience in seat retrieval |
| `branch/it_engineer/us-codes-and-laws-leave-the-library-unless-they-name-the-uae` | 2026-09-21 | 4 | no: 4 of 4 files differ from main | 0 | #772 merged | it_engineer: US standards and laws leave the knowledge library unless they cite the UAE (founder instruction 535) |
| `branch/it_engineer/vercel-config-snapshot` | 2026-10-12 | 6 | no: 2 of 6 files differ from main | 2 | #1296 merged | it_engineer: the Vercel check reads no scripts/sql text (it reads the live database; the probe proves the Dropbox folder) |
| `branch/it_engineer/walk-held-intake-and-overflow-leaves` | 2026-10-13 | 5 | no: 4 of 5 files differ from main | 3 | #1361 merged | it_engineer: the identity fence also needs app_metadata.e2e_run, set only by the service role; fails closed |
| `branch/it-eng/sandbox2-browser-walk-fixes` | 2026-10-12 | 4 | no: 2 of 4 files differ from main | 2 | #1337 merged | it_engineer: MANIFEST carries only the one new file line; openNewRequest keeps its doc comment |
| `branch/it-engineer/bulk-ml-embeds-run-locally` | 2026-10-12 | 2 | yes | 0 | #1297 merged | it_engineer: bulk multilingual embeds run in-process, not one embed_ml worker per text (Supabase cached egress 970/250 GB) |
| `branch/it-engineer/canonical-bodies-for-the-applied-sanctions-routines` | 2026-09-18 | 2 | no: 2 of 2 files differ from main | 1 | #758 closed | it_engineer: the applied sanctions routines get the canonical file they never had |
| `branch/it-engineer/deploy-functions-serialised` | 2026-10-13 | 1 | no: 1 of 1 files differ from main | 3 | #1400 merged | it_engineer: a last-deployed SHA that is not an ancestor fails the run instead of keeping a narrow base |
| `branch/it-engineer/deploy-parity-full-source` | 2026-10-13 | 2 | no: 2 of 2 files differ from main | 0 | #1399 merged | it_engineer: deploy parity compares every deployed source file with main, not 25 sampled strings |
| `branch/it-engineer/deploy-parity-originals` | 2026-10-13 | 4 | yes | 0 | #1410 merged | it_engineer: deploy parity compares the original source and reads 78/78 MATCH |
| `branch/it-engineer/matrix-breaker-test-probe-shape` | 2026-10-12 | 1 | no: 1 of 1 files differ from main | 0 | #1343 merged | it_engineer: the matrix breaker test trips the breaker as a named probe that raises (main red after #1328) |
| `branch/it-engineer/matrix-drift-12-oct` | 2026-10-12 | 2 | no: 2 of 2 files differ from main | 2 | #1328 merged | it_engineer: the breaker excuse covers a breaker open under an hour, not a day (review nit) |
| `branch/it-engineer/matrix-probe-hold-literal` | 2026-10-12 | 1 | no: 1 of 1 files differ from main | 0 | #1334 merged | it_engineer: the matrix probe's breaker reset spells no hold reason (main red after #1328) |
| `branch/it-engineer/nightly-window-leak-and-honest-badge` | 2026-10-18 | 11 | no: 7 of 11 files differ from main | 3 | #1427 closed | it_engineer: #1427 - the CAD journey runs the full request path with the AI on in its own capped window (founder ruling 18 Oct) |
| `branch/it-engineer/phone-check-seeds-verified` | 2026-10-13 | 1 | yes | 2 | #1377 merged | it_engineer: the phone check reads the local token only with QD_LIVE_CHECK=1 |
| `branch/it-engineer/phone-needs-verified-row` | 2026-10-13 | 3 | no: 2 of 3 files differ from main | 2 | #1362 merged | it_engineer: a_phone_cannot_select_an_account never leaves its rehearsal window open |
| `branch/it-walk-fixes` | 2026-10-12 | 4 | no: 4 of 4 files differ from main | 2 | #1321 merged | it_engineer: browser_walk.mjs parses again (one export on openNewRequest); the walk's test now runs node --check |
| `branch/it/apply-1335-escalate` | 2026-10-13 | 4 | no: 3 of 4 files differ from main | 0 | #1379 merged | it_engineer: #1335's escalation applied (fn_reason_held_escalate, PROBE OK); MANIFEST + mirror |
| `branch/it/apply-1348-demo-purge` | 2026-10-13 | 10 | no: 9 of 10 files differ from main | 0 | #1381 merged | it_engineer: #1348's demo-purge routines applied (22 routines, PROBE OK; purge not run); MANIFEST + mirror |
| `branch/it/apply-1352-knowledge-gap` | 2026-10-13 | 6 | no: 5 of 6 files differ from main | 0 | #1383 merged | it_engineer: #1352's knowledge-gap sweep applied (3 routines, PROBE OK); MANIFEST + mirror |
| `branch/it/apply-1364-1368` | 2026-10-13 | 4 | no: 2 of 4 files differ from main | 0 | #1386 merged | it_engineer: #1364 discount columns and #1368 FAQ fee base applied (PROBE OK both); MANIFEST + mirror |
| `branch/it/apply-1380-sonnet` | 2026-10-13 | 4 | no: 3 of 4 files differ from main | 0 | #1390 merged | it_engineer: #1380's model routes applied (4 conversation classes on Sonnet 5.5 > Gemini 3.8 Flash); MANIFEST + mirror |
| `branch/it/apply-1389-cap` | 2026-10-13 | 6 | no: 5 of 6 files differ from main | 0 | #1402 merged | it_engineer: #1389 applied at 04:00 UTC - founder weekly invite cap (PROBE OK; caps 20/30/50 read back); MANIFEST + mirror |
| `branch/it/apply-1394-scope` | 2026-10-13 | 3 | no: 2 of 3 files differ from main | 0 | #1397 merged | it_engineer: #1394 applied - ai_gateway joins five fn.* credential scopes (PROBE OK); MANIFEST + mirror |
| `branch/it/apply-1395-cost` | 2026-10-13 | 5 | no: 4 of 5 files differ from main | 0 | #1403 merged | it_engineer: #1395 applied - unknown model cost booked unknown; 3 model_rate rows; 28 rows re-priced, 138 streamed rows unknown; MANIFEST +  |
| `branch/it/apply-price-brief` | 2026-10-12 | 6 | no: 5 of 6 files differ from main | 0 | #1357 merged | it_engineer: #1330's price brief applied (fn_price_brief, PROBE OK); MANIFEST + mirror |
| `branch/it/demo-purge-1199` | 2026-10-13 | 11 | no: 2 of 11 files differ from main | 12 | #1348 merged | it_engineer: #1348 registers the Arabic Dropbox path it lists (an archived test supplier's folder name, verbatim) |
| `branch/it/demo-purge-1199-w` | 2026-10-13 | 11 | no: 6 of 11 files differ from main | 6 | no PR | it_engineer: #1348 review - real-looking names held off the Dropbox list until the founder answers |
| `branch/it/demo-purge-1199-w2` | 2026-10-13 | 11 | no: 2 of 11 files differ from main | 11 | no PR | it_engineer: #1348 - lead 143027 (a real sourced company) is never demo or purged; the pdpl check catches every form |
| `branch/it/duty-pause-expiry` | 2026-10-05 | 6 | no: 5 of 6 files differ from main | 1 | #1188 merged | it_engineer: a duty paused over 7 days is a finding (critical for money/security), proved by a real skipped tick; export probe is the exact  |
| `branch/it/e2e-fixture-jwt-refresh` | 2026-10-19 | 4 | no: 2 of 4 files differ from main | 2 | #1572 merged | Merge remote-tracking branch 'origin/it/e2e-fixture-jwt-refresh' into it/e2e-fixture-jwt-refresh |
| `branch/it/held-licence-portal-1230` | 2026-10-13 | 4 | no: 2 of 4 files differ from main | 0 | #1406 merged | it_engineer: the portal tells a supplier held for the licence why, and how long is left (ruling 1230) |
| `branch/it/held-supplier-notice-1230` | 2026-10-13 | 4 | no: 3 of 4 files differ from main | 2 | #1398 merged | it_engineer: the clearer-licence ask goes out on every decision short of approved, with what else is missing (#1398 review) |
| `branch/it/integration-run5-fixes-19-oct` | 2026-10-19 | 99 | no: 51 of 99 files differ from main | 65 | #1479 merged | it_engineer: register #1472's redefined delivery watch as a reviewed tracking file |
| `branch/it/knowledge-rerank` | 2026-10-12 | 11 | no: 11 of 11 files differ from main | 3 | #1331 closed | it_engineer: the knowledge rerank measurement script, with breaker guard, spend ceiling, 2-lane throttle and abort after 3 empty replies |
| `branch/it/ml-arabic-retrieval` | 2026-10-12 | 252 | no: 27 of 252 files differ from main | 13 | #1259 merged | sales_engineer: full native Arabic body for the 75 entries of 25 more market packs that failed only in Arabic; written blind to the question |
| `branch/it/model-registry-sync` | 2026-10-05 | 5 | no: 5 of 5 files differ from main | 1 | #1187 closed | it_engineer: the model registry follows the catalogue by a daily sync; the price check asserts the sync is fresh (follow-up 28) |
| `branch/it/no-own-txn-matched-supplier` | 2026-10-12 | 1 | yes | 0 | #1351 merged | it_engineer: every_matched_supplier file drops its own begin/commit (main red on the transaction-lines check; apply_sql wraps it, no behavio |
| `branch/it/prelaunch-security-a` | 2026-10-06 | 41 | no: 23 of 41 files differ from main | 5 | #1245 merged | Merge remote-tracking branch 'origin/it/prelaunch-security-a' into it/prelaunch-security-a |
| `branch/it/prelaunch-security-b` | 2026-10-06 | 10 | no: 3 of 10 files differ from main | 3 | #1246 merged | it_engineer: the resilience cron route fails closed and forwards no key without CRON_SECRET (review of #1246) |
| `branch/it/real-profiles-background` | 2026-10-13 | 27 | no: 17 of 27 files differ from main | 8 | no PR | WIP it_engineer: background read of supplier profiles and catalogues (in progress) |
| `branch/it/register-two-settings-keys` | 2026-10-13 | 1 | no: 1 of 1 files differ from main | 0 | #1411 merged | it_engineer: register conversation_retention_mode and document_expiry_ai as settings in the integration registry |
| `branch/it/resilience-detach-slow-steps` | 2026-10-12 | 12 | no: 4 of 12 files differ from main | 4 | #1305 merged | it_engineer: M2 check accepts the auth gate that returns liveness before anything else |
| `branch/it/safe-replay` | 2026-09-30 | 66 | no: 26 of 66 files differ from main | 2 | #1158 merged | it_engineer: one implementation - #1152's inline guard and the invitations check's strip give way to safe_replay |
| `branch/it/supplier-portal-english-only` | 2026-10-12 | 7 | no: 2 of 7 files differ from main | 0 | #1324 merged | it_engineer: the supplier portal is always English - no عربي toggle, no Arabic from /ar or leads.locale (ruling 1008) |
| `branch/it/supplier-readiness-1230` | 2026-10-13 | 5 | no: 3 of 5 files differ from main | 0 | #1393 merged | it_engineer: a supplier with no company yet is shown the registration form, not "Something went wrong" (ruling 1230) |
| `branch/it/supplier-surfaces-english-only` | 2026-10-13 | 11 | no: 9 of 11 files differ from main | 2 | #1409 merged | it_engineer: #1409 review - Arabic letters in a supplier file fail unless on the gated list |
| `branch/kb/brief-contract-arabic-supplier-materials` | 2026-10-12 | 29 | no: 9 of 29 files differ from main | 6 | no PR | sales_engineer: review of #1352 - lock_timeout 3s before the ALTERs, Arabic phrases registered, quote_review_messages read by its real roles |
| `branch/knowledge/arabic-buyer-pairs-native` | 2026-10-12 | 4 | no: 4 of 4 files differ from main | 0 | #1320 merged | sales_engineer: native Arabic title and body for the 8 trade entries behind the Arabic buyer pairs below 0.35 under the post-load model (fac |
| `branch/marketing/continuous-lead-sourcing` | 2026-10-12 | 10 | no: 4 of 10 files differ from main | 4 | #1304 merged | marketing: lead sourcing reserves its budget before it spends; the CI registries name it |
| `branch/marketing/invite-cap-schedule-1231` | 2026-10-13 | 3 | no: 2 of 3 files differ from main | 4 | #1389 merged | marketing: the lane restart keeps its day-1 line; its base is bounded by the cap already set (#1389) |
| `branch/marketing/seo-indexing` | 2026-10-19 | 1 | no: 1 of 1 files differ from main | 0 | #1484 merged | marketing: /en and /en/* redirect permanently (308), not 307, so Search Console folds them into the unprefixed page |
| `branch/op954` | 2026-09-24 | 11 | no: 9 of 11 files differ from main | 6 | no PR | Merge remote-tracking branch 'origin/main' into op954 |
| `branch/pr1161` | 2026-09-30 | 5 | no: 5 of 5 files differ from main | 1 | no PR | accountant: no supplier is charged interest above 9% a year, v14 signers included |
| `branch/pr1162` | 2026-09-30 | 16 | no: 11 of 16 files differ from main | 2 | no PR | sales_engineer: the export-registry check reads a pending DROP TABLE, as it reads a pending CREATE TABLE |
| `branch/pr1163` | 2026-09-30 | 3 | no: 2 of 3 files differ from main | 0 | no PR | it_engineer: the CEO's monthly strategy memo runs on the seat clock; its pg_cron job is unscheduled |
| `branch/pr1164` | 2026-09-30 | 3 | no: 3 of 3 files differ from main | 1 | no PR | marketing: no marketing or AI-visibility text names a supplier, on every surface that publishes |
| `branch/pr1210m` | 2026-10-19 | 6 | no: 3 of 6 files differ from main | 2 | no PR | Merge 7168c04cb50a6062f1b2607593647884af312a57 into c117ca57a1a635544a152d59ae5802113daac451 |
| `branch/pr1234` | 2026-10-06 | 4 | no: 4 of 4 files differ from main | 4 | no PR | ceo: company_facts carries privacy 1.6; the registry file holds no transaction of its own |
| `branch/pr1289` | 2026-10-12 | 29 | no: 20 of 29 files differ from main | 5 | no PR | it_engineer: the two new reads carry a deadline (every_outbound_fetch_has_a_timeout back to its baseline of 70) |
| `branch/pr1314` | 2026-10-12 | 3 | no: 1 of 3 files differ from main | 0 | no PR | sales_engineer: a single-trade request is matched on its category, and an Arabic emirate on its English name |
| `branch/pr1326` | 2026-10-12 | 5 | no: 5 of 5 files differ from main | 0 | no PR | sales_engineer: a licence or profile with no text layer has its model-read activities read for trades on every upload path (ruling 1177) |
| `branch/pr1330` | 2026-10-12 | 40 | no: 27 of 40 files differ from main | 13 | no PR | customer_support: the figure check reads number words to the millions and fee figures after subscription/price/cost |
| `branch/pr1335` | 2026-10-13 | 18 | no: 11 of 18 files differ from main | 8 | no PR | it_engineer: restore arabic_reviewed_strings.json (a hook had replaced it with log text) - main's file plus #1335's 7 hashes |
| `branch/pr1346` | 2026-10-12 | 4 | no: 4 of 4 files differ from main | 2 | no PR | customer_support: review of #1346 - the fallback plan is verified cross-family, and the supplier steps name the real buttons |
| `branch/pr1346b` | 2026-10-13 | 5 | no: 5 of 5 files differ from main | 3 | no PR | customer_support: FACTS_CUSTOMER follows ruling 1207, and its one Arabic label is registered as reviewed |
| `branch/pr1346c` | 2026-10-13 | 5 | no: 5 of 5 files differ from main | 4 | no PR | customer_support: the 3% base is the final quoted price after any discount, excluding VAT (ruling 1208) |
| `branch/pr1353` | 2026-10-12 | 3 | no: 3 of 3 files differ from main | 1 | no PR | sales_engineer: a blank licence image yields no fields; a new licence never keeps the old expiry |
| `branch/pr1353b` | 2026-10-12 | 5 | no: 4 of 5 files differ from main | 2 | no PR | sales_engineer: a new licence whose expiry is unread is held as licence_expiry_unread, never approved (review of #1353) |
| `branch/pr1362-rev` | 2026-10-13 | 2 | no: 1 of 2 files differ from main | 1 | no PR | it_engineer: a phone signs in only to a row whose phone and email are verified |
| `branch/pr1362-rev2` | 2026-10-13 | 3 | no: 2 of 3 files differ from main | 2 | no PR | it_engineer: a_phone_cannot_select_an_account never leaves its rehearsal window open |
| `branch/pr1376-review` | 2026-10-13 | 9 | no: 5 of 9 files differ from main | 2 | no PR | sales_engineer: release rule 7 refuses a lapsed validity, as the hold desk does (stacked on #1371) |
| `branch/pr1377` | 2026-10-13 | 1 | no: 1 of 1 files differ from main | 1 | no PR | it_engineer: the shared-number check seeds verified rows, and proves the verified one is chosen |
| `branch/pr1377b` | 2026-10-13 | 1 | yes | 2 | no PR | it_engineer: the phone check reads the local token only with QD_LIVE_CHECK=1 |
| `branch/pr1378r` | 2026-10-13 | 5 | no: 5 of 5 files differ from main | 1 | no PR | accountant: the reveal rate is read from pricing_config or the reveal is refused, never guessed |
| `branch/pr1387` | 2026-10-13 | 3 | no: 3 of 3 files differ from main | 1 | no PR | sales_engineer: the customer never receives the supplier's own quotation file, only our template (ruling 1220) |
| `branch/pr1387b` | 2026-10-13 | 4 | no: 2 of 4 files differ from main | 2 | no PR | sales_engineer: review of #1387 - every customer surface is scanned; has_original and the raw-file reads are gone (rulings 1228, 1229) |
| `branch/pr1407r` | 2026-10-13 | 10 | no: 10 of 10 files differ from main | 1 | no PR | sales_engineer: one cached brief for every language and channel, on the 1-hour cache tier |
| `branch/pr1407s` | 2026-10-13 | 10 | no: 8 of 10 files differ from main | 2 | no PR | sales_engineer: review of #1407 - both FAQ languages ride in the one brief, and a refused ttl is retried once without it |
| `branch/pr1420` | 2026-10-19 | 2 | no: 2 of 2 files differ from main | 2 | no PR | it_engineer: keep squawk-cli at ^2.66 (2.68 flags migration 20260815050000); lockfile resolves 2.66.0 |
| `branch/pr1493` | 2026-10-19 | 31 | no: 12 of 31 files differ from main | 3 | no PR | it_engineer: drop the notifications exemption (#1497 is the fix); a seat clock asks a demo subject once (pending) |
| `branch/pr1577` | 2026-10-19 | 3 | yes | 2 | no PR | customer_support: held reply is the sales engineer's on the portal chat; no raw key reaches the model; fallback described exactly |
| `branch/pr1583` | 2026-10-19 | 18 | no: 9 of 18 files differ from main | 4 | no PR | it_engineer: #1583 carries #1584's applied file too (MANIFEST in apply order, mirror from production) so neither PR's database check waits o |
| `branch/pr761` | 2026-09-21 | 22 | no: 12 of 22 files differ from main | 2 | no PR | sales_engineer: #761 finished — the CI trap, the rating rule as tested code, and a ranking that reads real quotes |
| `branch/pr878` | 2026-09-23 | 3 | no: 2 of 3 files differ from main | 1 | no PR | customer_support: an edited FAQ answer is re-embedded, and a quote is not a fee |
| `branch/qd-1567-book` | 2026-10-19 | 29 | no: 21 of 29 files differ from main | 10 | no PR | it_engineer: #1567 + #1569 applied (Option A: live customer leak); MANIFEST + mirror |
| `branch/r1342` | 2026-10-12 | 20 | no: 14 of 20 files differ from main | 2 | no PR | customer_support: the customer portal chat takes a photo too; one shared browser resize for both chats |
| `branch/r1356` | 2026-10-12 | 9 | no: 9 of 9 files differ from main | 1 | no PR | customer_support: a reply that states the reveal fee must also say no card fee and no VAT, or the model rewrites it |
| `branch/r1356b` | 2026-10-13 | 9 | no: 9 of 9 files differ from main | 2 | no PR | customer_support: any 3% fee statement must NEGATE the card fee and the VAT in so many words (review of #1356) |
| `branch/r1356c` | 2026-10-13 | 9 | no: 7 of 9 files differ from main | 3 | no PR | customer_support: only a 3% FEE sentence asks for 'no card fee, no VAT', and the negation must be of the card fee / VAT itself |
| `branch/r1356d` | 2026-10-13 | 9 | no: 7 of 9 files differ from main | 4 | no PR | customer_support: the 3%-fee exemptions match whole words only, and a refund is no exemption (review of #1356) |
| `branch/r1356e` | 2026-10-13 | 10 | no: 8 of 10 files differ from main | 5 | no PR | customer_support: a supplier's quotation stands as stated; the no card fee / no VAT line is our 3% fee's only (ruling 1207); the cost scenar |
| `branch/r1356f` | 2026-10-13 | 10 | no: 8 of 10 files differ from main | 6 | no PR | customer_support: a bare fee word is our fee unless tied to the supplier, and عرض counts only as a quotation (review of #1356) |
| `branch/r1356g` | 2026-10-13 | 10 | no: 8 of 10 files differ from main | 7 | no PR | customer_support: a sentence about the supplier or its quote, with none of our markers, keeps its fee and VAT as stated (review of #1356, ru |
| `branch/r1356h` | 2026-10-13 | 10 | no: 8 of 10 files differ from main | 8 | no PR | customer_support: the supplier shields a sentence only as its subject, 'you pay' marks our fee, and a negation counts only in the claim's ow |
| `branch/r1356i` | 2026-10-13 | 10 | no: 8 of 10 files differ from main | 9 | no PR | customer_support: Arabic letters in the fee-check matchers are written as \u escapes (house rule; review of #1356) |
| `branch/r1360` | 2026-10-13 | 11 | no: 8 of 11 files differ from main | 7 | no PR | customer_support: the widget's output ceiling comment says what the gateway gives (visitor_chat route capped at 900; review of #1360) |
| `branch/r1360b` | 2026-10-13 | 11 | no: 8 of 11 files differ from main | 8 | no PR | customer_support: the widget's output ceiling comment says what the gateway gives (visitor_chat route capped at 900; review of #1360) |
| `branch/r1360c` | 2026-10-13 | 11 | no: 8 of 11 files differ from main | 9 | no PR | customer_support: the widget's output ceiling comment says what the gateway gives (visitor_chat route capped at 900; review of #1360) |
| `branch/r1360d` | 2026-10-13 | 11 | no: 8 of 11 files differ from main | 10 | no PR | customer_support: the widget's output ceiling comment says what the gateway gives (visitor_chat route capped at 900; review of #1360) |
| `branch/r944` | 2026-09-24 | 17 | no: 13 of 17 files differ from main | 2 | no PR | Merge remote-tracking branch 'origin/main' into r944 |
| `branch/rebuild/phase-c-execution-kernel` | 2026-08-17 | 1 | no: 1 of 1 files differ from main | 1 | #428 merged | $(cat <<'EOF' |
| `branch/rel-1014` | 2026-09-28 | 2 | no: 1 of 2 files differ from main | 1 | no PR | merge main into #1014 |
| `branch/rel-1026` | 2026-09-28 | 6 | no: 3 of 6 files differ from main | 1 | no PR | Merge remote-tracking branch 'origin/main' into rel-1026 |
| `branch/rel-1245` | 2026-10-06 | 41 | no: 23 of 41 files differ from main | 5 | no PR | Merge branch 'main' into it/prelaunch-security-a |
| `branch/rel-995` | 2026-09-28 | 7 | no: 5 of 7 files differ from main | 2 | no PR | Merge remote-tracking branch 'origin/main' into rel-995 |
| `branch/release/batch-b-28-sep` | 2026-09-28 | 124 | no: 74 of 124 files differ from main | 59 | no PR | it_engineer: #966 ends with a verdict row (routines present and closed, table RLS-on with a policy) |
| `branch/restore-five-document-functions` | 2026-09-09 | 12 | no: 11 of 12 files differ from main | 1 | #549 closed | agent: sales_engineer — five document functions come back, and the two lies they left behind stop |
| `branch/review-854c` | 2026-09-23 | 13 | no: 11 of 13 files differ from main | 3 | no PR | Merge remote-tracking branch 'origin/main' into review-854c |
| `branch/rv1191` | 2026-10-05 | 6 | no: 4 of 6 files differ from main | 1 | no PR | sales_engineer: a customer with live quotes and no reveal is nudged on day 2 and day 7, with help to compare (1027) |
| `branch/rv1195` | 2026-10-05 | 6 | no: 6 of 6 files differ from main | 2 | no PR | sales_engineer: a pasted byte-order mark is not Arabic (review of #1195) |
| `branch/rv1311` | 2026-10-12 | 6 | no: 5 of 6 files differ from main | 4 | no PR | sales_engineer: the trades.from_text pin names the call as it now stands (codeWords, read through fn_norm_trades) |
| `branch/rv1313` | 2026-10-12 | 3 | no: 3 of 3 files differ from main | 2 | no PR | sales_engineer: only a legal-entity suffix, e-mail, web address or phone number marks a name line |
| `branch/rv1330` | 2026-10-12 | 40 | no: 27 of 40 files differ from main | 12 | no PR | customer_support: figure check reads every way a fee is written; held-road checks rewritten to ruling 1196; test traffic named; rate limit a |
| `branch/rv1333` | 2026-10-12 | 16 | no: 5 of 16 files differ from main | 7 | no PR | ceo: the host registry check treats the agent brief's URLs as citations only while the file is provably data |
| `branch/rv1348` | 2026-10-12 | 10 | no: 6 of 10 files differ from main | 3 | no PR | it_engineer: #1348 registers the four Arabic lines of fn_marketing_reputation it redefines (text unchanged, verbatim from production) |
| `branch/rv1352` | 2026-10-12 | 29 | no: 9 of 29 files differ from main | 6 | no PR | sales_engineer: review of #1352 - lock_timeout 3s before the ALTERs, Arabic phrases registered, quote_review_messages read by its real roles |
| `branch/rv1352d` | 2026-10-13 | 19 | no: 7 of 19 files differ from main | 5 | no PR | sales_engineer: the knowledge-gap routines pin search_path and revoke execute in the house form the duty-file check reads |
| `branch/sales_engineer/a-catalogue-is-read-as-a-catalogue-without-a-model` | 2026-09-21 | 35 | no: 27 of 35 files differ from main | 2 | #780 merged | sales_engineer: graphify update after the catalogue reader |
| `branch/sales_engineer/brief-and-style-reach-every-reply` | 2026-10-13 | 8 | no: 7 of 8 files differ from main | 4 | #1382 merged | sales_engineer: rebased on #1380 - the playbooks and the style are asserted in its single cached sys_stable block, once |
| `branch/sales_engineer/chat-runs-on-sonnet-5-5` | 2026-10-13 | 9 | no: 8 of 9 files differ from main | 0 | #1380 merged | sales_engineer: every conversation reply runs on Sonnet 5.5 with Gemini behind (ruling 1219) |
| `branch/sales_engineer/conversation-playbooks` | 2026-10-13 | 19 | no: 7 of 19 files differ from main | 5 | #1352 merged | sales_engineer: the knowledge-gap routines pin search_path and revoke execute in the house form the duty-file check reads |
| `branch/sales_engineer/customer-never-gets-raw-quote` | 2026-10-13 | 4 | no: 2 of 4 files differ from main | 2 | #1387 merged | sales_engineer: review of #1387 - every customer surface is scanned; has_original and the raw-file reads are gone (rulings 1228, 1229) |
| `branch/sales_engineer/dropbox-backup-gate` | 2026-10-12 | 11 | no: 5 of 11 files differ from main | 5 | #1280 merged | sales_engineer: the customer and supplier folder is the NAMED one, never a "Customer (<id8>)" placeholder |
| `branch/sales_engineer/every-document-offers-view-download-replace-remove-and-reads-its-own-dates` | 2026-09-21 | 16 | no: 13 of 16 files differ from main | 1 | #764 merged | sales_engineer: every document offers View / Download / Replace / Remove, and reads its own expiry by code (instruction 524) |
| `branch/sales_engineer/every-matched-supplier-is-invited` | 2026-10-12 | 7 | no: 5 of 7 files differ from main | 2 | #1345 merged | sales_engineer: S07 expects every capable aluminium supplier invited and quoting (no count cap) |
| `branch/sales_engineer/four-trades-authored-to-technical-director-depth` | 2026-09-21 | 11 | no: 1 of 11 files differ from main | 0 | #770 merged | sales_engineer: four gap trades authored to technical-director depth as rule seeds (LV switchboards, structural steel, fire alarm, chillers) |
| `branch/sales_engineer/one-cached-brief-for-every-language` | 2026-10-13 | 10 | no: 8 of 10 files differ from main | 2 | #1407 merged | sales_engineer: review of #1407 - both FAQ languages ride in the one brief, and a refused ttl is retried once without it |
| `branch/sales_engineer/one-job-number-and-a-bilingual-inquiry` | 2026-09-21 | 25 | no: 23 of 25 files differ from main | 1 | #790 merged | Merge remote-tracking branch 'origin/main' into sales_engineer/one-job-number-and-a-bilingual-inquiry |
| `branch/sales_engineer/photographed-quote-tables-are-read` | 2026-10-13 | 2 | no: 2 of 2 files differ from main | 3 | #1396 merged | sales_engineer: review of #1396 - the Arabic digit range and separators are written as \u escapes (house rule) |
| `branch/sales_engineer/privacy-self-service` | 2026-10-12 | 10 | no: 4 of 10 files differ from main | 6 | #1273 merged | sales_engineer: privacy.ts header no longer says there is no status routine (release review of #1273) |
| `branch/sales_engineer/profile-read-fixes` | 2026-10-19 | 39 | no: 21 of 39 files differ from main | 16 | #1483 open | sales_engineer: a vision, mission or goal statement names no trade (N09: "envisions providing ... Pipeline work") |
| `branch/sales_engineer/profile-read-fixes-v2` | 2026-10-19 | 14 | no: 14 of 14 files differ from main | 11 | no PR | Merge remote-tracking branch 'origin/main' into sales_engineer/profile-read-fixes-v2 |
| `branch/sales_engineer/profile-title-name-proposes-nothing` | 2026-10-12 | 2 | no: 1 of 2 files differ from main | 0 | #1341 merged | sales_engineer: a "<name> - Company Profile" title proposes no trade, whoever uploads it |
| `branch/sales_engineer/quote-review-in-background` | 2026-10-13 | 8 | no: 3 of 8 files differ from main | 2 | #1413 merged | sales_engineer: review of #1413 - STALE_MS 480 s, and one review at a time by claim |
| `branch/sales_engineer/rehearsal-lets-the-agent-close` | 2026-10-13 | 1 | no: 1 of 1 files differ from main | 0 | #1384 merged | sales_engineer: the conversation rehearsal lets the agent reach its summary (14 turns, not 9) and marks a capped conversation |
| `branch/sales_engineer/review-photos` | 2026-10-05 | 9 | no: 9 of 9 files differ from main | 2 | #1193 open | sales_engineer: review photos reload with the page and never lose a concurrent upload |
| `branch/sales_engineer/rule7-validity` | 2026-10-13 | 10 | no: 5 of 10 files differ from main | 3 | #1376 merged | sales_engineer: release rule 7 refuses a lapsed validity, as the hold desk does (stacked on #1371) |
| `branch/sales_engineer/s07-quotes-from-the-invited-suppliers` | 2026-10-12 | 1 | no: 1 of 1 files differ from main | 0 | #1340 merged | sales_engineer: S07 quotes from the suppliers the request invited, and proves the per-trade cap on the one left out |
| `branch/sales_engineer/s07-s09` | 2026-10-13 | 8 | no: 3 of 8 files differ from main | 3 | #1371 merged | sales_engineer: the validity reader's Arabic month patterns are \u escapes; the validity label is registered as reviewed |
| `branch/sales_engineer/stream-usage-is-logged` | 2026-10-13 | 3 | no: 1 of 3 files differ from main | 2 | #1391 merged | sales_engineer: review of #1391 - a missing usage chunk is unknown (null), never zero, and never a failure |
| `branch/sales_engineer/supplier-chat-attachments` | 2026-10-13 | 7 | no: 7 of 7 files differ from main | 0 | #1385 merged | sales_engineer: suppliers attach a photo or document in the quotation chat; every file is read (ruling 1177) |
| `branch/sales_engineer/supplier-chat-reaches-the-model` | 2026-10-13 | 3 | no: 1 of 3 files differ from main | 0 | #1394 merged | sales_engineer: the supplier quotation chat may reach the model - ai_gateway joins five fn.* credential scopes |
| `branch/sales_engineer/t3-quote-templates` | 2026-10-05 | 7 | no: 7 of 7 files differ from main | 1 | #1179 closed | sales_engineer: suppliers save and reuse quote templates — structure only, never a price (T3) |
| `branch/sales_engineer/the-chat-answers-the-question-it-was-asked` | 2026-09-21 | 11 | no: 8 of 11 files differ from main | 4 | #783 merged | sales_engineer: the fn_sales_assist probe deletes its own gap rows before its own tasks; the Arabic timeline FAQ is recorded as applied |
| `branch/sales_engineer/the-inquiry-travels-as-a-pdf-and-the-supplier-sees-its-own-quotation` | 2026-09-21 | 11 | no: 10 of 11 files differ from main | 1 | #765 merged | sales_engineer: the inquiry travels as a PDF and the supplier sees its own quotation |
| `branch/sales_engineer/the-quotation-review-reads-what-the-supplier-sent-2` | 2026-09-21 | 29 | no: 23 of 29 files differ from main | 2 | #773 merged | sales_engineer: the quotation review reads what the supplier sent, and every open point closes from the chat |
| `branch/sales_engineer/unknown-tokens-stay-null` | 2026-10-13 | 4 | no: 1 of 4 files differ from main | 4 | #1395 merged | sales_engineer: #1395 - the re-price skips an already re-priced row, so its suffix is never appended twice |
| `branch/sales_engineer/verified-badges` | 2026-10-05 | 8 | no: 7 of 8 files differ from main | 1 | #1183 closed | sales_engineer: verified badges - licence verified and documents complete, shown to the supplier with what earns each and on anonymised quot |
| `branch/sales_engineer/vision-trades` | 2026-10-12 | 5 | no: 5 of 5 files differ from main | 0 | #1326 merged | sales_engineer: a licence or profile with no text layer has its model-read activities read for trades on every upload path (ruling 1177) |
| `branch/sales-engineer-aluminium-trade` | 2026-10-12 | 5 | no: 4 of 5 files differ from main | 3 | #1311 merged | sales_engineer: #1311 review - the word rule is gated to work lines, read from the database, and named for what it is |
| `branch/sales-engineer-licence-415` | 2026-10-12 | 7 | no: 4 of 7 files differ from main | 2 | #1317 merged | sales_engineer: supplier-docs accepts the Word and PowerPoint profiles process_docs now reads |
| `branch/sales-engineer-name-lines-propose-nothing` | 2026-10-12 | 3 | no: 3 of 3 files differ from main | 2 | #1313 merged | sales_engineer: only a legal-entity suffix, e-mail, web address or phone number marks a name line |
| `branch/sales-engineer-spec-helper` | 2026-10-05 | 4 | no: 4 of 4 files differ from main | 1 | #1186 merged | sales_engineer: a held request asks its missing specs one plain question at a time, multiple choice plus "not sure" |
| `branch/sales-engineer-t3-profile-score` | 2026-10-05 | 4 | no: 2 of 4 files differ from main | 1 | #1176 closed | sales_engineer: the supplier sees a profile score out of 100 and a ranked list of fixes, each linking to the tab that fixes it (T3) |
| `branch/sales-engineer/document-intake-accuracy-suite` | 2026-10-12 | 26 | no: 22 of 26 files differ from main | 5 | #1285 merged | Merge remote-tracking branch 'origin/main' into sales-engineer/document-intake-accuracy-suite |
| `branch/sales-engineer/intake-held-says-why` | 2026-10-12 | 3 | no: 3 of 3 files differ from main | 2 | #1336 merged | sales_engineer: the gateway failure is per request and reaches only the harness, never a customer |
| `branch/sales-engineer/ruling-1207-portal-and-faq` | 2026-10-13 | 26 | no: 23 of 26 files differ from main | 2 | #1368 merged | sales_engineer: the portal shows the price, discount and VAT as stated and the fee basis; the FAQ states the 1207/1208 fee base |
| `branch/sales-engineer/ruling-1207-supplier-stated-terms` | 2026-10-13 | 21 | no: 16 of 21 files differ from main | 6 | #1364 merged | sales_engineer: #1364 review - the stated-price PDF test reads QD_DEMO_PDF_OUT only when env access is granted (CI runs without --allow-env) |
| `branch/sales-engineer/supplier-docs-read-deterministically` | 2026-09-15 | 19 | no: 16 of 19 files differ from main | 4 | #697 merged | sales_engineer: merge main; schema mirror after applying the supplier documents propose trades file |
| `branch/sales-engineer/t2-request-tracker` | 2026-10-05 | 6 | no: 3 of 6 files differ from main | 2 | #1185 closed | sales_engineer: a revealed or hired single quote is not stalled at Compare; quotes end a specs hold (review of #1185) |
| `branch/se-demo-match-fix` | 2026-10-12 | 3 | no: 1 of 3 files differ from main | 0 | #1314 merged | sales_engineer: a single-trade request is matched on its category, and an Arabic emirate on its English name |
| `branch/se-intake-repeat-question` | 2026-10-12 | 7 | no: 7 of 7 files differ from main | 2 | #1319 merged | sales_engineer: an unanswered spec stops being asked after 3 turns and the request is HELD with a sales_engineer handoff, never released |
| `branch/se-licence-arabic-low` | 2026-10-13 | 12 | no: 2 of 12 files differ from main | 7 | #1373 merged | sales_engineer: the retired-model scan skips only supabase/functions/_shared/vendor (third-party bytes, sha256-pinned) |
| `branch/se-licence-unreadable` | 2026-10-12 | 5 | no: 4 of 5 files differ from main | 3 | #1353 merged | sales_engineer: a new licence whose expiry is unread is held as licence_expiry_unread, never approved (review of #1353) |
| `branch/se/market-pack-broad-entries` | 2026-10-12 | 413 | no: 388 of 413 files differ from main | 8 | #1255 merged | sales_engineer: the 9 failing sizes entries open with how the trade is quoted and sold (blind rewrite, checked for added facts) |
| `branch/se/unsuffixed-name-lines` | 2026-10-12 | 6 | no: 5 of 6 files differ from main | 0 | #1325 merged | sales_engineer: a company name printed without a legal suffix no longer proposes a trade |
| `branch/sq-966` | 2026-09-28 | 9 | no: 7 of 9 files differ from main | 8 | no PR | #966 applied to production (release operator); MANIFEST lines added, pending notes removed, mirror regenerated |
| `branch/t4-contact-dedup` | 2026-10-05 | 5 | no: 2 of 5 files differ from main | 2 | #1197 closed | it_engineer: contact dedup review fixes - NULL never reads as demo, demo-ness judged on live members, one bad group cannot abort the duty, a |
| `branch/the-rfq-that-arrived-before-its-supplier-existed` | 2026-08-12 | 12 | no: 11 of 12 files differ from main | 5 | #277 merged | The RFQ waiting behind those two clicks lands on a real supplier |
| `branch/upd-1262` | 2026-10-06 | 1 | no: 1 of 1 files differ from main | 0 | no PR | Merge remote-tracking branch 'origin/main' into upd-1262 |
| `branch/wip-1023` | 2026-09-29 | 13 | no: 7 of 13 files differ from main | 1 | no PR | it_engineer: merge main into the portal cold load (#1023) |
| `branch/worktree-agent-a8ff802f1b3411199` | 2026-09-21 | 45 | no: 25 of 45 files differ from main | 1 | no PR | it_engineer: the founder removed the 3D environment, the network map, negotiations and bank details |
| `branch/worktree-agent-aa5b18e0983b7e4a5` | 2026-10-18 | 4 | no: 4 of 4 files differ from main | 2 | no PR | sales_engineer: next_question carries the slot key before a ready |
| `branch/worktree-agent-ab29a0f6fe1eda1d7` | 2026-09-28 | 3 | no: 3 of 3 files differ from main | 2 | no PR | customer_support: merge origin/main into this branch |
| `branch/worktree-agent-ac91f9e01debf627f` | 2026-09-18 | 17 | no: 10 of 17 files differ from main | 1 | #761 merged | sales_engineer: a customer can rate a supplier, and an Arabic date reads forwards |
| `branch/worktree-agent-ad7a3178595550264` | 2026-09-18 | 6 | no: 5 of 6 files differ from main | 1 | no PR | it_engineer: the tick runs what is stalest, not what is first in the list |
| `branch/zz-local-iter3` | 2026-10-19 | 12 | no: 6 of 12 files differ from main | 7 | no PR | customer_support: every adaptive conversation runs in the portal with its own account (ruling 1249: the homepage widget holds no job convers |

## Loose folders and files (3)

| ref | files | source |
|---|---|---|
| `loose-files` | 4067 | qd-deploy,qd-packs,qd-se-dwg-samples,qd-worktree-backup-20260728-194857,.claude/worktrees/agent-a4dd14af9fb107962 |
| `loose-files-2` | 24 | home-root qd-*.sh + C:/c/Users/Opera |
| `loose-files-3` | 43 | .claude/worktrees root files |

## Reading it back

```
git fetch origin 'refs/heads/archive/laptop-2026-10-26/*:refs/remotes/origin/archive/laptop-2026-10-26/*'
git show --stat origin/archive/laptop-2026-10-26/worktree/main-checkout
git checkout -b revive origin/archive/laptop-2026-10-26/branch/<name>~1   # ~1 = the original tip
```
