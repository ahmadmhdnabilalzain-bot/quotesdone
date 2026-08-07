# ROW #4 — CUSTOMER PORTAL, SCORED AGAINST PRODUCTION

```bash
node scripts/staging/verify_portal_blueprint.mjs                      # 147 checks, read-only, ~12 min
node scripts/staging/verify_portal_blueprint.mjs --json=out.json      # full evidence, unclipped
node scripts/staging/verify_portal_blueprint.mjs --only=twin-         # one prefix
```

## The run of 7 August 2026

| run | score | what changed |
|---|---|---|
| baseline | 104/147 (71%) | state at session start, reproduced twice |
| after the surface fix | 124/147 (84%) | instrument corrected; 21 gained, **1 lost** |
| after the build | 141/147 (96%) | §2 §3 §9 §10 §14 §16 §17 §21 shipped |
| after the regression fixes | **146/147 (99%)** | four of my own regressions closed |

0 errored checks and 0 denominator shortfall in every run. The remaining 1 is `disc-found-count`,
and no code closes it — see the last section.

## THE INSTRUMENT WAS MEASURING ONE FILE OF THE FIFTY-EIGHT ON THE SCREEN

Five section modules were written in parallel. Two computed the `/me` route's **import closure**;
two hardcoded `src/components/me/CustomerPortal.tsx` and scored that one file. They were the same
thing when they were written and stopped being the same thing when the portal was split into
`src/components/portal/*` — files `CustomerPortal.tsx` imports and mounts. One run therefore held
two different definitions of "the customer sees it".

`scripts/staging/portal_surface.mjs` now computes it once: **62 files, 24 customer-reachable edge
functions** — the same 24 the other modules already found. All five read it.

**This is not a weakening, and the run proves it.** Widening a surface makes "X is present" easier
AND "X is absent" harder. `mob-responsive-portal` went MET → MISSING on a `min-w-[380px]` that
forces a horizontal scrollbar on the 375px viewport §18 names, and one file could not see it.

Also fixed: `componentSrc()` replaces `slice(indexOf('function Messages('))`. `indexOf` returns -1
for a component that no longer exists, `slice(-1)` returns the file's last character, and every
count over it reads 0 — a missing component was indistinguishable from a present one with no
matches.

## A COMMENT QUOTING THE MARKUP IT REMOVED IS THAT MARKUP, TO A SCANNER

Three of the four regressions in the 141/147 run were caused by comments, not by code:

- a comment reading "WAS A `<table min-w-[380px]>`" kept both the table count and the fixed-width
  count non-zero after the table was gone;
- two comments naming `create_inquiry` took the "there is only one way to create an RFQ" count from
  1 to 3.

Describe what was removed; do not quote it.

The fourth was real: mapping `orderedModules()` straight into buttons left **no literal
`setView('documents')` anywhere**, so nothing could answer "where can this portal go" without
executing it — and it put the server's ranking into the DOM order, which is the tab order a
keyboard user gets. The buttons are written out again and flexbox `order` moves them, so the
layout is still per-customer and focus order is not.

## THE ONE REQUIREMENT NO CODE CAN CLOSE

`disc-found-count` — "Discovery returns how many suppliers were found."

Measured directly on production, 7 Aug 2026:

```
leads 20464 | verified 0 | approved 0 | self_registered 0 | claimed 0 | registration_submitted 0
                                                                          matchable 0
```

`fn_is_matchable` admits registered, verified suppliers. **Not one of the 20,464 is one.** The
estate is a scraped prospect list; nobody has registered. Every discovery query on production
answers zero, and it is answering honestly.

This closes when a real supplier completes registration and passes the licence gate. It does not
close by relaxing `fn_is_matchable` and it does not close by setting `verified` on scraped rows —
that would be inventing a supplier network, and it would put customers' RFQs in front of companies
who never agreed to receive them.

**It is the most important line in this document.** The marketplace has no supply side yet.
