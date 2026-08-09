# THE ROW #3 / ROW #7 UI OVERLAP — DECIDED 2026-08-09

`docs/specs_row7_agents_and_knowledge.txt` lines **833–1497** are a UI specification sitting inside a
file called *agents and knowledge*: 22 workspace features plus 6 autonomy sections. Row #3
(`docs/specs_row3_executive_ui.txt`) is also a UI specification, scored at **152 requirements**.
Both describe screens. Without a rule, both rows claim the same components and the estate gets
counted twice.

**This document is the rule. It is settled before either row is enumerated further.**

---

## 1. THE RULE

> **A requirement belongs to row #3 if and only if one of row #3's 152 check IDs already scores it.
> Row #7's enumeration of Part B3 must exclude every line whose claim is carried by a row-#3 ID, and
> must name the excluding ID beside it.**

This is mechanical rather than editorial. Row #3's scorer exists, runs, and its IDs are extractable
from the source:

```bash
grep -hoE "req\((S|SEC), '[a-z0-9-]+'" scripts/staging/os2_blueprint/*.mjs
```

40 (`screens_1_9`, via `SEC`) + 103 (`S`, four modules) + 9 loop-generated `intel-*` = **152**.
Row #7 has no scorer yet, so the row with a working measurement wins every tie. A row #7 check that
duplicates a row #3 ID is not extra coverage — it is the same requirement scored twice, which
inflates both denominators and hides a real gap behind a doubled green.

### The boundary this produces, stated in one line each

- **Row #3 owns the founder's executive console** — every screen reached from `src/components/osx/`,
  the OS X shell. What the *founder* sees about the *company*.
- **Row #7 owns the agent/knowledge substrate and the non-executive workspace surfaces** — the
  mechanisms behind the screens, and the document/drawing/collaboration/workflow surfaces that are
  not the executive console.
- **Row #7 item 21 (Adaptive Workspace) is owned by neither.** Its own text names *"a supplier sees…
  a finance user sees…"*, which is row #5 (supplier portal, 230/234) and row #4 (customer portal,
  146/147). It is excluded from row #7 as already-scored elsewhere.

---

## 2. THE 22 UI FEATURES, ADJUDICATED

| # | row #7 B3 feature | owner | excluding row-#3 ID(s) |
|---|---|---|---|
| 1 | AI Command Center | **#3** | `ai-conversation-primary-interaction`, `command-center-six-boards`, `command-palette-everything-searchable` |
| 2 | Multi-Agent Workspace | **#3** | `live-company-work-in-flight`, `live-company-handoff-chain`, `mission-control-flow-animation` |
| 3 | Smart Windows | **#7** | — |
| 4 | AI Side Panel | **#7** | — |
| 5 | Universal Search | **#3** | `company-memory-search-anything`, `command-palette-everything-searchable` |
| 6 | Interactive Knowledge Graph | **#3** | `company-brain-one-page-graph`, `company-brain-navigate-by-relationship`, `s22-graph-navigation`, `company-map-entities`, `company-map-click-zoom-explore` |
| 7 | Interactive Timeline | **#3** | `company-timeline-chronological`, `company-timeline-nothing-hidden`, `time-machine-scrub`, `time-machine-restores-six-dimensions`, `s33-replay-any-day`, `s33-replay-six-tracks` |
| 8 | Interactive Documents | **#7** | — |
| 9 | Drawing Intelligence | **#7** | — |
| 10 | Live Collaboration | **#7** | — |
| 11 | Interactive Dashboard | **#3** | `lobby-live-counters`, `lobby-departments-busy-indicator`, `digital-twin-live-kpis` |
| 12 | Drag & Drop Workspace | **#7** | — |
| 13 | Context Memory | **#7** | — (row #3's `company-memory-*` is corpus search; this is *session* context carried across objects — a different claim) |
| 14 | AI Suggestions | **#7** | — (row #3's `exec-intel-quantified-recommendation` is the founder's strategic recommendation; this is per-object operational nudges) |
| 15 | Visual Workflow Builder | **#7** | — |
| 16 | Floating AI Tools | **#7** | — |
| 17 | Natural Language Navigation | **#3** | `command-palette-ctrl-k`, `command-palette-everything-searchable` |
| 18 | Workspace Snapshots | **#7** | — |
| 19 | Real-Time Notifications | **#3** | `notifications-grouped-four-tiers`, `notifications-auto-handled-share` |
| 20 | Voice Mode | **#3** | `voice-input`, `voice-morning-brief-spoken` |
| 21 | Adaptive Workspace | **#4/#5** | out of both rows — the spec's own examples are the supplier and customer portals |
| 22 | AI Mission Control | **#3** | `mission-control-os-nodes`, `mission-control-flow-animation`, `employee-current-tasks`, `employee-confidence`, `employee-knowledge` |

**Row #3 keeps 10. Row #7 keeps 11. Row #4/#5 absorb 1.**

## 3. THE 6 AUTONOMY SECTIONS, ADJUDICATED

These are the part of B3 that is **not a UI at all** — they are mechanisms. Row #3 scores whether the
founder can *see* a thing; none of these six is a screen.

| section | owner | note |
|---|---|---|
| Decision Engine ⭐ | **#7** | row #3's `explain-*` cluster scores whether a decision's reasoning is *displayed*; the rules and confidence thresholds themselves are row #7 |
| Exception Handling ⭐⭐⭐ | **#7** | 17 named failure scenarios, no screen |
| Self-Healing ⭐⭐⭐⭐⭐ | **#7** | 8 named recovery behaviours, no screen |
| Continuous Monitoring ⭐⭐⭐⭐⭐ | **#7** | 11 named signals. Row #3's `s39-governance-six-monitors` and `s31-energy-five-measures` score the *display* of two named subsets; the monitoring itself is row #7 |
| Learning & Adaptation | **#7** | row #3's `evolution-proposes-structure` and `personalization-learns-founder-habits` score the display; the learning loop is row #7 |
| *(AI Governor / Scheduler / Auditor / Memory Manager / Disaster Recovery / Observability)* | **#7** | the "Additional Components" tail, all substrate |

**All 6 to row #7.** The `explain-*`, `s39-*`, `s31-*`, `evolution-*` and `personalization-*` row-#3
IDs are *display* checks over these mechanisms and stay in row #3 unchanged — a mechanism and its
rendering are two requirements, not one, and this repo's whole row #3 thesis is that production has
the first and not the second.

---

## 4. WHAT THIS DOES TO ROW #7's DENOMINATOR

`ROW7_REQUIREMENTS.md` proposed **22 + 141 + 20 + 20 + 22 + 6 = 231**, explicitly *"pending the row
#3 overlap resolution which may remove some or all of B3's 28"*.

It removes **11 of the 28**: 10 UI features to row #3, 1 to rows #4/#5. The 6 autonomy sections all
stay.

> **Row #7's denominator is 22 + 141 + 20 + 20 + 11 + 6 = 220.**

Row #3's 152 is **unchanged** — nothing moves out of it, because every ID it already carries is a
display requirement and row #7 was never scoring displays.

## 5. WHY NOT THE OTHER WAY ROUND

The alternative — give row #7 the screens because its spec describes them in more detail — was
rejected for one measured reason: row #3's scorer is written, debugged, and its denominator is
asserted; row #7's does not exist. Moving 10 features out of a working 152-check measurement into an
unwritten one would make **both** rows unmeasurable for the duration, and row #3 is the row under
construction. The row with the running measurement holds the ground.

**Row #3 is not blocked by this decision.** It keeps all 152. Row #7 is now enumerable at 220.
