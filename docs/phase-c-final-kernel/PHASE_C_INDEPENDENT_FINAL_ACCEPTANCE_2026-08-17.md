# Phase C — independent final acceptance, and Phase D test-harness readiness

Independent, read-only session. Nothing in the repository, the database, production configuration,
expected results, Phase A, Phase B or Phase C architecture was modified. This file is an untracked
audit artifact.

| | |
|---|---|
| commit audited | `d15a03a` (main) |
| project | `htdblwldjkcgjvmqkbeh` — the one project |
| window | 2026-08-17 19:46 → 20:49 UTC |
| zero-cost mode | `NO_PAID_AI=true OPENROUTER_DISABLED=true AI_PROVIDER_MODE=mock PHASE_D_EXTERNAL_EFFECT_MODE=mock` |
| management credential | present (`~/.supabase/access-token`) |
| OpenRouter / paid-provider requests | **0** — `llm_attempt` 0, `ai_usage` 0, `ai_cost_log` 0 rows, **AED 0.00 = USD 0.00** across the whole session including the full suite run |
| residue left on production | **0** — every write probe ran inside a transaction ending in `raise exception`; re-counted after |

## VERDICTS

### PHASE_C_FINAL_ACCEPTANCE_FAIL

### PHASE_D_TEST_HARNESS_NOT_READY

---

## What passed, measured independently

Re-run at HEAD with the credential present, not read from the builder's evidence.

| gate | measurement |
|---|---|
| Phase A drift | `fn_phase_a_baseline_drift()` → **0 rows** |
| Phase B drift | `fn_phase_b_baseline_drift()` → **0 rows**; `fn_phase_b_effective_errata()` → 3 rows, all `resolved=true` (EX-006, W13, W22) → effective drift 0 |
| Phase C runtime drift | `fn_phase_c_baseline_drift()` → **0**; `fn_phase_c_reporting_map_drift()` → **0** |
| component crosswalk | declarations **1801** = crosswalk **1801** = live **1801**; 23 columns compared per row; **0** incompatible cells; **0** duplicates; **0** missing in any direction |
| `dbfn:fn_kernel_signal_submit(jsonb)` / `dbfn:fn_kernel_trigger_submit(jsonb)` | both declared in `scripts/sql/rc4_execution_and_trace_are_atomic.sql`; crosswalk rows 739/740 carry type `database_function`, scope `SYSTEM_SCOPE` (justified, not a Phase B workflow), role `it_operations_engineer`, actor `system.command_router`, authority `routine_operational_decision`, trace policy `TRACE-SYSTEM-EXECUTION`, activation `active`, callers named, classification `ACTIVE_INTERNAL_CALLER`; all 23 columns match live |
| crosswalk credential contract | with the credential genuinely absent: `--require-live` → `NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL`, **exit 1** ✔; `--static` → static pass, exit 0, asserts nothing about production ✔ |
| routine source of truth (engine) | `canonical_routine_manifest.mjs --all` → 1013 canonical / 1013; conflicting 0, ambiguous 0, manifest gaps 0, repo→prod 0, prod→repo 0, uncommitted DDL 0, exit 0 |
| `canonical_routines.test.mjs` | genuinely thin: imports nothing but node built-ins, spawns the engine (`ENGINE` at :41), owns no parser / winner rule / DDL matcher / commit-time selection; forced counterexample refused |
| digit-bearing dollar tags | `$k34$`, `$k35$`, `$k13a$`, `$k3c$`, `$rc4b$`… parsed by `/\bas\s*(\$[A-Za-z0-9_]*\$)/i` (`canonical_routine_manifest.mjs:143`) |
| `fn_ws_operations` / `fn_ws_company` | both resolve to `scripts/sql/operations_company_remaining_lists.sql` (MANIFEST 1275); `source_sha256 == deployed_sha256` |
| founder chain | **30/30** checks; identification is by normalised columns (`run.command_id`, `workflow_run_id`, `correlation_id`, `causation_id`, `trace_id`); one canonical start event, one run, no self-emission, 0 unlinked derived objects, probe left nothing behind |
| command acceptance | **20/20**; every routed case created exactly **one** task — no pre-kernel fan-out; CC-014 ambiguous → 0 tasks; CC-017 refused → 0 tasks |
| CC-020 | frozen row: `W01`, workflows `W01;W21;W28`, primary role `strategy_director`. `W01-S01` owner = `chief_of_staff`; `W01-S02` owner = `strategy_director`. The one task created is owned by the first step's frozen owner. Chief of Staff is **asserted**, not exempted (`phase_c_command_acceptance.test.mjs:184-195`) |
| CC-011 / CC-019 | reconciled the same way and **not weakened** — the replacement assertion is strictly stronger: every task owner must be a first-step owner of a linked workflow (:176-181), which the previous version did not require |
| entry point | `phase_c_command_center_entry_point.test.mjs` → **54 ok, 0 FAIL**; calls `fn_founder_command_control` with **five** arguments (:186), matching the live signature `(bigint, text, text, text, text)`; reaches its assertions |
| negative guard suite | **55/55** refused; 31 refusals asserted on a SQLSTATE + guard pair; 0 prose-only; row counts unchanged |
| Phase B guard suite | **20/20** fired; steps 257 / handoffs 159 / exceptions 50 unchanged |
| Phase B invariants | **77/77** |
| founder authentication (6A) | no headers → **401**; anon key only → **401**; invalid bearer → **401**; valid non-founder → **403** on both a read-only and a founder-gated action; valid enabled founder → **200**. `build-mode@quotesdone.local` `active=false`; `fn_os_open_access()` = **false** |
| autonomous new work (6D) | real active adapter `dbtrigger:public.agent_actions:trg_page_high_agent_action` → 1 run (W29), **1** first ready task (W29-S01, `it_operations_engineer`), traced; founder commands created **0**; chief_of_staff tasks **0**; duplicate emit → `duplicate=true`, `{run:0,task:0,event:0,step_run:0,inbox_row:0}` |
| existing-workflow signal (6E) | 6 active signal types: 6/6 valid accepted, 6/6 invalid refused, 6/6 missing-workflow refused, 0 duplicate work, no second workflow |
| workflow closure (6F) | drove W14 S01→S08: **W14-S05 owner = `quote_evaluation`** ✔; blocked at W14-S08 by `23514 … names rfq_success as its independent reviewer and no approved, independent verdict` — mandatory blocker enforced ✔; run state stayed `active`, **no false terminal step** ✔; overlay-owned tasks **0**, untraced tasks **0**. W20 driven the same way (cross-owner, 9 steps, blocked at S09 by the same reviewer gate) |
| cancellation (6C) | `cancellation_reaches_the_kernel` 11/11 counters; replay produces 0 additional effect; `queued_work_derived_from_cancelled_commands` **0 of 44**; clarification UI calls `founderCommandClarify` (`src/components/osx/OsxShell.tsx:1449`) |
| legacy retirement (6H) | `fn_kernel_retired_path_state()` all ok — old cron 0, bypass grants 0 of 8, active callers of disabled paths 0 of 2, primitives called from outside the kernel 0 of 3; `fn_kernel_retired_grant_state()` all ok |
| trace integrity (6J) | `fn_phase_c_trace_coverage()` — missing **0** on all seven subjects; the 5 excluded open step runs are labelled with a stated reason. `fn_kernel_trace_integrity()` terminal-with-open-trace 0 on all five kinds |
| zero-cost window (7) | scheduled `ai_health` run observed live at **19:52:00 UTC** in this window: `skipped_due_to_zero_cost_mode: 8/8 routes held until 2126-08-15`; `llm_attempt` 0, `ai_usage` 0, `ai_cost_log` 0, AED 0.00. `fn_os_paid_ai_allowed()` = **false**; it denies on an empty route table by construction (`and exists (select 1 from public.llm_route_health)`). Cron 102 now runs `fn_kernel_cron_exec(102)` and makes **no** outbound OpenRouter request, metadata included |

---

## PHASE C — BLOCKING FINDINGS

### C1 — `fn_phase_c_outbox_emit` writes the kernel's event outbox from outside the kernel, untraced

**Gate:** §5B (no active door lacks a positive control), §6G (direct writes outside kernel accepted = 0), §6J (state-changing execution without trace = 0)
**Routine:** `public.fn_phase_c_outbox_emit(text, text, jsonb, text)`

Measured in an aborted transaction, as `service_role`:

```
{"door":"fn_phase_c_outbox_emit(UNREGISTERED)","result":"ACCEPTED"}
new_outbox: [{"id":2049,"status":"pending","producer":"audit-probe-2","trace_id":null}]
outbox_delta: 1
```

The row is `status='pending'` with `next_attempt_at` defaulting to `now()`, and
`fn_phase_c_outbox_claim` claims exactly `where status in ('pending','retry_wait') and
next_attempt_at <= now()`. So the next delivery sweep would deliver it. `trace_id` is null;
`fn_kernel_outbox_emit` writes a trace, this primitive does not.

The asymmetry that allows it — same probe, same role, same transaction:

| routine | in `kernel_retired_path`? | `service_role` EXECUTE | result |
|---|---|---|---|
| `fn_phase_c_workflow_start` | yes, `KERNEL_INTERNAL_PRIMITIVE` | **false** | REFUSED `42501` |
| `fn_phase_c_task_create` | yes, `KERNEL_INTERNAL_PRIMITIVE` | **false** | REFUSED `42501` |
| `fn_phase_c_outbox_emit` | **no** | **true** | **ACCEPTED, wrote a row** |
| `fn_phase_c_task_transition` | **no** | **true** | ACCEPTED |
| `fn_phase_c_handoff_open` | **no** | **true** | ACCEPTED |
| `fn_phase_c_handoff_decide` | **no** | **true** | ACCEPTED |

`kernel_write_authority.why` calls all four "kernel-internal primitive" / "the task state machine",
but none of them calls `fn_kernel_assert_in_kernel`, none is registered in `kernel_retired_path`,
and all four still hold `EXECUTE` for `service_role` — the role every edge function runs as.

**Smallest responsible issue:** `fn_phase_c_outbox_emit`, `fn_phase_c_task_transition`,
`fn_phase_c_handoff_open` and `fn_phase_c_handoff_decide` have the disposition of a kernel-internal
primitive recorded in prose but neither of the two mechanisms that enforce it — the `REVOKE` and the
`kernel_retired_path` row — that `fn_phase_c_workflow_start` and `fn_phase_c_task_create` have.

### C2 — `TRUNCATE` bypasses the kernel write guard on every protected table

**Gate:** §6G (direct writes outside kernel accepted = 0)
**Routine:** `public.fn_kernel_write_guard()` — a row-level trigger

Measured in an aborted transaction, as `service_role`:

```
AUDIT_RESULT TRUNCATE ACCEPTED — rows went 7 -> 0
```

(`public.phase_c_handoff_run`; rolled back, re-counted at 7.)

`service_role` holds `TRUNCATE` on all seven protected tables — `phase_c_workflow_run`,
`phase_c_workflow_step_run`, `phase_c_task`, `phase_c_handoff_run`, `phase_c_event_outbox`,
`phase_c_trace`, `founder_command`. A row-level `BEFORE INSERT/UPDATE/DELETE` trigger does not fire
on `TRUNCATE`, so the guard never runs and no trace is written.

`kernel_write_guard_both_directions.test.mjs` passes 7 cases; none of them is a `TRUNCATE`.

**Smallest responsible issue:** the guard is enforced by a row trigger and by grants, and the grant
list omits `TRUNCATE`.

### C3 — the positive-control denominator is filtered by a name prefix, not by disposition

**Gate:** §5B
**Test:** `scripts/checks/kernel_positive_controls.test.mjs:284-289`

```sql
where (a.routine_name like 'fn\_kernel\_%' or a.routine_name like 'fn\_founder\_command\_%')
  and not exists (select 1 from public.kernel_retired_path p where p.path_name = a.routine_name)
```

`kernel_write_authority` holds **23** distinct routines. Retirement removes 4. The name prefix
removes a further **6** — the four in C1 plus the trigger helpers
`fn_phase_c_step_run_trace_subject` and `fn_phase_c_task_trace_subject` — leaving 13.

The brief's rule is "active kernel write authorities **minus retired paths**". The implemented rule
is "…minus retired paths **minus everything not named `fn_kernel_*` or `fn_founder_command_*`**".
Six active authorised write routines therefore have no positive control, and the suite still prints
`13 door(s), 13 accepted`. C1 shows one of the six is reachable and writes.

`fn_kernel_retired_path_state()` cannot see them either: its `paths_with_no_recorded_disposition`
reads **0 of 0**, because its denominator is `kernel_retired_path` itself.

### C4 — a second committed source-of-truth authority, and it is red

**Gate:** §2 (one authoritative routine source of truth)
**Test:** `scripts/checks/application_source_of_truth.test.mjs`

Run at HEAD with the credential present:

```
  1. in repository, missing from production          0 / 607
  2. on production, missing from repository          0 / 1012
  3. conflicting current definitions                 0 / 148
  4. drifted application routines                    0 / 608
  5. uncommitted application DDL                    15 / 7439
  6. ledger claims the repository denies            90 / 1225
  countable findings                               105          -> exit 1
```

The engine reports `uncommitted_ddl: 0` for the same production at the same commit. This file is not
a thin test over the engine: it declares its own rule at :14 — *"THE ONE RULE THAT DECIDES CANON:
position in `scripts/sql/MANIFEST.txt`"* — takes its own winner at :209 (`list[list.length - 1]`),
and uses its own DDL matcher (`_ddl_from_sql.mjs`), which the engine does not import.

The 17 Aug correction rewrote `canonical_routines.test.mjs` into a thin test so there would be one
authority. `application_source_of_truth.test.mjs` was left with its own, and it is the one that is
red. Two committed checks claiming to be the source of truth is not a source of truth — the closure's
own words.

It is invisible because it exits 0 with no token (`:36-41`), and `checks.yml` supplies none.

### C5 — the closure generator renders a credential-blocked headline as PASS

**Gate:** §9 (no credential-blocked check represented as pass)
**File:** `scripts/phase_c/regenerate_builder_closure.mjs:122-131`, `:137-142`, `:148-152`, `:269-270`

Classification is `parsed.measurement === 'credential_blocked' ? NOT_VERIFIED… : status===0 ? 'PASS'`.
Two parsers detect the skip (`/SKIP phase_c_invariants/`, `/PRODUCTION COMPARISON SKIPPED/`). The
three COMMAND CENTER parsers **hardcode `measurement: 'production'`** and detect nothing.

Reproduced: with the credential genuinely absent, all three checks print `SKIP …` and exit 0. Feeding
that real output through the generator's own parse and classification:

```
{"headline":"the founder chain, end to end…","numerator":"0 checks passed","denominator":"0 checks","measurement":"production","exit_code":0,"result":"PASS"}
{"headline":"the Command Center entry point…","numerator":"undefined failed","denominator":"0 checks","measurement":"production","exit_code":0,"result":"PASS"}
{"headline":"command routing acceptance cases","numerator":"unparsed","denominator":"unparsed","measurement":"production","exit_code":0,"result":"PASS"}
```

`headlines CREDENTIAL_BLOCKED` would read **0**. `0 checks passed / 0 checks` is an empty population
scoring as satisfied — the document's stated purpose is to make that impossible.

Secondary, same file: `:139` `(out.match(/(d+) check(s) failed/) || ['?'])[1]` — `d+` not `\d+`, so
the failure branch can never match and renders `undefined failed`.

### C6 — the committed schema mirror is not what production runs, and the check that says so is exempt on pull requests

**Gate:** preflight ("production contains the same application definitions as main"), §2
**File:** `.github/workflows/project-parity.yml:78`, `supabase/schema/full_schema.sql`

`repo and database agree` is **failing on main right now** — runs 32060073748 (19:23), 32058828286
(19:09), 32048382089 (17:00), all `push` to `main`. The failing step:

```
live export     : 66048 lines, 3534935 chars
supabase/schema/full_schema.sql: 64150 lines, 3427493 chars
identical       : NO
differing lines : 65362
first at line   : 114
   database: "CREATE SEQUENCE IF NOT EXISTS public.kernel_adapter_failure_failure_id_seq;"
   git     : "CREATE SEQUENCE IF NOT EXISTS public.kernel_trigger_inbox_inbox_id_seq;"
```

`grep -c kernel_adapter_failure supabase/schema/full_schema.sql` → **0**. The mirror does not carry
the kernel adapter-failure objects at all.

Every Phase C correction PR merged green because the step carries
`if: ${{ github.event_name != 'pull_request' }}`. It runs only after merge, where nothing gates on it.

Routine **bodies** are not drifted — the engine's repo→prod and prod→repo are both 0, and the
crosswalk matches. What is stale is the whole-schema mirror the ledger cites as `source_file`.

---

## PHASE C — MATERIAL, NOT COUNTED AS THE FAILURE

**M1 — seven Phase C checks pass silently in CI.** `kernel_invariants`, `kernel_positive_controls`,
`phase_c_command_acceptance`, `phase_c_command_center_entry_point`, `phase_c_founder_chain`,
`phase_c_guards_reject_injected_defects`, `phase_c_invariants` all `console.log('SKIP …'); process.exit(0)`
without a management token, and `.github/workflows/checks.yml` has no `env:` block at all. The whole
Phase C gate is green in CI without running. (`project-parity.yml` does pass the secret to the
crosswalk and the routine engine, so those two are genuinely gated on PRs.)

**M2 — refunds auto-approve inside the promised window.** `fn_refund_request` writes
`status = 'approved'` when `refund_deadline >= now()` and the amount is under the
`customer_success / refund_within_window` threshold, live at **AED 2,000** — no founder decision. The
code states this as deliberate policy. It has never fired: `refunds` 0 rows,
`founder_approval_request` 0 rows, `phase_c_refund_decision` 0 rows. Whether this is a defect is a
commercial question about the founder's intent, not a technical one, so it is reported and not judged.

**Observation — `fn_kernel_trace_integrity()` carries five red rows by design**, disclosed in
`scripts/sql/kernel_k6_trace_ledger.sql:80-106`: 7 preserved pre-kernel orphan traces, 1 unmapped
subject kind, 589 components that have never executed, and 5 traces (workflow runs 91/92/93/96,
handoff 48, all 16 Aug) whose `state_after` was left at `queued`/`open` when the subject reached a
terminal state. None of these is one of the nine conditions §6J requires to be zero, and the handoff
one is fully labelled as a non-contemporaneous S2 retrofit. The three workflow-run traces are not
labelled.

---

## PHASE D TEST-HARNESS READINESS

### D1 — the nested untracked repository copy contaminates the runner (BLOCKING)

`scripts/checks/run.mjs:54` — `SKIP_DIRS` is
`{.git, node_modules, .next, dist, build, out, .vercel, coverage, .turbo, vendor}`. `$WT/` is not in
it, and `discover()` walks from the repo root. Measured by importing `discover()`:

```
node tests discovered TOTAL: 96
  from $WT/: 39
  from repo: 57
deno tests TOTAL: 2   from $WT/: 1
```

`$WT/` is 159 MB, dated 14 Aug 2026, untracked, with its own `.git` pointer.

The concrete hazard, not a hypothetical:

- `$WT/scripts/checks/v3_runtime_behaviour.test.mjs:26` —
  `const PROJECTS = { production: 'htdblwldjkcgjvmqkbeh', staging: 'pglpqrhvozwepymcuunn' };`
  a live reference to the project **deleted on 15 Aug 2026**.
- `$WT/scripts/checks/sql_files_match_live.test.mjs` — the version retired in the live tree
  (`sql_files_match_live.RETIRED.mjs`), restored to the runner's view.
- `$WT/.claude/skills/quotesdone-session/SKILL.md` is already being surfaced as a directory-scoped
  skill whose text instructs deploying to **both** Supabase projects — an instruction revoked when
  staging was deleted.

`npm test` as written could not be run inside this audit's zero-cost rule for that reason. The suite
was therefore run under a controlled configuration with `$WT/` excluded — identical discovery,
identical spawn. **Not deleted, per instruction.**

### D2 — management-API throttling manufactures product failures (BLOCKING)

10 of the 19 failures in the controlled run are
`AssertionError: query failed on htdblwldjkcgjvmqkbeh: 429 {"message":"ThrottlerException: Too Many Requests"}`,
several after ~48–50 s of retry-free waiting. `run.mjs` spawns one `node --test` process which runs
files concurrently; the per-check `q()` helpers (e.g. `org_reorg_behaviour.test.mjs:44`,
`workflow_ownership_alignment.test.mjs:40`, `a_phone_cannot_select_an_account.test.mjs:50-60`) have
no concurrency limiter, no backoff and no retry on 429. The failing set is therefore
non-deterministic — a different run throttles a different ten.

### D3 — unresolved failures that are not outside Phase C

C4 (`application_source_of_truth.test.mjs`, exit 1) is in the suite and is a Phase C source-of-truth
failure, not a later-phase one. C6 leaves `repo and database agree` red on main.

### Full-suite arithmetic (controlled configuration, `$WT/` excluded)

```
node:  tests 287   pass 268   fail 19   skipped 0   cancelled 0   todo 0
deno:  16 passed   0 failed
```

268 + 19 = 287. Disjoint primary causes, one per failing test:

| primary cause | count | tests |
|---|---:|---|
| MANAGEMENT_API_RATE_LIMIT | **10** | `a_phone_cannot_select_an_account` ×3; `org_reorg_behaviour` ×2 (stop authority, authority block); `v3_runtime_behaviour` ×2 (agent context, question banks); `workflow_ownership_alignment` ×3 (zero workflow callers, four broad specialists, workflow 11) |
| ROW3_BACKLOG | **3** | `org_reorg_behaviour` fn_org_role_violations is empty; `org_reorg_behaviour` canonical organisation shape holds; `workflow_ownership_alignment` every active role has tools… — all three are the same row: `no_kpi/no_knowledge/no_authority/no_tools: product_ux_designer` |
| PRODUCT_DEFECT | **3** | `agent_action_fields_are_filled_after_the_gate` (alternatives not read from the decision_log row the gate wrote); `v3_runtime_behaviour` decision trace `traces=1 ids=<NULL>`; `v3_runtime_behaviour` author-is-not-reviewer trigger must refuse rather than the assertion below it |
| PHASE_C_RUNTIME | **1** | `application_source_of_truth` — finding C4 |
| KNOWLEDGE_PHASE | **1** | `v3_runtime_behaviour` every packaged department resolves — "the delivery names 24 departments" against the 10 live departments |
| OTHER_WITH_EXPLANATION | **1** | `every_executor_kind_has_a_runner` — "fn_action_invoke_rpc has no active cron entry, so rpc executors only run when somebody calls them by hand". An executor-scheduling gap, not a Phase C kernel gate |
| DELETED_STAGING_REFERENCE | **0** | zero in the controlled run; non-zero in the uncontrolled command — see D1 |
| PHASE_A_OR_B_REGRESSION | **0** | Phase A and Phase B drift are both 0 rows; Phase B invariants 77/77; Phase B guards 20/20 |
| TEST_SETUP_DEFECT | **0** | |
| **total** | **19** | |

### The four the brief asks about

- **`a_phone_cannot_select_an_account`** — 3 failures, all 429. Not a product defect in this run. Not
  relevant to Phase C acceptance; relevant to Phase D only through D2.
- **`every_executor_kind_has_a_runner`** — `fn_action_invoke_rpc` has no active cron entry. A real
  gap, owned by the executor/Phase D handler work, not by Phase C acceptance. It cannot block Phase D
  deterministic handler work — it *is* that work.
- **`org_reorg_behaviour`** — 2 of 4 are 429; the other 2 are `product_ux_designer` missing tools,
  knowledge, authority and KPI. Role *content* is explicitly not frozen by the Phase A approval and is
  deferred later-phase work. Not Phase C, not Phase D-blocking.
- **knowledge-pack checks** — `scripts/kb/pack_scorecard.mjs` is not a `*.test.mjs` and is not in the
  suite. The nearest in-suite check is `v3_runtime_behaviour` "every packaged department resolves to a
  live runtime department", failing because the packaged delivery names 24 departments against 10 live
  ones. Knowledge-phase work; not Phase C, not Phase D-blocking.

### Readiness criteria

| # | requirement | state |
|---|---|---|
| 1 | no test uses the deleted staging project | **FAIL** — `$WT/scripts/checks/v3_runtime_behaviour.test.mjs:26` |
| 2 | management-API concurrency bounded | **FAIL** — 10 false failures from 429, no limiter, no backoff |
| 3 | no nested untracked repository copy | **FAIL** — `$WT/`, 39 node + 1 deno tests discovered |
| 4 | Phase C-specific tests all green | **FAIL** — `application_source_of_truth` exit 1 |
| 5 | Phase A/B frozen tests green | PASS |
| 6 | every remaining failure has a later-phase owner | PARTIAL — true for 8 of 19; not for C4 |
| 7 | failure counts disjoint and reconciling | PASS — 268 + 19 = 287 |

---

## Not run, by instruction

V3 certification, knowledge-agent certification, paid model tests and live provider effects were not
initiated. `v3_runtime_behaviour.test.mjs` executed as part of the repository suite; it made no paid
call — the hold held, and `llm_attempt`, `ai_usage` and `ai_cost_log` all recorded zero rows for the
entire window.

Phase D was not begun. No finding above was repaired.

---

# ADDENDUM — the six findings, repaired and re-measured

Added after the founder asked for the repair rather than the report. The verdicts above are left
exactly as the audit found them; this section records what changed and what it measures now.
Branch `fix/phase-c-independent-acceptance-six`, PR #434.

| # | fix | measured before | measured after |
|---|---|---|---|
| C1 | `kernel_s4…sql` — the six write authorities get a `kernel_retired_path` row and lose `EXECUTE` for every ordinary role | `fn_phase_c_outbox_emit` as `service_role`: **ACCEPTED**, wrote `status='pending'`, `trace_id=NULL` | **REFUSED `42501`**, outbox delta **0**; the other three likewise |
| C2 | same file — `REVOKE TRUNCATE` on all 7 protected tables **and** `fn_kernel_truncate_guard()` on a `BEFORE TRUNCATE … FOR EACH STATEMENT` trigger | `truncate public.phase_c_handoff_run` → **7 → 0 rows** | **REFUSED `42501`** as `service_role`; **REFUSED by the trigger** as the table **owner** with no `kernel.maintenance_reason` — so the guard fires, not merely the grant |
| C3 | `kernel_positive_controls.test.mjs` — the name-prefix term is gone; the denominator is `kernel_write_authority` minus `kernel_retired_path` | 6 active authorities silently dropped, incl. the door in C1; printed `13 door(s), 13 accepted` | **13 doors, 13 accepted, 0 failed** — same number, now because the register says so |
| C4 | `_ddl_from_sql.mjs` parser gaps closed; `kernel_s0c…sql` **generated** from the check's own derivation; new line 7 asserts the two authorities agree | engine **0** vs `application_source_of_truth` **105** (15 DDL + 90 ledger) | **0 across all seven lines, exit 0**; line 7 **forced** to fire → 1 finding, exit 1 |
| C5 | `regenerate_builder_closure.mjs` — skip detection moved into the runner loop; `(d+)` → `(\d+)` | credential absent → `0 checks passed \| 0 checks \| production \| **PASS**`, `CREDENTIAL_BLOCKED: 0` | credential absent → **9 CREDENTIAL_BLOCKED, 0 FAILED**, numerator reads *"NOT VERIFIED — the production half did not run"* |
| C6 | schema mirror refreshed; the `if: github.event_name != 'pull_request'` exemption removed | red on `main` for 3 pushes; mirror 1,898 lines behind, missing `kernel_adapter_failure` entirely | `identical: YES`, and the step now blocks a merge |
| M1 | new `phase-c` job in `project-parity.yml` runs the eleven credential-needing checks serially, and treats a `SKIP` there as a failure | seven Phase C checks printed `SKIP` and exited 0 on every PR | they run against production on every pull request |
| D1 | `run.mjs` refuses to walk any directory carrying its own `.git`, and names what it skipped | `npm test` discovered **96** node tests, **39** from `$WT/` | **57** node tests, **0** from `$WT/`, `$WT` reported by name |
| D2 | `run.mjs` runs `node --test --test-concurrency=1` | 10 of 19 failures were `429 ThrottlerException`, a different 10 each run | serialised against the shared management API |

Regenerated closure evidence at this commit, credential present: **15 headlines, 0 FAILED,
0 CREDENTIAL_BLOCKED**; routine count now **1014** (S4 adds `fn_kernel_truncate_guard`), crosswalk
**1801/1801/1801**.

## The nested copy is gone, and nothing was lost removing it

`$WT/` was not loose files. `git worktree list` showed it as a **registered worktree of this
repository**, on branch `role-model-map` at 92bf73f, with a **clean working tree** — zero
uncommitted changes, so every byte in it was already reachable from this repo. `git worktree remove`
therefore destroyed nothing: `git rev-parse role-model-map` still answers
`92bf73fedc7dcf260236876e2dc37875c25adf87`.

Measured after: discovery returns **57 node tests, 1 deno test, empty skip list**. And no test file
anywhere carries a live reference to the deleted staging project — the single remaining mention, at
`scripts/checks/artifact_review_alias_cannot_self_approve.test.mjs:32`, is a comment sitting above
`const PROJECTS = { production: 'htdblwldjkcgjvmqkbeh' }`.

## Deliberately not changed

**The five trace/subject disagreements are historical, and the mechanism is correct now.** Driven in
an aborted transaction: a workflow run started and then cancelled through `fn_kernel_cancel` moves
its trace `active → cancelled`, agreeing with the subject. Runs 91/92/93/96 and handoff 48 are all
16 Aug rows from before that path was fixed. Handoff 48 carries a full S2 retrofit label; the four
workflow-run traces do not, and labelling them means opening `z10_phase_c_trace_append_only` under
the K1 protocol. Recorded here rather than done at the end of a long session. None of these is one
of the nine conditions §6J requires to be zero.

**Refund auto-approval is unchanged.** `fn_refund_request` writes `status='approved'` when the
refund is inside the window the customer was promised at reveal and under the
`customer_success / refund_within_window` threshold, live at **AED 2,000** — with no founder
decision. The code states this as deliberate policy and it has never fired (`refunds` 0 rows). That
is a commercial question about intent, not a technical one, so it is named and left.
