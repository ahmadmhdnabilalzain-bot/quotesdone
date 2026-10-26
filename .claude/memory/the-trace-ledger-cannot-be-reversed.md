---
name: the-trace-ledger-cannot-be-reversed
description: A committed inquiry starts W05 and writes an append-only execution ledger with no maintenance door — so it can never be cleaned up.
metadata:
  type: project
---

`public.inquiries` AFTER INSERT fires `trg_inquiry_received_a`, a registered ACTIVE class A
NEW_WORK_REQUEST source. `fn_kernel_trigger_submit` starts a real W05 run, and
`phase_c_workflow_step_run` AFTER INSERT writes `public.phase_c_trace`, which cascades ON DELETE to
`public.phase_c_system_execution`. That table's `z10` trigger refuses DELETE **unconditionally** —
`kernel.maintenance_reason` returns the identical refusal, measured 24 Aug 2026. Both are the frozen
Phase C subject `trace_ledger`.

**So a committed inquiry can never be reversed**, and "zero residue" and "a committed inquiry"
cannot both hold. `fn_phase_d_committed_scenario_open` refuses one by name. Customers and leads ARE
reversible and the capability proves it (30 relations back at watermark).

**Why it matters:** it permanently blocks PD-PRIV-004 and PD-CONC-001, and any future request for a
committed inquiry fixture. Unblocking needs a Phase C change request — the founder's call.

Related: [[restore-a-frozen-subject-and-raise-the-change-request]].
