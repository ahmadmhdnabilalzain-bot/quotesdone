# Capacity plan — January 2027 launch

Owner: **it_engineer**. Written 28 Sep 2026. Load test: `scripts/load/launch_load_test.mjs`
(proof: `scripts/load/launch_load_test.test.mjs`).

**Status: planned, not measured.** No load has been run against the sandbox yet. Every
volume below is an assumption stated as such; replace each with the measured figure after
the first sandbox run and date the change.

## 1. What is being sized

| Path | Surface | Why it matters |
|---|---|---|
| Inquiry intake | `functions/v1/inquiry_intake` | The customer's first write; a slow or failed intake is a lost customer. |
| Quote submit | `functions/v1/supplier_portal` (quotation actions) | Suppliers answer inside a deadline; a timeout is a missed quote. |
| Portal reads | `functions/v1/customer_portal`, `supplier_portal` list/read actions | The bulk of traffic; the first thing to saturate connections. |

## 2. Expected volume and the 10x target

Assumed launch-month peak (planning numbers, not measurements): ~300 inquiries/day,
each matched to up to ~3 suppliers (top-3 rule), portal sessions reading ~10x the writes.
Peak hour taken as 40% of a working day's traffic over ~1 hour.

| Path | Assumed peak | Load-test baseline | 10x target (default `--scale=10`) |
|---|---|---|---|
| Inquiry intake | ~2 / min | 2 / min | 20 / min |
| Quote submit | ~6 / min | 6 / min | 60 / min |
| Portal reads | ~60 / min | 60 / min | 600 / min (10 / s) |

The baselines live in `SCENARIOS` in the script; change them there, not here only.

## 3. SLO thresholds (the pass line)

| Path | p95 latency | Error rate |
|---|---|---|
| Inquiry intake | ≤ 3000 ms (includes matching) | ≤ 1% |
| Quote submit | ≤ 2000 ms | ≤ 1% |
| Portal reads | ≤ 800 ms | ≤ 1% |

An error is a 5xx, a 429, a network failure or a 15 s timeout. A 4xx other than 429 is
counted as served (the fixture may not be authorised for the action; the platform still
answered). The script exits 1 if any path misses its SLO.

## 4. Platform limits to hold against

Read the current figures from the Supabase dashboard for the sandbox's compute tier before
the run; they change with the tier and are not assumed here.

- **Postgres connections.** Edge functions reach Postgres through the pooler (Supavisor).
  Watch *pooler client connections* and *direct connections* against the tier's cap. Portal
  reads at 10 / s with ~100 ms queries need ~1–2 concurrent connections; a sudden jump means
  queries are slow, not that traffic is high.
- **Edge function CPU.** Each invocation has a CPU-time cap separate from its wall-clock
  deadline (memory: *an edge function has a CPU cap a deadline doesn't bound*). A
  `546` / CPU-exceeded in the function logs is the signal; it bypasses any finding path.
- **Edge function concurrency / cold starts.** p95 inflated but p50 flat usually means cold
  starts, not saturation.
- **PostgREST / auth rate limits.** A wall of 429s is a configured limit, not a capacity limit.
- **Memory.** A large batch once pushed production past 4 GB and forced a restart
  (21 Sep 2026). Watch memory during the run; no batch jobs run alongside it.

## 5. How to read the first bottleneck

Run in steps: `--scale=1`, `--scale=3`, `--scale=10`. The first step where a path fails its
SLO is the bottleneck; then look in this order:

1. **Errors are 429** → a rate limit, not capacity. Raise it or accept it.
2. **Errors are 546 / CPU in edge logs** → the function's own work is too heavy (matching,
   escaping, LLM calls). Profile the function; more database will not help.
3. **p95 rises with scale while database CPU is high** → a query. Pull `pg_stat_statements`
   for the top mean-time statements during the window; add the index or cut the read.
4. **p95 rises, database CPU low, pooler connections at cap** → connection starvation.
   Shorten transactions, then raise the pool size or the tier.
5. **Only p95 is bad, p50 flat, errors 0** → cold starts or a single slow downstream (email,
   LLM gateway). Check which path; intake is the only one that calls out.

Record the step, the path, the p50 / p95 / error rate and the cause in this file under
section 7.

## 6. Safety — the run cannot reach a real person

- The script refuses unless `QD_LOADTEST=1` and `QD_LOADTEST_BASE_URL` are set, and refuses
  any base URL that is the production project or a quotesdone domain.
- Every generated identity is `ZZ DEMO — …` at `@example.invalid`; `assertFixture()` throws
  before each request, so a broken fixture stops the run rather than sending.
- Default mode is a dry run that prints the plan and sends nothing.
- Never run against production (auditor skill, section 8). Never run during a campaign hour.

## 7. Results

None yet. Pending: first run against the sandbox.
