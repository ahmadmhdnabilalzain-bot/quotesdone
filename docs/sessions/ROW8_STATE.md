# ROW #8 — STATE. Measured on production 2026-08-09.

**185 / 226 (82%)** on production. Full run, 226 registered, **0 errored**, no denominator shortfall.
Scorer: `scripts/staging/verify_ai_router.mjs`. Enumeration: `docs/sessions/ROW8_REQUIREMENTS.md`.

---

## 1. THE ROUTER IS BUILT, AND IT IS GOOD

This is row #6's shape again: far more exists than the spec's framing suggests. Do **not** start by
building a router.

| thing | on production |
|---|---|
| `model_registry` | 6 models, tiers small/medium/large/xlarge, real OpenRouter pricing incl. cache rates |
| `model_policy` | 31 task classes mapped to a tier, a model, a fallback and a `max_tokens` |
| `ai_cost_log` | 1,021 logged calls with cost, tokens, tier, task class and attribution |
| `llm_cache` | table + 4 routines + a semantic `embedding_gte` column |
| observability | 8 views: `v_ai_spend`, `v_cost_optimisation`, `v_llm_model_mix`, `v_llm_offpolicy`, … |
| routing routines | `fn_ai_route`, `fn_select_model`, `fn_ai_route_tier_rank`, `fn_model_autoswitch`, `fn_model_benchmark`, `fn_budget_*` |

`fn_ai_route` genuinely routes. Executed on production:

```
fn_ai_route('vat_calculation')
  -> {"use_llm": false, "tier": "none", "why": "REFUSED. SQL / plpgsql",
      "deterministic_alternative": "SQL / plpgsql"}

fn_ai_route('agent_reasoning')
  -> {"tier":"large", "model":"anthropic/claude-sonnet-5", "fallback":"anthropic/claude-opus-4.8",
      "cache":true, "stream":true, "max_tokens":8000, "in_per_mtok_usd":2, ...}
```

**Eleven task classes are refused an LLM outright** with a named SQL alternative. That is the
spec's §19 (deterministic tools first) and §33 (early exit) implemented properly, and it is the
strongest part of this estate. §1 router scored **9/9**, §3 engine **4/4**, §17 split **3/3**,
§39 fail-gracefully **2/2**, §11 providers **3/3**.

---

## 2. THE FINDING: THE MECHANISM IS COMPLETE AND LARGELY UNEXERCISED

This is why the row is scored with `-exists` and `-used` as separate requirements.

| mechanism | exists | actually runs |
|---|---|---|
| answer cache | table + 4 routines + semantic column | **0 rows**; 2 of 1,021 calls served from cache |
| quality scoring | `model_outcome` table, `v_ai_quality_proxy` view | **0 rows** |
| model quality score | `model_registry.quality_score` column | **null on all 6 models** |
| automatic model switching | `fn_model_autoswitch` | cannot fire — it needs `quality_score` |
| benchmarking | `fn_model_benchmark` | **0 results**, so all six benchmark legs fail |
| confidence capture | `ai_cost_log.confidence` column | **null on all 1,021 rows** |

Six of these chain from two empty tables. **`model_outcome` and `quality_score` are the keystone**:
populate them and `qual-score-*` (3), `bench-*` (6), `switch-automatic` and
`feedback-improves-routing` — **11 requirements** — become reachable. Nothing needs to be built;
the benchmark routine needs to be *run*.

## 3. THE DISTRIBUTION, WHICH IS WHAT THE SPEC IS ACTUALLY ABOUT

Measured over 1,021 logged calls against the spec's own §2 table:

| level | spec target | measured | |
|---|---|---|---|
| no AI | 20% | 35% of task classes | **beats target** |
| cheap (small) | 55% | **41%** (422 calls) | 14 points short |
| medium | 20% | **11%** (115 calls) | 9 points short |
| premium (large+xlarge) | ≤5% | **33%** (335 calls) | **6.6× the ceiling** |

The premium overrun is concentrated and nameable:

```
agent_reasoning          282 calls   AED 51.38   tier large
chief_of_staff_decision   52 calls   AED  5.03   tier large
(null task_class)        146 calls   AED 21.11   unclassified
```

`agent_reasoning` alone is **AED 51 of roughly AED 80 total spend**. And 146 calls carry no
`task_class` at all — they cannot be routed by policy because nothing told the router what they
were. That is the single highest-value fix in the row and it is a *classification* problem, not a
model problem.

`set-no-auto-premium` fails for the same reason: **25 premium calls are flagged
`could_be_cheaper`** by the estate's own `v_cost_optimisation` view.

## 4. THE CHANNELS ARE BUILT AND UNPOPULATED — ROW #5's WALL AGAIN

`customers` 0 rows, `wa_messages` 5, `messages` 1, `response_template` 6. Part B scored 37/43, C
17/22, D 21/23 — all on **mechanism**, deliberately and with the row counts printed. A `-used` bar
here would have failed 88 requirements and measured nothing except that the business has not
launched. That asymmetry with part A is stated in the module header rather than hidden.

The genuine channel gaps are small and concrete: four missing email templates (apology, shipping,
follow-up, complaint resolution), two missing WhatsApp templates (delivery, appointment), and no
per-session AI budget cap on the public widget.

## 5. ONE SCORER DEFECT, FOUND BY READING THE PAYLOAD

`cascade-starts-cheap` printed:

```
MISSING cascade-starts-cheap   fn_ai_route('category_classification') starts at tier=small
```

A MISSING whose own evidence says it should pass. The management API returns a Postgres boolean as
a JS boolean, so `startsCheap === 'true'` compared `true` to `'true'`. Fixed; three sibling legs had
the same bug and were caught in the smoke test.

A second false MISSING was caught before the first full run: `route-branch-simple-cheap` asked
`fn_ai_route('classification')`, but the estate's task class is `category_classification` — the
router correctly fell back to its safe medium default and the check read that as a routing failure.
**A scan whose vocabulary is not the estate's vocabulary produces a false MISSING**, which is row
#5's lesson in a third form.

---

## 6. WHAT IS BLOCKED BY BUSINESS REALITY RATHER THAN CODE

- **`spend-limit-free` / `-premium` / `-enterprise` (3)** — the estate budgets by DEPARTMENT
  (13 budgets set, `fn_ai_spend_guard` present). Per-USER caps need a plan/tier model, which is a
  pricing decision, not a schema one.
- **`uni-mix-website` (1)** — 0 AI calls attributed to the widget. Cannot be reported for a channel
  that has never called a model.
- **The eleven quality/benchmark requirements** — reachable only by *running* benchmarks against
  real tasks and recording real scores. Inventing `quality_score` values to light up
  `fn_model_autoswitch` would be fabrication of exactly the kind that makes the router choose
  wrongly in production.

## 7. THE HIGHEST-VALUE WORK, IN ORDER

1. **Classify the 146 unclassified calls** (AED 21.11). They bypass policy entirely.
2. **Run `fn_model_benchmark` and populate `model_outcome` + `quality_score`.** Unlocks 11
   requirements and lets `fn_model_autoswitch` fire.
3. **Wire the cache.** `llm_cache` has 0 rows against 1,021 calls; the routines already exist.
4. **Move `agent_reasoning` off `large` where it can go.** 282 calls, AED 51 — the single biggest
   line, and `v_cost_optimisation` already flags 25 of them as downgradable.
5. Capture `confidence` on write — unblocks `dash-avg-quality` and `cascade-confidence-score`.
