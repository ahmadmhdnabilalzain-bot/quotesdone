const s = {
'IDEM-002': `the driver's own idempotency_key replayed on the completed W10-S04: replay=true, completions 1->1, step runs 5->5, handoff runs 2->2, state completed. CONTROL, a different key on the same step run: refused k3_step_state_invalid (23514).`,
'REV-002': `W10-S05 reviewer risk_and_governance_manager: outcome=pass with no verdict refused k3_reviewer_verdict_missing (23514), completions 0->0, step run left active. CONTROL, the same call after an approved verdict from that role: completed.`,
'REV-004': `rejected verdict + outcome=pass refused k3_reviewer_verdict_missing (23514), +0 successors; CONTROL approved: completed, +1. GAP: 3g fires only on outcome=pass at the 28 of 257 steps naming a reviewer; on the other 229 a rejection stops nothing.`,
'REV-005': `editing evidence_refs on sealed verdict trace 1996143 was refused 23514 by z10_phase_c_trace_append_only and the original rejected verdict is still on the row (1 of 1). CONTROL, setting superseded_by alone on that row: permitted.`,
'STATE-002': `completing W10-S08 with earlier mandatory steps never executed refused k3_closure_blocked (23514), 3 blocker classes incl. mandatory_steps_never_executed, closed_at null. CONTROL, every earlier step completed: run completed, closed_at set.`,
'STATE-003o': `driven instead: W10-S05 is non-closure, fn_kernel_step_successor returned same_owner and completing it opened 1 successor step run(s). CONTROL W10-S08 returned closure and opened 0. The catalogued injection itself was NOT staged.`,
'STATE-003b': `the injection is a step whose is_closure_step disagrees with next_step_if_pass: 0 of 257 today, and creating one means UPDATEing frozen phase_b_workflow_step, which z90_phase_b_freeze refuses. REFUSED would be a zero-population pass.`,
'TRACE-003': `trace 1996641 written open, then status=sealed with sealed_at left null: refused 23514 by CHECK phase_c_trace_sealed_ck, row unchanged. CONTROL, the same UPDATE carrying sealed_at=now(): accepted.`,
'TRACE-004': `(a) live fn_kernel_step_complete: idempotency claim at char 12594, lost-race replay return 13336, first trace write 15637; a lost race returns before any trace exists. (b) deferred guards forced: a correct pair silent, task 205836 on a deleted trace 23503.`,
};
for (const [k, v] of Object.entries(s)) console.log(String(v.length).padStart(4), k);
