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
7. **11 Nov 2026, later (it_engineer, branch `it_engineer-main-green-gate`): the gate now enforces all of this.**
   `node-tree` fails unless the worktree's own `node_modules` is lockfile-exact (`scripts/lib/lockfile_tree.mjs`, the
   same platform filter the builder uses); `next-build` runs `npm run build`; `tree-unchanged` fails if any step
   rewrote the tree. Every Deno call the gate makes, including `scripts/checks/run.mjs`'s suite and the checks that
   spawn Deno, uses `DENO_NPM_FLAGS` (`--no-lock --node-modules-dir=none`, `scripts/lib/deno_npm.mjs`); a runtime read
   inside a package (tesseract's wasm) is granted on `denoNpmCache()`. Guard:
   `scripts/checks/the_gate_certifies_the_tree_that_ships.test.mjs`.
8. **A check rewrote a lockfile-exact tree within the hour.** `legal_pdfs_have_no_overlapping_text.test.mjs` ran
   `scripts/legal/pdf_layout.ts` (imports `npm:pdfjs-dist@4.10.38`) with `=auto`; afterwards the website's
   `pdfjs-dist` 6.5.438 was a symlink to 4.10.38 and `node_modules/.deno` existed. Any `deno --node-modules-dir=auto`
   anywhere in a worktree corrupts that worktree's tree; the detector says which packages moved.
9. **The old tree hid a red step.** Dependabot #1875 locked `squawk-cli` 2.70.0, which adds `ban-drop-constraint`; the
   gate's Deno-layout tree still ran 2.66.0, so `migration-lint` passed. On the lockfile tree it failed on the
   replace-a-constraint statement in `20260815050000_phase_a_organization_closure.sql`, now ignored at that statement.
10. **`deno.lock` is gone** (TD-31): CLI 2.110's `--use-api` deploy never reads or uploads it (a dry bundle to a
    loopback stand-in for the API: byte-identical uploads with and without it). Point the CLI at a loopback server
    with `--profile supabase-local` (it calls `http://localhost:8080`), never with `SUPABASE_API_URL` (ignored).

