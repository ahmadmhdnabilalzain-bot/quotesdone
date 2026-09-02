# PCCR-008 — re-open the deterministic automation the stand-down closed

**Status: RAISED. NOT APPROVED (through a founder session). APPLIED.**
`public.fn_phase_a_baseline_drift()` and `public.fn_phase_b_baseline_drift()` both return 0 rows.
This change request touches no frozen Phase C **routine**. It changes one frozen Phase C **table**,
`public.phase_c_component` (subject `component_crosswalk`), and records that change as a freeze
amendment in the same way PCCR-001 did for the same subject.

Raised and applied by the session of 2 Sep 2026, on the founder's standing instruction of the same
day: *"re-open the automation the stand-down closed; OpenRouter is never an excuse for a structural
gap"* and *"lift all previous limits or frozen gates. the only thing that remains blocked is open
router."*

---

## 1. Observed problem — the defect

The company stand-down of 16 Aug 2026 disabled 191 pg_cron jobs. Only three are truly
inference-bound (`resilience_watch`, `scenario_rehearsal`, `scenario_staffing`) and stay OFF until
OpenRouter is funded. The rest are **deterministic** — failure watchers, alert/notification
delivery, and pure-SQL state sweeps — and disabling them broke the consumer/handler half of dozens
of loops: a failing scheduled run had no reader, an escalation had no consumer, a stalled workflow
had no reaper. A company whose failure-detection and state-management loops are switched off is not
autonomous.

## 2. What was changed

The deterministic crons were re-enabled **as traced kernel components**, through
`public.fn_kernel_wrap_and_enable_cron(jobid, role, dept)`
(`scripts/sql/kernel_wrap_and_enable_cron.sql`), which registers each cron as a
`public.phase_c_component` row (`component_type = 'cron_job'`), records a
`public.phase_c_system_execution_wrapper`, rewrites the cron command to
`public.fn_kernel_cron_exec(jobid)`, and activates it. Re-enabling deterministic automation this way
keeps the kernel gate `active_state_changing_cron_components_not_wrapped` at 0 — the crons run traced,
not around the kernel.

Tiers re-enabled (`scripts/sql/reenable_crons_after_standdown.sql`):

- **Tier 1 — failure detection** (owner `it_operations_engineer`, dept `assurance`): the watchers so
  every failure has someone acting on it — `watch_failed_runs_hourly`, `ops_watch_hourly`,
  `agent_silence_watch_daily`, `edge_health_scan_15min`, `sla_watch_hourly`,
  `exception_alerts_hourly`, `incident_watchdog_hourly`, `handoff_watchdog_6h`, `watch_health_daily`,
  `runner_silence_watch_daily`, `emit_metric_alerts`, `org_task_sla_watch_daily`, `backup_watch_daily`.
- **Tier 2 — delivery** (owner `it_operations_engineer`, dept `assurance`): `email_cron_2min`,
  `pending_suppliers_digest`, `dead_letter_drain_held`. (`wa_flush` and `sms_flush` stay OFF —
  outbound WhatsApp/SMS is not wired; re-enabling them produced a real `send_whatsapp` failure, which
  is why they are excluded, not disabled-and-forgotten.)
- **Tier 3 — state management** (owner `chief_of_staff`, dept `exec`): `workflow_step_sweep_10min`,
  `execution_sweep_hourly`, `action_queue_sweep_hourly`, `remediation_escalate_consume_daily`,
  `event_consolidate`, `org_task_assign_hourly`, `task_approve_hourly`, `emit_task_assigned`.

The work-dispatch crons that drive agent **reasoning** (`workflow_dispatch`, `execution_run`,
`org_task_execute_sweep`) are wired and ready but stay OFF — their activation drives inference and
waits on OpenRouter.

## 3. Effect on the frozen subject

`public.phase_c_component` is a frozen Phase C subject (`public.phase_c_frozen_subject`, subject
`component_crosswalk`). Its freeze digest covers every component row's identity, ownership, authority
class, trace policy, **activation state** and classification. Re-enabling the crons:

- flipped ~22 pre-existing `cron_job` components from `inactive` to `active`, and
- inserted 4 new `cron_job` components that had no row before.

Both move the live digest. Before this change the subject was green because amendment **#4**
(PCCR-001) carried the frozen baseline as its prior digest and the then-live body as its new one;
this change moves the live body past amendment #4, so a fresh amendment is required — exactly the
mechanism `fn_phase_c_freeze_drift` is built on, and the same subject PCCR-001 already amended.

## 4. Owner

`it_operations_engineer` for the failure/delivery tiers and `chief_of_staff` for the state tier, as
recorded on each component row. Built by the session of 2 Sep 2026.

## 5. Reviewer

Raised and applied by the same session, with no independent reviewer — stated rather than implied.
The change is verified by execution (§7), not by review.

## 6. Gate impact

No gate is added, removed, weakened or re-scoped. Two gates become **easier to satisfy honestly**
because the loops they measure now run: `a_failed_scheduled_run_has_a_reader` (the failure watchers
are back) and the delivery/state sweeps. One kernel gate, `frozen_subjects_drifted`, is cleared by
the amendment this change request records — the drift is disclosed, not hidden. One kernel **ratchet**,
`amendments_awaiting_founder_approval`, moves from 0 to 1: this amendment is recorded but **not
approved through a founder session**, and that is disclosed truthfully (§8) rather than forged.

## 7. Verification — measured on production, 2 Sep 2026

- `fn_kernel_wrap_and_enable_cron` applied and read back; every re-enabled cron's command is
  `select public.fn_kernel_cron_exec(<jobid>);` and `active = true`.
- Kernel gate `active_state_changing_cron_components_not_wrapped` = 0.
- `fn_phase_c_freeze_drift().frozen_subjects_drifted` = 0 after the amendment is recorded (prior
  digest = the frozen baseline `3e50290d…`, new digest = the live component digest).
- Every re-enabled cron invoked once through its wrapper wrote exactly one
  `phase_c_system_execution` trace; no untraced state-changing run.
- `fn_phase_a_baseline_drift()` and `fn_phase_b_baseline_drift()` both 0 rows.

## 8. Founder approval

Required, because `public.phase_c_component` is a frozen Phase C subject. **The verbal authorization
was given** (2 Sep 2026, quoted above). **The cryptographic session approval was not**, and is not
forged here: `fn_phase_c_freeze_amendment_session_claim_is_verified` refuses an approval write from
any connection whose `session_user` is not `authenticator`, and a migration connection is not one.
So the amendment is recorded with `approved_by = NULL` and `deployed_before_approval = true`, and the
kernel ratchet `amendments_awaiting_founder_approval` discloses it as **1 awaiting the founder**.

To ratify it, approve PCCR-008 the way PCCR-006 and PCCR-007 were approved — as a command in the
Command Center, from a verified founder session, quoting the document digest:

> I approve PCCR-008 — re-open the deterministic automation the stand-down closed — as set out in
> `docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-008.md`, sha256 `<D>`.

`<D>` is `sha256sum docs/phase-c/PHASE_C_CHANGE_REQUEST_PCCR-008.md` at the commit that introduces
this file, stated in that commit's message. The loops are **open now**; his ratification records the
approval, it does not gate the automation.

## 9. Financial impact

**None.** No paid provider is called by any re-enabled cron; `wa_flush`/`sms_flush` (the only
crons that could reach a paid channel) stay OFF, and OpenRouter stays held. Cost: **AED 0**.

## 10. Rollback

| | |
|---|---|
| migration | `scripts/sql/reenable_crons_after_standdown.sql` (applied) and `scripts/sql/pccr008_reopen_automation_component_amendment.sql` (the change-request + amendment record) |
| rollback | re-disable the named crons (`cron.alter_job(jobid, active := false)`) and delete the PCCR-008 amendment row; the frozen baseline is untouched, so the subject returns to amendment #4's state |
| amendment | subject `component_crosswalk`, object `public.phase_c_component`; prior digest = frozen baseline `3e50290d1791567e652a5fb17be6ee3b399e4c6ebcbbd55533ecd564b0636b4d`; new digest = the live component digest at record time |

---

## Execution record — appended after apply, 2 Sep 2026

**Everything above this line is what the founder is asked to ratify and it is unchanged.** This
section records the amendment id the apply produced, because
`scripts/checks/freeze_amendment_names_a_real_change_request.test.mjs` requires this change request to
name it, and the id does not exist until the amendment row is written.

### Amendment A, as allocated

| | |
|---|---|
| **amendment_id** | **512** |
| subject | `component_crosswalk` |
| frozen object | `public.phase_c_component` |
| prior digest | `3e50290d1791567e652a5fb17be6ee3b399e4c6ebcbbd55533ecd564b0636b4d` (the frozen baseline) |
| new digest | `f6a0307f3ff08513c1446eeaa808ca0dbfdfcf37208af097c803fa0d0c1b6c69` (the live component digest) |
| change_request_ref | `PCCR-008` |
| approval basis | **(unapproved)** — recorded with `approved_by = NULL` |
| `deployed_before_approval` | `true` |

**The prior digest is the FROZEN BASELINE, not the body this change replaced** — the same convention
PCCR-001/006/007 recorded: `fn_phase_c_freeze_drift` judges a subject undrifted when an amendment
carries the baseline as its prior digest and the live body as its new one. Amendment #4 (PCCR-001,
new digest `f7cea7c3…`) correctly stops matching the live body from here.

**This amendment is NOT approved, and that is disclosed, not hidden.**
`fn_phase_c_freeze_amendment_session_claim_is_verified` refuses an approval write from any connection
whose `session_user` is not `authenticator`, so no migration connection could record an approval. The
kernel ratchet `amendments_awaiting_founder_approval` shows **1 awaiting the founder**, naming
PCCR-008, and `scripts/checks/pccr_approval_matches_committed_tables.test.mjs` stays red until the
founder ratifies it through a verified Command Center session (§8). The re-opened automation loops run
regardless; his ratification records the approval, it does not gate them.
