---
name: quotesdone-work-is-assigned
description: ALWAYS APPLY on the QuotesDone repository. There are exactly two agents — ceo and customer_support — and no departments. Every change names the agent accountable for it before the work starts. No task exists unless the founder confirmed it. Load this with quotesdone-session at the start of every session.
---

# Two agents, no departments, no unconfirmed tasks

Founder rulings, 7 September 2026, in his words:

> *"you need to mention the agent with the department you assigned the task for. you cant just
> randomly program stuff here and there"*
>
> *"for now remove all tasks from all agents except the CEO and the agent who is handling the
> whatsapp"* — *"literally everyone else should have nothing. cause clearly its a mess"*
>
> *"actually remove the whole organization chart that you made cause its trash"* —
> *"we are gonna build stuff one by one"*
>
> *"so no departments from now."* — *"no tasks excepts what i confirm"*
>
> *"and rename lifecycle channel operation into customer support"* — *"not archive. remove totally"*

---

## 1. The organisation, in full

| agent | what it is |
|---|---|
| `ceo` | Chief Executive (AI). Owns the direction and every decision that is not the founder's. |
| `customer_support` | Customer Support. Answers WhatsApp — the deterministic route, the fact pack, the conversation memory, documents that arrive on the channel. |

That is the whole company. **There are no departments.** `org_departments` and `os_department` are
empty and `primary_department_id` is null on both roles. Do not write a department into anything, do
not reintroduce `dept_key` as a required field, and do not describe work as belonging to one.

**Never invent a third agent.** If work does not fit `ceo` or `customer_support`, that is the
finding — say so and stop. It does not license creating a role to receive it. The founder is
building this back one piece at a time and each piece is his to add.

## 2. Every change names its agent

Before you touch anything, say which of the two owns the outcome, in this shape, and keep using it:

> **Assigned: `customer_support`** — the WhatsApp deterministic route.

The name goes in the commit message too, near the top:

```
Assigned: customer_support
```

No department line. If a change genuinely spans both seats, name both and say what each owns.

## 3. No task exists unless he confirmed it

`org_tasks` is empty and stays empty. **Do not create a task, an objective, a goal, a queue item or
a work item for either agent unless the founder has confirmed that specific piece of work.**

This is not the same as asking permission to do engineering — `quotesdone-session` §3 still stands
and technical calls are still yours. The rule is about *recorded work items* accumulating again:
2,489 of them existed and none had been confirmed by anyone. Build the thing he asked for; do not
open a ticket for the six adjacent things you noticed. Note them in your reply instead.

## 4. What was removed, so nobody rebuilds it by reflex

Removed **totally** on 7 Sep 2026 — not archived; he was explicit about that:

- 179 of 181 roles, 94 of 96 agents, every role alias, every agent alias
- all 33 `org_departments` and all 14 `os_department` rows, department budgets and objectives
- the whole chart: workflow ownership, workflow steps, committees, reporting authority lines
- all 2,489 `org_tasks`
- every certification, exam result, training attempt and remediation row for the dropped agents

`phase_c_system_execution` keeps its 61,721 rows. It is a log of who acted at the time, its foreign
key to `org_agents` was dropped rather than its history rewritten, and a record of the past is not an
organisation chart.

## 5. The remit sets the scope

Once you have named the agent, the shape of the fix follows from what that seat is for.
`customer_support` owns what happens on WhatsApp end to end — the answer, the memory, the document
that arrives, the escalation to the founder. `ceo` owns everything about direction and every call
the founder has not reserved. If the fix you are about to make sits outside the seat you named, you
named the wrong seat.
