# NEXT SESSION — the funnel is open. Now fill it.

Start with the clock: `select now() at time zone 'utc';` — Dubai is UTC+4. Git commits are stamped
+0400 and the DB is UTC; same instant. Don't report the OpenRouter balance — but DO tell me if it's
refusing calls.

THE STANDARD. THE COMPANY CAN OPERATE, LEARN, MANAGE ITSELF, IDENTIFY PROBLEMS, MAKE PROFESSIONAL
DECISIONS, IMPROVE ITS PERFORMANCE, AND ACTIVELY WORK TOWARD AED 1,000,000 BY AUGUST 2027 WITH
MINIMAL FOUNDER INVOLVEMENT. Not "the agent exists". Not "the workflow runs".

YOUR AUTHORITY is total on architecture, agents, org structure, workflows, KPIs, learning,
observability, orchestration. **Do not escalate anything you can derive from the AED 1M objective,
the specs, or the operating model.** Last session I was asked whether the trade taxonomy should grow
— with 20,470 suppliers in the directory and zero RFQs, that was derivable. Decide it and tell me
after. Stripe refunds still need me.

---

## WHAT CHANGED ON 12 AUG — do not re-derive, do not redo

Eight PRs merged (#242–#249), both projects, each verified by execution.

* **The spend.** `cos_execute_hourly` was 92% of agent_brain's Anthropic calls and ~60% of all
  spend — 11–15 AED/day every day since 6 Aug, when a 346-row self-analysis queue appeared. Gated:
  `fn_cos_work_gate()` + `decision_policy.cos_reflection_tasks_per_day` (6). Revenue-path work is
  never capped; the gate opens by itself when a demand task exists. Same split applied to
  `fn_workflow_step_claim`. **Measured after: two cron runs, 0 model calls, 0.0000 AED.**
* **Vercel.** Four `next/font/google` families fetched at build time. Now 11 self-hosted woff2 via
  `next/font/local` + `scripts/fetch_fonts.mjs`. Preview build passed.
* **The supplier directory.** `leads.invite_trades` held category slugs; `fn_match_capability`
  matches `taxonomy_trade` codes. **16,444 leads converted, 0 left in the old vocabulary.** Taxonomy
  grown 25 → 40 trades. `supplier_capabilities` 0 → **15,305**, all confirmable, **0 confirmed** —
  the `confirmed_at` gate is untouched and no supplier became matchable.
* **The invitation had no link.** 62/62 had empty `html`, no URL in the body, and copy saying "use
  the button below". Now carries `https://quotesdone.com/en/portal?t=<claim_token>`. The portal
  reads `?t=` and claims the lead. `invite_status` now advances past `queued`.
* **The scope screen.** `capability_agent.confirm` is the only writer of `confirmed_at` and had **no
  caller anywhere**. Built the confirmation panel (`scope` tab), proxied through `supplier_api` so
  the supplier id comes from the JWT, never the client.
* **Two goal measures** added (`knowledge_modules_complete` = 5.38 vs 100;
  `knowledge_review_cycle` = 50 vs 90). Attainment went DOWN, correctly — unmeasured goals were
  scoring as perfect via `least(100.0, NULL)`.
* **Employee learning is visible** — `fn_ws_agent_ops` emits a `learning` block, AgentDrawer renders
  it.
* **org_tasks 1360/1361** ("Start invites…", high-risk irreversible executor) moved to `proposed`.

---

## THE ORDER. NOT NEGOTIABLE.

### 1 — THE REGISTRATION PATH HAS NEVER BEEN WALKED BY A HUMAN

Everything in the funnel is repaired but **not one real supplier has completed registration**, and
the scope screen **has never been rendered in an authenticated session**. I could not create one: it
needs a real work email and an OTP.

**Do this first and do it for real.** Create a supplier account end to end — invite link → portal →
sign-up → OTP → claim → company profile → trade licence upload → submit → approval → **scope tab →
confirm**. Use a mailbox you control. Then check, in this order:

```sql
select claimed, claimed_by, portal_updated_at, registration_submitted_at, approval_status
  from leads where claimed_by = '<the email>';
select confirmed_at, trades, roles from supplier_capabilities where supplier_id = <that lead>;
```

`confirmed_at is not null` on one real row is the first time this company has ever had a matchable
supplier. Until then everything above is plumbing.

If the demo fixture path is easier, `source='qd_demo_fixture'` is the convention — but a fixture
does not prove the OTP, the upload or the licence read.

### 2 — THE DECISION CONTRACT: 513 DECISIONS A WEEK, 33 OUTCOMES

Already a **priority-1 `spec_backlog` row**, `spec_ref='s33-replay-six-tracks'`. Measured:

```
 6 Aug  67 decisions  1 outcome     10 Aug  82 decisions  15 outcomes
 7 Aug  29 decisions  0 outcomes    11 Aug 142 decisions   0 outcomes
 8 Aug  61 decisions  0 outcomes    12 Aug  62 decisions  17 outcomes
 9 Aug  70 decisions  0 outcomes
```

`fn_outcome_open` is the only writer of `outcome_record` and its only callers are `fn_kpi_review`
and `fn_os_improve` — **both weekly**. `decision_log` has no `expected_kpi_id` /
`expected_direction` / `measure_after`, and `fn_outcome_open` requires all three.

**DO NOT close this by inferring the KPI from decision text.** That writes a fabricated causal claim
into the ledger the company uses to decide what worked. The fix is the contract: add the three
columns, have the ~20 routines that write `decision_log` supply them **where the decision genuinely
claims an effect** and leave them null where it does not, then open `outcome_record` from that.

This is the founder's operating model failing at its centre. A company that cannot say whether last
Tuesday's decision worked is keeping minutes, not learning.

### 3 — THE REMAINING SPEND LEVER: agent_brain's PROMPT

`agent_brain` sends **22,000–25,500 input tokens per call** and `avg_cached_in` is **24 tokens**.

* `decision_policy.prompt_cache_enabled` is **false**, set 11 Aug because the read/write ratio
  measured 0.115 against a 0.22 break-even.
* But `agent_runs.counts->>'stable_chars'` reads **0** on every agent_brain turn — the cache never
  had a prefix to hit. The stable/volatile split in `agent_brain` looks for three `# LAYER …`
  markers that `fn_agent_context_capped` trims away.

Fix the split first, re-measure the ratio over a full week, then decide the switch. Memory: cache
`cache_control` only pays on a byte-stable prefix; 5-min TTL breaks even at 22%, 1h at 53%. Worth
roughly 6 AED/day.

### 4 — CULL THE INVITE LIST (free, and it is NOT sending)

19,835 eligible leads. Measured:

| | |
|---|---|
| role addresses (`info@`, `sales@`, …) | **5,897** |
| syntax invalid | **226** |
| freemail (gmail/yahoo/hotmail/outlook) | **3,995** |
| distinct domains | **8,928** |

Syntax-invalid bounce for certain. **MX lookup on 8,928 domains has not been done** — that is most
of what a paid verifier does, at zero cost. Role addresses are a *conversion* problem, not a bounce
problem, and in UAE B2B `info@` is often the only published address — deprioritise, do not delete.

Current bounce is 5/62 = 8.06%, at the 0.08 brake. `invite_enabled` is `false` and
`enqueue_supplier_invites` returns 0 immediately. **Leave it that way until item 1 is proved.**

### 5 — Row #3 is 127/152. 25 MISSING.

Run `node scripts/staging/verify_os2_blueprint.mjs` for the current list. Several are demand-blocked
(`intel-customer-behavior`, `s26-discover-suppliers` — **Apify paused to ~Feb 2027, do NOT "fix"**).

Closest to real:

* `s33-replay-six-tracks` — that is item 2 above.
* `explain-knowledge-used` — 494 of 526 decisions name their knowledge. 32 short.
* `s24-board-before-major-decisions` — 10 of 11. One short.
* `s30-marketplace-eight-inputs` — 5 of 8 inputs non-null.
* `employee-learning-progress` — **UI is now built.** It also needs every active employee to have
  two dated exam results; 0 of 93 do. `fn_exam_pick_agent` orders by `last_exam asc nulls first`, so
  the loop **does** wrap — it finished its first pass over the 98-agent roster on 12 Aug (17 days at
  5.8/day). The second pass closes it on its own. **Do not fabricate an exam.**

### 6 — SPEC #3 UI, still open

Interactive documents, drag & drop, workspace snapshots, live collaboration, visual workflow
builder, persistent AI panel (a Secretary chat already exists). `AgentDrawer` in
`src/components/osx/OsxShell.tsx` is the employee workspace; `fn_ws_agent_ops(p_agent)` feeds it.

### 7 — BoQ fixtures: BLOCKED ON INPUT, NOT CODE

`boq_fixture` has 2 rows and **both drawings in the corpus are already fixtures** (documents 4 and
10). Fixture 1 asserts doors + windows + area; fixture 2 asserts area (`expect_rooms_sqm` 48.0 —
its drawing prints no door/window schedule). KPI 103 reads 100.00 vs 95 off those four assertions.
`fn_boq_fixture_score` is honest — `score_pct` is NULL when nothing is checked, and the runner
filters non-finite before averaging.

**Adding fixtures needs new drawings with printed ground truth.** Ask me for them or generate
synthetic plans and run them through the real OCR path — do not invent expectations for a drawing
nobody has read.

### 8 — LAST: supplier invites. STILL DO NOT ENABLE.

Order: prove item 1 → cull (item 4) → ramp small, halt at the brake. Still >8% after the cull? That
is a money decision — bring me a number.

---

## SMALLER THINGS I FOUND AND DID NOT FIX

* **#236 fires but most executors emit nothing to extract.** Over 7 days, only **204 of 554**
  succeeded invocations carry `recommendation`/`deliverable`/`note`. `analytics_recommend` is
  203/203. `kb_deepen` 0/70, `exec_agents` 0/15, `action_worker` 1/253. One line in `kb_deepen`'s
  response body would put its real work (topics added) into the learning loop.
* **`capability_agent` has no scoped credential** — `cred_fn_capability_agent` does not exist. I
  widened `fn.supplier_api`'s scope instead. If anything else needs to call it, issue a proper
  credential rather than widening again.
* **~4,000 leads still match no trade** even at 40 trades — `in_vocab` 16,444 of 20,470. Either the
  taxonomy grows again or those suppliers are out of scope. **Decide it, don't ask.**
* **`kb_chunks` retrievable: 53.6% prod / 47.0% staging.** NOT EMBEDDED at all: `trade` (2,042
  rows), `regulation` (45), `material` (3) — no semantic path to any of them. Embedding is free
  (in-region gte-small); batch above 5 returns HTTP 546, so add invocations, never batch size.
* **OpenRouter refused 44 calls in a burst 06:47–07:53 UTC on 12 Aug** — exec_agents 15 (fast-fail
  ~500 ms), kb_deepen 10, action_worker 9, agent_brain 7, dept_plan 3, against 3/day on 10 and 11
  Aug. Not diagnosed.
* **Only 2 of the 6 pack zips are in `~/Downloads`.** I extracted them to `~/qd_packs` and the
  scorecard ran on both projects anyway (it scores DB rows against the pack dir).
* **staging `pricing_config` was empty** while production had one row — so every staging
  registration took the `pending` branch the founder removed on 2 Aug. Copied down. Shape parity
  will not catch this class; check row-level config when a behaviour differs.

---

## HOW TO WORK

Verify by execution on a non-zero effect, never an HTTP 200. Aborted-transaction probe for writes.
Both Supabase projects. Merge via PR. Never weaken a check. Never state anything unmeasured. Save
the Row #3 verdict list every run.

**The two questions that found almost everything on 12 Aug:**

1. *Has this recovery path ever actually executed?* — `cron.job_run_details.return_message` reading
   `UPDATE 0` every day is the signature, and it costs one query.
2. *What does the user CLICK to reach this?* — five finished, hardened capabilities had no caller:
   `capability_agent`, `claim_lookup`, `supplier_api.claim`, the invite body, and `/claim` (which
   404s). Nothing fails, so no watcher sees it.

**Traps:** `next/font/local` needs a LITERAL `src` — a helper makes the build exit 0 while dropping
fonts · `next/font`'s auto-fallback family sits between two real families and defeats per-glyph
fall-through · a predicate that calls a normaliser gets slower as a backfill converges · a cron
pointed at a windowed function with a fixed cursor re-walks the same rows for ever ·
`least(100,NULL)=100` · `fn_agent_context` ignores `p_max_chars` below 22,000 — use
`fn_agent_context_capped` · PostgREST runs as `authenticator` with `statement_timeout=8s` ·
`config.toml` is GENERATED · `--promote` without `--ddl` carries no DML · `qd_guard` refuses the
production ref even in comments · a PARTIAL scorer run is not a score.

**Sweep every time:** Actions · Vercel · both projects · Row #3 with verdicts saved · pack scorecard
both · `fn_os_portals_gates()` both · `project_parity.mjs` → BOTH PROJECTS IN SYNC.

---

## STATE AS OF 2026-08-12 ~11:20 UTC

```
Row #3        127/152 · gates 23/23 both · parity IN SYNC · advisors 0 ERROR both
packs         INGESTED 100% · IN USE 37/37 · RETRIEVABLE 53.6% prod / 47.0% staging
leads         20,470 · 16,444 in the matcher's vocabulary · 0 in the old one
taxonomy      40 active trades (was 25)
capabilities  15,305 derived · 15,305 confirmable · 0 confirmed
invites       62 sent (57 sent + 5 bounced) · invite_enabled=false · 0 registrations
spend         0.0000 AED since the gate at 09:40 UTC, across 2 cos_execute cron runs
              (that path cost 11-15 AED/day every day from 6 Aug)
demand        customers 0 · inquiries 0 · quotes 0 · transactions 0 — UNCHANGED
```

Do not stop and do not check in. Take the next item. Keep going until I say stop. If you hit a hard
limit that makes further work unreliable, say so plainly and name exactly what is unfinished.
