---
name: supplier-portal-waits-for-the-website-redesign
description: "9 Sep 2026 — the supplier portal rebuild is parked until the whole website design is upgraded. Do not start it, and do not build things whose only consumer is it."
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-09T03:39:28.181Z
---

Founder, 9 September 2026:

> "leave the supplier portal because it will take alot of time and i wanna do it later when we
> upgrade the whole design of the website."

Earlier the same day he had said it *needed* a full rebuild — *"the supplier portal need a full
rebuild so we will make sure that such details are collected properly"* — so this is a decision
about **sequencing**, not a change of mind about the portal being wrong.

## What this parks, and why the whole chain parks with it

The supplier side is one dependency chain, and the portal is its entry point:

```
supplier registers in the portal
  -> declares what work it actually does
     -> supplier_capabilities.confirmed_at is written
        -> fn_match_capability's FIRST gate passes
           -> an inquiry can match anyone at all
```

Measured 9 Sep: `supplier_capabilities` holds 15,305 rows and **0 have `confirmed_at`**, so
`fn_match_capability` returns the empty set for every possible query. `capability_agent` — the only
function that ever wrote that column — was deleted on 8 Sep.

**Do not rebuild `capability_agent` as a standalone.** Its only caller is `supplier_api`'s
`capability_state` / `capability_confirm`, which exist to serve the portal. Building it now means
building against a UI that is about to be replaced.

## What this does NOT park

The customer side, the CEO, the archive and the knowledge work are all independent and shipped:
the Sales Engineer seat, its knowledge and retrieval, matching as an action, the Dropbox tree,
compliance archival, the letterhead, the rating loop.

## The honest state to report while it is parked

There are **no registered suppliers** — all 22,264 rows in `leads` are scraped prospects, 0 verified,
and every category on them is `keyword_v1`, i.e. a guess from directory text rather than anything a
supplier said. So the marketplace cannot match, and that is a *consequence of a deliberate
sequencing decision*, not a defect to chase. Say so plainly rather than reporting matching as broken.

Related: [[payments-are-held-for-the-accountant-agent]] holds surfaces for future seats the same way.
