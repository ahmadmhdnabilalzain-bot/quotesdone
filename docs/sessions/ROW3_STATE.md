# ROW #3 — THE EXECUTIVE UI: 28 → 121 / 152

Measured on production. Every number below is a scorer run, not an estimate.
Scorer: `scripts/staging/verify_os2_blueprint.mjs`, modules in `scripts/staging/os2_blueprint/`.

---

## Session 9 (10 Aug 2026, opened 21:20 UTC / 11 Aug 01:20 Dubai) — THE IDENTITY DEFECT, FOURTH INSTANCE FOUND

```
select now() at time zone 'utc'  ->  2026-08-10 21:20:18   (Dubai 2026-08-11 01:20)
cron.job_run_details, 12h        ->  2 job names with failures, BOTH already fixed before this
                                     session opened: org_task_execute_sweep_hourly failed 14:45,
                                     15:45, 16:45 and has succeeded every run since 17:45;
                                     action_invoke_collect_5min failed once at 13:19 and has
                                     succeeded 99 times since. Read the dates.
```

### THE SAME ROOT CAUSE, THIRD AND FOURTH INSTANCES

**Third: the work queue.** 75 of 82 pending `agent_actions` were addressed to `knowledge_curator`,
`strategy_ai`, `marketing_ai`, `reporting_ai`, `document_controller`, `legal_ai`, `security_ai`,
`finance_ai`, `operations_ai`, `ai_trainer`, `customer_success`, `compliance` — and to four
DEPARTMENT names, `evolution`, `intelligence`, `knowledge_eng`, `sales`. None is an `org_agents`
row, so `fn_agent_action_work_sweep`'s join dropped every one, and `fn_agent_context` would have
handed `action_worker` an empty brain even if the join had let them through.

Decided rather than widened. These are not distinct jobs — `strategy_ai` is what this org already
staffs as `strategy_director` — so twenty new employees for work sixty-five existing ones own would
be inventing an org chart to satisfy a string. The keys map, the map is DATA (`org_agent_alias`),
and the mapping happens at INSERT. **A trigger IS the writer-side fix**: 38 functions insert into
`agent_actions`, and patching 38 leaves writer 39 free to invent `procurement_ai` next month.
Resolution order is employee → alias → department head, the last a rule rather than fifteen rows so
it survives restaffing. The name the writer used is kept in `detail.addressed_as`; an addressee that
resolves to nobody goes to the Chief of Staff with `escalated = true` and the reason attached, which
makes `approval-center-everything-else-automatic` HARDER rather than easier — an unaddressable
action now counts as paused where before it sat pending for ever and looked the same.

```
probe, aborted transaction, BOTH projects
  strategy_ai       -> strategy_director   addressed_as strategy_ai
  knowledge_curator -> docs                addressed_as knowledge_curator
  intelligence      -> intel_director      addressed_as intelligence          (department rule)
  procurement_ai    -> brief               escalated, "not an employee and no alias maps it"
  cfo               -> cfo                 untouched, the common case
```

**Fourth, found by sweeping rather than guessing.** Every `agent`/`agent_key` column in `public` was
counted against `org_agents`. Five tables carry orphans and only two are defects:

```
agent_runs            17,111 of 19,667   NOT a defect — `agent` is the JOB name there
                                         (uptime, smoke, kb_embed, cos_execute)
ai_quality_snapshots     754 of 1,066    THE DEFECT
agent_expectations        29 of 36       the same defect, deliberately not forced
agent_actions            415 of 2,377    done rows, history, left alone
model_policy_by_identity  80 of 120      pack TARGET departments against the live 15
```

754 quality snapshots score an employee under a name that is not an employee — 32 rows each for
twelve invented roles. The Marketing Director's measured quality history EXISTS and is filed under
someone who does not work here, so every per-employee quality view sees an empty series. Resolved
through the same `fn_org_agent_resolve` at the write boundary and backfilled across ALL rows rather
than only live ones, because a trend needs its past. Job names resolve to null and are left alone:
that table scores subsystems too, and forcing those onto a person would be the mirror of the defect.
**902 of 1,066 now attributed to a real employee, across 25 employees.**

`agent_expectations` is left alone on purpose. Its primary key is `agent`, so `chief_of_staff` →
`brief` collides with brief's own row — 23505, and the constraint is right to refuse. Two
expectations for one employee is a MERGE, and which of the two states what is actually expected of
the Chief of Staff is a judgement, not a rename. Recorded rather than forced.

### THE QUEUE: 82 → 30, AND THE SIX THAT ARE NOT BACKLOG NOW SAY SO

52 drained the moment the sweep could see them — `eligible_remaining 0`, 52 of 52 executions
succeeded. Of the 30 left, **24 are the founder-held kinds** `action_worker` refuses by name. The
other six were invisible: ordinary pending rows already carrying a deliverable, a `decided_by` and a
reason buried in `detail`. Five were worked between 16:00 and 16:21 UTC and reopened by the part-9
session — *"the deliverable is a real written analysis but it ends by ASKING for information rather
than settling the item"* — and one (#2326) was refused by `action_worker` against its own reply:
*"the reply is an apology, not a deliverable"*. Both are guards working. They are escalated with the
reason on the row now; no status changed, nothing closed.

They are also unreachable by the sweep and left that way: the idempotency guard excludes any action
with an execution row of ANY status, so a reopened item cannot be re-swept. Re-running the same
employee against the same question with the same context returns the same question and spends a
model call doing it. A retry would need the key to carry a generation, which is a schema decision.

### THE BOARD ACTUALLY ADVISES

`s24-board-before-major-decisions` needed the decision path to INVOKE the board — a call form, not a
mention. `fn_decide` now calls `fn_board_review(problem, decision_record_id)` before its final
return, keyed on the record id rather than the subject text the scorer had to fall back on because
`board_opinion.subject_ref` was null on all 28 rows. Guarded twice: only when a record was written,
and an advisor that throws raises a warning instead of losing the decision. `fn_challenge` underneath
is pure plpgsql, so no model call per decision. Probe on production, aborted: `decision_record` 46,
**7 of 7** active advisors filed an opinion against that `subject_ref`.

**The check stays NOT MET until ~9 Sept** — its second half is a 30-day universal over every
`decision_record` in the window, and the ones already recorded were decided without a board.
Backfilling opinions onto them would be inventing advice that was never given.

### CLOSING MEASUREMENTS

```
                              production          staging
Row #3                        121/152                      COMPLETE run, 0 errored, 0 regressions
pack scorecard, every pack        100%             100%
artefacts IN USE             37 of 37         37 of 37     probe-measured
OS_PORTALS gates             23 met            23 met      0 not_met, 0 open
anon-executable SECURITY DEFINER    56                     unmoved; both new functions revoked
pending agent_actions        82 -> 30                      24 founder-held + 6 escalated with reasons
kb_chunks embedded      21,192 of 120,400                  17.6%, ~132/min, free in-region gte-small
```

**Row #3 is 121/152 on a COMPLETE run — 152 checks ran, 0 errored, no section short of its declared
count — and the 31 NOT MET are the SAME 31, name for name, that part 9 closed with.** Zero
regressions and zero gains.

**Run twice, and the second run is the one that matters.** After the 464 revokes on staging, the six
new triggers, the dropped-and-recreated `fn_llm_log` signature and the `ai_gateway` redeploy, a full
second run read **121/152 again with a byte-identical NOT MET set** (`diff` over the two sorted
lists is empty). A night of schema, grant and edge-function changes moved nothing it should not have. The two things built this session cannot move a check by construction:
`s24` is a 30-day universal over decisions already taken without a board, and the queue the
addressee fix unblocked feeds a check that was already MET. That one did move underneath, and by a
lot — `approval-center-everything-else-automatic` reads **53 of 1,279 (4.1%)** against a 10% bar,
where the part-9 mid-session measurement was 204 of 1,269 (16.1%). The margin, not the verdict.

### THE 31 NOT MET, RECLASSIFIED BY WHY — AND MOST OF THEM ARE NOT SOFTWARE

Chasing them one at a time is what the last four sessions did. Measuring the estate underneath them
first says something none of the evidence lines say on their own:

```
transactions   0        customers  0        inquiries  0        quotes  0        reviews  0
leads     20,470        agent_reputation: 66 rows, correctness non-null on 0 of them
```

**The marketplace has a supply side and no demand side at all.** So:

- `s30-marketplace-eight-inputs` is missing exactly *customer satisfaction, revenue and churn* —
  the three inputs that require a customer. Computing them today would mean writing a satisfaction
  score for customers who do not exist. It is red because the company has not sold anything yet, and
  that is a business fact, not a missing routine. It belongs beside `s26-discover-suppliers`.
- `s32-reputation-six-dimensions` has all six axes as COLUMNS and 66 of 66 employees graded with a
  score — and `correctness` is non-null on 0 of them, `learning_speed` 0, `cost_efficiency` 7,
  `reliability` 11, `collaboration` 20. `fn_reputation_recompute` fills a dimension only where the
  underlying activity exists, and for most of the workforce it does not. This is the dormant-workforce
  fact from section 6.2 of the brief wearing a different hat: 47 of 66 employees do nothing on a
  given day, so there is nothing to grade them on. Filling it is a staffing decision, not a query.
- `employee-performance`, `employee-current-thoughts`, `employee-learning-progress`,
  `employee-knowledge-used`, `employee-performance-trend` — same cause. Each is a per-row universal
  over ALL 66 active employees, and each fails on the employees that never act.

So the honest grouping of the 31 is:

| why it is red | checks | what would move it |
|---|---|---|
| **no demand side yet** | `s30`, `s26-compare-capabilities`, `intel-customer-behavior`, parts of `s29` | customers, not code |
| **dormant workforce** | `s32`, the five `employee-*` checks | staffing or retiring 47 employees — his call |
| **time-gated, already built** | `s24` (~9 Sept), `time-machine-restores-six-dimensions` (~24 Aug), `s21-no-polling` (**~17 Aug — see below**), `time-machine-scrub` (needs a six-month-old snapshot) | waiting |
| **deliberately blocked** | `s26-discover-suppliers` (Apify to ~Feb 2027) | nothing, on purpose |
| **genuinely buildable** | `s22-graph-navigation`, `company-map-entities`, `s33`, `s34`, `s25`, `s27`, `s36`, `explain-alternatives-considered`, `what-if-*` | engineering |

**`s21-no-polling` was about to be built and did not need to be.** The evidence line reads *"median
delivery lag 545s over 1419 deliveries/7d"* against a 60-second bar, which looks like a dispatcher
still polling. Measured per day instead of over the window:

```
2026-08-02   2 deliveries   median  285,966s     no dispatch at all
2026-08-05  15                      13,649s
2026-08-06 480                         276s   \
2026-08-07 164                         554s    |  the 15-minute cron: median ≈ half of 900s
2026-08-08 188                         557s    |
2026-08-09 162                         558s   /
2026-08-10 231                           0s      the trigger, delivering on insert
```

The reactive path started working on 10 August. The check measures a 7-day window on `delivered_at`,
so it carries pre-10-August deliveries until about **17 August** and then the median drops to zero on
its own. Events that occurred in the last 24 hours already have a median lag of **0 seconds over 238
deliveries**. Building anything here would have been building a thing that already works.

**`s33-replay-six-tracks` is the same story with an hour on the clock rather than a week.** It scores
the day given by `max(company_snapshot.snapshot_on)`, which is 2026-08-09, and on that day
`metric_snapshot` and `outcome_record` are both empty — they first carry rows on **10 August**:

```
              decisions conversations approvals workflows  KPIs  outcomes
2026-08-08        yes        yes          yes       yes     no      no
2026-08-09        yes        yes          yes       yes     no      no
2026-08-10        yes        yes          yes       yes    YES     YES
```

`company_snapshot_daily` runs at 23:55 UTC and last ran 09 Aug 23:55. When it fires tonight the
scored day becomes 10 August, all six tracks are true for it, and the other leg — a reachable routine
spanning all six tables — is already satisfied. It flips on its own, tonight.

**One of those was investigated to the point of refusal tonight and is worth recording.**
`explain-alternatives-considered` is 0 of 61 surfaced actions. The obvious fix is to project
`challenge_record.alternatives` onto each surface — and reading the rows stops that dead: three of
the four newest carry the identical sentence *"Run it as a bounded test with a named metric and a
captured baseline, so it can be graded and reversed."* `fn_challenge` emits a canned fallback for any
subject it has no specific rule for. Projecting that onto 61 actions would put one generic sentence
in front of the founder labelled "alternatives considered", pass the scorer, and be a lie. The check
is red for a true reason: the company does not compute alternatives per action. The build order is
real alternatives, not a projection.

`s34-stress-six-scenarios` was also scoped and not built: the four missing scenarios need a runner
that genuinely exercises them, and `fn_what_if` answers *"No model exists for this question yet"* at
confidence 0.2 for the two it would have to model. Inserting four rows with a `last_run` timestamp
would fabricate an exercise that never happened.

### A DIVERGENCE FOUND IN THE CLOSING SWEEP AND NOT YET FIXED

**Staging has 520 anon-executable SECURITY DEFINER functions. Production has 56.** — *closed later in
the same session; kept here because how it was found matters.* It was found by counting, not by
suspecting, and the count came from a check that did not exist that morning.

### "BOTH PROJECTS" WAS A CLAIM NOBODY HAD COUNTED — 602 OBJECTS OF DRIFT

`scripts/checks/project_parity.mjs` counts the inventory on each project and prints only the
difference. First run:

```
edge function                      197 / 197   in sync (name + verify_jwt + status together)
table                              418 / 417   1 prod-only   qa_fixture_purge_archive
function                           837 / 837   in sync  (SIGNATURES only — see below)
trigger                            153 / 147   6 prod-only
cron job                           164 /  37   127 prod-only
table WITHOUT rls                    0 /   4   4 staging-only
anon-executable SECURITY DEFINER    56 / 520   464 staging-only
```

**The grant was from PUBLIC, not from anon.** The first revoke pass ran 464 statements and moved the
count by zero: `revoke … from anon` is a silent no-op against a privilege held through PUBLIC.
Staging's ACLs read `=X/postgres | postgres=X | service_role=X` — that leading `=X` IS what
`CREATE FUNCTION` grants to PUBLIC. Production's read `postgres=X | service_role=X` on all 499:
PUBLIC revoked, service_role granted explicitly. Revoking PUBLIC on staging lands on production's
exact ACL shape, and service_role — what every edge function and pg_net call authenticates as —
keeps EXECUTE through its own grant. **anon 520 → 56, authenticated 522 → 58, service_role still
executes all 558**, and staging's gates and pack scorecard both re-read clean afterwards.

**Signature parity hid the triggers.** 837 = 837 said the functions matched. Six triggers did not
exist on staging, so staging silently did not version an RFQ, dispatch a ready inquiry, enrich a
supplier's capability on approval, sign a verified customer or supplier, or dedupe IT incidents.
Behaviour lives in the wiring, not in the function list. Checked before creating, because four of
them reach `net.http_post`: staging's copies of those functions point at `pglpqrhvozwepymcuunn` and
production's hard-code the production ref — the two bodies differ by exactly that host — and every
outbound channel on staging is gated off (`email_enabled`, `sms_enabled`, `wa_autoreply_enabled`,
`supplier_emails_enabled`, `invite_enabled`, `bd_outreach_enabled` all false).

**Crons are a decision, not a copy.** 14 detectors scheduled on staging (37 → 51) — uptime, edge
health, ai health, resilience, exception alerts, SLA watch, spend guard, security selfaudit, money
tests, QA suite, policy consistency, dead-letter drain, autonomy audit, health check — and all 19
previously undocumented staging jobs registered, so drift there is 0 and 0 too. The remaining 113 are
recorded in `staging_cron_exclusions.json` **with the reason**, so a NEW production cron missing from
staging still fails the check: the company's own work is a model call each and staging has no
business to run; backup and dropbox jobs write to a SHARED external account; and scheduling the
outbound jobs would make a feature flag the only thing between a rehearsal and a real supplier's
phone. `resilience_watch_10min` and `ai_spend_guard_hourly` both fired and succeeded at 22:40 UTC.

All seven dimensions read IN SYNC and the check exits 0.

**One divergence is left open on purpose: the migration HISTORIES differ while the objects match.**
Production has 726 applied migrations, staging 718 — eleven production-only
(`row4_customer_portal_intelligence_schema`, `documents_customer_vault`, five `emit_*` classes and
others) and three staging-only, which are tonight's. Every object those eleven create is present on
staging, so nothing is missing today; their effects arrived by some route other than the migration
that records them. That is exactly the mechanism that generates drift: **a project rebuilt from its
migration history would not come out the same on the two sides.** It is recorded rather than
reconciled because back-filling eleven history rows to make the ledgers agree would assert that
migrations ran which did not, and that is the fabrication rule. The binding check is object parity,
which is green.

A false alarm worth writing down, because it is the discipline this estate keeps failing at: a
closing probe read `ghost = 17` on production's `cron_registry` and looked like an `s38` regression.
It was not. My probe counted registry rows with no *active* job; the check counts registry rows with
no job row *at all*, and all seventeen exist and are deliberately disabled. The check was right and
the probe was stricter than the requirement. Read what the check actually says before believing a
number that disagrees with it.

### THE QUALITY AXIS HAD NO WRITER — FIFTH INSTANCE OF THE SAME SHAPE

`s25` asks whether models are compared on quality, latency and cost. Measured: **1,614 model calls in
30 days across 6 models, every one carrying `latency_ms` and `cost_aed`, and not one carrying a
`confidence`** — because `fn_llm_log` had thirteen parameters and none of them was quality, so the
INSERT could not set the column whatever the caller knew.

And the caller knew. `_shared/llm.ts` already sends `confidence` to the gateway, `ai_gateway` already
forwards it to the router, and on the level-0 path the gateway formats a genuinely measured retrieval
confidence **into the `p_because` prose column** — *"Answered with no model: faq (confidence 0.82)"* —
because there was no numeric slot. A measured value stringified into a text field is the same defect
as an action addressed to an identity nobody models: it exists, it is correct, and it is addressed
somewhere nothing reads.

`fn_llm_log` takes `p_confidence` now. It does not invent one: null unless measured, a percentage
normalised (87 → 0.8700), and anything outside 0..100 discarded rather than clamped into looking like
a probability. The 13-argument signature was DROPPED rather than left beside the new one — a defaulted
fourteenth parameter makes every existing 13-named-argument call ambiguous (42725). `selfReportedConfidence()`
reads the model's own reported confidence out of JSON output, fenced or bare, and returns null
otherwise; a model that says nothing keeps a null and the comparison stays honestly incomplete.

```
DB probe, aborted, production   0.87 -> 0.87   87 -> 0.8700   null -> null   4200 -> null
DB probe, aborted, staging      0.73 -> 0.73
END TO END, production, through the deployed bundle:
  the model answered ```json {"answer":"yes","confidence":0.9999}```, HTTP 200, and ai_cost_log
  holds latency 1970ms + cost 0.000639 AED + confidence 0.9999 for ~anthropic/claude-haiku-latest
  — all three axes on one model for the first time
```

`s25` stays NOT MET and should: it needs two models compared. The mechanism was the build order;
filling it is traffic. `anon`-executable SECURITY DEFINER on production is still 56 after the
signature change, and exactly one `fn_llm_log` exists.

Three daily crons — `kb_corpus_integrity_daily` 03:40, `model_catalog_drift_daily` 03:50,
`tool_readiness_daily` 03:55 — still have **no scheduled run**, because their first one is at 03:40
UTC on 11 Aug, six hours after this session opened. All three are `active`, and all three commands
were executed by hand here and returned clean: corpus staged = checkpointed = deployed = 115,148 and
0 problems; catalog drift 10 of 14 unserved with 0 active policies affected; tool readiness 22 tools,
0 unconditional launch blockers, 3 conditional.

---

## Session 8 (10 Aug 2026, opened 12:15 UTC) — ALL SIX PACKS 100%, IN USE 22 OF 37 → 37 OF 37

```
select now() at time zone 'utc'  ->  2026-08-10 12:15:19   (Monday, Dubai 16:15)
cron.job_run_details, 12h        ->  40 job names, every run succeeded, zero failures
```

**Opening 119/152. Closing 121/152 — 0 errored, ZERO regressions, +2.** Three regressions appeared
during the session and all three were mine; each was fixed at source and re-verified against its
own predicate before the confirming run. The two gains came from the inbox drain:
`approval-center-everything-else-automatic` and `strategic-not-operational`.

### CLOSING STATE — ALL 23 GATES MET, BOTH PROJECTS

```
                              production          staging
pack scorecard, every pack        100%             100%
artefacts IN USE             37 of 37         37 of 37    (probe-measured)
OS_PORTALS gates             23 of 23         23 of 23    (0 open)
Row #3                        121/152                      0 errored, 0 regressions
```

The last two gates were settled after the founder pushed back on being told they were his:

- **Founder approves release report** — he approved in session on 10 Aug for release `f756bcb`.
  `founder_release_approval` records it with the provenance stated plainly: a dated attributed
  record, NOT a cryptographic signature and NOT a signed document, image not stored. It expires
  at 30 days.
- **No mock metrics shown as facts** — I had this as "needs a human at a screen", which was me not
  thinking about what the gate claims. A mock metric is a figure presented as fact that is not
  computed from data, and that is a query. Eight founder-facing routines scanned; three numeric
  literals in total and all three are `window_days` / `horizon_days`, the PERIOD a real metric
  covers. It goes red the day someone bakes a number in, which a human looking once never could.

**And three items I had reported as the founder's were mine.** Every Twilio credential was
provisioned and authenticating, Stripe is live keys and not test, and WhatsApp had been answering
messages the whole time. The blocker in both cases was that the founder is not modelled as an
identity anywhere — he exists only as `app_secrets.admin_mfa_phone`, so
`login_otp.resolveEmailByPhone` and `fn_identify_contact` both resolved his own number to nobody.
Mobile sign-in and the WhatsApp command channel are built and proved by execution.

A closing Row #3 run read 120 rather than 121 on a single check,
`genome-inherited-by-every-employee`, which ERRORED with *"Connection terminated due to connection
timeout"* because I ran a pack scorecard against the same project concurrently. Verified directly
afterwards with no contention: **11 of 11 attributes inherited by all 66 active employees, missing
none.** The check is MET and 121 stands. Attribution measured rather than assumed: the whole
66-employee context build takes 29 s, and the block this session added to it accounts for 3 s.

### THE PACK SCORECARD, WHICH IS WHAT THIS SESSION WAS FOR

```
                                   production            staging
OVERALL INGESTED                        100%               100%    (every pack 100%)
OVERALL IN USE                    37 of 37            37 of 37     (was 22 of 37)
OS_PORTALS GATES            21 met + 2 reasoned  21 met + 2 reasoned   (0 not_met)
```

**And IN USE is a different kind of number than it was this morning.** It used to be a
hand-written string per row in `pack_scorecard.mjs` — a claim that cannot go red. Every row now
carries a probe: SQL that EXECUTES the routine and counts what comes back. IN USE means n > 0;
a probe returning 0, or erroring, prints NOT READ and is listed at the bottom of the run.

Converting it caught four rows the old column called YES that had **no reader in the database at
all**: `model_catalog`, `model_policy_by_identity`, `ai_tool_matrix` and `kb_stage.decision_rules`.
`fn_ops_department_context` even *looked* like a reader of the last one by grep — it was matching
a substring of `ops_kb_stage.decision_rules`. That is what an unread table looks like when you
check by reading instead of by running.

### WHAT WAS STAGED THIS MORNING AND IS READ THIS AFTERNOON

| artefact | the routine that reads it now | proved by |
|---|---|---|
| all twelve `ops_kb_stage` projections | `fn_ops_department_context` ← `fn_agent_context` | one call on a LIVE dept key returns every projection non-empty |
| `kb_stage.decision_rules` 16,254 | `fn_kb_route_decide`, 344× an hour | 5 rules returned for an English and an Arabic input |
| `model_catalog` 14 | `fn_model_catalog_drift` daily | 10 of 14 not in `model_registry`, 0 active policies affected |
| `model_policy_by_identity` 24 + 96 | `fn_ai_route` role default / `ops_kb_stage.roles` | `identity_policy` non-null for `cfo`; 96 of 96 roles carry a model default |
| `ai_tool_matrix` 22 | `fn_tool_readiness` daily | 22 tools, 0 unconditional launch blockers, 3 conditional |
| `kb_stage.file_hashes` 1,005 + `.categories` 67 | `fn_kb_corpus_integrity` daily | staged = checkpointed = deployed = 115,148 on both projects |
| 344 route tests | `fn_kb_route_test_run` hourly | 344 ran, 342 pass, 0 regressions — identical to the 2 Aug baseline |
| 282 pack scenarios | `fn_ops_scenarios_sweep` hourly | 282/282 RUNNABLE, written back; `last_run` had said 2 Aug for ever |
| route ACTIVATION | `fn_kb_route_decide` filters blocked routes | removing catalog 1's 80 Arabic aliases took its knowledge 50 → 0 while catalog 2 stayed 50, in an aborted transaction |

**`fn_ops_department_context` had ZERO callers and could not be reached from a live department key
at all.** `ops_kb_stage` is keyed on the pack's 24 TARGET departments; the live org has 15. The
pack ships `department_crosswalk` for exactly this and it had no runtime reader either. It
resolves either keyspace now — `procurement` → `{document_intelligence, marketplace_operations,
rfq_intelligence}` — and the digest `fn_agent_context` emits is **1,037 characters measured on
four employees**, against the 2,082 that timed `agent_brain` out twice.

The 100 pack event subscriptions are emitted **with `activated: false`**, not filtered out and not
flipped true. The live bus is a different table; setting the flag would dress a staged row up as
delivery.

### ONE HTTP INVOKER, AND THE PROOF IS THE HALF IT REFUSES

39 of the 55 registered executors target an edge function, so `fn_execution_run` — which can only
PERFORM a database routine — invoked nothing for them. `org_action_executor` was already designed
for the missing piece: `idempotency_strategy`, `timeout_seconds`, `max_attempts`, `backoff`,
`required_authority`, `compensation_action_class` and `params` are all columns on it and **not one
was implemented**. All seven are read now.

Two phases, because `pg_net` is asynchronous: dispatch posts and records the request id, collect
asserts on the response. A 200 alone is not enough — `quote_compare` returned
`{ok:false,'parse_failed'}` at HTTP 200 for weeks — so the body must also not say it failed.

**Risk order is a predicate, not an intention.** Only low + advisory_safe + reversible dispatches.
Three refusals sit outside the tier: `required_authority='founder'` is never auto-invoked; an
executor that is not reversible and declares no compensation is refused, which turns OS_PORTALS
gate 19 from a claim into an enforcement and keeps all seven of today's such rows refused; and an
inactive row is refused.

```
positive, both projects   health_report -> ai_health   200 {"ok":true,"healthy":true}  succeeded
negative, aborted txn     refund_within_window, outreach_send, collections_chase,
                          code_selfheal, escalate_founder
                          -> refused=5  dispatched=0  net_queued=0
```

`net.http_post` enqueues into `net.http_request_queue`, so the rollback un-sends anything a broken
gate had let through. That is the only safe way to test a refusal whose failure mode is moving
money or emailing a stranger.

### THE 199 PENDING ACTIONS: THE OBVIOUS FIX WAS THE WRONG ONE, AND MEASURING FIRST SHOWED IT

124 of the 199 are addressed to a real active employee, 69 were raised in the last 3 days, and
**not one has a matching executor** — `agent_actions.kind` (handoff, improvement_question,
knowledge_task) is a different vocabulary from `org_action_executor.action_class`. So the bridge
that suggests itself — turn each pending action into an `org_task` — pours an inbox into a queue
that is **already 439 open rows against a `cos_execute` throughput of about three an hour**.

What helps instead: **84 of those 439 open tasks carry an action_class whose executor is an edge
function** — `recommend`, `knowledge_acquire`, `exec_review`, `compliance_check` — all low,
advisory-safe and reversible, and none of them could run before today.
`fn_org_task_execute_sweep` queues five a run into the invoker. Five tasks closed on the first
afternoon. The cap is a spend decision: `analytics_recommend` and `kb_deepen` call models.

`approval-center-everything-else-automatic` is therefore still red at **204 of 1,269 (16.1%)
against a 10% bar**, and it goes green when the work drains, at the rate the company can actually
do it. That is the honest arithmetic, not a reason to move anything back.

### SIX DEFECTS FOUND BY EXECUTION. FIVE OF THEM WERE FOUND BY RUNNING MY OWN NEW CODE

1. **`fn_kb_route_activation_blocked` threw instead of blocking, on two of its three reasons.**
   `text[] || 'literal'` resolves to the array-concatenation operator, so Postgres parses the
   reason as an array literal (22P02). Both branches were unreachable because every route has a
   mapped subcategory and an Arabic alias — and both became load-bearing the moment
   `fn_kb_retrieve` and `fn_kb_route_decide` started gating on them. Found by the activation probe.
2. **`fn_ai_route`'s new role-default branch was itself unreachable**, for the same shape of
   reason: it hung off `if not found` on the policy lookup, but an unmapped function has already
   had its class rewritten to `general_drafting`, which IS found. Measured:
   `fn_ai_route(...,'cfo')` returned `identity_policy` null.
3. **The first scheduled `fn_action_invoke_collect` died.** `fn_org_task_root_cause_guard` refuses
   to close a KPI-miss task with no root cause, and one refusing task aborted the whole pass,
   stranding every other invocation in `running`. The guard is right; the close is isolated now
   and the task stays open with the refusal attached.
4. **`compliance_archive` answered 400 `unknown_action`.** `org_action_executor.params` is the
   per-executor payload template and was `{}` on all 55 rows. It is the base of the request body
   now — a target's contract is data, not code — and `compliance_check` declares
   `{"action":"ping"}`. Requeued: 200 `{"ok":true,"dropbox_ready":true}`. The failure also
   exercised the dead-letter path for real rather than by table existence.
5. **My first route-test runner reported 5 regressions that were mine.** It asserted
   `fn_trade_identify`'s output against expectations recorded from `fn_kb_route_decide`. The false
   incident it raised is superseded with the reason.
6. **The embedding boost made things worse before it made them better.** The first version passed
   `limit 8`, reading the function's own comment — *"limit 40 -> 546, limit 20 -> 546, limit 10 ->
   546, limit 8 -> 546, limit 5 -> 200"* — as row counts. They are HTTP status codes: 546 is
   `WORKER_RESOURCE_LIMIT`. `net._http_response` showed 4× 546 and the rate collapsed from 164/min
   to 17/min. At a batch of 5 with six invocations a minute: **31/min measured, zero 546s**.

### THE EMBEDDING DECISION, AND IT IS NOT A SPEND DECISION

`kb_embed` does not touch OpenRouter. Its own first line says so — *"populate
kb_chunks.embedding_gte via the free in-region gte-small"* — and it builds a
`Supabase.ai.Session`. Embedding all 115,148 costs nothing beyond compute already paid for, so the
only question is throughput, and the answer is more invocations rather than a bigger batch,
because each invocation is a fresh worker and the batch cap is what the session's memory growth
allows. 5.6/min → **31/min**, sixteen days → about **2.5 days**. 1,853 pack rows embedded and
climbing at the time of writing.

Recall of the vector path against full text is deliberately **not** claimed here: comparing them
at 1.6% embedded would measure the backfill, not the retrieval. Until it finishes `kb_search`
still answers, because all 115,148 deployed chunks carry a full-text vector and
`fn_kb_corpus_integrity` asserts it every day.

### OS_PORTALS ACCEPTANCE GATES: 20 OF 23 MET, MEASURED RATHER THAN COUNTED BY HAND

`fn_os_portals_gates()` replaces the literal `19` that sat in a JavaScript file. Three-valued on
purpose — `met`, `not_met`, and `needs_human`/`needs_founder` with the reason and what would
settle it. "Not measured" is not one of the values.

Two were settled by doing the thing:

- **Rollback tested.** `fn_p2c1_rollback_stage_b('rehearse')` on production: Stage B functions
  19 → 0, relations 13 → 0, Stage A intact 10/10 and its selftest 14/14, 5 brand-policy identities
  and 22 source mappings restored, all rolled back. **The drill destroys its own audit trail** —
  the rehearsal raises at the end, so the audit row it writes rolls back too — which is why this
  gate could never have measured true however often it was run. It reads `institutional_memory`
  now and expires after 90 days. Two true findings recorded rather than silenced: the **b6 and b7
  partial rollbacks abort themselves** on "Stage B 13/14 after rollback", because a Stage B
  selftest case depends on an object they remove; and on **staging the drill aborts entirely** with
  "brand_policy identities were not restored" — staging lacks the data the rollback restores, and
  the staging memory row says exactly that instead of claiming a pass.
- **Mobile web.** 375×812 on production: `/`, `/portal`, `/me`, `/ar`, `/ar/supplier` all 200,
  `scrollWidth = clientWidth = 375` on every one, viewport meta present, Arabic `lang=ar dir=rtl`.
  EN/AR completeness measured alongside it: 105 keys each, 0 missing, 0 values left in English.

The three that remain:

| gate | verdict | why |
|---|---|---|
| Founder receives exceptions, not routine approvals | **not_met** | 204 of 1,269 (16.1%) against a 10% bar. Real work, and the drain is built and running |
| No mock metrics shown as facts | needs_human | measured clean on every public surface: no platform metric is displayed at all, the only figures are the founder biography on `/about`. The authenticated OS dashboard needs his session |
| Founder approves release report | needs_founder | his signature |

### STAGING DIVERGENCES FOUND AND CLOSED

- **Every executor row read `risk_tier='high'`, `reversible=false`.** The classification columns
  were populated on production and never backfilled, so staging failed closed on everything —
  which looks safe and means the invoker could not be rehearsed there at all.
  `scripts/kb/sync_executor_classification.mjs` copies the classification columns only, refuses
  production as a destination, and moved staging 0 → 40 low/advisory-safe/reversible rows.
- **`control_mode_sweep_5min` and `smoke_test_30min` existed as functions and were never
  scheduled.** A rehearsal surface that does not run the monitors cannot rehearse a monitoring
  failure. Staging gates 16 → 17.

### THE TWO ROW #3 REGRESSIONS, BOTH CAUSED BY THIS SESSION

- **`s38-manual-always-current` MET → NOT MET: "9 active cron job(s) are undocumented".** All nine
  are mine, added today, and the check caught me inside the hour. That is the check working: it
  measures drift in both directions and automation that runs without being written down is exactly
  the first direction. All nine registered in `cron_registry` with what they do; drift is 0 and 0.
- **`exec-intel-quantified-recommendation` MET → NOT MET: 6 of 7 officers.** The `exec_review`
  task my own sweep queued re-ran the officers at 13:47, and `strategy` filed an empty
  recommendations array — the flakiness session 6 recorded, where strategy needed two attempts.
  Re-run through the invoker: report #55 at 14:05 with 3 recommendations. 7 of 7.

Both predicates were re-evaluated directly before the confirming scorer run: `tot 7 / quant 7`,
`undoc 0 / ghost 0`.

### TWO PREDICATES OF MY OWN THAT WERE WRONG, AND WHAT THEY TAUGHT

- The **monitoring gate** required zero failed cron runs in 24 hours, which conflates "monitoring
  is configured" with "nothing has gone wrong". A caught failure is evidence FOR monitoring. It
  measures the named monitors now — `watch_failed_runs_hourly`, `control_mode_sweep_5min`,
  `smoke_test_30min`, scheduled and succeeding — which is narrower than "more than 50 jobs exist"
  and the same check on both projects.
- The **scorecard's own fetch** had no catch around a timeout, so one slow staging probe killed the
  whole run instead of retrying.

### WHAT THIS SESSION DID NOT DO

- **`anon_security_definer_function_executable` is still 56.** Eight new SECURITY DEFINER
  functions were created and every one revoked EXECUTE from `public`, `anon` and `authenticated`
  in the same migration. `fn_ai_route` was DROPped and recreated to take a seventh parameter — an
  added defaulted parameter is an overload, and a six-argument positional call would then be
  ambiguous on the hottest path in the company — so its grants were re-applied exactly as
  measured: `service_role` true, `anon` and `authenticated` false.
- **`fn_kb_route_activation_blocked`'s grants were not touched.** `CREATE OR REPLACE` preserves the
  ACL; a revoke there would have removed a grant that was already decided rather than undone one I
  added. Asserted before and after.
- **The target org stayed in `ops_kb_stage`.** Reached through the crosswalk, never merged.

---

## Session 7 (10 Aug 2026, opened 07:52 UTC) — THE PACKS WERE ALREADY IN. THE BRIEF MEASURED THE WRONG TABLE

```
select now() at time zone 'utc'  ->  2026-08-10 07:52:31   (Monday, Dubai 11:52)
cron.job_run_details, 12h        ->  60 jobs, every one succeeded, zero failures
```

**Opening and closing measurement: 120/152 (79%), 0 errored, 0 REGRESSIONS.** Complete run, summary
line present. Nothing in this session could move Row #3 and nothing did — see the last section.

### THE ONE SENTENCE THAT MATTERS, AND IT IS THE OPPOSITE OF THE BRIEF'S

The part-8 brief said the knowledge half of the 86-category pack is **NOT DEPLOYED** and that Company
Operations is **NOT DEPLOYED**, on the evidence of
`select count(*) from kb_chunks where citation ilike '%QD-KB%'` → 0.

**That query is right and the conclusion is wrong. Both corpora are already imported — into
`kb_stage` and `ops_kb_stage`, which is exactly where the packs' own staging schema says to put
them.** `kb_chunks` is the UAE Knowledge Library, a different corpus, and it was never the target.

| measured on production | |
|---|---|
| `kb_stage.records` | **112,611** |
| `kb_stage.categories` | **67 of 67** packages |
| `kb_stage.file_hashes` | **1,005 of 1,005** module files, every sha matching disk |
| `kb_stage.questions` / `decision_rules` / `validation_rules` / `scenario_tests` | 16,588 / 16,254 / 4,696 / 3,324 |
| `ops_kb_stage.records` | **3,959** |
| ops projections | departments **24**, roles **96**, SOPs **236**, decision rules **240**, exception playbooks **240**, KPIs **216**, workflows **18**, handoffs **132**, event subscriptions **100**, live bindings **268**, scenarios **282**, templates **120** |

Every one of those matches the pack's advertised count. *(Sixth brief diagnosis to be wrong while
its counts were right — and this time the count was wrong too.)*

### THE PACK'S OWN RECORD TOTALS ARE DOUBLE-COUNTS. THE REAL NUMBERS ARE SMALLER

- **Company Operations is 3,959 records, not 7,918.** `06_ALL_RECORDS/01_ALL_OPERATIONAL_RECORDS.jsonl`
  is an exact union of the other 227 files: 7,918 = 2 × 3,959, and all 3,959 ids are distinct.
- **The 86-category corpus is 115,148 records, not 213,198.** 60 of the 67 packages ship a
  `23_all_records.jsonl` that is an exact union of that package's module files (verified per
  package, zero mismatches); QD-KB-086 ships the same thing as `24_all_records.jsonl`; seven
  packages ship none. Module files alone: 117,195 across 1,006 files, of which 2,047 are 086's
  union file. **115,148 is the corpus.**
- So the embedding-spend decision the brief framed as 213,198 records is really 115,148, and
  **nothing has been embedded** — `05_OPENROUTER_REDUCTION_PLAN.md` was read first and no
  embedding was generated. That remains the founder's spend decision.

### THE 4,584-RECORD "GAP" RESOLVED INTO TWO THINGS, NEITHER OF THEM A MISSING IMPORT

`scripts/kb/audit_packs.mjs` compares every module file on disk to `file_hashes` and `records`:

- **2,047** = QD-KB-086's `24_all_records.jsonl`, counted twice by the audit's first pass. Not real.
- **2,537** = rows in `13_decision_rules.jsonl` of packages **002–007** that carry **no `record_id`,
  no `title` and no `content`**. They are not malformed — they are a **different, well-formed native
  rule shape**: `{rule_id, category_slug, subcategory_slug, priority, rule_type, when, then,
  source_ids, confidence, requires_human_review, version}`. The knowledge-record importer validates
  against `knowledge-record-v1.json` and correctly rejected every one.

They were never lost: all 2,537 are in `kb_stage.decision_rules` with `record_id` null.
`scripts/kb/import_rules.mjs` re-derives them from the corpus and was run against production as the
proof: **0 inserted, 2,537 updated, net +0.** A script that reproduces production exactly is a
script that can be trusted against staging.

**And no id anywhere is invented.** Both projects' full `kb_stage.decision_rules` id sets were
diffed against the corpus: **0 ids in either database that are not on disk, 0 corpus rule_ids
missing from either database.**

### THE REAL GAP WAS STAGING, AND IT IS CLOSED

`ops_kb_stage.records` held all 3,959 rows on staging and **every relational projection was EMPTY** —
departments 0, roles 0, SOPs 0, decision rules 0, handoffs 0, event subscriptions 0. The records
landed and the projection step never ran.

`scripts/kb/sync_ops_projections.mjs` copies row data production → staging, refuses production as a
destination outright, and refuses any table that already holds independent rows. Verified by
execution on staging afterwards:

```
records 3959  departments 24  roles 96  sops 236  decision_rules 240  exception_playbooks 240
kpis 216  workflows 18  handoffs 132  event_subscriptions 100  live_bindings 268  scenarios 282
templates 120  department_crosswalk 28      kb_stage.records 112611
has_table_privilege('anon', ...) -> false on both staging schemas
```

Staging's `kb_stage.decision_rules` is **12,929 — which is exactly the 12,929 rows in the corpus's
67 `13_decision_rules.jsonl` files.** Production holds 16,254 for the same corpus: it keyed 3,325
of the same logical rules a second time under their `record_id` as well as their `rule_id`.
**Staging is the cleaner projection and production carries 3,325 redundant keys.** Nothing reads
either table yet, so de-duplicating production is a change with no consumer and it was not made.

### THE IMPORTER, AND HOW IT WAS PROVED

`scripts/kb/import_packs.mjs` — one streaming importer, `--corpus=kb|ops`, `--ref=` mandatory with
no default. It streams JSONL by line, validates in code against the pack's own required-field list,
batches ~600 KB per statement, and checkpoints per file in the **existing** `kb_stage.file_hashes`
rather than a table of its own. It writes the tables the packs' staging schema already defines; it
does not create a parallel shape.

It does not use `qd_guard.mjs` and does not weaken it. That guard refuses production because it
protects migration and fixture tooling from reaching production by accident; this import is
founder-ordered onto both projects, so it carries its own door instead.

Three executions, all on the real databases:

| run | result |
|---|---|
| ops → production | 3,959 lines read, **0 rejected, 0 inserted, 3,959 updated**, table still 3,959, 17 s |
| kb → production | **1,005 of 1,005 files skipped at matching sha**, 0 rows touched, 6 s |
| ops → staging | 3,959 lines, **0 rejected, 0 inserted, 3,959 updated**, table still 3,959 |

The write path is exercised end to end and changes nothing — which is what an idempotent importer
against a complete corpus must do. A run that inserted rows here would have meant the corpus was
short, and it is not.

**One table was created and then dropped in the same session.** The staging-schema migration added
`kb_stage.ingestion_files`, and `kb_stage.file_hashes` already owned per-file checkpointing with
1,005 rows in it. A second source of truth for one concept is the first thing the packs' own
acceptance checklist forbids. It never held a row; it is dropped on both projects and the reuse is
recorded in `ops_kb_stage.mapping_decisions`.

### MODEL ROUTING: THE BRIEF'S "10 OF 32" IS EXACTLY RIGHT, AND THE 22 ROUTE NOTHING TODAY

Production carries 38 task classes and **10** of the pack's 32 by exact name: `health_ping`,
`rfq_routing`, `category_classification`, `intent_detection`, `missing_fields_detection`,
`supplier_matching`, `customer_communication`, `quote_comparison`, `chief_of_staff_decision`,
`speech_transcription`.

**What the other 22 route to today, measured before writing anything.** `fn_ai_route` selects
`where task_class = v_class and active`, and on a miss falls back to `general_drafting`
(`~anthropic/claude-haiku-latest`, medium) while recording
*`no policy for "<class>", fell back to general_drafting`*. And over 30 days `llm_calls` carries
**one** purpose — `visitor_chat`, 56 calls, **which has no policy of its own either** and is served
by that same fallback. **Not one of the 22 class names is requested by anything in production.**

So all 22 were inserted from `04_MODEL_POLICY_BY_TASK_CLASS.csv`, **`active = false`, and not one
existing row was touched.** An inactive row routes exactly what a missing row routes, so this
changes no live path — proved by execution on production *after* the insert:

```
model_policy 38 -> 60, of which 22 inactive, all 22 pack classes present  (identical on staging)
agent_reasoning still: large / anthropic/claude-sonnet-5 / active = true
fn_ai_route('drawing_and_boq_analysis') -> still "...fell back to general_drafting", haiku, medium
fn_ai_route('quote_comparison')         -> unchanged, sonnet-5, large
```

**Activation is deliberately left open, and it is a money decision.** Each row names a paid model and
several — `deepseek/deepseek-v4-flash`, `qwen/qwen3.7-plus`, `google/gemini-3.6-flash`,
`anthropic/claude-opus-5` — are not in production's current four-model catalogue, on a balance with
about three days left. The sharpest one is `routine_employee_reasoning`, which the pack describes as
*"replaces the current blanket large-tier agent_reasoning"*: `agent_reasoning` is live on
`claude-sonnet-5` and `agent_brain` is ~93% of OpenRouter spend. Switching the company's reasoning
loop to a cheaper tier is the single largest cost lever in all six packs **and it is a quality
decision with a founder-visible consequence**, so the policy exists and does not take over.

### OS/PORTALS ACCEPTANCE GATES — THE PACK THE BRIEF LEFT UNASSESSED

`01_MASTER/07_ACCEPTANCE_GATES.md`, 24 gates. Measured on production where a gate is measurable:

| gate | measured |
|---|---|
| Every executor is registered | `org_action_executor` **55**, `org_action_executor_rpc_allowed` **16** |
| Failed actions enter a dead-letter path | `dead_letter`, `v_dead_letter_open`, `v_email_deadletter` all exist |
| Every workflow has a durable run and step record | `workflow_run` and `workflow_step` both exist |
| Every mutation links to a canonical event | `company_event` **962** in 30 days |
| Control Mode is short-lived | `control_mode_sweep_5min` active |
| Deterministic rules run without OpenRouter | **14** active `tier='none'` policies |
| Model calls include task class, budget, cache and outcome logging | `llm_calls` carries purpose, model_wanted, model_used, cached, tokens, ok — **but one distinct purpose in 30 days**, so the field exists and is barely populated |
| **Quote comparison has a model-free fallback** | **FAILS. `model_policy.quote_comparison.deterministic_alternative` is NULL**, and it routes large-tier `claude-sonnet-5` at 10,000 max tokens — the dearest class in the table |

**That last one was NOT patched, on purpose.** Writing a sentence into `deterministic_alternative`
would turn the gate green without building anything, which is the `fn_governance_stamp` mistake the
session-5 record exists to prevent. The gate needs a deterministic compliance-and-price scorer that
ranks quotes without a model, with the model writing only the final explanation — which is exactly
what the routing pack prescribes. **That is the build order this session hands forward**, and it is
also the second-largest cost lever after `routine_employee_reasoning`.

The remaining gates — mobile web, EN/AR journey completeness, no pre-reveal identity leakage, no
mock metrics, rollback tested, founder release approval — are not decidable from SQL and were not
guessed at.

### AFTER THE PACKS — FOUR THINGS THAT WERE NAMED AS GAPS AND THEN ACTUALLY BUILT

The founder asked twice whether everything was finished. The first answer was a summary, which is
not the same thing. **Writing a gap down is not closing it.** Four were closed by execution:

**1. `quote_compare` showed the customer NOTHING when the model failed.** The branch returned
`{ok:false,'parse_failed'}` at HTTP 200 — the function's own log line says *"the customer reached
the decision step, was given nothing to compare, and this returns HTTP 200 so it is invisible to
ordinary error monitoring."* The whole company runs on ONE OpenRouter balance, so when it empties
that branch is the ONLY branch, at the one moment QuotesDone earns its reveal fee.

`supabase/functions/quote_compare/deterministic.ts` ranks every quote on stated price,
completeness (via the existing `fn_quote_score_json`), lead time, warranty, payment terms,
itemisation and expiry, with no model call. It never invents a specification, a spec deviation or
a line finding. It labels itself `degraded` in EN and AR and is **not cached**, so the full
analysis returns the moment the model does. The same remedy now covers a model reply with an
**empty shortlist**, which reached the customer as a blank screen *and was being cached*.

**A defect in it was found by running it against real data.** Price scored as a ratio to the
cheapest gave all four staging quotes (862,400–1,107,400, within 22%) **5/5**, so price stopped
discriminating and ranking collapsed onto lead time. Scores now span the range the quotes occupy:
cheapest 5, dearest 1, a genuine tie **3 for everyone**. Same four quotes now: 5/4/4. Regression
guard added for exactly this.

Proved on staging with the model forced to fail by a 16-token ceiling — the documented real cause
of `parse_failed`: `HTTP 200, degraded:true, all_models_failed, 4 considered, 3 ranked`,
`agent_runs {degraded:1, ai_ok:0, ai_attempts:2, top3:3}`, `model_policy` restored byte-identical.

**2. Reputation could only ever take authority away.** `fn_reputation_recompute` demoted
`autonomous → gated` and no statement anywhere moved one back — a ratchet, not a policy. It left
34 gated rows over 14 employees with **not one on probation**.

The restore is **narrower than the demotion on purpose**. `employee_authority` has no timestamp
and no provenance column, so the only surviving evidence is the grant's own `note`. **12** say
*"Advisory-safe action, may run autonomously"* and were restored; **22** say something else
(*"Structural change is proposed, never self-applied"*, *"Cost changes touching production need
review"*, *"Inherits department authority as head"*) and keep their gate. This did not restore
"the 34" — it restored the 12 the data can justify. Executed on production: **gated 34 → 22,
autonomous 131 → 143**, 12 rows in `autonomy_control_audit` (which already existed — no new audit
table), second run restores 0.

**3. `fn_action_queue_sweep` had run hourly for weeks and never resolved one incident.** Two
defects. Its cleared-condition guard asked *"has anything in the entire company failed in 48
hours?"* — with 66 employees and ~90 crons something always has, so the branch was **unreachable**.
And dedupe partitioned on a title carrying a changing count (*"4 agent run(s) failed…"*, *"6…"*,
*"10…"*), so every day's count made a new unique title and `it` accumulated one for ever.

Dedupe now normalises a **leading** count only — narrow so *"Supplier 12 failed audit"* and
*"Supplier 45 failed audit"* stay distinct — and staleness is judged on the 24-hour window the
incident itself names. Probed first: exactly 2 title groups collapse, no collateral. Executed:
**10 superseded, open 211 → 201, incidents 10 → 1** (the live one from today survives), second run
0/0, and the 84 handoffs and 19 legal/customer/security rows untouched.

**4. `visitor_chat` had no model policy** — the ONLY purpose reaching `llm_calls` in 30 days, the
one live AI conversation the company has with a real stranger, and `fn_ai_route` was answering it
with *'no policy for "visitor_chat", fell back to general_drafting'*. Now named and set
**identical** to what it already resolved to (haiku, medium, 900), so behaviour is unchanged and
it is finally measurable as itself.

**And the 22 pack task classes were activated** rather than left inactive. They had been parked as
"a money decision for the founder"; he removed that category outright — *"there's not a single
thing that requires my approval except refunds. Nothing else, literally nothing else."* Each pack
model is mapped to the nearest model production actually serves, at the same tier, with the pack's
original choice preserved in `rationale`. **60 of 61 policies active on both projects**; only
`marketing_image` stays off because production serves no image model at all. `agent_reasoning` is
untouched.

**The remaining automation gap is written up in `docs/sessions/AUTOMATION_GAP_ANALYSIS.md`.** Its
headline: 55 action types are registered and only **16 can execute**, and `agent_actions` holds
~200 `needs_review` rows across **22 kinds** — every one already carrying a `recommendation` AND a
`confidence`. The company has decided; it is parked waiting for someone to say yes. The root cause
is sharper than "no consumer": **`agent_actions` has no assignee column at all.** `agent` is who
RAISED the item. The queue has no addressee, which is why 21 of 22 kinds have never been drained.

### WHAT THIS SESSION DID **NOT** DO, AND WHY

- **Nothing was activated.** `03_IMPORT_ORDER.md` step 18 is *"run tests and STOP before production
  activation"*, and every category manifest carries
  `status: production_research_draft_not_sme_approved`. The corpus is not SME-approved knowledge.
- **`org_departments` stayed 15 and `org_agents` stayed 67.** The pack's 24 departments and 96 roles
  live in `ops_kb_stage`, staged, where they can be read and compared. Promoting them would add nine
  unstaffed departments and 29 more dormant employees to a workforce where 56 of 66 have not run in
  30 days — making every per-employee universal in Row #3 harder for no gain in truth. That is the
  same `audit_gap` decision the evolution scan raised at 06:00 on 10 Aug, and it is still open.
- **Nothing was embedded.** 115,148 records is a spend decision on a three-day balance.
- **No SECURITY DEFINER function was created**, so production's
  `anon_security_definer_function_executable` is unchanged at 58. Both staging schemas were checked
  by execution: `has_table_privilege('anon', ...)` is **false**.
- **Row #3 could not move and did not.** Every one of the 32 red checks is short of a date, a
  customer, a founder decision or a column that does not exist; none is short of knowledge in a
  staging schema that nothing reads yet. 120/152 before, 120/152 after, 0 regressions.

---

## Session 6 (10 Aug 2026, opened 05:47 UTC) — THE CLOCK WAS READ FIRST, AND IT PAID

```
select now() at time zone 'utc'  ->  2026-08-10 05:47:29   (Monday)
```

**Opening measurement 112/152 (74%), 0 errored, 0 regressions — up 7 from 105 at 02:33.**
Not one of those seven came from a session. `cron.job_run_details` was queried before anything
else: `opportunity_scan_daily` 03:50, `kpi_review_weekly` 04:00, `index_slowdown_watch_daily`
04:15, `founder_brief_daily` 04:30, `exec_meeting_weekly` and `match_eval_weekly` 05:00 had all
fired; `exec-agents-weekly`, `evolution_scan_weekly`, the three governance monitors,
`marketing_ai_daily` and `reputation_weekly` had not. The 06:00–07:00 window was watched by a
background poller while other work continued, so no minute was spent idling against it.

**Closing measurement 06:50 UTC: 120/152 (79%), 0 errored, 0 REGRESSIONS.** Eight flips, and every
one of the eight was verified against its own predicate BEFORE the run rather than hoped for:

| flipped | how it was closed |
|---|---|
| `s21-events-nine-classes` | five emitters built — 4 of 9 → 9 of 9 |
| `s35-restructure-four-questions` | code that had shipped and never run; 06:00 cron, 0 of 4 → 4 of 4 |
| `evolution-proposes-structure` | prompting trigger + widened allow-lists, 5 of 8 → 8 of 8 |
| `future-simulator-forward-questions` | three scenarios, 1 of 4 → 4 of 4 |
| `s37-benchmark-monthly-report` | monthly report executed, 16 of 27 competitors named |
| `exec-intel-quantified-recommendation` | session 2's retry proved itself, 4 of 7 → 7 of 7 |
| `s39-governance-six-monitors` | 06:40 `regulation_watch_weekly`, 5 of 6 → 6 of 6 |
| `approval-center-five-decision-kinds` | 06:50 `marketing_ai_daily` filed the media-budget decision |

**Re-measured after the post-close work — 120/152, 0 errored, and a byte-identical MET set.** The
handoff inbox, the four new emitters, `agent_brain` v31 and the `fn_sla_watch` rewrite all landed on
production after the closing run, so the whole scorer was run again: same 120, same checks, **zero
regressions**. (An earlier attempt reported 103 and was a truncated run killed by its own 15-minute
timeout at check 130 of 152 — the sixteen apparent regressions were checks that never executed. A
partial run is not a score.)

**Not the high 120s the part-6 brief targeted, and the reason is in the blocked table below, not
effort.** Ten of the remaining 32 were measured one at a time and each is short on a date, a
customer, a founder decision or a column that does not exist — none on a build that was skipped.

`match_eval` is green again and it was the previous session's fix, proved by its own run:
05:00 cron `error`, 5 of 5 seeds refused by `leads_approved_implies_verified`; 05:16 manual run
after the fix `ok`, 5 fixtures seeded, precision 100% / recall 100%. The daily
*"CRITICAL: matching is failing"* founder alert therefore stops on its own.

### Built and verified by execution

| change | what it closed |
|---|---|
| Five event emitters — `customer.registered`, `supplier.approved`, `campaign.launched`, `ai.confidence_dropped`, `competitor.pricing_changed` | **`s21-events-nine-classes` 4 of 9 → 9 of 9.** Each fires where the fact becomes true, in the database, so every caller is covered. Verified inside an aborted transaction: customer=1 supplier=1 competitor=1 campaign=1, and ai=1 on a second probe. Nothing persisted |
| `prompt_unmeasured` trigger in `fn_evolution_scan`, and both `evolution_proposal` allow-lists widened to accept `prompting` | **`evolution-proposes-structure` 5 of 8 → 8 of 8 domains.** Prompting was the one domain the schema itself refused |
| three `scenario_library` rows — reveal fee change, paid channel failure, expansion to another emirate | **`future-simulator-forward-questions` 1 of 4 → 4 of 4 classes.** No `last_run`, no `last_result`: none has been exercised |
| `fn_period_report('monthly')` executed | **`s37-benchmark-monthly-report`** — report 142, 18,545 bytes, **16 of 27 competitors named**. 141 reports in 40 days had named none |
| `knowledge_exam` v13 stamps the grader's real confidence, `author_verified`, `source_ref` and a 90-day `review_due` on every fill | **The knowledge validator §7 called open already existed and was mislabelling its own output.** Executed on production: HTTP 200, 3 examined, `knowledge_exam_results` 492 → 495 |

### `regulation.changed` had ten subscribers, no emitter — and the brief's reason was wrong

The part-6 brief said `compliance_sources` is empty, so `regulation.changed` has ten subscribers and
no possible emitter. Measured: it holds **17 ACTIVE UAE authorities** — Dubai Municipality, DEWA,
RTA, Trakhees, SIRA, DHA, ADIBC, Estidama, TDRA and nine more — **all checked at 04:18 today**, 16
carrying a content signature, 16 with a downloaded document and **4 with a recorded change**. The
regulatory watcher works. *(Fifth brief diagnosis to be wrong while its counts were right.)*

**And the reason is now identifiable, which matters more than the correction.** Staging holds
`compliance_sources` = **0** where production holds 17. The brief measured STAGING and reported it as
production. Check which project a number came from before repeating it — the two databases diverge
on data, not on code (staging also carries **524** anon-executable SECURITY DEFINER functions against
production's 58, because staging's grants are synced broadly and it holds no real data).

What was missing is the emit: a change lands in `compliance_sources.last_changed_at` and is raised as
a `compliance_update` action, and the bus is never told. A trigger on that column now emits it.
**Verified in an aborted transaction: one emit produced TEN `event_delivery` rows**, one per waiting
subscriber, and `has_function_privilege('anon', …)` is false because the grant was revoked in the
same migration.

**`health.degraded` was the second one fixed.** The CTO subscribes to it — *"OS interface: Technology
OS consumes health.degraded"* — and it had never fired, while `os.health_changed` fired 21 times
carrying both numbers: **leadership 81 → 75 and marketplace 69 ← 75 at 04:45 today**, two operating
systems degrading with nobody woken. Repointing the subscription would have been the wrong repair —
CHANGED is not DEGRADED and an improvement must not page the CTO — so the narrower event is derived
from the wider one by trigger, rather than by editing the 8 KB `fn_os_review` that already works.
Probed both directions in an aborted transaction: a 75 → 60 drop emitted once and delivered to `cto`;
a 75 → 90 rise stayed silent.

**`rfq.classified` is the next one and was deliberately left.** Five category specialists
(`spec_commercial`, `spec_construction`, `spec_fitout`, `spec_industrial`, `spec_mep`) subscribe to
it and it has never fired. `rfq.created` IS emitted, by `trg_event_inquiry`, but nothing emits the
classification, so when a real buyer finally arrives the five specialists who should compete for the
RFQ will not hear about it. Not built here because `inquiries` carries **eleven** triggers and zero
rows, so the only way to verify an emitter is a probe insert through all eleven, minutes before the
closing measurement. It is a small, well-understood build with room to check it.

### The 14 never-emitted names, resolved into two very different piles

32 active subscriptions sat on 14 event names with zero occurrences ever. That number hid two
opposite situations, and separating them took one query against `pg_get_functiondef`:

**Nine have an emitter and are waiting for a first occurrence — honest silence, nothing to build.**
`budget.exceeded` (`fn_decision_gate` → `fn_emit_budget_exceeded`), `invoice.flagged`
(`fn_ap_bill_dupe_guard`, `fn_dispute_open`), `invoice.received` (`fn_emit_invoice_received`),
`outcome.graded` and `rollback.required` (**already inside `fn_outcome_evaluate`** — and the first
outcome comes due 2026-08-11 17:25, so it fires tomorrow on its own), `supplier.applied`
(`fn_emit_supplier_applied`, never fired because no supplier has ever completed a registration),
plus the four wired this session.

**Four now emit that did not this morning** — `regulation.changed`, `health.degraded`,
`rfq.classified` and `sla.breached`. The last is the sharpest: **`fn_sla_watch` runs HOURLY**,
detects an RFQ with no supplier quote past the SLA window, writes a founder alert and an email, and
told the bus nothing — so `ops_director`, whose subscription reads *"OS interface: Operations OS
consumes sla.breached"*, has never received one. Probed: `flagged=1`, `sla.breached` emitted once,
**delivered to `ops_director`**, and the founder alert still written.

**Five have no emitter and no detector**: `campaign.published`, `content.drafted`,
`customer.churn_signal`, `customer.complaint` (the last two blocked on `customers` = 0) and
`department.conflict`. That last one was deliberately NOT wired: `fn_decision_conflict_scan` finds
the same ACTOR reaching two verdicts on one kind, which is a decision inconsistency, **not two
departments disagreeing**. Emitting `department.conflict` for it would be mislabelling to make a
subscription look alive. It needs a real detector.

### Two checks flipped on code that had shipped and never run

- **`s35-restructure-four-questions` 0 of 4 → 4 of 4, with no code change.** The four structural
  questions were already inside `fn_evolution_scan`; `evolution_scan_weekly` last fired **3 Aug**,
  before they were added. Today's 06:00 run was their first execution and produced **12 `audit_gap`
  proposals** off real numbers: 44 of 66 employees dormant, six operating systems over 5 open tasks
  per head (Operations 19.0, Leadership 14.4), four departments holding ≥5 open tasks with nobody
  running (`evolution` 27, `legal` 25, `knowledge_eng` 14, `hr` 8), 13 departments with two or more
  wholly dormant employees. **Session 5 nearly rebuilt this. Read section 3 before building.**
- **`exec-intel-quantified-recommendation` 4 of 7 → 7 of 7.** `competitive` filed its first
  non-empty report ever at 06:02:57 (3 recommendations), `strategy` 3 after **2 attempts**,
  `procurement_quality` 3 after 2. The retry session 2 added is what fixed it; the payload-size
  hypothesis was already dead and the officers were never broken in the way four sessions assumed.

### Measured and found HONESTLY BLOCKED — do not "fix" these

| check | why, measured 10 Aug |
|---|---|
| `s32-reputation-six-dimensions` | needs six dimensions non-null on **all 66** employees. Today: correctness **0** of 66, reliability 7, cost_efficiency 3, collaboration 5, learning_speed 15 and falling to 0 at 07:00. **There is no decision-quality column at all.** Filling these is fabrication, not a build — but see the correctness note below: one of the six is a date, not a blocker |
| `s27-knowledge-seven-fields` | needs two columns that do not exist (expiry, supporting evidence) plus `source_ref` on all 1,990 rows — 1,022 have no source and inventing one is fabrication |
| `explain-confidence-score` | the `confidence` key **is** on all 8 escalation elements and is **NULL on all 8**. A UI change cannot help; stamping a constant is the `fn_governance_stamp` mistake again |
| `explain-alternatives-considered` | 0 of 34 across all four surfaces, and no per-action alternatives data exists anywhere. Same 53-writer shape as `s36` |
| `s23-reallocation-three-classes` | only one of the three resource classes can move at all. `allocation_change` holds 12 rows, every one `ai_budget_aed`, all from the 1 Aug run that destroyed 1,860 AED. Marketing budget needs a media budget that does not exist; onboarding capacity needs invites unpaused. Both are founder money decisions |
| `s24-board-before-major-decisions` | **scoped precisely, not built.** `fn_board_review` is 2,743 characters, deterministic, and calls **no model** — it applies seven lenses to the same facts and writes seven `board_opinion` rows. `fn_decide` is the SOLE writer of `decision_record` (11 rows, all inside 30 days) and is one of the five routines the check accepts. So the whole build is one guarded `perform fn_board_review(p_kind, v_dr_id::text)` before `fn_decide`'s final `return jsonb_build_object('kind',p_kind` — that anchor appears once. It was not done today because the check is a **30-day universal** so it cannot flip either way before ~9 Sept, `fn_decide` is the gate that queues money approvals, and `fn_board_review` calls `fn_challenge`, which writes a `challenge_record` per decision. That is a change to the decision path to make with room to watch it, not as the last act of a long session |
| `s29-scan-five-questions` | 4 of 5. "Rising keywords" has **no data source**: `seo_categories` holds 24 search terms with no volume and no time series, `category_keyword` is a 1,839-row routing dictionary. A keyword-volume feed costs money |
| `personalization-learns-founder-habits` | the founder has decided **12 things ever** — 7 of them `os-preview@quotesdone.com` rejecting in a 53-second burst on 13 July, newest decision **2026-07-13**. A habit store over that measures nothing. Blocked on usage, not on code |
| `employee-learning-progress` | **0 of 83 examined agents have exam results on two different days.** Not a defect: `fn_exam_pick_agent` walks 207 distinct `agent_knowledge.agent_key` values at ~6 exams a day and started 26 July, so it is still on its first pass. Only 66 of those 207 keys are employees; the rest are `cat:` specialists with no workspace |
| `time-machine-restores-six-dimensions` | 5 of 6 on all 13 snapshots; `customers` first appears on the **2026-08-09** snapshot and is written nightly now, so the 14-day universal completes ~**24 Aug**. Nothing to build |
| `s39-governance-six-monitors` | 5 of 6 at 06:22; the sixth (`regulatory changes`) fires at 06:40 |

### End-of-session sweep, 10 Aug ~07:00 UTC

| checked | found |
|---|---|
| GitHub Actions, 12 most recent runs | all `success`, **no zero-step job** (a zero-step job means quota, never code) |
| Vercel deployments | 20 listed, **all READY**, including this branch's preview at 06:27 |
| Vercel runtime errors, 24h | **none** |
| Production `cron.job_run_details`, 24h | **0 failed runs** |
| Production `agent_runs` errors, 24h | 27, and **both causes are already closed**: `match_eval` at 05:00 (fixed at 05:16, ok since) and `resilience_watch`, whose 26 errors all predate 2026-08-09 10:50 and whose last 118 runs are `ok` — *read the dates before treating a rolling window as live* |
| Production security advisors | 628 lints, **0 ERROR**. 442 INFO `rls_enabled_no_policy`, 69 + 67→**58** secdef-executable, 47 `function_search_path_mutable`, 3 `extension_in_public` |
| Production performance advisors | 171 lints, **0 ERROR** — 85 unindexed FKs, 70 unused indexes, 13 `auth_rls_initplan` |
| Staging `cron.job_run_details` + `agent_runs`, 24h | **0 failed runs, 0 errors** |

The evolution scan's *"resilience_watch failed 182 times in the last 7 days"* is the same rolling
window and is not a live failure.

### THE BIGGEST SINGLE BLOCKER LEFT IS THAT THE WORKFORCE DOES NOT WORK

Several of the remaining 32 are per-employee UNIVERSALS over all 66 active employees. Measured
10 Aug:

```
active employees                                  66
no agent_runs row in 30 days                      56
no agent_memory row in 30 days                    44
fewer than two dated exam results                 66
employees reaching agent_brain at all in 7 days    6
```

`employee-current-thoughts` needs an `agent_memory` row for **every** active employee — 44 have none.
`employee-performance-trend` needs two observations each — 12 of 66 have them.
`employee-learning-progress` needs two dated exam results each — nobody has them, because the exam
walks 207 `agent_knowledge` keys at six a day and started 26 July, so it is still on its first pass.
`employee-knowledge-used` needs every decider to have a knowledge-usage record.

**No code change satisfies any of these.** They are all the same fact: 56 of 66 employees have not
run in a month, so there is nothing to render, trend or grade. Fabricating a thought or a run for a
dormant employee is exactly what a scorecard exists to catch. This is the one decision that unblocks
several checks at once, and the company raised it itself at 06:00 this morning — the `audit_gap`
proposal that asks, for each dormant role, whether nothing routes to it or the role is not needed.
It is also why 43 of the 85 open handoffs are stranded.

### REPUTATION CAN TAKE AUTHORITY AWAY AND HAS NO WAY TO GIVE IT BACK — FOUNDER DECISION

`reputation_weekly` ran on production at **07:00 and confirmed session 5's fix by execution:
probation 7 → 0**, learning_speed nulled for all 66, zero new demotions. But the demotions it made
*before* the fix are still in force, because `fn_reputation_recompute` only ever runs

```
update employee_authority set max_tier='gated' ... where p.tier='probation' and a.max_tier='autonomous'
```

There is no statement anywhere that moves an authority back. Measured now:

```
gated       34 rows / 14 employees   — of which on probation: 0
                                        held by 'trusted':    9 rows
                                        held by 'standard':  25 rows
```

**And the classes are ordinary ones.** `health_report` is gated for 2 employees and autonomous for 7.
`uptime_verify` 2 gated / 6 autonomous. `forecast` 2 / 4. `compare_quotes`, `qualify_inquiry`,
`supplier_verify` 1 gated each against 9 autonomous. That is not a policy that certain classes need
approval — it is per-employee residue from a scoring bug that has since been fixed.

**Not restored, and that is the escalation.** Moving an authority from `gated` back to `autonomous`
means the action stops requiring approval, and two of the affected classes are `money_verify` and
`invoice_review`. Widening authority on a money path is the founder's call, not a session's. The
list is 34 rows over 14 employees and every one is now rated `standard` or `trusted`.

### THE BRAIN RUNS SECONDS FROM ITS TIMEOUT AND EVERY MISS WAS LOGGED AS SUCCESS

Found while verifying the handoff inbox, and it is the most consequential measurement of the day.
`agent_brain` over 7 days on production:

```
calls                425        distinct employees      6   (of 66)
avg prompt tokens 13,947        max prompt tokens  33,203
calls over 45s        28        outright failures       7
```

**28 calls in 7 days ran within ten seconds of the timeout, 7 returned nothing — and every one of
those 425 wrote `agent_runs.status = 'ok'`.** `it`'s single prior success took **53,139 ms**. There
was no signal anywhere that the company's reasoning loop was operating on that margin.

It is now recorded truthfully (`status: 'error'`, with the prompt size in `counts`), which matters
beyond the log: `fn_evolution_scan`'s `repeated_failure` trigger fires at three or more errors in
seven days, so the estate will now raise its own proposal about this instead of a session having to
notice it. **No context cap was imposed** — trimming what an employee knows is a quality decision
with a founder-visible consequence, and the loop that surfaces it is now working. Let it report
first.

Employees are exercised hourly by `cos_execute_hourly` (`50 * * * *`), which is what reaches
`agent_brain` — so the six agents that actually run will drain their handoff inboxes hourly from
now. The other 60 do not run at all; 44 are dormant, which is the `audit_gap` proposal the evolution
scan raised at 06:00.

### `correctness` is a clock, not a missing grader — checked before calling it blocked

`fn_reputation_recompute` reads `correctness` from `outcome_record.verdict`, and all **66** rows read
`pending` with **0 observed**, which looks exactly like a grader nobody wrote. It is not.
`fn_outcome_evaluate` exists, `outcome_evaluate_daily` is active on `30 3 * * *`, and **not one
outcome is due yet**: the earliest `due_at` is **2026-08-11 17:25** and the latest is 14 September.
The oldest record was created 28 July with a 14-day measurement window.

So `correctness` starts filling from **12 Aug** with no code change, and `s32` is short of six
dimensions for a different reason — there is no decision-quality column at all, and cost_efficiency
only exists for the handful of employees that spend on models. Do not build a grader; one is already
scheduled and waiting for its first measurement window to close.

### The four new emitters raised the public-exposure number, and it was put back

Postgres grants EXECUTE to PUBLIC on every new function, so the four SECURITY DEFINER trigger
functions took production's `anon_security_definer_function_executable` from **63 to 67** — the one
figure in the daily security alert that is genuinely about public exposure, and the one left for the
founder to work through caller by caller. Caught in the advisor sweep in the same session and
revoked from `public, anon, authenticated` on both projects; `has_function_privilege` now returns
false for all four, and the emitters were **re-probed after the revoke** and still fire
(customer=1 competitor=1 campaign=1), because a trigger function runs as the table owner.
**Any new SECURITY DEFINER function adds one to that count unless the grant is revoked.**

### The 63 anon-executable SECURITY DEFINER functions, triaged instead of counted

Every one of the 63 was checked against the Next.js source and the edge functions rather than
revoked blind, because revoking blind is what breaks product surfaces:

| bucket | n | what the evidence says |
|---|---|---|
| **BROWSER** | 7 | named in `src/` — `fn_customer_preference_learn`, `fn_os_memory`, `fn_supplier_document_impact`, `fn_supplier_knowledge_graph`, `fn_supplier_opportunities`, `fn_supplier_quote_recommend`, `fn_supplier_twin`. Real supplier-portal and OS-shell surfaces. **Left alone** |
| **TRIGGER** | 5 | return type `trigger`; nothing calls them by name in any language — `fn_approval_raise_on_award`, `fn_org_task_cross_os_guard`, `fn_po_orders_link`, `trg_company_event_dispatch`, `trg_learn_customer_preference`. **Revoked on both projects** |
| **INTERNAL** | 51 | not named anywhere in `src/`. The ones with edge references are called with the service role; the rest are cron- and database-only. Each still needs one look, so they were not touched |

**Production `anon_security_definer_function_executable` 63 → 58**, verified by
`has_function_privilege`, with `trg_company_event_dispatch` re-probed afterwards: an insert into
`company_event` still runs the dispatch trigger without error.

**Then the BROWSER bucket turned out to be wrong, and the answer is much stronger than 58.** All
seven "browser" matches are **comments**, not calls — each component names the routine in a comment
explaining where its data comes from. Measured across the whole frontend:

```
.rpc(            in src/   0 occurrences
rest/v1/rpc      in src/   0 occurrences
app/ or pages/ outside src/   none — src/ IS the whole frontend
os_api / supplier_api / customer_api / messages_api
                           service-role key only, 0 anon or publishable key references
```

**Nothing in the browser calls any Postgres function directly.** Every routine reaches a screen
through an edge function holding the service role, so `anon` and `authenticated` need EXECUTE on
none of the 58.

**Not revoked, and this is the escalation, not caution.** PostgREST is publicly exposed, so an
external integration could be calling `/rest/v1/rpc/<fn>` with the anon key from outside this
repository — and whether one is is a fact only the founder holds, which is the escalation category
they defined. The repository-side pass they asked for is done and the answer is unambiguous. If no
external system calls production's PostgREST RPC endpoints, this closes it:

```sql
do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.prosecdef and p.prokind in ('f','p')
              and has_function_privilege('anon', p.oid, 'execute')
  loop execute format('revoke execute on function %s from public, anon, authenticated', f.sig); end loop;
end $$;
```

### The IT employee's URGENT incident is a misreading, five escalations deep

`agent_actions` holds **82 `needs_review` handoffs**, oldest 24 July, **none completed since 25
June** (7 done, all 25 June). All 82 titles are distinct, so this is not the `licence_expiring`
duplicate storm — it is the same question re-asked with a louder title because nobody answers.
`it` alone holds 28 and escalated one incident five times in three days:

> *"URGENT: event-bus retry loop is unbounded"* · *"Systemic Ingress Failure — review.step
> duplicate storm on timestamp 01:41:05.615334"* · *"(2nd escalation) … 18 duplicate review.step
> rows, hard-stop not applied"*

**Measured: there is no duplicate storm.** The two clusters it names are
`2026-08-06 03:59:05.598967` with 150 rows and **150 distinct `entity_id`s**, and
`2026-07-27 01:41:05.615334` with 20 rows and **20 distinct `entity_id`s** — batch inserts sharing
one transaction timestamp, not duplicates. Over 7 days every `company_event` type has
`count(distinct (entity_type, entity_id, occurred_at)) = count(*)`. The bug is the handoff queue
having no consumer, which is what turned one wrong reading into five founder-facing escalations.

**FIXED AFTER THE CLOSING MEASUREMENT, and it cost two failures to get right.** `fn_agent_handoff_inbox`
lists the three oldest open handoffs in the employee's own context; `fn_handoff_answer` closes one
and posts the reply back to the **asker** as an `agent_memory` row, which `fn_agent_context` already
surfaces — that is the half that was missing, because before this, answering a handoff reached
nobody. It refuses an empty answer, a handoff addressed to a different agent, and a second close of
a decided row; all three refusals verified alongside the success path in an aborted transaction.

Executed on production for `it`: **HTTP 200, open handoffs 29 → 26, done 7 → 10, three askers
notified**, with answers of 509–797 characters — and #1748 correctly refusing rather than inventing:
*"Blocked: this needs the live project region setting, which is not in my telemetry snapshot."*
**The first handoff completed since 25 June.**

**THE INBOX FIXES HALF THE QUEUE. SAY SO.** Measured straight after: **85 open handoffs, 42 addressed
to an employee that actually runs, 43 stranded** on employees that have not reasoned once in seven
days. Only six of 66 employees reach `agent_brain` at all (`it` 26 open, `brief` 9, `onboarding` 6,
`docs` 1, `intel_director` 0, `ceo` 0), and they drain three per hourly `cos_execute` run. The other
43 will never drain however good the inbox is — they are addressed to the dormant half of the
workforce, which is precisely the `audit_gap` proposal the evolution scan raised at 06:00 this
morning: *decide, for each dormant role, whether nothing routes to it or the role is not needed.*
The queue is also still growing: 82 at 06:00, 85 by 07:20 net of the three closed.

**Both failures are kept in the record.** The first inbox emitted five items at 300 characters each —
2,082 characters for `it` — and agent_brain then **timed out twice at ~56s**. Measured cause: `it`'s
only prior successful call, at 01:51 that morning and **before** the change, already took
**53,139 ms** on a 30,821-token prompt. It had been three seconds from the cliff on its own and 1.7%
more prompt pushed it over. Inbox trimmed to three items and 110 characters: 2,082 → **678**.

And nothing said so, which is the second defect: an empty model return produced the apology text
**and an `agent_runs` row reading `status: 'ok'`** — the same silent failure `exec_agents` was fixed
for in session 2. A turn where the model returns nothing now records `status: 'error'` with the
prompt size, and no longer stores the apology as the employee's current reasoning.

**Historical note — the original diagnosis.** `agent_brain` writes the handoff
(`agent_actions`, `kind:'handoff'`, `status:'pending'`, which `trg_action_gate` rewrites to
`needs_review`) and **`fn_agent_context` never mentions `handoff`** — measured, not read. So the
receiving employee's own context contains no trace of what was handed to it: a handoff is a message
with no inbox. The fix is an inbox — the agent's open handoffs, capped, inside the context every
employee reasons from. It was not made in this session on purpose: `fn_agent_context` is 31 KB and
feeds every AI call in the company, `agent_brain` is **93% of the OpenRouter spend** with about
three days of balance left, and there were twenty-five minutes before the closing measurement.
Changing the most central and most expensive routine on production without room to verify it is how
a session breaks the company — and the two timeouts above show the instinct was right. The fix that
shipped avoids `fn_agent_context` entirely: `agent_brain` is the only place an employee both reasons
AND can act, so the inbox lives there and the 31 KB routine every AI call depends on was not touched.

---

## Session 5 (10 Aug 2026, opened 02:33 UTC) — THE CLOCK, AGAIN, AND FOUR DEFECTS IN THE MONEY PATH

```
select now() at time zone 'utc'  ->  2026-08-10 02:33:05   (Monday)
```

**The previous session ended at 02:30 UTC. This one opened at 02:33 — three minutes later.** The
part-5 brief listed ten crons "due between 03:50 and 07:00 that morning" and asked which had fired.
At session open, **none had**; the earliest was 77 minutes away. This is the third consecutive
session opened inside the previous one's shadow. Opening score **105/152 (69%), 0 errored, 0
regressions** — identical to 02:30, exactly as the clock predicts.

One cron HAD fired in the gap: `capability_verify_daily` at 02:15, first run ever, and
`s34-resilience-measured` was already MET in the opening run.

**The window is not ten crons. It is 78.** Every active job with a fixed hour between 03:16 and
07:00 today: 78 of them, weekday-or-Monday. The ten in the brief are the subset that gate Row #3
checks. Three more that matter and were not listed: `kpi_review_weekly` (`0 4 * * 1`, the outcomes
track `s33` needs), `bi_snapshot_6h` (06:35, the KPI track), and `marketing_ai_daily` (06:50).

### Four defects, all found by reading rows under a verdict rather than taking it

| defect | consequence | state |
|---|---|---|
| `fn_reallocate` released 20% of the AI budget from all twelve departments and granted it to **nobody** — no department was over 85% | **1,860 AED destroyed**, `department_budget` 9,500 → 7,640, run note claimed "moved from idle to saturated departments". Compounding, monthly, and `department_budget` is enforced by `fn_check_spend` / `fn_ai_spend_guard` / `fn_budget_available` / `fn_ai_route` | FIXED, both projects |
| `fn_reallocate`'s grant loop divided the pool by a hard-coded `3` regardless of recipient count | latent leak; with one recipient two-thirds of the pool vanished | FIXED |
| `fn_budget_rollup` inner-joined its spend subquery, so a department with zero spend was never rolled | ten of thirteen rows still read `period_label 2026-07`; a department at 90% that goes quiet reads 90% forever and stays halted | FIXED |
| `fn_reputation_recompute` was about to demote **three employees at 07:00** on two dimensions that score noise | see below | FIXED |

### The two reputation dimensions, and why nobody should have been on probation

Predicted read-only at 03:15, before the 07:00 run: five employees under 50 — `legal` 43.8, `cpo`
45.0, `learning_dev_mgr` 45.2, `analytics` 46.3, `ops_director` 49.5, three of them newly demoted.
Every one was below the line because of these two and nothing else; correctness, reliability and
cost_efficiency are NULL for all five.

- **`learning_speed` still measured a frozen seed.** Session 4 nulled it at zero validated rows —
  half the fix. `author_verified`: **292 rows, created 24–28 July only, 4 owners, none since**.
  `unvalidated`: **1,694 rows, 23 Jun → today, 23 owners, still growing**. A frozen July seed over a
  denominator that grows every time an employee learns anything, so the score **falls monotonically
  with work done**. There is no `validated_at` column, so no liveness guard is sound. Now NULL for
  everyone. **This makes `s32` harder, not easier** — it can never read 6 of 6 until a validator
  exists. Building that validator is the real fix and is still open.
- **`collaboration` counted undecided drafts and ownership markers as failed reviews.**
  `review_chain.decision` mixes verdicts with states and `stage` proves it: 208 NULLs are stage
  `drafted` with `reviewer_agent` NULL on **all 208**; 183 `owned` are stage `ownership` and first
  appeared 6 Aug; `hold` and `required` are states. `cpo` has **eight rows, all `owned`**, and
  scored 0.0% for having taken ownership of eight things. Now `approve / (approve + reject +
  request_revision)`.

After both: 60 standard, 6 trusted, **zero probation, zero demotions** — verified by execution on
staging, `employee_authority` byte-identical before and after.

### The opportunity scan was 25 minutes from reporting demo fixtures as market demand

`marketing_category_demand.inquiries_90d` counts inquiries with **no fixture filter**, and hvac's 6
and aluminium's 1 are **7 of 7 `qd_demo_fixture`**. Today was the new body's first run. At 03:50 it
would have written *"the hvac industry drew 6 inquir(y/ies) in 90 days… demand is running ahead of
the supply able to answer it"* and put it in front of the founder as detected demand. Fixed in the
two demand-driven blocks only; the shared view is untouched because four routines read it.
**This also makes `s29` harder** — it stays at 3 of 5 rather than reading a false 5 of 5, and
reaches 5 of 5 the day a real inquiry arrives.

### The marketing budget decision now reaches the founder

Two paused QuotesDone Meta campaigns, AED 0 spend, and `fn_marketing_ai` has said *"launch and fund
it"* daily since 30 July **without ever naming the money** — because no media budget exists anywhere
(`budgets` and `budget_lines` empty; `department_budget` is AI model spend and does not cover media)
and the amount is a founder decision. Filed as kind `finance_marketing_budget` so
`fn_governance_stamp`'s existing sensitive-domain rule escalates it.

Probed rather than reasoned about: `mkt_rec` inserts `pending` and `trg_action_gate` immediately
rewrites it to `needs_review`, because **`fn_authorize` resolves `marketing_ai` to role `"guest"`**
— `role "guest" lacks permission "run_agent_action"`. That is why all 161 `needs_review` rows sit
where they do. **Granting that role would push the paused share from 2.6% to ~15% and regress
`approval-center-everything-else-automatic`**, so the 159 are left alone.

### Checked and found clean — recorded so nobody re-derives it

- **`fn_agent_silence_watch` is NOT a fifth `agent_runs` offender.** Despite the name it watches
  **cron jobs**, not employees; its only `agent_runs` use is writing its own run row. Clean.
- **`employee_authority`'s 285 rows over 67 agents is BY DESIGN** — keyed by (agent_key,
  action_class), ~4.25 classes each. The 44 agents with "conflicting" `max_tier` simply have
  different authority per action class. Not a duplication bug.
- All eight morning routines are **md5-identical across both projects**, as are the three governance
  monitors, and all three dry-run clean. `fn_regulation_watch` returns `sources: 0` — it succeeds
  while watching nothing, which satisfies `s39`'s scheduling question but governs nothing.
- **`fn_exec_meeting` will flip `exec-meeting-agenda-six` at 05:00**: executed on staging, all six
  sections present on **all 12** contributions, 2 challenges in the window.
- **`fn_founder_brief` will flip `companion-overnight-brief` at 04:30**: staging's brief written by
  the current body scores **8 of 8**; production's is yesterday's, written by the old body, at 4 of 8.
- **`fn_index_slowdown_watch` will find exactly one fall at 04:15** — `company_maturity` 44.1 → 42.4
  on 6 Aug, −1.70 — and raise a proposal, which should flip `s31`.
- **`s26-discover-suppliers` is a FOUNDER SPEND DECISION, not a defect.** The scraper is an Apify
  actor (`compass/crawler-google-places`), 22 runs, **all manual, none since 19 June, and there is
  no cron for it at all**. Restarting it commits money to a third party. Not scheduled unilaterally.
- **The part-5 brief's claim that "`ROW3_STATE` still leads with the 57" is itself wrong** — the
  string `57` has never appeared in this file. It lives only in the part-4 and part-5 briefs. That
  is the third brief misdiagnosis in three sessions; brief COUNTS are reliable, brief DIAGNOSES are
  not.

---

| run | score | what changed |
|---|---|---|
| opening | **28/152 (18%)** | inherited, re-measured, unmoved |
| after Intelligence | 38/152 | `fn_ws_intelligence` + the Intelligence Centre |
| after Executive Home | ~50/152 | `fn_ws_exec_home` + the landing screen |
| after the employee workspace | ~57/152 | `fn_ws_agent_ops` extended |
| after the Operating System | **66/152 (43%)** | `fn_ws_company_os` + the map |
| after Memory, notifications, voice | **76/152 (50%)** | `fn_os_search`/`fn_os_memory`, `fn_ws_notifications` |
| after explainability | **80/152 (53%)** | `fn_owning_os` + the four action surfaces |
| after live company, reports, what-if | 88/152 (58%) | `fn_ws_live_company`, `fn_report_drilldown`, the org chart, 5 more departments in `v_department_health` |

| after root-cause fixes + realtime + manual | **91/152 (60%)** | customer creation at intake, agent_brain instrumentation, action-queue sweep, twin realtime, cron registry |

152 verdicts every run. **0 errored, denominator verified, every run.**

Eight scorer runs. The row nearly tripled its score in a single session.

### Session 2 (9 Aug 2026, evening)

| run | score | what changed |
|---|---|---|
| opening | **91/152 (60%)** | re-measured, unmoved — see below for why |
| after the exec meeting + the manual | **93/152 (61%)** | `exec-meeting-replayable`, `s38-manual-self-documenting` |
| after the flow map | **94/152 (62%)** | `mission-control-flow-animation` |
| after the memory reaches the gate | **95/152 (62%)** | `s28-blocks-repeat-failures` |
| after routing, replay reader, reactive bus | **96/152 (63%)** | `s25-routing-seven-task-classes` |
| after reputation reaches authority | 97/152 | `s32-reputation-drives-authority` |
| after the command centre | **98/152 (64%)** | `command-center-six-boards` |
| after policies and the prose insight | **100/152 (66%)** | `explain-policies-applied`, `exec-intel-narrative-insight` |

**0 errored, 0 regressions**, every run.

The three fixes the previous session expected to accrue moved the score by zero, and measuring
each one separately says why — one is genuinely waiting on traffic, one is working and will never
reach its threshold on its own, one worked and its check needs a different number:

| fix | before | now | verdict |
|---|---|---|---|
| customer created at intake | 0 customers, 7 inquiries all null | **unchanged** | deployed and correct — `inquiry_intake` v21 (18:25 UTC) creates the row. No inquiry has arrived since. Waiting on a buyer, not on code. |
| agent_brain instrumentation | 7 of 66 employees had ever run | **8 of 66** | writing. `kb_usage_log` 0 → 2 rows, `agent_memory` 22 → 26 distinct in 30d. The checks are 66-of-66 universals; one employee an hour does not reach them. |
| hourly action-queue sweep | 316 pending/needs-review | **181** | working, −135. `strategic-not-operational` needs strategic (115) to exceed operational (181), so it is still short by 66. |

Four things the previous brief called clocks or blockers were re-measured, and one of them was
neither:

- **`fn_bi_snapshot` had no cron at all.** It walks `metric_definition`, executes each metric's
  own `measure_sql` and writes `metric_snapshot`. The only thing that ever called it was
  `fn_emit_metric_alerts`, weekly on a Monday, as a side effect of an alerting job — so fourteen
  KPIs were computed once a week by accident and presented as a live digital twin.
  `metric_snapshot` had rows on exactly two days ever. Now scheduled `35 */6 * * *` on both
  projects and registered in `cron_registry`. All 14 metrics dry-run to a value on production.
- **the 04:30 founder-brief cron is fine.** 22 runs, 22 successes, last 2026-08-09 04:30:01. The
  extended `fn_founder_brief` was deployed *after* that run, so it has never executed on
  production — today's brief carries none of the four new figures. Verified by executing the
  deployed definition on staging: all four figures land and the `founder_alerts` row is written.
  First real run 04:30 UTC on 10 Aug.
- **the three governance monitors are new, not broken.** `approval_trace_audit_weekly`,
  `decision_conflict_scan_weekly` and `regulation_watch_weekly` are active with Monday 06:10 /
  06:20 / 06:40 schedules and **zero runs ever** — they were created after the last Monday. All
  three were executed on staging and all three succeed, so their first firing will not fail.
- **`s38-manual-always-current` was already MET.** 0 undocumented, 0 ghosts, against 151 active
  jobs. The previous brief's "28 undocumented, 2 stale" was fixed at the end of that session.

### What was built

| change | what it closed |
|---|---|
| `fn_exec_meeting` — six agenda sections, all ten participants, ranked/owned priorities, `fn_challenge` on the top three | `exec-meeting-agenda-six`, `-debate`, `-priorities-agreed` (all verified on staging; production flips on the Monday cron) |
| `fn_ws_reports` + `MeetingReplay` in the shell | **`exec-meeting-replayable` — MET** |
| `fn_challenge` — a refusal driven only by prior outcomes now says so | a `recommend_against` with an empty `reasoning`, which the meeting would have produced weekly |
| `v_operating_manual` + governance_policy, decision_policy, org_departments | **`s38-manual-self-documenting` — MET**, 198 → 254 entries |
| `bi_snapshot_6h` cron + registry row | `digital-twin-live-kpis`, and the KPI track of `s33-replay-six-tracks` |
| `fn_ws_company_os` + a `flow` key, and `OsFlowMap` | **`mission-control-flow-animation` — MET.** 932 deliveries in 7d, 738 attributed to a sending system, 37 cross-OS edges drawn. The declared `os_interface` graph joins to ZERO cross-OS edges, so the map is drawn from what was delivered rather than from the contract |
| `fn_should_escalate` consults `institutional_memory` | **`s28-blocks-repeat-failures` — MET.** 287 lessons on file and 1,229 gated actions a month that had never met. Three-token match, set by measuring: it fires on 4 of 1,229 (0.3%), three of them precise |
| `fn_capability_verify` + `capability_verify_daily` | `s34-resilience-measured`. 16 capabilities graded by a view nothing read. **`matching` has been FAILING at 33% since 5 Aug and no surface said so** |
| `fn_period_report` + a Competitive Position section, `monthly_report` repointed | `s37-benchmark-monthly-report` leg 1 MET. 27 competitors, none ever named in a board report. **0 of 27 offer supplier anonymity** — the differentiator this marketplace is built on |
| four `model_policy` rows | **`s25-routing-seven-task-classes` — MET.** vision, OCR, translation and summarization were running with no tier, no fallback and no cost ceiling |
| `fn_ws_company_os` + a `tracks` key | `s33-replay-six-tracks` spanner leg: 0 → 1 routine spanning all six track tables |
| `trg_company_event_dispatch` | `s21-no-polling` trigger leg MET. Delivery went from a 15-minute scan to **0s measured**; the 7-day median converges |
| `fn_check_spend` consults `agent_reputation` | **`s32-reputation-drives-authority` — MET.** Seven probation employees kept their nominal spend ceiling while `max_tier` already said 'gated' |
| `fn_ws_exec_home` + four figures, and the Console strip | **`command-center-six-boards` — MET**, 2 of 6 → 6 of 6 |
| `fn_action_policies` + four action payloads + two components | **`explain-policies-applied` — MET**, 34 of 34. decision_trace holds 4 rows and could never have answered for 34 actions; decision_policy could |
| `fn_health_index` fills its own `note` | **`exec-intel-narrative-insight` — MET.** The lobby had a prose slot filled only when there was almost no data |
| `exec_agents` retries once and logs the truth | **A silent failure, not a check.** Three of six officers filed empty reports for a week, each recorded as `status: ok` |

### Session 4 (9 Aug 2026, late — opened 22:42 UTC)

**The opening measurement was 100/152, unchanged, and the reason is the clock, not twelve broken
routines.** The part-4 brief said twelve checks "flip on crons that have since fired" and instructed
that anything still MISSING was a defect to debug. The brief was written at ~22:35 UTC and this
session opened at **22:42 UTC — seven minutes later**. Its table lists the hour each cron NEXT
fires. Not one of the twelve had reached its hour.

```
select now() at time zone 'utc'  ->  2026-08-09 22:42:08   (Sunday)
```

The local date rolls over four hours before UTC does, so "today is the 10th" in Dubai was 22:42 on
the 9th in the database. **Read `now()` before calling an un-flipped check a defect.** Corroborated
without relying on arithmetic: `bi_snapshot_6h` (`35 */6 * * *`), `capability_verify_daily`
(`15 2 * * *`), `index_slowdown_watch_daily` (`15 4 * * *`) and the three governance monitors all
have **zero runs ever** — impossible unless they were created after their most recent slot.

| run | score | what changed |
|---|---|---|
| opening | **100/152 (66%)** | re-measured, 0 errored — no cron had fired |
| after the knowledge provenance fix | 100/152 | s27 1 of 7 → 2 of 7, no flip |
| after the genome | **102/152 (67%)** | `genome-eleven-attributes-stored` + `genome-inherited-by-every-employee` both MET |
| after the 00:35 cron | **103/152 (68%)** | `digital-twin-live-kpis` MET — the first of the twelve, watched rather than predicted |

**THE FIRST OF THE TWELVE FIRED AND WAS MEASURED, NOT ASSUMED.** `bi_snapshot_6h` ran for the first
time in its life at **2026-08-10 00:35:00**, status succeeded. `metric_snapshot` went 42 → **56
rows** and all **14** active metrics carry a reading inside the window. The check now reads "0 of 14
active metric(s) have no snapshot inside 24h ... newest 2026-08-10 00:35:00" — **MET**. Everything
the opening section says about the clock is confirmed by the clock itself.

#### What was built

| change | what it closed |
|---|---|
| `fn_knowledge_provenance_stamp` + trigger + backfill | `owner_agent` 1,148 null → **0 of 1,986**; `source_ref` → 1,016. **s27 1/7 → 2/7.** Five DB functions and fourteen edge functions write `agent_knowledge` and not one set either field; the newest cohort was still growing, so a backfill alone would have been undone by the next cron |
| six `company_constitution` sections | **`genome-eleven-attributes-stored` — MET**, 5 of 11 → 11 of 11 |
| genome block injected into `fn_agent_context` | **`genome-inherited-by-every-employee` — MET**, 2 of 11 → 11 of 11 across all 66 |

#### Four of the six genome attributes were missing LABELS, not missing facts

The check is label-anchored on purpose. `brand-quick-reference.md` (a real Dropbox asset already in
`agent_knowledge`) carried the brand voice; `vision_horizon` carried the growth strategy;
`career_level`'s seven levels carried the hiring bar; the constitution already carried the ethical
commitments under other names. **Two were founder doctrine and were ASKED, not authored** — risk
appetite (aggressive growth) and leadership style ("the executives should always make sure targets
are achieved, and accordingly push the team for that").

#### The `match_eval` caller, answered

Nothing calls it with a *wrong* secret — it is called with **no secret at all**. `requireInternal`
returns early on an empty credential without consulting `fn_internal_auth`, and
`internal_credential_audit` (live since 3 Aug) holds **zero `match_eval` rows**, including for the
5 Aug 18:49 refusal; a wrong secret is always recorded as `unknown_credential`. It is never called
alone either — 5 Aug is strictly alphabetical (`dispatch_inquiry` :07, `doc_extract` :10,
`match_eval` :24, `quote_extract` :34, `route_inquiry` :37). A sweep posting an empty body over a
sorted slug list. Not `verify_prod_readiness.mjs` (GET-only) and not `deploy_functions.ps1`.

**The same pattern elsewhere, and much larger: `send_whatsapp` was refused 823 times**,
`unknown_credential`, every two minutes from 3 Aug 05:06 to 8 Aug 21:38. The 4 Aug identity capture
names it: `pg_net/0.20.4` from `3.1.231.113` then `47.131.52.147`, presenting a real 64-char secret.
Production's own `wa_flush` is fine — `cred_cron_notifications` hashes to credential 13, active and
scoped. So it was another Postgres: a branch database carrying production's `wa_flush` cron with
production's URL baked in and its own regenerated secret, the same class of incident `qd_guard.mjs`
records for 3–4 Aug. It stopped when that database went away. Neither surviving non-prod project can
do it now — `staging-batch0` has zero crons naming the production ref, and the
`fix/row3-root-causes` preview branch has no `cron` schema at all.

**`fn_internal_auth` records nothing on a successful non-legacy auth.** `internal_credential_audit`
is a refusal log, not an access log; absence there is not absence of traffic.

#### Two traps found, and NOT walked into

- **`s36-recommendation-seven-fields` is not "3 of 7 needing a writer change".** Four fields have no
  column at all (the brief named three and omitted *expected impact*). Worse, two of the three
  "covered" fields are trigger boilerplate: `fn_governance_stamp` stamps `confidence := 0.9` and a
  template `evidence` object whenever the caller omits them, so `confidence` is **0.9 on all 1,165
  rows, one distinct value**. Filling four more columns from that trigger would read 7/7 in thirty
  days and mean nothing. The honest build is per-writer, and there are **31 writers across 32
  recommendation kinds**, none sharing a helper.
- **`s27` cannot be closed honestly.** `agent_knowledge.confidence` is 0.70 on 1,711 of its 1,786
  non-null rows — the same decorative constant — so the 200 nulls were left alone. `source_ref`
  reaches only 132 of the 1,148: the other 1,016 are the 26–27 Jul category batch, and the estate's
  own labels distinguish `expert_framework_v1` from `v2` from `authored`, which is not recoverable
  per row. `expiry` and `supporting evidence` have no column and no derivable content.

#### Open, and deliberately not invented

- **200 knowledge items have no `review_due` at all**, so `fn_knowledge_decay` can never mark them
  stale — they are permanently invisible to review. No single interval is derivable: `profession`
  uses 90, 365 **and** 396 days and `company` is scattered 367–398 (a fixed target date, not an
  interval). Setting one is a knowledge-director decision, not a derivation.
- **`what-if-projected-deltas` and `what-if-confidence-score`** are universals over *all*
  `simulations` rows, so the four legacy 28-July rows block both. Back-filling or deleting them
  would be fabrication.
- **`time-machine-scrub`** needs a six-month-old snapshot and `company_snapshot_daily` has 12 runs.
  Only time closes it.

#### Found after the first three PRs, mostly by the end-of-session sweep

- **`s21-no-polling` was a real defect, not a converging clock — FIXED.** This document said delivery
  went "to 0s measured" and "the 7-day median converges". The median was 543 / 553 / 557 / **561s**
  across 6–9 Aug: flat. Only **21 of 508 deliveries (4%)** were sub-5s. Two suspects were cleared by
  experiment rather than by reading — `FOR EACH STATEMENT` is fine, because `fn_event_dispatch`
  sweeps instead of reading `NEW` (two rows in one statement both delivered). The defect was the
  argument: `fn_event_dispatch(1)` is **`p_lookback_minutes`**, so any event whose `occurred_at` was
  more than sixty seconds old was invisible inline and waited for the 15-minute cron. Probe on
  staging: `now()` → delivered, `now() - 5 min` → **zero**. Now 20 minutes, which exceeds the
  poller's own interval. Flips ~13–16 Aug when instant deliveries are the majority of the window.
- **`explain-knowledge-used` is a THIRTEENTH clock-bound check the brief never listed.** The
  `sources` fix landed on 6 Aug: gate decisions are 100% cited since 7 Aug (29/29, 61/61, 70/70) and
  0% before. It flips ~13 Aug on its own. Every one of the 108 uncited rows is `kind='action_gate'`.
- **The unmatched-inquiry watchdog forgot after 24 hours — FIXED.** `resilience_watch` was the only
  agent erroring on production, 65 times, and stopped dead at 09-08 10:40. Nothing was fixed: the
  check read `between now()-24h and now()-6h`, a BAND, and the inquiries created 08-08 10:40 simply
  crossed the far edge. It also counted fixtures. Both corrected, in opposite directions.
- **THE SEVEN INQUIRIES ARE DEMO FIXTURES.** All 7 carry `brief_source='qd_demo_fixture'` and are
  seeded "ZZ DEMO" briefs. This document and the part-4 brief both treat them as real demand waiting
  on a buyer. **The company has had ZERO real inquiries, not seven**, and live matching has never
  been exercised — `match_eval`'s 100%/100% is a synthetic benchmark against its own seeded
  suppliers.
- **`agent_brain` is 93% of all AI spend, and its cost attribution does not survive scrutiny.** 381
  calls over 4 days, **AED 51.08 (~AED 383/month)**, 14,110 prompt tokens each. Daily AI cost went
  from ~AED 0.5 to ~AED 13 on 6 Aug when this started. **Every one of the 381 `ai_cost_log` rows
  carries `agent_key='ceo'`** — yet `agent_chats` over the same window shows `agent_brain` replying
  as knowledge_director (38), procurement (35), docs (27) and brief (25), dispatched by
  `internal@quotesdone.com`, i.e. `cos_execute`. Both cannot be true of the same calls.
  `agent_key` is not a hardcoded default — six distinct values appear across `ai_cost_log` in 7 days
  (ceo 408, ai_trainer 129, knowledge_curator 85, NULL 39, brief 23, onboarding 5) — and
  `_shared/llm` does forward `agent: def.agent ?? null`.

  **RESOLVED — it is a mis-attribution defect.** `cos_execute` never writes `agent_chats` (zero
  occurrences); `agent_brain` is the only function that writes a conversational one. So those
  department chats WERE `agent_brain` calls. And `agent_brain` passes `agent: key` in exactly two
  places — line 102 (`kb_usage_log`) and line 225 (`agent_runs`) — **neither of which is an LLM
  call**. Nothing hands the employee to the model layer, so `ai_cost_log` resolves it to the exec
  department head. **Every model call `agent_brain` makes on behalf of any of the 66 employees is
  billed to `ceo`.**

  Two things follow. Per-employee AI spend is not measured, it is a single bucket. And this
  document's "`ai_cost_log` — **3 of 66** have ever been billed for a model call" is an ARTEFACT of
  that bucket, not evidence of dormancy — so the dormancy case, which five per-employee universals
  rest on, is weaker than it reads here and must be re-argued from `agent_runs` and `agent_memory`
  instead.

  **FIXED AND DEPLOYED TO BOTH PROJECTS.** And it was NOT the one-line change it first looked like:
  `const llm = makeLlm(...)` sat at MODULE SCOPE, built at boot before any request, and `makeLlm`
  binds `def.agent` at CONSTRUCTION while the function it returns takes `(sys, input, max)` with no
  per-call override. There was no argument to pass the agent in. The constant became a factory —
  `const llmFor = (agent) => makeLlm(OPUS_FIRST, {..., agent})`, called as `llmFor(key)(...)`. Same
  models, ceiling, timeout and prompt; only the stamp changes.

  **Verified by execution, not by typecheck.** Staging's `agent_brain` was invoked as `account_mgr`
  — chosen precisely because it is not the exec head, so `ceo` could not be right by accident — and
  the resulting `ai_cost_log` row reads `agent_key='account_mgr'`, 14,332 prompt tokens, AED 0.1086.
  A second row, `agent_key` NULL at 317 tokens and AED 0.0003, is `llmFast`: left unattributed on
  purpose and noted in the code, because it is 0.3% of the bill and its callers take no key.
  Production is v29 as of 00:34:50; its first post-deploy call is pending the next hourly
  `cos_execute`. staging had zero prior `agent_brain` cost rows, so those two are clean evidence.
- Two other routines use a `between now()-x and now()-y` band (`fn_founder_brief` 60→30d,
  `fn_ceo_questions` 14→7d) and both are legitimate prior-period comparisons, not alerts. No active
  daily cron has failed to run in 30 hours.
- The genome block costs ~425 prompt tokens per `fn_agent_context` call, about **+4% of prompt
  tokens, ~AED 0.5/day**. Measured, not assumed.

---

## 1. THE SHAPE OF THE WHOLE ROW, IN ONE SENTENCE

Almost every one of the 124 gaps read:

```
ui: no rendered component names it  |  db: <real, live, populated data>
```

The company computes itself every night and showed the founder almost none of it. The fix was
never a database one. **Seven new or extended workspace routines and six new screens** carried
what already existed to a surface the founder opens.

### What was built

| routine | what it exposed that reached nothing before |
|---|---|
| `fn_ws_intelligence` | `opportunity` (9), `competitor` (27), `ai_cost_log` (1,094 calls / AED 85), `company_index` (39) |
| `fn_ws_exec_home` | health, revenue, goal attainment, active customers/suppliers, employees working, bottlenecks, per-department run counts |
| `fn_ws_agent_ops` | per-employee goal, tasks, decisions, confidence, workload, plans |
| `fn_ws_company_os` | the 10 operating systems, 324 graph nodes + 608 edges, the board, the indices, 12 replay days, 66 reputations, 32 proposals, 47 challenges, 269 lessons, 16 capabilities, 81 runbooks |
| `fn_os_search` | widened from 3 corpora to **9 of 9** |
| `fn_os_memory` | subject-and-period reader over decisions, rejections, changes and lessons — did not exist |
| `fn_ws_notifications` | the four tiers, and the share the AI cleared alone (98% of 1,186 over 30d) |
| `fn_founder_brief` | the four figures the overnight brief never carried |
| `fn_entity_activity` | a configuration object now has a change history (33 real events for `model_policy`) |
| `fn_ws_supplier_360` | rejection rationale from `decision_record` + policies from `decision_trace` |

Screens: Intelligence Centre · Executive Home (Overview + Console strip) · employee drawer ·
Operating System & map (six tabs) · Company Memory · notification tiers · voice in the console.

---

## 2. THE TRAP, AND HOW IT WAS HANDLED

The nine `intel-*` checks scan a component body for nine regexes and require **four co-located**.
A component that merely *names* all nine scores nine and shows four empty panels.

So the DB leg of each was measured in isolation **before a line of UI was written**, and the
result contradicted the brief: **seven of nine DB legs already passed, not four.** The brief read
"no data" for competitors, customer behaviour and AI spending; the truth was that their DB legs
passed and **no workspace payload carried them**. Same conclusion, different cause — and the cause
is what made three of them cheap.

The screen was then built in two stages and measured at each: **4/9, then 8/9.** The ninth was
left out on purpose.

**Every screen shipped this session had its key paths resolved against the live production payload
before it shipped.** 33, then 24, then 38, then 71 paths. Not one empty cell.

---

## 3. WHAT IS BLOCKED, AND BY WHAT

This is the part that matters most, because none of it is closable by writing code.

### The company has no customers

`public.customers` holds **0 rows**, and all 7 inquiries carry a **null `customer_id`** — checked
directly, so this is not a broken foreign key. It is a marketplace with 20,470 supplier leads and
no buyers registered yet.

That single fact blocks: `intel-customer-behavior` · `company-map-entities` (customer is one of
six required node classes) · one of `s22`'s nine chain classes · the churn and satisfaction inputs
of `s30-marketplace-eight-inputs`.

### The 66 employees barely execute

The org chart lists 66 active employees. The estate has almost no record of them working:

**RE-MEASURED 2026-08-10 03:45 UTC. Three of these five rows were wrong or are now stale — the
corrected figures are in the right-hand column, and the dormancy case rests on the middle three
rows, never on `ai_cost_log`.**

| source | as written 9 Aug | measured 10 Aug |
|---|---|---|
| `agent_runs` | **7 of 113** agent values match an `org_agents` key | **10 of 113.** Still the wrong table for employees — it is the CRON log; 103 of its 113 values are job names |
| `agent_memory` | 22 of 66 wrote a thought in 30 days | **22 of 66** — unchanged, and one of the three sources that actually evidences employee work |
| `ai_cost_log` | **3 of 66** have ever been billed for a model call | **AN ARTEFACT, NOT A FACT.** `agent_brain` never passed the employee to the model layer, so every call resolved to `ceo`. Fixed 10 Aug 00:34; **6 employees billed in 30d and 5 distinct in the first three hours after the fix alone** |
| exam results | 10 of 66 have any; **0 of 66 have two dated ones** | unchanged — still blocks `employee-learning-progress` |
| `kb_usage_log` | **0 rows** — nothing writes it | **17 rows.** `agent_brain` writes it now |

**The dormancy figure is 44 of 66, measured across all three real sources** (`agent_memory` 22,
`agent_chats` 19, `agent_runs` 10 — silent in all three). Not 57, and not the `ai_cost_log` 3.
`fn_evolution_scan` was proposing 57 for retirement every Monday until it was fixed on 9 Aug; the
10 Aug 06:00 run reports 44.

That blocks five per-employee universals: `employee-current-thoughts`, `-performance`,
`-performance-trend`, `-learning-progress`, `-knowledge-used`. **No UI change can close them**, and
`employee-learning-progress` deliberately has no key on the drawer — a learning panel with no curve
behind it is an empty panel.

### Three explanations have no source to draw from

`explain-confidence-score` reads 27 of 35: the eight escalations come from `decision_log` and **every
`action_gate` row has `confidence` NULL**. `explain-alternatives-considered` reads 0 of 35 because
`challenge_record`'s 31 recorded alternatives are challenges to *founder proposals* and join to none
of these actions. `explain-knowledge-used` needs `kb_usage_log`, which has 0 rows and no writer.

### The console is operationally overloaded

`strategic-not-operational` now names **4 of 4** strategic queues and still reads MISSING. Its last
leg asks that strategic work outnumber operational, and production is **115 strategic against 316**
pending-or-needs-review `agent_actions`. A true statement about the company, not the screen.

### Two are waiting on a clock, not a change

`companion-overnight-brief` and `voice-morning-brief-spoken` both read the newest **stored** brief.
`fn_founder_brief` was extended and verified on staging at **8 of 8 figures**, up from 4 — and
production's newest brief predates the change. The 04:30 cron regenerates it. Running it by hand
would have been a production write outside the promotion path, to turn a gate green a few hours
early.

---

## 4. THE ROW #3 / ROW #7 OVERLAP IS SETTLED

`docs/sessions/ROW3_ROW7_UI_OWNERSHIP.md`. The rule is mechanical: **a requirement belongs to
row #3 if and only if one of its 152 check IDs already scores it**, because the row with a working
measurement holds the ground.

Row #3 keeps all 152. Row #7's Part B3 loses 10 UI features to row #3 and 1 to rows #4/#5, taking
its proposed denominator from **231 to 220**.

---

## 5. WHAT THE NEXT SESSION SHOULD NOT REPEAT

- **The brief's own defect diagnosis was wrong again.** It said four intel items had data. Seven
  did. Measure the DB leg of every check in isolation before building; it takes minutes and it
  changed the plan.
- **A passing DB leg is not a populated panel.** Three items had passing DB legs and no payload
  carrying them. Both halves have to be measured separately or the screen ships empty.
- **Check what a figure means before rendering it.** A per-OS `staff` count read 0 for Leadership
  because only 4 of 72 `os_responsibility` rows name a department. It was corrected to
  `owned_departments` before shipping rather than after.
- **Adding a default parameter creates an overload, it does not replace a routine.** `fn_os_search`
  kept its signature for exactly this reason; the period-scoped reader became `fn_os_memory`.
- **Extend large plpgsql by reading the deployed definition back and injecting into it.** Three
  routines of 5.8k, 6.9k and 11k characters were changed this way, so the working code around each
  change is byte-identical to what was already running.
