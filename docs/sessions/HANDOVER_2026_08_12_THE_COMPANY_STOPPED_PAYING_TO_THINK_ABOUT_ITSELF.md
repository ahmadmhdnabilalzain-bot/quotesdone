# Hand-over — 12 Aug 2026, ~10:30 UTC

Items 1–4 of the session brief are done, deployed to both projects and verified by measurement.
Items 5–8 are not started. This is where I stopped and why.

---

## 1 — #236 fires. Confirmed.

`fn_action_invoke_collect` is byte-identical on both projects (`deliverable` at offset 3207,
definition length 6779). No task had closed through that path since the fix deployed at 08:36 UTC —
the last one was 05:49 — so the query in the brief could only ever have returned pre-fix rows.

Proved it by **aborted-transaction probe on production**, feeding two real `net._http_response`
bodies through the deployed function:

```
collect = {"succeeded": 2}
A  kb_deepen body : task done, mode=executed_by_invoker, deliverable key PRESENT, value NULL
B  note body      : task done, mode=executed_by_invoker, deliverable = "no pending documents"
```

**The plumbing works. The second half is the finding.** Over 7 days of real executor bodies, only
**204 of 554** succeeded invocations carry any of the three keys #236 extracts
(`recommendation` → `deliverable` → `note`):

| executor | calls/7d | would yield a deliverable |
|---|---|---|
| analytics_recommend | 203 | **203** |
| action_worker | 253 | 1 |
| kb_deepen | 70 | 0 |
| exec_agents | 15 | 0 |
| ai_health / cost_snapshot / compliance_archive | 13 | 0 |

`analytics_recommend` — the escalation path the founder actually reads — is fully covered. `kb_deepen`
does real work (it adds named KB topics) and emits none of the three keys, so its deliverable is
still null after #236. **One line in `kb_deepen`'s response body would fix that.** Not done.

---

## 2 — The spend. Gate built, deployed, verified. #242

### The premise, corrected in both directions

`0.3 USD/hour` was the **session**, not the company. But the idle company is **not** six cents an
hour either. `ai_cost_log`, agent_brain + cos_execute on Anthropic models:

| | | | |
|---|---|---|---|
| 1 Aug | 3 calls, 0.61 AED | 6 Aug | 54 calls, **15.00 AED** |
| 2 Aug | 4 calls, 0.91 AED | 7 Aug | 48 calls, **12.62 AED** |
| 3 Aug | 6 calls, 1.01 AED | 8 Aug | 43 calls, **11.19 AED** |
| 4 Aug | 0 calls, 0.00 AED | 9 Aug | 47 calls, **11.85 AED** |
| 5 Aug | 4 calls, 0.41 AED | 10 Aug | 52 calls, **12.51 AED** |
| | | 11 Aug | 61 calls, **11.61 AED** |

**On 6 August the company generated a queue of tasks about itself and the bill went up twelvefold
overnight, then held there every day since** — on days with a session and days without. The true
idle burn before this fix was ~12 AED/day ≈ **$0.14/hour**, not $0.064, and ~95% of it was one loop.

### Where, exactly

290 of the 316 agent_brain Anthropic calls in seven days — **92%, 71.27 of 77.02 AED** — fire at
minute 50 or 51. That is cron 124, `cos_execute_hourly`. It takes 2 tasks off a FIFO queue every
hour and hands each to a ~25,000-token sonnet-5 call; `fn_task_review` then spends more calls having
the department head and the Chief of Staff review it. **385 org_tasks are open and 346 are
`action_class='analysis'`.** Demand: 0 customers, 0 inquiries, 0 quotes, 0 transactions.

The brief proposed gating `fn_workflow_step_claim`. That path is **4.2%** of spend. The money is
`cos_execute`. Both are gated now; the second one matters.

### What shipped

`fn_cos_work_gate()` + `decision_policy.cos_reflection_tasks_per_day` (6). **The gate is on the WORK,
not the model.** Revenue-path tasks are never capped; self-analysis has a daily ceiling. It opens by
itself — it asks whether *this task* is on the revenue path, never whether the company is busy yet.
Same split applied to `fn_workflow_step_claim`, whose single 24/day ceiling had been rationing
revenue work and reflection together.

### Verified

```
production, ceiling spent : cos_execute returned gated:true worked:0
                            ai_cost_log gained 0 rows / 0.0000 AED
staging,   ceiling has room: processed:2 done:2 — two real deliverables,
                            reviewed and approved by ops_director and the Chief of Staff
fn_workflow_step_claim    : aborted probe — reflection refused at 24/6, and a step
                            reclassified onto the revenue path in the SAME aborted
                            transaction WAS claimed
real cron, 09:50 UTC      : 1 run, 0 model calls, 0.0000 AED
```

**AED/day, before and after.** Before: 11.19–15.00/day on this path, every day since 6 Aug. After:
one real cron run has executed and spent **0.0000**. The honest 24-hour figure is not measurable yet
— re-run this to get it:

```sql
select (occurred_at at time zone 'utc')::date d, count(*) n, round(sum(cost_aed),2) aed
from ai_cost_log where occurred_at > now() - interval '3 days' group by 1 order by 1 desc;
```

### Two defects caught before shipping

1. **The counter over-counted by ten.** Keying on `result.mode <> 'executed_by_invoker'` misses the
   invoker's in-flight work, because that mode is written at *collect* time. The ten `Supply gap`
   kb_deepen tasks at 0.026 AED a call were being charged against a ceiling meant for a
   25,000-token one. Keyed on the `action_execution` row instead.
2. **Moving demand to the front would have promoted two high-risk invite tasks.** org_tasks
   **1360 and 1361** — "Start invites: kitchen-and-bathroom-suppliers", "Start invites:
   real-estate-agencies" — are `action_class='invite'`, `tier='autonomous'`, `status='assigned'`,
   wired to `fn_org_exec_invite` with `risk_tier='high'`, `advisory_safe=false`, `reversible=false`.
   They hold the highest ids in a 385-row FIFO queue, so **today they are unreachable**; promoting
   `invite` would have put a high-risk irreversible supplier mailing first in line on the day you
   wrote *"LAST — supplier invites. DO NOT ENABLE YET."* The gate now refuses any class wired to an
   unsafe executor. **Those two rows are still sitting there — worth a decision.**

### Still not done on spend

`agent_brain` sends **~22,000–25,500 input tokens per call** and `avg_cached_in` is **24 tokens**.
`decision_policy.prompt_cache_enabled` is false, set deliberately on 11 Aug when the read/write ratio
measured 0.115 against a 0.22 break-even — but `agent_runs.counts->>'stable_chars'` reads **0** on
every agent_brain turn, so the cache never had a prefix to hit. The stable/volatile split in
`agent_brain` is broken (`fn_agent_context_capped` trims the head the markers live in). Fixing the
split, then re-measuring the ratio over a full week, is the next real lever on the remaining bill.

---

## 3 — Vercel font fetch killed. #243

`src/app/[locale]/layout.tsx` imported four families from `next/font/google`; Next fetches every one
**at build time**. **11 Aug: 21:01 UTC failed on `space_grotesk`, 21:16 UTC on
`plus_jakarta_sans`** — different fonts, unchanged `src/`. Four network calls per build was the flake.

Now 11 woff2 in `public/fonts` (167 KB) via `next/font/local`; `scripts/fetch_fonts.mjs` pulled them
from Google's own CSS at the same unicode ranges the old `subsets:` asked for. Not wired into the
build — a build that fetches is the defect.

**Two defects found by measurement, neither visible in a screenshot:**

1. **A green build that silently dropped half the fonts.** Tajawal's `src` came from a helper
   function; `next/font/local` is a bundler *loader* that statically parses the call site, so `src`
   must be a literal. **The build still exited 0**, emitted 3 woff2 instead of 11, and both Arabic
   families vanished.
2. **The Latin half of Arabic never loaded.** Tajawal is declared as two families relying on
   per-glyph fall-through, but `next/font` emits a metrics-adjusted `"tajawal Fallback"` that covers
   *every* character and sat between them. Measured on `/ar`: all four `tajawalLatin` faces
   `unloaded`, `fonts.check('700 16px tajawalLatin','AED 12,400')` **false** — every AED figure in
   the Arabic locale in a system face. `adjustFontFallback:false` on the Arabic family only.

Verified in a running dev server, both locales; Vercel preview build **passed**.

**Note:** the local `npm run build` exits 1 with `InvariantError: Expected workStore to be
initialized` on 16 data-driven pages. **Not this change** — proved by stashing it and building the
unmodified tree: same failure, same count. There is no `.env` in this checkout.

---

## 4 — The revenue diagnosis. #244

### 0/6 is not real — confirmed and fixed at the source

All six pending rows carry `source='qd_demo_fixture'`, `matching_blocked=true`, `ZZ DEMO —` and
`@example.invalid`. The approver is correctly refusing companies that do not exist. **Real suppliers
awaiting approval: 0** — a worse number than six, because none has ever reached the queue.

`agent_brain`'s LIVE DATA SNAPSHOT is where the six entered the company's reasoning: `context()`
counted `approval_status='pending'` with no source filter and reported `kyc_pending: 6` to every
employee, every turn. Five other functions already exclude that source; the employee context did not.
One predicate, deployed to both.

### The real gate — three causes, each sufficient alone

1. **The trades were in a vocabulary the matcher cannot read.** `leads.invite_trades` held coarse
   category slugs; `fn_match_capability` matches `taxonomy_trade` codes. Of the 89 distinct values,
   **zero** appear in `lead_trade_map.catalog_slug` and none is a taxonomy code. Wrong on the merits
   too — #1 Amana Aluminium & Glass stored as `interior-fit-out…, manufacturing-by-process` when
   `fn_norm_trades` gives `aluminium, doors, glazing`; #2 Jama Auto Glass stored as
   `facilities-management-and-support-services`.
2. **The job that would fix it could only touch rows that did not need fixing** — cron 120's `WHERE`
   was `invite_trades is null`. `UPDATE 0` every day, forever.
3. **`enrich_capability` runs daily and cannot select a row** — requires `approval_status='approved'`
   (0) **and** `registration_submitted_at` (0 of 20,470). And it writes `leads.capability_summary`,
   not `supplier_capabilities`, so a full run would still leave the gate empty.

### What shipped, all SQL, zero AED

- `fn_leads_retrade(limit)` — bounded, idempotent, and now what cron 120 runs
- `fn_supplier_capability_derive(limit)` — derives `supplier_capabilities` from the directory

**Measured after:** `supplier_capabilities` **0 → 5,220**, all extracted inside 180 days,
**0 confirmed**. `fn_match_capability` gates on `confirmed_at is not null`, untouched — **not one
derived supplier became matchable.** Deriving a scope is not a supplier standing behind it; what
changes is that there is now something concrete to ask them to confirm, per trade.

`leads.invite_trades` in the taxonomy vocabulary: **634 → 8,292**. The rest is unfinished — see below.

---

## WHAT IS UNFINISHED, PRECISELY

1. **The trade re-normalisation has not converged.** 8,292 leads are in the taxonomy vocabulary;
   roughly 4,700 still hold the old slugs. `fn_leads_retrade` is bounded and idempotent and cron 120
   now runs `fn_leads_retrade(3000)` daily, so it converges on its own in ~2 days — or force it:
   `select public.fn_leads_retrade(1200);` repeatedly. Each call is ~50 s; a larger batch hits the
   statement timeout.
2. **~7,400 leads match none of the 25 taxonomy trades** and were written with empty trades. The
   taxonomy covers construction/fit-out; the directory also holds jewellery, aviation, laboratory
   and hospitality suppliers. Either the taxonomy needs extending or those suppliers are out of
   scope — **that is a business decision, not an engineering one.**
3. **`supplier_capabilities` derivation stopped at 5,220** of a possible ~13,000. The loop ends when
   a whole batch yields no trade; re-run `fn_supplier_capability_derive(900)` to continue.
4. **Item 5 — why 57 suppliers never registered — NOT STARTED.** This is the revenue-critical one.
5. **Items 6, 7, 8 — NOT STARTED.**
6. **The pack scorecard was not run on either project.** The Row #3 scorer was running against
   production and the two must not run against the same project at once.

## SWEEP AT HAND-OVER

| check | result |
|---|---|
| `fn_os_portals_gates()` | **23/23 met on BOTH projects** |
| `project_parity.mjs` | **BOTH PROJECTS IN SYNC** — 199 edge fns, 422 tables, 867 functions, 156 triggers, 0 tables without RLS |
| Supabase advisors, production | **0 ERROR** (452 INFO, 169 WARN) |
| GitHub Actions | green; only the merge of #244 in flight |
| Vercel | preview builds passed on #243 and #244 |
| OpenRouter | **not refusing** as of 10:00 UTC — but 44 calls failed in a burst 06:47–07:53 UTC today across exec_agents (15), kb_deepen (10), action_worker (9), agent_brain (7), dept_plan (3), against 3/day on 10 and 11 Aug. Fast-fail at ~500 ms for exec_agents, 26–56 s timeouts for the rest. Mixed causes, not diagnosed. |
| Row #3 scorer | see the run log; started 10:05 UTC |
| Pack scorecard | **NOT RUN** |
