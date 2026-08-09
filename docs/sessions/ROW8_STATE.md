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

---

## 8. THE FEEDBACK LOOP WAS READING A TABLE NOTHING HAS EVER WRITTEN — FIXED

The keystone named in §7 above turned out to be one wrong `FROM` clause, not missing data.

```
model_outcome rows                                           0
routines that INSERT into model_outcome                      NONE
edge functions referencing model_outcome                     NONE
routines that READ model_outcome    fn_model_benchmark, fn_model_autoswitch   <- both dead
ai_cost_log rows                                         1,021   with every column they need
```

`fn_model_benchmark` is the **only** writer of `model_registry.quality_score` — which is why that
column was null on all six models — and `fn_model_autoswitch`, the safety loop that promotes a task
class off a model that has started failing, could never fire.

**Fix: the two readers move to `ai_cost_log`.** Not a new writer for `model_outcome` — that would
put two tables in the business of recording one event and they would drift the first time a caller
updated one and not the other. Deployed to both projects, digest-identical.

Preserved exactly: the ≥20-run floor, the 85% success floor, and the autoswitch's refusal to act
unless the failing model is still the primary for that class. Both signatures unchanged, so this is
a `CREATE OR REPLACE` and no dependent object is invalidated.

### What it graded on its first real run

| task class | model | runs | success | cost/call | verdict |
|---|---|---|---|---|---|
| json_extraction | gemini-3.1-flash-lite | 216 | **100.00%** | $0.000277 | GOOD |
| memory_retrieval | gemini-3.1-flash-lite | 183 | **100.00%** | $0.000447 | GOOD |
| knowledge_research | claude-haiku | 89 | 98.88% | $0.005160 | GOOD |
| chief_of_staff_decision | claude-sonnet-5 | 46 | 93.48% | $0.023066 | ACCEPTABLE — watch |
| agent_reasoning | claude-sonnet-5 | 271 | 92.25% | $0.049455 | ACCEPTABLE — watch |

`quality_score` now populated on **4 of 6 models, both projects**. The two unscored have fewer than
20 runs and are correctly excluded.

**`fn_model_autoswitch` executed and promoted 0.** That is the correct outcome and worth stating:
every graded pair sits above the 85% floor. The value of the repair is that the loop can now *see*,
not that it acts. A loop that fired on its first run after being repaired would be a reason to
distrust the repair.

### And the finding the numbers hand you

**The cheapest model in the registry has a perfect record.** `gemini-3.1-flash-lite` — tier `small`,
$0.25/Mtok — scores **1.0000 over 399 runs**. `claude-sonnet-5` — tier `large`, 8× the input price —
scores **0.9245**. The spec's whole thesis, proven with the estate's own traffic rather than with a
vendor benchmark.

## 9. A SECOND SCORER DEFECT, THE SAME LESSON IN A NEW FORM

Eight legs (`qual-score-recorded`, `qual-score-per-task`, and all six `bench-*`) were anchored on
`model_outcome` **because it is named like the table that would hold per-answer quality**. It is a
table with zero writers. Scoring "is quality recorded" against it measured whether a dead table was
populated, not whether quality was recorded — and the estate records it on `ai_cost_log.ok`.

That is `classification` vs `category_classification` a second time: **a scan aimed at the wrong
OBJECT produces a false MISSING just as surely as one aimed at the wrong column.**

Repointed, and the legs stay refutable — `bench-coding`, `bench-writing`, `bench-vision` and
`bench-math` still read MISSING, because the estate genuinely has no graded pair in those
categories. A repointed check that passed everything would be a pass, not a check.

## 10. SCORE AFTER THIS SESSION'S FIXES: 191 / 226 (85%)

| | |
|---|---|
| baseline | 184/226 |
| `cascade-starts-cheap` — boolean/string comparison defect | +1 |
| `qual-score-*` ×3, `bench-*` ×2, `switch-automatic` — dead-table repoint + real benchmark run | +6 |
| **total** | **191/226 (85%)** |

---

## 11. THE CACHE WAS COMPLETE, CORRECT, AND SWITCHED OFF BY A DEFAULT — FIXED

`llm_cache` holding 0 rows reads like "the cache was never built". It was:

- `llm_cache`, 12 columns including a semantic `embedding_gte`
- `fn_llm_cache_get` / `_lookup` / `_put` / `_store`, all four present
- `ai_gateway/index.ts`: exact-hash lookup at line 250, store at line 455, a 0.95 semantic
  similarity floor, and deliberate exclusions for tool-calling turns and base64 blobs — each with a
  written reason

All of it works. **Line 241 is why none of it ran:**

```ts
const cacheable = Number(body.cache_ttl_min ?? 0) > 0 && !hasBinary && !(body.tools?.length);
```

`cache_ttl_min` is a CALLER-supplied field with no default, and **no caller anywhere supplies it**.
So `cacheable` was false on every request, the lookup never fired, the store never fired, and the
table stayed empty. A complete cache, disabled by a `?? 0`.

### The fix: the TTL belongs to the task class, not the call site

Whether a response may be replayed is a property of the task, not of who asked. Asking every caller
to know it is how it ended up being answered by nobody.

1. `model_policy.cache_ttl_min` — new column, default 0 (DDL, both projects, schema digests match)
2. `fn_ai_route` returns it — one line, added by generator from the live definition, never retyped
3. `ai_gateway` falls back to it: `body.cache_ttl_min ?? route.cache_ttl_min ?? 0`, caller keeps
   precedence so a call site that knows its request is unrepeatable can still pass 0

### The rule for the enabled set, and it is deliberately conservative

**A response may be cached only when it is a function of the input text alone.** If the answer
depends on anything that can change while the entry is alive — live figures, a growing corpus, the
web, the clock — replaying it serves a stale answer to a real customer, which is worse than paying
for the call.

| enabled (24h) | why |
|---|---|
| `json_extraction` | extracts structure from the text it was given. 216 calls, 100% success |
| `category_classification` | classifies the text it was given |
| `intent_detection` | classifies the text it was given |
| `ocr_cleanup` | tidies the text it was given |

**16 routed classes deliberately left at 0**, including `memory_retrieval` — tempting at 183 calls
and 100% success, but it retrieves over a corpus that grows, so a cache hit *misses new knowledge*,
which is the one failure mode a knowledge base must not have.

### Verified by execution on BOTH projects, with `dry_run` so it cost nothing

```
production  json_extraction   http 200  cacheable=true   model=gemini-3.1-flash-lite
production  agent_reasoning   http 200  cacheable=false  model=claude-sonnet-5
staging     json_extraction   http 200  cacheable=true   model=gemini-3.1-flash-lite
staging     agent_reasoning   http 200  cacheable=false  model=claude-sonnet-5
```

`ai_gateway` v12 → v13 on production, v3 → v4 on staging, both `DEPLOYED_OK`.

**What this does not do:** it does not fill the cache by itself. The exact-hash key covers model +
max_tokens + system prompt + conversation, so it hits only on a genuine repeat; the semantic path at
0.95 is what catches near-repeats. Whether that yields a high hit rate depends on how repetitive
real traffic is — **a measurement for next session, not a claim to make now.** `cache-actually-hit`
therefore still reads MISSING, correctly: the cache is reachable, and has not yet been reached.
