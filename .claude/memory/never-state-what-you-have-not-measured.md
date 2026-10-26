---
name: never-state-what-you-have-not-measured
description: "Founder's standing rule — never give a comment or verdict you are not 100% sure of; a narrow check never licenses a broad claim."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 0081aec4-fde6-48b7-8226-cd4e593cbe56
  modified: 2026-08-11T13:27:17.825Z
---

Given 11 Aug 2026, and added to `.claude/skills/quotesdone-session/SKILL.md` §10.

> "from now on, you never give a comment or feedback that you are not 100% sure of."

**Why:** it was triggered by a concrete failure in the same session. A search of *column names* for
`is_demo`/`is_test`/`demo`/`seed` returned nothing, and that was written into a session brief as
"nothing in the schema marks a row as demo today" — which was then used to justify building a
`demo_run`/`demo_row` registry from scratch. Six clearly-marked demo suppliers had existed since
7 Aug, using a convention that lived **in the data, not the schema**: `ZZ DEMO — <name> (QuotesDone
fixture, not a real company)` with an `@example.invalid` email. The founder caught it with "you are
wrong. there is alot of demo data."

**How to apply:** state what was measured and what it covered, never what it implies about
everything unchecked. "The scan covered `text`/`varchar` columns in `public` base tables for three
patterns and found X" is honest; "there is no demo data" is a claim about every column not scanned.
Before writing a verdict, ask what the check would have missed, and say that out loud. If unsure,
measure again or say so — both are fine; a confident guess is not, and neither is hedged phrasing
that still reads as knowledge.

Same failure shape as [[instruments-report-on-the-wrong-subject]]: an unbounded conclusion drawn
from a bounded measurement.
