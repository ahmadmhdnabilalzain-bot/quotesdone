# FINDING — W04-S04 positive case regressed from EXECUTED to `pd_evidence_absent`

**Status: FINDING, not a gate change.** `PHASE_D_FINAL_ACCEPTANCE_STANDARD_V1` §E: an audit finding
that would require a new gate is recorded, reported, and left to the change-control process. This
one needs no new gate — it is a **failure against an existing frozen regression item**, item 17
(`1,799 of 1,799, 0 failed`), which is also Gate FD-02 requirement 11.

Measured 2026-08-25T18:31Z on `htdblwldjkcgjvmqkbeh` by
`node scripts/phase_d/run_step_cases_live.mjs`:

```
steps driven   257
cases written  1799
cases passed   1798
cases failed   1
  1  positive:pd_evidence_absent      (W04-S04)
```

The committed deliverable from the 24 August audit — `docs/phase-d/PHASE_D_STEP_CASE_RESULT.csv`
line 207 — records the same case as:

```
W04-S04,W04,execution,positive,live_step_run,...,true,EXECUTED,
the canonical drive answered EXECUTED and the ledger holds 1 effect(s) for this step run
```

So this is a regression between HEAD `521ed16` (the standard's baseline) and now, not a case that
was always red.

---

## The refusal, verbatim

```
fn_phase_d_handler_execute: step W04-S04 blocked by 1 hard gate(s), every one of them for evidence
the call did not name rather than for a condition the gate judged and rejected:
[{"state":"BLOCKED","gate_id":"GATE-005","refusal_code":"gate005_founder_boundary",
  "evidence_absent":true,
  "reason":"gate GATE-005 (Founder boundary) requires [founder_authority_ref] and the call names
            none of it. Declared evidence: Decision is within delegated authority or founder
            approval exists."}]
(pd_evidence_absent)   UNRESOLVED={founder_authority_ref,packet,requested_action,sla_policy_id,source_version}
```

## Root cause, traced by execution

1. `fn_phase_d_founder_authority(run_id,'W04-S04')` returns
   `{"valid":false,"kind":"FOUNDER_RESERVED","exists":true,"current":true,"covers":false,
     "reserved_by":"FDR-002",
     "why":"W04 is reserved to the founder by FDR-002 and no founder command instructed this run"}`.
   W04 is inside `phase_b_founder_boundary.FDR-002` (`W04;W09;W15;W16;W17;W27;W28`), so the
   delegated-authority branch cannot cover it and a founder command must have instructed the run.

2. The fixture DOES create one. Stage 999 of `fn_phase_d_fixture_scenario` reports
   `{"stage_key":"founder_authority","status":"CREATED","result_reference":"founder_command:40100"}`,
   and the exact lookup `fn_phase_d_drive_workflow` performs — `phase_d_scenario_record` where
   `fixture_run_id = fn_phase_d_fixture_context()` and `contributes_ref='founder_authority_ref'` —
   returns `40100` when evaluated immediately before the drive is called.

3. The run the drive ends up on nevertheless carries `command_id: null`. **Because it is not the
   run the drive started.** Measured immediately before `fn_phase_d_drive_workflow` is called:

   ```
   PRE_RUNS  181190|W04|cmd-|EV-W04-STARTED|W04:customer_account:f1000638-…:1
   ```

   A W04 run for the fixture customer **already exists**, opened by the customer-registration path,
   with no command. `fn_kernel_workflow_start` dedupes on
   `W04:customer_account:<uuid>:1` and hands that run back, so the drive's
   `source_kind='founder_command'` arrival never takes effect.

4. That pre-existing run is new. `scripts/sql/phase_d_q03_a_customer_created_by_eleven_paths_and_
   routed_by_none.sql` (PR #470, commit `ac7ab8e`) created
   `public.trg_customer_registered_kernel`, which routes a registered customer into the kernel.
   Closing "eleven paths created a customer nobody owned" wired customer registration to a W04
   arrival — and the Phase D fixture customer now trips it first.

**It is W04-only for a structural reason, not by luck.** Eighteen steps carry a `founder_gate`, and
most of their workflows are also founder-reserved; the other seventeen pass because nothing opens
their run before the drive does. W04 is the one whose primary object is the customer the fixture
creates.

## What this does NOT show

- Not a Phase C or Phase A drift: `fn_phase_a_baseline_drift()` 0 rows, `fn_phase_b_baseline_drift()`
  0 rows, Phase B baseline reproduces 30/257/56/54/32/159/347.
- Not repository↔production drift: `canonical_routine_manifest --all` reports all six zeros, exit 0.
- Not residue: `fn_phase_d_fixture_residue()` 0 rows; customers/inquiries/quotes/transactions/
  refunds/effect ledger/object record/dispatch all 0.
- **Not measured here: whether GATE-005 blocking a customer-initiated W04 run is the correct
  production behaviour.** It may be — W04-S04 presents founder-approved terms, and FDR-002 reserves
  exactly that. If it is correct, the defect is the fixture, and the 24 August EXECUTED reading was
  the artefact. If it is not, the defect is the collision between the trigger's arrival and the
  drive's. Deciding that changes what "1,799 of 1,799" means and belongs in
  `PHASE_D_ACCEPTANCE_STANDARD_CHANGE_REQUEST`, not in a session's judgement.
