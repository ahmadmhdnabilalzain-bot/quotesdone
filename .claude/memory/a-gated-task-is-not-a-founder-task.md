---
name: a-gated-task-is-not-a-founder-task
description: "needs_founder derived from \"the tier is not autonomous\" made every gated task try to page the founder and the refund-only guard refused it; the writer must read the same table the guard reads (phase_c_action_class.founder_approval_required)"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-04T09:24:11.153Z
---

`fn_event_dispatch` wrote `needs_founder := v_tier <> 'autonomous'`. That reads "this department is
not autonomous for this action class" as "the founder must decide this". The company's rule is the
opposite: only an action class marked `founder_approval_required` reaches him (today the refund
class alone), and `fn_kernel_founder_routing_is_refund_only` enforces it. A merely gated task goes
up the INTERNAL chain — the same row was already being written `'proposed'` for exactly that, so the
two halves of one INSERT disagreed with each other.

It stayed invisible while every department granted `analysis` autonomously. The STAFF_ORG seating
gave Supply its own head on 4 Sep 2026; Supply grants `analysis` at `gated`; from that moment every
event routed to a Supply subscriber raised 23514. **Fourteen failed kernel traces for
`cron:event_dispatch_15min` between 05:45 and 09:00 UTC while `cron.job_run_details` kept reporting
`succeeded`** — the kernel wrapper swallows the routine's failure, so the scheduler's own log is not
a failure signal for a wrapped job. Only the red-view alerter, built that morning, said so.

**How to apply:** when a writer sets a flag that a guard also tests, have the writer read the guard's
source of truth rather than deriving the flag from something adjacent
([[two-gates-one-vocabulary-nothing-keeps-them-in-step]]). And when checking whether a wrapped cron
is healthy, read `phase_c_system_execution.result`, never `cron.job_run_details.status`
([[connected-is-a-claim-not-a-measurement]]).
