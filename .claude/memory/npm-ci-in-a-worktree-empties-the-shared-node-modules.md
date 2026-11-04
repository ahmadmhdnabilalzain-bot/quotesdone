---
name: npm-ci-in-a-worktree-empties-the-shared-node-modules
description: "27 Oct 2026: agent worktrees symlink node_modules to the main checkout; `npm ci` inside a worktree wiped the shared folder (0 entries) and every gate's typecheck went red. Install only in the main checkout."
metadata:
  type: feedback
  modified: 2026-10-27
---

At 19:56 on 27 Oct the release operator ran `npm ci` inside its worktree to run a combined gate. That worktree's
`node_modules` was a symlink to `/home/user/quotesdone/node_modules`, so `npm ci` emptied the shared folder.
Every other worktree linked to it lost its dependencies: `typecheck` failed, and one gate misreported
"764 live vs 754 committed tables". It was fixed with `npm ci --prefix /home/user/quotesdone`, which restored 201 entries.

**Why:** `npm ci` deletes `node_modules` before it installs, and it follows the symlink.

**How to apply:** never run `npm ci`/`npm install` inside a worktree whose `node_modules` is a symlink. Install in the
main checkout, or give the worktree its own real `node_modules`. If a gate suddenly fails `typecheck` across
unrelated branches, check `ls node_modules | wc -l` first.
