# Phase C — Command Center read paths (gate 14)

All calls below are real authenticated HTTPS requests to `os_api` as `management@quotesdone.com`.

| # | Requirement | Result | Evidence |
|---|---|---|---|
| 1 | Command visible | **PASS** | `founder_command_status` HTTP 200 returns `raw_text` verbatim, `intent CMD-W20`, `status tasks_created`, `owner chief_of_staff`, `due_at`, and all four tasks. `founder_command_inbox` HTTP 200 lists command 222 with `plan`, `said`, `owners`, `tasks_open: 4` |
| 2 | Task progress visible | **PASS** | `founder_command_thread` HTTP 200 returns 21 fields including `tasks[]` (owner, owner_name, manager, department, state, due_at, blocker, blocker_owner, objective, acceptance, closure), `history`, `progress`, `completion`, `traces`, `overlays_invoked` |
| 3 | Blocker update possible | **PASS** | the thread carries `blocker` and `blocker_owner` per task; `phase_c_task` has `blocked` in its state model with `in_progress -> blocked` and `blocked -> in_progress` both legal, and the command state model carries `partially_blocked` reachable from `in_progress` and returning to `in_progress` or `completed` |
| 4 | Completion can return to founder thread | **PASS** | `completion` and `progress` are first-class fields of `founder_command_thread`; the command state model allows `in_progress -> completed` and `partially_blocked -> completed` |
| 5 | Refund inbox is separate | **PASS** | `founder_command_inbox` returns `counts.awaiting_founder` and `counts.non_refund_awaiting_founder` as distinct figures (both 0). Refund approvals live in `public.founder_approval_request`, a different table, reached by a different surface, and constrained to `action_class = 'refund_decision'` |
| 6 | No general approval inbox exists | **PASS** | `founder_approval_request` = 0 rows and cannot hold a non-refund class (CHECK + trigger, see `PHASE_C_REFUND_ONLY_APPROVAL_RESULT.md`). `counts.non_refund_awaiting_founder = 0` is enforced structurally, not by convention |
| 7 | Every command-centre action is reachable from the founder's own client | **PASS** | `founder_command`, `founder_command_control`, `founder_command_status`, `founder_command_inbox`, `founder_command_thread` all appear in `src/lib/osClient.ts` / `src/components/osx/OsxShell.tsx`, are classified in both gates (`ACTION_CLASS` in `os_api` and `public.control_mode_action`), and answered HTTP 200 in this audit |

## GATE 14 FAILS — a clarification cannot be closed

`founder_command_control(command_id: 223, op: 'cancel')` returned **HTTP 409**:

```json
{"ok": false, "from": "clarification_required", "to": "cancelled",
 "error": "transition_not_permitted",
 "message": "A command in 'clarification_required' cannot be cancelled; the state model does not allow it."}
```

`public.phase_c_command_transition` confirms it. Of the eight states, `clarification_required` is the only one
with no terminal exit at all:

| from_state | permitted to_state |
|---|---|
| received | cancelled, failed, interpreting, superseded |
| interpreting | accepted, clarification_required, failed, refused |
| **clarification_required** | **interpreting** — and nothing else |
| accepted | cancelled, routed, superseded |
| routed | cancelled, failed, tasks_created |
| tasks_created | cancelled, in_progress, superseded |
| in_progress | blocked→partially_blocked, cancelled, completed, failed |
| partially_blocked | completed, in_progress |

`fn_founder_command_control` implements exactly four operations — `cancel`, `reprioritize`, `supersede`,
`explain` (`scripts/sql/phase_c_04_command_center.sql:532–576`). **None of them drives
`clarification_required -> interpreting`.** There is no `answer` or `clarify` operation, and `cancel` and
`supersede` are both refused from that state.

Consequence, measured: command 223 ("Make marketing better.") is now permanently open in the founder's inbox.
`founder_command_inbox` counts it in `open_commands`. This audit created it under instruction and **could not
remove it** through any surface the founder has. Every future ambiguous command adds another.

The refusal itself is correct — the guard is doing its job. The defect is that the state model has no legal
route out and the API exposes no operation that would take it.

**GATE 14: FAIL** on requirement 3's sibling case — the founder can update a blocker but cannot dispose of a
clarification. Requirements 1, 2, 4, 5, 6, 7 pass.

## Also observed — the founder-gated control is currently satisfied by an open door

Not one of the enumerated requirements, but it belongs in this file because it is what stands between a stolen
session and the command channel.

`public.fn_os_open_access()` returns **true**. With it true, `os_api` accepts a request carrying no usable
identity, names the caller `build-mode@quotesdone.local`, and proceeds. That identity is an **active row in
`public.phase_c_founder_identity`** (`kind = 'build_mode'`, added 2026-08-15, note: *"Delete this row when
credentials are activated."*).

So the control that `founder_gated` relies on — the founder-identity allow-list, which is what exempts these
actions from Control Mode — is presently satisfiable without authenticating. Evidence that this is not
theoretical: `founder_command_message` row 256 (2026-08-16 03:52) and row 217 both carry
`founder_identity = 'build-mode@quotesdone.local'`. Real founder commands have already been recorded under the
open door.

Mitigating facts, stated for completeness: `app_secrets.os_bypass_key` does not exist, so the static-key
preview bypass cannot be used at all; and this audit's own canary authenticated properly and was recorded as
`management@quotesdone.com`.
