---
name: green-pr-does-not-mean-deployable
description: "The PR edge-function typecheck is non-blocking by design, but the deploy job hard-fails on the same errors — so all-green PR checks can sit on top of a broken deploy."
metadata: 
  node_type: memory
  type: project
  originSessionId: 9e304e25-2c45-4722-877e-761ec03b37f2
  modified: 2026-08-11T10:14:41.318Z
---

`checks.yml`'s "typecheck the edge functions" job **never blocks**, and says so in its own comment:
"a failure here does not block, because 191 functions written over months will not all be clean on
day one and a permanently red gate teaches people to ignore gates."

But `deploy-functions.yml` has a step "Typecheck what is about to deploy" that runs
`deno check --no-lock --node-modules-dir=auto` over the functions it is about to push, and **exits 1**.

**Why:** the same errors are advisory in one workflow and fatal in the other. On 2026-08-11 this
left `deploy edge functions` red on main since 09:13 with "Found 19 errors" while every PR showed
all checks green. Edge function deploys were blocked and nothing said so.

**How to apply:** an all-green PR is not evidence that edge functions can ship. In the end-of-session
sweep, check the `deploy edge functions` workflow specifically — `gh run list --workflow="deploy edge
functions"` — not just the PR checks. Reproduce locally with
`deno check --no-lock --node-modules-dir=auto supabase/functions/<slug>/index.ts`.

Two of those 19 were real, not cosmetic: `pdf_native` served every raw PDF as `application/json`
because `...CORS` (which carries a Content-Type) was spread after it, and `kb_research_test` imported
a `llmWeb` that had been deleted, so it could not load at all. Deno 2 typing `Uint8Array` as
`Uint8Array<ArrayBufferLike>` accounts for most of the rest — cast at the `BodyInit`/`BufferSource`
use site, not on the function parameter, or one error becomes three at the call sites.

Related: [[end-of-session-log-sweep]]
