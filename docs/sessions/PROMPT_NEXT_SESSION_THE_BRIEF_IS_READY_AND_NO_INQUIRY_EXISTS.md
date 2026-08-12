# Next session — the brief is ready and no inquiry exists

Start with the clock: `select now() at time zone 'utc';` — Dubai is UTC+4. Git commits are stamped +0400, the DB is UTC, same instant. Don't report the OpenRouter balance — but DO tell me if it's refusing calls.

THE STANDARD. THE COMPANY CAN OPERATE, LEARN, MANAGE ITSELF, IDENTIFY PROBLEMS, MAKE PROFESSIONAL DECISIONS, IMPROVE ITS PERFORMANCE, AND ACTIVELY WORK TOWARD AED 1,000,000 BY AUGUST 2027 WITH MINIMAL FOUNDER INVOLVEMENT. Not "the agent exists". Not "the workflow runs".

YOUR AUTHORITY is total on architecture, agents, org structure, workflows, KPIs, learning, observability, orchestration. Decide it and tell me after. Stripe refunds, spending money, and flipping the three go-live switches still need me.

---

## WHAT CHANGED ON 12 AUG — do not re-derive, do not redo

24 PRs merged (#251–#274), both projects, each verified by execution. Read `docs/sessions/HANDOVER_2026_08_12_*` parts 1–4 before touching anything.

Headlines:

* **The supplier path is walked.** Lead 30466 registered end to end on production — invite e-mail → OTP from a real inbox → claim → licence read 6/6 fields at `high` → approved → `confirmed_at`. `fn_match_capability` returns it for an HVAC job in Dubai. First matchable supplier this company has ever had.
* **The first customer exists.** `customers` 0 → 1 (`ahmadmhdnabilalzain+qdcust1@gmail.com`), created through the real `login_otp` + `kyc.save_customer` path.
* **All ten workflows are classified.** 163 of 163 step definitions carry an `action_class`. `refund` step 8 — *Execute the refund in Stripe* — had `gate = none` and is now `gate = founder`.
* **Reputation stopped inventing scores.** 75 employees who had never run were sitting at 51.0, one point above probation. Now 57 `unmeasured` with NULL score; 3 fell to real probation on genuine readings.
* **`org_tasks.assigned_agent` had no writer anywhere.** 339 tasks were "assigned" to nobody. `fn_org_task_assign` runs hourly; employees holding work 5 → 33.
* **Seven event types reached nobody**, including `payment.received` and `customer.registered`. Subscribed; 89 events delivered.
* **1,566 leads culled** by MX sweep; **519 recovered** from a hyphen (`building-materials` vs the alias `building materials`). `in_vocab` 16,445 → 16,964.
* **The scenario tally was inverted** — reported 32 gaps when the truth is 32 staffed.

---

## 1 — THE BRIEF IS READY AND NO INQUIRY EXISTS. START HERE.

I walked the demand path to its last step and it stops one row short.

```
customers                       1     created via kyc.save_customer
inquiry_intake session          18e2c133-f728-464a-b5f1-43d1f9dc3c1e
  category hvac · trades ["hvac"] · urgency normal
  final status                  ready
  assistant: "All set — I have everything needed to send your 40 TR
              ducted split project out to suppliers for quoting."
inquiry_id returned             NONE
select count(*) from inquiries  0
```

The intake conversation completes, classifies correctly as `hvac`, gathers cooling load, zones, ceiling height, condenser location, budget and timeline, declares itself **ready** — and creates no `inquiries` row. Find what is supposed to promote a `ready` intake into an inquiry and whether it has ever run. Ask the two questions that found almost everything: *has this path ever actually executed?* and *what does the user CLICK?*

If it needs building, build it. Then the loop closes for the first time: inquiry → `fn_match_capability` → lead 30466 (already confirmed, already matchable, already HVAC in Dubai) → RFQ. `rfq_handling`'s twelve steps are now all classified, so the workflow can move.

**Do not fabricate an inquiries row to make this look done.**

## 2 — THE CUSTOMER PORTAL SIGN-IN, PROPERLY DRIVEN

I could not make `/me`'s "Send me a code" fire from the browser tools — the field's React state stayed empty while the DOM value updated, so `send()` early-returned. **I could not isolate this from my own tooling and I am not claiming it is a defect.** The backend is fine: the same call by HTTP returns 200 and issues a code, and the identical component pattern in `/portal` worked this morning.

Drive it with a tool that produces real React change events, or add one Playwright check, and settle it. If it IS broken, it is the demand front door and nothing else matters more.

## 3 — s36: FOUR FIELDS THAT DO NOT EXIST

`s36-recommendation-seven-fields` is the last genuinely buildable Row #3 item. `agent_actions` has `evidence`, `risk`, `confidence` (all non-null) and **no column at all** for `assumptions`, `expected impact` or `cost`. I added `alternatives` today, filled by trigger from the linked `decision_log` row — extraction, never authoring — and 101 rows carry it.

The other three need a real source per writer across 41 routines. **Adding them with defaults satisfies the letter and defeats the spec.** The check also needs every row in a 30-day window, so it cannot flip for a month regardless.

## 4 — INVITES: THE NUMBER YOU ASKED FOR

All five bounces are **role addresses on domains with live MX**, every one flagged `email_verified` by the scrape. The MX cull removed 1,566 certain bounces and **zero of the five observed** — these are mailbox-level failures and MX is a domain-level test.

```
role addresses      58 invited   5 bounced   8.6%
personal             4 invited   0 bounced   n=4, too small to compare
```

Role addresses are now deprioritised, not deleted (5,870 of 19,835 publish no other address). Probed: the next run would queue 9 invitations, all to named humans, zero `info@`. `invite_enabled` stays **false** — 8.6% against an 0.08 brake, and the 3-day brake window is empty so auto-pause would not engage until 15 had gone. The cheap next test is an SMTP `RCPT TO` probe: free, but it touches third-party mail servers and can cost sender reputation. **That is a reputation decision and it is yours.**

## 5 — ROW #3 IS 127/152. MUCH OF THE RESIDUE IS TIME, NOT CODE.

Run `node scripts/staging/verify_os2_blueprint.mjs`. Save the verdict list.

**Already fixed, waiting to age into their windows** — do not rebuild these:
* `explain-knowledge-used` — all 29 uncited decisions are 5–6 Aug. Clears **13 Aug**.
* `explain-alternatives-considered` — `decision_log.alternatives` hit **67 of 67 (100%) on 12 Aug**; the surface shows the last 15 escalations, which predate it.
* `s24-board-before-major-decisions` — probed live, a new decision draws **7 of 7 advisors**. One historical row (decision 42, executed 6 Aug). Clears **5 Sep**.
* `s21-no-polling` — events occurring in the last 24h have **median lag 0s, 258 of 258 under 60s**. The 264s figure is backfill pollution, and my new subscriptions will make it look worse first.

**Blocked, not broken:** `s22` (needs customer/rfq/quote/revenue node kinds), `s29` (needs external search-term data, Apify paused to ~Feb 2027), `s30` (churn and CSAT with zero customers), `s32` + `employee-learning-progress` (the exam loop's second pass), `s33` (next outcomes due 19 Aug), `s34` (`fn_scenario_run` deliberately refuses to stamp `last_run` — a staffing check is not a rehearsal), `what-if-*` (six stored simulations keep their old shapes; rewriting a stored result would change an answer the company may have acted on), `s23` (marketing budget and supplier capacity have genuinely never been reallocated).

## 6 — SPEC #3 UI, still open

Interactive documents, drag & drop, workspace snapshots, live collaboration, visual workflow builder, persistent AI panel. `AgentDrawer` in `src/components/osx/OsxShell.tsx` is the employee workspace; `fn_ws_agent_ops(p_agent)` feeds it. You told me on 10 Aug the dashboard was disappointing — your judgement of the screen outranks the score.

## 7 — BoQ fixtures: BLOCKED ON INPUT

`boq_fixture` has 2 rows and both drawings are already fixtures. Adding more needs new drawings with printed ground truth. Ask me for them or generate synthetic plans and run them through the real OCR path — do not invent expectations for a drawing nobody has read.

---

## SMALLER THINGS STILL OPEN

* **66 legacy parked workflow step-runs** with NULL `action_class` — residue from paths already completed or never walked, not backlog. `customer_registration`'s 56 and `employee_task`'s 986 were deliberately left parked (OTP against phantom customers; a shadow of `org_tasks`).
* **`exec` generates 3× the work it staffs** — the assigner's run note names it: `exec 77/28, knowledge 24/21, sales 17/15`. That is a hiring signal and it is yours to act on.
* **41 tasks still unowned** behind `max_open_per_dept` backpressure. Correct behaviour, not a fault.
* **`kb_deepen` and `exec_agents` now return their work** in the response body; `action_worker`'s `outcome` is extracted. Re-measure the 204 → 458 of 556 figure after a full day.
* **Priority knowledge embedding** — `trade`/`regulation`/`material` 100% on staging, ~730 of 2,090 and climbing on production via `kb_embed_priority_kinds`. Free.
* **`prompt_cache_enabled` still false.** Split now works: 81.3% of context byte-stable, boundary at 17,501 chars. Predicted hit rates **58.5% at 5-min TTL, 89.0% at 1-hour** against break-evens of 22% and 53%. Re-measure a full week, then decide.

## TRAPS LEARNED TODAY — these cost me time

* **`apply_sql --promote` carries ONLY the routine definition.** A `revoke`, `insert` or `update` in the same file lands on staging alone. It left `fn_org_task_assign` anon-executable on production; `project_parity` caught it, I did not.
* **Every `cron.schedule` needs a `cron_registry` row in the same change.** I added one without it and dropped Row #3 to 126.
* **`_` is a WORD character in Postgres regex** — `'ai_budget_aed' ~* '\yai\y'` is false. Same shape as `building-materials` against the alias `building materials`. Normalise separators; never loosen the anchors.
* **`fn_event_dispatch`'s argument is `lookback_minutes`, not a batch size** — but `<= 0` disables the limit and the cron passes nothing, so events ARE reconsidered. I claimed otherwise in a commit and corrected it in the PR body.
* **Two vocabularies drift and nothing fails.** Four instances in one day: `invite_trades`/`taxonomy_trade`, `outcome`/`deliverable`, `ai_budget_aed`/`\yai\y`, `staffed`/`ready`. Ask of any counter: *is this measuring what its name says?*

## SWEEP EVERY TIME

Actions · Vercel · both projects · Row #3 with verdicts saved · pack scorecard both · `fn_os_portals_gates()` both · `project_parity.mjs` → BOTH PROJECTS IN SYNC · `select count(*) from cron.job j where j.active and not exists (select 1 from cron_registry r where r.jobname=j.jobname)` = 0 on both.

## STATE AT 2026-08-12 ~15:10 UTC

```
Row #3        127/152 · gates 23/23 both · parity IN SYNC · advisors 0 ERROR both
workflows     163/163 steps classified · refund Stripe step gate=founder
suppliers     20,471 leads · 16,964 in vocabulary · 18,037 sendable · 1 CONFIRMED and matchable
customers     1 · inquiries 0 · quotes 0 · transactions 0
tasks         employees holding work 33 · 41 unowned behind backpressure
reputation    57 unmeasured · 22 standard · 8 trusted · 3 senior_trusted · 3 probation
knowledge     retrievable 56.2% prod · trade/regulation/material 100% staging, draining prod
spend         17.60 AED today · 0 model failures in 3 hours · OpenRouter quiet since 09:00
switches      invite_enabled false · marketing_golive false · bd_outreach_enabled false — ALL YOURS
```

Do not stop and do not check in. Take the next item. Keep going until I say stop. If you hit a hard limit that makes further work unreliable, say so plainly and name exactly what is unfinished.
