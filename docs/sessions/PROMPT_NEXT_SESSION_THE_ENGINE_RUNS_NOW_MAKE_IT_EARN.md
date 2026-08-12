# NEXT SESSION — the engine runs. Now make it earn.

Read `docs/sessions/HANDOVER_2026_08_11_THE_ENGINE_GOT_ITS_EMPLOYEE_SIDE.md` first — sections 1–16.
It carries every measurement below and the reasoning, so you do not re-derive them. The
`quotesdone-session` skill applies automatically.

The specs are the contract, all eight:

```
C:\Users\Opera\OneDrive\Desktop\quotesdone archeticture.txt
C:\Users\Opera\OneDrive\Desktop\OS.txt
C:\Users\Opera\OneDrive\Desktop\OS 2.txt
C:\Users\Opera\OneDrive\Desktop\customer portal.txt
C:\Users\Opera\OneDrive\Desktop\supplier portal.txt
C:\Users\Opera\OneDrive\Desktop\suppliers categories.txt
C:\Users\Opera\OneDrive\Desktop\quotesdone agents and knowledge.txt
C:\Users\Opera\OneDrive\Desktop\open router.txt
C:\Users\Opera\Downloads\QuotesDone_*_v2026.07.31.zip   (all six)
```

Start with the clock: `select now() at time zone 'utc';` — Dubai is UTC+4. **The git commits are
stamped +0400 and the DB is UTC; they are the same instant.** Last session lost time to that.
Do not report the OpenRouter balance — but DO tell me if it is refusing calls, because on 12 Aug it
was, and that gated every employee-reasoning path for 25 minutes.

THE STANDARD — the only definition of done. THE COMPANY CAN OPERATE, LEARN, MANAGE ITSELF, IDENTIFY
PROBLEMS, MAKE PROFESSIONAL DECISIONS, IMPROVE ITS PERFORMANCE, AND ACTIVELY WORK TOWARD AED
1,000,000 IN REVENUE BY AUGUST 2027 WITH MINIMAL FOUNDER INVOLVEMENT. Not "the agent exists". Not
"the workflow runs". Not "the table was created."

The one business objective is AED 1,000,000 by August 2027, and it must flow downward: management
decides what departments must achieve, departments decide what employees must achieve, employees
decide how to execute. I do not define the method. The system derives it.

YOUR AUTHORITY is unchanged and total on architecture, agent design, org structure, workflows, KPIs,
learning mechanisms, observability and orchestration. Correct bad work, connect disconnected work,
replace what prevents the intended behaviour. Escalate only what cannot be inferred from the AED 1M
objective, the specs, or the operating model. Stripe refunds still need me.

---

## THE ORDER, AND IT IS NOT NEGOTIABLE

The founder's instruction, 12 Aug: *"logically you need to finish all those before you worry about
invitation."* He is right. Work the backlog first. **Sending invitations is the LAST item on this
page**, and the only thing above it that touches suppliers is finding out why the ones already
invited never registered — which is a broken capability on the revenue path, not invite work.

```
1  confirm #236 fires                       one query
2  Vercel: kill the build-time font fetch   diagnosed, small, closes a known failure mode
3  the dispatcher's 24/day cap              one CREATE OR REPLACE, ours to decide
4  WHY 57 SUPPLIERS NEVER REGISTERED        revenue-critical. NOT sending. Do not skip.
5  BoQ fixtures + the goals/KPIs worth doing
6  spec #3 UI
7  ...then, and only then, supplier invites
```

---

## 1. THE FIRST THING — one query, and it is the highest-value single check

**Finish this before starting anything else.** The pattern that produced every mistake of 12 Aug was
moving to the next thing before the check in front of me was done: a step marked done on a truncated
deliverable, three claims asserted before they were measured, a reason written as "needs a fixture"
when it was "needs demand", and a whole priority list reordered because the founder mentioned
invites mid-sentence. Work items in order. Verify each one before opening the next.

`fn_action_invoke_collect` used to close a task writing only a 500-character `summary` and never
`result.deliverable`. **Ten routines read `deliverable`** — `fn_task_lesson`,
`fn_learning_loop_sweep`, `fn_task_review`, `fn_ws_company_os` among them — so **93 completed tasks
produced real work that never entered the learning loop, was never reviewed, and never reached my
screen.** PR #236 fixed it forward. It has never been observed firing.

```sql
select id, result->>'mode' mode, left(result->>'deliverable',120) deliverable, updated_at
from org_tasks
where status='done' and result->>'mode' in ('executed_by_invoker','executed')
order by updated_at desc limit 5;
```

If the newest rows carry a deliverable, ~86 tasks a month rejoin the learning loop and you can move
on. If they do not, that is the bug to fix before anything else.

**The example that proves why this matters:** `org_tasks` 1309 — the AI-spend escalation I asked for
a decision on — had already answered it, and the answer was invisible:

> *"Redirect AI spend from internal automation and quote optimization to diagnosing why the
> 20,470-supplier directory generates zero RFQs and why supplier approval is stuck at 0/6 — these
> are the revenue gates, not AI quality."*

**That is the company telling us where the AED 1M is blocked. Treat it as the session's theme.**

---

## THEN, IN ORDER

### 1. Vercel: kill the build-time font fetch — VERIFIED CAUSE, 12 Aug

Three production builds failed on 2026-08-11 between 21:01 and 21:16 UTC. Cause is confirmed and is
NOT "mechanism unknown" as the old traps list says:

```
21:01 build  Module not found  space_grotesk_4a3aa992.module.css
21:16 build  Module not found  plus_jakarta_sans_d01242c0.module.css
             Error: Command "npm run build" exited with 1
```

**Different fonts on different builds.** `src/app/[locale]/layout.tsx` imports FOUR families from
`next/font/google` — Space_Grotesk, Plus_Jakarta_Sans, JetBrains_Mono, Tajawal — and Next fetches
every one from Google **at build time**. Any single failed fetch emits a CSS module referencing font
files that do not exist, and the build dies. Four network calls per build is the flake.

**Fix: download the four woff2 files into the repo and switch to `next/font/local`.** No fetch, no
flake. Verify the rendered pages afterwards — this is a visual change and needs a real look, which
is why I did not do it at the end of a long session. The last 40 deployments are READY, so this is
prevention, not an outage.

### 2. The dispatcher's 24/day cap — I am asking you to decide it

107 workflow steps are ready and the cap clears them in 4–5 days. It exists because 85.4% of model
spend went to `leadership` and 0.04% to `marketplace` against revenue of 0.
**The company has now answered that question itself** (see the quote above) and its answer is *shift
toward demand*. Read `scripts/sql/the_dispatcher_needed_a_daily_ceiling_before_it_needed_speed.sql`,
then make the call — raise it, keep it, or split it so marketplace work is uncapped and internal
work is not. One `CREATE OR REPLACE`. Tell me which you chose and why.

### 3. Act on the company's own revenue diagnosis

Its two named gates were **the 20,470-supplier directory generates zero RFQs** and **supplier
approval is stuck at 0/6**.

**THE SECOND GATE IS NOT REAL — measured 12 Aug after the diagnosis was written.** All six "pending
approvals" are seeded test fixtures:

```
ZZ DEMO — Al Barsha HVAC Trading        qd-demo-supplier-005@example.invalid
ZZ DEMO — Al Noor HVAC Manufacturing    demo-supplier@example.invalid
ZZ DEMO — Capital Mechanical Works      qd-demo-supplier-006@example.invalid
ZZ DEMO — Emirates Air Engineering      qd-demo-supplier-003@example.invalid
ZZ DEMO — Gulf Climate Systems          qd-demo-supplier-002@example.invalid
ZZ DEMO — Northern Cooling Contracting  qd-demo-supplier-004@example.invalid
```

Every one is labelled *"not a real company"* in its own name and sits on `@example.invalid`.
Approval automation is not stuck — it is correctly refusing to approve companies that do not exist.
**Do not go looking for a broken approver.** It is a decorative number, the same defect class as
`ocr_coverage_pct`, and the honest fix is to exclude `ZZ DEMO` fixtures from that count wherever it
is computed. **Not one real supplier has ever reached the approval queue**, because none has ever
started registration — which is item 4 below, not this one.

The FIRST gate is real. `s26-compare-capabilities` reads "0 capability record(s) against 0 approved
supplier(s), 0 extracted in 180d" — 20,470 rows of supplier data and no processing over it. Start
there. **Apify stays paused until ~Feb 2027; work the existing leads.** Do not "fix"
`s26-discover-suppliers`.

### 4. WHY 57 REAL SUPPLIERS NEVER REGISTERED — revenue-critical, and NOT invite work

62 invitations were genuinely sent (5 hard-bounced through the Resend webhook and are in
`email_suppressions`; the other 57 show no bounce). **Zero recipients ever started registration** —
`registration_submitted_at` is 0 across all 20,470 leads.

**Walk the path yourself**: invite link → supplier portal → company profile → submit → trade-licence
upload → approval queue. Find out whether it is broken or simply unpersuasive, and fix what breaks.
Until one real registration completes end to end, sending more invitations burns addresses for
nothing — which is why the invite section is at the bottom of this page and this is not.

Note `invite_status` never advances past `queued` on success — only the bounce webhook writes back.
That is a tracking gap worth closing while you are in there; it is what made "were these even sent?"
unanswerable without cross-checking `email_suppressions`.

### 5. Goals and KPIs still without a measure — 34 and 14

Every one now carries a written `no_measure_reason`, so none is silently decorative. Re-read those
reasons before building: two of mine were the wrong KIND last session (I wrote "needs a fixture"
where the truth was "needs demand", and the distinction decides whether you build or wait).
- **103 is done** — the BoQ fixture set exists and scores 100.00 against a target of 95. **Add more
  fixtures**; two drawings and four checks is a thin instrument.
- **114** needs a holdout of qualified RFQs and there are 0 inquiries. Blocked.

### 6. The remaining spec #3 UI

Landed last session: the workflow screen ("Processes in flight", with what each run waits on) and
"What the company's processes produced". Still open: **interactive documents, drag & drop, workspace
snapshots, live collaboration, visual workflow builder**, and making the AI side panel persistent —
note it is *less absent* than the spec implies, a Secretary chat and a per-entity `askAI` already
exist in `OsxShell`.

---

## LAST — supplier invites. Everything above comes first, and the gate is still NOT met

On 12 Aug the founder delegated this: *"you can proceed once you are 100% sure that suppliers won't
have an issue when they register... in case we ever get banned on the email from spam or any issue
that's gonna be on you. I have no clue about the limits per day... its your responsibility."*

**DO NOT ENABLE INVITES YET.** His condition is not met and the measurement says so:

```
20,470 leads · 19,903 with an email
    62 ever invited
     0 registration_submitted_at   <- not one supplier has EVER started registration
     0 approved
```

62 invitations, zero registrations started. That may be a broken path or it may be cold outreach
being ignored — **nobody has ever distinguished the two, and that is the job.**

**The domain risk is now ours to carry.** 7-day bounce is **13.3%**; providers throttle above ~5%
and block sustained double digits, and a burned sending domain takes the company's real customer
mail with it. `app_secrets.invite_max_bounce_rate` is already set to **0.08** and the live rate is
above the platform's own brake. At the 10/day cap the list takes 5.4 years anyway, so volume is not
available until the list is clean.

**Do these three, in order. None needs the founder's money:**

1. **Walk the registration path end to end yourself** — invite link → supplier portal → company
   profile → submit → trade-licence upload → approval queue. Find where it breaks and fix it.
   Until one real registration completes, every further invitation burns an address for nothing.
   `s26-compare-capabilities` reads "0 capability record(s) against 0 approved supplier(s)" — the
   supplier side has 20,470 rows of data and no working intake.
2. **Cull the list for free** — syntax validation, MX-record lookup, drop role addresses
   (`info@`, `sales@`, `admin@`) and dead domains. That is most of what a paid verifier does and
   should pull 13.3% under the 8% brake at zero cost.
3. **Only then ramp**, small batches, re-measuring bounce after each, halting automatically at the
   brake. If bounce is still above 8% after step 2, verification becomes a money decision — go back
   to him with the number, not with a request to "consider verification".


---

## WHAT I DECIDE, NOT YOU

* ~~Resuming supplier invites~~ — **DELEGATED TO US on 12 Aug**, conditional on proving the
  registration path works. See THE FIRST THING. The email-reputation risk is explicitly ours.
  Buying list verification is still money and still his, but only after the free cull.
* **Rotating the shared internal credentials** (below). It touches 172 cron jobs.
* Stripe refunds.

---

## FOUND, RECORDED, NOT FIXED — do not rediscover these

* **Staging and production hold BYTE-IDENTICAL internal credentials.** `inbound_secret`,
  `cred_cron_agents`, `cred_cron_monitoring` — same md5, same length. Anything with staging access
  can invoke production with full internal authority. Four staging crons were POSTing to production
  and are now unscheduled, but the credential sharing is the real defect and rotating it is my call.
* **`ocr_coverage_pct` reports 100%** in `document_kpi_snapshots` while 4 of 8 documents extracted to
  completely empty structure. It counts extractions that RAN, not ones that PRODUCED. Changing what
  it counts is a business definition — mine.
* **Four Row #3 checks measure the wrong population** and cannot be closed without fabricating:
  `s32` (only 14 of 93 employees have runs, 14 have cost, 13 have exams — six axes would need
  53–80 invented numbers each, and one axis has no column); `s36` (population is 487
  machine-generated incidents and 150 licence-expiry alerts, not deliberations); `s24` (its one
  unadvised "major decision" is *"which agent owns signage work"*, and it ages out 5 Sept);
  `explain-alternatives-considered` (`challenge_record` has 39 rows with alternatives and no join
  key to a surfaced action).
* **`explain-knowledge-used` needs no work** — 420 of 420 decisions since 6 Aug cite their knowledge;
  the 43 uncited are from 4–6 Aug and age out.

---

## WHAT MUST NOT BE REBUILT

`os_objective` · `org_agents.manager_key` · the review chain · `fn_agent_context` (extend only
through `fn_agent_context_capped`) · `kb_search` · `fn_scenario_run` · `fn_kpi_review` ·
`drawing_boq` — **and it is now graded, so a regression will show up in KPI 103** ·
`scripts/rehearsal/` · the workflow engine's two halves (`fn_workflow_step_sweep` executor-side and
`workflow_dispatch` employee-side).

---

## HOW TO WORK

Verify by execution in the same turn, on a non-zero effect, never on an HTTP 200. Aborted-transaction
probe for writes. Deploy to both Supabase projects. **Merge via PR, never straight to main** — I did
that twice last session and it was wrong. Never weaken a check; if a fix makes one harder because
the old pass was false, say so in the commit. Never state anything you have not measured.

**Save the Row #3 per-check verdict list every run.** Four are now committed
(`ROW3_VERDICTS_2026_08_11.txt`, `_LATE`, `_2026_08_12_MORNING`, `_AFTER_CLEANUP`, `_FINAL`) and the
diffs between them are the only reason last session could attribute every point of movement.

### THE QUESTION THAT FOUND FIVE DEFECTS IN ONE SESSION

**"Has this recovery path ever actually executed?"** Not "is it correct" — has it run. Five
instances in one night, all correct code, all unreachable:

```
195 workflow steps parked on an executor that could never pick them up
fn_ai_route's confidence arms — p_confidence cannot exist before the call
exec_review's 140s timeout — six officers in series need up to 290s
cos_execute's stale reclaim — `if (batch.length < MAX_TASKS)` with 340 assigned
fn_delete_proposer reopening decisions seconds after they were answered
```

The 25 existing watcher functions miss all of them because **nothing failed** — the runner ran,
succeeded, and did nothing. Do not add a 26th generic watcher. Measure the specific queue.

### TRAPS — the new ones are at the top

* **`next/font/google` fetches at BUILD time.** Now diagnosed, see §1. Not "mechanism unknown".
* **pg_net attributes the whole elapsed time to DNS on any timeout** — "DNS time: 140002 ms,
  handshake 0.000000 ms" is a timeout artefact, not a name-resolution problem.
* **`action_execution.finished_at - started_at`** is the invoker's dispatch-then-collect cycle
  (~420s for successes AND failures), not the function's runtime.
* **`agent_runs.agent` is a JOB name and one function may use two.** `cos_execute` writes its
  per-run row as `chief_of_staff`. I read "it has not run in 6 hours" off the wrong name.
* **`"fell back from"` is only logged when a fallback SUCCEEDS.** Zero of them does NOT mean the
  ladder never engaged. `ai_cost_log` now records `ALL MODELS FAILED after the full ladder: …`.
* **A function with no `fn_task_class` row is routed to `general_drafting`** — haiku, 900 tokens —
  and `min(caller, policy)` makes the caller's ladder irrelevant. That truncated 133 of
  `action_worker`'s 229 calls before anyone noticed.
* **`config.toml` is GENERATED.** Run `node scripts/gen_supabase_config.mjs`; it only picks up a
  function that is already deployed, so deploy → PATCH `verify_jwt` → regenerate.
* **`apply_sql.mjs --promote` cannot carry a REVOKE or any DML** — without `--ddl` only
  `pg_get_functiondef()` is promoted, so UPDATEs run on staging alone and a new SECURITY DEFINER
  reaches production granted to PUBLIC.
* **`qd_guard` refuses any SQL applied to staging that contains the production ref — even in a
  comment.** It is right; write `<production-ref>`.
* `pg_get_functiondef` emits no trailing semicolon. `jsonb_array_elements(x) c` names the FROM item
  — use `as t(c)`. `least(100.0, NULL)` = 100.0. BEFORE triggers fire in name order.
  `revoke … from anon` is a no-op under PUBLIC; revoke from PUBLIC. PostgREST runs as
  `authenticator` with `statement_timeout=8s`. Reading a table in the statement that refreshes it
  returns the pre-update snapshot. A PARTIAL scorer run is not a score — look for `N/152`.
  `LIMIT` on an aggregate query limits the aggregated row, not the rows fed into `jsonb_agg`.

---

## END-OF-SESSION SWEEP, EVERY TIME

GitHub Actions (a zero-step job means quota, not code) · Vercel · both Supabase projects · Row #3 to
completion with the verdict list saved · pack scorecard on both (**the six zips are in
`~/Downloads` and extract cleanly to 596 files — there is no excuse to skip it**) ·
`fn_os_portals_gates()` on both · `project_parity.mjs` → BOTH PROJECTS IN SYNC ·
`sql_files_match_live.test.mjs` → drift 0 · and `select count(*) from cron.job j where j.active and
not exists (select 1 from cron_registry r where r.jobname=j.jobname)` → 0, because a new cron job
without a registry row silently re-breaks `s38`.

---

## STATE AS OF 2026-08-12 ~08:40 UTC — do not re-derive

```
main                  20 PRs merged last session (#220–#237) · production READY on quotesdone.com
Row #3                126/152 · verdict list byte-identical across the last two runs
gates                 23/23 BOTH · parity BOTH PROJECTS IN SYNC · scripts/sql drift 0
                      198 edge fns · 420 tables · 866 functions · 156 triggers
                      0 tables without RLS · 56 anon-executable SECURITY DEFINER (baseline)
advisors              0 ERROR security, 0 ERROR performance
workflow_run          131 done · 107 running · 13 failed      (was 5 · 195 · 7)
workflow steps        48 delivered by a named employee · 107 ready · 0 stuck
actor vocabulary      1 of 66 catalogue names unresolvable ("domain specialist"), was 33
company_goals         63 · 29 measurable (was 24) · 0 silent
employee_kpi          122 · 108 measurable (was 104) · 0 silent · KPI 103 = 100.00 vs target 95
employee_kpi_history  2 measured days · 94 employees with a trend · the Row #3 check is MET
org_tasks             340 assigned · 47 in_progress (draining, reclaim now reachable) · 22 need me
agent_actions         39 pending · 8 delete proposals, all 8 decided
ai_cost_log           confidence live and DISCRIMINATING: 0.35 / 0.40 / 0.45 / 0.55
                      fn_ai_confidence_prior armed; intel_director {n:6, prior:0.45, spread:0.0801}
                      ai_trainer refused by the variance guard (constant 1.0)
pack scorecard        INGESTED 100% · IN USE 37/37 · RETRIEVABLE 52.3% (was 46.6%)
demand side           customers 0 · inquiries 0 · quotes 0 · transactions 0 — UNCHANGED
```

New last session: `workflow_dispatch` and `boq_fixture_check` (edge, both on cron) ·
`fn_workflow_actor_resolve` · `fn_workflow_step_claim` · `fn_workflow_step_release` ·
`fn_workflow_run_follow_task` (+trigger) · `fn_workflow_actor_coverage` · `fn_ai_confidence_prior` ·
`fn_boq_fixture_score` · tables `boq_fixture`, `boq_fixture_run` · columns
`company_goals.no_measure_reason`, `employee_kpi.no_measure_reason`. Every new SECURITY DEFINER
revoked from PUBLIC, every new cron job in `cron_registry`.

Do not stop and do not check in. Take the next item. Keep going until I say stop. If you hit a hard
limit that makes further work unreliable, hand over honestly and name exactly what is unfinished —
a truthful hand-over is worth more to me than a green tick.
