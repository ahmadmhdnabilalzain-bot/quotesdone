---
name: a-condition-that-cannot-not-fire
description: "The mirror of the guarded-by-an-impossible-condition lens — a rule whose match is a tautology, so it fires on every instance of a shape and never on what it was written for."
metadata: 
  node_type: memory
  type: project
  originSessionId: 5cddcd24-7d49-4fa9-84c5-f33b74a74e52
  modified: 2026-08-13T05:45:44.223Z
---

`fn_should_escalate` carries a rule whose comment states its purpose plainly: *"A FAILED STRATEGY IS
NOT REPEATED UNKNOWINGLY."* Measured on production 13 Aug 2026, of the 51 actions frozen in
`needs_review` it had held **32 handoffs and zero strategies**.

It matched an action's text against `institutional_memory` headlines graded `worse`, on ≥3 shared
tokens of ≥6 characters:

```
action  "Handoff — Bundled scheduled_run failure cluster: day_conductor suspected root cause"
memory  "knowledge: test.failed on scheduled_run day_conductor"
shared  day_conductor, failed, scheduled_run
```

The action **is the report of that failure**. A handoff naming a failure will *always* share
vocabulary with the memory of that failure. The gate held the remediation because the thing being
remediated was remembered.

**Why:** [[guarded-by-a-condition-that-cannot-occur]] asks whether a recovery path has ever actually
run. This is its mirror and it is just as productive: **is there a class of input on which this
condition cannot fail to fire?** A text-similarity rule aimed at "is this the same attempt" will
always also match "is this about the same subject", and reports are always about their subject.

**How to apply:** when a queue is full of one shape, do not accept "it is a security decision" —
join the rows to the reason and count by kind. If one kind is 100% held and the kind the rule names
is 0% held, the rule is matching a tautology. Two fixes, both small: pass the discriminating field
(`trg_action_gate` derived `moves_money` FROM `kind` and then dropped `kind`, so the rule could not
tell a strategy from a handoff — the same defect its own `actor` comment describes), and scope the
rule by an **exclusion** list so a new kind is held by default, never an allow-list
([[a-list-with-no-third-answer]]).

Also measured, and the reason the fix is safe: `action_worker:it` has completed **39** handoffs, so
the released rows rejoin a path that works. `zzz_action_gate` is `BEFORE INSERT` only — a bulk
`UPDATE … SET status='pending'` does **not** re-run the gate, it overrides it.
