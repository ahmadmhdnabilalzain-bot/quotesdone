# Phase C — the five root causes, engineering closure

**Branch:** `fix/phase-c-final-five-root-causes`
**Run:** 17 Aug 2026, 16:00–17:10 UTC, against production `htdblwldjkcgjvmqkbeh`.
**Mode:** `NO_PAID_AI=true OPENROUTER_DISABLED=true AI_PROVIDER_MODE=mock` on every command.

Five root causes, implemented in the order the brief set, each rehearsed as the exact committed SQL
in an aborted production transaction with production re-read afterwards to prove it was unchanged,
then deployed and read back. No broad independent audit was run. Phase D was not begun.

---

## SOURCE OF TRUTH

| | |
|---|---|
| application repository → production drift | **0** |
| application production → repository drift | **0** |
| conflicting current definitions | **0** |
| ambiguous routine winners | **0** |
| uncommitted application DDL | **0** |
| manifest gaps | **0** |

`scripts/checks/canonical_routine_manifest.mjs --all` — exit 0, 965 routine names, 965 canonical.
Selection is by an explicit sequence, never a commit timestamp: migration version for
`supabase/migrations_history` and `supabase/migrations`, filename for `ai-organization/db-functions`,
and **line position in `scripts/sql/MANIFEST.txt`** for `scripts/sql`. Two files at one sequence key
is itself a failure, so no tie is ever broken by a heuristic.

`fn_ws_operations` and `fn_ws_company`: canonical file `operations_company_remaining_lists.sql` at
MANIFEST position 1275, source SHA equal to deployed SHA, and the competing definitions in
`operations_assistance_company_reports.sql` explicitly retired in `scripts/sql/SUPERSEDED.txt`.

Three defects had to be fixed before the gate could pass, none of them the one the brief named:
the manifest was corrupted with twelve lines of captured hook stdout and a concatenated path; the
parser dropped every kernel routine because its body tag `$k34$` carries digits; and two DDL
matchers reported committed DDL as uncommitted (a multi-column `add column` read as one, and
inline-declared constraints whose Postgres-generated names appear in no file).

`sql_files_match_live.test.mjs` now refuses to run and names its replacement.
`.github/workflows/project-parity.yml` runs the new check **on every pull request**.

## CANCELLATION

| | |
|---|---|
| cancelled commands with active runs | **0** |
| cancelled commands with active step runs | **0** |
| cancelled commands with active tasks | **0** |
| cancelled commands with pending handoffs | **0** |
| cancelled commands with deliverable pending events | **0** |
| cancelled commands with unsealed required traces | **0** |
| cancellation using JSON payload matching as its relationship | **0** (executable code, comments stripped) |
| cancellation replay creating additional effects | **0** |
| command 338 final state | **cancelled** |
| run 538 final state | **cancelled** |
| step run 531 final state | **cancelled** |

Measured across all **9** cancelled commands in the estate, not only 338.

`fn_founder_command_control` delegates cancel and supersede to `fn_kernel_cancel`; the founder is
verified in the control and again inside the kernel. `fn_kernel_cancel` sweeps and re-counts on
COLUMNS — command, run, step run, task — after `phase_c_event_outbox` gained `task_id`, the one
normalised relationship it lacked. `z05_outbox_refuse_cancelled_subject` guards the transition into
`delivered` on the table itself, so a row claimed a moment before the cancellation, or a worker
written tomorrow, cannot deliver an event whose work is cancelled. A delivered event is never
touched.

Command 338 was repaired **through the canonical canceller**, with the original defect named in the
cancellation reason. Its own state and history are untouched.

## SIGNALS

| | |
|---|---|
| active existing-workflow signal sources | **12** |
| active signal types | **6** of 11 |
| inactive target signal types used by active sources | **0** |
| handlers implemented | **6 of 6** active types |
| valid-state cases accepted | **6 / 6** |
| invalid-state cases refused | **6 / 6** |
| missing-workflow cases refused | **6 / 6** |
| duplicate signal effects | **0** |
| falsely cut-over rows | **0** |

Five types activated under option A, each because its handler was already implemented **and was
driven by a fixture before activation**: `clarification.response` (COMPLETE_STEP), `followup.due`,
`provider.callback`, `supplier.acknowledgement`, `supplier.quote_revision`. Five stay inactive with
the reason recorded — three have no source; `review.verdict` stays shut because a verdict is
recorded by the reviewer where independence is enforced; `run.cancellation_requested` stays shut
because cancellation already has two doors and root cause 2 exists because there were two.

The rule is enforced from both sides: `z10_signal_type_activation_guard` refuses deactivating a type
an ACTIVE source names, `z10_source_signal_guard` refuses activating a source whose type is
inactive. `fn_kernel_cutover_measure` now requires all seven conditions and reports three new lines,
all at 0; the verdict split is unchanged at CUT_OVER 32, READ_ONLY 19, RETIRED_OR_INACTIVE 16.

Register: `docs/phase-c-final-kernel/PHASE_C_ACTIVE_SIGNAL_REGISTER.csv`, twelve rows, every field
the brief names.

## SYSTEM TRACES

| | |
|---|---|
| current system-execution traces without execution subject | **0** |
| current system executions without trace | **0** |
| current terminal state/trace mismatches | **0** |
| current sealed traces without `sealed_at` | **0** |
| current active orphan traces | **0** |
| `fn_kernel_system_trace_state` failing checks | **0** (was 1 of 13) |
| `fn_kernel_historical_register_state` failing checks | **0** |
| trace 3730 disposition | **repaired post-cutover defect, not a historical exception** |

The investigation: `fn_kernel_trigger_submit` created 3730 at 05:05:00.033303 for trigger-inbox row
46. **No execution row was ever attempted** — the code path had none. The transaction separated
nothing; the trace and its subject row are both present. What was missing was the subject the policy
requires, and nothing refused a trace written under a contract it could not meet.
`fn_kernel_signal_submit` had the same shape and worse, claiming subject_ref `signal:<id>`.

The lifecycle — `_begin`, `_finish`, `_fail`, plus `fn_kernel_intake_execution` for the doors —
writes the pair together. The execution row is written at FINISH because
`phase_c_system_execution` is append-only, so an open trace with no execution row is exactly what an
execution in flight looks like, and the enforcement is written to that fact: two DEFERRABLE
INITIALLY DEFERRED constraint triggers checked at COMMIT. Proved by forcing `SET CONSTRAINTS ALL
IMMEDIATE` on a deliberately half-written pair — refused, 23514.

Trace 3730 keeps its original subject, `created_at` and `sealed_at`, because
`fn_phase_c_trace_append_only` refuses editing a sealed trace and that refusal is correct. It gained
a reconstructed execution row carrying the original instant in `started_at` and the repair instant in
`recorded_at`. rc4 first classified it as a historical exception;
`fn_kernel_historical_register_state` failed that within a minute — *"a 'historical' exception that
happened after the kernel took over is not historical"* — and rc4b corrected it through the
register's own append-only correction protocol. Historical exceptions preserved: **38**, exactly as
before.

## GUARDS

| | |
|---|---|
| negative cases refused | **55 / 55** |
| positive cases accepted | **20 / 20** (Phase B suite, both directions) |
| prose-only assertions | **0** |
| refusals asserted on a SQLSTATE + guard pair | **31** |
| partial side effects | **0** — every probe aborts its transaction |
| row counts after refused operations | unchanged, 10 of 10 counters, measured as a delta |

No guard was touched. The pairs were captured by running every case exactly as the suite runs it,
maintenance-door preamble included — the first attempt omitted it, K18 answered first with 42501,
and 13 cases were recorded against the wrong guard; that attempt was thrown away.

## FROZEN BASELINES

| | |
|---|---|
| Phase A drift | **0 rows** |
| effective Phase B drift | **0 rows** |
| Phase B invariants | **77 / 77** |
| kernel write guard, both directions | **7 / 7** |

## COST

| | |
|---|---|
| OpenRouter HTTP requests | **0** |
| other paid inference requests | **0** |
| paid inference attempts (`llm_attempt` rows) | **0** — newest row in the table is 2026-08-15 02:51 |
| `ai_usage` rows | **0** |
| paid inference cost | **USD 0.00** — `sum(cost_usd)` over every trace created in the window |
| fallback provider keys used | **0** |
| `ai_health` runs in the window | **8**, every one recording *"made NO request to any paid provider"* |
| provider routes held | **8 of 8**, `paid_ai_allowed = false` |

---

## What was deployed

| file | routines | rollback |
|---|---|---|
| `rc2_cancellation_reaches_the_kernel.sql` | 4 + `task_id` column and index | yes |
| `rc3_active_signals_are_executable.sql` | 3 + two activation columns | yes |
| `rc4_execution_and_trace_are_atomic.sql` | 8 + two component rows | yes |
| `rc4b_3730_is_not_history.sql` | 1 + one correcting register row | yes |

Every one applied with `scripts/apply_sql.mjs --apply --ddl`, which posts the committed bytes and
reads the definition back. Root cause 1 and root cause 5 are repository-side only and changed no
routine on production.
