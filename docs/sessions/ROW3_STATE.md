# ROW #3 — THE EXECUTIVE UI: 28 / 152 (18%), AND THE NUMBER IS NOW TRUSTWORTHY

Measured on production 2026-08-09. **0 errored, denominator verified.** Scorer:
`scripts/staging/verify_os2_blueprint.mjs`, modules in `scripts/staging/os2_blueprint/`.

---

## 1. THE FIRST NUMBER WAS NOT A SCORE

The run reported **21/152 (14%)** and said twice, in ways easy to read past, that it was not
trustworthy:

```
19 CHECK(S) ERRORED — an errored check is NOT a MISSING verdict, it is
an unmeasured requirement, and reporting it as MISSING would be a false negative
!! 1 section(s) have an unverified check count — the denominator is not
   trustworthy, so neither is the percentage below
```

Three defects, **all in the measurement, none in the estate**:

| defect | cost |
|---|---|
| set-returning function in a `VALUES` list | **18 requirements unmeasured** |
| `export const expected` vs the `EXPECTED` the runner reads | denominator unverified |
| `leads.status` (is `approval_status`), and `::numeric` on a JSON **array** | 2 more errors |

`SURFACE` calls every executable screen routine inside `values (...)`. `callable` filtered on
`pronargs = 0` and `provolatile <> 'v'` but not on `proretset`, so one screen returning a SET made
every check using `DELIVERED()` fail with `0A000`. The set-returning screens were **not dropped** —
that would shrink the surface and turn a measurement bug into a scoring bug. They moved to the
static-read path, which is how every other non-executable screen is already handled.

`screens_1_9.mjs` declared its count in lowercase. It was registering exactly the 40 checks it
intended and declaring that to nobody — **a silent casing slip inside the very assertion that
exists to catch silent slips.** 20+18+32+42+40 = 152 confirms it.

**Trustworthy baseline: 28/152.** The seven-point move is entirely requirements that always passed
and could not be measured.

---

## 2. THE 124 GAPS ARE ONE SENTENCE REPEATED

Nearly every evidence line has the same shape:

```
ui: no rendered component names it (0 of 73 components)  |  db: <real, live, populated data>
```

- `intel-top-opportunities` — **9 open opportunities**, browser-reachable, rendered by nothing
- `intel-competitors` — **27 competitors** read by `fn_company_reflect`, rendered by nothing
- `intel-ai-spending` — **1,050 `ai_cost_log` rows** in 30 days, rendered by nothing
- `company-brain-one-page-graph` — **324 nodes, 608 edges**, rebuilt nightly, no reachable reader
- `explain-owning-os` — **0 of 35 surfaced actions** name the OS that owns them

**The company computes itself every night and shows the founder almost none of it.** That is the
whole of row #3, and it is a front-end programme, not a database one.

### Where the 124 sit

| cluster | n | what closes it |
|---|---|---|
| `employee-*` | 11 | agent drawer: goal, knowledge used, performance trend |
| `intel-*` | 9 | **one** Intelligence screen carrying ≥4 of the 9 named items |
| `explain-*` | 8 | why / owning OS / policies / alternatives / confidence / outcome on 4 action surfaces |
| `exec-home-*`, `exec-*` | 9 | landing figures and the meeting record |
| `s21`–`s40` | 31 | one screen each, mostly already computed server-side |
| screens 1–17 | 56 | the workspace screens themselves |

## 3. THE CHEAPEST REAL WIN, AND ITS EXACT CONTRACT

The nine `intel-*` checks share one bar, stated once in `screens_10_17.mjs`:

> the component that renders the item must carry **at least four of the nine**. Below that it is a
> functional module — Finance showing a cash forecast, Strategy showing a risk list — which is
> exactly the case the spec's "one screen" wording excludes, and which is what production has today.

Today `StrategyApp` carries 1 of 9 (risks) and `FinanceApp` carries 1 of 9 (forecast). **One
Intelligence workspace rendering all nine closes all nine**, and eight of the nine already have a
browser-reachable data source. The ninth, `growth_probability`, has none — *"0 browser-reachable
routine(s) mention a probability"* — so it needs a server-side figure as well as a screen.

## 4. WHAT IS HONESTLY LEFT

Row #3 is **124 requirements of front-end work** against a database that already holds the answers.
It is the largest remaining row by a wide margin and it is not a session's work. The measurement is
now sound, the clusters are sized, and the contract for each is written down — which is the
precondition for building it, and was not true before today.

**The one thing not to repeat:** the first run's 14% would have sent someone building things that
already worked. Nineteen requirements had no verdict, and the report still printed a percentage.
An errored check is not a MISSING verdict — fix the measurement before reading the score.
