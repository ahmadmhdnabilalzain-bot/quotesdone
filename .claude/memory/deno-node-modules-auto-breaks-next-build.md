---
name: deno-node-modules-auto-breaks-next-build
description: "9 Nov 2026: running deno check/test with --node-modules-dir=auto in the repo rewrites the shared node_modules (node_modules/.deno, relinked packages); next build then loads a second React and fails prerendering /_global-error with 'Cannot read properties of null (reading useContext)'. Fix: rm -rf node_modules && npm ci. In a shared tree, run deno with --node-modules-dir=none."
metadata:
  type: feedback
  modified: 2026-11-09
---

**What happened (measured 9 Nov 2026, it_engineer).** Several agents ran `deno check`/`deno test` with
`--node-modules-dir=auto` (the flag `scripts/ci/local_gate.mjs` and `scripts/checks/run.mjs` use) in the main
checkout while another agent ran `next build`. `npm ls` showed `next -> ./node_modules/.deno/next@16.4.3/...`,
and the build failed on `/_global-error` with `TypeError: Cannot read properties of null (reading 'useContext')`.
That is the classic two-Reacts symptom; it looked like the last commit's fault and was not. After
`rm -rf node_modules && npm ci` the same HEAD built 522 pages, exit 0.

**How to apply.**
- A `next build` that fails with a null `useContext`/hook error right after deno ran in the same tree: reinstall
  (`rm -rf node_modules && npm ci`) before blaming the code.
- Parallel agents in one tree: deno with `--node-modules-dir=none` (it worked for every edge function on 9 Nov),
  and builds in an isolated copy with a hard-linked snapshot of a clean install (`cp -al node_modules ...`;
  a symlinked node_modules makes Turbopack report "Could not find the Next.js package").
- Docker sidesteps it: compose keeps node_modules in its own volume.
- Tracked as TD-14 in docs/engineering/tech-debt.md.
