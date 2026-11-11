---
name: the-gate-tree-is-not-the-lockfile
description: "11 Nov 2026: the shared node_modules every gate links to (/tmp/claude-0/gate-1876/node_modules) is Deno's layout, written by the gate's own --node-modules-dir=auto steps: 13 of 215 packages differ from package-lock.json and sharp is the vulnerable 0.34.5 despite the ^0.35.5 override. To test a lockfile (a Dependabot PR) with 750 MB free, build a lockfile-exact tree by hard links: scripts/ci/node_modules_from_lockfile.mjs. Also: main was red on 8 offline checks the gate's --skip=npm-test hides; diff the offline suite against main."
metadata:
  type: project
  modified: 2026-11-11
---

**Measured 11 Nov 2026 (it_engineer, technical due-diligence review).** Extends
[[deno-node-modules-auto-breaks-next-build]].

1. **The gate's tree is not the lockfile.** `/tmp/claude-0/gate-1876/node_modules` has `node_modules/.deno/` and its
   top-level packages are symlinks into it. Against `package-lock.json`: 202 same, 13 differ (supabase-js 2.119 vs
   2.118, motion 14.11 vs 14.9, pdfjs 6.5 vs 6.4, ...), because Deno resolves `^` ranges afresh, and it ignores npm
   `overrides`, so `sharp` is 0.34.5 (GHSA-wq5f-xc86-pv6w, high) where the override pins ^0.35.5. Vercel installs from
   the lockfile, so production is not affected; the gate certifies a different tree. TD-24.
2. **Testing a lockfile without 2 GB of disk.** `scripts/ci/node_modules_from_lockfile.mjs <lock> <store> <out>`
   hard-links each locked package out of the Deno store and downloads only what is absent (sha512-checked). ~0 MB plus
   the missing packages; 217 of 217 top-level packages matched the lockfile. Build it INSIDE the worktree (Turbopack
   refuses a node_modules whose real path is outside the project). Never `npm install` or `deno ... =auto` into it:
   the files are hard links into the shared store.
3. **`next build` with no disk:** `ln -s /dev/shm/x .next` (tmpfs, 16 GB) and `NODE_PATH=$PWD/node_modules`, or the
   PostCSS worker (it runs from the build directory) cannot find `@tailwindcss/postcss`. Output is ~400 MB.
4. **Deno type checks do not need the node_modules at all:** `deno check --no-lock --node-modules-dir=none` over all
   78 functions passes from a tmpfs copy of `supabase/functions` plus `package.json` (reads the global Deno cache).
5. **`main` can be red while every gate table is green.** At 5d20a57eb, every `scripts/checks/*.test.mjs` run with no
   token gave 570 pass, 8 fail; the gate runs as `--offline --skip=npm-test`, which is where they live. Before saying
   a branch is clean, run the offline suite on a pristine `origin/main` worktree (tmpfs: `git worktree add --detach
   /dev/shm/x origin/main`) and on the branch, and diff per file. TD-26.
6. **otp-race in a cloud session:** with `TMPDIR` set to the root-only scratchpad the gate's own initdb fails; start a
   cluster as the postgres user in `/dev/shm` and pass `QD_OTP_RACE_PG` ([[the-otp-race-step-runs-on-a-throwaway-postgres-in-the-cloud-container]]).
