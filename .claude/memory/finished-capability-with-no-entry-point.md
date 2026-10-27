---
name: finished-capability-with-no-entry-point
description: "QuotesDone's other recurring root cause — a complete, hardened, deployed capability that nothing ever calls. Grep for the caller before assuming a feature is broken."
metadata: 
  node_type: memory
  type: project
  originSessionId: c74ced25-1096-4610-97ff-a1de3e88e117
  modified: 2026-08-12T10:58:48.195Z
---

The sibling of [[addressed-to-an-identity-nobody-models]], and it cost the company its entire
supplier funnel. There the message reached nobody; here **the door was built and no handle was
fitted**. Five instances found on 12 Aug 2026 alone:

1. **`capability_agent`** — owns `supplier_capabilities` end to end, validates against a controlled
   vocabulary, versions every confirmation. Sets `confirmed_at`, which `fn_match_capability` gates
   on. **No caller in `src/`, no cron.** So no supplier could ever be matched to anything —
   matching was never broken, the screen that unlocks it was never built.
2. **`claim_lookup`** — a whole edge function, security-hardened against enumeration on 19 Jul.
   No caller. Its own header states the outreach contract nobody implemented.
3. **`supplier_api` action `claim`** — accepts `body.t`, refuses conflicts, sets `claimed_by`.
   No caller.
4. **The invitation itself** — 62 emails told suppliers to use "the button below". `html` was empty
   and the body had no URL. The entry point was a sentence describing a link that did not exist.
5. **`/claim`** — the route `claim_lookup` documents (`quotesdone.com/claim?t=…`) returns **404**.
   The documented URL was never built.

**Why the watchers miss it:** nothing fails. The function deploys, typechecks, passes its
credential test and never runs. `fn_watch_failed_runs` sees no failure because there is no run.

**How to find it, cheaply:**
- `grep -rl "<function_name>" src/ supabase/functions/` — a capability whose only hits are its own
  file and migration history has no caller.
- `select … from cron.job where command ilike '%<fn>%'` — no cron either.
- For an edge function: zero rows in `agent_runs` / `ai_cost_log` for its name over a long window.

**Ask it as a question about the ENTRY POINT, not the capability:** not "does the confirm endpoint
work" but "what does a supplier click to reach it?" Every one of the five above passes the first
question and fails the second.

Also check the reverse of the founder's own lens ([[guarded-by-a-condition-that-cannot-occur]]):
that one asks whether a path ever ran; this one asks whether anything can ever *start* it.
