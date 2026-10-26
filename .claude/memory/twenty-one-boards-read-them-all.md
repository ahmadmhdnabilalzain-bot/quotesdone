---
name: twenty-one-boards-read-them-all
description: "The estate has 21 state boards discoverable by signature; fn_kernel_all_boards() reads every one, and before 18 Aug 2026 six of seven kernel boards were read by no test and no CI job."
metadata: 
  node_type: memory
  type: project
  originSessionId: a0718a3f-8c12-4c09-9a8e-d518ddb85dd8
  modified: 2026-08-18T06:37:05.512Z
---

Every state board in this estate is a **zero-argument function returning
`(check_name, expected, actual, ok)`**. That signature is the discovery mechanism — 21 exist as of
18 Aug 2026, and `public.fn_kernel_all_boards()` calls all of them and returns
`(board, check_name, expected, actual, ok)`. ~301 checks total.

Before that function existed, **six of the seven kernel boards were read by no test and no CI job**.
Two were red on production while `npm test` passed 288 tests and `PHASE_C_BUILDER_CLOSURE.md`
reported "headlines FAILED 0". A board nobody opens is a comment.

`scripts/checks/kernel_boards_are_green.test.mjs` is the gate. Default is **fail on any red**; a
board only escapes that by being named in `scripts/checks/kernel-boards.json`, which **ratchets** it:
the disclosed numerator may stand and may not grow. Five of the six current reds are
`fn_kernel_trace_integrity`, which `kernel_k6_trace_ledger.sql` deliberately leaves as an open-gap
report ("the gap stays visible" — every numerator and denominator over the full table, no
population filter). Demanding zero there would be demanding the disclosure be deleted.

**How to apply:** when you want to know whether the estate is healthy, run
`select * from public.fn_kernel_all_boards() where not ok` — one query, not seven. When you add a
board, do nothing: it is watched from the moment it deploys. When a board goes red, the choice is
fix it or disclose it in `kernel-boards.json` with an owner and a reason — never delete the check.

A board that raises rather than returning rows is reported as `BOARD_RAISED` and counts as red;
`fn_phase_c_invariants` once raised 22007 on every call after a column retype and took
`fn_phase_c_baseline_drift` down with it.

Watch out: a function that returns this signature will **discover itself**. `fn_kernel_all_boards`
did, and recursed to the statement timeout on its first call.

Related: [[instruments-report-on-the-wrong-subject]], [[connected-is-a-claim-not-a-measurement]],
[[expectation-typed-into-its-own-check]].
