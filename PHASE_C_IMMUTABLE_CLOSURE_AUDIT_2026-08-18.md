# Phase C immutable closure audit — 18 Aug 2026

Independent, read-only. Nothing was modified: no repository file, test, database definition,
production configuration, expected result, Phase A/B/C artefact, or test-profile ownership. No
finding was repaired. Phase D was not begun. Every write probe ran inside a transaction ending in
`raise exception`, and every count was re-measured afterwards to prove the rollback.

| | |
|---|---|
| branch | `main` |
| commit | `f0f7339d0c39d6dea918d1d24da81f8ff7e09f14` — the merge commit of PR #444 |
| PR #444 | **MERGED** 2026-08-18T11:00:26Z |
| project | `htdblwldjkcgjvmqkbeh` |
| audit window | 2026-08-18 11:15 → 11:40 UTC |
| working tree | clean; untracked audit artifacts only |

## VERDICTS

**PHASE_C_FINAL_ACCEPTANCE_PASS**

**PHASE_D_TEST_HARNESS_READY**

---

## 1. PREFLIGHT AND DEPLOYMENT PARITY

| item | measured |
|---|---|
| branch = main · HEAD = origin/main | yes · `f0f7339`, 0 ahead / 0 behind |
| PR #444 merged, HEAD is its merge commit | yes |
| Phase A drift · Phase B drift | **0 · 0** |
| declarations / crosswalk / live components | **1801 / 1801 / 1801** |
| routine source of truth, both directions | repo→prod **0**, prod→repo **0**, conflicts **0**, ambiguous **0**, uncommitted DDL **0**, manifest gaps **0** |
| edge function parity | **202 functions** carry the repo's current code, exit 0 |
| full schema snapshot vs production | **identical: YES** — 66,490 lines / 3,563,876 chars both sides; 0 project refs embedded |
| paid-AI routes held | **8/8**, `fn_os_paid_ai_allowed()` = false |
| nested/duplicate repository tree | none — `nestedReposSkipped()` = `[]`; `vendor/` is third-party reference material excluded by `SKIP_DIRS` by design |

Parity was **not** accepted on the strength of a regenerated snapshot: the canonical routine manifest
and the committed migrations were verified independently, and `application_source_of_truth`
separately asserts agreement with that engine (`0 / 618`, "the engine owns this subject").

### Disclosure — PR #444 carried a commit outside its stated scope

`354348f` ("The predicate follows the map: 19 to 9, by measurement") has parent `e753505` and was
committed to **local `main`** at 09:25 UTC *during the previous session's read-only audit*, then swept
into the PR when the fix branch was cut from local `main`. PR #444's description does not mention it.

Verified benign, and verified in the safe direction:

- it **tightened** a ratchet — `active_autonomous_source_not_yet_routing_through_the_inbox`
  `max_numerator` **19 → 9**. A lowered ratchet is debt reduction, never a weakened check.
- the two SQL files it adds are registered in `MANIFEST.txt`, applied to production, and carry
  0 drift in both directions.
- it is also the true origin of the `MANIFEST.txt` debris (three lines of hook output and the quoted
  duplicate), which the previous session attributed to "an earlier session".

This is a **process** finding about how the change reached `main`, not a Phase C runtime defect. It
also corrects the previous session's claim that its tree was "byte-identical to `e753505`" — local
`main` carried this extra commit at the time, which that session did not re-check.

---

## 2. PR #444 — TRUNCATE PROTECTION, INDEPENDENTLY REPRODUCED

Population derived directly from `pg_trigger` / `pg_class` / `pg_proc`, not from the builder's list:
a table is in scope when it carries a **row-level** (`tgtype & 32 = 0`), non-internal trigger whose
function body raises.

| measure | required | measured |
|---|---|---|
| catalogue-derived enforcing-table population | = builder claim | **75** (claim 75) |
| enforcing tables missing a TRUNCATE guard | 0 | **0** |
| enforcing tables granting TRUNCATE (`service_role`, `authenticated`, `anon`, `public`) | 0 | **0** |
| duplicate / conflicting statement guards | 0 | **0** |
| statement guard using a function other than `fn_kernel_truncate_guard` | 0 | **0** |
| guard attached to an unrelated (non-enforcing) table | 0 | **0** |

### The complete loop — all 75, not a sample

One aborted transaction, `TRUNCATE ... CASCADE` as `service_role` against **every** table in the
derived population:

```
attempted=75   refused=75   accepted=0
rows_before=46628   rows_after=46628   non-42501 refusals=[none]   accepted=[none]
```

Every refusal carried SQLSTATE **42501**. Persistent row counts unchanged.

### The audited maintenance path

| case | result |
|---|---|
| unauthorised caller (`service_role`) setting the reason itself | **REFUSED 42501** — cannot enable it |
| table owner **without** a stated reason | **REFUSED 42501** — privilege alone is not enough |
| table owner **with** a stated reason | **ACCEPTED**, and recorded — `kernel_maintenance_write` 0 → 1 |
| a different table after the reason is cleared | **REFUSED 42501** — scope limited, protection restored |

All aborted; `kernel_maintenance_write` back to 0, `phase_c_historical_repair` 71,
`security_audit_log` 2,882.

### Future-table coverage — canary

In one aborted transaction a new table was created with the same enforcing row-guard pattern a
future migration would introduce:

```
population        75 -> 76      the catalogue-derived checker detected it automatically
unguarded          1
gate ok            false        the gate FAILS while the new table lacks protection
canary truncatable true         and the unguarded table really was truncatable
```

`fn_kernel_truncate_protection_state()` is discovered by `fn_kernel_all_boards()` on signature and is
**not** in `kernel-boards.json`, so it is a gate rather than a ratchet: a new enforcing table cannot
pass CI while lacking TRUNCATE protection. Canary table, function and trigger left nothing behind.

---

## 3. PHASE C RUNTIME REGRESSION

Re-measured, not taken from a headline.

| path | measured |
|---|---|
| **A** founder authentication | no headers **401** · anon apikey only **401** · anon as bearer **401** · invalid bearer **401** · malformed bearer **401**; body is a structured refusal. Build-mode identity `build-mode@quotesdone.local` is **active = false** |
| **B** one command, one effect | duplicate workflow start **0** (1 run) · event self-emission **0 of 33** · unlinked derived objects **0** · a duplicate command returns the **same** command (`tasks=1`) · duplicate outbox emit returns the same row |
| **C** clarification and cancellation | beneath a cancelled command: open tasks **0** · active step runs **0** · active workflow runs **0** · pending handoffs **0** · pending outbox rows **0** |
| **D/E** autonomous source and signals | `active_signal_types_are_executable` **6 accepted / 6** |
| **F** workflow progression | `fn_kernel_review_decide` accepted at **W14-S08**, reviewer `rfq_success`; overlay has no standing executor and cannot own work; overlays granted dispatch/payment/reveal/release **0**; overlay accountable outside scope **0**; 86 overlays governed |
| **G** kernel-only writes | verified in §2 and by the write-guard suite (7 cases) |
| **H** legacy retirement | `fn_phase_c_step_advance` refuses (retired); no committed document names a retired path a door; 13 canonical doors derived |
| **I** refund-only founder approval | refund decisions **0**, non-refund founder approval records **0**; ledger is append-only and now TRUNCATE-proof |
| **J** trace integrity | active commands/runs/step runs/tasks/handoffs without trace **0/0/0/0/0**; sealed traces without `sealed_at` **0**; system executions without trace **0** |

**Boundary stated:** two §3A cases were **not executed** — "valid non-founder bearer → 403" and
"valid enabled founder bearer → success". Both require minting real authentication sessions against
production, which this read-only mandate does not permit. The non-founder branch was verified by
source (`supabase/functions/os_api/index.ts:186`, `if (!(await isAdmin(email))) return J({ error:
'forbidden' }, 403);`, with the comment at :180 "somebody who is not an admin is 403. There is no
fourth branch."), and the founder path is exercised at SQL level by the Command Center entry-point
test (54 checks, passing).

### Every red board row is a recorded ratchet at or below baseline

`fn_kernel_all_boards()` returns 7 red checks across 22 boards. All 7 are ratcheted, none exceeds its
baseline, and **0 red checks lack a ratchet entry**:

| check | live | baseline |
|---|---|---|
| `orphan_traces_task` | 7 | 7 |
| `trace_state_disagrees_with_subject_workflow_run` | 4 | 4 |
| `trace_state_disagrees_with_subject_handoff_run` | 1 | 1 |
| `traces_with_unmapped_subject_kind` | 1 | 1 |
| `system_execution_components_with_no_trace` | 589 | 589 |
| `active_sources_bypassing_the_kernel` | 1 | 1 |
| `active_autonomous_source_not_yet_routing_through_the_inbox` | 9 | 9 |

---

## 4. GUARD SUITES

| suite | measured |
|---|---|
| negative injected defects | **58 cases, 58 refused, 0 accepted** · refusals on a SQLSTATE + guard pair **34** · prose-only assertions **0** · all monitored row counts unchanged |
| genuine positive controls | **13 doors, 13 accepted, 0 failed** · row counts unchanged after every aborted control |

Denominator re-derived independently from the live registry: `kernel_write_authority` holds **23**
distinct routines, **10** appear in `kernel_retired_path`, **23 − 10 = 13**. The selection is
`where not exists (... kernel_retired_path ...)` with **no name-prefix filter**. Active authorised
door without a positive control: **0**. Retired door counted as active: **0**.

---

## 5. ROUTINE MANIFEST AND MANIFEST.TXT

Engine: 0 conflicts, 0 ambiguous winners, 0 gaps, 0 drift either direction, 0 uncommitted DDL,
digit-bearing dollar tags (`$k34$`) parsed on both bodies, and the same engine runs on pull requests.

### The quoted, CR-terminated duplicate — **not a Phase C failure**

It is at **line 1420**, not 1421. Measured against the real parser
(`canonical_routine_manifest.mjs:75-79`):

```
line 1419: recognised=YES  "scripts/sql/the_write_map_in_the_database.sql"
line 1420: recognised=NO   "'scripts/sql/the_write_map_in_the_database.sql'  "
line 1421: recognised=YES  "scripts/sql/the_predicate_follows_the_map.sql"
line 1422: recognised=YES  "scripts/sql/the_truncate_protection_was_a_typed_list.sql"

recognised manifest entries: 734      DUPLICATE logical entries: 0
```

- **Duplicate logical entry?** No. `split(/\r?\n/)` removes the CR and `.trim()` removes the trailing
  spaces, but the leading apostrophe survives, so `p.startsWith('scripts/sql/')` is **false** and the
  line produces no map entry at all.
- **Quoting/CR normalised or preserved?** The CR and trailing spaces are normalised away by the
  parser; the quotes are **preserved**, and that is precisely why the line is inert.
- **Can it affect winner selection?** No. It contributes no entry. It occupies one line position, so
  every later entry is shifted by one — uniformly, which preserves relative order, and tier-4 winner
  selection depends only on relative order.
- **Can it become ambiguous after an adjacent migration?** No. The leading apostrophe disqualifies it
  permanently, independent of neighbours.
- **Recorded?** Yes — named and deliberately left alone in the commit message of `54ea850`, with the
  reason (MANIFEST position is part of the winner rule, so removal needs its own measurement). It is
  bounded source-hygiene debt. It was **not** removed by this audit.

---

## 6. PHASE D TEST-HARNESS READINESS

**The dedicated command:**

```bash
npm run test:phase-d
```

(= `node scripts/checks/run.mjs --profile=phase-d`)

| run | tests | pass | fail | skipped | cancelled | exit | 429 |
|---|---|---|---|---|---|---|---|
| 1 | 300 | **300** | **0** | **0** | 0 | **0** | 5, all recovered |
| 2 | 300 | **300** | **0** | **0** | 0 | **0** | **0** |

**Stable and repeatable.** The profile prints its contract and both exclusions with file, phase and
owner before running — visible, never a silent skip:

```
PROFILE phase-d — ... Runs under the zero-cost contract ...
  contract: NO_PAID_AI=true OPENROUTER_DISABLED=true AI_PROVIDER_MODE=mock PHASE_D_EXTERNAL_EFFECT_MODE=mock
  EXCLUDED — 2 test(s), each owned and owed:
    production: every packaged department resolves to a live runtime department
      scripts/checks/v3_runtime_behaviour.test.mjs · KNOWLEDGE_V3 · owner: knowledge-pack remediation
    production: a decided agent action writes a decision trace naming those records
      scripts/checks/v3_runtime_behaviour.test.mjs · KNOWLEDGE_V3 · owner: knowledge-pack remediation
```

Arithmetic: the full suite is 302; the profile runs **all 61 discovered node files** and removes the
2 named knowledge tests → 300. 302 − 2 = 300, and `skipped 0` confirms nothing else was dropped.
Phase A, effective Phase B and Phase C tests are all members — the profile has no include-list, so
membership is the entire discovered set minus two named exclusions.

| requirement | measured |
|---|---|
| deleted-staging references executed by the profile | **0** — exactly one executed file mentions it, in a comment (`artifact_review_alias_cannot_self_approve.test.mjs:32`) |
| nested repository files included | **0** — `nestedReposSkipped()` = `[]` |
| uncontrolled 429 failures | **0** — serialised at `--test-concurrency=1`, 5 then 0 across the two runs, all recovered |
| Phase A / effective Phase B / Phase C failures | **0 / 0 / 0** |
| Phase D deterministic harness failures | **0** |
| harness skipped required tests | **0** |
| exclusion still matches a real test | `every_exclusion_still_matches_a_test.test.mjs` 5 pass, 0 fail |

The two KNOWLEDGE_V3 failures are genuine knowledge/runtime-intelligence tests (a packaged
department manifest of 24 against 10 active departments; a V3 decision-trace shape over
`agent_actions`), explicitly owned by the later knowledge phase, absent from the deterministic
profile, and incapable of hiding a Phase A/B/C defect — the Phase C trace estate is separately
asserted by `fn_kernel_trace_integrity` and `fn_kernel_system_trace_state`.

---

## 7. AUTOMATION HOLD

**183 of 206 cron jobs are inactive.** The 23 active are kernel infrastructure, monitoring and audit
only: `ai_health_15min`, `phase_c_outbox_deliver_1min`, `control_mode_sweep_5min`, `health_check`,
`uptime_check_15min`, `smoke_test_30min`, `backup_daily`, `dropbox_backup_scan`, `dropbox_sync_daily`,
`ai_spend_guard_hourly`, `autonomy_dispose_hourly`, `agent_security_hourly`, `security_ai_daily`,
`security_selfaudit_daily`, `founder_brief_daily`, `board_report_weekly`, `monthly_report`,
`approval_trace_audit_weekly`, `autonomy_audit_weekly`, `decision_conflict_scan_weekly`,
`evolution_scan_weekly`, `policy_consistency_weekly`, `regulation_watch_weekly`.

No business-producing automation is active. Notifications **sent** during the audit window: **0**
(last send anywhere: 2026-08-16 05:30 UTC). Nothing was reactivated.

---

## 8. ZERO-COST OBSERVATION

**Two real scheduled `ai_health` executions observed inside the audit window** — 11:22:00 and
11:37:00 UTC — and **both** recorded:

> `skipped_due_to_zero_cost_mode: 8/8 routes held until 2126-08-15T02:51:36+00; key_present=true;
> no request was made to any paid provider`

| requirement | measured |
|---|---|
| OpenRouter HTTP requests | **0** — the gate short-circuits before `fetch` |
| other paid-inference requests | **0** |
| `llm_attempt` delta | **0** (69 → 69, last 2026-08-15 02:51:33) |
| `ai_usage` delta | **0** (14 → 14) |
| paid inference cost | **AED 0.00 = USD 0.00** |
| fallback provider key | none — the gate does not fall back and does not guess |
| gate-read failure denies | `paidProviderGate` is fail-closed: throw, null, malformed shape and explicit refusal all arrive as `allowed=false` |
| empty/malformed route state denies | `fn_os_paid_ai_allowed()` denies on an empty route table by construction |
| live email / SMS / WhatsApp / social / payment / refund | **none** |

---

## 9. GENERATED CLOSURE EVIDENCE

| requirement | measured |
|---|---|
| headlines | **15** |
| failed | **0** |
| credential-blocked | **0** |
| headlines missing command / numerator / denominator / measurement / result | **0** |
| environment recorded | `project_ref`, `NO_PAID_AI`, `OPENROUTER_DISABLED`, `AI_PROVIDER_MODE`, `PHASE_D_EXTERNAL_EFFECT_MODE`, `management_credential_present` |
| counts current | crosswalk 1801 · routines 1022 · negative 58 · positive 13 — each matching what this audit measured independently |

The document records commit `3b590d13`, the last content commit of the branch, rather than the merge
commit `f0f7339`. Verified consequence: `git diff 3b590d13 f0f7339` excluding the closure files
themselves is **empty** — every code, SQL and artefact file is byte-identical. A generated evidence
document cannot name the commit that contains itself; it certifies main's content exactly.

---

## Audit hygiene

Working tree at close: clean apart from untracked audit artifacts. No tracked file was modified, no
commit was made, no database definition changed. Every probe aborted; `org_phase_baseline` 2,
`phase_c_task` 52, `phase_c_historical_repair` 71, `security_audit_log` 2,882,
`kernel_maintenance_write` 0, Phase A drift 0, Phase B drift 0, TRUNCATE board green at 75/75.
