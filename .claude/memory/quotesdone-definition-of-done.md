---
name: quotesdone-definition-of-done
description: "On QuotesDone, \"fixed\" means deployed to Supabase and verified by measurement in the same turn — never reported as done and left to a later session."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 09417d0d-d206-4a76-81b2-5878d1e0a4cc
  modified: 2026-08-05T22:16:37.695Z
---

The founder's standard: the moment a fix is reported as done, it must already be **deployed, mitigated and verified**. Reporting a fix while the code sits uncommitted, unmerged, or undeployed is treated as a failure, because the same issue is then still live in Supabase next session.

**Why:** stated 6 Aug 2026 — "I don't wanna end up finishing stuff and assuming things are done and then the same issues are still existing in the supabase." Several prior sessions produced green gates over code that was never deployed, and a readiness gate that reported 13/13 while five changed functions were unverified on either project.

**How to apply:** finish each fix with commit → deploy → a measurement that would fail if the fix were absent. Prefer positive signatures (does the new code exist in the deployed bundle) over negative ones (has the old defect left) — `scripts/verify_deploy_parity.mjs` does this for Edge Functions on both projects. For the frontend, fetch the route's own bundle: Next.js code-splits, so the homepage chunks do not contain the portal, and probing `/` alone yields a false negative. Always include a control needle that should be present, to prove the right bundle was read.

Related: [[quotesdone-autonomy-and-staging-rules]]
