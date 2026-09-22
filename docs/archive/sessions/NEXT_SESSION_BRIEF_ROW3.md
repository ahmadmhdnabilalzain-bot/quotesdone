# Row #3 — the Executive UI ("OS X"). Opening brief.

Spec: `docs/specs_row3_executive_ui.txt` (your `OS 2.txt`, 1,147 lines).
Scorer: `scripts/staging/verify_os2_blueprint.mjs`, modules in `scripts/staging/os2_blueprint/`.
State: `docs/sessions/ROW3_STATE.md`.

**Measured on production 2026-08-09: 28/152 (18%), 0 errored, denominator verified.**

Everything below was measured, not inferred.

---

## 1. THE NUMBER YOU INHERIT IS TRUSTWORTHY. THE ONE BEFORE IT WAS NOT.

The first run of this scorer reported **21/152 (14%)** and said twice that it could not be believed:

```
19 CHECK(S) ERRORED — an errored check is NOT a MISSING verdict, it is
an unmeasured requirement, and reporting it as MISSING would be a false negative
!! 1 section(s) have an unverified check count — the denominator is not trustworthy
```

Three defects, **all in the measurement, none in the estate**, all fixed:

| defect | cost |
|---|---|
| set-returning function inside a `VALUES` list (`callable` never filtered `proretset`) | **18 requirements unmeasured** |
| `export const expected` where the runner reads `EXPECTED` | denominator unverified |
| `leads.status` (it is `approval_status`); `::numeric` cast on a JSON **array** | 2 more errors |

The seven-point move from 21 to 28 is **entirely requirements that always passed and could not be
measured**. Nothing was built to earn it.

## 2. THE 124 GAPS ARE ONE SENTENCE REPEATED

Almost every evidence line reads:

```
ui: no rendered component names it (0 of 73 components)  |  db: <real, live, populated data>
```

- 9 open opportunities, browser-reachable, rendered by nothing
- 27 competitors read by `fn_company_reflect`, rendered by nothing
- 1,050 `ai_cost_log` rows in 30 days, rendered by nothing
- 324 graph nodes and 608 edges rebuilt nightly, **no reachable reader at all**
- 0 of 35 surfaced actions name the Operating System that owns them

**The company computes itself every night and shows you almost none of it.** This row is a
front-end programme against a database that already holds the answers.

### The clusters, sized

| cluster | n | what closes it |
|---|---|---|
| screens 1–17 | 56 | the workspace screens themselves |
| sections 21–40 | 31 | one screen each, mostly already computed server-side |
| `employee-*` | 11 | agent drawer: current goal, knowledge used, performance trend |
| `intel-*` | 9 | **one** Intelligence screen — see the trap below |
| `explain-*` | 8 | why / owning OS / policies / alternatives / confidence / outcome, on 4 action surfaces |
| `exec-*`, `exec-home-*` | 9 | landing figures and the meeting record |

---

## 3. THE TRAP. READ THIS BEFORE YOU WRITE A COMPONENT.

The nine `intel-*` checks scan a **component body** for nine regexes and require the component to
carry **at least four of the nine** (threshold stated once in `screens_10_17.mjs`). Today
`StrategyApp` carries 1 (risks) and `FinanceApp` carries 1 (forecast).

The obvious read is "one Intelligence component closes all nine". **It does not, and acting on that
ships a green score and four empty panels.** The three workspace routines were executed on
production and their payloads measured:

| intel item | data reachable today | source |
|---|---|---|
| risks | **yes** — 6 rows, top risk scored 20 | `ws.strategy.risks` |
| predictions | **yes** — 4 simulations | `ws.strategy.recent_simulations` |
| forecast | **yes** — burn 1,127, cash −4,317, rfqs 7/30d, category growth | `ws.strategy.kpis` + `ws.analytics.marketplace` |
| supplier health | **yes** — 1 under-supplied category, capacity avg 4.2 | `ws.strategy.under_supplied` + `ws.analytics` |
| opportunities | partial — 8 recommendations, but the `opportunity` table (9 rows) is in no payload | — |
| competitors | **no** — `market_intel` is **0 rows**, `competitor_intel` is **0** | — |
| customer behaviour | **no** — no customer figure in any of the three payloads | — |
| AI spending | **no** — 1,050 rows and no workspace routine exposes them | — |
| growth probability | **no** — 0 browser-reachable routines mention a probability | — |

**Four have live data, which is exactly the co-location threshold.** So an honest Intelligence
screen carrying risks + predictions + forecast + supplier health flips **four**. The other five need
a workspace routine exposing `opportunity`, `competitor`, customer health and `ai_cost_log`, plus a
growth-probability figure that exists nowhere yet.

**The cluster is 4 now, 5 after a server change — not 9 from one component.**

## 4. WHERE THE UI LIVES

- `src/components/osx/OsxShell.tsx`, **2,308 lines**
- `MODULES` array at **line 43**; the render switch at **line 128**; `StrategyApp` at **2042**,
  `FinanceApp` at **1643** — copy their shape
- Workspace hooks in use: `ws.analytics`, `ws.company`, `ws.documents`, `ws.ea`, `ws.governance`,
  `ws.operations`, `ws.reports`, `ws.strategy`; other screens use `osApi('customers_board')` etc.
- The scorer scans **rendered** components — a body containing `<X` and `return`

## 5. THE OVERLAP YOU MUST RESOLVE FIRST

`docs/specs_row7_agents_and_knowledge.txt` (row #7, never scored) devotes its **last 377 lines** to a
UI spec: AI Command Center, Multi-Agent Workspace, Smart Windows, Universal Search, Interactive
Knowledge Graph, Timeline, Drawing Intelligence, Voice Mode, AI Mission Control, plus Decision
Engine / Exception Handling / Self-Healing / Continuous Monitoring / Learning & Adaptation.

**That overlaps this row.** Settle which row owns those screens before either is enumerated further,
or both will claim the same components. Groundwork is in `docs/sessions/ROW7_REQUIREMENTS.md`.

## 6. THE REST OF THE ESTATE, SO YOU DO NOT RE-MEASURE IT

| spec | score |
|---|---|
| #1 company architecture | **48/48 (100%)** |
| #2 OS blueprint | **110/110 (100%)** |
| #4 customer portal | 146/147 — one gap: discovery returns no found-count |
| #5 supplier portal | 230/234 — 3 tier-benefit requirements + `entry-not-form-wall`, all founder calls |
| #6 supplier categories | 249/283 — the 34 are sourced authoring, not code |
| #8 openrouter cost | 200/226 — 12 need traffic, 11 to build |

Both Supabase projects are digest-identical: **800 routines, 161 views, 5,363 columns**, and
**nothing is ahead in staging**. Vercel is deployed at `main`.

## 7. TWO STANDING DECISIONS ALREADY TAKEN

- **`kb_embed_backfill` and `site_autodeploy` stay on their every-minute schedule.** Neither calls a
  model, so neither costs anything per run, and the first is actively draining a real backfill.
  Row #8's `sleep-agent-sleeps-after` still reads MISSING and was deliberately **not** weakened.
- **Per-user AI spend caps are dropped** at the founder's instruction. Departments stay budgeted.

## 8. THE LESSON THAT COST THE MOST THIS SESSION

**The brief is a hypothesis. The scorer is the measurement. Run it first, every time.**

Four documents were accurate when written and wrong when read:

- Row #6's brief named a defect whose proposed fix would have **caused a regression**
- Row #2's worklist listed 45 gaps of which **44 were already closed**
- My own scorer anchored on `classification` when the estate's class is `category_classification`
- …and on `model_outcome`, a table with **zero writers**

Each produced a false MISSING. When a check reads 0, or an evidence line contradicts its own
verdict, **suspect the check before you build anything.**

---

## THE PROMPT TO COPY

```
Read docs/sessions/NEXT_SESSION_BRIEF_ROW3.md first, then docs/sessions/ROW3_STATE.md.

Row #3 is the Executive UI — the OS tool. Spec is
docs/specs_row3_executive_ui.txt, scorer is
scripts/staging/verify_os2_blueprint.mjs.

Founder rules, unchanged: one row at a time to 100%; everything deploys to BOTH
Supabase projects, is verified by execution in the same turn, committed, and
merged via PR. A MISSING verdict is a BUILD ORDER, never an argument that
something existing already covers it. Never fabricate, back-date or mass-close
data to turn a gate green, and never weaken a check to make it pass.

Do these in order:

1. Run the scorer before anything else and tell me the number. It was 28/152 on
   9 Aug with 0 errored. If it moved, say so. Do NOT open with the brief's plan
   — three planning documents were wrong this month and each would have cost a
   change.

2. Resolve the overlap with row #7 first. The last 377 lines of
   docs/specs_row7_agents_and_knowledge.txt are a UI spec that overlaps this
   row — AI Command Center, Multi-Agent Workspace, Smart Windows, Knowledge
   Graph, Voice Mode, Mission Control, Decision Engine, Self-Healing. Decide
   which row owns those screens and write the decision down before enumerating
   either further.

3. Then build the Intelligence screen, and build it HONESTLY. The nine intel-*
   checks scan a component body for nine regexes with a threshold of four, so a
   component that merely NAMES all nine scores nine and shows me four empty
   panels. Only four have live data today: risks, predictions, forecast,
   supplier health. Build those four against ws.strategy and ws.analytics, and
   tell me plainly that it is four — not nine.

4. Then expose what the other five need: a workspace routine over the
   opportunity table, competitor data, customer health and ai_cost_log, plus a
   growth-probability figure that exists nowhere yet. Only then does the intel
   cluster reach nine.

5. Do not ship a React component into my production console without verifying
   it renders real data. Screenshot it or read the payload back.

Report the score as a measurement with its evidence, and tell me plainly about
anything blocked by business reality rather than by code.
```
