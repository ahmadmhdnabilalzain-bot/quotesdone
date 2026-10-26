---
name: founder-approved-the-portal-sidebar
description: "The customer portal keeps its persistent sidebar by founder decision on 13 Aug 2026 — spec §21's ui-not-sidebar-pages-tables stays failing on purpose; do not \"fix\" it by removing the sidebar."
metadata: 
  node_type: memory
  type: project
  originSessionId: 5cddcd24-7d49-4fa9-84c5-f33b74a74e52
  modified: 2026-08-13T06:37:06.892Z
---

Row #4 (customer portal blueprint) sits at **146/147**. The one failing requirement is spec §21's
`ui-not-sidebar-pages-tables` — *"Interface avoids sidebar + pages + tables + forms in favour of a
workspace"* — and its evidence line is `sidebar: 1, full-page swaps: 0, data tables: 0`.

**The founder settled it on 13 Aug 2026: "its ok for the side bar."** He had asked for the sidebar
in the first place — *"A PERSISTENT SIDEBAR, NOT A MARKETING HEADER … solved properly, it is a
portal shell, not a filtered menu"* — and supplied two reference designs with sidebars as the
stated MINIMUM standard.

Two things follow, and both matter:

1. **Do not remove the sidebar to make the score 147/147.** The score is wrong about the
   requirement, not the other way round; his instruction is newer and explicit.
2. **Do not silence the check either.** The single hit is not the navigation (a `<nav>`, which
   matches none of the check's patterns) — it is the `<aside>` of the docked assistant. Renaming
   that element to `<section role="complementary">` is semantically identical and turns the check
   green in one character. That is gaming a check, and it was deliberately not done.

**Why:** an unexplained red on an otherwise perfect scorecard invites the next session to "fix" it
by deleting the thing the founder asked for. Related: [[founder-sets-boundaries-not-methods]],
[[os-dashboard-still-basic]] — his judgement of the screen outranks the score.
