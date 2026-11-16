> **Archived 16 Nov 2026** (simplification wave B, it_engineer): it describes the department-agent organisation (org roles, handoffs, overlays) removed on 7-8 Sep 2026. 8 of the 9 routines it names are gone from production (SELECT pg_proc, 16 Nov 2026). History, not the build today.

# Cross-department handoff report

Measured 14 Aug 2026 · blueprint `runtime_blueprint/CROSS_DEPARTMENT_HANDOFFS.csv`,
`schemas/handoff.schema.json`.

## Status: `EXISTING_PARTIAL_REPAIR` — the contract reached production today and has no traffic

`handoff_contract` and its guard trigger `a00_handoff_contract_guard` did not exist on production
until today; they arrived with `v3_repair_07_handoff_contract`. Both projects now carry:

| routine | purpose |
|---|---|
| `fn_handoff_open(p jsonb)` | open a handoff with evidence and criteria |
| `fn_handoff_criteria(p jsonb)` | validate acceptance/closure criteria |
| `fn_handoff_respond(id, agent, decision, reason)` | receiving side accepts or refuses |
| `fn_handoff_amend(id, agent, patch)` | amend without losing ownership |
| `fn_handoff_close(id, agent, closure_evidence)` | close against the stated criteria |
| `fn_handoff_stalled(dept, limit)` | find handoffs that have lost their owner |
| `fn_handoff_notify(agent, content, source)` | tell the receiver |
| `trg_handoff_contract_guard` | refuses a handoff missing its contract fields |

`fn_agent_handoff_inbox` and `fn_handoff_answer` both now resolve the agent identity before matching,
so a handoff addressed to an employee under an alias reaches them. Before today,
`fn_handoff_answer` compared `p_agent_key` raw against `agent_actions.agent`, and 415 rows in that
table are filed under aliases.

## Measured

| | staging | production |
|---|---|---|
| `handoff_contract` rows | 0 | 0 |
| routines present | 8/8 | 8/8 |
| guard trigger present | yes | yes |

**Zero handoffs exist on either project.** The blueprint's requirement — "a handoff must contain
evidence, receiving owner, acceptance criteria, closure criteria, deadline and return state; one
accountable owner remains until closure" — is *enforceable* (the guard refuses a handoff without
them) but is **not demonstrated**, because nothing has opened one.

I am not going to seed one to make this table non-empty. A fabricated handoff would prove that
`INSERT` works, which was never in doubt, and would put a row in a business table that no
department asked for.

## What would demonstrate it

The cheapest honest demonstration is an aborted-transaction probe: open a handoff, respond, close it,
assert ownership never transferred and closure required the stated evidence, then `raise` so the
transaction rolls back and the counts still come out. That is the pattern the behavioural suite uses
throughout and it costs nothing. It is the next item here and is **not done**.

## Open

- `CROSS_DEPARTMENT_HANDOFFS.csv` in the package names the specific department pairs and their
  acceptance criteria. None of those rows has been loaded into `handoff_contract` as a template, so
  the runtime has the mechanism and not the map. `MISSING_BUILD`.
- Ownership-until-closure is enforced by the guard on write. Whether it survives an *amend* is
  untested.
