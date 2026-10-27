---
name: no-job-or-task-without-an-agent
description: Founder's rule, 7 Sep 2026 — nothing scheduled or queued may exist without an owning agent; the estate is one job and zero tasks
metadata:
  type: feedback
---

*"the rule is simple, no job/task should exist if it doesnt belong to an agent."* — founder,
7 September 2026.

**Why it exists:** the estate had reached **235 scheduled jobs and 2,489 tasks** while the
organisation drifted to seats that no longer existed. Jobs ran for dissolved departments; tasks sat
in queues nobody held. Neither number showed up as a problem because neither had an owner to notice
it. 95 of those jobs were created across ~60 build sessions in one month — each build adding one,
nothing ever removing one — and 96 were already switched off but never deleted.

**How to apply, before anything is scheduled or queued:**
1. Name the agent it belongs to. The rule is **an agent that actually EXISTS**, not "the two agents"
   — he said on 7 Sep *"well we will add more agents for sure. but till those are added, the rule
   remains"*. Read the live seats rather than a remembered list:
   `select role_id from public.org_role where status = 'active';`
2. If neither fits, it does not get created. Say so and stop. Do not invent a seat to receive it and
   do not leave it unowned "for now" — unowned is how 235 happened.
3. An agent that is deleted takes its jobs and tasks with it. They do not outlive their owner.

**The baseline as of 7 Sep 2026 (it will grow as he adds seats):** one job, `wa_flush`, owned by `customer_support`, held
inactive. Zero tasks. Anything that makes either number grow needs a named owner, and a task also
needs his confirmation — see [[the-org-is-two-agents-and-no-departments]] and
[[quotesdone-work-is-assigned]].
