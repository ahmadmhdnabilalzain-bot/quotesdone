---
name: the-phase-d-dispatch-fires-at-step-open
description: "Phase D's handler is attempted when the kernel OPENS a step, not when one is completed — so a refusal leaves the step for an actor and never stops the workflow."
metadata: 
  node_type: memory
  type: project
  originSessionId: f4baf9ca-e2a9-4d49-aa5b-18d5d5fefa11
  modified: 2026-08-20T22:33:12.245Z
---

Measured by reading every routine whose body names `fn_phase_d_dispatch_step`: only
`fn_kernel_workflow_start` and `fn_kernel_open_step`. **Not `fn_kernel_step_complete`.**

So the deterministic handler attempts a step at the moment the kernel opens it. If it refuses, the
kernel is unaffected and the step waits for an actor. Two consequences that decide how every Phase D
number must be read:

- **"N of 30 workflows close" was never a Phase D claim.** It measured how far a harness could push
  the KERNEL. The Phase D number is `phase_d_dispatch.outcome = 'EXECUTED'` — how many step-openings
  the handler completed unaided.
- Both numbers belong in the deliverable, named for what they measure. Driven through the kernel
  doors 2026-08-20: 257 of 257 step-openings dispatched, **3 EXECUTED**, 30 of 30 runs reaching
  `completed` when an actor drives them, **0 of 30** closed by the handler unaided.

**Why:** for weeks the estate quoted a closure figure produced by `fn_phase_d_drive_workflow`, which
called `fn_phase_d_handler_execute` DIRECTLY — an entry point that accepts `context`,
`gate_evidence`, `business_key`, `owner_ref` and `effect_payload` from its caller. The kernel
dispatch accepts NONE of those and resolves them itself, so routing through
`fn_kernel_step_complete` structurally removes a harness's ability to feed the rules anything. See
[[harness-seeds-an-order-reality-cannot-produce]].

**How to apply:** when a Phase D number looks good, ask which door produced it. If a routine can be
handed a context, the number it produces is about the harness.
