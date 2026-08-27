# NARROW PHASE D / PHASE C CORRECTION — BUILDER CLOSURE, 2026-08-27

**Production project:** `htdblwldjkcgjvmqkbeh` (the only one; staging was deleted 15 Aug 2026)
**Branch:** `phase-d-narrow-correction-2026-08-27`, from `main` at `8db01d6`
**Production clock at precheck:** `2026-08-27 11:44:13.549157` UTC

This session was scoped to six findings. It did not begin Phase E, did not reactivate business
automation, did not activate `outcome_evaluate_daily` or `reputation_weekly`, called no paid
provider, and sent no live external effect.

---

## 0. Precheck, as read before any edit

| item | value |
|---|---|
| branch / HEAD | `main` / `8db01d6af339257ad1da211285ef13a1d08d330e` |
| origin/main | `8db01d6af339257ad1da211285ef13a1d08d330e` — identical |
| working tree | 0 modified tracked files; 979 untracked (permanent session debris — paths are staged individually, never `git add -A`) |
| PR / merge state | no open PR; `#472` merged, checks green |
| repository → production drift | **0** |
| production → repository drift | **0** |
| uncommitted application DDL | **0** |
| Phase A drift | **0 rows** |
| effective Phase B drift | **0 rows** |
| Phase C freeze board | 11 rows, **1 red**: `approved_change_requests_with_no_verified_governance_decision` = `1 of 1 approved` (PCCR-003) |
| Phase D acceptance standard | `PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1`, approved by founder command 37730, frozen |
| active cron | **23** of 206 (ceiling 25) |
| automation hold | `GATE-032` **PASSED** |
| provider hold | `fn_kernel_paid_provider_gate` → `allowed: false`, 8 of 8 routes held open-circuit |
| active W04 orphan runs | **8** (209068–209073, 209193, 209194) |
| `phase_c_founder_auth_event` | **0 rows** |
| `phase_c_governance_decision` | **0 rows** |
| `kernel_write_authority` for `phase_c_founder_auth_event` | 1 row — `fn_phase_c_founder_subject_bind` only |
| `fn_phase_c_founder_subject_bind` proacl | `postgres=X`, **`service_role=X`** |
| `fn_phase_c_governance_decide` proacl | `postgres=X`, **`service_role=X`**, `authenticated=X` |
| deployed Edge Functions | **202** |
| `kernel_trigger_source` edge_function rows | 26 |
| `phase_c_component` edge_function rows | 202 |

**`postgres_error_log_stream` — VERIFIED, with its window stated.** Log Explorer **was** available
this session, so the brief's instruction to record `NOT_VERIFIED_BACKEND_ERROR` does not apply and
recording it would have been false. `select count(*) from logs where source='postgres_logs'` returned
**7,126** rows. Severity is not populated on this project's stream (`error_severity` is empty on
7,124 of them), so the message body was matched instead: **15** entries contain `ERROR`, **0**
contain `FATAL`, **0** contain `PANIC`. All 15 are accounted for — 8 are a `PHASE_D_DEFECTS` evidence
string that contains the word, and 7 are the statement text of this session's own deliberate
`raise exception` rehearsals and assertion blocks. **Limitation, stated: the stream holds 24 hours.
This says nothing about any earlier period.**

---

## 1–3. The founder door and the governance door

Full report: [`docs/phase-c/PCCR-006_GOVERNANCE_DOOR_CANARY.md`](../phase-c/PCCR-006_GOVERNANCE_DOOR_CANARY.md),
including the call graph, the authorization matrix, the threat model and the tamper-evident record.

| | before | after |
|---|---|---|
| governance decisions ever recorded | **0** | **1** (PCCR-007, decision 6) |
| founder auth events ever minted | **0** | **2** |
| service_role can bind the founder's subject | **YES** | no — 403 |
| `fn_phase_c_governance_decide` can write its own auth event | no — 42501 | yes, via `kernel_write_authority` |
| service_role holds EXECUTE on either door | yes | **no** |
| authorization cases driven over real HTTPS | — | **22 of 22 correct** |
| direct-write / management-SQL refusals measured | — | **12 of 12 refused** |

`fn_phase_c_require_founder` — a frozen Phase C subject — was **not** touched.

---

## 4. PCCR-003

Full report: [`docs/phase-c/PCCR-003_DISPOSITION.md`](../phase-c/PCCR-003_DISPOSITION.md).

**Determination:** approved in a verified founder session on the amendment ledger
(amendment 36, `AUTHENTICATED_FOUNDER_SESSION`, route `auth.uid()`, subject
`1256c7ec-17bf-4b1e-af8f-aaa32a8fdd14`, 2026-08-22 21:55:32+00), migration-backfilled onto the
change-request row, and **pre-ledger** on the governance ledger, which PCCR-006 did not create until
2026-08-25.

**It is still red, and this is the one item in the session that is his and not mine.** Ratifying it
requires a Command-Center sentence from him quoting the document digest; the door correctly refuses
without one (canary case GOV-N11), and supplying it on his behalf would be forging his approval. The
exact sentence and the one command that follows it are in §4 of that document.

Freeze board after this session: **11 rows, 1 red** — `1 of 2 approved`. The denominator moved from
1 to 2 because PCCR-007 is now APPROVED **with** a verified decision. *A real fix moved the headline
the wrong way, and that is stated rather than hidden.*

| required | result |
|---|---|
| written instruction presented as authenticated session | **0** |
| PCCR-003 cleared by migration-written `approved_by` | **0** (refused, measured) |
| Phase C freeze-board red caused by PCCR-003 | **1 — NOT MET, awaiting one founder sentence** |

---

## 5. The eight orphaned W04 runs

Full report: [`PHASE_D_ORPHAN_WORK_REPAIR.md`](PHASE_D_ORPHAN_WORK_REPAIR.md).

8 runs cancelled through `fn_kernel_cancel` with `ORPHANED_PARENT_MISSING_PRE_FIX`; 8 step runs,
8 tasks, 24 open traces closed; 0 rows deleted; 0 customers recreated. Board extended from 6 rows to
**13**, all green, with the original six unchanged word for word. Two prevention guards deployed and
**forced to fire**, not merely deployed.

A second class was found by writing the first: run 352 (W29, `incident:agent_action:3833`) does not
resolve under its binding but its parent — `agent_actions` 3833, still `pending`, a high-severity
security item — is alive. **It was not cancelled.** It is named in its own informational row with the
row that does back it, and the producer/map disagreement is recorded as an open finding.

---

## 6. The 202 Edge Functions

Full report: [`PHASE_D_EDGE_FUNCTION_INVENTORY.md`](PHASE_D_EDGE_FUNCTION_INVENTORY.md);
data: [`PHASE_D_EDGE_FUNCTION_INVENTORY.csv`](PHASE_D_EDGE_FUNCTION_INVENTORY.csv).

Both heuristic numbers in the brief were measuring something other than what they said:

* *"117 write a trigger-protected table"* → the guarded population is the **13** tables carrying
  `fn_kernel_write_guard` (not eight — that figure is stale in several documents here), and **0** of
  202 write one.
* *"97 have no edge source row"* → a cron-driven function's source is the **cron job** and a
  trigger-driven function's source is the **trigger**; asked in the shape the register is written in,
  **0** required source rows are missing. **No source row was created by this session.**

202 of 202 inventoried and classified, 0 unclassified, 140 state-changing, all 140 carrying a
workflow, accountable role, authority class and trace policy. 2 dynamic writers hand-reviewed and
declared, 0 unreviewed, neither reaching a guarded table.

---

## 7. Reputation under the stand-down

Full report: [`PHASE_D_REPUTATION_STANDDOWN_POLICY.md`](PHASE_D_REPUTATION_STANDDOWN_POLICY.md).

The scorer was **not** run to make anything green and the snapshot was **not** recomputed. It is now
a mechanism rather than a sentence: `fn_reputation_recompute` returns
`PAUSED_BY_FOUNDER_STANDDOWN` with `ok:false` while a hold is open, writes nothing to
`agent_reputation`, `employee_authority` or `autonomy_control_audit`, and after a resume returns
`NOT_MEASURED_DURING_HOLD` until a complete 30-day window has elapsed entirely after the resume. The
migration's assertion calls it for real and asserts that nothing moved.

Four employees were not demoted because the scorer did not run — not because a result was
overridden. `reputation_weekly` and `outcome_evaluate_daily` remain **inactive**.

---

## 8. Production deployment and rollback ledger

Applied production-direct, each with `node scripts/apply_sql.mjs <file> --apply --ddl`, each read
back out of the database and compared to the committed bytes.

| # | file | routines | read-back | reversal | reversing it re-opens |
|---|---|---|---|---|---|
| 1 | `scripts/sql/phase_c_the_bind_door_took_the_subject_as_an_argument.sql` | `fn_phase_c_founder_subject_bind` + 1 registry row + 8 grant statements | identical | `down/phase_c_the_bind_door_took_the_subject_as_an_argument_down.sql` | service_role binding the founder's subject with no founder token; the governance door refusing its own write with 42501 |
| 2 | `scripts/sql/phase_c_active_work_whose_business_parent_is_gone.sql` | `fn_kernel_business_subject_resolve`, `fn_kernel_business_parent_missing`, `fn_kernel_orphaned_work`, `fn_kernel_workflow_run_parent_exists`, `fn_kernel_business_parent_delete_guard` + 8 triggers | identical | `down/phase_c_active_work_whose_business_parent_is_gone_down.sql` | a run opening on a parent that does not exist; a parent being deleted while its work is live |
| 3 | `scripts/sql/phase_c_the_scorer_would_have_read_a_hold_as_underperformance.sql` | `fn_reputation_recompute`, `fn_reputation_hold_state` | identical | `down/phase_c_the_scorer_would_have_read_a_hold_as_underperformance_down.sql` | the scorer reading a founder-imposed silence as underperformance and gating four employees' authority |
| 4 | `scripts/sql/phase_c_two_boards_written_when_the_door_had_never_opened.sql` | `fn_phase_c_founder_auth_state` + 2 truncate triggers + 2 revokes | identical | `down/phase_c_two_boards_written_when_the_door_had_never_opened_down.sql` | `TRUNCATE public.transactions` firing no row trigger; two board rows that read the narrowed bind grant as the defect and expected an append-only table to stay empty |
| 5 | `scripts/sql/phase_c_the_ownership_ledger_named_two_superseded_files.sql` | (2 `kernel_routine_ownership` rows) | n/a — DDL only | `down/phase_c_the_ownership_ledger_named_two_superseded_files_down.sql` | the ledger pointing at files that no longer define `fn_kernel_orphaned_work` and `fn_reputation_recompute` |

All three down scripts carry **no transaction control**. None resurrects history: the cancelled runs
stay cancelled (sealed traces are append-only) and the recorded governance decision stays recorded
(`phase_c_governance_decision` refuses UPDATE and DELETE). Reversing the **code** does not reverse
the **facts**, and that asymmetry is deliberate.

Data writes, outside those files:

| write | how | reversal |
|---|---|---|
| 8 W04 runs cancelled + derived work closed | `fn_kernel_cancel`, one call per run, `subject_kind = workflow_run` | none — a cancellation a migration could undo is not a cancellation |
| 1 governance decision (PCCR-007) + 2 founder auth events | `fn_phase_c_governance_decide` over real HTTPS with a founder bearer | none — append-only by design; `phase_c_change_request` PCCR-007 is derived from it |

`MANIFEST.txt` gained exactly three lines, one per file, in apply order; `sort | uniq -d` reports
**0** duplicate script paths.

---

## 9. Zero cost, zero effect

Window: `2026-08-27 11:40:00+00` → end of session.

| required | measured |
|---|---|
| OpenRouter HTTP requests | **0** |
| other paid-inference requests | **0** |
| `llm_attempt` delta | **0** |
| `ai_usage` delta | **0** |
| `ai_cost_log` delta | **0 rows**, **AED 0** |
| paid inference cost | **USD 0.00** |
| live email | **0** |
| SMS / WhatsApp | **0** |
| social publication | **0** |
| payment execution | **0** |
| refund execution | **0** |
| customer / supplier notification | **0** (`public.notifications` delta 0) |
| Apify runs | **0** |
| production Dropbox writes | **0** |
| fallback provider key | **0** |
| `phase_d_effect_ledger` | **0 rows, total** |
| `phase_d_external_attempt` | **0 rows, total** |

**11 database-originated HTTP requests were issued in the window, and they are not this session's.**
`net._http_response` records 11 responses, all 200, at 11:45/12:00/12:15/12:30 (×2 each) and
11:52/12:07/12:22 (×1 each). Those cadences are `uptime_check_15min` (job 35),
`dropbox_backup_scan` (job 88) and `ai_health_15min` (job 102) — three of the 23 cron jobs the
founder's partial resume left running. `net.http_request_queue` deletes its row on completion, so the
URLs are no longer retrievable and this is an attribution by schedule, stated as such. No paid
inference was recorded by any of them: `llm_attempt`, `ai_usage` and `ai_cost_log` are all 0 over the
same window, and `fn_kernel_paid_provider_gate` returns `allowed: false` with 8 of 8 routes held.

Holds unchanged: active cron **23** (ceiling 25), `GATE-032` **PASSED**, provider gate **held**,
`reputation_weekly` **inactive**, `outcome_evaluate_daily` **inactive**. No cron job was activated,
paused or rescheduled by this session.

---

## 10. Frozen baselines and regressions after the session

| baseline | required | measured |
|---|---|---|
| Phase A drift | 0 rows | **0** |
| effective Phase B drift | 0 rows | **0** |
| Phase C freeze drift | every row ok | **1 red of 11** — PCCR-003 only, see §4 |
| repository → production drift | 0 | **0** |
| production → repository drift | 0 | **0** |
| manifest gaps | 0 | **0** |
| conflicting current definitions / ambiguous winners / uncommitted DDL | 0 | **0 / 0 / 0** |
| schema mirror byte-identical | yes | **yes** — `supabase/schema/full_schema.sql` regenerated after the LAST apply, 84,606 lines, identical, 0 project refs embedded |
| Edge parity | 202/202 | **202/202** — `node scripts/verify_deploy_parity.mjs --all` → `DEPLOY PARITY OK`, exit 0. No edge function was deployed by this session |
| Phase D frozen regression set | pass | `npm run test:phase-d` → **0 failing checks**. Seven regressions this session introduced were caught by it and repaired before merge; see below |
| kernel positive controls | no door without one | 22 doors, 16 accepted, **0 failed**, 6 not driveable from a management connection and named |
| injected-defect suite | every guard refuses | **56 of 58 refused, 0 failed**, 2 not driveable and named (both pre-dating this session) |
| automation / provider holds | unchanged | **unchanged** |

### Seven things this session broke, and the checks that caught every one before merge

Recorded in full because the count is the point: a narrow correction that touches the kernel's write
path breaks things, and the value of this estate's checks is that none of it reached a merge.

| # | what broke | caught by | repair |
|---|---|---|---|
| 1 | `fn_kernel_workflow_run_parent_exists` and `fn_kernel_business_parent_delete_guard` were EXECUTE-able by `anon` and `authenticated` — a plain `CREATE` grants to PUBLIC, and a trigger function is no exception | `anon_cannot_execute_security_definer.test.mjs` | revoked in the same file, plus an assertion that refuses to apply if any routine the file creates is client-executable |
| 2 | the delete guard REFUSED instead of compensating, so every fixture that creates a customer could no longer clean up: two ZZ DEMO rows left committed | `phase_d_dispatch_reaches_executed`, `phase_d_fixture_catalogue_matches_the_file`, `kernel_boards_are_green` | the guard now cancels the live runs through `fn_kernel_cancel` and then permits the delete; the two rows were removed through it |
| 3 | the run-start guard refused every Phase D drive, which opens workflows on subjects it invents inside aborting transactions | `phase_d_the_three_steps_that_had_no_effect`, `phase_c_guards_reject_injected_defects` | a verified `fn_phase_d_fixture_context()` — HMAC-bound to the txid and to an approved operation — is exempt |
| 4 | the run-start guard refused every W16 run the estate can produce: the producer keys `payment_transaction` by `payment_ref`, not by `id`, and `payment_ref` is not unique | `phase_c_guards_reject_injected_defects` | the resolver asks three questions, not one — see the orphan-work register §5 |
| 5 | `public.os_incidents` and `public.transactions` became **enforcing** with no truncate guard, so `TRUNCATE public.transactions` would have taken every payment the company has recorded and fired no row trigger | `kernel_boards_are_green` via `fn_kernel_truncate_protection_state` | `z00_kernel_truncate_guard` attached and TRUNCATE revoked on both |
| 6 | `fn_phase_c_governance_decide` joined `kernel_write_authority` and so joined the canonical door list with no positive control | `kernel_positive_controls.test.mjs` | a control added and declared not driveable from a management connection, naming the HTTPS run that does drive it |
| 7 | the ownership ledger still named the superseded source file for two re-owned routines | `application_source_of_truth.test.mjs` | both rows reconciled; the structural cause named in the file |

Two further reds were **not** regressions and are corrected rather than silenced:
`fn_kernel_trigger_submit`'s positive control was manufacturing its own subject
(`incident:ZZ-POSITIVE-CONTROL-TRIGGER`, which resolves to nothing) and now drives the shape the
source actually emits; and `freeze_amendment_names_a_real_change_request`'s resolution arm could no
longer empty the founder register, because the first governance decision created a foreign key to it
— the arm now deactivates instead, which exercises the predicate the board actually evaluates.

`fn_phase_c_founder_subject_bind` was added to `anon_cannot_execute_security_definer`'s
`AUTHENTICATED_BY_DESIGN` set with the per-function review it demands. It is a **narrowing**: the
same change removed the `service_role` grant that was the actual hole.

**One disclosure, not this session's and not repaired here.** `resend_inbound` errored at
2026-08-27 10:44:16Z — an hour before this session opened. The founder forwarded a Supabase invoice
to the inbound address; the receipt-extraction call returned HTTP 503 while the paid-provider hold is
open-circuit on 8 of 8 routes, and no expense was booked. No paid inference was made or charged —
`llm_attempt`, `ai_usage` and `ai_cost_log` have been empty since 2026-08-15 02:51:33Z. The gap is
real: an inbound path still attempts a held provider and silently drops the receipt. It belongs to
the business-automation work this session is holding, and it is now a named disclosure in
`a_failed_scheduled_run_has_a_reader.test.mjs`, so a second occurrence still fails.

**And the zero-cost window's sixth slip is now a generator, not a reminder.**
`docs/phase-d/PHASE_D_ZERO_COST_EVIDENCE.md` states a window whose close must be at or after the
newest Phase D timestamp; the check has caught a stale close six times, and the document names the
cause in its own words — *"the only thing keeping them in step is a person remembering to regenerate
this file last … what would end the pattern is a generator that reads the close off the database at
write time, which does not exist"*. `scripts/phase_d/regenerate_zero_cost_evidence.mjs` is that
generator. It reads `now()` on production, re-measures every figure against the stated window, and
**refuses to write** if any paid inference is recorded inside it — moving a close to cover spend
would turn a true statement into a false one.

---

## 11. Exact remaining blockers

1. **PCCR-003 has no governance-ledger row.** One Command-Center sentence from
   `management@quotesdone.com`, verbatim in
   [`PCCR-003_DISPOSITION.md`](../phase-c/PCCR-003_DISPOSITION.md) §4, then
   `node scripts/phase_d/prove_governance_door.mjs --record --ref=PCCR-003`. Everything on this side
   of that sentence is built, deployed and proved.

Nothing else in this session's scope is outstanding.

---

## 12. Findings raised, not repaired here

| finding | why not here |
|---|---|
| W29 writes `incident:agent_action:<agent_actions.id>` while `phase_d_business_object_binding` says `incident:<os_incidents.id>` | re-keying a committed run is impossible, and changing what the security pager emits is business automation, which is held |
| The event-expiry predicate on `phase_c_governance_decision` cannot fire on the canonical path (`now()` is transaction-start time) | not a defect; a guard for a writer that does not exist. Recorded rather than removed |
| `fn_phase_c_require_founder` Route B's `action_class is null` predicate is unreachable from either live caller | same shape; the predicate is present and correct, and nothing can reach it today |
| Several documents state the kernel-guarded table count as **eight**; it is **thirteen** | a documentation sweep is outside a narrow correction session |

---

**PHASE_D_NOT_READY** — on exactly one item, and it is the founder's sentence, not an engineering
gap.
