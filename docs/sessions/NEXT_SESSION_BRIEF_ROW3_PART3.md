# Row #3, part 3 — opening brief

Spec: `docs/specs_row3_executive_ui.txt`. Scorer: `scripts/staging/verify_os2_blueprint.mjs`.
State: `docs/sessions/ROW3_STATE.md`. Overlap decision: `docs/sessions/ROW3_ROW7_UI_OWNERSHIP.md`.

**Measured on production at the end of the previous session: 93/152 (61%), 0 errored, 0
regressions. Run the scorer before you read another line — six checks were deployed and verified
but flip on clocks between 00:35 and 06:40 UTC, so the number should be materially higher.**

---

## 1. RUN THE SCORER FIRST, AND EXPECT THESE SIX

Every one of these is deployed to both projects and verified by executing the routine. None needs
a change. If one of them is still MISSING after its hour, **that is a defect and it is yours** —
the routine did not do what execution said it would.

| flips at (UTC) | check | verified how |
|---|---|---|
| 00:35 | `digital-twin-live-kpis` | `bi_snapshot_6h` scheduled + registered; all 14 active metrics dry-run to a value on production; every other leg of the check already passes |
| 04:30 | `companion-overnight-brief`, `voice-morning-brief-spoken` | extended `fn_founder_brief` executed on staging: all four new figures land, `founder_alerts` row written. Digest-identical on both projects |
| 05:00 Mon | `exec-meeting-agenda-six`, `exec-meeting-debate` | `fn_exec_meeting` executed on staging: 6 of 6 sections on all 12 contributions, 2 challenges recorded between cfo and procurement |
| 06:40 Mon | `s39-governance-six-monitors` | the three unrun monitors executed on staging; all three succeed |

`exec-meeting-priorities-agreed` will NOT flip with the others. It is a universal over every ceo
`exec_report` in 60 days and three of the four in the window were written on 28 Jul and 3 Aug with
string recommendations. The routine is fixed; **rewriting those three rows would be editing the
record to turn a gate green**, so they are left to age out — 27 Sept, 3 Oct, 6 Oct.

## 2. DO NOT REBUILD THIS

Session 1 built eleven workspace routines and nine screens (section 1 of
`NEXT_SESSION_BRIEF_ROW3_PART2.md` — still accurate). Session 2 added:

`fn_exec_meeting` (six agenda sections, ten participants, ranked priorities, `fn_challenge` on the
top three) · `fn_ws_reports` (the meeting transcript, priorities and challenges) · `fn_challenge`
(a prior-outcome refusal now states its basis) · `v_operating_manual` (+ governance_policy,
decision_policy, org_departments — 198 → 254 entries) · `bi_snapshot_6h` cron · `MeetingReplay` in
`OsxShell.tsx`.

## 3. THE RULE THAT PAID FOR ITSELF TWICE THIS SESSION

**Measure the mechanism before you believe the brief about it.** Two of the previous brief's own
items were wrong:

- `s38-manual-always-current` was listed as the top buildable item with "28 undocumented jobs".
  It was already MET — 0 and 0. Ten minutes saved by running `--only=s38` first.
- The 04:30 founder-brief cron was described as something to wait for. It had already run today,
  successfully, for the 22nd time — and the extended routine was deployed *after* it, so waiting
  for "the 04:30 cron" without checking would have meant waiting a day to discover nothing had
  changed. The distinction only shows up if you read `cron.job_run_details` **and** compare the
  stored output against what the new body should produce.

And the one that was a real defect hiding as business reality: **`fn_bi_snapshot` had no cron at
all.** A writer with no schedule looks exactly like an empty table.

## 4. WHAT IS LEFT, RE-MEASURED

### A. Genuinely blocked by the company, not the code

| what | why |
|---|---|
| `intel-customer-behavior`, `company-map-entities`, part of `s22` | `public.customers` holds 0 rows. `inquiry_intake` v21 creates the row now — verified in the deployed source — so this fills on the first authenticated inquiry. |
| the five per-employee universals | 8 of 66 employees have ever produced an `agent_run`. `agent_brain` writes `agent_runs`, `agent_memory` and `kb_usage_log` per turn, but 66-of-66 coverage needs the employees to work. |
| `strategic-not-operational` | 115 strategic against **181** operational — the hourly sweep took it from 316. Still needs strategic to exceed operational. |
| `explain-confidence-score` | `decision_log.confidence` NULL on every `action_gate` row. |
| `explain-alternatives-considered` | `challenge_record`'s alternatives join to none of the 35 surfaced actions. **Re-measure this one** — the meeting now writes challenges whose proposal text names the agenda item, which may change the join. |
| `what-if-projected-deltas`, `-confidence-score` | four simulation rows from 28 July with different keys. Rewriting them is fabrication. |

### B. `twin-realtime-updates` is MET and must stay untouched

Section B2 of `NEXT_SESSION_BRIEF_ROW3_PART2.md` explains why the obvious version would have been
fraud: all thirteen twin classes have **RLS enabled with zero policies** — deny-all — and the
console reads them through `os_api` with the service role, so a browser subscription would never
fire. Making it real is a security change with its own review. **Nothing in session 2 touched RLS
or the realtime publication.**

### C. Buildable, closest first

- **`s33-replay-six-tracks`** — two legs. The KPI track is fixed by `bi_snapshot_6h` (from 00:35
  every snapshot day has metric rows). The **outcomes** track needs `outcome_record` rows on the
  replay day; `fn_outcome_open` is called only by `fn_kpi_review`, weekly on Monday 04:00. Decide
  honestly whether outcomes should open daily before scheduling anything — an outcome row created
  to fill a track is fabrication. The second leg is pure build: **no browser-reachable routine
  spans all six tables**, and one `fn_os_replay(p_day date)` wired into `os_api` closes it.
- **`time-machine-restores-six-dimensions`** — 5 of 6. The missing dimension is **customers**: the
  nightly `company_snapshot.state` carries 24 keys and not one matches `customer|buyer`. Adding a
  real count (0 today) is a true measurement, not a fabrication — but the check is a universal
  over the last 14 days, so it flips 14 days after the writer changes, not on deploy.
- **`s32-reputation-six-dimensions`** — `agent_reputation` has 66 rows with only `score` and
  `learning_speed`. The other four need the reputation job to compute them.
- **`s36-recommendation-seven-fields`** — 3 of 7 on every one of 1,157 recommendations/30d;
  missing alternatives, assumptions, cost and one more.
- **`s29-scan-five-questions`** (2 of 5), **`s35-restructure-four-questions`** (0 of 4) — the scan
  and the restructure prompts do not ask the named questions.
- **`mission-control-flow-animation`** — pure frontend: 3 components draw connections, 0 animate,
  0 are bound to a flow.
- **`s27-knowledge-seven-fields`** — 1 of 7 metadata fields on 1,985 rows. A backfill; only if the
  values are derivable, never invented.

### D. One softness worth knowing about

`s38-manual-self-documenting` is MET, and its delivery leg passes because `fn_ws_company_os`
carries the 81 runbooks into the payload. **`v_operating_manual` itself still has no real reader**
— the only routine naming it, `fn_agent_context`, names it in a comment. The founder cannot open
the operating manual on any screen. That is not what the check measures, and it is worth building
anyway.

## 5. THE RULE THAT KEEPS THE SCORE HONEST

Every screen shipped is resolved against the live production payload before it ships. `MeetingReplay`
was resolved twice: **10 of 21 paths** against production's 6 Aug meeting (the six agenda sections
and the challenge fields do not exist on it, and the component renders only what is present), and
**25 of 26** against the new-shape meeting on staging. The one empty path was
`challenge.reasoning` — which turned out to be a real defect in `fn_challenge`, found because the
path was measured rather than assumed, and fixed in the same session.
